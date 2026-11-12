package savedata_example

// Phase 3 of the roadmap in one program:
//
//   - a save file that survives closing the app (launch count and a score)
//   - SceAppUtil: init, a save-data slot, system parameters (language, which
//     button means "enter", user name)
//   - ScePower: battery and clock speeds
//   - an image and a font loaded from files packed in the VPK (app0:/assets)
//   - a real LiveArea icon and pictures (the sce_sys folder next to this file)
//
//   Cross     score + 1, then save
//   Square    delete the save file
//   Triangle  switch the CPU clock between 333 and 444 MHz
//   Start     exit
//
// To check it: press Cross a few times, close the app, start it again. The
// launch count goes up by one and the score is still there.

import "core:fmt"
import "core:log"

import sce  "../../lib/sce"
import v2d  "../../lib/vita2d"
import vito "../../lib/vito"

WHITE  :: u32(0xFFFFFFFF)
GREEN  :: u32(0xFF40E040)
RED    :: u32(0xFF4040FF)
YELLOW :: u32(0xFF00DCFF)
CYAN   :: u32(0xFFE0D030)
GREY   :: u32(0xFF909090)

TITLE_ID :: "ODIN00008" // must match build.bat

// ---------------------------------------------------------------
// The save file
// ---------------------------------------------------------------
SAVE_MAGIC   :: u32(0x4F544956) // "VITO"
SAVE_VERSION :: u32(1)

Save :: struct {
    magic:    u32,
    version:  u32,
    launches: u32,
    score:    u32,
    saved_at: sce.DateTime, // local time of the last save
}

// Where saves go. savedata0: is the app's own save-data area (the system
// encrypts it and shows it under Settings > Application Data). If it cannot be
// written, the example falls back to a plain folder on the memory card.
SAVE_DIRS := [?]cstring{
    "savedata0:",
    "ux0:data/" + TITLE_ID,
}
SAVE_NAME :: "save.bin"

save_dir:    cstring // the directory that worked, or nil
save_status: string  // what the last load / save did, for the screen

save_path :: proc(dir: cstring) -> cstring {
    return fmt.ctprintf("%s/%s", dir, SAVE_NAME)
}

load_save :: proc() -> (s: Save, ok: bool) {
    for dir in SAVE_DIRS {
        fd := sce.sceIoOpen(save_path(dir), sce.O_RDONLY, 0)
        if fd < 0 do continue
        n := sce.sceIoRead(fd, &s, size_of(Save))
        sce.sceIoClose(fd)
        if n == size_of(Save) && s.magic == SAVE_MAGIC && s.version == SAVE_VERSION {
            save_dir = dir
            return s, true
        }
        log.warnf("%s: found a file but it is not a valid save (read %d bytes)", dir, n)
    }
    return {}, false
}

write_save :: proc(s: ^Save) -> bool {
    sce.sceRtcGetCurrentClockLocalTime(&s.saved_at)
    s.magic, s.version = SAVE_MAGIC, SAVE_VERSION

    dirs := SAVE_DIRS
    for dir in dirs {
        if save_dir != nil && dir != save_dir do continue
        // Harmless if the folder exists already (and for savedata0: itself).
        sce.sceIoMkdir(dir, 0o777)
        fd := sce.sceIoOpen(save_path(dir), sce.O_WRONLY | sce.O_CREAT | sce.O_TRUNC, 0o777)
        if fd < 0 {
            log.warnf("cannot open %s for writing: 0x%08X", save_path(dir), u32(fd))
            continue
        }
        n := sce.sceIoWrite(fd, s, size_of(Save))
        sce.sceIoClose(fd)
        if n == size_of(Save) {
            save_dir = dir
            return true
        }
        log.warnf("short write to %s: %d", save_path(dir), n)
    }
    return false
}

delete_save :: proc() {
    for dir in SAVE_DIRS do sce.sceIoRemove(save_path(dir))
    save_dir = nil
}

// ---------------------------------------------------------------
// SceAppUtil: save-data slot and system parameters
// ---------------------------------------------------------------
// Slot text is UTF-16. This only handles ASCII, which is all the example uses.
to_utf16 :: proc "contextless" (dst: []u16, s: string) {
    n := min(len(s), len(dst) - 1)
    for i in 0 ..< n do dst[i] = u16(s[i])
    dst[n] = 0
}

from_utf16 :: proc(src: []u16) -> string {
    buf := make([]u8, len(src), context.temp_allocator)
    n := 0
    for c in src {
        if c == 0 do break
        buf[n] = u8(c) if c < 128 else '?'
        n += 1
    }
    return string(buf[:n])
}

