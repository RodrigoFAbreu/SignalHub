# Alert sounds

SignalHub's own notification sounds, which the Android app plays when a push
arrives in the background (see [the client README](../README.md#alert)).

| Sound | File | What it is |
|---|---|---|
| Signal (the default) | `android/app/src/main/res/raw/signalhub_signal.wav` | Two bell tones rising a fifth, 0.75 s |
| Beacon | `android/app/src/main/res/raw/signalhub_beacon.wav` | Three plucked notes rising through a major chord, 0.8 s |
| Pulse | `android/app/src/main/res/raw/signalhub_pulse.wav` | Two short, bright blips with a slight warble, 0.4 s |
| Glass | `android/app/src/main/res/raw/signalhub_glass.wav` | One glassy strike with inharmonic partials, 1.1 s |

**Source:** original works made for SignalHub. `generate.py` synthesises
every sample from sine waves; no recording, sample library or sound of
another product or platform is used, in whole or in part.

**Licence:** the same as the rest of this repository, whose sounds they are.

To change a sound, edit `generate.py`, run it (Python 3.10 or later, no
other dependency), listen to the result, and commit the script with the WAV
files. CI runs `generate.py --check`, which fails when the committed files
are not what the script makes. The app refers to them by name
(`signalhub_<sound>`); `res/raw/keep.xml` keeps release builds from
shrinking them away.
