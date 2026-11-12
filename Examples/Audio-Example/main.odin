package audio_example

import "base:intrinsics"
import "base:runtime"
import "core:math"

import sce "../../lib/sce"
import v2d "../../lib/vita2d"

SCREEN_W :: f32(960)
SCREEN_H :: f32(544)

SAMPLE_RATE :: 48000
GRAIN       :: 1024 // samples per sceAudioOutOutput call (21 ms), multiple of 64
VOICES      :: 4
TABLE_BITS  :: 10
TABLE_LEN   :: 1 << TABLE_BITS

VOLUME_STEP :: i32(2048)

SHOULDER_L :: sce.CTRL_LTRIGGER | sce.CTRL_L1
SHOULDER_R :: sce.CTRL_RTRIGGER | sce.CTRL_R1

// Key -> note. Each key is one voice.
NoteKey :: struct {
    button: u32,
    name:   cstring,
    freq:   f32, // Hz
}
KEYS :: [VOICES]NoteKey{
    {sce.CTRL_CROSS,    "Cross  C4", 261.63},
    {sce.CTRL_CIRCLE,   "Circle E4", 329.63},
    {sce.CTRL_SQUARE,   "Square G4", 392.00},
    {sce.CTRL_TRIANGLE, "Tri    C5", 523.25},
}

// ---------------------------------------------------------------
// State shared with the audio thread. Only 32-bit values, accessed with
// volatile loads/stores (atomic for aligned 32-bit values). Not
// intrinsics.atomic_*: for Odin's default ARMv6 target those add CP15 `mcr`
// barrier instructions, which are deprecated on the Vita's Cortex-A9 and may
// fault. The values are independent flags, so no ordering is needed. The sine
// table is written once before the thread is created.
// ---------------------------------------------------------------
Shared :: struct {
    running: i32,
    octave:  i32,            // -1 .. 2, applied as a shift of the phase increment
    peak:    i32,            // loudest sample of the last grain, 0 .. 32767
    gate:    [VOICES]i32,    // 1 while the key is held
    inc:     [VOICES]u32,    // base phase increment per sample (octave 0)
    table:   [TABLE_LEN + 1]i16, // one sine cycle; the last entry repeats the first so interpolation can read idx+1
    port:    i32,
}
shared: Shared

// Two output buffers, used alternately. sceAudioOutOutput returns before the
// hardware has finished reading the buffer you gave it, so refilling that same
// buffer straight away corrupts the audio that is still playing (on real
// hardware this was a buzz at the grain rate, heard under the notes; Vita3K
// copies instantly and hides it). 64-byte aligned for DMA.
AudioBufs :: struct #align(64) {
    grain: [2][GRAIN]i16,
}
audio_bufs: AudioBufs

// ---------------------------------------------------------------
// Audio thread: fills one grain at a time and blocks in sceAudioOutOutput.
// Integer math only.
// ---------------------------------------------------------------
audio_thread :: proc "c" (args: u32, argp: rawptr) -> i32 {
    phase: [VOICES]u32
    amp:   [VOICES]i32 // envelope, 0 .. 32767
    which := 0         // buffer being filled (the other one is playing)
    errors := 0

    ATTACK  :: i32(32767 / (SAMPLE_RATE / 200)) // about 5 ms up
    RELEASE :: i32(32767 / (SAMPLE_RATE / 30))  // about 33 ms down

    for intrinsics.volatile_load(&shared.running) != 0 {
        buf := &audio_bufs.grain[which]
        oct  := intrinsics.volatile_load(&shared.octave)
        peak := i32(0)

        // Per-grain voice setup (octave shift, key gate).
        incs:   [VOICES]u32
        target: [VOICES]i32
        for v in 0 ..< VOICES {
            inc := shared.inc[v]
            incs[v] = oct >= 0 ? inc << u32(oct) : inc >> u32(-oct)
            target[v] = intrinsics.volatile_load(&shared.gate[v]) != 0 ? 32767 : 0
        }

        for i in 0 ..< GRAIN {
            mix := i32(0)
            for v in 0 ..< VOICES {
                if amp[v] < target[v] {
                    amp[v] = min(amp[v] + ATTACK, target[v])
                } else if amp[v] > target[v] {
                    amp[v] = max(amp[v] - RELEASE, target[v])
                }
                phase[v] += incs[v]
                // Linear interpolation between neighbouring table entries.
                idx  := phase[v] >> (32 - TABLE_BITS)
                frac := i32((phase[v] >> (16 - TABLE_BITS)) & 0xFFFF)
                a := i32(shared.table[idx])
                b := i32(shared.table[idx + 1])
                s := a + (((b - a) * frac) >> 16)
                mix += (s * amp[v]) >> 15
            }
            mix /= VOICES // headroom for all four keys at once
            buf[i] = i16(mix)
            peak = max(peak, abs(mix))
        }

        intrinsics.volatile_store(&shared.peak, peak)
        // Blocks until the previously queued grain has played, then queues this
        // one. We then fill the other buffer while this one plays.
        if r := sce.sceAudioOutOutput(shared.port, &buf[0]); r < 0 && errors < 3 {
            errors += 1
            sce.sceClibPrintf("sceAudioOutOutput failed: 0x%08x\n", u32(r))
        }
        which ~= 1
    }

    sce.sceKernelExitThread(0)
    return 0
}

