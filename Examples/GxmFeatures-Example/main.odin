package gxm_features_example

// The rest of SceGxm that Gxm-Example and Sprite-Example do not touch.
// Six pages, switched with L and R; each has its own text on screen.
//
//   1  stencil: a moving circle is written into the stencil buffer; the cube
//      is drawn solid inside it and as wireframe outside   (Triangle: on / off)
//   2  mipmaps: a floor whose texture has seven sizes, each a different
//      colour, so the size the GPU picks is visible          (Cross: on / off)
//   3  texture formats: the same picture as 32-bit linear, 32-bit swizzled,
//      16-bit, 8-bit with a palette, and DXT1 compressed
//   4  lines, points with a size each, and wireframe         (Up / Down: width)
//   5  instancing: 400 cubes in one draw call
//   6  region clip (scissor): drawing limited to a moving rectangle; on a
//      real Vita the OUTSIDE and INSIDE modes both keep the inside
//                                                            (Square: mode)
//
// Hold Start + Select for a second to exit. Start-up errors go to
// ux0:data/vito_gfx.log.

import "core:fmt"
import "core:math"
import "core:math/linalg"

import gfx  "../../lib/gfx"
import sce  "../../lib/sce"
import vito "../../lib/vito"

Mat4 :: linalg.Matrix4f32

Color_Vertex :: struct {
    position: [3]f32,
    color:    u32,
}

Texture_Vertex :: struct {
    position: [3]f32,
    uv:       [2]f32,
}

Point_Vertex :: struct {
    position: [3]f32,
    color:    u32,
    size:     f32,
}

Instance :: struct {
    offset: [4]f32, // xyz position, w size
    tint:   u32,
}

Mesh :: struct {
    vertices: rawptr,
    indices:  [^]u16,
    count:    u32,
}

POOL_SIZE :: 128 * 1024
pool:      [^]u8
pool_used: int

pool_alloc :: proc($T: typeid, count: int) -> [^]T {
    pool_used = (pool_used + 3) &~ 3
    result := ([^]T)(&pool[pool_used])
    pool_used += count * size_of(T)
    assert(pool_used <= POOL_SIZE, "mesh pool is full")
    return result
}

sequence_indices :: proc(count: int) -> [^]u16 {
    indices := pool_alloc(u16, count)
    for i in 0 ..< count do indices[i] = u16(i)
    return indices
}

make_cube :: proc(shade: bool) -> Mesh {
    Face :: struct { normal, u, v: [3]f32, color: u32 }
    faces := [6]Face{
        {{ 1, 0, 0}, {0, 1, 0}, {0, 0, 1}, 0xFF3030E0}, {{-1, 0, 0}, {0, 0, 1}, {0, 1, 0}, 0xFF30A0E0},
        {{ 0, 1, 0}, {0, 0, 1}, {1, 0, 0}, 0xFF30D030}, {{ 0,-1, 0}, {1, 0, 0}, {0, 0, 1}, 0xFFD0D030},
        {{ 0, 0, 1}, {1, 0, 0}, {0, 1, 0}, 0xFFE05030}, {{ 0, 0,-1}, {0, 1, 0}, {1, 0, 0}, 0xFFD030D0},
    }
    // For instancing the faces are shades of white, so the instance tint shows.
    shades := [6]u32{0xFFFFFFFF, 0xFFB0B0B0, 0xFFE0E0E0, 0xFF909090, 0xFFD0D0D0, 0xFFA0A0A0}
    corners := [4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}
    v := pool_alloc(Color_Vertex, 24)
    indices := pool_alloc(u16, 36)
    for face, f in faces {
        for c, i in corners {
            v[f * 4 + i] = {face.normal + face.u * c.x + face.v * c.y, shades[f] if shade else face.color}
        }
        for offset, i in ([6]u16{0, 1, 2, 0, 2, 3}) do indices[f * 6 + i] = u16(f * 4) + offset
    }
    return {v, indices, 36}
}

// A filled circle of radius 1 around the origin, as separate triangles.
make_disc :: proc(segments: int, color: u32) -> Mesh {
    v := pool_alloc(Color_Vertex, segments * 3)
    for i in 0 ..< segments {
        a0 := f32(i) / f32(segments) * math.TAU
        a1 := f32(i + 1) / f32(segments) * math.TAU
        v[i * 3 + 0] = {{0, 0, 0}, color}
        v[i * 3 + 1] = {{math.cos(a0), math.sin(a0), 0}, color}
        v[i * 3 + 2] = {{math.cos(a1), math.sin(a1), 0}, color}
    }
    return {v, sequence_indices(segments * 3), u32(segments * 3)}
}

