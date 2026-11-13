package mixer_example

// The audio mixer in lib/vito/audio.odin, WAV files loaded from the VPK, the
// other SceAudioOut port types, and the microphone.
//
//   Cross      play blip.wav, panned by the left stick (left / right)
//   Circle     play beep.wav
//   Triangle   play beep.wav an octave up (pitch 2)
//   Square     start / stop the music loop
//   Up / Down  music volume
//   L / R      master volume
//   Select     port test: a short tone on the BGM port (44.1 kHz stereo) and
//              on the VOICE port (16 kHz mono), with every call's result
//   Start      record one second from the microphone, then play it back
//   Start + Select (hold)  exit
//
// The three WAV files come from tools/make_test_sounds.py. They differ on
// purpose: 8-bit mono 11 kHz, 16-bit mono 22 kHz, 16-bit stereo 16 kHz. The
// mixer resamples all of them to its 48 kHz stereo output.

import "core:fmt"
import "core:log"
import "core:math"

import sce  "../../lib/sce"
import v2d  "../../lib/vita2d"
import vito "../../lib/vito"

WHITE  :: u32(0xFFFFFFFF)
GREEN  :: u32(0xFF40E040)
RED    :: u32(0xFF4040FF)
YELLOW :: u32(0xFF00DCFF)
CYAN   :: u32(0xFFE0D030)
GREY   :: u32(0xFF909090)
DARK   :: u32(0xFF403830)

describe :: proc(name: string, s: vito.Sound, ok: bool) -> cstring {
    if !ok do return fmt.caprintf("%s: FAILED TO LOAD", name)
    return fmt.caprintf("%s: %d Hz, %s, %d frames (%.2f s)", name, s.sample_rate,
        "stereo" if s.channels == 2 else "mono", s.frames, f32(s.frames) / f32(s.sample_rate))
}

// ---------------------------------------------------------------
// Port test: the SceAudioOut calls the mixer does not use
// ---------------------------------------------------------------
Port_Test :: struct {
    ran:                                bool,
    bgm_open, bgm_out, bgm_rest:        i32,
    bgm_len, bgm_freq, bgm_mode:        i32,
    bgm_volume, bgm_set_config:         i32,
    voice_open, voice_out:              i32,
    alc_on, alc_off:                    i32,
    adopt_main, adopt_bgm, adopt_voice: i32,
}

// Plays `seconds` of a sine tone on a port, one grain at a time. The calls
// block, so the picture freezes for that long; fine for a test.
play_tone :: proc(port: i32, grain, rate, channels: int, freq: f32, seconds: f32) -> i32 {
    // Two buffers used in turn (see getting-started, gotcha 13).
    buffers: [2][]i16
    buffers[0] = make([]i16, grain * channels, context.temp_allocator)
    buffers[1] = make([]i16, grain * channels, context.temp_allocator)
    total := int(seconds * f32(rate))
    phase: f32
    step := 2 * math.PI * freq / f32(rate)
    result: i32
    current := 0
    for done := 0; done < total; done += grain {
        buf := buffers[current]
        for i in 0 ..< grain {
            fade := min(1, f32(done + i) / 400, f32(total - done - i) / 400)
            s := i16(math.sin(phase) * 9000 * max(fade, 0))
            phase += step
            for c in 0 ..< channels do buf[i * channels + c] = s
        }
        result = sce.sceAudioOutOutput(port, raw_data(buf))
        if result < 0 do break
        current ~= 1
    }
    sce.sceAudioOutOutput(port, nil) // let it play out
    return result
}

