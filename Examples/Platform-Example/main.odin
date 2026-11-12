package platform_example

// Exercises the bindings Matchbox needs beyond vita2d:
//   - clock:      sceKernelGetProcessTimeWide  (Matchbox get_delta_time)
//   - file I/O:   sceIoOpen / Read / Lseek32 / Write / Close / Getstat /
//                 Mkdir / Remove / Dopen / Dread / Dclose
//   - input:      pressed / held / released from SceCtrl, sticks as -1..1
//   - exit:       sceKernelExitProcess (Start)
// The file tests run once at startup; results are drawn on screen and
// logged with sceClibPrintf.

import "base:runtime"

import sce "../../lib/sce"
import v2d "../../lib/vita2d"

HELLO_PATH :: cstring("app0:/assets/hello.txt")
DATA_DIR   :: cstring("ux0:/data/ODIN00006")
DATA_FILE  :: cstring("ux0:/data/ODIN00006/test.bin")
HELLO_TEXT :: "Hello from app0:/assets/hello.txt\n0123456789\n"

TEST_COUNT :: 7

// ---------------------------------------------------------------
// Small text builder: no allocator, no fmt.
// ---------------------------------------------------------------
Txt :: struct {
    buf: [192]u8,
    n:   int,
}

txt_reset :: proc "contextless" (t: ^Txt) -> ^Txt {
    t.n = 0
    t.buf[0] = 0
    return t
}

txt_s :: proc "contextless" (t: ^Txt, s: string) -> ^Txt {
    for c in transmute([]u8)s {
        if t.n < len(t.buf) - 1 {
            t.buf[t.n] = c
            t.n += 1
        }
    }
    t.buf[t.n] = 0
    return t
}

txt_i :: proc "contextless" (t: ^Txt, value: i32) -> ^Txt {
    digits: [12]u8
    d := 0
    v := value
    neg := v < 0
    if neg do v = -v
    if v == 0 {
        digits[d] = '0'
        d += 1
    }
    for v > 0 {
        digits[d] = u8('0' + v % 10)
        d += 1
        v /= 10
    }
    if neg do txt_s(t, "-")
    for d > 0 {
        d -= 1
        s := [1]u8{digits[d]}
        txt_s(t, string(s[:]))
    }
    return t
}

txt_h :: proc "contextless" (t: ^Txt, value: u32) -> ^Txt {
    HEX := "0123456789ABCDEF"
    txt_s(t, "0x")
    for shift := i32(28); shift >= 0; shift -= 4 {
        s := [1]u8{HEX[(value >> u32(shift)) & 0xF]}
        txt_s(t, string(s[:]))
    }
    return t
}

txt_c :: proc "contextless" (t: ^Txt) -> cstring {
    return cstring(&t.buf[0])
}

// ---------------------------------------------------------------
// Matchbox-style input state (pressed / held / released + sticks)
// ---------------------------------------------------------------
Input :: struct {
    pressed, held, released: u32,
    left, right:             [2]f32,
}

// Maps 0..255 (128 = centre) to -1..1 with a small dead zone.
stick_axis :: proc "contextless" (v: u8) -> f32 {
    a := (f32(v) - 128.0) / 128.0
    if a > -0.1 && a < 0.1 do return 0
    return a
}

poll :: proc "contextless" (input: ^Input, prev: ^u32) {
    pad: sce.CtrlData
    sce.sceCtrlPeekBufferPositive(0, &pad, 1)
    input.held     = pad.buttons
    input.pressed  = pad.buttons & ~prev^
    input.released = ~pad.buttons & prev^
    prev^          = pad.buttons
    input.left     = {stick_axis(pad.lx), stick_axis(pad.ly)}
    input.right    = {stick_axis(pad.rx), stick_axis(pad.ry)}
}

// ---------------------------------------------------------------
// File tests
// ---------------------------------------------------------------
Result :: struct {
    t:  Txt,
    ok: bool,
}

result :: proc "contextless" (r: ^Result, label: string, ok: bool) {
    r.ok = ok
    txt_reset(&r.t)
    txt_s(&r.t, label)
    txt_s(&r.t, ok ? ": PASS" : ": FAIL")
}

