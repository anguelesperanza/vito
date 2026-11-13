#!/usr/bin/env python3
"""Make the media files Examples/Media-Example plays, with ffmpeg.

    python tools/make_test_media.py [output folder]

    music.ogg   Ogg Vorbis, 44.1 kHz stereo, about 32 s: the loop from
                tools/make_test_sounds.py, four times over
    blip.wav    the short effect from the same script, to play over the music
    video.mp4   H.264 baseline 640 x 360 at 30 fps with AAC sound, 10 s:
                ffmpeg's test pattern with a running clock, and a beep each second
    video_b.mp4 the same clip as H.264 Main 960 x 544, "mp42" brand, no edit lists

Everything is synthesised, so the repository needs no recorded media.
Requires ffmpeg on the PATH (with libvorbis and libx264).
"""
import os
import subprocess
import sys
import tempfile
import wave

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_test_sounds as sounds  # noqa: E402


def run(args):
    result = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y"] + args)
    if result.returncode != 0:
        sys.exit("ffmpeg failed")


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "Examples", "Media-Example", "assets")
    os.makedirs(out, exist_ok=True)

    with tempfile.TemporaryDirectory() as temp:
        # The loop as a 44.1 kHz WAV, repeated; a rate other than the mixer's
        # 48 kHz on purpose, so the stream is resampled.
        loop = os.path.join(temp, "loop.wav")
        sounds.write(loop, 44100, 2, 2, sounds.music(rate=44100) * 4)
        music = os.path.join(out, "music.ogg")
        run(["-i", loop, "-c:a", "libvorbis", "-q:a", "4", music])
        print(f"wrote {music} ({os.path.getsize(music)} bytes)")

    sounds.write(os.path.join(out, "blip.wav"), 11025, 1, 1, sounds.blip())

    # The same clip encoded two ways, because which MP4 details SceAvPlayer
    # accepts is not documented. video.mp4 is what ffmpeg writes by default;
    # video_b.mp4 is closer to what Sony's own tools write: "mp42" brand, no
    # edit lists, Main profile, the screen's own size.
    beep = "aevalsrc='0.4*sin(2*PI*660*t)*lt(mod(t,1),0.1)|0.4*sin(2*PI*660*t)*lt(mod(t,1),0.1)':s=48000:d=10"
    audio = ["-c:a", "aac", "-b:a", "128k", "-ar", "48000", "-ac", "2"]
    variants = {
        "video.mp4": (
            "640x360",
            ["-c:v", "libx264", "-profile:v", "baseline", "-level", "3.0", "-pix_fmt", "yuv420p", "-g", "30", "-b:v", "900k"],
            ["-movflags", "+faststart"],
        ),
        "video_b.mp4": (
            "960x544",
            ["-c:v", "libx264", "-profile:v", "main", "-level", "3.1", "-pix_fmt", "yuv420p", "-g", "30", "-bf", "0", "-b:v", "1500k"],
            ["-movflags", "+faststart", "-brand", "mp42", "-use_editlist", "0"],
        ),
    }
    for name, (size, video_options, container_options) in variants.items():
        video = os.path.join(out, name)
        run(["-f", "lavfi", "-i", f"testsrc2=size={size}:rate=30:duration=10", "-f", "lavfi", "-i", beep]
            + video_options + audio + container_options + ["-shortest", video])
        print(f"wrote {video} ({os.path.getsize(video)} bytes)")


if __name__ == "__main__":
    main()
