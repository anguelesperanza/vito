package sprite_example

// 2D on SceGxm without vita2d, through lib/gfx: batched sprites, shapes and
// text, drawn over a 3D scene in the same frame.
//
//   - a cube turning in the background (3D, own shader)
//   - sprites bouncing around: Up / Down adds or removes 200, Cross pauses
//   - one image drawn six ways: as it is, enlarged, turning about its centre,
//     mirrored, a quarter of it, tinted and see-through
//   - shapes: rectangle, outline, lines, triangle, circle, and glowing dots
//     that add their light together (additive blending)
//   - text from two baked atlases (20 and 40 pixels), with accents, colours,
//     scaling, and a box sized with measure_text
//   - a small picture drawn into a texture every frame with the same 2D calls,
//     then used as a sprite (bottom right)
//   - a line of numbers: frames per second, sprites, quads, draw calls
//
// The image is read from the VPK (app0:/assets/test.png) and decoded with
// libpng; the fonts are embedded with #load. The atlases were made with
//     python tools/make_font.py C:\Windows\Fonts\DejaVuSans.ttf 20 assets/font20 --chars latin1
//
// Hold Start + Select for a second to exit. Start-up errors go to
// ux0:data/vito_gfx.log.

import "core:fmt"
import "core:math"
import "core:math/linalg"

import gfx  "../../lib/gfx"
import sce  "../../lib/sce"
import vito "../../lib/vito"

Color_Vertex :: struct {
    position: [3]f32,
    color:    u32,
}

Bouncer :: struct {
    position, velocity: [2]f32,
    angle, spin:        f32,
    color:              gfx.Color,
}

MAX_BOUNCERS :: 4000
bouncers: [MAX_BOUNCERS]Bouncer

random_state: u32 = 0x2545F491
random :: proc() -> f32 { // 0 to 1
    random_state ~= random_state << 13
    random_state ~= random_state >> 17
    random_state ~= random_state << 5
    return f32(random_state & 0xFFFFFF) / f32(0x1000000)
}

fail :: proc(what: string) -> i32 {
    text := fmt.tprintf("%s\ninit step: %v\ninit error: 0x%08X\nalloc error: 0x%08X\nprogram error: 0x%08X\npng: %s\n",
        what, gfx.init_step, u32(gfx.init_error), u32(gfx.last_alloc_error), u32(gfx.last_program_error),
        cstring(&gfx.last_png_error[0]))
    vito.print(text)
    vito.write_entire_file("ux0:data/vito_gfx.log", transmute([]u8)text)
    return sce.sceKernelExitProcess(1)
}

