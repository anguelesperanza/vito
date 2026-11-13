#!/usr/bin/env python3
"""Write the WAV files Examples/Mixer-Example plays.

    python tools/make_test_sounds.py [output folder]

They are synthesised here so the repository needs no recorded audio. Each one
uses a different WAV layout on purpose, to exercise the loader and the mixer's
resampling:

    blip.wav    8-bit   mono    11025 Hz   a short falling chirp
    beep.wav    16-bit  mono    22050 Hz   a 660 Hz tone with a soft edge
    music.wav   16-bit  stereo  16000 Hz   a four-bar loop, bass left, melody right

Only the Python standard library is used.
"""
import math
import os
import struct
import sys
import wave


def write(path, rate, channels, width, frames):
    """frames: list of tuples of floats in -1..1, one tuple per frame."""
    with wave.open(path, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(width)
        w.setframerate(rate)
        out = bytearray()
        for frame in frames:
            for s in frame:
                s = max(-1.0, min(1.0, s))
                if width == 1:
                    out.append(int(round(s * 127)) + 128)       # 8-bit WAV is unsigned
                else:
                    out += struct.pack("<h", int(round(s * 32767)))
        w.writeframes(bytes(out))
    print(f"wrote {path} ({os.path.getsize(path)} bytes)")


def envelope(i, n, attack, release):
    return min(1.0, i / attack, (n - i) / release)


def blip(rate=11025, seconds=0.18):
    n = int(rate * seconds)
    frames, phase = [], 0.0
    for i in range(n):
        freq = 1400 - 900 * i / n
        phase += 2 * math.pi * freq / rate
        frames.append((0.8 * math.sin(phase) * envelope(i, n, 20, n * 0.6),))
    return frames


def beep(rate=22050, seconds=0.35, freq=660):
    n = int(rate * seconds)
    return [(0.7 * math.sin(2 * math.pi * freq * i / rate) * envelope(i, n, 200, 1500),) for i in range(n)]


def music(rate=16000, bpm=120):
    beat = 60 / bpm
    step = beat / 2                      # eighth notes
    # A minor: (bass note, melody notes) per bar, as semitones from A2 / A4
    bars = [(0, [0, 3, 7, 12, 7, 3, 7, 3]), (-4, [0, 3, 8, 12, 8, 3, 8, 3]),
            (-7, [0, 5, 9, 12, 9, 5, 9, 5]), (-5, [2, 5, 10, 14, 10, 5, 10, 5])]
    total = int(rate * step * 8 * len(bars))
    left, right = [0.0] * total, [0.0] * total

    def note(buf, start, length, freq, gain, harmonics):
        n = int(length * rate)
        for i in range(n):
            if start + i >= total:
                break
            t = i / rate
            s = sum(a * math.sin(2 * math.pi * freq * k * t) for k, a in harmonics)
            buf[start + i] += gain * s * envelope(i, n, 60, n * 0.5)

    for b, (bass, melody) in enumerate(bars):
        bar_start = int(b * 8 * step * rate)
        for half in range(2):
            note(left, bar_start + int(half * 4 * step * rate), step * 3.6, 110 * 2 ** (bass / 12), 0.45, [(1, 1.0), (2, 0.4)])
        for k, semis in enumerate(melody):
            note(right, bar_start + int(k * step * rate), step * 0.9, 440 * 2 ** (semis / 12), 0.30, [(1, 1.0), (3, 0.25)])
    # a little of each side in the other, so neither ear is empty
    return [(l + 0.25 * r, r + 0.25 * l) for l, r in zip(left, right)]


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "Examples", "Mixer-Example", "assets")
    os.makedirs(out, exist_ok=True)
    write(os.path.join(out, "blip.wav"), 11025, 1, 1, blip())
    write(os.path.join(out, "beep.wav"), 22050, 1, 2, beep())
    write(os.path.join(out, "music.wav"), 16000, 2, 2, music())


if __name__ == "__main__":
    main()
