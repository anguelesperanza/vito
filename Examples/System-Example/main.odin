package system_example

// The system's own UI and services, driven from one screen:
//
//   - message dialogs: OK, Yes / No, three custom buttons, an error code,
//     a progress bar the game fills and closes
//   - the on-screen keyboard (IME dialog), plain and as a password box
//   - power events through a callback (suspend, resume, PS button, charger),
//     SceAppMgr system events, and the "system UI is on top" flag
//   - optional system modules loaded with SceSysmodule
//   - a notification, the screenshot switch, the PS button lock
//   - launching another app (Settings) by URI
//
// The dialogs come from lib/vito/dialog.odin and the events from
// lib/vito/system.odin; the rest are direct calls into lib/sce.
//
// Hold Start + Select for a second to exit.

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
PANEL  :: u32(0xFF2A2420)

// --- event log ---------------------------------------------------------
LOG_LINES :: 9
Log_Line :: struct {
    time: f64,
    text: [96]u8,
    len:  int,
}
event_log:   [LOG_LINES]Log_Line
event_count: int

log_event :: proc(format: string, args: ..any) {
    line := &event_log[event_count % LOG_LINES]
    line.time = vito.time_seconds()
    line.len  = len(fmt.bprintf(line.text[:], format, ..args))
    event_count += 1
    log.info(string(line.text[:line.len]))
}

Power_Name :: struct {
    flag: u32,
    name: string,
}
POWER_NAMES := [?]Power_Name{
    {sce.POWER_CB_APP_SUSPEND,           "app suspend"},
    {sce.POWER_CB_APP_RESUMING,          "app resuming"},
    {sce.POWER_CB_APP_RESUME,            "app resume"},
    {sce.POWER_CB_SYSTEM_SUSPEND,        "system suspend"},
    {sce.POWER_CB_SYSTEM_RESUMING,       "system resuming"},
    {sce.POWER_CB_SYSTEM_RESUME,         "system resume"},
    {sce.POWER_CB_AFTER_SYSTEM_RESUME,   "after system resume"},
    {sce.POWER_CB_BATTERY_ONLINE,        "battery online"},
    {sce.POWER_CB_POWER_ONLINE,          "charger"},
    {sce.POWER_CB_LOW_BATTERY,           "low battery"},
    {sce.POWER_CB_BUTTON_PS_PRESS,       "PS press"},
    {sce.POWER_CB_BUTTON_PS_HOLD,        "PS hold"},
    {sce.POWER_CB_BUTTON_PS_START_PRESS, "PS+Start"},
    {sce.POWER_CB_BUTTON_PS_POWER_PRESS, "PS+Power"},
    {sce.POWER_CB_BUTTON_POWER_PRESS,    "Power press"},
    {sce.POWER_CB_BUTTON_POWER_HOLD,     "Power hold"},
}

log_power_events :: proc(flags: u32) {
    buf: [80]u8
    n := 0
    for p in POWER_NAMES {
        if flags & p.flag == 0 do continue
        n += len(fmt.bprintf(buf[n:], "%s%s", ", " if n > 0 else "", p.name))
    }
    log_event("power 0x%08X  %s", flags, string(buf[:n]))
}

// What the open dialog is for, so its result goes to the right line.
Pending :: enum {
    None,
    Ok,
    Yes_No,
    Three,
    Error_Code,
    Progress,
    Name,
    Password,
}

app_event: sce.AppUtilAppEventParam