run_file_tests :: proc "contextless" (res: ^[TEST_COUNT]Result) {
    // 1. Getstat on a file inside the VPK
    st: sce.IoStat
    r := sce.sceIoGetstat(HELLO_PATH, &st)
    result(&res[0], "Getstat app0 file",
        r >= 0 && u64(st.st_size) == u64(len(HELLO_TEXT)) && st.st_mode & sce.S_IFMT == sce.S_IFREG)
    txt_s(&res[0].t, "  size ")
    txt_i(&res[0].t, i32(st.st_size))
    txt_s(&res[0].t, " mode ")
    txt_h(&res[0].t, u32(st.st_mode))

    // 2. Open / Read / Close
    buf: [128]u8
    fd := sce.sceIoOpen(HELLO_PATH, sce.O_RDONLY, 0)
    n := i32(-1)
    if fd >= 0 {
        n = sce.sceIoRead(fd, &buf[0], u32(len(buf)))
    }
    expected := HELLO_TEXT
    same := n == i32(len(HELLO_TEXT))
    if same {
        for k in 0 ..< len(HELLO_TEXT) {
            if buf[k] != expected[k] do same = false
        }
    }
    result(&res[1], "Open+Read app0 file", same)
    txt_s(&res[1].t, "  fd ")
    txt_i(&res[1].t, fd)
    txt_s(&res[1].t, " read ")
    txt_i(&res[1].t, n)

    // 3. Lseek32: size via SEEK_END, then read 4 bytes from offset 6
    end_pos := i32(-1)
    seek_ok := false
    if fd >= 0 {
        end_pos = sce.sceIoLseek32(fd, 0, sce.SEEK_END)
        p := sce.sceIoLseek32(fd, 6, sce.SEEK_SET)
        small: [8]u8
        got := sce.sceIoRead(fd, &small[0], 4)
        seek_ok = p == 6 && got == 4 && small[0] == 'f' && small[1] == 'r' && small[2] == 'o' && small[3] == 'm'
        sce.sceIoClose(fd)
    }
    result(&res[2], "Lseek32", seek_ok && end_pos == i32(len(HELLO_TEXT)))
    txt_s(&res[2].t, "  end ")
    txt_i(&res[2].t, end_pos)

    // 4. Directory listing of app0:/assets
    dfd := sce.sceIoDopen("app0:/assets")
    entries := i32(0)
    saw_hello := false
    if dfd >= 0 {
        ent: sce.IoDirent
        for sce.sceIoDread(dfd, &ent) > 0 {
            entries += 1
            if cstring(&ent.d_name[0]) == "hello.txt" do saw_hello = true
        }
        sce.sceIoDclose(dfd)
    }
    result(&res[3], "Dopen/Dread/Dclose", dfd >= 0 && saw_hello)
    txt_s(&res[3].t, "  entries ")
    txt_i(&res[3].t, entries)

    // 5. A missing file gives a negative error, not a crash
    bad := sce.sceIoOpen("app0:/assets/nope.bin", sce.O_RDONLY, 0)
    result(&res[4], "Open missing file", bad < 0)
    txt_s(&res[4].t, "  -> ")
    txt_h(&res[4].t, u32(bad))

    // 6. Write a file to ux0:/data, read it back
    sce.sceIoMkdir(DATA_DIR, sce.IO_DEFAULT_MODE) // fails harmlessly if it exists
    payload: [64]u8
    for k in 0 ..< len(payload) do payload[k] = u8(k * 3 + 1)
    wfd := sce.sceIoOpen(DATA_FILE, sce.O_WRONLY | sce.O_CREAT | sce.O_TRUNC, sce.IO_DEFAULT_MODE)
    wrote := i32(-1)
    if wfd >= 0 {
        wrote = sce.sceIoWrite(wfd, &payload[0], u32(len(payload)))
        sce.sceIoClose(wfd)
    }
    back: [64]u8
    rfd := sce.sceIoOpen(DATA_FILE, sce.O_RDONLY, 0)
    readn := i32(-1)
    size_by_fd := u64(0)
    if rfd >= 0 {
        readn = sce.sceIoRead(rfd, &back[0], u32(len(back)))
        st2: sce.IoStat
        sce.sceIoGetstatByFd(rfd, &st2)
        size_by_fd = u64(st2.st_size)
        sce.sceIoClose(rfd)
    }
    result(&res[5], "Write+Read ux0:/data", wrote == 64 && readn == 64 && back == payload && size_by_fd == 64)
    txt_s(&res[5].t, "  wfd ")
    txt_i(&res[5].t, wfd)
    txt_s(&res[5].t, " rfd ")
    txt_i(&res[5].t, rfd)

    // 7. Remove it again
    rm := sce.sceIoRemove(DATA_FILE)
    gone := sce.sceIoOpen(DATA_FILE, sce.O_RDONLY, 0)
    result(&res[6], "Remove", rm >= 0 && gone < 0)

    for k in 0 ..< TEST_COUNT {
        sce.sceClibPrintf("%s\n", txt_c(&res[k].t))
    }
}

