package input_example

// Everything the Vita reports about input, live on one screen, read through
// the input layer in lib/vito/input.odin:
//
//   - every button: lit while held, with a count of presses
//   - both sticks: the raw position (grey dot) and the dead-zoned one (white)
//   - front touches (cyan) and back touches (magenta), drawn where they map
//     to on the screen, with id and force
//   - motion: acceleration, gyro, orientation, and a "bubble level"
//   - a few direct SceCtrl / SceTouch / SceMotion calls the layer does not
//     wrap, including the three SceMotion functions that go through the float
//     bridge (lib/sce/bridge.c)
//
// Hold Start + Select for a second to exit (both are also shown as buttons).

import "core:fmt"
import "core:log"

import sce  "../../lib/sce"
import v2d  "../../lib/vita2d"
import vito "../../lib/vito"

WHITE   :: u32(0xFFFFFFFF)
GREEN   :: u32(0xFF40E040)
RED     :: u32(0xFF4040FF)
YELLOW  :: u32(0xFF00DCFF)
CYAN    :: u32(0xFFE0D030)
MAGENTA :: u32(0xFFC040E0)
GREY    :: u32(0xFF909090)
DARK    :: u32(0xFF403830)
PANEL   :: u32(0xFF2A2420)

Button_Box :: struct {
    name: cstring,
    mask: u32,
    x, y: f32,
}

// Laid out roughly like the console: d-pad on the left, shapes on the right.
BUTTONS := [?]Button_Box{
    {"L",      vito.BUTTON_L,        24, 96},
    {"L3",     vito.BUTTON_L3,       94, 96},
    {"Up",     vito.BUTTON_UP,       94, 140},
    {"Left",   vito.BUTTON_LEFT,     24, 184},
    {"Right",  vito.BUTTON_RIGHT,    164, 184},
    {"Down",   vito.BUTTON_DOWN,     94, 228},
    {"Select", vito.BUTTON_SELECT,   264, 228},
    {"Start",  vito.BUTTON_START,    334, 228},
    {"R",      vito.BUTTON_R,        544, 96},
    {"R3",     vito.BUTTON_R3,       474, 96},
    {"Tri",    vito.BUTTON_TRIANGLE, 474, 140},
    {"Square", vito.BUTTON_SQUARE,   404, 184},
    {"Circle", vito.BUTTON_CIRCLE,   544, 184},
    {"Cross",  vito.BUTTON_CROSS,    474, 228},
}
BOX_W :: 64
BOX_H :: 36

press_counts: [len(BUTTONS)]int

draw_stick :: proc(cx, cy: f32, name: cstring, raw_x, raw_y: u8, value: [2]f32) {
    R :: f32(44)
    v2d.DrawFillCircle(cx, cy, R, PANEL)
    v2d.DrawFillCircle(cx, cy, R * vito.stick_dead_zone, DARK) // the dead zone
    // raw position, then the value the layer reports
    v2d.DrawFillCircle(cx + (f32(raw_x) - 128) / 127 * R, cy + (f32(raw_y) - 128) / 127 * R, 5, GREY)
    v2d.DrawFillCircle(cx + value.x * R, cy + value.y * R, 7, WHITE)
    v2d.DrawText(i32(cx - R), i32(cy + R + 18), GREY, 0.7, fmt.ctprintf("%s %5.2f %5.2f", name, value.x, value.y))
}

draw_touches :: proc(panel: ^vito.Touch_Panel, color: u32, label: cstring) {
    for t in vito.touches(panel) {
        // A ring on the first frame, so "pressed" is visible.
        v2d.DrawFillCircle(t.pos.x, t.pos.y, 34 if t.pressed else 22, color)
        v2d.DrawText(i32(t.pos.x) + 26, i32(t.pos.y) - 8, color | 0xFF000000, 0.7,
            fmt.ctprintf("%s id %d  %d,%d  force %d", label, t.id, i32(t.pos.x), i32(t.pos.y), t.force))
    }
}

