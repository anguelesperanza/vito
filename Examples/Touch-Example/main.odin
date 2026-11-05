package touch_example

import "base:runtime"

import sce "../../lib/sce"
import v2d "../../lib/vita2d"

SCREEN_W :: f32(960)
SCREEN_H :: f32(544)

// Front panel is reported in 1920x1088, back in about 1920x890. These are only
// used if sceTouchGetPanelInfo fails; normally the real active area is used.
FRONT_DEFAULT :: [2]i32{1919, 1087}
BACK_DEFAULT  :: [2]i32{1919, 889}

TRAIL_LEN :: 96

// Maps raw panel coordinates onto the 960x544 screen.
Panel :: struct {
    min_x, min_y: i32,
    w, h:         f32,
}

make_panel :: proc "contextless" (port: u32, fallback: [2]i32) -> Panel {
    info: sce.TouchPanelInfo
    p := Panel{0, 0, f32(fallback.x), f32(fallback.y)}
    if sce.sceTouchGetPanelInfo(port, &info) == 0 && info.maxAaX > info.minAaX && info.maxAaY > info.minAaY {
        p.min_x = i32(info.minAaX)
        p.min_y = i32(info.minAaY)
        p.w     = f32(i32(info.maxAaX) - i32(info.minAaX))
        p.h     = f32(i32(info.maxAaY) - i32(info.minAaY))
    }
    return p
}

to_screen :: proc "contextless" (p: Panel, r: sce.TouchReport) -> (x, y: f32) {
    x = f32(i32(r.x) - p.min_x) / p.w * SCREEN_W
    y = f32(i32(r.y) - p.min_y) / p.h * SCREEN_H
    return
}

// ---------------------------------------------------------------
// Tiny text builder (no allocation): append to buf, then NUL-terminate.
// ---------------------------------------------------------------
put_str :: proc "contextless" (buf: []u8, n: ^int, s: string) {
    for c in transmute([]u8)s {
        if n^ < len(buf) - 1 {
            buf[n^] = c
            n^ += 1
        }
    }
}

put_int :: proc "contextless" (buf: []u8, n: ^int, value: i32) {
    digits: [12]u8
    d := 0
    v := value
    if v < 0 {
        put_str(buf, n, "-")
        v = -v
    }
    if v == 0 {
        digits[d] = '0'
        d += 1
    }
    for v > 0 {
        digits[d] = u8('0' + v % 10)
        d += 1
        v /= 10
    }
    for d > 0 {
        d -= 1
        if n^ < len(buf) - 1 {
            buf[n^] = digits[d]
            n^ += 1
        }
    }
}

finish :: proc "contextless" (buf: []u8, n: int) -> cstring {
    buf[n] = 0
    return cstring(&buf[0])
}

