"""Synthesises SignalHub's notification sounds from sine waves.

The sounds are original: every sample comes from the formulas below, with no
recording or third-party material. They are written as 16-bit mono WAV files
into the Android app's raw resources, where the app plays them (README.md in
this directory). Run from anywhere, with Python 3.10 or later and nothing
else; the WAV files are committed.

    python3 client/sounds/generate.py            # writes the WAV files
    python3 client/sounds/generate.py --check    # fails if they differ
"""

from __future__ import annotations

import argparse
import io
import math
import struct
import sys
import wave
from dataclasses import dataclass
from pathlib import Path

RATE = 32000
PEAK = 0.89  # -1 dBFS, so no sound clips at full volume
RAW = Path(__file__).resolve().parent.parent / "android/app/src/main/res/raw"


@dataclass(frozen=True)
class Note:
    """One struck tone: a fundamental and its partials, each a (ratio,
    level) pair, fading out exponentially from its start."""

    start: float
    frequency: float
    decay: float
    partials: tuple[tuple[float, float], ...] = ((1.0, 1.0),)
    level: float = 1.0
    vibrato: float = 0.0


BELL = ((1.0, 1.0), (2.0, 0.3), (3.0, 0.1))
PLUCK = ((1.0, 1.0), (2.0, 0.2))
BLIP = ((1.0, 1.0), (3.0, 0.2), (5.0, 0.06))
GLASS = ((1.0, 1.0), (2.76, 0.4), (5.4, 0.15), (8.93, 0.05))

# Each is short, and none is a single plain tone like a phone's defaults.
SOUNDS = {
    # The default: two bell tones rising a fifth.
    "signal": (
        0.75,
        [
            Note(0.0, 880.0, 0.12, BELL),
            Note(0.14, 1318.5, 0.2, BELL),
        ],
    ),
    # Three quick plucked notes rising through a major chord.
    "beacon": (
        0.8,
        [
            Note(0.0, 1046.5, 0.06, PLUCK, 0.8),
            Note(0.1, 1318.5, 0.06, PLUCK, 0.8),
            Note(0.2, 1568.0, 0.16, PLUCK),
        ],
    ),
    # Two short, bright blips with a slight warble.
    "pulse": (
        0.4,
        [
            Note(0.0, 1480.0, 0.03, BLIP, vibrato=12.0),
            Note(0.16, 1480.0, 0.05, BLIP, vibrato=12.0),
        ],
    ),
    # One glassy strike with inharmonic partials, ringing out.
    "glass": (1.1, [Note(0.0, 1244.5, 0.25, GLASS)]),
}

FADE_IN = 0.004  # seconds; avoids a click at each note's start


def note_sample(note: Note, t: float) -> float:
    age = t - note.start
    if age < 0:
        return 0.0
    envelope = math.exp(-age / note.decay) * min(1.0, age / FADE_IN)
    value = 0.0
    for ratio, level in note.partials:
        # Higher partials fade faster, as in a struck object.
        fade = math.exp(-age * (ratio - 1.0) / (note.decay * 4.0))
        wobble = note.vibrato * math.sin(2 * math.pi * 6.0 * age) / 6.0
        phase = 2 * math.pi * (note.frequency * ratio * age + wobble)
        value += level * fade * math.sin(phase)
    return note.level * envelope * value


def samples(length: float, notes: list[Note]) -> list[int]:
    count = round(length * RATE)
    raw = [sum(note_sample(n, i / RATE) for n in notes) for i in range(count)]
    # The last 20 ms fade to silence, so the end never clicks.
    tail = round(0.02 * RATE)
    for i in range(tail):
        raw[count - tail + i] *= 1.0 - (i + 1) / tail
    scale = PEAK * 32767 / max(abs(v) for v in raw)
    return [round(v * scale) for v in raw]


def wav(values: list[int]) -> bytes:
    out = io.BytesIO()
    with wave.open(out, "wb") as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(RATE)
        file.writeframes(struct.pack(f"<{len(values)}h", *values))
    return out.getvalue()


def rendered() -> dict[Path, bytes]:
    return {
        RAW / f"signalhub_{name}.wav": wav(samples(length, notes))
        for name, (length, notes) in SOUNDS.items()
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail if the committed files differ from what this script makes",
    )
    args = parser.parse_args(argv)
    stale = []
    for path, content in rendered().items():
        if args.check:
            if not path.exists() or path.read_bytes() != content:
                stale.append(path.name)
        else:
            path.write_bytes(content)
    if stale:
        print(f"Not what generate.py makes: {', '.join(stale)}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
