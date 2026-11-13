package media_example

// Compressed music, video and the camera. Three pages, switched with L and R.
//
//   1  Music: an Ogg Vorbis file decoded while it plays (lib/vorbis), mixed
//      with a WAV effect by lib/vito's mixer.
//        Cross  play from the start     Square  pause / resume
//        Triangle  loop on / off        Circle  play the effect over it
//        Up / Down  volume              Left / Right  jump 5 seconds
//   2  Video: an MP4 (H.264 + AAC) played by the console's own decoder
//      (lib/video), drawn as a texture.
//        Cross  play from the start     Square  pause / resume
//        Circle  stop
//   3  Camera: the live picture, straight into a texture.
//        Cross  start / stop            Triangle  front / back camera
//
// The music keeps playing while you look at the other pages, so the video's
// sound and the music can be heard together.
//
// The media files are made by tools/make_test_media.py (ffmpeg).
//
// Hold Start + Select for a second to exit. Start-up errors go to
// ux0:data/vito_gfx.log.

import "core:fmt"

import gfx    "../../lib/gfx"
import sce    "../../lib/sce"
import video  "../../lib/video"
import vito   "../../lib/vito"
import vorbis "../../lib/vorbis"

CAMERA_W :: 640
CAMERA_H :: 480

fail :: proc(what: string) -> i32 {
    text := fmt.tprintf("%s\ninit step: %v\ninit error: 0x%08X\nalloc error: 0x%08X\nprogram error: 0x%08X\nvorbis error: %d\n",
        what, gfx.init_step, u32(gfx.init_error), u32(gfx.last_alloc_error), u32(gfx.last_program_error), vorbis.last_error)
    vito.print(text)
    vito.write_entire_file("ux0:data/vito_gfx.log", transmute([]u8)text)
    return sce.sceKernelExitProcess(1)
}

Camera :: struct {
    texture:  gfx.Texture,
    device:   i32,
    running:  bool,
    open_result, start_result, read_result: i32,
    frames:   int,
    last_frame: u64,
}

camera_start :: proc(camera: ^Camera) {
    info: sce.CameraInfo
    info.size       = size_of(sce.CameraInfo)
    info.priority   = sce.CAMERA_PRIORITY_SHARE
    info.format     = sce.CAMERA_FORMAT_ABGR
    info.resolution = sce.CAMERA_RESOLUTION_640_480
    info.framerate  = sce.CAMERA_FRAMERATE_30_FPS
    // The camera writes each picture straight into the texture's memory.
    info.sizeIBase  = CAMERA_W * CAMERA_H * 4
    info.pIBase     = camera.texture.pixels
    info.pitch      = u16((camera.texture.stride - CAMERA_W) * 4) // unused bytes at the end of each row
    info.buffer     = 0 // the buffer given here is used for every read
    camera.open_result = sce.sceCameraOpen(camera.device, &info)
    if camera.open_result < 0 do return
    camera.start_result = sce.sceCameraStart(camera.device)
    if camera.start_result < 0 {
        sce.sceCameraClose(camera.device)
        return
    }
    camera.running = true
    camera.frames = 0
}

camera_stop :: proc(camera: ^Camera) {
    if !camera.running do return
    sce.sceCameraStop(camera.device)
    sce.sceCameraClose(camera.device)
    camera.running = false
}

camera_update :: proc(camera: ^Camera) {
    if !camera.running do return
    read: sce.CameraRead
    read.size = size_of(sce.CameraRead)
    read.mode = 1 // do not wait for the next picture
    camera.read_result = sce.sceCameraRead(camera.device, &read)
    if camera.read_result >= 0 && read.frame != camera.last_frame {
        camera.last_frame = read.frame
        camera.frames += 1
    }
}