// ---- the test picture ---------------------------------------------------
// Red grows to the right, green grows downwards, and a white L sits in the
// top left corner. A texture that comes out mirrored, turned, or with red
// and blue exchanged is then obvious.
PICTURE :: 64

picture_is_mark :: proc(x, y: int) -> bool {
    return (x >= 4 && x < 12 && y >= 4 && y < 28) || (y >= 20 && y < 28 && x >= 4 && x < 28)
}

picture_rgb :: proc(x, y: int) -> (r, g, b: u8) {
    if picture_is_mark(x, y) do return 255, 255, 255
    return u8(x * 255 / (PICTURE - 1)), u8(y * 255 / (PICTURE - 1)), 60
}

Format_Tile :: struct {
    name:    string,
    texture: gfx.Texture,
    ok:      bool,
    error:   i32,
}

make_format_tiles :: proc(tiles: ^[5]Format_Tile, palette_out: ^sce.UID) {
    // 32-bit, rows in order.
    tiles[0].name = "32-bit linear"
    tiles[0].texture, tiles[0].ok = gfx.create_texture(PICTURE, PICTURE, .POINT, .CLAMP)
    if !tiles[0].ok do tiles[0].error = gfx.last_alloc_error
    if tiles[0].ok {
        for y in 0 ..< PICTURE do for x in 0 ..< PICTURE {
            r, g, b := picture_rgb(x, y)
            tiles[0].texture.pixels[y * tiles[0].texture.stride + x] = gfx.rgba(r, g, b)
        }
    }

    // 32-bit, swizzled.
    tiles[1].name = "32-bit swizzled"
    tiles[1].texture, tiles[1].ok = gfx.create_texture_format(PICTURE, PICTURE, .U8U8U8U8_ABGR, PICTURE * PICTURE * 4, .Swizzled, 1, .POINT, .CLAMP)
    if !tiles[1].ok do tiles[1].error = gfx.last_alloc_error
    if tiles[1].ok {
        for y in 0 ..< PICTURE do for x in 0 ..< PICTURE {
            r, g, b := picture_rgb(x, y)
            tiles[1].texture.pixels[gfx.swizzle(u32(x), u32(y))] = gfx.rgba(r, g, b)
        }
    }

    // 16-bit: 5 bits red, 6 green, 5 blue.
    tiles[2].name = "16-bit 565"
    tiles[2].texture, tiles[2].ok = gfx.create_texture_format(PICTURE, PICTURE, .U5U6U5_RGB, PICTURE * PICTURE * 2, .Linear, 1, .POINT, .CLAMP)
    if !tiles[2].ok do tiles[2].error = gfx.last_alloc_error
    if tiles[2].ok {
        pixels := ([^]u16)(tiles[2].texture.pixels)
        for y in 0 ..< PICTURE do for x in 0 ..< PICTURE {
            r, g, b := picture_rgb(x, y)
            pixels[y * PICTURE + x] = u16(r >> 3) << 11 | u16(g >> 2) << 5 | u16(b >> 3)
        }
    }

    // 8-bit indices into a palette of 256 colours. The palette lives in GPU
    // memory too. Index = 16 levels of red by 15 of green, 255 is the mark.
    tiles[3].name = "8-bit palette"
    tiles[3].texture, tiles[3].ok = gfx.create_texture_format(PICTURE, PICTURE, .P8_ABGR, PICTURE * PICTURE, .Linear, 1, .POINT, .CLAMP)
    if !tiles[3].ok do tiles[3].error = gfx.last_alloc_error
    if tiles[3].ok {
        palette_memory, palette_uid := gfx.alloc(256 * 4)
        palette_out^ = palette_uid
        if palette_memory == nil {
            tiles[3].ok = false
        } else {
            palette := ([^]u32)(palette_memory)
            for i in 0 ..< 240 do palette[i] = gfx.rgba(u8((i % 16) * 17), u8((i / 16) * 18), 60)
            for i in 240 ..< 256 do palette[i] = gfx.WHITE
            sce.sceGxmTextureSetPalette(&tiles[3].texture.texture, palette_memory)
            pixels := ([^]u8)(tiles[3].texture.pixels)
            for y in 0 ..< PICTURE do for x in 0 ..< PICTURE {
                index := u8(x * 16 / PICTURE + (y * 15 / PICTURE) * 16)
                pixels[y * PICTURE + x] = 255 if picture_is_mark(x, y) else index
            }
        }
    }

    // DXT1 (UBC1): 4 x 4 pixel blocks of 8 bytes, the blocks in swizzled
    // order. Each block here is one colour: both end colours the same, every
    // pixel picking the first.
    tiles[4].name = "DXT1 compressed"
    BLOCKS :: PICTURE / 4
    tiles[4].texture, tiles[4].ok = gfx.create_texture_format(PICTURE, PICTURE, .UBC1_ABGR, BLOCKS * BLOCKS * 8, .Swizzled, 1, .POINT, .CLAMP)
    if !tiles[4].ok do tiles[4].error = gfx.last_alloc_error
    if tiles[4].ok {
        Block :: struct { color0, color1: u16, indices: u32 }
        blocks := ([^]Block)(tiles[4].texture.pixels)
        for by in 0 ..< BLOCKS do for bx in 0 ..< BLOCKS {
            r, g, b := picture_rgb(bx * 4 + 1, by * 4 + 1)
            c := u16(r >> 3) << 11 | u16(g >> 2) << 5 | u16(b >> 3)
            blocks[gfx.swizzle(u32(bx), u32(by))] = {c, c, 0}
        }
    }
}

