package my_game

import "base:runtime"

import sce "../lib/sce"

SCREEN_W :: sce.DISPLAY_WIDTH
SCREEN_H :: sce.DISPLAY_HEIGHT

SQUARE_SIZE  :: 64
SQUARE_SPEED :: 6

// ---------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------
// The proc name below can be anything — only the link_name matters.
@(export, link_name = "odin_main")
game_main :: proc "c" (argc: i32, argv: [^]cstring) -> i32 {
    context = runtime.default_context()

    sce.sceCtrlSetSamplingMode(.ANALOG)
    sce.sceClibPrintf("odin_main: started\n")

    // ---------------------------------------------------------------
    // Framebuffer: one CDRAM block big enough for 960x544 RGBA8888.
    // ---------------------------------------------------------------
    fb_bytes :: SCREEN_W * SCREEN_H * 4
    fb_size  :: u32((fb_bytes + sce.CDRAM_ALIGNMENT - 1) / sce.CDRAM_ALIGNMENT * sce.CDRAM_ALIGNMENT)

    block := sce.sceKernelAllocMemBlock("display", sce.MEMBLOCK_TYPE_USER_CDRAM_RW, fb_size, nil)
    if block < 0 {
        sce.sceClibPrintf("sceKernelAllocMemBlock failed: 0x%08x\n", u32(block))
        return sce.sceKernelExitProcess(1)
    }

    base: rawptr
    sce.sceKernelGetMemBlockBase(block, &base)
    pixels := ([^]u32)(base)

    frame := sce.DisplayFrameBuf {
        size        = size_of(sce.DisplayFrameBuf),
        base        = base,
        pitch       = SCREEN_W,
        pixelformat = sce.DISPLAY_PIXELFORMAT_A8B8G8R8,
        width       = SCREEN_W,
        height      = SCREEN_H,
    }

    // ---------------------------------------------------------------
    // Main loop
    // ---------------------------------------------------------------
    pad:    sce.CtrlData
    sq_x:   i32 = (SCREEN_W - SQUARE_SIZE) / 2
    sq_y:   i32 = (SCREEN_H - SQUARE_SIZE) / 2
    scroll: u32 = 0
    alt:    bool

    prev_buttons: u32
    for {
        sce.sceCtrlPeekBufferPositive(0, &pad, 1)
        pressed := pad.buttons & ~prev_buttons
        prev_buttons = pad.buttons

        // START exits
        if pad.buttons & sce.CTRL_START != 0 do break

        // ---- Update ----
        if pad.buttons & sce.CTRL_LEFT  != 0 do sq_x -= SQUARE_SPEED
        if pad.buttons & sce.CTRL_RIGHT != 0 do sq_x += SQUARE_SPEED
        if pad.buttons & sce.CTRL_UP    != 0 do sq_y -= SQUARE_SPEED
        if pad.buttons & sce.CTRL_DOWN  != 0 do sq_y += SQUARE_SPEED

        // Left analogue stick: 0..255, centred near 128, with a dead zone.
        if dx := i32(pad.lx) - 128; dx > 30 || dx < -30 do sq_x += dx / 20
        if dy := i32(pad.ly) - 128; dy > 30 || dy < -30 do sq_y += dy / 20

        sq_x = clamp(sq_x, 0, SCREEN_W - SQUARE_SIZE)
        sq_y = clamp(sq_y, 0, SCREEN_H - SQUARE_SIZE)

        if pressed & sce.CTRL_CROSS != 0 {
            alt = !alt
            sce.sceClibPrintf("CROSS pressed\n")
        }
        scroll += 1

        // ---- Render ----
        draw(pixels, sq_x, sq_y, scroll, alt)
        sce.sceDisplaySetFrameBuf(&frame, .NEXTFRAME)
        sce.sceDisplayWaitVblankStart()
    }

    // Do not free the framebuffer block here: the display is still scanning it
    // out. The kernel releases it when the process exits.
    sce.sceKernelExitProcess(0)
    return 0
}

// Scrolling diagonal gradient with a white square on top.
draw :: proc "contextless" (pixels: [^]u32, sq_x, sq_y: i32, scroll: u32, alt: bool) {
    for y in 0 ..< SCREEN_H {
        for x in 0 ..< SCREEN_W {
            t := u8((u32(x + y) + scroll) & 0xFF)
            if alt {
                pixels[y * SCREEN_W + x] = sce.Color32(t, 0x20, 0xFF - t, 0xFF)
            } else {
                pixels[y * SCREEN_W + x] = sce.Color32(0x20, t, 0xFF - t, 0xFF)
            }
        }
    }

    white := sce.Color32(0xFF, 0xFF, 0xFF, 0xFF)
    for y in sq_y ..< sq_y + SQUARE_SIZE {
        for x in sq_x ..< sq_x + SQUARE_SIZE {
            pixels[y * SCREEN_W + x] = white
        }
    }
}
