package gxm_example

// Drawing with SceGxm directly (no vita2d), through the thin setup layer in
// lib/gfx. Five pages, switched with L and R:
//
//   1  a triangle with a colour per vertex, turning
//   2  a textured square and three translucent squares (alpha blending)
//        Cross switches the texture between smooth and blocky filtering
//   3  two coloured cubes passing through each other (depth test)
//        Triangle turns the depth test off and on
//        Square cycles face culling: none, clockwise, counter-clockwise
//   4  a textured cube lit by one moving light (a shader does the lighting)
//        the left stick turns the cube
//   5  page 1 drawn into a texture, and that texture shown on a cube
//
// There is no text (text is vita2d's job), so the top-left corner shows the
// state as squares: first row, the page; second row, in order: antialiasing
// on, depth test on, culling (none / CW / CCW), smooth filtering.
//
// The screen is antialiased (4x MSAA). Hold Select while the app starts to
// run without it. If start-up fails, the reason is in ux0:data/vito_gfx.log.
//
// The shaders are in shaders/*.cg, compiled to .gxp by
// tools/build_shaders.py and embedded with #load.
//
// Hold Start + Select for a second to exit.

import "core:fmt"
import "core:math"
import "core:math/linalg"

import gfx  "../../lib/gfx"
import sce  "../../lib/sce"
import vito "../../lib/vito"

Mat4 :: linalg.Matrix4f32
Vec3 :: linalg.Vector3f32

Color_Vertex :: struct {
    position: [3]f32,
    color:    u32, // 0xAABBGGRR
}

Texture_Vertex :: struct {
    position: [3]f32,
    uv:       [2]f32,
}

Lit_Vertex :: struct {
    position: [3]f32,
    normal:   [3]f32,
    uv:       [2]f32,
}

Mesh :: struct {
    vertices: rawptr,
    indices:  [^]u16,
    count:    u32,
}

// ---- GPU memory for the meshes: one block, handed out in pieces ----------
POOL_SIZE :: 64 * 1024
pool:      [^]u8
pool_used: int
pool_uid:  sce.UID

pool_alloc :: proc($T: typeid, count: int) -> [^]T {
    pool_used = (pool_used + 3) &~ 3
    result := ([^]T)(&pool[pool_used])
    pool_used += count * size_of(T)
    assert(pool_used <= POOL_SIZE, "mesh pool is full")
    return result
}

quad_indices :: proc(quads: int) -> [^]u16 {
    indices := pool_alloc(u16, quads * 6)
    for q in 0 ..< quads {
        base := u16(q * 4)
        indices[q * 6 + 0] = base
        indices[q * 6 + 1] = base + 1
        indices[q * 6 + 2] = base + 2
        indices[q * 6 + 3] = base
        indices[q * 6 + 4] = base + 2
        indices[q * 6 + 5] = base + 3
    }
    return indices
}

// A square from (0,0) to (1,1) in one colour.
make_color_quad :: proc(color: u32) -> Mesh {
    v := pool_alloc(Color_Vertex, 4)
    v[0] = {{0, 0, 0}, color}
    v[1] = {{1, 0, 0}, color}
    v[2] = {{1, 1, 0}, color}
    v[3] = {{0, 1, 0}, color}
    return {v, quad_indices(1), 6}
}

make_triangle :: proc() -> Mesh {
    v := pool_alloc(Color_Vertex, 3)
    v[0] = {{ 0.0,  0.8, 0}, 0xFF0000FF} // top, red
    v[1] = {{-0.7, -0.6, 0}, 0xFF00FF00} // left, green
    v[2] = {{ 0.7, -0.6, 0}, 0xFFFF0000} // right, blue
    indices := pool_alloc(u16, 3)
    indices[0], indices[1], indices[2] = 0, 1, 2
    return {v, indices, 3}
}

make_texture_quad :: proc() -> Mesh {
    v := pool_alloc(Texture_Vertex, 4)
    v[0] = {{0, 0, 0}, {0, 0}}
    v[1] = {{1, 0, 0}, {1, 0}}
    v[2] = {{1, 1, 0}, {1, 1}}
    v[3] = {{0, 1, 0}, {0, 1}}
    return {v, quad_indices(1), 6}
}

