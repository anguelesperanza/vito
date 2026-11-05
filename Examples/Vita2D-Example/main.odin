package vita2d_example

import "base:intrinsics"
import "base:runtime"
import "core:math"

import sce "../../lib/sce"
import v2d "../../lib/vita2d"

SCREEN_W :: f32(960)
SCREEN_H :: f32(544)

// See the shutdown code at the end of game_main.
CALL_FINI :: false

// Test image: 64x64 RGBA PNG, embedded in the executable.
TEST_PNG :: #load("assets/test.png")

// Writes "<label><value>" into buf as a NUL-terminated string.
format_int :: proc "contextless" (buf: []u8, label: string, value: i32) -> cstring {
    n := 0
    for c in transmute([]u8)label {
        buf[n] = c
        n += 1
    }
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
    if neg {
        buf[n] = '-'
        n += 1
    }
    for d > 0 {
        d -= 1
        buf[n] = digits[d]
        n += 1
    }
    buf[n] = 0
    return cstring(&buf[0])
}

// ---------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------
@(export, link_name = "odin_main")
game_main :: proc "c" (argc: i32, argv: [^]cstring) -> i32 {
    context = runtime.default_context()

    sce.sceCtrlSetSamplingMode(.ANALOG)
    sce.sceClibPrintf("odin_main: started\n")

    // libm bridge self-test. The value is loaded volatile so the compiler cannot
    // fold it at build time. Expected: sin(1)=841470 cos(1)=540302 max(2,-3)=2 (x1e6 / x1).
    one: f32 = 1.0
    x := intrinsics.volatile_load(&one)
    sce.sceClibPrintf("selftest sin(1)*1e6=%d cos(1)*1e6=%d max(2x,-3x)=%d\n",
        i32(math.sin(x) * 1e6), i32(math.cos(x) * 1e6), i32(max(2 * x, -3 * x)))

    if v2d.Init() < 0 {
        sce.sceClibPrintf("vita2d: Init failed\n")
        return sce.sceKernelExitProcess(1)
    }
    v2d.SetClearColor(v2d.RGBA8(0x12, 0x14, 0x28, 0xFF))

    tex  := v2d.LoadPNGBuffer(raw_data(TEST_PNG))
    font := v2d.LoadDefaultPvf()
    sce.sceClibPrintf("texture: %p, font: %p\n", tex, font)
    if tex != nil {
        v2d.TextureSetFilters(tex, .LINEAR, .LINEAR)
    }

    white  := v2d.RGBA8(0xFF, 0xFF, 0xFF, 0xFF)
    yellow := v2d.RGBA8(0xFF, 0xDC, 0x00, 0xFF)
    red    := v2d.RGBA8(0xE0, 0x30, 0x30, 0xFF)
    cyan   := v2d.RGBA8(0x30, 0xD0, 0xE0, 0xFF)

    pad:          sce.CtrlData
    prev_buttons: u32
    angle:        f32
    cursor_x:     f32 = SCREEN_W / 2
    cursor_y:     f32 = SCREEN_H / 2
    tinted:       bool
    frames:       i32
    buf:          [64]u8

    // ---------------------------------------------------------------
    // Main loop
    // ---------------------------------------------------------------
    for {
        sce.sceCtrlPeekBufferPositive(0, &pad, 1)
        pressed := pad.buttons & ~prev_buttons
        prev_buttons = pad.buttons

        if pad.buttons & sce.CTRL_START != 0 do break

        // ---- Update ----
        if pad.buttons & sce.CTRL_LEFT  != 0 do cursor_x -= 5
        if pad.buttons & sce.CTRL_RIGHT != 0 do cursor_x += 5
        if pad.buttons & sce.CTRL_UP    != 0 do cursor_y -= 5
        if pad.buttons & sce.CTRL_DOWN  != 0 do cursor_y += 5
        if dx := f32(i32(pad.lx) - 128); dx > 30 || dx < -30 do cursor_x += dx / 25
        if dy := f32(i32(pad.ly) - 128); dy > 30 || dy < -30 do cursor_y += dy / 25
        cursor_x = clamp(cursor_x, 0, SCREEN_W)
        cursor_y = clamp(cursor_y, 0, SCREEN_H)

        if pressed & sce.CTRL_CROSS != 0 {
            tinted = !tinted
            sce.sceClibPrintf("CROSS pressed\n")
        }
        angle  += 0.03
        frames += 1

        cx := SCREEN_W / 2
        cy := SCREEN_H / 2
        pulse := 1.5 + 0.5 * math.sin(angle * 2)

        // ---- Render ----
        v2d.StartDrawing()
        v2d.ClearScreen()

        // Orbiting circles: every coordinate here is a float crossing the bridge.
        for i in 0 ..< 6 {
            a := angle + f32(i) * (math.TAU / 6)
            v2d.DrawFillCircle(cx + 150 * math.cos(a), cy + 150 * math.sin(a), 14, yellow)
        }

        // Spinning, pulsing sprite (scale + rotation in one call).
        if tex != nil {
            v2d.DrawTextureScaleRotate(tex, cx, cy, pulse, pulse, angle)

            // Static sprites: plain, scaled, and tinted (Cross toggles the tint).
            v2d.DrawTexture(tex, 40, 400)
            v2d.DrawTextureScale(tex, 140, 380, 1.5, 1.5)
            if tinted {
                v2d.DrawTextureTintScale(tex, 280, 380, 1.5, 1.5, red)
            } else {
                v2d.DrawTextureTintScale(tex, 280, 380, 1.5, 1.5, cyan)
            }
        }

        // Cursor: a line from the center, a rectangle, and a pixel.
        v2d.DrawLine(cx, cy, cursor_x, cursor_y, white)
        v2d.DrawRectangle(cursor_x - 8, cursor_y - 8, 16, 16, white)
        v2d.DrawPixel(cursor_x, cursor_y, red)

        if font != nil {
            v2d.PvfDrawText(font, 24, 40, white, 1.4, "Odin + vita2d")
            v2d.PvfDrawText(font, 24, 70, white, 1.0, "Float arguments cross the C bridge.")
            v2d.PvfDrawText(font, 24, 100, white, 0.9, "D-pad / left stick: cursor   Cross: tint   Start: exit")
            v2d.PvfDrawText(font, 24, 520, yellow, 1.0, format_int(buf[:], "frame ", frames))
        }

        v2d.EndDrawing()
        v2d.SwapBuffers()
    }

    // Shutdown order matters on real hardware. The last frame is still queued on
    // the GPU and may be reading the texture, so wait for the GPU to go idle
    // before freeing anything it could be using, and only then shut vita2d down.
    sce.sceClibPrintf("exit: waiting for GPU\n")
    v2d.WaitRenderingDone()
    sce.sceClibPrintf("exit: GPU idle, freeing texture\n")
    if tex != nil do v2d.FreeTexture(tex)
    sce.sceClibPrintf("exit: freeing font\n")
    if font != nil do v2d.FreePvf(font)
    // vita2d_fini hangs inside Vita3K v0.2.1 (the real Vita runs it fine). With
    // the GPU idle, exiting without it is safe: the kernel tears GXM down with
    // the process. Set CALL_FINI to true to run it anyway.
    if CALL_FINI {
        sce.sceClibPrintf("exit: vita2d fini\n")
        v2d.Fini()
    }
    sce.sceClibPrintf("exit: calling sceKernelExitProcess\n")
    sce.sceKernelExitProcess(0)
    return 0
}