@(export, link_name = "odin_main")
game_main :: proc "c" (argc: i32, argv: [^]cstring) -> i32 {
    context = vito.init()

    if v2d.Init() < 0 {
        vito.println("vita2d: Init failed")
        return sce.sceKernelExitProcess(1)
    }
    v2d.SetClearColor(v2d.RGBA8(0x10, 0x12, 0x20, 0xFF))

    all_started := vito.input_init({.Front_Touch, .Back_Touch, .Motion})
    log.infof("input_init: %v", all_started)

    // --- direct calls the input layer does not wrap --------------------
    // Touch force is off by default.
    force_front := sce.sceTouchEnableTouchForce(sce.TOUCH_PORT_FRONT)
    force_back  := sce.sceTouchEnableTouchForce(sce.TOUCH_PORT_BACK)

    sampling_mode: sce.CtrlPadInputMode
    mode_result := sce.sceCtrlGetSamplingMode(&sampling_mode)

    ports: sce.CtrlPortInfo
    ports_result := sce.sceCtrlGetControllerPortInfo(&ports)

    touch_state: sce.TouchSamplingState
    touch_state_result := sce.sceTouchGetSamplingState(sce.TOUCH_PORT_FRONT, &touch_state)

    // The three SceMotion functions with a float parameter or result. They go
    // through lib/sce/bridge.c; this is a round trip to prove the bridge.
    threshold_before := sce.sceMotionGetAngleThreshold()
    set_result       := sce.sceMotionSetAngleThreshold(30)
    threshold_after  := sce.sceMotionGetAngleThreshold()
    yaw_result       := sce.sceMotionRotateYaw(0)
    bridge_ok        := set_result >= 0 && threshold_after == 30
    log.infof("motion angle threshold: %.2f -> set 30 (0x%08X) -> %.2f; RotateYaw(0): 0x%08X",
        threshold_before, u32(set_result), threshold_after, u32(yaw_result))

    tilt_correction := sce.sceMotionGetTiltCorrection()
    deadband        := sce.sceMotionGetDeadband()

    input: vito.Input
    exit_hold := 0
    frames := 0

    for {
        vito.input_update(&input)

        // Start + Select held for about a second exits.
        if vito.held(input, vito.BUTTON_START) && vito.held(input, vito.BUTTON_SELECT) {
            exit_hold += 1
            if exit_hold > 60 do break
        } else {
            exit_hold = 0
        }

        for b, i in BUTTONS {
            if vito.pressed(input, b.mask) do press_counts[i] += 1
        }

        v2d.StartDrawing()
        v2d.ClearScreen()

        v2d.DrawText(24, 40, WHITE, 1.3, "Input example")
        v2d.DrawText(24, 66, GREY, 0.8, "lib/vito input layer: buttons, sticks, both touch panels, motion")

        // --- buttons
        for b, i in BUTTONS {
            color := DARK
            if vito.held(input, b.mask)     do color = GREEN
            if vito.pressed(input, b.mask)  do color = WHITE  // one frame
            if vito.released(input, b.mask) do color = RED    // one frame
            v2d.DrawRectangle(b.x, b.y, BOX_W, BOX_H, color)
            v2d.DrawText(i32(b.x) + 4, i32(b.y) + 16, WHITE if color == DARK else 0xFF000000, 0.7, b.name)
            v2d.DrawText(i32(b.x) + 4, i32(b.y) + 32, GREY if color == DARK else 0xFF000000, 0.6, fmt.ctprintf("%d", press_counts[i]))
        }
        dp := vito.dpad(input)
        v2d.DrawText(24, 290, GREY, 0.7, fmt.ctprintf("held %08X   d-pad %2.0f,%2.0f   white = pressed this frame, red = released", input.held, dp.x, dp.y))

        // --- sticks
        draw_stick(110, 370, "L", input.raw.lx, input.raw.ly, input.left_stick)
        draw_stick(300, 370, "R", input.raw.rx, input.raw.ry, input.right_stick)

        // --- motion
        MX :: 640
        v2d.DrawText(MX, 108, CYAN, 1.0, "Motion")
        m := input.motion
        if m.valid {
            v2d.DrawText(MX, 134, WHITE, 0.75, fmt.ctprintf("accel  %6.2f %6.2f %6.2f g", m.acceleration.x, m.acceleration.y, m.acceleration.z))
            v2d.DrawText(MX, 156, WHITE, 0.75, fmt.ctprintf("gyro   %6.2f %6.2f %6.2f rad/s", m.gyro.x, m.gyro.y, m.gyro.z))
            v2d.DrawText(MX, 178, WHITE, 0.75, fmt.ctprintf("quat   %5.2f %5.2f %5.2f %5.2f", m.orientation.x, m.orientation.y, m.orientation.z, m.orientation.w))
            v2d.DrawText(MX, 200, WHITE, 0.75, fmt.ctprintf("facing %2.0f %2.0f %2.0f", m.basic_orientation.x, m.basic_orientation.y, m.basic_orientation.z))
            // Bubble level: tilt the console and the dot moves.
            LX, LY, LR :: f32(790), f32(290), f32(56)
            v2d.DrawFillCircle(LX, LY, LR, PANEL)
            v2d.DrawLine(LX - LR, LY, LX + LR, LY, DARK)
            v2d.DrawLine(LX, LY - LR, LX, LY + LR, DARK)
            v2d.DrawFillCircle(LX + clamp(m.acceleration.x, -1, 1) * LR, LY - clamp(m.acceleration.y, -1, 1) * LR, 8, YELLOW)
        } else {
            v2d.DrawText(MX, 134, RED, 0.8, "no motion data")
        }

        // --- direct calls
        y := i32(380)
        v2d.DrawText(MX, y, GREEN if bridge_ok else RED, 0.7,
            fmt.ctprintf("float bridge: threshold %.1f -> %.1f  yaw 0x%X", threshold_before, threshold_after, u32(yaw_result)))
        y += 20
        v2d.DrawText(MX, y, GREY, 0.7, fmt.ctprintf("tilt correction %d   deadband %d", tilt_correction, deadband))
        y += 20
        v2d.DrawText(MX, y, GREY if mode_result >= 0 else RED, 0.7,
            fmt.ctprintf("sampling mode %d   touch state %d (0x%X)", i32(sampling_mode), i32(touch_state), u32(touch_state_result)))
        y += 20
        v2d.DrawText(MX, y, GREY if ports_result >= 0 else RED, 0.7,
            fmt.ctprintf("controller ports %d %d %d %d %d", ports.port[0], ports.port[1], ports.port[2], ports.port[3], ports.port[4]))
        y += 20
        v2d.DrawText(MX, y, GREY if force_front >= 0 && force_back >= 0 else RED, 0.7,
            fmt.ctprintf("touch force: front 0x%X  back 0x%X", u32(force_front), u32(force_back)))

        v2d.DrawText(24, 496, GREY, 0.7,
            fmt.ctprintf("touches: front %d  back %d   released this frame: %d / %d",
                input.front.count, input.back.count, input.front.released_count, input.back.released_count))
        v2d.DrawText(24, 522, YELLOW if exit_hold > 0 else GREY, 0.8, "Hold Start + Select to exit   Touch the screen or the back panel")

        // --- touches go on top of everything
        draw_touches(&input.back, MAGENTA & 0xB0FFFFFF, "back")
        draw_touches(&input.front, CYAN & 0xB0FFFFFF, "front")

        v2d.EndDrawing()
        v2d.SwapBuffers()
        free_all(context.temp_allocator)
        frames += 1
    }

    v2d.WaitRenderingDone()
    v2d.FreeSizedFonts()
    vito.input_shutdown()
    vito.shutdown()
    sce.sceKernelExitProcess(0)
    return 0
}
