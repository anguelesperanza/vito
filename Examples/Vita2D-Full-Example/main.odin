package vita2d_full_example

// Exercises every vita2d binding (except the printf-style text functions,
// which are not bound). Eight pages; L / R shoulder buttons switch pages.
// Pages 6 and 7 do things that may crash the app or the GPU, so they only
// start when you press Cross on that page. Everything that happens is also
// written to the log with sceClibPrintf.

import "base:runtime"
import "core:math"

import sce "../../lib/sce"
import v2d "../../lib/vita2d"

SCREEN_W :: f32(960)
SCREEN_H :: f32(544)

// See the shutdown code at the end of game_main.
CALL_FINI :: false

// Which init call to use. 0 = Init, 1 = InitAdvanced (1 MiB pool),
// 2 = InitAdvancedWithMsaa (4x). Change it and rebuild to test the others.
INIT_MODE :: 0

SHOULDER_L :: sce.CTRL_LTRIGGER | sce.CTRL_L1
SHOULDER_R :: sce.CTRL_RTRIGGER | sce.CTRL_R1

TEST_PNG :: #load("assets/test.png")
TEST_JPG :: #load("assets/test.jpg")
TEST_BMP :: #load("assets/test.bmp")
TEST_TTF :: #load("assets/font.ttf")

PAGE_COUNT :: 8
PAGE_NAMES := [PAGE_COUNT]cstring{
    "1/8  Primitives, vertex pool, DrawArray",
    "2/8  Clipping, blend, vblank",
    "3/8  Texture draw variants",
    "4/8  Loaders and texture queries",
    "5/8  PVF text",
    "6/8  FreeType text",
    "7/8  PGF text (Cross starts it)",
    "8/8  Render target (Cross starts it)",
}

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
// State
// ---------------------------------------------------------------
// Constants, not v2d.RGBA8() calls: package-level variables initialised by a
// procedure call are not set up with -no-entry-point. Layout is 0xAABBGGRR.
WHITE  :: u32(0xFFFFFFFF)
YELLOW :: u32(0xFF00DCFF) // RGBA8(0xFF, 0xDC, 0x00, 0xFF)
RED    :: u32(0xFF3030E0) // RGBA8(0xE0, 0x30, 0x30, 0xFF)
GREEN  :: u32(0xFF60D030) // RGBA8(0x30, 0xD0, 0x60, 0xFF)
CYAN   :: u32(0xFFE0D030) // RGBA8(0x30, 0xD0, 0xE0, 0xFF)
GREY   :: u32(0xFF909090) // RGBA8(0x90, 0x90, 0x90, 0xFF)

pvf: ^v2d.Pvf

text :: proc "contextless" (x, y: i32, color: u32, scale: f32, s: cstring) {
    // DrawText rasterises the font at each size; PvfDrawText with a scale would
    // stretch one 18 px bitmap and small text comes out broken.
    v2d.DrawText(x, y, color, scale, s)
}

do_init :: proc "contextless" () -> i32 {
    when INIT_MODE == 1 {
        return v2d.InitAdvanced(1024 * 1024)
    } else when INIT_MODE == 2 {
        return v2d.InitAdvancedWithMsaa(1024 * 1024, .X4)
    } else {
        return v2d.Init()
    }
}

any_char :: proc "c" (c: u32) -> i32 {
    return 1
}

// Fills a 32-bit-per-pixel texture with a pattern.
fill_texture :: proc "contextless" (tex: ^v2d.Texture, checker: bool) {
    data   := cast([^]u8)v2d.TextureData(tex)
    stride := v2d.TextureStride(tex)
    w      := v2d.TextureWidth(tex)
    h      := v2d.TextureHeight(tex)
    for y in 0 ..< h {
        row := cast([^]u32)(&data[y * stride])
        for x in 0 ..< w {
            if checker {
                on := ((x / 8) + (y / 8)) % 2 == 0
                row[x] = on ? v2d.RGBA8(0xF0, 0xF0, 0x40, 0xFF) : v2d.RGBA8(0x30, 0x30, 0x90, 0xFF)
            } else {
                row[x] = v2d.RGBA8(u8(x * 4), u8(y * 4), 0x80, 0xFF)
            }
        }
    }
}