@(export, link_name = "odin_main")
game_main :: proc "c" (argc: i32, argv: [^]cstring) -> i32 {
    context = vito.init()
    vito.input_init({})

    if !gfx.init() do return fail("gfx.init failed")
    if !gfx.draw2d_init() do return fail("gfx.draw2d_init failed")
    ok: bool
    font: gfx.Font
    if font, ok = gfx.load_font(#load("assets/font20.png"), #load("assets/font20.fnt")); !ok do return fail("font")

    audio_ok := vito.audio_init()

    // ---- music and an effect ----------------------------------------------
    ogg, ogg_read := vito.read_entire_file("app0:/assets/music.ogg")
    music: ^vorbis.Music
    music_ok: bool
    if ogg_read do music, music_ok = vorbis.open(ogg)
    blip, blip_ok := vito.load_wav("app0:/assets/blip.wav")
    volume: f32 = 0.8
    music_paused := false
    blips := 0

    // ---- video ---------------------------------------------------------------
    movie: ^video.Video
    movie_error: i32
    movie_step: video.Step
    movie_tried := false
    // The same clip encoded two ways, to find out what the player accepts.
    VIDEO_FILES := [2]cstring{"app0:/assets/video.mp4", "app0:/assets/video_b.mp4"}
    video_file := 0

    // ---- camera --------------------------------------------------------------
    camera: Camera
    camera.device = sce.CAMERA_DEVICE_BACK
    camera_texture_ok: bool
    camera.texture, camera_texture_ok = gfx.create_texture(CAMERA_W, CAMERA_H, .LINEAR, .CLAMP)

    PAGES :: 3
    page := 0
    input: vito.Input
    timer: vito.Frame_Timer
    exit_hold := 0

    WHITE  := gfx.WHITE
    GREY   := gfx.rgba(170, 170, 170)
    YELLOW := gfx.rgba(240, 220, 60)
    GREEN  := gfx.rgba(120, 250, 140)
    RED    := gfx.rgba(250, 100, 100)
    CYAN   := gfx.rgba(120, 220, 250)

    close_movie :: proc(movie: ^^video.Video) {
        if movie^ == nil do return
        gfx.finish() // the GPU may still be drawing its last picture
        video.close(movie^)
        movie^ = nil
    }

    for {
        vito.frame_tick(&timer)
        vito.input_update(&input)
        if vito.held(input, vito.BUTTON_START) && vito.held(input, vito.BUTTON_SELECT) {
            exit_hold += 1
            if exit_hold > 60 do break
        } else {
            exit_hold = 0
        }

        old_page := page
        if vito.pressed(input, vito.BUTTON_R) do page = (page + 1) % PAGES
        if vito.pressed(input, vito.BUTTON_L) do page = (page + PAGES - 1) % PAGES
        if page != old_page {
            // The video and the camera stop when their page is left; the music goes on.
            if old_page == 1 do close_movie(&movie)
            if old_page == 2 do camera_stop(&camera)
        }

        switch page {
        case 0:
            if music_ok {
                if vito.pressed(input, vito.BUTTON_CROSS) {
                    vorbis.play(music, volume, music.loop)
                    music_paused = false
                }
                if vito.pressed(input, vito.BUTTON_SQUARE) {
                    music_paused = !music_paused
                    vorbis.set_paused(music, music_paused)
                }
                if vito.pressed(input, vito.BUTTON_TRIANGLE) do music.loop = !music.loop
                if vito.pressed(input, vito.BUTTON_UP)       do volume = min(volume + 0.1, 2)
                if vito.pressed(input, vito.BUTTON_DOWN)     do volume = max(volume - 0.1, 0)
                if vito.pressed(input, vito.BUTTON_UP) || vito.pressed(input, vito.BUTTON_DOWN) do vorbis.set_volume(music, volume)
                if vito.pressed(input, vito.BUTTON_RIGHT) do vorbis.seek(music, vorbis.position(music) + 5)
                if vito.pressed(input, vito.BUTTON_LEFT)  do vorbis.seek(music, vorbis.position(music) - 5)
            }
            if blip_ok && vito.pressed(input, vito.BUTTON_CIRCLE) {
                vito.play_sound(blip)
                blips += 1
            }
        case 1:
            if vito.pressed(input, vito.BUTTON_CROSS) {
                close_movie(&movie)
                movie_tried = true
                opened: bool
                movie, opened = video.open(VIDEO_FILES[video_file])
                if !opened do movie_error, movie_step = video.last_error, video.last_step
            }
            if movie != nil && vito.pressed(input, vito.BUTTON_SQUARE) do video.set_paused(movie, !movie.paused)
            if vito.pressed(input, vito.BUTTON_CIRCLE) do close_movie(&movie)
            if vito.pressed(input, vito.BUTTON_TRIANGLE) {
                close_movie(&movie)
                video_file = (video_file + 1) % len(VIDEO_FILES)
            }
            if movie != nil do video.update(movie)
        case 2:
            if camera_texture_ok {
                if vito.pressed(input, vito.BUTTON_CROSS) {
                    if camera.running do camera_stop(&camera)
                    else do camera_start(&camera)
                }
                if vito.pressed(input, vito.BUTTON_TRIANGLE) {
                    was_running := camera.running
                    camera_stop(&camera)
                    camera.device = sce.CAMERA_DEVICE_FRONT if camera.device == sce.CAMERA_DEVICE_BACK else sce.CAMERA_DEVICE_BACK
                    if was_running do camera_start(&camera)
                }
                camera_update(&camera)
            }
        }

        // ---- draw --------------------------------------------------------------
        gfx.begin_frame()
        gfx.clear({0.05, 0.06, 0.10, 1})
        gfx.begin_2d()

        switch page {
        case 0:
            gfx.draw_text(&font, 24, 36, "1  Music (Ogg Vorbis, streamed)", WHITE, 1.5)
            gfx.draw_text(&font, 24, 64, "Cross play   Square pause   Triangle loop   Circle effect   Up/Down volume   Left/Right jump 5 s", YELLOW)
            y := f32(120)
            if !audio_ok do gfx.draw_text(&font, 24, y, "vito.audio_init failed", RED)
            if !ogg_read {
                gfx.draw_text(&font, 24, y, "could not read app0:/assets/music.ogg", RED)
            } else if !music_ok {
                gfx.draw_text(&font, 24, y, fmt.tprintf("the decoder refused the file: stb_vorbis error %d", vorbis.last_error), RED)
            } else {
                playing := vorbis.is_playing(music)
                position, length := vorbis.position(music), vorbis.duration(music)
                gfx.draw_text(&font, 24, y, fmt.tprintf("%d Hz, %d channels, %.1f s, %d KB as Ogg (about %d KB as WAV)",
                    music.sample_rate, music.channels, length, len(ogg) / 1024, music.frames * 4 / 1024), GREY)
                y += 40
                state := "stopped"
                if playing do state = "paused" if music_paused else "playing"
                gfx.draw_text(&font, 24, y, fmt.tprintf("%s    loop %s    volume %.1f", state, "on" if music.loop else "off", volume),
                    GREEN if playing && !music_paused else WHITE)
                y += 40
                // Where the decoder is in the file.
                gfx.draw_rect(24, y, 700, 18, gfx.rgba(40, 44, 60))
                gfx.draw_rect(24, y, 700 * clamp(position / max(length, 0.001), 0, 1), 18, CYAN)
                gfx.draw_text(&font, 740, y + 15, fmt.tprintf("%.1f / %.1f s", position, length), WHITE)
                y += 50
                // Loudness of what the mixer is sending out.
                gfx.draw_text(&font, 24, y + 15, "output", GREY)
                gfx.draw_rect(100, y, 624, 18, gfx.rgba(40, 44, 60))
                gfx.draw_rect(100, y, 624 * clamp(vito.audio_peak(), 0, 1), 18, GREEN)
                y += 50
                gfx.draw_text(&font, 24, y, fmt.tprintf("effect played %d times (it mixes with the music)%s", blips,
                    "" if blip_ok else "   blip.wav did not load"), GREY if blip_ok else RED)
            }

        case 1:
            gfx.draw_text(&font, 24, 36, "2  Video (MP4: H.264 + AAC, hardware decoder)", WHITE, 1.5)
            gfx.draw_text(&font, 24, 64, "Cross play from the start   Square pause   Circle stop   Triangle other file", YELLOW)
            if movie != nil && movie.has_frame {
                // No alpha in a video picture: draw it without blending.
                gfx.set_blend(.None)
                gfx.draw_texture_ex(&movie.texture, {0, 0, f32(movie.width), f32(movie.height)}, {200, 80, 560, 315})
                gfx.set_blend(.Alpha)
            } else {
                gfx.draw_rect_lines(200, 80, 560, 315, 1, GREY)
            }
            if movie != nil {
                state := "playing"
                if video.starting(movie) do state = "opening the file..."
                else if video.finished(movie) do state = "finished"
                else if movie.paused do state = "paused"
                // What the player has asked for and reported, to tell a file it
                // cannot read from one it cannot play.
                gfx.draw_text(&font, 24, 458, fmt.tprintf("file: opened %d, size %d, %d reads, %d KB, error 0x%X   events (%d): %v",
                    movie.file_opens, movie.file_length, movie.file_reads, movie.file_bytes / 1024, u32(movie.file_error),
                    movie.event_count, movie.events[:min(movie.event_count, len(movie.events))]), GREY, 0.8)
                reads := fmt.tprintf("reads:")
                for r in movie.read_log[:min(movie.file_reads, len(movie.read_log))] {
                    reads = fmt.tprintf("%s  %d+%d=%d", reads, r.position, r.length, r.result)
                }
                gfx.draw_text(&font, 24, 478, reads, GREY, 0.8)
                gfx.draw_text(&font, 24, 498, fmt.tprintf("memory: %d calls, %d KB, largest %d, %d failed    pictures: %d calls, %d KB, align %d, %d failed, %d misaligned",
                    movie.allocs.calls, movie.allocs.bytes / 1024, movie.allocs.largest, movie.allocs.failures,
                    movie.frame_allocs.calls, movie.frame_allocs.bytes / 1024, movie.frame_allocs.alignment,
                    movie.frame_allocs.failures, movie.frame_misaligned), GREY, 0.8)
                gfx.draw_text(&font, 24, 438, fmt.tprintf("%s: %s   %.1f s   %d x %d   pictures %d   sound buffers %d at %d Hz",
                    VIDEO_FILES[video_file], state, f32(video.time_ms(movie)) / 1000, movie.width, movie.height, movie.frames, movie.audio_frames, movie.sample_rate), GREEN)
            } else if movie_tried && movie_step != .None {
                gfx.draw_text(&font, 24, 438, fmt.tprintf("could not open the video: step %v, error 0x%08X", movie_step, u32(movie_error)), RED)
            } else {
                gfx.draw_text(&font, 24, 438, fmt.tprintf("%s   press Cross to play, Triangle for the other file", VIDEO_FILES[video_file]), GREY)
            }

        case 2:
            gfx.draw_text(&font, 24, 36, "3  Camera", WHITE, 1.5)
            gfx.draw_text(&font, 24, 64, "Cross start / stop   Triangle front / back", YELLOW)
            if !camera_texture_ok {
                gfx.draw_text(&font, 24, 120, "could not make the camera texture", RED)
            } else {
                if camera.running {
                    gfx.set_blend(.None) // the camera's alpha channel is not meaningful
                    gfx.draw_texture_ex(&camera.texture, {0, 0, CAMERA_W, CAMERA_H}, {200, 84, 560, 420})
                    gfx.set_blend(.Alpha)
                } else {
                    gfx.draw_rect_lines(200, 84, 560, 420, 1, GREY)
                }
                which := "back" if camera.device == sce.CAMERA_DEVICE_BACK else "front"
                failed := camera.open_result < 0 || camera.start_result < 0
                gfx.draw_text(&font, 24, 120, fmt.tprintf("%s camera", which), WHITE)
                gfx.draw_text(&font, 24, 146, "running" if camera.running else "stopped", GREEN if camera.running else GREY)
                gfx.draw_text(&font, 24, 172, fmt.tprintf("pictures %d", camera.frames), GREY)
                gfx.draw_text(&font, 24, 220, fmt.tprintf("open  0x%X", u32(camera.open_result)), RED if failed else GREY)
                gfx.draw_text(&font, 24, 244, fmt.tprintf("start 0x%X", u32(camera.start_result)), RED if failed else GREY)
                gfx.draw_text(&font, 24, 268, fmt.tprintf("read  0x%X", u32(camera.read_result)), GREY)
            }
        }

        gfx.draw_text(&font, 24, 530, fmt.tprintf("L / R: page %d of %d     %.0f fps     Hold Start + Select: exit", page + 1, PAGES, timer.fps),
            YELLOW if exit_hold > 0 else GREY)
        gfx.end_2d()
        gfx.end_frame()
        gfx.swap()
        free_all(context.temp_allocator)
    }

    camera_stop(&camera)
    close_movie(&movie)
    if music_ok do vorbis.close(music)
    vito.stop_all_voices()
    if blip_ok do vito.unload_sound(&blip)
    if ogg_read do delete(ogg)
    vito.audio_shutdown()

    gfx.finish()
    sce.sceGxmDisplayQueueFinish()
    if camera_texture_ok do gfx.destroy_texture(&camera.texture)
    gfx.destroy_font(&font)
    gfx.draw2d_shutdown()
    gfx.shutdown()

    vito.input_shutdown()
    vito.shutdown()
    sce.sceKernelExitProcess(0)
    return 0
}