// The six faces of a cube from -1 to 1: the direction each faces, and two
// directions along it, chosen so the corners run counter-clockwise seen from
// outside.
Face :: struct {
    normal, u, v: [3]f32,
    color: u32,
}
FACES := [6]Face{
    {{ 1, 0, 0}, {0, 1, 0}, {0, 0, 1}, 0xFF3030E0}, // +x red
    {{-1, 0, 0}, {0, 0, 1}, {0, 1, 0}, 0xFF30A0E0}, // -x orange
    {{ 0, 1, 0}, {0, 0, 1}, {1, 0, 0}, 0xFF30D030}, // +y green
    {{ 0,-1, 0}, {1, 0, 0}, {0, 0, 1}, 0xFFD0D030}, // -y cyan
    {{ 0, 0, 1}, {1, 0, 0}, {0, 1, 0}, 0xFFE05030}, // +z blue
    {{ 0, 0,-1}, {0, 1, 0}, {1, 0, 0}, 0xFFD030D0}, // -z magenta
}
CORNERS := [4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}

make_color_cube :: proc() -> Mesh {
    v := pool_alloc(Color_Vertex, 24)
    for face, f in FACES {
        for c, i in CORNERS {
            v[f * 4 + i] = {face.normal + face.u * c.x + face.v * c.y, face.color}
        }
    }
    return {v, quad_indices(6), 36}
}

make_texture_cube :: proc() -> Mesh {
    v := pool_alloc(Texture_Vertex, 24)
    for face, f in FACES {
        for c, i in CORNERS {
            v[f * 4 + i] = {face.normal + face.u * c.x + face.v * c.y, {c.x * 0.5 + 0.5, 0.5 - c.y * 0.5}}
        }
    }
    return {v, quad_indices(6), 36}
}

make_lit_cube :: proc() -> Mesh {
    v := pool_alloc(Lit_Vertex, 24)
    for face, f in FACES {
        for c, i in CORNERS {
            v[f * 4 + i] = {face.normal + face.u * c.x + face.v * c.y, face.normal, {c.x + 1, 1 - c.y}}
        }
    }
    return {v, quad_indices(6), 36}
}

// An 8 x 8 board of coloured cells with a border, small enough that the
// difference between smooth and blocky filtering is obvious when enlarged.
fill_checker :: proc(texture: ^gfx.Texture) {
    CELLS := [4]u32{0xFFF0F0F0, 0xFF4040E0, 0xFF40C040, 0xFFE08040}
    for y in 0 ..< texture.height {
        for x in 0 ..< texture.width {
            cell := (x / 8 + (y / 8) * 3) % 4
            color := CELLS[cell]
            if x == 0 || y == 0 || x == texture.width - 1 || y == texture.height - 1 do color = 0xFF202020
            texture.pixels[y * texture.stride + x] = color
        }
    }
}

draw_mesh :: proc(mesh: Mesh) {
    sce.sceGxmSetVertexStream(gfx.ctx, 0, mesh.vertices)
    sce.sceGxmDraw(gfx.ctx, .TRIANGLES, .U16, mesh.indices, mesh.count)
}

fail :: proc(what: string) -> i32 {
    text := fmt.tprintf("%s\ninit step: %v\ninit error: 0x%08X\nalloc error: 0x%08X\nprogram error: 0x%08X\n",
        what, gfx.init_step, u32(gfx.init_error), u32(gfx.last_alloc_error), u32(gfx.last_program_error))
    vito.print(text)
    vito.write_entire_file("ux0:data/vito_gfx.log", transmute([]u8)text)
    return sce.sceKernelExitProcess(1)
}

