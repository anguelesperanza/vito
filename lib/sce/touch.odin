package sce

// Touch panel bindings (psp2/touch.h). Struct layouts and enum values were
// checked against the VitaSDK header, which pins the sizes asserted below.
// Link with -lSceTouch_stub. All arguments are integers, so no float bridge.

foreign import sce_touch "system:SceTouch_stub"

TOUCH_PORT_FRONT :: u32(0)
TOUCH_PORT_BACK  :: u32(1)

// Number of report slots in TouchData. The panels report fewer at once
// (6 front, 4 back per the header's comment).
TOUCH_MAX_REPORT :: 8

TouchSamplingState :: enum i32 {
    STOP  = 0,
    START = 1,
}

// TouchReport.info bit: this touch is hidden under an upper layer.
TOUCH_REPORT_INFO_HIDE_UPPER_LAYER :: u16(0x0001)

TouchPanelInfo :: struct {
    minAaX, minAaY:     i16, // active area, top left
    maxAaX, maxAaY:     i16, // active area, bottom right
    minDispX, minDispY: i16, // display origin, top left
    maxDispX, maxDispY: i16, // display origin, bottom right
    minForce, maxForce: u8,
    reserved:           [30]u8,
}
#assert(size_of(TouchPanelInfo) == 0x30)

TouchReport :: struct {
    id:       u8,
    force:    u8,
    x, y:     i16, // panel coordinates, not screen pixels
    reserved: [8]u8,
    info:     u16,
}
#assert(size_of(TouchReport) == 0x10)

TouchData :: struct {
    timeStamp: u64,
    status:    u32, // unused
    reportNum: u32,
    report:    [TOUCH_MAX_REPORT]TouchReport,
}
#assert(size_of(TouchData) == 0x90)
#assert(offset_of(TouchData, report) == 16)

@(default_calling_convention = "c")
foreign sce_touch {
    // Peek returns the latest sample without blocking; Read waits for new data.
    // Both return the number of buffers filled (1..nBufs), or < 0 on error.
    sceTouchPeek                :: proc(port: u32, data: ^TouchData, nBufs: u32) -> i32 ---
    sceTouchRead                :: proc(port: u32, data: ^TouchData, nBufs: u32) -> i32 ---
    sceTouchGetPanelInfo        :: proc(port: u32, info: ^TouchPanelInfo) -> i32 ---
    sceTouchSetSamplingState    :: proc(port: u32, state: TouchSamplingState) -> i32 ---
    sceTouchGetSamplingState    :: proc(port: u32, state: ^TouchSamplingState) -> i32 ---
    sceTouchEnableTouchForce    :: proc(port: u32) -> i32 ---
    sceTouchDisableTouchForce   :: proc(port: u32) -> i32 ---
}