@(export, link_name = "odin_main")
game_main :: proc "c" (argc: i32, argv: [^]cstring) -> i32 {
    context = vito.init()
    vito.input_init({})

    if !gfx.init({multisample = ._4X}) do return fail("gfx.init failed")
    if !gfx.draw2d_init() do return fail("gfx.draw2d_init failed")

    // ---- assets ---------------------------------------------------------
    ok: bool
    png_file: []u8
    if png_file, ok = vito.read_entire_file("app0:/assets/test.png"); !ok do return fail("reading app0:/assets/test.png")
    image: gfx.Texture
    if image, ok = gfx.load_png(png_file); !ok do return fail("decoding test.png")
    delete(png_file)

    font, big_font: gfx.Font
    if font, ok = gfx.load_font(#load("assets/font20.png"), #load("assets/font20.fnt")); !ok do return fail("font20")
    if big_font, ok = gfx.load_font(#load("assets/font40.png"), #load("assets/font40.fnt")); !ok do return fail("font40")

    target: gfx.Target
    if target, ok = gfx.create_target(128, 128); !ok do return fail("render target")

    // ---- the 3D cube in the background ------------------------------------
    color_v, color_f: gfx.Program
    if color_v, ok = gfx.register_program(#load("shaders/color_v.gxp")); !ok do return fail("color_v")
    if color_f, ok = gfx.register_program(#load("shaders/color_f.gxp")); !ok do return fail("color_f")
    attributes := [?]sce.GxmVertexAttribute{
        gfx.attribute(color_v, "aPosition", u16(offset_of(Color_Vertex, position)), sce.GXM_ATTRIBUTE_FORMAT_F32, 3),
        gfx.attribute(color_v, "aColor",    u16(offset_of(Color_Vertex, color)),    sce.GXM_ATTRIBUTE_FORMAT_U8N, 4),
    }
    color_vp := gfx.create_vertex_program(color_v, attributes[:], size_of(Color_Vertex))
    color_fp := gfx.create_fragment_program(color_f, color_v)
    if color_vp == nil || color_fp == nil do return fail("cube programs")
    color_mvp := gfx.parameter(color_v, "uMvp")

    cube_memory, cube_uid := gfx.alloc(24 * size_of(Color_Vertex) + 36 * size_of(u16))
    if cube_memory == nil do return fail("cube memory")
    cube_vertices := ([^]Color_Vertex)(cube_memory)
    cube_indices  := ([^]u16)(uintptr(cube_memory) + 24 * size_of(Color_Vertex))
    {
        Face :: struct { normal, u, v: [3]f32, color: u32 }
        faces := [6]Face{
            {{ 1, 0, 0}, {0, 1, 0}, {0, 0, 1}, 0xFF603020}, {{-1, 0, 0}, {0, 0, 1}, {0, 1, 0}, 0xFF704028},
            {{ 0, 1, 0}, {0, 0, 1}, {1, 0, 0}, 0xFF805030}, {{ 0,-1, 0}, {1, 0, 0}, {0, 0, 1}, 0xFF503020},
            {{ 0, 0, 1}, {1, 0, 0}, {0, 1, 0}, 0xFF906038}, {{ 0, 0,-1}, {0, 1, 0}, {1, 0, 0}, 0xFF402818},
        }
        corners := [4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}
        for face, f in faces {
            for c, i in corners do cube_vertices[f * 4 + i] = {face.normal + face.u * c.x + face.v * c.y, face.color}
            base := u16(f * 4)
            for offset, i in ([6]u16{0, 1, 2, 0, 2, 3}) do cube_indices[f * 6 + i] = base + offset
        }
    }
    projection := linalg.matrix4_perspective_f32(math.to_radians(f32(50)), f32(gfx.WIDTH) / f32(gfx.HEIGHT), 0.1, 100)
    view := linalg.matrix4_translate_f32({0, 0, -5})

    // ---- sprites ----------------------------------------------------------
    for &b in bouncers {
        b.position = {random() * gfx.WIDTH, random() * gfx.HEIGHT}
        b.velocity = {(random() - 0.5) * 300, (random() - 0.5) * 300}
        b.spin     = (random() - 0.5) * 4
        b.color    = gfx.rgba(u8(128 + random() * 127), u8(128 + random() * 127), u8(128 + random() * 127), 200)
    }
    bouncer_count := 200
    paused := false

    input: vito.Input
    timer: vito.Frame_Timer
    time: f32
    exit_hold := 0

    IW, IH := f32(image.width), f32(image.height)
    whole := gfx.Rect{0, 0, IW, IH}

    for {
        dt := vito.frame_tick(&timer)
        time += dt
        vito.input_update(&input)
        if vito.held(input, vito.BUTTON_START) && vito.held(input, vito.BUTTON_SELECT) {
            exit_hold += 1
            if exit_hold > 60 do break
        } else {
            exit_hold = 0
        }
        if vito.pressed(input, vito.BUTTON_UP)    do bouncer_count = min(bouncer_count + 200, MAX_BOUNCERS)
        if vito.pressed(input, vito.BUTTON_DOWN)  do bouncer_count = max(bouncer_count - 200, 0)
        if vito.pressed(input, vito.BUTTON_CROSS) do paused = !paused

        if !paused {
            for &b in bouncers[:bouncer_count] {
                b.position += b.velocity * dt
                b.angle += b.spin * dt
                if b.position.x < 0 || b.position.x > gfx.WIDTH  do b.velocity.x = -b.velocity.x
                if b.position.y < 0 || b.position.y > gfx.HEIGHT do b.velocity.y = -b.velocity.y
            }
        }

        // ---- a small picture drawn into a texture, with the 2D calls -------
        gfx.begin_target(&target)
        gfx.clear({0.1, 0.25, 0.2, 1})
        gfx.begin_2d()
        gfx.draw_circle(64, 64, 40 + math.sin(time * 3) * 12, gfx.rgba(240, 200, 60))
        gfx.draw_rect_lines(4, 4, 120, 120, 4, gfx.WHITE)
        gfx.draw_text(&font, 22, 72, "target", gfx.BLACK)
        gfx.end_2d()
        gfx.end_frame()

        // ---- the screen ------------------------------------------------------
        gfx.begin_frame()
        gfx.clear({0.05, 0.06, 0.10, 1})

        // 3D first.
        {
            model := linalg.matrix4_rotate_f32(time * 0.5, {0, 1, 0}) * linalg.matrix4_rotate_f32(time * 0.3, {1, 0, 0})
            mvp := projection * view * model
            vertex_uniforms, _ := gfx.use_programs(color_vp, color_fp)
            gfx.set_uniform_matrix(vertex_uniforms, color_mvp, &mvp)
            sce.sceGxmSetVertexStream(gfx.ctx, 0, cube_vertices)
            sce.sceGxmDraw(gfx.ctx, .TRIANGLES, .U16, cube_indices, 36)
        }

        // Then 2D on top of it.
        gfx.begin_2d()

        for b in bouncers[:bouncer_count] {
            gfx.draw_texture_ex(&image, whole, {b.position.x, b.position.y, 32, 32}, {16, 16}, b.angle, b.color)
        }

        // One image, six ways.
        y := f32(96)
        gfx.draw_texture(&image, 24, y)
        gfx.draw_texture_ex(&image, whole, {110, y, IW * 1.5, IH * 1.5})
        gfx.draw_texture_ex(&image, whole, {270, y + IH / 2, IW, IH}, {IW / 2, IH / 2}, time)
        gfx.draw_texture_ex(&image, whole, {330, y, IW, IH}, flip_x = true)
        gfx.draw_texture_ex(&image, {0, 0, IW / 2, IH / 2}, {420, y, IW, IH})
        gfx.draw_texture_ex(&image, whole, {510, y, IW, IH}, color = gfx.rgba(255, 120, 120, 140))
        labels := [6]string{"plain", "x 1.5", "turning", "mirrored", "a quarter", "tinted"}
        label_x := [6]f32{24, 110, 240, 330, 420, 510}
        for label, i in labels do gfx.draw_text(&font, label_x[i], y - 8, label, gfx.rgba(170, 170, 170))

        // Shapes.
        y = 250
        gfx.draw_rect(24, y, 90, 60, gfx.rgba(60, 120, 230))
        gfx.draw_rect_lines(130, y, 90, 60, 3, gfx.rgba(240, 220, 60))
        gfx.draw_line(240, y, 330, y + 60, 2, gfx.WHITE)
        gfx.draw_line(240, y + 60, 330, y, 6, gfx.rgba(240, 80, 80))
        gfx.draw_triangle({395, y}, {440, y + 60}, {350, y + 60}, gfx.rgba(80, 220, 120))
        gfx.draw_circle(500, y + 30, 30, gfx.rgba(230, 120, 240))

        // Lights that add up where they overlap.
        gfx.set_blend(.Additive)
        for i in 0 ..< 3 {
            angle := time * 1.5 + f32(i) * math.TAU / 3
            colors := [3]gfx.Color{gfx.rgba(255, 40, 40, 200), gfx.rgba(40, 255, 40, 200), gfx.rgba(40, 80, 255, 200)}
            gfx.draw_circle(640 + math.cos(angle) * 22, y + 30 + math.sin(angle) * 22, 34, colors[i])
        }
        gfx.set_blend(.Alpha)

        // Text.
        gfx.draw_text(&big_font, 24, 52, "Sprite example", gfx.WHITE)
        y = 360
        gfx.draw_text(&font, 24, y, "Text at its baked size: sharp. Größe, café, señor, ½ ©", gfx.WHITE)
        gfx.draw_text(&font, 24, y + 28, "Coloured, ", gfx.rgba(240, 220, 60))
        width, _ := gfx.measure_text(&font, "Coloured, ")
        gfx.draw_text(&font, 24 + width, y + 28, "and placed with measure_text.", gfx.rgba(120, 220, 250))
        gfx.draw_text(&font, 24, y + 66, "The same font at twice the size: softer.", gfx.WHITE, 2)
        gfx.draw_text(&big_font, 24, y + 112, "A 40 pixel atlas instead: sharp.", gfx.WHITE)

        boxed := "two lines,\nin a measured box"
        box_w, box_h := gfx.measure_text(&font, boxed)
        gfx.draw_rect(560, y - 22, box_w + 16, box_h + 12, gfx.rgba(0, 0, 0, 170))
        gfx.draw_rect_lines(560, y - 22, box_w + 16, box_h + 12, 1, gfx.rgba(200, 200, 200))
        gfx.draw_text(&font, 568, y, boxed, gfx.WHITE)

        // The texture drawn above, as a sprite.
        gfx.draw_texture_ex(&target.color, {0, 0, 128, 128}, {860, 440, 128, 128}, {64, 64}, math.sin(time) * 0.3)

        // Numbers, right-aligned.
        quads, batches := gfx.draw2d_stats()
        stats := fmt.tprintf("%.0f fps   %d sprites   %d quads in %d draw calls   dropped %d",
            timer.fps, bouncer_count, quads, batches, gfx.draw2d_dropped())
        stats_w, _ := gfx.measure_text(&font, stats)
        gfx.draw_rect(gfx.WIDTH - stats_w - 32, 14, stats_w + 16, 28, gfx.rgba(0, 0, 0, 170))
        gfx.draw_text(&font, gfx.WIDTH - stats_w - 24, 34, stats, gfx.rgba(120, 250, 140))

        gfx.draw_text(&font, 24, 530, "Up / Down: sprites    Cross: pause    Hold Start + Select: exit",
            gfx.rgba(240, 220, 60) if exit_hold > 0 else gfx.rgba(150, 150, 150))

        gfx.end_2d()
        gfx.end_frame()
        gfx.swap()
        free_all(context.temp_allocator)
    }

    gfx.finish()
    sce.sceGxmDisplayQueueFinish()
    gfx.destroy_target(&target)
    gfx.destroy_font(&big_font)
    gfx.destroy_font(&font)
    gfx.destroy_texture(&image)
    gfx.free(cube_uid)
    sce.sceGxmShaderPatcherReleaseFragmentProgram(gfx.patcher, color_fp)
    sce.sceGxmShaderPatcherReleaseVertexProgram(gfx.patcher, color_vp)
    gfx.unregister_program(&color_f)
    gfx.unregister_program(&color_v)
    gfx.draw2d_shutdown()
    gfx.shutdown()

    vito.input_shutdown()
    vito.shutdown()
    sce.sceKernelExitProcess(0)
    return 0
}