run_port_test :: proc() -> (t: Port_Test) {
    t.ran = true
    t.adopt_main  = sce.sceAudioOutGetAdopt(.MAIN)
    t.adopt_bgm   = sce.sceAudioOutGetAdopt(.BGM)
    t.adopt_voice = sce.sceAudioOutGetAdopt(.VOICE)

    // BGM port: 44.1 kHz stereo. Opened at 22.05 kHz first, then changed with
    // SetConfig, to exercise that call too.
    GRAIN :: 512
    t.bgm_open = sce.sceAudioOutOpenPort(.BGM, GRAIN, 22050, .STEREO)
    if t.bgm_open >= 0 {
        port := t.bgm_open
        t.bgm_set_config = sce.sceAudioOutSetConfig(port, GRAIN, 44100, .STEREO)
        t.bgm_len  = sce.sceAudioOutGetConfig(port, .LEN)
        t.bgm_freq = sce.sceAudioOutGetConfig(port, .FREQ)
        t.bgm_mode = sce.sceAudioOutGetConfig(port, .MODE)
        // Left channel at half volume, right at full.
        volumes := [2]i32{sce.AUDIO_OUT_MAX_VOL / 2, sce.AUDIO_OUT_MAX_VOL}
        t.bgm_volume = sce.sceAudioOutSetVolume(port, sce.AUDIO_VOLUME_FLAG_L_CH | sce.AUDIO_VOLUME_FLAG_R_CH, &volumes[0])
        t.bgm_out  = play_tone(port, GRAIN, 44100, 2, 523.25, 0.4)
        t.bgm_rest = sce.sceAudioOutGetRestSample(port)
        sce.sceAudioOutReleasePort(port)
    }

    // VOICE port: 16 kHz mono.
    t.voice_open = sce.sceAudioOutOpenPort(.VOICE, 256, 16000, .MONO)
    if t.voice_open >= 0 {
        t.voice_out = play_tone(t.voice_open, 256, 16000, 1, 783.99, 0.4)
        sce.sceAudioOutReleasePort(t.voice_open)
    }

    // Automatic level control, on then off again.
    t.alc_on  = sce.sceAudioOutSetAlcMode(.MODE1)
    t.alc_off = sce.sceAudioOutSetAlcMode(.OFF)
    log.infof("port test: %v", t)
    return
}

// ---------------------------------------------------------------
// Microphone
// ---------------------------------------------------------------
MIC_RATE  :: 16000
MIC_GRAIN :: 256
MIC_SECONDS :: 1

Mic :: struct {
    port:      i32,
    recording: bool,
    filled:    int,
    samples:   []i16, // MIC_RATE * MIC_SECONDS, kept for the whole run
    result:    i32,
    peak:      i32,
    sound:     vito.Sound,
}