@(export, link_name = "odin_main")
game_main :: proc "c" (argc: i32, argv: [^]cstring) -> i32 {
    context = vito.init()
    vito.input_init({})

    // Select held at start-up: no antialiasing.
    input: vito.Input
    vito.input_update(&input)
    antialias := !vito.held(input, vito.BUTTON_SELECT)

    if !gfx.init({multisample = ._4X if antialias else .NONE}) do return fail("gfx.init failed")

    // ---- programs -----------------------------------------------------
    ok: bool
    color_v, color_f, texture_v, texture_f, lit_v, lit_f: gfx.Program
    if color_v, ok = gfx.register_program(#load("shaders/color_v.gxp")); !ok do return fail("color_v")
    if color_f, ok = gfx.register_program(#load("shaders/color_f.gxp")); !ok do return fail("color_f")
    if texture_v, ok = gfx.register_program(#load("shaders/texture_v.gxp")); !ok do return fail("texture_v")
    if texture_f, ok = gfx.register_program(#load("shaders/texture_f.gxp")); !ok do return fail("texture_f")
    if lit_v, ok = gfx.register_program(#load("shaders/lit_v.gxp")); !ok do return fail("lit_v")
    if lit_f, ok = gfx.register_program(#load("shaders/lit_f.gxp")); !ok do return fail("lit_f")

    color_attributes := [?]sce.GxmVertexAttribute{
        gfx.attribute(color_v, "aPosition", u16(offset_of(Color_Vertex, position)), sce.GXM_ATTRIBUTE_FORMAT_F32, 3),
        gfx.attribute(color_v, "aColor",    u16(offset_of(Color_Vertex, color)),    sce.GXM_ATTRIBUTE_FORMAT_U8N, 4),
    }
    texture_attributes := [?]sce.GxmVertexAttribute{
        gfx.attribute(texture_v, "aPosition", u16(offset_of(Texture_Vertex, position)), sce.GXM_ATTRIBUTE_FORMAT_F32, 3),
        gfx.attribute(texture_v, "aTexcoord", u16(offset_of(Texture_Vertex, uv)),       sce.GXM_ATTRIBUTE_FORMAT_F32, 2),
    }
    lit_attributes := [?]sce.GxmVertexAttribute{
        gfx.attribute(lit_v, "aPosition", u16(offset_of(Lit_Vertex, position)), sce.GXM_ATTRIBUTE_FORMAT_F32, 3),
        gfx.attribute(lit_v, "aNormal",   u16(offset_of(Lit_Vertex, normal)),   sce.GXM_ATTRIBUTE_FORMAT_F32, 3),
        gfx.attribute(lit_v, "aTexcoord", u16(offset_of(Lit_Vertex, uv)),       sce.GXM_ATTRIBUTE_FORMAT_F32, 2),
    }
    color_vp   := gfx.create_vertex_program(color_v, color_attributes[:], size_of(Color_Vertex))
    texture_vp := gfx.create_vertex_program(texture_v, texture_attributes[:], size_of(Texture_Vertex))
    lit_vp     := gfx.create_vertex_program(lit_v, lit_attributes[:], size_of(Lit_Vertex))

    color_fp        := gfx.create_fragment_program(color_f, color_v)
    color_blend_fp  := gfx.create_fragment_program(color_f, color_v, .Alpha)
    color_target_fp := gfx.create_fragment_program(color_f, color_v, .None, sce.GxmMultisampleMode.NONE) // for page 5's texture
    texture_fp      := gfx.create_fragment_program(texture_f, texture_v)
    lit_fp          := gfx.create_fragment_program(lit_f, lit_v)
    if color_vp == nil || texture_vp == nil || lit_vp == nil || color_fp == nil || color_blend_fp == nil ||
       color_target_fp == nil || texture_fp == nil || lit_fp == nil {
        return fail("creating a vertex or fragment program failed")
    }

    color_mvp     := gfx.parameter(color_v, "uMvp")
    texture_mvp   := gfx.parameter(texture_v, "uMvp")
    texture_tint  := gfx.parameter(texture_f, "uTint")
    texture_unit  := gfx.texture_unit(texture_f, "uTexture")
    lit_mvp       := gfx.parameter(lit_v, "uMvp")
    lit_model     := gfx.parameter(lit_v, "uModel")
    lit_direction := gfx.parameter(lit_f, "uLightDirection")
    lit_color     := gfx.parameter(lit_f, "uLightColor")
    lit_ambient   := gfx.parameter(lit_f, "uAmbient")
    lit_unit      := gfx.texture_unit(lit_f, "uTexture")

    // ---- meshes, textures, the offscreen target -----------------------
    memory: rawptr
    memory, pool_uid = gfx.alloc(POOL_SIZE)
    if memory == nil do return fail("mesh pool")
    pool = ([^]u8)(memory)

    triangle      := make_triangle()
    color_cube    := make_color_cube()
    texture_cube  := make_texture_cube()
    lit_cube      := make_lit_cube()
    texture_quad  := make_texture_quad()
    white_quad    := make_color_quad(0xFFFFFFFF)
    grey_quad     := make_color_quad(0xFF505050)
    green_quad    := make_color_quad(0xFF40E040)
    glass_red     := make_color_quad(0x903030F0)
    glass_green   := make_color_quad(0x9030F030)
    glass_blue    := make_color_quad(0x90F03030)

    checker_smooth, checker_blocky: gfx.Texture
    if checker_smooth, ok = gfx.create_texture(32, 32, .LINEAR); !ok do return fail("texture")
    if checker_blocky, ok = gfx.create_texture(32, 32, .POINT); !ok do return fail("texture")
    fill_checker(&checker_smooth)
    fill_checker(&checker_blocky)

    target: gfx.Target
    if target, ok = gfx.create_target(256, 256); !ok do return fail("render target")

    // ---- cameras ------------------------------------------------------
    // Pixels, origin top left, for the flat pages and the status squares.
    screen := linalg.matrix_ortho3d_f32(0, gfx.WIDTH, gfx.HEIGHT, 0, -1, 1)
    projection := linalg.matrix4_perspective_f32(math.to_radians(f32(50)), f32(gfx.WIDTH) / f32(gfx.HEIGHT), 0.1, 100)
    view := linalg.matrix4_translate_f32({0, 0, -6})

    PAGES :: 5
    page := 0
    depth_test := true
    cull := sce.GxmCullMode.NONE
    smooth := true
    spin := [2]f32{0.6, 0.4}

    timer: vito.Frame_Timer
    time: f32
    exit_hold := 0

    draw_color :: proc(vp: ^sce.GxmVertexProgram, fp: ^sce.GxmFragmentProgram, param: ^sce.GxmProgramParameter, mvp: Mat4, mesh: Mesh) {
        mvp := mvp
        vertex_uniforms, _ := gfx.use_programs(vp, fp)
        gfx.set_uniform_matrix(vertex_uniforms, param, &mvp)
        draw_mesh(mesh)
    }

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
        if vito.pressed(input, vito.BUTTON_R) do page = (page + 1) % PAGES
        if vito.pressed(input, vito.BUTTON_L) do page = (page + PAGES - 1) % PAGES
        if vito.pressed(input, vito.BUTTON_CROSS)    do smooth = !smooth
        if vito.pressed(input, vito.BUTTON_TRIANGLE) do depth_test = !depth_test
        if vito.pressed(input, vito.BUTTON_SQUARE) {
            switch cull {
            case .NONE: cull = .CW
            case .CW:   cull = .CCW
            case .CCW:  cull = .NONE
            }
        }
        spin += input.left_stick * dt * 2

        triangle_model := linalg.matrix4_rotate_f32(time, {0, 0, 1})
        // The triangle is drawn in a square space from -1 to 1; on the wide
        // screen that needs the same number of pixels each way.
        triangle_screen := linalg.matrix_ortho3d_f32(-f32(gfx.WIDTH) / f32(gfx.HEIGHT), f32(gfx.WIDTH) / f32(gfx.HEIGHT), -1, 1, -1, 1)

        // ---- page 5 first draws into the texture ------------------------
        if page == 4 {
            gfx.begin_target(&target)
            gfx.clear({0.95, 0.85, 0.3, 1})
            square := linalg.matrix_ortho3d_f32(-1, 1, -1, 1, -1, 1)
            draw_color(color_vp, color_target_fp, color_mvp, square * triangle_model, triangle)
            gfx.end_frame()
        }

        // ---- the screen -------------------------------------------------
        gfx.begin_frame()
        gfx.clear({0.06, 0.07, 0.13, 1})

        switch page {
        case 0:
            draw_color(color_vp, color_fp, color_mvp, triangle_screen * triangle_model, triangle)

        case 1:
            // The texture, enlarged ten times.
            checker := &checker_smooth if smooth else &checker_blocky
            model := linalg.matrix4_translate_f32({80, 150, 0}) * linalg.matrix4_scale_f32({320, 320, 1})
            mvp := screen * model
            vertex_uniforms, fragment_uniforms := gfx.use_programs(texture_vp, texture_fp)
            gfx.set_uniform_matrix(vertex_uniforms, texture_mvp, &mvp)
            gfx.set_uniform(fragment_uniforms, texture_tint, {1, 1, 1, 1})
            sce.sceGxmSetFragmentTexture(gfx.ctx, texture_unit, &checker.texture)
            draw_mesh(texture_quad)

            // Three translucent squares over a white one; where they overlap
            // the colours mix. They move so the blending is easy to see.
            draw_color(color_vp, color_fp, color_mvp,
                screen * linalg.matrix4_translate_f32({520, 170, 0}) * linalg.matrix4_scale_f32({340, 280, 1}), white_quad)
            glass := [3]Mesh{glass_red, glass_green, glass_blue}
            for mesh, i in glass {
                angle := time + f32(i) * 2.1
                x := 620 + math.cos(angle) * 60
                y := 240 + math.sin(angle) * 60
                draw_color(color_vp, color_blend_fp, color_mvp,
                    screen * linalg.matrix4_translate_f32({x, y, 0}) * linalg.matrix4_scale_f32({140, 140, 1}), mesh)
            }

        case 2:
            sce.sceGxmSetCullMode(gfx.ctx, cull)
            sce.sceGxmSetFrontDepthFunc(gfx.ctx, .LESS_EQUAL if depth_test else .ALWAYS)
            rotation := linalg.matrix4_rotate_f32(time * 0.7, {0, 1, 0}) * linalg.matrix4_rotate_f32(time * 0.4, {1, 0, 0})
            offset := math.sin(time) * 1.2
            // Drawn far one first, so without the depth test the picture is wrong.
            draw_color(color_vp, color_fp, color_mvp,
                projection * view * linalg.matrix4_translate_f32({offset, 0, 0.8}) * rotation, color_cube)
            draw_color(color_vp, color_fp, color_mvp,
                projection * view * linalg.matrix4_translate_f32({-offset, 0, -0.8}) * rotation, color_cube)
            sce.sceGxmSetCullMode(gfx.ctx, .NONE)
            sce.sceGxmSetFrontDepthFunc(gfx.ctx, .LESS_EQUAL)

        case 3:
            model := linalg.matrix4_rotate_f32(spin.x, {0, 1, 0}) * linalg.matrix4_rotate_f32(spin.y, {1, 0, 0}) *
                     linalg.matrix4_scale_f32({1.4, 1.4, 1.4})
            mvp := projection * view * model
            vertex_uniforms, fragment_uniforms := gfx.use_programs(lit_vp, lit_fp)
            gfx.set_uniform_matrix(vertex_uniforms, lit_mvp, &mvp)
            gfx.set_uniform_matrix(vertex_uniforms, lit_model, &model)
            // The light circles the cube, a little above it.
            gfx.set_uniform(fragment_uniforms, lit_direction, {math.cos(time), 0.6, math.sin(time)})
            gfx.set_uniform(fragment_uniforms, lit_color, {1.0, 0.95, 0.85})
            gfx.set_uniform(fragment_uniforms, lit_ambient, {0.15, 0.15, 0.2})
            sce.sceGxmSetFragmentTexture(gfx.ctx, lit_unit, &checker_smooth.texture)
            draw_mesh(lit_cube)

        case 4:
            model := linalg.matrix4_rotate_f32(time * 0.6, {0, 1, 0}) * linalg.matrix4_rotate_f32(time * 0.35, {1, 0, 0}) *
                     linalg.matrix4_scale_f32({1.5, 1.5, 1.5})
            mvp := projection * view * model
            vertex_uniforms, fragment_uniforms := gfx.use_programs(texture_vp, texture_fp)
            gfx.set_uniform_matrix(vertex_uniforms, texture_mvp, &mvp)
            gfx.set_uniform(fragment_uniforms, texture_tint, {1, 1, 1, 1})
            sce.sceGxmSetFragmentTexture(gfx.ctx, texture_unit, &target.color.texture)
            draw_mesh(texture_cube)
        }

        // ---- status squares, on top of everything ------------------------
        sce.sceGxmSetFrontDepthFunc(gfx.ctx, .ALWAYS)
        square :: proc(vp: ^sce.GxmVertexProgram, fp: ^sce.GxmFragmentProgram, param: ^sce.GxmProgramParameter,
                       screen: Mat4, column, row: int, mesh: Mesh) {
            mvp := screen * linalg.matrix4_translate_f32({16 + f32(column) * 26, 14 + f32(row) * 26, 0}) * linalg.matrix4_scale_f32({20, 20, 1})
            vertex_uniforms, _ := gfx.use_programs(vp, fp)
            gfx.set_uniform_matrix(vertex_uniforms, param, &mvp)
            draw_mesh(mesh)
        }
        for i in 0 ..< PAGES {
            square(color_vp, color_fp, color_mvp, screen, i, 0, white_quad if i == page else grey_quad)
        }
        square(color_vp, color_fp, color_mvp, screen, 0, 1, green_quad if antialias else grey_quad)
        square(color_vp, color_fp, color_mvp, screen, 2, 1, green_quad if depth_test else grey_quad)
        square(color_vp, color_fp, color_mvp, screen, 4, 1, white_quad if cull == .NONE else grey_quad)
        square(color_vp, color_fp, color_mvp, screen, 5, 1, white_quad if cull == .CW else grey_quad)
        square(color_vp, color_fp, color_mvp, screen, 6, 1, white_quad if cull == .CCW else grey_quad)
        square(color_vp, color_fp, color_mvp, screen, 8, 1, green_quad if smooth else grey_quad)
        if exit_hold > 0 do square(color_vp, color_fp, color_mvp, screen, 10, 0, glass_red)
        sce.sceGxmSetFrontDepthFunc(gfx.ctx, .LESS_EQUAL)

        gfx.end_frame()
        gfx.swap()
        free_all(context.temp_allocator)
    }

    // The GPU must be idle before anything it used is released.
    gfx.finish()
    sce.sceGxmDisplayQueueFinish()
    gfx.destroy_target(&target)
    gfx.destroy_texture(&checker_blocky)
    gfx.destroy_texture(&checker_smooth)
    gfx.free(pool_uid)
    sce.sceGxmShaderPatcherReleaseFragmentProgram(gfx.patcher, lit_fp)
    sce.sceGxmShaderPatcherReleaseFragmentProgram(gfx.patcher, texture_fp)
    sce.sceGxmShaderPatcherReleaseFragmentProgram(gfx.patcher, color_target_fp)
    sce.sceGxmShaderPatcherReleaseFragmentProgram(gfx.patcher, color_blend_fp)
    sce.sceGxmShaderPatcherReleaseFragmentProgram(gfx.patcher, color_fp)
    sce.sceGxmShaderPatcherReleaseVertexProgram(gfx.patcher, lit_vp)
    sce.sceGxmShaderPatcherReleaseVertexProgram(gfx.patcher, texture_vp)
    sce.sceGxmShaderPatcherReleaseVertexProgram(gfx.patcher, color_vp)
    for p in ([]^gfx.Program{&lit_f, &lit_v, &texture_f, &texture_v, &color_f, &color_v}) do gfx.unregister_program(p)
    gfx.shutdown()

    vito.input_shutdown()
    vito.shutdown()
    sce.sceKernelExitProcess(0)
    return 0
}
