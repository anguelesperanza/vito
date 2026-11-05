package sce

// Bindings for the PS Vita (VitaSDK). Struct layouts and constants were
// checked against the headers in %VITASDK%\arm-vita-eabi\include\psp2*.

foreign import sce_ctrl    "system:SceCtrl_stub"
foreign import sce_display "system:SceDisplay_stub"
foreign import sce_sysmem  "system:SceSysmem_stub"
foreign import sce_kernel  "system:SceLibKernel_stub"

// ---------------------------------------------------------------
// Controller  (psp2/ctrl.h, psp2common/ctrl.h)
// ---------------------------------------------------------------
CTRL_SELECT   :: u32(0x00000001)
CTRL_L3       :: u32(0x00000002)
CTRL_R3       :: u32(0x00000004)
CTRL_START    :: u32(0x00000008)
CTRL_UP       :: u32(0x00000010)
CTRL_RIGHT    :: u32(0x00000020)
CTRL_DOWN     :: u32(0x00000040)
CTRL_LEFT     :: u32(0x00000080)
CTRL_LTRIGGER :: u32(0x00000100)
CTRL_RTRIGGER :: u32(0x00000200)
CTRL_L1       :: u32(0x00000400)
CTRL_R1       :: u32(0x00000800)
CTRL_TRIANGLE :: u32(0x00001000)
CTRL_CIRCLE   :: u32(0x00002000)
CTRL_CROSS    :: u32(0x00004000)
CTRL_SQUARE   :: u32(0x00008000)

// 32 bytes. The per-button fields (up..square) are analogue pressure values.
CtrlData :: struct {
    timeStamp: u64,
    buttons:   u32,
    lx, ly:    u8,
    rx, ry:    u8,
    up, right, down, left:           u8,
    lt, rt, l1, r1:                  u8,
    triangle, circle, cross, square: u8,
    reserved:  [4]u8,
}
#assert(size_of(CtrlData) == 32)

CtrlSamplingMode :: enum i32 {
    DIGITAL     = 0,
    ANALOG      = 1,
    ANALOG_WIDE = 2,
}

@(default_calling_convention = "c")
foreign sce_ctrl {
    sceCtrlSetSamplingMode    :: proc(mode: CtrlSamplingMode) -> i32 ---
    sceCtrlPeekBufferPositive :: proc(port: i32, pad_data: ^CtrlData, count: i32) -> i32 ---
}

// ---------------------------------------------------------------
// Display  (psp2common/display.h)
// ---------------------------------------------------------------
DISPLAY_WIDTH  :: 960
DISPLAY_HEIGHT :: 544

// Pixels are u32 laid out 0xAABBGGRR.
DISPLAY_PIXELFORMAT_A8B8G8R8 :: u32(0)

DisplaySetBufSync :: enum u32 {
    IMMEDIATE = 0,
    NEXTFRAME = 1,
}

DisplayFrameBuf :: struct {
    size:        u32,    // sizeof(DisplayFrameBuf)
    base:        rawptr,
    pitch:       u32,    // in pixels
    pixelformat: u32,
    width:       u32,
    height:      u32,
}
#assert(size_of(DisplayFrameBuf) == 24)

@(default_calling_convention = "c")
foreign sce_display {
    sceDisplaySetFrameBuf     :: proc(param: ^DisplayFrameBuf, sync: DisplaySetBufSync) -> i32 ---
    sceDisplayWaitVblankStart :: proc() -> i32 ---
}

// ---------------------------------------------------------------
// Memory  (psp2/kernel/sysmem.h)
// ---------------------------------------------------------------
MEMBLOCK_TYPE_USER_RW       :: u32(0x0C20D060)
MEMBLOCK_TYPE_USER_CDRAM_RW :: u32(0x09408060)

// CDRAM blocks must be a multiple of 256 KiB.
CDRAM_ALIGNMENT :: 256 * 1024

@(default_calling_convention = "c")
foreign sce_sysmem {
    sceKernelAllocMemBlock   :: proc(name: cstring, type: u32, size: u32, opt: rawptr) -> i32 ---
    sceKernelFreeMemBlock    :: proc(uid: i32) -> i32 ---
    sceKernelGetMemBlockBase :: proc(uid: i32, base: ^rawptr) -> i32 ---
}

// ---------------------------------------------------------------
// Kernel
// ---------------------------------------------------------------
@(default_calling_convention = "c")
foreign sce_kernel {
    sceKernelExitProcess :: proc(res: i32) -> i32 ---
    sceKernelDelayThread :: proc(delay: u32) -> i32 ---
    sceClibPrintf        :: proc(fmt: cstring, #c_vararg args: ..any) -> i32 ---
}

// ---------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------

// Color32 packs a pixel for DISPLAY_PIXELFORMAT_A8B8G8R8.
Color32 :: #force_inline proc "contextless" (r, g, b, a: u8) -> u32 {
    return u32(a) << 24 | u32(b) << 16 | u32(g) << 8 | u32(r)
}