@(export, link_name = "odin_main")
game_main :: proc "c" (argc: i32, argv: [^]cstring) -> i32 {
    context = vito.init()

    if v2d.Init() < 0 {
        vito.println("vita2d: Init failed")
        return sce.sceKernelExitProcess(1)
    }
    v2d.SetClearColor(v2d.RGBA8(0x10, 0x12, 0x20, 0xFF))
    vito.input_init({})

    audio_ok := vito.audio_init()
    log.infof("audio_init: %v", audio_ok)

    blip,  blip_ok  := vito.load_wav("app0:/assets/blip.wav")
    beep,  beep_ok  := vito.load_wav("app0:/assets/beep.wav")
    music, music_ok := vito.load_wav("app0:/assets/music.wav")
    blip_text  := describe("blip.wav", blip, blip_ok)
    beep_text  := describe("beep.wav", beep, beep_ok)
    music_text := describe("music.wav", music, music_ok)
    log.infof("%s | %s | %s", blip_text, beep_text, music_text)
    free_all(context.temp_allocator) // load_wav reads the file into temp memory

    music_voice:   vito.Voice
    music_volume:  f32 = 0.6
    master_volume: f32 = 1.0
    port_test:     Port_Test
    mic := Mic{port = -1, samples = make([]i16, MIC_RATE * MIC_SECONDS)}

    input: vito.Input
    timer: vito.Frame_Timer
    exit_hold := 0
    plays := 0

    for {
        vito.input_update(&input)
        vito.frame_tick(&timer)

        both := vito.held(input, vito.BUTTON_START) && vito.held(input, vito.BUTTON_SELECT)
        if both {
            exit_hold += 1
            if exit_hold > 60 do break
        } else {
            exit_hold = 0
        }

        // --- sound effects
        if vito.pressed(input, vito.BUTTON_CROSS) {
            if vito.play_sound(blip, pan = input.left_stick.x) != 0 do plays += 1
        }
        if vito.pressed(input, vito.BUTTON_CIRCLE) {
            if vito.play_sound(beep) != 0 do plays += 1
        }
        if vito.pressed(input, vito.BUTTON_TRIANGLE) {
            if vito.play_sound(beep, pitch = 2) != 0 do plays += 1
        }

        // --- music
        if vito.pressed(input, vito.BUTTON_SQUARE) {
            if vito.voice_is_playing(music_voice) {
                vito.stop_voice(music_voice)
            } else {
                music_voice = vito.play_sound(music, volume = music_volume, loop = true)
            }
        }
        if vito.pressed(input, vito.BUTTON_UP | vito.BUTTON_DOWN) {
            music_volume = clamp(music_volume + (0.1 if vito.pressed(input, vito.BUTTON_UP) else -0.1), 0, 1.5)
            vito.voice_set_volume(music_voice, music_volume)
        }
        if vito.pressed(input, vito.BUTTON_L | vito.BUTTON_R) {
            master_volume = clamp(master_volume + (0.1 if vito.pressed(input, vito.BUTTON_R) else -0.1), 0, 2)
            vito.set_master_volume(master_volume)
        }

        // --- port test and microphone (not while holding both to exit)
        if !both && exit_hold == 0 {
            if vito.released(input, vito.BUTTON_SELECT) && !vito.held(input, vito.BUTTON_START) {
                port_test = run_port_test()
            }
            if vito.released(input, vito.BUTTON_START) && !vito.held(input, vito.BUTTON_SELECT) && !mic.recording {
                vito.stop_sound(mic.sound)
                mic.port = sce.sceAudioInOpenPort(.VOICE, MIC_GRAIN, MIC_RATE, .PARAM_FORMAT_S16_MONO)
                mic.result = mic.port
                mic.filled = 0
                mic.peak = 0
                mic.recording = mic.port >= 0
            }
        }
        if mic.recording {
            // Each read blocks for one grain: 256 samples at 16 kHz is 16 ms,
            // about one frame, so the picture keeps moving while it records.
            mic.result = sce.sceAudioInInput(mic.port, raw_data(mic.samples[mic.filled:]))
            if mic.result >= 0 do mic.filled += MIC_GRAIN
            if mic.result < 0 || mic.filled + MIC_GRAIN > len(mic.samples) {
                sce.sceAudioInReleasePort(mic.port)
                mic.recording = false
                for s in mic.samples[:mic.filled] do mic.peak = max(mic.peak, abs(i32(s)))
                if mic.filled > 0 {
                    mic.sound = vito.Sound{samples = mic.samples[:mic.filled], channels = 1, sample_rate = MIC_RATE, frames = mic.filled}
                    vito.play_sound(mic.sound, volume = 2)
                }
            }
        }

        // --- draw
        v2d.StartDrawing()
        v2d.ClearScreen()

        v2d.DrawText(24, 40, WHITE, 1.3, "Mixer example")
        v2d.DrawText(24, 66, GREEN if audio_ok else RED, 0.8,
            "lib/vito mixer: 48 kHz stereo, 16 voices, WAV files from app0:/assets" if audio_ok else "audio_init FAILED")

        y := i32(104)
        v2d.DrawText(24, y, WHITE if blip_ok else RED, 0.75, blip_text);   y += 22
        v2d.DrawText(24, y, WHITE if beep_ok else RED, 0.75, beep_text);   y += 22
        v2d.DrawText(24, y, WHITE if music_ok else RED, 0.75, music_text); y += 34

        v2d.DrawText(24, y, CYAN, 0.9, fmt.ctprintf("voices playing %d of %d    sounds started %d    music %s",
            vito.active_voice_count(), vito.MAX_VOICES, plays, "on" if vito.voice_is_playing(music_voice) else "off"))
        y += 26
        v2d.DrawText(24, y, WHITE, 0.8, fmt.ctprintf("music volume %.1f   master volume %.1f   blip pan %.2f (left stick)",
            music_volume, master_volume, input.left_stick.x))
        y += 22

        // level meter
        peak := vito.audio_peak()
        v2d.DrawRectangle(24, f32(y), 400, 14, DARK)
        v2d.DrawRectangle(24, f32(y), 400 * min(peak, 1), 14, RED if peak > 0.98 else GREEN)
        v2d.DrawText(436, y + 12, GREY, 0.7, fmt.ctprintf("peak %.2f%s", peak, " (clipping)" if peak > 0.98 else ""))
        y += 40

        // port test results
        v2d.DrawText(24, y, CYAN, 0.9, "Port test (Select)")
        y += 24
        if port_test.ran {
            t := port_test
            bgm_ok := t.bgm_open >= 0 && t.bgm_out >= 0 && t.bgm_set_config >= 0 && t.bgm_freq == 44100 && t.bgm_volume >= 0
            v2d.DrawText(24, y, GREEN if bgm_ok else RED, 0.7, fmt.ctprintf(
                "BGM: open 0x%X  SetConfig 0x%X  GetConfig len %d freq %d mode %d  SetVolume 0x%X  output 0x%X  rest %d",
                u32(t.bgm_open), u32(t.bgm_set_config), t.bgm_len, t.bgm_freq, t.bgm_mode, u32(t.bgm_volume), u32(t.bgm_out), t.bgm_rest))
            y += 20
            v2d.DrawText(24, y, GREEN if t.voice_open >= 0 && t.voice_out >= 0 else RED, 0.7,
                fmt.ctprintf("VOICE: open 0x%X  output 0x%X", u32(t.voice_open), u32(t.voice_out)))
            y += 20
            v2d.DrawText(24, y, GREEN if t.alc_on >= 0 && t.alc_off >= 0 else RED, 0.7, fmt.ctprintf(
                "ALC on 0x%X off 0x%X   GetAdopt main %d bgm %d voice %d", u32(t.alc_on), u32(t.alc_off), t.adopt_main, t.adopt_bgm, t.adopt_voice))
        } else {
            v2d.DrawText(24, y, GREY, 0.7, "not run yet: two short tones, the first quieter on the left")
            y += 40
        }
        y += 34

        // microphone
        v2d.DrawText(24, y, CYAN, 0.9, "Microphone (Start)")
        y += 24
        switch {
        case mic.recording:
            v2d.DrawText(24, y, YELLOW, 0.8, fmt.ctprintf("recording... %d of %d samples", mic.filled, len(mic.samples)))
        case mic.result < 0:
            v2d.DrawText(24, y, RED, 0.8, fmt.ctprintf("failed: 0x%08X", u32(mic.result)))
        case mic.filled > 0:
            v2d.DrawText(24, y, GREEN, 0.8, fmt.ctprintf("recorded %d samples at %d Hz, peak %d of 32767; played back through the mixer",
                mic.filled, MIC_RATE, mic.peak))
        case:
            v2d.DrawText(24, y, GREY, 0.7, "not run yet: records one second, then plays it back")
        }

        v2d.DrawText(24, 496, GREY, 0.7, fmt.ctprintf("%.0f fps", timer.fps))
        v2d.DrawText(24, 522, YELLOW if exit_hold > 0 else GREY, 0.75,
            "X blip  O beep  Tri beep x2  Sq music  Up/Down music vol  L/R master  Select ports  Start mic  Start+Select exit")

        v2d.EndDrawing()
        v2d.SwapBuffers()
        free_all(context.temp_allocator)
    }

    // Stop the mixer before freeing anything it might still be reading.
    vito.audio_shutdown()
    vito.unload_sound(&blip)
    vito.unload_sound(&beep)
    vito.unload_sound(&music)
    delete(mic.samples)

    v2d.WaitRenderingDone()
    v2d.FreeSizedFonts()
    vito.shutdown()
    sce.sceKernelExitProcess(0)
    return 0
}
