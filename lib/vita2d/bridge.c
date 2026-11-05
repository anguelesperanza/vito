// ABI bridge for vita2d functions that take float parameters.
//
// Odin passes f32 arguments in integer registers (r0-r3, then the stack).
// vita2d is compiled hard-float and expects them in VFP registers. Each
// wrapper here takes every float as uint32_t (integer register / stack slot,
// which both sides agree on) and converts with u2f() before calling the real
// function. Functions with no float parameters are bound directly from Odin.

#include <vita2d.h>
#include "../bridge_utils.h"

// ---------------------------------------------------------------
// Primitives
// ---------------------------------------------------------------
// vita2d_draw_pixel draws a GXM POINTS primitive and never sets a point size.
// Vita3K draws 1 px, but real hardware drew a larger, flickering square. The
// binding's DrawPixel therefore draws a 1x1 rectangle (normal triangle path).
// The raw point version is kept as vito_vita2d_draw_point.
void vito_vita2d_draw_pixel(uint32_t x, uint32_t y, unsigned int color) {
    vita2d_draw_rectangle(u2f(x), u2f(y), 1.0f, 1.0f, color);
}

void vito_vita2d_draw_point(uint32_t x, uint32_t y, unsigned int color) {
    vita2d_draw_pixel(u2f(x), u2f(y), color);
}

void vito_vita2d_draw_line(uint32_t x0, uint32_t y0, uint32_t x1, uint32_t y1, unsigned int color) {
    vita2d_draw_line(u2f(x0), u2f(y0), u2f(x1), u2f(y1), color);
}

void vito_vita2d_draw_rectangle(uint32_t x, uint32_t y, uint32_t w, uint32_t h, unsigned int color) {
    vita2d_draw_rectangle(u2f(x), u2f(y), u2f(w), u2f(h), color);
}

void vito_vita2d_draw_fill_circle(uint32_t x, uint32_t y, uint32_t radius, unsigned int color) {
    vita2d_draw_fill_circle(u2f(x), u2f(y), u2f(radius), color);
}

// ---------------------------------------------------------------
// Textures
// ---------------------------------------------------------------
void vito_vita2d_draw_texture(const vita2d_texture *tex, uint32_t x, uint32_t y) {
    vita2d_draw_texture(tex, u2f(x), u2f(y));
}

void vito_vita2d_draw_texture_rotate(const vita2d_texture *tex, uint32_t x, uint32_t y, uint32_t rad) {
    vita2d_draw_texture_rotate(tex, u2f(x), u2f(y), u2f(rad));
}

void vito_vita2d_draw_texture_rotate_hotspot(const vita2d_texture *tex, uint32_t x, uint32_t y, uint32_t rad,
                                             uint32_t cx, uint32_t cy) {
    vita2d_draw_texture_rotate_hotspot(tex, u2f(x), u2f(y), u2f(rad), u2f(cx), u2f(cy));
}

void vito_vita2d_draw_texture_scale(const vita2d_texture *tex, uint32_t x, uint32_t y, uint32_t xs, uint32_t ys) {
    vita2d_draw_texture_scale(tex, u2f(x), u2f(y), u2f(xs), u2f(ys));
}

void vito_vita2d_draw_texture_part(const vita2d_texture *tex, uint32_t x, uint32_t y,
                                   uint32_t tx, uint32_t ty, uint32_t tw, uint32_t th) {
    vita2d_draw_texture_part(tex, u2f(x), u2f(y), u2f(tx), u2f(ty), u2f(tw), u2f(th));
}

void vito_vita2d_draw_texture_part_scale(const vita2d_texture *tex, uint32_t x, uint32_t y,
                                         uint32_t tx, uint32_t ty, uint32_t tw, uint32_t th,
                                         uint32_t xs, uint32_t ys) {
    vita2d_draw_texture_part_scale(tex, u2f(x), u2f(y), u2f(tx), u2f(ty), u2f(tw), u2f(th), u2f(xs), u2f(ys));
}

void vito_vita2d_draw_texture_scale_rotate(const vita2d_texture *tex, uint32_t x, uint32_t y,
                                           uint32_t xs, uint32_t ys, uint32_t rad) {
    vita2d_draw_texture_scale_rotate(tex, u2f(x), u2f(y), u2f(xs), u2f(ys), u2f(rad));
}

void vito_vita2d_draw_texture_tint(const vita2d_texture *tex, uint32_t x, uint32_t y, unsigned int color) {
    vita2d_draw_texture_tint(tex, u2f(x), u2f(y), color);
}

void vito_vita2d_draw_texture_tint_rotate(const vita2d_texture *tex, uint32_t x, uint32_t y, uint32_t rad,
                                          unsigned int color) {
    vita2d_draw_texture_tint_rotate(tex, u2f(x), u2f(y), u2f(rad), color);
}

void vito_vita2d_draw_texture_tint_scale(const vita2d_texture *tex, uint32_t x, uint32_t y,
                                         uint32_t xs, uint32_t ys, unsigned int color) {
    vita2d_draw_texture_tint_scale(tex, u2f(x), u2f(y), u2f(xs), u2f(ys), color);
}

void vito_vita2d_draw_texture_tint_scale_rotate(const vita2d_texture *tex, uint32_t x, uint32_t y,
                                                uint32_t xs, uint32_t ys, uint32_t rad, unsigned int color) {
    vita2d_draw_texture_tint_scale_rotate(tex, u2f(x), u2f(y), u2f(xs), u2f(ys), u2f(rad), color);
}

// ---------------------------------------------------------------
// PVF (system vector font) text
// ---------------------------------------------------------------
int vito_vita2d_pvf_draw_text(vita2d_pvf *font, int x, int y, unsigned int color, uint32_t scale, const char *text) {
    return vita2d_pvf_draw_text(font, x, y, color, u2f(scale), text);
}

int vito_vita2d_pvf_text_width(vita2d_pvf *font, uint32_t scale, const char *text) {
    return vita2d_pvf_text_width(font, u2f(scale), text);
}

int vito_vita2d_pvf_text_height(vita2d_pvf *font, uint32_t scale, const char *text) {
    return vita2d_pvf_text_height(font, u2f(scale), text);
}
