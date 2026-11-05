package vita2d

// Bindings for libvita2d (vita/libvita2d in vdpm). Checked against
// %VITASDK%\arm-vita-eabi\include\vita2d.h.
//
// Functions with float parameters are bound to wrappers in bridge.c (named
// vito_vita2d_*) because Odin passes f32 in integer registers while vita2d
// expects VFP registers. From Odin they are called with ordinary f32 values.
// The remaining functions are bound directly.
//
// Build requirements (see NewProjectTemplate\build.bat):
//   - compile lib\vita2d\bridge.c with the other objects
//   - link: -lvita2d -lSceDisplay_stub -lSceGxm_stub -lSceSysmodule_stub
//           -lSceCtrl_stub -lScePgf_stub -lScePvf_stub -lSceCommonDialog_stub
//           -lfreetype -lpng16 -ljpeg -lz -lbz2 -lm

foreign import vita2d        "system:vita2d"
foreign import vita2d_bridge "system:vita2d_bridge"

// Opaque handles.
Texture :: struct {}
Pvf     :: struct {}

// RGBA8 packs a color for vita2d. Same layout as sce.Color32.
RGBA8 :: #force_inline proc "contextless" (r, g, b, a: u8) -> u32 {
    return u32(a) << 24 | u32(b) << 16 | u32(g) << 8 | u32(r)
}

@(default_calling_convention = "c")
foreign vita2d {
    // ---------------------------------------------------------------
    // Setup and frame control
    // ---------------------------------------------------------------
    @(link_name = "vita2d_init")                 Init                :: proc() -> i32 ---
    @(link_name = "vita2d_init_advanced")        InitAdvanced        :: proc(temp_pool_size: u32) -> i32 ---
    @(link_name = "vita2d_fini")                 Fini                :: proc() -> i32 ---
    @(link_name = "vita2d_wait_rendering_done")  WaitRenderingDone   :: proc() ---
    @(link_name = "vita2d_start_drawing")        StartDrawing        :: proc() ---
    @(link_name = "vita2d_end_drawing")          EndDrawing          :: proc() ---
    @(link_name = "vita2d_swap_buffers")         SwapBuffers         :: proc() ---
    @(link_name = "vita2d_clear_screen")         ClearScreen         :: proc() ---
    @(link_name = "vita2d_set_clear_color")      SetClearColor       :: proc(color: u32) ---
    @(link_name = "vita2d_get_clear_color")      GetClearColor       :: proc() -> u32 ---
    @(link_name = "vita2d_set_vblank_wait")      SetVblankWait       :: proc(enable: i32) ---
    @(link_name = "vita2d_common_dialog_update") CommonDialogUpdate  :: proc() -> i32 ---

    // ---------------------------------------------------------------
    // Clipping (integer arguments only)
    // ---------------------------------------------------------------
    @(link_name = "vita2d_enable_clipping")     EnableClipping    :: proc() ---
    @(link_name = "vita2d_disable_clipping")    DisableClipping   :: proc() ---
    @(link_name = "vita2d_get_clipping_enabled") ClippingEnabled  :: proc() -> i32 ---
    @(link_name = "vita2d_set_clip_rectangle")  SetClipRectangle  :: proc(x_min, y_min, x_max, y_max: i32) ---

    // ---------------------------------------------------------------
    // Textures (no float parameters)
    // ---------------------------------------------------------------
    @(link_name = "vita2d_load_PNG_file")       LoadPNGFile       :: proc(filename: cstring) -> ^Texture ---
    @(link_name = "vita2d_load_PNG_buffer")     LoadPNGBuffer     :: proc(buffer: rawptr) -> ^Texture ---
    @(link_name = "vita2d_load_JPEG_file")      LoadJPEGFile      :: proc(filename: cstring) -> ^Texture ---
    @(link_name = "vita2d_load_JPEG_buffer")    LoadJPEGBuffer    :: proc(buffer: rawptr, size: u32) -> ^Texture ---
    @(link_name = "vita2d_load_BMP_file")       LoadBMPFile       :: proc(filename: cstring) -> ^Texture ---
    @(link_name = "vita2d_load_BMP_buffer")     LoadBMPBuffer     :: proc(buffer: rawptr) -> ^Texture ---
    @(link_name = "vita2d_free_texture")        FreeTexture       :: proc(tex: ^Texture) ---
    @(link_name = "vita2d_texture_get_width")   TextureWidth      :: proc(tex: ^Texture) -> u32 ---
    @(link_name = "vita2d_texture_get_height")  TextureHeight     :: proc(tex: ^Texture) -> u32 ---
    @(link_name = "vita2d_texture_get_stride")  TextureStride     :: proc(tex: ^Texture) -> u32 ---
    @(link_name = "vita2d_texture_get_datap")   TextureData       :: proc(tex: ^Texture) -> rawptr ---
    @(link_name = "vita2d_texture_set_filters") TextureSetFilters :: proc(tex: ^Texture, min_filter, mag_filter: TextureFilter) ---

    // ---------------------------------------------------------------
    // PVF text
    // ---------------------------------------------------------------
    @(link_name = "vita2d_load_default_pvf")    LoadDefaultPvf    :: proc() -> ^Pvf ---
    @(link_name = "vita2d_free_pvf")            FreePvf           :: proc(font: ^Pvf) ---
}