// One texture-variant cell on page 3. cx, cy is the cell's top-left corner.
draw_variant :: proc "contextless" (i: i32, tex: ^v2d.Texture, cx, cy, a: f32) {
    x := cx + 8
    y := cy + 28
    mid_x := x + 32 // centre of a 64x64 texture drawn at (x, y)
    mid_y := y + 32
    tint := v2d.RGBA8(0xFF, 0x90, 0x90, 0xFF)
    switch i {
    case 0:  v2d.DrawTexture(tex, x, y)
    case 1:  v2d.DrawTextureRotate(tex, mid_x, mid_y, a)
    case 2:  v2d.DrawTextureRotateHotspot(tex, x, y, a, 0, 0)
    case 3:  v2d.DrawTextureScale(tex, x, y, 1.25, 0.75)
    case 4:  v2d.DrawTexturePart(tex, x, y, 0, 0, 32, 32)
    case 5:  v2d.DrawTexturePartScale(tex, x, y, 32, 32, 32, 32, 1.5, 1.5)
    case 6:  v2d.DrawTextureScaleRotateHotspot(tex, x, y, 0.75, 0.75, a, 0, 0)
    case 7:  v2d.DrawTextureScaleRotate(tex, mid_x, mid_y, 0.8, 0.8, a)
    case 8:  v2d.DrawTexturePartScaleRotate(tex, mid_x, mid_y, 0, 0, 32, 32, 1.5, 1.5, a)
    case 9:  v2d.DrawTextureTint(tex, x, y, tint)
    case 10: v2d.DrawTextureTintRotate(tex, mid_x, mid_y, a, tint)
    case 11: v2d.DrawTextureTintRotateHotspot(tex, x, y, a, 0, 0, tint)
    case 12: v2d.DrawTextureTintScale(tex, x, y, 1.25, 0.75, tint)
    case 13: v2d.DrawTextureTintPart(tex, x, y, 0, 0, 32, 32, tint)
    case 14: v2d.DrawTextureTintPartScale(tex, x, y, 32, 32, 32, 32, 1.5, 1.5, tint)
    case 15: v2d.DrawTextureTintScaleRotateHotspot(tex, x, y, 0.75, 0.75, a, 0, 0, tint)
    case 16: v2d.DrawTextureTintScaleRotate(tex, mid_x, mid_y, 0.8, 0.8, a, tint)
    case 17: v2d.DrawTexturePartTintScaleRotate(tex, mid_x, mid_y, 0, 0, 32, 32, 1.5, 1.5, a, tint)
    case 18:
        // DrawArrayTextured: a triangle strip quad, vertices from the pool.
        v := cast([^]v2d.TextureVertex)v2d.PoolMalloc(4 * size_of(v2d.TextureVertex))
        if v != nil {
            v[0] = {x,      y,      0.5, 0, 0}
            v[1] = {x + 64, y,      0.5, 1, 0}
            v[2] = {x,      y + 64, 0.5, 0, 1}
            v[3] = {x + 64, y + 64, 0.5, 1, 1}
            v2d.DrawArrayTextured(tex, .TRIANGLE_STRIP, v, 4, WHITE)
        }
    }
}

VARIANT_NAMES := [19]cstring{
    "Texture", "Rotate", "RotateHotspot", "Scale", "Part", "PartScale",
    "ScaleRotateHotspot", "ScaleRotate", "PartScaleRotate",
    "Tint", "TintRotate", "TintRotateHotspot", "TintScale", "TintPart",
    "TintPartScale", "TintScaleRotateHotspot", "TintScaleRotate",
    "PartTintScaleRotate", "DrawArrayTextured",
}