// ---------------------------------------------------------------
// Tiny text builder (no allocation): append to buf, then NUL-terminate.
// ---------------------------------------------------------------
put_str :: proc "contextless" (buf: []u8, n: ^int, s: string) {
    for c in transmute([]u8)s {
        if n^ < len(buf) - 1 {
            buf[n^] = c
            n^ += 1
        }
    }
}

put_int :: proc "contextless" (buf: []u8, n: ^int, value: i32) {
    digits: [12]u8
    d := 0
    v := value
    if v < 0 {
        put_str(buf, n, "-")
        v = -v
    }
    if v == 0 {
        digits[d] = '0'
        d += 1
    }
    for v > 0 {
        digits[d] = u8('0' + v % 10)
        d += 1
        v /= 10
    }
    for d > 0 {
        d -= 1
        if n^ < len(buf) - 1 {
            buf[n^] = digits[d]
            n^ += 1
        }
    }
}

finish :: proc "contextless" (buf: []u8, n: int) -> cstring {
    buf[n] = 0
    return cstring(&buf[0])
}

// ---------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------
@(export, link_name = "odin_main")
game_main :: proc "c" (argc: i32, argv: [^]cstring) -> i32 {
    context = runtime.default_context()

    sce.sceClibPrintf("odin_main: started\n")
    sce.sceCtrlSetSamplingMode(.ANALOG)

    // ---- Audio setup ----
    // One cycle of a sine wave. math.sin goes through the libm bridge.
    for i in 0 ..< TABLE_LEN {
        shared.table[i] = i16(math.sin(f32(i) * (math.TAU / TABLE_LEN)) * 32767)
    }
    shared.table[TABLE_LEN] = shared.table[0] // guard entry for interpolation
    keys := KEYS
    for v in 0 ..< VOICES {
        // phase increment = freq / sample_rate * 2^32
        shared.inc[v] = u32(keys[v].freq / SAMPLE_RATE * 4294967296.0)
    }
    sce.sceClibPrintf("table[256]=%d (expect 32767)  inc[0]=%u\n",
        i32(shared.table[TABLE_LEN / 4]), shared.inc[0])

    port := sce.sceAudioOutOpenPort(.MAIN, GRAIN, SAMPLE_RATE, .MONO)
    if port < 0 {
        sce.sceClibPrintf("sceAudioOutOpenPort failed: 0x%08x\n", u32(port))
        return sce.sceKernelExitProcess(1)
    }
    shared.port    = port
    shared.running = 1
    sce.sceClibPrintf("audio port %d opened (grain %d, %d Hz, mono)\n", port, i32(GRAIN), i32(SAMPLE_RATE))

    volume: i32 = sce.AUDIO_OUT_MAX_VOL / 2
    vols   := [2]i32{volume, volume}
    r := sce.sceAudioOutSetVolume(port, sce.AUDIO_VOLUME_FLAG_L_CH | sce.AUDIO_VOLUME_FLAG_R_CH, &vols[0])
    sce.sceClibPrintf("SetVolume(%d) -> 0x%08x\n", volume, u32(r))

    thread := sce.sceKernelCreateThread("audio", audio_thread, sce.THREAD_DEFAULT_PRIORITY_USER,
        sce.THREAD_DEFAULT_STACK_SIZE, 0, sce.THREAD_CPU_AFFINITY_MASK_DEFAULT, nil)
    if thread < 0 {
        sce.sceClibPrintf("sceKernelCreateThread failed: 0x%08x\n", u32(thread))
        return sce.sceKernelExitProcess(1)
    }
    sce.sceKernelStartThread(thread, 0, nil)

    // ---- Graphics setup ----
    if v2d.Init() < 0 {
        sce.sceClibPrintf("vita2d: Init failed\n")
        return sce.sceKernelExitProcess(1)
    }
    v2d.SetClearColor(v2d.RGBA8(0x10, 0x12, 0x20, 0xFF))
    font := v2d.LoadDefaultPvf()

    white  := v2d.RGBA8(0xFF, 0xFF, 0xFF, 0xFF)
    yellow := v2d.RGBA8(0xFF, 0xDC, 0x00, 0xFF)
    dim    := v2d.RGBA8(0x30, 0x34, 0x50, 0xFF)
    pad_colors := [VOICES]u32{
        v2d.RGBA8(0x40, 0x90, 0xE8, 0xFF), // Cross: blue
        v2d.RGBA8(0xE0, 0x50, 0x50, 0xFF), // Circle: red
        v2d.RGBA8(0xE0, 0x70, 0xC0, 0xFF), // Square: pink
        v2d.RGBA8(0x40, 0xC8, 0x80, 0xFF), // Triangle: green
    }

    pad:          sce.CtrlData
    prev_buttons: u32
    level:        f32 // smoothed meter value 0..1
    buf:          [96]u8

    for {
        sce.sceCtrlPeekBufferPositive(0, &pad, 1)
        pressed := pad.buttons & ~prev_buttons
        prev_buttons = pad.buttons

        if pad.buttons & sce.CTRL_START != 0 do break

        // ---- Input -> shared state ----
        for v in 0 ..< VOICES {
            held: i32 = pad.buttons & keys[v].button != 0 ? 1 : 0
            intrinsics.volatile_store(&shared.gate[v], held)
        }
        oct := intrinsics.volatile_load(&shared.octave)
        if pressed & sce.CTRL_UP   != 0 do oct = min(oct + 1, 2)
        if pressed & sce.CTRL_DOWN != 0 do oct = max(oct - 1, -1)
        intrinsics.volatile_store(&shared.octave, oct)

        // L1 / R1 change the port volume.
        // The handheld's shoulder buttons are reported as LTRIGGER / RTRIGGER;
        // L1 / R1 are the PS TV / DualShock buttons. Accept both.
        if pressed & (SHOULDER_L | SHOULDER_R) != 0 {
            if pressed & SHOULDER_R != 0 do volume = min(volume + VOLUME_STEP, sce.AUDIO_OUT_MAX_VOL)
            if pressed & SHOULDER_L != 0 do volume = max(volume - VOLUME_STEP, 0)
            vols = {volume, volume}
            vr := sce.sceAudioOutSetVolume(port, sce.AUDIO_VOLUME_FLAG_L_CH | sce.AUDIO_VOLUME_FLAG_R_CH, &vols[0])
            sce.sceClibPrintf("SetVolume(%d) -> 0x%08x\n", volume, u32(vr))
        }

        // Level meter: jump up fast, fall slowly.
        peak := f32(intrinsics.volatile_load(&shared.peak)) / 32767
        level = peak > level ? peak : level * 0.92

        // ---- Render ----
        v2d.StartDrawing()
        v2d.ClearScreen()

        for v in 0 ..< VOICES {
            x := 60 + f32(v) * 220
            lit := pad.buttons & keys[v].button != 0
            v2d.DrawRectangle(x, 150, 200, 200, lit ? pad_colors[v] : dim)
            if font != nil {
                v2d.DrawText(i32(x) + 14, 260, white, 1.0, keys[v].name)
            }
        }

        // Meter.
        v2d.DrawRectangle(60, 400, 840, 28, dim)
        v2d.DrawRectangle(60, 400, 840 * level, 28, yellow)

        if font != nil {
            v2d.DrawText(24, 40, white, 1.4, "Audio example")
            v2d.DrawText(24, 70, white, 0.9, "Hold Cross / Circle / Square / Triangle to play.  Up/Down: octave   L1/R1: volume   Start: exit")

            n := 0
            put_str(buf[:], &n, "octave ")
            put_int(buf[:], &n, oct)
            put_str(buf[:], &n, "    volume ")
            put_int(buf[:], &n, volume * 100 / sce.AUDIO_OUT_MAX_VOL)
            put_str(buf[:], &n, "%    queued samples ")
            put_int(buf[:], &n, sce.sceAudioOutGetRestSample(port))
            v2d.DrawText(24, 480, yellow, 1.0, finish(buf[:], n))
        }

        v2d.EndDrawing()
        v2d.SwapBuffers()
    }

    // ---- Shutdown ----
    // Stop the audio thread first and wait for it, then release the port.
    intrinsics.volatile_store(&shared.running, 0)
    stat: i32
    sce.sceKernelWaitThreadEnd(thread, &stat, nil)
    sce.sceKernelDeleteThread(thread)
    sce.sceAudioOutOutput(port, nil) // wait for the last grain to play out
    sce.sceAudioOutReleasePort(port)

    // Graphics: see docs/getting-started.md, gotchas 10 and 11.
    v2d.WaitRenderingDone()
    if font != nil do v2d.FreePvf(font)
    v2d.FreeSizedFonts()
    sce.sceKernelExitProcess(0)
    return 0
}