// SceGxmTextureFilter
TextureFilter :: enum u32 {
    POINT         = 0,
    LINEAR        = 1,
    MIPMAP_LINEAR = 2,
    MIPMAP_POINT  = 3,
}

// Wrappers from bridge.c. The f32 parameters travel in integer registers,
// matching the uint32_t parameters on the C side.
@(default_calling_convention = "c")
foreign vita2d_bridge {
    // ---------------------------------------------------------------
    // Primitives
    // ---------------------------------------------------------------
    // DrawPixel is a 1x1 rectangle. DrawPoint is vita2d's raw GPU point, which
    // has no point size set and renders as a larger, unstable square on real hardware.
    @(link_name = "vito_vita2d_draw_pixel")       DrawPixel      :: proc(x, y: f32, color: u32) ---
    @(link_name = "vito_vita2d_draw_point")       DrawPoint      :: proc(x, y: f32, color: u32) ---
    @(link_name = "vito_vita2d_draw_line")        DrawLine       :: proc(x0, y0, x1, y1: f32, color: u32) ---
    @(link_name = "vito_vita2d_draw_rectangle")   DrawRectangle  :: proc(x, y, w, h: f32, color: u32) ---
    @(link_name = "vito_vita2d_draw_fill_circle") DrawFillCircle :: proc(x, y, radius: f32, color: u32) ---

    // ---------------------------------------------------------------
    // Textures
    // ---------------------------------------------------------------
    @(link_name = "vito_vita2d_draw_texture")                  DrawTexture                :: proc(tex: ^Texture, x, y: f32) ---
    @(link_name = "vito_vita2d_draw_texture_rotate")           DrawTextureRotate          :: proc(tex: ^Texture, x, y, rad: f32) ---
    @(link_name = "vito_vita2d_draw_texture_rotate_hotspot")   DrawTextureRotateHotspot   :: proc(tex: ^Texture, x, y, rad, center_x, center_y: f32) ---
    @(link_name = "vito_vita2d_draw_texture_scale")            DrawTextureScale           :: proc(tex: ^Texture, x, y, x_scale, y_scale: f32) ---
    @(link_name = "vito_vita2d_draw_texture_part")             DrawTexturePart            :: proc(tex: ^Texture, x, y, tex_x, tex_y, tex_w, tex_h: f32) ---
    @(link_name = "vito_vita2d_draw_texture_part_scale")       DrawTexturePartScale       :: proc(tex: ^Texture, x, y, tex_x, tex_y, tex_w, tex_h, x_scale, y_scale: f32) ---
    @(link_name = "vito_vita2d_draw_texture_scale_rotate")     DrawTextureScaleRotate     :: proc(tex: ^Texture, x, y, x_scale, y_scale, rad: f32) ---
    @(link_name = "vito_vita2d_draw_texture_tint")             DrawTextureTint            :: proc(tex: ^Texture, x, y: f32, color: u32) ---
    @(link_name = "vito_vita2d_draw_texture_tint_rotate")      DrawTextureTintRotate      :: proc(tex: ^Texture, x, y, rad: f32, color: u32) ---
    @(link_name = "vito_vita2d_draw_texture_tint_scale")       DrawTextureTintScale       :: proc(tex: ^Texture, x, y, x_scale, y_scale: f32, color: u32) ---
    @(link_name = "vito_vita2d_draw_texture_tint_scale_rotate") DrawTextureTintScaleRotate :: proc(tex: ^Texture, x, y, x_scale, y_scale, rad: f32, color: u32) ---

    // ---------------------------------------------------------------
    // PVF text. x and y are integers; scale is a float (1.0 = normal size).
    // ---------------------------------------------------------------
    @(link_name = "vito_vita2d_pvf_draw_text")   PvfDrawText   :: proc(font: ^Pvf, x, y: i32, color: u32, scale: f32, text: cstring) -> i32 ---
    @(link_name = "vito_vita2d_pvf_text_width")  PvfTextWidth  :: proc(font: ^Pvf, scale: f32, text: cstring) -> i32 ---
    @(link_name = "vito_vita2d_pvf_text_height") PvfTextHeight :: proc(font: ^Pvf, scale: f32, text: cstring) -> i32 ---
}