// A 64 x 64 swizzled texture with all seven sizes, each its own colour; the
// full size one is a checkerboard.
MIP_LEVELS :: 7
make_mip_texture :: proc() -> (texture: gfx.Texture, ok: bool) {
    total := 0
    for level in 0 ..< MIP_LEVELS do total += (64 >> uint(level)) * (64 >> uint(level)) * 4
    texture = gfx.create_texture_format(64, 64, .U8U8U8U8_ABGR, total, .Swizzled, MIP_LEVELS, .LINEAR, .REPEAT) or_return
    colors := [MIP_LEVELS]u32{0, gfx.rgba(230, 60, 60), gfx.rgba(60, 200, 60), gfx.rgba(70, 90, 240),
                              gfx.rgba(240, 220, 50), gfx.rgba(220, 70, 220), gfx.rgba(60, 220, 220)}
    offset := 0
    for level in 0 ..< MIP_LEVELS {
        size := 64 >> uint(level)
        for y in 0 ..< size do for x in 0 ..< size {
            color := colors[level]
            if level == 0 do color = gfx.rgba(235, 235, 235) if (x / 8 + y / 8) % 2 == 0 else gfx.rgba(70, 70, 80)
            texture.pixels[offset + int(gfx.swizzle(u32(x), u32(y)))] = color
        }
        offset += size * size
    }
    return texture, true
}

fail :: proc(what: string) -> i32 {
    text := fmt.tprintf("%s\ninit step: %v\ninit error: 0x%08X\nalloc error: 0x%08X\nprogram error: 0x%08X\n",
        what, gfx.init_step, u32(gfx.init_error), u32(gfx.last_alloc_error), u32(gfx.last_program_error))
    vito.print(text)
    vito.write_entire_file("ux0:data/vito_gfx.log", transmute([]u8)text)
    return sce.sceKernelExitProcess(1)
}

draw_mesh :: proc(mesh: Mesh, primitive := sce.GxmPrimitiveType.TRIANGLES) {
    sce.sceGxmSetVertexStream(gfx.ctx, 0, mesh.vertices)
    sce.sceGxmDraw(gfx.ctx, primitive, .U16, mesh.indices, mesh.count)
}

