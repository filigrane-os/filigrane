#!/usr/bin/env python3
"""Génère les sons de Filigrane (WAV stéréo 32 kHz, synthèse pure, sans dépendance).

Usage: make-sounds.py DOSSIER [NOM...]   (sans NOM: tous)
Idée: le bruit du papier et de l'écriture, jamais une cloche: sourd, discret, sans aigus stridents. Bruit filtré
et petits chocs graves, un peu d'écho alterné gauche/droite pour l'air, volume bas. `note` (cloche de verre) reste
disponible pour d'autres sons.
"""
import math
import struct
import sys
import wave

SR = 32000
PARTIALS = [(1.0, 1.0, 1.0), (2.76, 0.30, 0.55), (5.40, 0.10, 0.35), (8.93, 0.04, 0.22)]  # (rapport, niveau, durée relative)


def note(freq, dur, detune=0.0, attack=0.006, bright=1.0):
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
                att = min(1.0, t / attack)
                att = 0.5 - 0.5 * math.cos(math.pi * att)
                out[i] += (amp if ratio == 1.0 else amp * bright) * att * math.exp(-t / tau) * math.sin(w * i)
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


def lowpass(buf, cutoff):
    """Passe-bas à deux pôles (12 dB/octave): étouffe les aigus."""
    a = 1 - math.exp(-2 * math.pi * cutoff / SR)
    for _ in range(2):
        y = 0.0
        for i, v in enumerate(buf):
            y += a * (v - y)
            buf[i] = y
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


import random


def noise(n, seed):
    rnd = random.Random(seed)
    return [rnd.uniform(-1.0, 1.0) for _ in range(n)]


def highpass(buf, cutoff):
    a = math.exp(-2 * math.pi * cutoff / SR)
    px = py = 0.0
    for i, v in enumerate(buf):
        py = a * (py + v - px)
        px = v
        buf[i] = py
    return buf


def grain(dur, seed, low, high, decay):
    """Grain de bruit filtré (passe-bande low..high Hz) à enveloppe exponentielle: un « tac » ou un froissement."""
    n = int(SR * dur)
    g = noise(n, seed)
    g = highpass(lowpass(g, high), low)
    return [v * math.exp(-i / (SR * decay)) for i, v in enumerate(g)]


def thump(freq, dur, decay):
    """Petit choc grave (la touche qui frappe le rouleau)."""
    n = int(SR * dur)
    return [math.sin(2 * math.pi * freq * i / SR) * math.exp(-i / (SR * decay)) for i in range(n)]


def key(seed, hard=1.0):
    """Une frappe de machine à écrire: choc sourd + claquement mat."""
    t = thump(150, 0.05, 0.012)
    c = grain(0.05, seed, 700, 3200, 0.006)
    return [(a * 0.9 + b * 0.8) * hard for a, b in zip(t + [0.0] * 4000, c + [0.0] * 4000)][:int(SR * 0.06)]


def hum(freq, dur, decay, harmonics=6):
    """Ronflement électrique: fondamentale + harmoniques (dent de scie adoucie), qui s'éteint vite."""
    n = int(SR * dur)
    out = [0.0] * n
    for h in range(1, harmonics + 1):
        w = 2 * math.pi * freq * h / SR
        for i in range(n):
            out[i] += math.sin(w * i) / h
    return [v * math.exp(-i / (SR * decay)) for i, v in enumerate(out)]


def sweep(f0, f1, dur, level=1.0):
    """Glissando sinusoïdal de f0 à f1 (montée d'un appareil qui se met sous tension), enveloppe en cloche."""
    n = int(SR * dur)
    ph = 0.0
    out = []
    for i in range(n):
        f = f0 + (f1 - f0) * (i / n) ** 2
        ph += 2 * math.pi * f / SR
        out.append(math.sin(ph) * math.sin(math.pi * i / n) ** 1.5 * level)
    return out


def sparks(dur, seed, density=90.0):
    """Étincelles: craquements très brefs et secs, plus nombreux au début."""
    rnd = random.Random(seed)
    n = int(SR * dur)
    out = [0.0] * n
    t = 0.0
    while t < dur:
        g = grain(rnd.uniform(0.0015, 0.004), rnd.randrange(10**6), 1500, 5500, 0.0012)
        o = int(t * SR)
        amp = rnd.uniform(0.4, 1.0) * (1 - t / dur)
        for i, v in enumerate(g):
            if o + i < n:
                out[o + i] += v * amp
        t += rnd.expovariate(density * (1.3 - t / dur))
    return out


def click(seed):
    """Contact qui s'enclenche: un « clic » sec et bref."""
    return [a * 1.0 + b * 0.6 for a, b in zip(grain(0.012, seed, 1200, 4500, 0.002), thump(220, 0.012, 0.004))]


SOUNDS = {
    # « Frappe »: deux touches de machine à écrire, étouffées (choc sourd + claquement mat), à 0,11 s. Notification.
    # Candidats pour le chargeur branché (électrique, discret)
    "contact": lambda: finish(lowpass(mix([(0.0, click(11), 1.0), (0.02, hum(100, 0.22, 0.07), 0.35)], 0.45), 3800), peak=0.40),
    "arc": lambda: finish(lowpass(mix([(0.0, click(12), 0.8), (0.0, sparks(0.18, 4), 0.8), (0.05, sweep(300, 1400, 0.26), 0.35)], 0.5), 4200), peak=0.40),
    "charge": lambda: finish(lowpass(mix([(0.0, click(13), 0.7), (0.03, sweep(420, 640, 0.12), 0.45), (0.15, sweep(520, 860, 0.16), 0.45)], 0.45), 2600), peak=0.38),
    "notification": lambda: finish(mix([(0.0, key(1), 1.0), (0.11, key(2), 0.85)], 0.4), peak=0.45),
}

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for name in sys.argv[2:] or SOUNDS:
        save(f"{sys.argv[1]}/{name}.wav", SOUNDS[name]())
        print(name)
