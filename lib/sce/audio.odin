package sce

// Audio output bindings (psp2/audioout.h). Values were checked against the
// VitaSDK header. Link with -lSceAudio_stub. All arguments are integers or
// pointers, so no float bridge is needed.
//
// Audio is fed by calling sceAudioOutOutput with one grain of PCM at a time.
// That call BLOCKS until the hardware has consumed the previous grain, so it
// belongs on its own thread (see thread.odin), not in the render loop.

foreign import sce_audio "system:SceAudio_stub"

// sceAudioOutOpenPort 'type'
AudioOutPortType :: enum i32 {
    MAIN  = 0, // normal game audio
    BGM   = 1, // background music
    VOICE = 2,
}

// sceAudioOutOpenPort 'mode' / sceAudioOutSetConfig 'mode'.
// MONO takes one s16 per sample; STEREO takes interleaved L,R s16 pairs.
AudioOutMode :: enum i32 {
    MONO   = 0,
    STEREO = 1,
}

AudioOutConfigType :: enum i32 {
    LEN  = 0,
    FREQ = 1,
    MODE = 2,
}

AudioOutAlcMode :: enum i32 {
    OFF   = 0,
    MODE1 = 1,
}

// Grain length is in samples, a multiple of 64 between these limits.
AUDIO_MIN_LEN :: 64
AUDIO_MAX_LEN :: 65472

// Output port volume per channel: 0 .. AUDIO_OUT_MAX_VOL.
AUDIO_OUT_MAX_VOL :: i32(32768)
AUDIO_VOLUME_0DB  :: AUDIO_OUT_MAX_VOL

// sceAudioOutSetVolume 'ch': OR the channel flags together.
AUDIO_VOLUME_FLAG_L_CH :: i32(1)
AUDIO_VOLUME_FLAG_R_CH :: i32(2)

// Sample rates accepted by sceAudioOutOpenPort.
// 8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000

AUDIO_OUT_ERROR_NOT_OPENED          :: u32(0x80260001)
AUDIO_OUT_ERROR_BUSY                :: u32(0x80260002)
AUDIO_OUT_ERROR_INVALID_PORT        :: u32(0x80260003)
AUDIO_OUT_ERROR_INVALID_POINTER     :: u32(0x80260004)
AUDIO_OUT_ERROR_PORT_FULL           :: u32(0x80260005)
AUDIO_OUT_ERROR_INVALID_SIZE        :: u32(0x80260006)
AUDIO_OUT_ERROR_INVALID_FORMAT      :: u32(0x80260007)
AUDIO_OUT_ERROR_INVALID_SAMPLE_FREQ :: u32(0x80260008)
AUDIO_OUT_ERROR_INVALID_VOLUME      :: u32(0x80260009)
AUDIO_OUT_ERROR_INVALID_PORT_TYPE   :: u32(0x8026000A)
AUDIO_OUT_ERROR_INVALID_FX_TYPE     :: u32(0x8026000B)
AUDIO_OUT_ERROR_INVALID_CONF_TYPE   :: u32(0x8026000C)
AUDIO_OUT_ERROR_OUT_OF_MEMORY       :: u32(0x8026000D)

@(default_calling_convention = "c")
foreign sce_audio {
    // Returns a port number, or < 0 on error.
    sceAudioOutOpenPort    :: proc(type: AudioOutPortType, len: i32, freq: i32, mode: AudioOutMode) -> i32 ---
    sceAudioOutReleasePort :: proc(port: i32) -> i32 ---

    // Blocking. Pass nil for buf to wait until the last grain has played out.
    sceAudioOutOutput      :: proc(port: i32, buf: rawptr) -> i32 ---

    // vol points to one i32 (both channels) or two (L then R), each 0..32768.
    sceAudioOutSetVolume   :: proc(port: i32, ch: i32, vol: ^i32) -> i32 ---

    sceAudioOutSetConfig   :: proc(port: i32, len: u32, freq: i32, mode: AudioOutMode) -> i32 ---
    sceAudioOutGetConfig   :: proc(port: i32, type: AudioOutConfigType) -> i32 ---
    sceAudioOutSetAlcMode  :: proc(mode: AudioOutAlcMode) -> i32 ---

    // Samples still queued on the port.
    sceAudioOutGetRestSample :: proc(port: i32) -> i32 ---
    sceAudioOutGetAdopt      :: proc(type: AudioOutPortType) -> i32 ---
}