SLOT_ID :: 0

slot_result: i32 // result of the last slot call
slot_info:   sce.AppUtilSaveDataSlotParam
slot_ok:     bool

// A slot is the entry the system shows for a save (title, subtitle, time).
// It is separate from the file itself.
update_slot :: proc(s: Save) {
    param: sce.AppUtilSaveDataSlotParam
    to_utf16(param.title[:], "Odin save data example")
    to_utf16(param.subTitle[:], fmt.tprintf("Score %d, %d launches", s.score, s.launches))
    to_utf16(param.detail[:], "Written by Examples/SaveData-Example")

    slot_result = sce.sceAppUtilSaveDataSlotCreate(SLOT_ID, &param, nil)
    if slot_result == sce.APPUTIL_ERROR_SAVEDATA_SLOT_EXISTS {
        slot_result = sce.sceAppUtilSaveDataSlotSetParam(SLOT_ID, &param, nil)
    }
    read_back: sce.AppUtilSaveDataSlotParam
    got := sce.sceAppUtilSaveDataSlotGetParam(SLOT_ID, &read_back, nil)
    slot_ok = got >= 0
    if slot_ok do slot_info = read_back
    if slot_result < 0 do log.warnf("save-data slot: 0x%08X (get: 0x%08X)", u32(slot_result), u32(got))
}

System_Info :: struct {
    lang:         i32,
    enter_button: i32,
    date_format:  i32,
    time_format:  i32,
    username:     [sce.SYSTEM_PARAM_USERNAME_MAXSIZE]u8,
    results:      [5]i32,
}

read_system_info :: proc() -> (info: System_Info) {
    info.results[0] = sce.sceAppUtilSystemParamGetInt(sce.SYSTEM_PARAM_ID_LANG, &info.lang)
    info.results[1] = sce.sceAppUtilSystemParamGetInt(sce.SYSTEM_PARAM_ID_ENTER_BUTTON, &info.enter_button)
    info.results[2] = sce.sceAppUtilSystemParamGetInt(sce.SYSTEM_PARAM_ID_DATE_FORMAT, &info.date_format)
    info.results[3] = sce.sceAppUtilSystemParamGetInt(sce.SYSTEM_PARAM_ID_TIME_FORMAT, &info.time_format)
    info.results[4] = sce.sceAppUtilSystemParamGetString(sce.SYSTEM_PARAM_ID_USERNAME, raw_data(info.username[:]), len(info.username))
    return
}