// ---------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------
@(export, link_name = "odin_main")
game_main :: proc "c" (argc: i32, argv: [^]cstring) -> i32 {
    context = runtime.default_context()

    sce.sceClibPrintf("odin_main: started\n")
    sce.sceCtrlSetSamplingMode(.ANALOG)

    // Touch sampling has to be started per panel.
    sce.sceTouchSetSamplingState(sce.TOUCH_PORT_FRONT, .START)
    sce.sceTouchSetSamplingState(sce.TOUCH_PORT_BACK, .START)

    front := make_panel(sce.TOUCH_PORT_FRONT, FRONT_DEFAULT)
    back  := make_panel(sce.TOUCH_PORT_BACK, BACK_DEFAULT)
    sce.sceClibPrintf("front panel: min=(%d,%d) size=(%d,%d)\n",
        front.min_x, front.min_y, i32(front.w), i32(front.h))
    sce.sceClibPrintf("back panel:  min=(%d,%d) size=(%d,%d)\n",
        back.min_x, back.min_y, i32(back.w), i32(back.h))

    if v2d.Init() < 0 {
        sce.sceClibPrintf("vita2d: Init failed\n")
        return sce.sceKernelExitProcess(1)
    }
    v2d.SetClearColor(v2d.RGBA8(0x10, 0x12, 0x20, 0xFF))
    font := v2d.LoadDefaultPvf()

    white   := v2d.RGBA8(0xFF, 0xFF, 0xFF, 0xFF)
    cyan    := v2d.RGBA8(0x30, 0xD0, 0xE0, 0xFF)
    magenta := v2d.RGBA8(0xE0, 0x40, 0xC0, 0xB0)
    yellow  := v2d.RGBA8(0xFF, 0xDC, 0x00, 0xFF)

    pad:      sce.CtrlData
    fdata:    sce.TouchData
    bdata:    sce.TouchData
    trail:    [TRAIL_LEN][2]f32
    trail_n:  int // how many valid points
    trail_at: int // next write slot
    buf:      [96]u8

    for {
        sce.sceCtrlPeekBufferPositive(0, &pad, 1)
        if pad.buttons & sce.CTRL_START != 0 do break
        // Cross clears the trail.
        if pad.buttons & sce.CTRL_CROSS != 0 do trail_n = 0

        // ---- Read both panels ----
        fn := sce.sceTouchPeek(sce.TOUCH_PORT_FRONT, &fdata, 1)
        bn := sce.sceTouchPeek(sce.TOUCH_PORT_BACK, &bdata, 1)
        f_count := fn > 0 ? min(fdata.reportNum, sce.TOUCH_MAX_REPORT) : 0
        b_count := bn > 0 ? min(bdata.reportNum, sce.TOUCH_MAX_REPORT) : 0

        // Record the first front touch in the trail.
        if f_count > 0 {
            x, y := to_screen(front, fdata.report[0])
            trail[trail_at] = {x, y}
            trail_at = (trail_at + 1) % TRAIL_LEN
            trail_n = min(trail_n + 1, TRAIL_LEN)
        }

        // ---- Render ----
        v2d.StartDrawing()
        v2d.ClearScreen()

        // Trail, oldest first, fading in.
        for i in 0 ..< trail_n {
            idx := (trail_at - trail_n + i + TRAIL_LEN) % TRAIL_LEN
            alpha := u8(30 + (200 * i) / TRAIL_LEN)
            v2d.DrawFillCircle(trail[idx].x, trail[idx].y, 10, v2d.RGBA8(0x30, 0xD0, 0xE0, alpha))
        }

        // Back panel: magenta squares.
        for i in 0 ..< b_count {
            x, y := to_screen(back, bdata.report[i])
            v2d.DrawRectangle(x - 36, y - 36, 72, 72, magenta)
        }

        // Front panel: cyan circles with a white core.
        for i in 0 ..< f_count {
            x, y := to_screen(front, fdata.report[i])
            v2d.DrawFillCircle(x, y, 44, cyan)
            v2d.DrawFillCircle(x, y, 8, white)
        }

        if font != nil {
            v2d.PvfDrawText(font, 24, 40, white, 1.3, "Touch example")
            v2d.PvfDrawText(font, 24, 68, white, 0.9, "Touch the screen (cyan) or the back panel (magenta).  Cross: clear trail   Start: exit")

            n := 0
            put_str(buf[:], &n, "front: ")
            put_int(buf[:], &n, i32(f_count))
            put_str(buf[:], &n, "   back: ")
            put_int(buf[:], &n, i32(b_count))
            v2d.PvfDrawText(font, 24, 100, yellow, 1.0, finish(buf[:], n))

            // One line per front touch: id and raw panel coordinates.
            for i in 0 ..< f_count {
                r := fdata.report[i]
                n = 0
                put_str(buf[:], &n, "front id ")
                put_int(buf[:], &n, i32(r.id))
                put_str(buf[:], &n, "  x=")
                put_int(buf[:], &n, i32(r.x))
                put_str(buf[:], &n, " y=")
                put_int(buf[:], &n, i32(r.y))
                v2d.PvfDrawText(font, 24, 128 + 24 * i32(i), white, 0.85, finish(buf[:], n))
            }
            for i in 0 ..< b_count {
                r := bdata.report[i]
                n = 0
                put_str(buf[:], &n, "back id ")
                put_int(buf[:], &n, i32(r.id))
                put_str(buf[:], &n, "  x=")
                put_int(buf[:], &n, i32(r.x))
                put_str(buf[:], &n, " y=")
                put_int(buf[:], &n, i32(r.y))
                v2d.PvfDrawText(font, 560, 128 + 24 * i32(i), magenta | 0xFF000000, 0.85, finish(buf[:], n))
            }
        }

        v2d.EndDrawing()
        v2d.SwapBuffers()
    }

    // Shutdown order matters on real hardware: see docs/getting-started.md,
    // gotchas 10 and 11. Wait for the GPU before freeing, and skip vita2d_fini
    // (it hangs Vita3K v0.2.1).
    v2d.WaitRenderingDone()
    if font != nil do v2d.FreePvf(font)
    sce.sceKernelExitProcess(0)
    return 0
}