// ---------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------
@(export, link_name = "odin_main")
game_main :: proc "c" (argc: i32, argv: [^]cstring) -> i32 {
    context = runtime.default_context()

    sce.sceCtrlSetSamplingMode(.ANALOG)
    sce.sceClibPrintf("odin_main: started\n")

    init_result := do_init()
    if init_result < 0 {
        sce.sceClibPrintf("vita2d: init failed (mode %d) -> 0x%08x\n", i32(INIT_MODE), u32(init_result))
        return sce.sceKernelExitProcess(1)
    }
    sce.sceClibPrintf("vita2d: init ok (mode %d)\n", i32(INIT_MODE))
    v2d.SetClearColor(v2d.RGBA8(0x12, 0x14, 0x28, 0xFF))
    sce.sceClibPrintf("clear color: %08x\n", v2d.GetClearColor())

    // Calls that only return something: log it.
    sce.sceClibPrintf("context=%p patcher=%p indices=%p fb=%p\n",
        v2d.GetContext(), v2d.GetShaderPatcher(), v2d.GetLinearIndices(), v2d.GetCurrentFb())
    sce.sceClibPrintf("CommonDialogUpdate -> %d\n", v2d.CommonDialogUpdate())
    sce.sceClibPrintf("pool free space: %u\n", v2d.PoolFreeSpace())
    v2d.PoolReset()
    sce.sceClibPrintf("pool free space after reset: %u\n", v2d.PoolFreeSpace())
    sce.sceClibPrintf("alloc memblock type: %08x\n", v2d.TextureAllocMemblockType())
    v2d.TextureSetAllocMemblockType(v2d.TextureAllocMemblockType())

    // ---- Textures ----
    png_buf  := v2d.LoadPNGBuffer(raw_data(TEST_PNG))
    jpg_buf  := v2d.LoadJPEGBuffer(raw_data(TEST_JPG), u32(len(TEST_JPG)))
    bmp_buf  := v2d.LoadBMPBuffer(raw_data(TEST_BMP))
    png_file := v2d.LoadPNGFile("app0:/assets/test.png")
    jpg_file := v2d.LoadJPEGFile("app0:/assets/test.jpg")
    bmp_file := v2d.LoadBMPFile("app0:/assets/test.bmp")
    gen_tex  := v2d.CreateEmptyTexture(64, 64)
    fmt_tex  := v2d.CreateEmptyTextureFormat(64, 64, sce.GxmTextureFormat.U8U8U8U8_ABGR)
    gray_tex := v2d.CreateEmptyTextureFormat(64, 64, sce.GxmTextureFormat.U8_R)
    sce.sceClibPrintf("png buf/file %p %p  jpg %p %p  bmp %p %p\n", png_buf, png_file, jpg_buf, jpg_file, bmp_buf, bmp_file)
    sce.sceClibPrintf("empty %p  empty(format) %p  empty(U8_R) %p\n", gen_tex, fmt_tex, gray_tex)
    if gen_tex != nil do fill_texture(gen_tex, false)
    if fmt_tex != nil do fill_texture(fmt_tex, true)
    if gray_tex != nil {
        // 8 bits per pixel: stride is in bytes.
        data   := cast([^]u8)v2d.TextureData(gray_tex)
        stride := v2d.TextureStride(gray_tex)
        for y in 0 ..< 64 {
            for x in 0 ..< 64 {
                data[u32(y) * stride + u32(x)] = u8(x * 4)
            }
        }
    }
    // Page 3 uses gen_tex for the variant grid.
    variant_tex := gen_tex
    if variant_tex == nil do variant_tex = png_buf

    // ---- Fonts ----
    pvf = v2d.LoadDefaultPvf()
    sys_cfg := [1]v2d.SystemPvfConfig{{code = sce.PVF_DEFAULT_LANGUAGE_CODE, in_font_group = any_char}}
    pvf_sys    := v2d.LoadSystemPvf(1, raw_data(sys_cfg[:]))
    pvf_custom := v2d.LoadCustomPvf("sa0:data/font/pvf/ltn0.pvf")
    ft_mem     := v2d.LoadFontMem(raw_data(TEST_TTF), u32(len(TEST_TTF)))
    ft_file    := v2d.LoadFontFile("app0:/assets/font.ttf")
    sce.sceClibPrintf("pvf default %p system %p custom %p  freetype mem %p file %p\n",
        pvf, pvf_sys, pvf_custom, ft_mem, ft_file)

    pad:          sce.CtrlData
    prev_buttons: u32
    angle:        f32
    frames:       i32
    page:         i32
    t:            Txt

    // page 1 state
    clip_on:      bool
    region_mode:  i32
    add_blend:    bool
    vblank:       bool = true
    // page 4 state
    smooth:       bool = true
    // page 7 state
    pgf_state:    i32 // 0 = not started, 1 = loaded
    pgf_default:  ^v2d.Pgf
    pgf_system:   ^v2d.Pgf
    pgf_custom:   ^v2d.Pgf
    rt_state:     i32 // 0 = not started, 1 = running
    rt:           ^v2d.Texture

    // ---------------------------------------------------------------
    // Main loop
    // ---------------------------------------------------------------
    for {
        sce.sceCtrlPeekBufferPositive(0, &pad, 1)
        pressed := pad.buttons & ~prev_buttons
        prev_buttons = pad.buttons

        if pad.buttons & sce.CTRL_START != 0 do break
        if pressed & SHOULDER_L != 0 do page = (page + PAGE_COUNT - 1) % PAGE_COUNT
        if pressed & SHOULDER_R != 0 do page = (page + 1) % PAGE_COUNT
        angle  += 0.03
        frames += 1

        // ---- Per-page input ----
        switch page {
        case 1:
            if pressed & sce.CTRL_CROSS != 0 {
                clip_on = !clip_on
                if clip_on {
                    v2d.SetClipRectangle(240, 150, 720, 400)
                    v2d.EnableClipping()
                } else {
                    v2d.DisableClipping()
                }
                sce.sceClibPrintf("clipping %d\n", i32(clip_on))
            }
            if pressed & sce.CTRL_SQUARE != 0 {
                region_mode = (region_mode + 1) % 3
                switch region_mode {
                case 0: v2d.SetRegionClip(.NONE, 0, 0, 960, 544)
                case 1: v2d.SetRegionClip(.OUTSIDE, 224, 160, 736, 416)
                case 2: v2d.SetRegionClip(.INSIDE, 224, 160, 736, 416)
                }
                sce.sceClibPrintf("region clip mode %d\n", region_mode)
            }
            if pressed & sce.CTRL_CIRCLE != 0 {
                add_blend = !add_blend
                v2d.SetBlendModeAdd(add_blend ? 1 : 0)
                sce.sceClibPrintf("add blend %d\n", i32(add_blend))
            }
            if pressed & sce.CTRL_TRIANGLE != 0 {
                vblank = !vblank
                v2d.SetVblankWait(vblank ? 1 : 0)
                sce.sceClibPrintf("vblank wait %d\n", i32(vblank))
            }
        case 3:
            if pressed & sce.CTRL_CROSS != 0 {
                smooth = !smooth
                f: v2d.TextureFilter = smooth ? .LINEAR : .POINT
                for tx in ([?]^v2d.Texture{png_buf, png_file, jpg_buf, jpg_file, bmp_buf, bmp_file, gen_tex, fmt_tex}) {
                    if tx != nil do v2d.TextureSetFilters(tx, f, f)
                }
            }
        case 6:
            if pressed & sce.CTRL_CROSS != 0 && pgf_state == 0 {
                sce.sceClibPrintf("pgf: LoadDefaultPgf...\n")
                pgf_default = v2d.LoadDefaultPgf()
                sce.sceClibPrintf("pgf: default %p; LoadSystemPgf...\n", pgf_default)
                pgf_cfg := [1]v2d.SystemPgfConfig{{code = sce.FONT_LANGUAGE_DEFAULT, in_font_group = any_char}}
                pgf_system = v2d.LoadSystemPgf(1, raw_data(pgf_cfg[:]))
                sce.sceClibPrintf("pgf: system %p; LoadCustomPgf...\n", pgf_system)
                pgf_custom = v2d.LoadCustomPgf("sa0:data/font/pgf/ltn0.pgf")
                sce.sceClibPrintf("pgf: custom %p\n", pgf_custom)
                pgf_state = 1
            }
        case 7:
            if pressed & sce.CTRL_CROSS != 0 && rt_state == 0 {
                sce.sceClibPrintf("rendertarget: creating\n")
                rt = v2d.CreateEmptyTextureRendertarget(192, 144, sce.GxmTextureFormat.A8B8G8R8)
                sce.sceClibPrintf("rendertarget: texture %p\n", rt)
                if rt != nil do rt_state = 1
            }
        }

        // ---- Offscreen pass (page 8) ----
        if page == 7 && rt_state == 1 && rt != nil {
            v2d.StartDrawingAdvanced(rt, 0)
            v2d.ClearScreen()
            v2d.DrawFillCircle(96 + 50 * math.cos(angle), 72 + 40 * math.sin(angle), 24, YELLOW)
            v2d.DrawRectangle(10, 10, 60, 30, GREEN)
            v2d.DrawLine(0, 0, 192, 144, WHITE)
            v2d.EndDrawing()
        }

        // ---- Render ----
        v2d.StartDrawing()
        v2d.ClearScreen()

        text(24, 30, YELLOW, 1.0, PAGE_NAMES[page])
        text(24, 524, GREY, 0.7, "L / R: page   Start: exit")

        switch page {
        case 0:
            // Pixels (1x1 rectangles) and the raw GPU point (Triangle).
            text(24, 66, WHITE, 0.7, "DrawPixel row, DrawLine fan, DrawRectangle, DrawFillCircle")
            for i in 0 ..< 40 {
                v2d.DrawPixel(30 + f32(i) * 6, 80, WHITE)
            }
            for i in 0 ..< 12 {
                a := f32(i) * (math.TAU / 12)
                v2d.DrawLine(120, 170, 120 + 50 * math.cos(a), 170 + 50 * math.sin(a), CYAN)
            }
            v2d.DrawRectangle(200, 130, 90, 70, RED)
            v2d.DrawFillCircle(350, 170, 35, GREEN)
            if pad.buttons & sce.CTRL_TRIANGLE != 0 {
                for i in 0 ..< 5 {
                    v2d.DrawPoint(420 + f32(i) * 20, 170, WHITE)
                }
            }
            text(420, 210, GREY, 0.6, "hold Triangle: DrawPoint (raw GPU point)")

            // DrawArray: triangles, a strip and lines, vertices from the pool.
            text(24, 250, WHITE, 0.7, "DrawArray (vertices from PoolMalloc)")
            tri := cast([^]v2d.ColorVertex)v2d.PoolMalloc(3 * size_of(v2d.ColorVertex))
            if tri != nil {
                tri[0] = {60,  420, 0.5, RED}
                tri[1] = {180, 420, 0.5, GREEN}
                tri[2] = {120, 290, 0.5, v2d.RGBA8(0x30, 0x50, 0xFF, 0xFF)}
                v2d.DrawArray(.TRIANGLES, tri, 3)
            }
            strip := cast([^]v2d.ColorVertex)v2d.PoolMalloc(5 * size_of(v2d.ColorVertex))
            if strip != nil {
                strip[0] = {260, 290, 0.5, YELLOW}
                strip[1] = {260, 420, 0.5, RED}
                strip[2] = {340, 300, 0.5, GREEN}
                strip[3] = {340, 410, 0.5, CYAN}
                strip[4] = {420, 290, 0.5, WHITE}
                v2d.DrawArray(.TRIANGLE_STRIP, strip, 5)
            }
            lines := cast([^]v2d.ColorVertex)v2d.PoolMalloc(4 * size_of(v2d.ColorVertex))
            if lines != nil {
                lines[0] = {470, 290, 0.5, WHITE}
                lines[1] = {640, 420, 0.5, WHITE}
                lines[2] = {470, 420, 0.5, YELLOW}
                lines[3] = {640, 290, 0.5, YELLOW}
                v2d.DrawArray(.LINES, lines, 4)
            }
            fan := cast([^]v2d.ColorVertex)v2d.PoolMalloc(6 * size_of(v2d.ColorVertex))
            if fan != nil {
                fan[0] = {780, 360, 0.5, WHITE}
                for i in 0 ..< 5 {
                    a := f32(i) * (math.PI / 4) - math.PI / 2
                    fan[1 + i] = {780 + 80 * math.cos(a), 360 + 80 * math.sin(a), 0.5, CYAN}
                }
                v2d.DrawArray(.TRIANGLE_FAN, fan, 6)
            }
            text(24, 460, WHITE, 0.7, txt_c(txt_s(txt_i(txt_s(txt_reset(&t), "pool free space: "), i32(v2d.PoolFreeSpace())), " bytes")))

        case 1:
            text(24, 66, WHITE, 0.7, "Cross: clip rect   Square: region clip   Circle: additive blend   Triangle: vblank")
            // Big shapes that cross the clip areas.
            v2d.DrawRectangle(120, 100, 720, 330, v2d.RGBA8(0x30, 0x60, 0x30, 0xFF))
            v2d.DrawLine(0, 90, 960, 440, WHITE)
            v2d.DrawLine(0, 440, 960, 90, WHITE)
            v2d.DrawFillCircle(480, 270, 140, v2d.RGBA8(0x30, 0x30, 0xC0, 0xFF))
            // Three overlapping translucent circles show the blend mode.
            v2d.DrawFillCircle(400, 270, 70, v2d.RGBA8(0xFF, 0x00, 0x00, 0x80))
            v2d.DrawFillCircle(480, 270, 70, v2d.RGBA8(0x00, 0xFF, 0x00, 0x80))
            v2d.DrawFillCircle(560, 270, 70, v2d.RGBA8(0x00, 0x00, 0xFF, 0x80))
            // A bar that moves one step per frame: faster without vblank wait.
            bar := f32(frames % 960)
            v2d.DrawRectangle(bar, 470, 20, 10, YELLOW)

            x0, y0, x1, y1: i32
            v2d.GetClipRectangle(&x0, &y0, &x1, &y1)
            text(24, 456, WHITE, 0.7, txt_c(txt_i(txt_s(txt_reset(&t), "clipping enabled: "), v2d.ClippingEnabled())))
            text(24, 482, WHITE, 0.7, txt_c(txt_i(txt_s(txt_i(txt_s(txt_i(txt_s(txt_i(txt_s(txt_reset(&t), "clip rect: "), x0), ", "), y0), " - "), x1), ", "), y1)))
            text(24, 508, WHITE, 0.7, txt_c(txt_i(txt_s(txt_i(txt_s(txt_i(txt_s(txt_reset(&t), "region mode: "), region_mode), "   add blend: "), i32(add_blend)), "   vblank: "), i32(vblank))))

        case 2:
            text(24, 56, GREY, 0.6, "Texture draw variants (all go through the C bridge)")
            if variant_tex != nil {
                for i in 0 ..< 19 {
                    col := i % 5
                    row := i / 5
                    cx := f32(col) * 192
                    cy := 66 + f32(row) * 114
                    v2d.DrawRectangle(cx + 2, cy + 2, 188, 110, v2d.RGBA8(0x1C, 0x20, 0x3C, 0xFF))
                    text(i32(cx) + 8, i32(cy) + 20, WHITE, 0.55, VARIANT_NAMES[i])
                    draw_variant(i32(i), variant_tex, cx, cy, angle)
                }
            }

        case 3:
            text(24, 56, WHITE, 0.7, "Cross: toggle LINEAR / POINT filter   (images drawn 2x)")
            Entry :: struct {
                name: cstring,
                tex:  ^v2d.Texture,
            }
            entries := [8]Entry{
                {"PNG buffer", png_buf}, {"PNG file", png_file}, {"JPEG buffer", jpg_buf}, {"JPEG file", jpg_file},
                {"BMP buffer", bmp_buf}, {"BMP file", bmp_file}, {"Empty RGBA", gen_tex}, {"Empty U8U8U8U8", fmt_tex},
            }
            for e, i in entries {
                col := i32(i % 4)
                row := i32(i / 4)
                x := 24 + col * 232
                y := 80 + row * 190
                text(x, y + 12, WHITE, 0.6, e.name)
                if e.tex == nil {
                    text(x, y + 40, RED, 0.8, "FAILED (nil)")
                    continue
                }
                v2d.DrawTextureScale(e.tex, f32(x), f32(y + 20), 2, 2)
                txt_reset(&t)
                txt_i(&t, i32(v2d.TextureWidth(e.tex)))
                txt_s(&t, "x")
                txt_i(&t, i32(v2d.TextureHeight(e.tex)))
                txt_s(&t, " stride ")
                txt_i(&t, i32(v2d.TextureStride(e.tex)))
                text(x, y + 168, GREY, 0.55, txt_c(&t))
            }
            if gray_tex != nil {
                v2d.DrawTexture(gray_tex, 860, 80)
                text(850, 170, WHITE, 0.55, "U8_R texture")
            }
            if png_buf != nil {
                txt_reset(&t)
                txt_s(&t, "format ")
                txt_h(&t, u32(v2d.TextureFormat(png_buf)))
                txt_s(&t, "  min ")
                txt_i(&t, i32(v2d.TextureMinFilter(png_buf)))
                txt_s(&t, "  mag ")
                txt_i(&t, i32(v2d.TextureMagFilter(png_buf)))
                txt_s(&t, "  palette ")
                txt_h(&t, u32(uintptr(v2d.TexturePalette(png_buf))))
                text(24, 480, WHITE, 0.6, txt_c(&t))
            }

        case 4:
            text(24, 66, WHITE, 0.7, "PVF: PvfDrawText, PvfDrawTextLs, PvfText{Width,Height,Dimensions}")
            if pvf != nil {
                v2d.PvfDrawText(pvf, 24, 110, WHITE, 1.0, "Default font, scale 1.0")
                v2d.PvfDrawText(pvf, 24, 150, CYAN, 1.8, "Scale 1.8")
                v2d.PvfDrawTextLs(pvf, 24, 200, 14, GREEN, 1.0, "Line spacing 14:\nsecond line\nthird line")
                w1 := v2d.PvfTextWidth(pvf, 1.0, "Default font, scale 1.0")
                h1 := v2d.PvfTextHeight(pvf, 1.0, "Default font, scale 1.0")
                dw, dh: i32
                v2d.PvfTextDimensions(pvf, 1.0, "Default font, scale 1.0", &dw, &dh)
                txt_reset(&t)
                txt_s(&t, "width ")
                txt_i(&t, w1)
                txt_s(&t, " height ")
                txt_i(&t, h1)
                txt_s(&t, "   dimensions ")
                txt_i(&t, dw)
                txt_s(&t, " x ")
                txt_i(&t, dh)
                text(24, 330, WHITE, 0.7, txt_c(&t))
                // The measured box around the first line.
                v2d.DrawLine(24, 112, 24 + f32(w1), 112, RED)
            }
            if pvf_sys != nil {
                v2d.PvfDrawText(pvf_sys, 24, 380, YELLOW, 1.0, "LoadSystemPvf font")
            } else {
                text(24, 380, RED, 0.8, "LoadSystemPvf returned nil")
            }
            if pvf_custom != nil {
                v2d.PvfDrawText(pvf_custom, 24, 420, YELLOW, 1.0, "LoadCustomPvf font (sa0:data/font/pvf/ltn0.pvf)")
            } else {
                text(24, 420, RED, 0.8, "LoadCustomPvf returned nil (sa0:data/font/pvf/ltn0.pvf)")
            }
            // Side by side: the same small text, stretched by vita2d and rasterised at size.
            if pvf != nil do v2d.PvfDrawText(pvf, 24, 456, WHITE, 0.7, "PvfDrawText scale 0.7: one 18 px bitmap shrunk on the GPU 0123456789")
            v2d.DrawText(24, 480, WHITE, 0.7, "DrawText 0.7: glyphs rasterised at this size 0123456789")

        case 5:
            text(24, 66, WHITE, 0.7, "FreeType: LoadFontMem / LoadFontFile, FontDrawText, FontDrawTextLs, FontText*")
            if ft_mem != nil {
                v2d.FontDrawText(ft_mem, 24, 130, WHITE, 28, "FreeType from memory, 28 px")
                v2d.FontDrawText(ft_mem, 24, 175, CYAN, 18, "18 px, from the embedded font")
                v2d.FontDrawTextLs(ft_mem, 24, 230, 8, GREEN, 22, "Line spacing 8:\nsecond line\nthird line")
                fw := v2d.FontTextWidth(ft_mem, 28, "FreeType from memory, 28 px")
                fh := v2d.FontTextHeight(ft_mem, 28, "FreeType from memory, 28 px")
                dw, dh: i32
                v2d.FontTextDimensions(ft_mem, 28, "FreeType from memory, 28 px", &dw, &dh)
                txt_reset(&t)
                txt_s(&t, "width ")
                txt_i(&t, fw)
                txt_s(&t, " height ")
                txt_i(&t, fh)
                txt_s(&t, "   dimensions ")
                txt_i(&t, dw)
                txt_s(&t, " x ")
                txt_i(&t, dh)
                text(24, 400, WHITE, 0.7, txt_c(&t))
                v2d.DrawLine(24, 134, 24 + f32(fw), 134, RED)
            } else {
                text(24, 130, RED, 0.8, "LoadFontMem returned nil")
            }
            if ft_file != nil {
                v2d.FontDrawText(ft_file, 24, 460, YELLOW, 24, "LoadFontFile: app0:/assets/font.ttf")
            } else {
                text(24, 440, RED, 0.8, "LoadFontFile returned nil")
            }

        case 6:
            if pgf_state == 0 {
                text(24, 120, WHITE, 0.9, "Press Cross to load the PGF fonts.")
                text(24, 150, GREY, 0.7, "The PGF functions are weak imports in vita2d: this may crash.")
                text(24, 170, GREY, 0.7, "The log shows how far it got.")
            } else {
                if pgf_default != nil {
                    v2d.PgfDrawText(pgf_default, 24, 130, WHITE, 1.0, "LoadDefaultPgf font")
                    v2d.PgfDrawTextLs(pgf_default, 24, 180, 12, GREEN, 1.0, "PgfDrawTextLs:\nsecond line")
                    pw := v2d.PgfTextWidth(pgf_default, 1.0, "LoadDefaultPgf font")
                    ph := v2d.PgfTextHeight(pgf_default, 1.0, "LoadDefaultPgf font")
                    dw, dh: i32
                    v2d.PgfTextDimensions(pgf_default, 1.0, "LoadDefaultPgf font", &dw, &dh)
                    txt_reset(&t)
                    txt_s(&t, "width ")
                    txt_i(&t, pw)
                    txt_s(&t, " height ")
                    txt_i(&t, ph)
                    txt_s(&t, "   dimensions ")
                    txt_i(&t, dw)
                    txt_s(&t, " x ")
                    txt_i(&t, dh)
                    text(24, 300, WHITE, 0.7, txt_c(&t))
                } else {
                    text(24, 130, RED, 0.8, "LoadDefaultPgf returned nil")
                }
                if pgf_system != nil {
                    v2d.PgfDrawText(pgf_system, 24, 360, YELLOW, 1.0, "LoadSystemPgf font")
                } else {
                    text(24, 360, RED, 0.8, "LoadSystemPgf returned nil")
                }
                if pgf_custom != nil {
                    v2d.PgfDrawText(pgf_custom, 24, 400, YELLOW, 1.0, "LoadCustomPgf font")
                } else {
                    text(24, 400, RED, 0.8, "LoadCustomPgf returned nil")
                }
            }

        case 7:
            if rt_state == 0 {
                text(24, 120, WHITE, 0.9, "Press Cross to create a render target and draw into it.")
                text(24, 150, GREY, 0.7, "CreateEmptyTextureRendertarget + StartDrawingAdvanced. May crash the GPU.")
            } else {
                text(24, 66, WHITE, 0.7, "The 192x144 texture is drawn offscreen, then shown below at 1x and 2x.")
                v2d.DrawTexture(rt, 40, 100)
                v2d.DrawTextureScale(rt, 300, 100, 2, 2)
                txt_reset(&t)
                txt_s(&t, "format ")
                txt_h(&t, u32(v2d.TextureFormat(rt)))
                txt_s(&t, "  size ")
                txt_i(&t, i32(v2d.TextureWidth(rt)))
                txt_s(&t, "x")
                txt_i(&t, i32(v2d.TextureHeight(rt)))
                text(24, 460, WHITE, 0.7, txt_c(&t))
            }
        }

        v2d.EndDrawing()
        v2d.SwapBuffers()
    }

    // Shutdown order matters on real hardware. The last frame is still queued on
    // the GPU and may be reading the textures, so wait for the GPU to go idle
    // before freeing anything it could be using.
    sce.sceClibPrintf("exit: waiting for GPU\n")
    v2d.WaitRenderingDone()
    sce.sceClibPrintf("exit: GPU idle, freeing\n")
    for tx in ([?]^v2d.Texture{png_buf, png_file, jpg_buf, jpg_file, bmp_buf, bmp_file, gen_tex, fmt_tex, gray_tex, rt}) {
        if tx != nil do v2d.FreeTexture(tx)
    }
    if ft_mem != nil     do v2d.FreeFont(ft_mem)
    if ft_file != nil    do v2d.FreeFont(ft_file)
    v2d.FreeSizedFonts()
    if pvf != nil        do v2d.FreePvf(pvf)
    if pvf_sys != nil    do v2d.FreePvf(pvf_sys)
    if pvf_custom != nil do v2d.FreePvf(pvf_custom)
    if pgf_default != nil do v2d.FreePgf(pgf_default)
    if pgf_system != nil  do v2d.FreePgf(pgf_system)
    if pgf_custom != nil  do v2d.FreePgf(pgf_custom)
    // vita2d_fini hangs inside Vita3K v0.2.1 (the real Vita runs it fine).
    if CALL_FINI {
        sce.sceClibPrintf("exit: vita2d fini\n")
        v2d.Fini()
    }
    sce.sceClibPrintf("exit: calling sceKernelExitProcess\n")
    sce.sceKernelExitProcess(0)
    return 0
}