// ---------------------------------------------------------------
@(export, link_name = "odin_main")
game_main :: proc "c" (argc: i32, argv: [^]cstring) -> i32 {
    context = vito.init()

    sce.sceCtrlSetSamplingMode(.ANALOG)

    // SceAppUtil must be initialised before savedata0: and the system
    // parameters are used. Both structs must be zeroed.
    init_param: sce.AppUtilInitParam
    boot_param: sce.AppUtilBootParam
    apputil := sce.sceAppUtilInit(&init_param, &boot_param)
    log.infof("sceAppUtilInit: 0x%08X", u32(apputil))

    if v2d.Init() < 0 {
        vito.println("vita2d: Init failed")
        return sce.sceKernelExitProcess(1)
    }
    v2d.SetClearColor(v2d.RGBA8(0x10, 0x12, 0x20, 0xFF))

    // Assets packed in the VPK by build.bat (the assets folder).
    image := v2d.LoadPNGFile("app0:/assets/test.png")
    font  := v2d.LoadFontFile("app0:/assets/font.ttf") // optional: put any .ttf there
    log.infof("app0:/assets/test.png: %p   app0:/assets/font.ttf: %p", image, font)

    save, had_save := load_save()
    save.launches += 1
    save_status = "loaded the save from the last run" if had_save else "no save found, starting fresh"
    if !write_save(&save) do save_status = "COULD NOT WRITE THE SAVE"
    update_slot(save)
    system := read_system_info()

    pad, old_pad: sce.CtrlData
    fast_clock := false

    for {
        old_pad = pad
        sce.sceCtrlPeekBufferPositive(0, &pad, 1)
        pressed := pad.buttons & ~old_pad.buttons
        if pressed & sce.CTRL_START != 0 do break

        if pressed & sce.CTRL_CROSS != 0 {
            save.score += 1
            if write_save(&save) {
                save_status = "saved"
                update_slot(save)
            } else {
                save_status = "COULD NOT WRITE THE SAVE"
            }
        }
        if pressed & sce.CTRL_SQUARE != 0 {
            delete_save()
            save = {}
            save_status = "save deleted (Cross writes a new one)"
        }
        if pressed & sce.CTRL_TRIANGLE != 0 {
            fast_clock = !fast_clock
            sce.scePowerSetArmClockFrequency(444 if fast_clock else 333)
        }

        v2d.StartDrawing()
        v2d.ClearScreen()

        v2d.DrawText(24, 40, WHITE, 1.3, "Save data example")
        v2d.DrawText(24, 66, GREY, 0.8, "Save file, SceAppUtil, ScePower, assets and LiveArea from the VPK")

        // --- save file
        y := i32(108)
        v2d.DrawText(24, y, CYAN, 1.0, "Save file")
        y += 28
        v2d.DrawText(24, y, WHITE, 0.9, fmt.ctprintf("launches %d    score %d", save.launches, save.score))
        y += 24
        v2d.DrawText(24, y, GREEN if save_dir != nil else RED, 0.8,
            fmt.ctprintf("%s   (%s)", save_status, save_path(save_dir) if save_dir != nil else cstring("no writable location")))
        y += 22
        t := save.saved_at
        v2d.DrawText(24, y, GREY, 0.8, fmt.ctprintf("last saved %04d-%02d-%02d %02d:%02d:%02d", t.year, t.month, t.day, t.hour, t.minute, t.second))

        // --- slot
        y += 36
        v2d.DrawText(24, y, CYAN, 1.0, "Save-data slot (SceAppUtil)")
        y += 26
        if slot_ok {
            v2d.DrawText(24, y, GREEN, 0.8, fmt.ctprintf("\"%s\" / \"%s\"   %d KB", from_utf16(slot_info.title[:]), from_utf16(slot_info.subTitle[:]), slot_info.sizeKB))
        } else {
            v2d.DrawText(24, y, RED, 0.8, fmt.ctprintf("slot call failed: 0x%08X   (sceAppUtilInit: 0x%08X)", u32(slot_result), u32(apputil)))
        }

        // --- system parameters
        y += 36
        v2d.DrawText(24, y, CYAN, 1.0, "System parameters")
        y += 26
        enter: cstring = "Circle" if system.enter_button == i32(sce.SystemParamEnterButtonAssign.CIRCLE) else "Cross"
        v2d.DrawText(24, y, WHITE if system.results[0] >= 0 else RED, 0.8,
            fmt.ctprintf("language %d   enter button: %s   date format %d   time format %d   user \"%s\"",
                system.lang, enter, system.date_format, system.time_format, cstring(raw_data(system.username[:]))))

        // --- power
        y += 36
        v2d.DrawText(24, y, CYAN, 1.0, "Power")
        y += 26
        v2d.DrawText(24, y, WHITE, 0.8, fmt.ctprintf("battery %d%%%s   CPU %d MHz   bus %d MHz   GPU %d MHz",
            sce.scePowerGetBatteryLifePercent(),
            cstring("  charging") if sce.scePowerIsBatteryCharging() != 0 else cstring(""),
            sce.scePowerGetArmClockFrequency(), sce.scePowerGetBusClockFrequency(), sce.scePowerGetGpuClockFrequency()))

        // --- assets from the VPK
        if image != nil {
            v2d.DrawTextureScale(image, 800, 96, 2, 2)
            v2d.DrawText(772, 250, GREEN, 0.7, "app0:/assets/test.png")
        } else {
            v2d.DrawText(700, 120, RED, 0.8, "test.png did not load")
        }
        if font != nil {
            v2d.FontDrawText(font, 24, 476, YELLOW, 22, "This line uses app0:/assets/font.ttf")
        } else {
            v2d.DrawText(24, 470, GREY, 0.8, "(no app0:/assets/font.ttf in this build: copy any .ttf to assets\\font.ttf)")
        }

        v2d.DrawText(24, 522, GREY, 0.8, "Cross: score+1 and save   Square: delete save   Triangle: CPU 333/444 MHz   Start: exit")

        v2d.EndDrawing()
        v2d.SwapBuffers()
        free_all(context.temp_allocator)
    }

    v2d.WaitRenderingDone()
    if image != nil do v2d.FreeTexture(image)
    if font != nil  do v2d.FreeFont(font)
    v2d.FreeSizedFonts()
    sce.sceAppUtilShutdown()
    vito.shutdown()
    sce.sceKernelExitProcess(0)
    return 0
}
