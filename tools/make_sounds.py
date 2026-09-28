"""Make the addon's own sounds, Media/Sounds/*.ogg.

    python -m pip install numpy soundfile
    python tools/make_sounds.py

Built from sine waves here rather than taken from a sound library, so they
belong to this addon and ship under its license, the same way Blackthornes
Farmer's sounds are made.

- mail-haul.ogg: coins pouring in and a bright chime, when the mail report
  opens after collecting mail.
- mail-record.ogg: a short brass fanfare, when that visit beats your best
  haul or holds your best sale ever.

Run it again only to change them. The game needs a full restart to pick up a
new or changed sound file.
"""

import os

import numpy as np
import soundfile as sf

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Media", "Sounds")
os.makedirs(OUT, exist_ok=True)


def t(sec):
    return np.arange(int(SR * sec)) / SR


def bell(freq, sec, decay, partials=((1, 1), (2.76, .45), (5.4, .25), (8.93, .12))):
    x = t(sec)
    out = np.zeros_like(x)
    for ratio, amp in partials:
        out += amp * np.sin(2 * np.pi * freq * ratio * x) * np.exp(-x * ratio / decay)
    return out * np.clip(x / 0.002, 0, 1)


def coin(freq, sec=0.35):
    # A coin is a bright, inharmonic ring that dies fast.
    return bell(freq, sec, 0.09, ((1, 1), (2.41, .6), (3.87, .4), (5.93, .25)))


def brass(freq, sec, attack=0.04, release=0.35):
    x = t(sec)
    out = np.zeros_like(x)
    for h in range(1, 12):
        out += np.sin(2 * np.pi * freq * h * x * (1 + 0.0015 * np.sin(2 * np.pi * 5 * x))) / h ** 1.3
    a = np.clip(x / attack, 0, 1)
    r = np.clip((sec - x) / release, 0, 1)
    return out * a * r


def place(buf, clip, at):
    i = int(at * SR)
    end = min(len(buf), i + len(clip))
    buf[i:end] += clip[:end - i]


def reverb(x, mix=0.25):
    out = x.copy()
    for d, g in ((0.029, .5), (0.037, .45), (0.043, .4), (0.051, .35), (0.067, .3), (0.089, .25)):
        k = int(d * SR)
        z = np.zeros(len(x) + k * 12)
        z[:len(x)] = x
        for s in range(k, len(z), k):
            z[s:s + k] += g * z[s - k:s][:len(z[s:s + k])]
        out = np.pad(out, (0, len(z) - len(out)))
        out += mix / 6 * z
    return out


def finish(x, name, peak_db):
    x = x - np.mean(x)
    thresh = np.max(np.abs(x)) * 10 ** (-60 / 20)
    last = np.max(np.nonzero(np.abs(x) > thresh)) + 1
    x = x[:last]
    fade = int(0.02 * SR)
    x[-fade:] *= np.linspace(1, 0, fade)
    x = x / np.max(np.abs(x)) * 10 ** (peak_db / 20)
    sf.write(os.path.join(OUT, name), x.astype(np.float32), SR, format="OGG", subtype="VORBIS")
    print(name, round(len(x) / SR, 2), "s")


# The haul: a run of coins landing, quickening, then a bright chime on top.
rng = np.random.default_rng(7)
buf = np.zeros(int(SR * 2.0))
at = 0.0
for i in range(14):
    place(buf, (0.45 + 0.03 * i) * coin(rng.uniform(2600, 3900)), at)
    at += max(0.035, 0.11 - i * 0.006)
for i, f in enumerate((1318.5, 1568.0, 2093.0)):
    place(buf, 0.7 * bell(f, 1.3, 0.4), at + 0.02 + i * 0.06)
finish(reverb(buf, 0.3), "mail-haul.ogg", -4)

# A new record: rising brass call, a held major chord and coins over it.
buf = np.zeros(int(SR * 2.8))
for at, f in ((0.00, 349.23), (0.12, 440.0), (0.24, 523.25), (0.36, 698.46)):
    place(buf, 0.5 * brass(f, 0.17, 0.015, 0.05), at)
for f in (349.23, 440.0, 523.25, 698.46):
    place(buf, 0.3 * brass(f, 1.3, 0.03, 0.8), 0.5)
for i in range(8):
    place(buf, 0.3 * coin(rng.uniform(2800, 4200)), 0.55 + i * 0.08)
for i, f in enumerate((2093.0, 2637.0, 3136.0, 4186.0)):
    place(buf, 0.3 * bell(f, 1.0, 0.3), 0.6 + i * 0.07)
finish(reverb(buf, 0.4), "mail-record.ogg", -3)