@(export, link_name = "odin_main")
game_main :: proc "c" (argc: i32, argv: [^]cstring) -> i32 {
    context = vito.init()

    if v2d.Init() < 0 {
        vito.println("vita2d: Init failed")
        return sce.sceKernelExitProcess(1)
    }
    v2d.SetClearColor(v2d.RGBA8(0x10, 0x12, 0x20, 0xFF))

    vito.input_init({})
    dialogs_ok := vito.dialog_init()
    dialogs_error := vito.dialog_last_error
    power_ok := vito.power_events_start()

    // Optional system modules. A module's functions fail until it is loaded.
    load_ime    := sce.sceSysmoduleLoadModule(.IME)
    load_notify := sce.sceSysmoduleLoadModule(.NOTIFICATION_UTIL)
    load_shot   := sce.sceSysmoduleLoadModule(.SCREEN_SHOT)
    shell_init  := sce.sceShellUtilInitEvents(0)

    // The string the app was started with (empty when started from its bubble).
    app_param: [1024]u8
    app_param_result := sce.sceAppMgrGetAppParam(raw_data(app_param[:]))

    pending := Pending.None
    progress := 0
    last_result: [96]u8
    last_result_len := len(fmt.bprintf(last_result[:], "none yet"))
    name_buf: [192]u8
    name := ""
    password_length := -1

    ps_locked, shots_disabled := false, false
    lock_result, shot_result, notify_result, launch_result: i32
    have_lock, have_shot, have_notify, have_launch: bool
    notify_count := 0

    input: vito.Input
    timer: vito.Frame_Timer
    exit_hold := 0
    combo := false
    frames := 0
    longest_frame: f32

    for {
        dt := vito.frame_tick(&timer)
        if frames > 10 && dt > longest_frame do longest_frame = dt
        vito.input_update(&input)

        // ---- events from the system ------------------------------------
        if flags := vito.power_events_take(); flags != 0 do log_power_events(flags)
        if event, ok := vito.system_event_poll(); ok {
            log_event("AppMgr system event 0x%08X%s", event, "  (resume)" if event == sce.APPMGR_SYSTEMEVENT_ON_RESUME else "")
        }
        if sce.sceAppUtilReceiveAppEvent(&app_event) >= 0 && app_event.type != 0 {
            log_event("AppUtil app event %d", app_event.type)
        }
        overlaid := vito.system_ui_overlaid()

        // ---- the open dialog -------------------------------------------
        if pending == .Progress {
            progress += 1
            vito.progress_dialog_set(progress / 2)
            if progress == 100 do vito.progress_dialog_set_text("Half way...")
            if progress == 200 do vito.message_dialog_close()
        }
        if result, done := vito.message_dialog_poll(); done {
            last_result_len = len(fmt.bprintf(last_result[:], "%v: button %d%s", pending, result.button, "  canceled" if result.canceled else ""))
            log_event("dialog %v -> button %d canceled %v", pending, result.button, result.canceled)
            pending = .None
        }
        if pending == .Name {
            if text, accepted, done := vito.text_input_poll(name_buf[:]); done {
                if accepted do name = text
                last_result_len = len(fmt.bprintf(last_result[:], "keyboard: %s", "accepted" if accepted else "canceled"))
                pending = .None
            }
        } else if pending == .Password {
            secret: [192]u8
            if text, accepted, done := vito.text_input_poll(secret[:]); done {
                if accepted do password_length = len(text)
                last_result_len = len(fmt.bprintf(last_result[:], "password: %s", "accepted" if accepted else "canceled"))
                pending = .None
            }
        }

        // ---- the game's own input, ignored while a dialog is open -------
        if vito.held(input, vito.BUTTON_START) && vito.held(input, vito.BUTTON_SELECT) {
            combo = true
            exit_hold += 1
            if exit_hold > 60 && !vito.dialog_active() do break
        } else {
            exit_hold = 0
        }

        if !vito.dialog_active() {
            opened := true
            switch {
            case vito.pressed(input, vito.BUTTON_CROSS):
                pending = .Ok
                opened = vito.message_dialog_open("A message from Odin.\nThe game keeps drawing behind it.")
            case vito.pressed(input, vito.BUTTON_CIRCLE):
                pending = .Yes_No
                opened = vito.message_dialog_open("Do you like the Vita?", .Yes_No)
            case vito.pressed(input, vito.BUTTON_SQUARE):
                pending = .Three
                opened = vito.message_dialog_open("Pick one.", .Three, {"First", "Second", "Third"})
            case vito.pressed(input, vito.BUTTON_R):
                pending = .Error_Code
                opened = vito.error_dialog_open(sce.COMMON_DIALOG_ERROR_NOT_FINISHED)
            case vito.pressed(input, vito.BUTTON_L):
                pending = .Progress
                progress = 0
                opened = vito.progress_dialog_open("Pretending to work...")
            case vito.pressed(input, vito.BUTTON_TRIANGLE):
                pending = .Name
                opened = vito.text_input_open("Your name", name, 32)
            case vito.pressed(input, vito.BUTTON_UP):
                pending = .Password
                opened = vito.text_input_open("A password", "", 16, .Basic_Latin, {.Password, .No_Assistance})

            case vito.pressed(input, vito.BUTTON_LEFT):
                text: [sce.NOTIFICATIONUTIL_TEXT_MAX + 1]u16
                notify_count += 1
                vito.to_utf16(text[:], fmt.tprintf("Hello from Odin, number %d", notify_count))
                notify_result = sce.sceNotificationUtilSendNotification(raw_data(text[:]))
                have_notify = true
            case vito.pressed(input, vito.BUTTON_RIGHT):
                ps_locked = !ps_locked
                if ps_locked {
                    lock_result = sce.sceShellUtilLock(sce.SHELL_UTIL_LOCK_TYPE_PS_BTN)
                } else {
                    lock_result = sce.sceShellUtilUnlock(sce.SHELL_UTIL_LOCK_TYPE_PS_BTN)
                }
                have_lock = true
            case vito.pressed(input, vito.BUTTON_DOWN):
                shots_disabled = !shots_disabled
                shot_result = sce.sceScreenShotDisable() if shots_disabled else sce.sceScreenShotEnable()
                have_shot = true
            case vito.released(input, vito.BUTTON_START) && !combo:
                launch_result = sce.sceAppMgrLaunchAppByUri(0xFFFFF, "settings_dlg:")
                have_launch = true
                log_event("launch Settings -> 0x%08X", u32(launch_result))
            }
            if !opened {
                last_result_len = len(fmt.bprintf(last_result[:], "%v did not open: 0x%08X", pending, u32(vito.dialog_last_error)))
                pending = .None
            }
        }
        if !vito.held(input, vito.BUTTON_START) && !vito.held(input, vito.BUTTON_SELECT) do combo = false

        // ---- draw ------------------------------------------------------
        v2d.StartDrawing()
        v2d.ClearScreen()

        v2d.DrawText(24, 40, WHITE, 1.3, "System example")
        v2d.DrawText(24, 66, GREY, 0.8, "dialogs, keyboard, power events, system modules")
        // A moving bar: it must keep moving while a dialog is open.
        v2d.DrawRectangle(700 + f32(frames % 120) * 2, 30, 16, 16, YELLOW)

        y := i32(104)
        v2d.DrawText(24, y, CYAN, 1.0, "Dialogs")
        y += 26
        v2d.DrawText(24, y, WHITE, 0.75, "Cross  message      Circle  Yes / No      Square  three buttons"); y += 22
        v2d.DrawText(24, y, WHITE, 0.75, "L  progress bar     R  error code"); y += 22
        v2d.DrawText(24, y, WHITE, 0.75, "Triangle  keyboard      Up  password keyboard"); y += 26
        v2d.DrawText(24, y, GREEN if dialogs_ok else RED, 0.75, fmt.ctprintf("dialog_init 0x%X    open: %v", u32(dialogs_error), vito.dialog_open_kind())); y += 22
        v2d.DrawText(24, y, YELLOW, 0.8, fmt.ctprintf("last: %s", string(last_result[:last_result_len]))); y += 22
        v2d.DrawText(24, y, WHITE, 0.8, fmt.ctprintf("name: \"%s\"  (%d bytes)", name, len(name))); y += 22
        if password_length >= 0 {
            v2d.DrawText(24, y, WHITE, 0.8, fmt.ctprintf("password: %d characters", password_length))
        }
        y += 34

        v2d.DrawText(24, y, CYAN, 1.0, "Services")
        y += 26
        v2d.DrawText(24, y, WHITE, 0.75, "Left  notification    Right  PS button lock    Down  screenshots    Start  Settings"); y += 24
        result_line :: proc(y: i32, have: bool, result: i32, text: cstring) {
            color := GREY
            if have do color = GREEN if result >= 0 else RED
            v2d.DrawText(24, y, color, 0.75, text)
        }
        result_line(y, have_notify, notify_result, fmt.ctprintf("notifications sent %d   result 0x%X", notify_count, u32(notify_result))); y += 20
        result_line(y, have_lock, lock_result, fmt.ctprintf("PS button %s   result 0x%X", "LOCKED" if ps_locked else "free", u32(lock_result))); y += 20
        result_line(y, have_shot, shot_result, fmt.ctprintf("screenshots %s   result 0x%X", "DISABLED" if shots_disabled else "allowed", u32(shot_result))); y += 20
        result_line(y, have_launch, launch_result, fmt.ctprintf("launch Settings   result 0x%X", u32(launch_result))); y += 20
        modules_ok := load_ime >= 0 && load_notify >= 0 && load_shot >= 0 && shell_init >= 0
        v2d.DrawText(24, y, GREEN if modules_ok else RED, 0.75,
            fmt.ctprintf("modules: IME 0x%X  notify 0x%X  screenshot 0x%X  shell 0x%X", u32(load_ime), u32(load_notify), u32(load_shot), u32(shell_init))); y += 20
        v2d.DrawText(24, y, GREY, 0.75,
            fmt.ctprintf("loaded now: IME %d  NET %d    app param (0x%X): \"%s\"",
                i32(sce.sceSysmoduleIsLoaded(.IME) == sce.SYSMODULE_LOADED), i32(sce.sceSysmoduleIsLoaded(.NET) == sce.SYSMODULE_LOADED),
                u32(app_param_result), cstring(&app_param[0])))

        // --- right column: events
        EX :: 560
        v2d.DrawRectangle(EX - 12, 84, 960 - EX, 250, PANEL)
        v2d.DrawText(EX, 108, CYAN, 1.0, "System events")
        register := vito.power_events_register_result()
        v2d.DrawText(EX, 130, GREEN if power_ok && register >= 0 else RED, 0.7, fmt.ctprintf("power callback: register 0x%X", u32(register)))
        v2d.DrawText(EX, 150, YELLOW if overlaid else GREY, 0.7, fmt.ctprintf("system UI on top: %v", overlaid))
        ey := i32(176)
        first := max(0, event_count - LOG_LINES)
        for i in first ..< event_count {
            line := &event_log[i % LOG_LINES]
            v2d.DrawText(EX, ey, WHITE, 0.6, fmt.ctprintf("%6.1f  %s", line.time, string(line.text[:line.len])))
            ey += 17
        }
        if event_count == 0 {
            v2d.DrawText(EX, ey, GREY, 0.7, "none yet: press the PS button and come back")
        }

        v2d.DrawText(EX, 362, GREY, 0.7,
            fmt.ctprintf("battery %d%%  charging %d  plugged in %d", sce.scePowerGetBatteryLifePercent(),
                sce.scePowerIsBatteryCharging(), sce.scePowerIsPowerOnline()))
        v2d.DrawText(EX, 382, GREY, 0.7, fmt.ctprintf("frame %d   longest gap %.2f s", frames, longest_frame))

        v2d.DrawText(24, 522, YELLOW if exit_hold > 0 else GREY, 0.8, "Hold Start + Select to exit")

        v2d.EndDrawing()
        v2d.CommonDialogUpdate() // lets the open dialog draw over this frame
        v2d.SwapBuffers()
        free_all(context.temp_allocator)
        frames += 1
    }

    // Leave the console as it was.
    if ps_locked      do sce.sceShellUtilUnlock(sce.SHELL_UTIL_LOCK_TYPE_PS_BTN)
    if shots_disabled do sce.sceScreenShotEnable()

    v2d.WaitRenderingDone()
    v2d.FreeSizedFonts()
    vito.power_events_stop()
    vito.input_shutdown()
    sce.sceAppUtilShutdown()
    vito.shutdown()
    sce.sceKernelExitProcess(0)
    return 0
}