@(export, link_name = "odin_main")
game_main :: proc "c" (argc: i32, argv: [^]cstring) -> i32 {
    context = vito.init()
    vito.input_init({})

    if !gfx.init({multisample = ._4X}) do return fail("gfx.init failed")
    if !gfx.draw2d_init() do return fail("gfx.draw2d_init failed")

    ok: bool
    font: gfx.Font
    if font, ok = gfx.load_font(#load("assets/font20.png"), #load("assets/font20.fnt")); !ok do return fail("font")

    // ---- programs ---------------------------------------------------------
    color_v, color_f, texture_v, texture_f, point_v, instance_v: gfx.Program
    if color_v, ok = gfx.register_program(#load("shaders/color_v.gxp")); !ok do return fail("color_v")
    if color_f, ok = gfx.register_program(#load("shaders/color_f.gxp")); !ok do return fail("color_f")
    if texture_v, ok = gfx.register_program(#load("shaders/texture_v.gxp")); !ok do return fail("texture_v")
    if texture_f, ok = gfx.register_program(#load("shaders/texture_f.gxp")); !ok do return fail("texture_f")
    if point_v, ok = gfx.register_program(#load("shaders/point_v.gxp")); !ok do return fail("point_v")
    if instance_v, ok = gfx.register_program(#load("shaders/instance_v.gxp")); !ok do return fail("instance_v")

    color_attributes := [?]sce.GxmVertexAttribute{
        gfx.attribute(color_v, "aPosition", u16(offset_of(Color_Vertex, position)), sce.GXM_ATTRIBUTE_FORMAT_F32, 3),
        gfx.attribute(color_v, "aColor",    u16(offset_of(Color_Vertex, color)),    sce.GXM_ATTRIBUTE_FORMAT_U8N, 4),
    }
    texture_attributes := [?]sce.GxmVertexAttribute{
        gfx.attribute(texture_v, "aPosition", u16(offset_of(Texture_Vertex, position)), sce.GXM_ATTRIBUTE_FORMAT_F32, 3),
        gfx.attribute(texture_v, "aTexcoord", u16(offset_of(Texture_Vertex, uv)),       sce.GXM_ATTRIBUTE_FORMAT_F32, 2),
    }
    point_attributes := [?]sce.GxmVertexAttribute{
        gfx.attribute(point_v, "aPosition", u16(offset_of(Point_Vertex, position)), sce.GXM_ATTRIBUTE_FORMAT_F32, 3),
        gfx.attribute(point_v, "aColor",    u16(offset_of(Point_Vertex, color)),    sce.GXM_ATTRIBUTE_FORMAT_U8N, 4),
        gfx.attribute(point_v, "aSize",     u16(offset_of(Point_Vertex, size)),     sce.GXM_ATTRIBUTE_FORMAT_F32, 1),
    }
    // Two streams: 0 is per vertex, 1 is per instance.
    instance_attributes := [?]sce.GxmVertexAttribute{
        gfx.attribute(instance_v, "aPosition", u16(offset_of(Color_Vertex, position)), sce.GXM_ATTRIBUTE_FORMAT_F32, 3, 0),
        gfx.attribute(instance_v, "aColor",    u16(offset_of(Color_Vertex, color)),    sce.GXM_ATTRIBUTE_FORMAT_U8N, 4, 0),
        gfx.attribute(instance_v, "aOffset",   u16(offset_of(Instance, offset)),       sce.GXM_ATTRIBUTE_FORMAT_F32, 4, 1),
        gfx.attribute(instance_v, "aTint",     u16(offset_of(Instance, tint)),         sce.GXM_ATTRIBUTE_FORMAT_U8N, 4, 1),
    }
    instance_streams := [?]sce.GxmVertexStream{
        {stride = size_of(Color_Vertex), indexSource = sce.GXM_INDEX_SOURCE_INDEX_16BIT},
        {stride = size_of(Instance),     indexSource = sce.GXM_INDEX_SOURCE_INSTANCE_16BIT},
    }
    color_vp    := gfx.create_vertex_program(color_v, color_attributes[:], size_of(Color_Vertex))
    texture_vp  := gfx.create_vertex_program(texture_v, texture_attributes[:], size_of(Texture_Vertex))
    point_vp    := gfx.create_vertex_program(point_v, point_attributes[:], size_of(Point_Vertex))
    instance_vp := gfx.create_vertex_program_streams(instance_v, instance_attributes[:], instance_streams[:])

    // Writes nothing to the colour buffer: for drawing into the stencil only.
    no_color := sce.GxmBlendInfo{colorMask = sce.GXM_COLOR_MASK_NONE}
    color_fp      := gfx.create_fragment_program(color_f, color_v)
    mask_fp       := gfx.create_fragment_program_blend(color_f, color_v, &no_color)
    texture_fp    := gfx.create_fragment_program(texture_f, texture_v)
    point_fp      := gfx.create_fragment_program(color_f, point_v)
    instance_fp   := gfx.create_fragment_program(color_f, instance_v)
    if color_vp == nil || texture_vp == nil || point_vp == nil || instance_vp == nil ||
       color_fp == nil || mask_fp == nil || texture_fp == nil || point_fp == nil || instance_fp == nil {
        return fail("creating a vertex or fragment program failed")
    }
    color_mvp     := gfx.parameter(color_v, "uMvp")
    texture_mvp   := gfx.parameter(texture_v, "uMvp")
    texture_tint  := gfx.parameter(texture_f, "uTint")
    texture_unit  := gfx.texture_unit(texture_f, "uTexture")
    point_mvp     := gfx.parameter(point_v, "uMvp")
    instance_mvp  := gfx.parameter(instance_v, "uMvp")
    instance_time := gfx.parameter(instance_v, "uTime")

    // ---- meshes -----------------------------------------------------------
    pool_memory, pool_uid := gfx.alloc(POOL_SIZE)
    if pool_memory == nil do return fail("mesh pool")
    pool = ([^]u8)(pool_memory)

    cube       := make_cube(false)
    white_cube := make_cube(true)
    disc       := make_disc(48, 0xFFFFFFFF)

    floor: Mesh
    {
        v := pool_alloc(Texture_Vertex, 4)
        v[0] = {{-30, -1.5,   0}, { 0,  0}}
        v[1] = {{ 30, -1.5,   0}, {40,  0}}
        v[2] = {{ 30, -1.5, -80}, {40, 54}}
        v[3] = {{-30, -1.5, -80}, { 0, 54}}
        indices := pool_alloc(u16, 6)
        for value, i in ([6]u16{0, 1, 2, 0, 2, 3}) do indices[i] = value
        floor = {v, indices, 6}
    }

    LINE_COUNT :: 24
    lines: Mesh
    {
        v := pool_alloc(Color_Vertex, LINE_COUNT * 2)
        for i in 0 ..< LINE_COUNT {
            angle := f32(i) / LINE_COUNT * math.TAU
            color := gfx.rgba(u8(128 + 127 * math.cos(angle)), u8(128 + 127 * math.sin(angle)), 220)
            v[i * 2 + 0] = {{math.cos(angle) * 0.25, math.sin(angle) * 0.25, 0}, color}
            v[i * 2 + 1] = {{math.cos(angle), math.sin(angle), 0}, color}
        }
        lines = {v, sequence_indices(LINE_COUNT * 2), LINE_COUNT * 2}
    }

    POINT_COUNT :: 40
    points: Mesh
    {
        v := pool_alloc(Point_Vertex, POINT_COUNT)
        for i in 0 ..< POINT_COUNT {
            angle := f32(i) / POINT_COUNT * math.TAU
            v[i] = {{math.cos(angle), math.sin(angle), 0},
                    gfx.rgba(255, u8(100 + 150 * i / POINT_COUNT), 60), 2 + f32(i % 10) * 2.5}
        }
        points = {v, sequence_indices(POINT_COUNT), POINT_COUNT}
    }

    GRID :: 20
    INSTANCES :: GRID * GRID
    instances := pool_alloc(Instance, INSTANCES)
    for i in 0 ..< INSTANCES {
        gx, gy := i % GRID, i / GRID
        instances[i] = {
            {(f32(gx) - (GRID - 1) * 0.5) * 0.9, (f32(gy) - (GRID - 1) * 0.5) * 0.5, 0, 0.16},
            gfx.rgba(u8(60 + gx * 195 / (GRID - 1)), u8(60 + gy * 195 / (GRID - 1)), 200),
        }
    }
    // The cube's 36 indices, repeated once per instance.
    instance_indices := pool_alloc(u16, 36 * INSTANCES)
    for i in 0 ..< 36 * INSTANCES do instance_indices[i] = white_cube.indices[i % 36]

    // ---- textures ---------------------------------------------------------
    tiles: [5]Format_Tile
    palette_uid: sce.UID = -1
    make_format_tiles(&tiles, &palette_uid)
    mip_texture, mip_ok := make_mip_texture()
    mip_error := gfx.last_alloc_error
    mip_count := sce.sceGxmTextureGetMipmapCount(&mip_texture.texture) if mip_ok else 0

    // ---- cameras ----------------------------------------------------------
    aspect := f32(gfx.WIDTH) / f32(gfx.HEIGHT)
    projection := linalg.matrix4_perspective_f32(math.to_radians(f32(50)), aspect, 0.1, 200)
    view := linalg.matrix4_translate_f32({0, 0, -6})
    pixels := linalg.matrix_ortho3d_f32(0, gfx.WIDTH, gfx.HEIGHT, 0, -1, 1)
    flat := linalg.matrix_ortho3d_f32(-aspect, aspect, -1, 1, -1, 1)

    PAGES :: 6
    page := 0
    stencil_on := true
    mips_on := true
    line_width := u32(3)
    clip_mode := sce.GxmRegionClipMode.OUTSIDE

    input: vito.Input
    timer: vito.Frame_Timer
    time: f32
    exit_hold := 0

    draw_color :: proc(vp: ^sce.GxmVertexProgram, fp: ^sce.GxmFragmentProgram, param: ^sce.GxmProgramParameter,
                       mvp: Mat4, mesh: Mesh, primitive := sce.GxmPrimitiveType.TRIANGLES) {
        mvp := mvp
        vertex_uniforms, _ := gfx.use_programs(vp, fp)
        gfx.set_uniform_matrix(vertex_uniforms, param, &mvp)
        draw_mesh(mesh, primitive)
    }

    GREY   := gfx.rgba(170, 170, 170)
    YELLOW := gfx.rgba(240, 220, 60)
    GREEN  := gfx.rgba(120, 250, 140)
    RED    := gfx.rgba(250, 100, 100)

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
        if vito.pressed(input, vito.BUTTON_TRIANGLE) do stencil_on = !stencil_on
        if vito.pressed(input, vito.BUTTON_CROSS) {
            mips_on = !mips_on
            if mip_ok do sce.sceGxmTextureSetMipFilter(&mip_texture.texture, .ENABLED if mips_on else .DISABLED)
        }
        if vito.pressed(input, vito.BUTTON_UP)   do line_width = min(line_width + 1, 16)
        if vito.pressed(input, vito.BUTTON_DOWN) do line_width = max(line_width - 1, 1)
        if vito.pressed(input, vito.BUTTON_SQUARE) {
            switch clip_mode {
            case .OUTSIDE: clip_mode = .INSIDE
            case .INSIDE:  clip_mode = .ALL
            case .ALL:     clip_mode = .NONE
            case .NONE:    clip_mode = .OUTSIDE
            }
        }

        rotation := linalg.matrix4_rotate_f32(time * 0.6, {0, 1, 0}) * linalg.matrix4_rotate_f32(time * 0.35, {1, 0, 0})
        cube_mvp := projection * view * rotation * linalg.matrix4_scale_f32({1.5, 1.5, 1.5})

        title, hint, info: string

        gfx.begin_frame()
        gfx.clear({0.05, 0.06, 0.10, 1})

        switch page {
        case 0:
            title = "1  Stencil"
            hint = "Triangle: stencil test on / off"
            info = fmt.tprintf("stencil test %s: solid inside the circle, wireframe outside", "ON" if stencil_on else "OFF")
            if stencil_on {
                // 1. The circle goes into the stencil buffer only: every pixel
                //    it covers gets the value 1. No colour, no depth.
                cx := f32(gfx.WIDTH) / 2 + math.cos(time * 0.9) * 200
                cy := f32(gfx.HEIGHT) / 2 + math.sin(time * 1.3) * 110
                sce.sceGxmSetFrontStencilRef(gfx.ctx, 1)
                sce.sceGxmSetFrontStencilFunc(gfx.ctx, .ALWAYS, .KEEP, .KEEP, .REPLACE, 0xFF, 0xFF)
                sce.sceGxmSetFrontDepthFunc(gfx.ctx, .ALWAYS)
                sce.sceGxmSetFrontDepthWriteEnable(gfx.ctx, .DISABLED)
                draw_color(color_vp, mask_fp, color_mvp,
                    pixels * linalg.matrix4_translate_f32({cx, cy, 0}) * linalg.matrix4_scale_f32({130, 130, 1}), disc)
                sce.sceGxmSetFrontDepthFunc(gfx.ctx, .LESS_EQUAL)
                sce.sceGxmSetFrontDepthWriteEnable(gfx.ctx, .ENABLED)

                // 2. Solid cube where the stencil is 1.
                sce.sceGxmSetFrontStencilFunc(gfx.ctx, .EQUAL, .KEEP, .KEEP, .KEEP, 0xFF, 0)
                draw_color(color_vp, color_fp, color_mvp, cube_mvp, cube)

                // 3. Wireframe cube where it is not.
                sce.sceGxmSetFrontStencilFunc(gfx.ctx, .NOT_EQUAL, .KEEP, .KEEP, .KEEP, 0xFF, 0)
                sce.sceGxmSetFrontPolygonMode(gfx.ctx, .TRIANGLE_LINE)
                draw_color(color_vp, color_fp, color_mvp, cube_mvp, cube)
                sce.sceGxmSetFrontPolygonMode(gfx.ctx, .TRIANGLE_FILL)
                sce.sceGxmSetFrontStencilFunc(gfx.ctx, .ALWAYS, .KEEP, .KEEP, .KEEP, 0xFF, 0xFF)
            } else {
                draw_color(color_vp, color_fp, color_mvp, cube_mvp, cube)
            }

        case 1:
            title = "2  Mipmaps"
            hint = "Cross: mipmaps on / off"
            if mip_ok {
                info = fmt.tprintf("mipmaps %s   levels reported: %d   near: checkerboard, then red, green, blue, yellow...",
                    "ON" if mips_on else "OFF", mip_count)
                mvp := projection * linalg.matrix4_translate_f32({0, 0, -1})
                vertex_uniforms, fragment_uniforms := gfx.use_programs(texture_vp, texture_fp)
                gfx.set_uniform_matrix(vertex_uniforms, texture_mvp, &mvp)
                gfx.set_uniform(fragment_uniforms, texture_tint, {1, 1, 1, 1})
                sce.sceGxmSetFragmentTexture(gfx.ctx, texture_unit, &mip_texture.texture)
                draw_mesh(floor)
            } else {
                info = fmt.tprintf("the mipmapped texture failed: 0x%08X", u32(mip_error))
            }

        case 2:
            title = "3  Texture formats"
            hint = "each should match the first: red grows right, green grows down, white L top left"

        case 3:
            title = "4  Lines, points, wireframe"
            hint = "Up / Down: line width"
            info = fmt.tprintf("line width %d", line_width)
            sce.sceGxmSetFrontPointLineWidth(gfx.ctx, line_width)

            sce.sceGxmSetFrontPolygonMode(gfx.ctx, .LINE)
            draw_color(color_vp, color_fp, color_mvp,
                flat * linalg.matrix4_translate_f32({-1.15, 0, 0}) * linalg.matrix4_rotate_f32(time * 0.3, {0, 0, 1}) * linalg.matrix4_scale_f32({0.45, 0.45, 1}),
                lines, .LINES)

            sce.sceGxmSetFrontPolygonMode(gfx.ctx, .POINT)
            draw_color(point_vp, point_fp, point_mvp,
                flat * linalg.matrix4_rotate_f32(-time * 0.4, {0, 0, 1}) * linalg.matrix4_scale_f32({0.45, 0.45, 1}),
                points, .POINTS)

            sce.sceGxmSetFrontPolygonMode(gfx.ctx, .TRIANGLE_LINE)
            draw_color(color_vp, color_fp, color_mvp,
                projection * view * linalg.matrix4_translate_f32({3.3, 0, 0}) * rotation, cube)
            sce.sceGxmSetFrontPolygonMode(gfx.ctx, .TRIANGLE_FILL)
            sce.sceGxmSetFrontPointLineWidth(gfx.ctx, 1)

        case 4:
            title = "5  Instancing"
            info = fmt.tprintf("%d cubes, one draw call, each with its own position, colour and turn", INSTANCES)
            mvp := projection * linalg.matrix4_translate_f32({0, 0, -13})
            seconds := [1]f32{time}
            vertex_uniforms, _ := gfx.use_programs(instance_vp, instance_fp)
            gfx.set_uniform_matrix(vertex_uniforms, instance_mvp, &mvp)
            gfx.set_uniform(vertex_uniforms, instance_time, seconds[:])
            sce.sceGxmSetVertexStream(gfx.ctx, 0, white_cube.vertices)
            sce.sceGxmSetVertexStream(gfx.ctx, 1, instances)
            sce.sceGxmDrawInstanced(gfx.ctx, .TRIANGLES, .U16, instance_indices, 36 * INSTANCES, 36)

        case 5:
            title = "6  Region clip"
            hint = "Square: next mode (OUTSIDE, INSIDE, ALL, NONE)"
            x0 := u32(280 + math.cos(time * 0.8) * 180)
            y0 := u32(180 + math.sin(time * 1.1) * 90)
            x1, y1 := x0 + 320, y0 + 200
            mode: string
            // On a real Vita OUTSIDE and INSIDE both keep only what is inside
            // the rectangle. What ALL does there is not recorded yet.
            switch clip_mode {
            case .OUTSIDE: mode = "OUTSIDE (keeps the inside)"
            case .INSIDE:  mode = "INSIDE (on hardware: also keeps the inside)"
            case .ALL:     mode = "ALL (not recorded yet)"
            case .NONE:    mode = "NONE (no clipping)"
            }
            info = fmt.tprintf("mode %s   rectangle %d,%d to %d,%d", mode, x0, y0, x1, y1)
            sce.sceGxmSetRegionClip(gfx.ctx, clip_mode, x0, y0, x1, y1)
            for i in 0 ..< 5 {
                offset := (f32(i) - 2) * 2.6
                draw_color(color_vp, color_fp, color_mvp, projection * view * linalg.matrix4_translate_f32({offset, 0, 0}) * rotation, cube)
            }
            sce.sceGxmSetRegionClip(gfx.ctx, .NONE, 0, 0, gfx.WIDTH - 1, gfx.HEIGHT - 1)
            // The exact rectangle asked for, to compare with what was clipped.
            gfx.begin_2d()
            gfx.draw_rect_lines(f32(x0), f32(y0), f32(x1 - x0), f32(y1 - y0), 1, YELLOW)
            gfx.end_2d()
        }

        // ---- text over every page ------------------------------------------
        gfx.begin_2d()
        if page == 2 {
            for &tile, i in tiles {
                x := 24 + f32(i) * 186
                if tile.ok {
                    gfx.draw_texture_ex(&tile.texture, {0, 0, PICTURE, PICTURE}, {x, 170, 160, 160})
                    gfx.draw_text(&font, x, 356, tile.name, GREEN)
                } else {
                    gfx.draw_rect_lines(x, 170, 160, 160, 1, RED)
                    gfx.draw_text(&font, x, 356, tile.name, RED)
                    gfx.draw_text(&font, x + 8, 250, fmt.tprintf("0x%08X", u32(tile.error)), RED)
                }
            }
        }
        gfx.draw_rect(0, 0, gfx.WIDTH, 84, gfx.rgba(0, 0, 0, 150))
        gfx.draw_text(&font, 24, 30, title, gfx.WHITE, 1.5)
        gfx.draw_text(&font, 24, 54, hint, YELLOW)
        gfx.draw_text(&font, 24, 76, info, GREY)
        gfx.draw_text(&font, 24, 530, fmt.tprintf("L / R: page %d of %d     %.0f fps     Hold Start + Select: exit", page + 1, PAGES, timer.fps),
            YELLOW if exit_hold > 0 else GREY)
        gfx.end_2d()

        gfx.end_frame()
        gfx.swap()
        free_all(context.temp_allocator)
    }

    gfx.finish()
    sce.sceGxmDisplayQueueFinish()
    if mip_ok do gfx.destroy_texture(&mip_texture)
    for &tile in tiles do if tile.ok do gfx.destroy_texture(&tile.texture)
    gfx.free(palette_uid)
    gfx.free(pool_uid)
    gfx.destroy_font(&font)
    for fp in ([]^sce.GxmFragmentProgram{instance_fp, point_fp, texture_fp, mask_fp, color_fp}) {
        sce.sceGxmShaderPatcherReleaseFragmentProgram(gfx.patcher, fp)
    }
    for vp in ([]^sce.GxmVertexProgram{instance_vp, point_vp, texture_vp, color_vp}) {
        sce.sceGxmShaderPatcherReleaseVertexProgram(gfx.patcher, vp)
    }
    for p in ([]^gfx.Program{&instance_v, &point_v, &texture_f, &texture_v, &color_f, &color_v}) do gfx.unregister_program(p)
    gfx.draw2d_shutdown()
    gfx.shutdown()

    vito.input_shutdown()
    vito.shutdown()
    sce.sceKernelExitProcess(0)
    return 0
}