// ---------------------------------------------------------------
// Colours (0xAABBGGRR) and text
// ---------------------------------------------------------------
WHITE  :: u32(0xFFFFFFFF)
GREEN  :: u32(0xFF60D030)
RED    :: u32(0xFF3030E0)
YELLOW :: u32(0xFF00DCFF)
GREY   :: u32(0xFF909090)

pvf: ^v2d.Pvf

text :: proc "contextless" (x, y: i32, color: u32, scale: f32, s: cstring) {
    // DrawText rasterises the font at each size; PvfDrawText with a scale would
    // stretch one 18 px bitmap and small text comes out broken.
    v2d.DrawText(x, y, color, scale, s)
}

@(export, link_name = "odin_main")
game_main :: proc "c" (argc: i32, argv: [^]cstring) -> i32 {
    context = runtime.default_context()

    sce.sceCtrlSetSamplingMode(.ANALOG)
    if v2d.Init() < 0 do return sce.sceKernelExitProcess(1)
    v2d.SetClearColor(v2d.RGBA8(0x12, 0x14, 0x28, 0xFF))
    pvf = v2d.LoadDefaultPvf()

    results: [TEST_COUNT]Result
    run_file_tests(&results)

    input: Input
    prev:  u32
    t:     Txt
    start := sce.sceKernelGetProcessTimeWide()
    last  := start
    frames: i32
    seen: [3]u32 // last non-zero pressed / held / released masks

    for {
        poll(&input, &prev)
        if input.pressed & sce.CTRL_START != 0 do break

        now := sce.sceKernelGetProcessTimeWide()
        dt_us := u32(now - last)
        last = now
        frames += 1
        if input.pressed != 0  do seen[0] = input.pressed
        if input.held != 0     do seen[1] = input.held
        if input.released != 0 do seen[2] = input.released

        v2d.StartDrawing()
        v2d.ClearScreen()

        text(24, 36, WHITE, 1.0, "Platform bindings (clock, file I/O, input)")

        y := i32(80)
        for k in 0 ..< TEST_COUNT {
            text(24, y, results[k].ok ? GREEN : RED, 0.7, txt_c(&results[k].t))
            y += 26
        }

        y += 14
        txt_reset(&t)
        txt_s(&t, "Clock: elapsed us ")
        txt_i(&t, i32(now - start))
        txt_s(&t, "   frame dt us ")
        txt_i(&t, i32(dt_us))
        txt_s(&t, "   frames ")
        txt_i(&t, frames)
        text(24, y, YELLOW, 0.7, txt_c(&t))
        y += 26

        txt_reset(&t)
        txt_s(&t, "Pressed ")
        txt_h(&t, seen[0])
        txt_s(&t, "  Held ")
        txt_h(&t, seen[1])
        txt_s(&t, "  Released ")
        txt_h(&t, seen[2])
        text(24, y, YELLOW, 0.7, txt_c(&t))
        y += 26

        txt_reset(&t)
        txt_s(&t, "Left stick x ")
        txt_i(&t, i32(input.left.x * 100))
        txt_s(&t, " y ")
        txt_i(&t, i32(input.left.y * 100))
        txt_s(&t, "   Right stick x ")
        txt_i(&t, i32(input.right.x * 100))
        txt_s(&t, " y ")
        txt_i(&t, i32(input.right.y * 100))
        text(24, y, YELLOW, 0.7, txt_c(&t))
        y += 26

        text(24, y + 10, GREY, 0.7, "Start exits through sceKernelExitProcess")

        v2d.EndDrawing()
        v2d.SwapBuffers()
    }

    sce.sceClibPrintf("exiting after %d frames\n", frames)
    v2d.WaitRenderingDone()
    return sce.sceKernelExitProcess(0)
}
