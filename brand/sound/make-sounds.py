#!/usr/bin/env python3
"""Génère les sons de Filigrane (WAV stéréo 32 kHz, synthèse pure, sans dépendance).

Usage: make-sounds.py DOSSIER [NOM...]   (sans NOM: tous)
Idée: un fil de verre qu'on effleure. Attaque très douce, partiels inharmoniques de cloche de verre (les aigus
s'éteignent les premiers), un peu d'écho alterné gauche/droite pour l'air, volume bas.
"""
import math
import struct
import sys
import wave

SR = 32000
PARTIALS = [(1.0, 1.0, 1.0), (2.76, 0.30, 0.55), (5.40, 0.10, 0.35), (8.93, 0.04, 0.22)]  # (rapport, niveau, durée relative)


def note(freq, dur, detune=0.0):
    n = int(SR * dur)
    out = [0.0] * n
    for ratio, amp, life in PARTIALS:
        f = freq * ratio
        if f > 0.45 * SR:
            continue
        for d in ([-detune, detune] if detune else [0.0]):
            w = 2 * math.pi * (f + d * ratio) / SR
            tau = dur * life / 4.0
            for i in range(n):
                t = i / SR
                att = min(1.0, t / 0.006)
                att = 0.5 - 0.5 * math.cos(math.pi * att)
                out[i] += amp * att * math.exp(-t / tau) * math.sin(w * i)
    return out


def mix(notes, total):
    n = int(SR * total)
    buf = [0.0] * n
    for start, samples, gain in notes:
        o = int(start * SR)
        for i, v in enumerate(samples):
            if o + i < n:
                buf[o + i] += v * gain
    return buf


def finish(buf, peak=0.42):
    # écho: 3 répétitions affaiblies, alternées gauche/droite
    n = len(buf) + int(SR * 0.4)
    left = buf + [0.0] * (n - len(buf))
    right = list(left)
    for k, (delay, gain) in enumerate([(0.085, 0.32), (0.17, 0.18), (0.26, 0.09)]):
        o = int(delay * SR)
        tgt = right if k % 2 == 0 else left
        for i, v in enumerate(buf):
            tgt[o + i] += v * gain
    m = max(max(abs(x) for x in left), max(abs(x) for x in right)) or 1.0
    k = peak / m
    fade = int(SR * 0.12)
    for i in range(fade):
        g = (i / fade)
        left[n - 1 - i] *= g
        right[n - 1 - i] *= g
    return [x * k for x in left], [x * k for x in right]


def save(path, lr):
    left, right = lr
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<hh", int(a * 32767), int(b * 32767)) for a, b in zip(left, right)))


SOUNDS = {
    # « Goutte »: trois notes de verre pentatoniques qui montent (sol6, si6, ré7), courtes. Notification.
    "notification": lambda: finish(mix([(0.0, note(1568.0, 0.7), 0.9), (0.09, note(1975.5, 0.7), 0.8), (0.18, note(2349.3, 0.8), 0.7)], 1.0)),
}

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for name in sys.argv[2:] or SOUNDS:
        save(f"{sys.argv[1]}/{name}.wav", SOUNDS[name]())
        print(name)
