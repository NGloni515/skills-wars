import math
import os
import sys
import wave

import numpy as np

RATE = 44100
OUT_DIR = sys.argv[1] if len(sys.argv) > 1 else "game/audio/sfx"
rng = np.random.default_rng(7)


def timeline(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def envelope(t, attack, decay):
    rise = np.clip(t / max(attack, 1e-4), 0.0, 1.0)
    fall = np.exp(-np.maximum(t - attack, 0.0) / decay)
    return rise * fall


def noise(n):
    return rng.uniform(-1.0, 1.0, n)


def lowpass(signal, cutoff):
    cutoff = np.broadcast_to(cutoff, signal.shape)
    out = np.empty_like(signal)
    y = 0.0
    for i, x in enumerate(signal):
        a = 1.0 - math.exp(-2.0 * math.pi * cutoff[i] / RATE)
        y += a * (x - y)
        out[i] = y
    return out


def bandpass(signal, center, q):
    center = np.broadcast_to(center, signal.shape)
    out = np.empty_like(signal)
    x1 = x2 = y1 = y2 = 0.0
    for i, x in enumerate(signal):
        w = 2.0 * math.pi * center[i] / RATE
        alpha = math.sin(w) / (2.0 * q)
        a0 = 1.0 + alpha
        b0, b2 = alpha / a0, -alpha / a0
        a1, a2 = -2.0 * math.cos(w) / a0, (1.0 - alpha) / a0
        y = b0 * x + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, x, y1, y
        out[i] = y
    return out


def tone(t, frequency, shape="sine"):
    phase = 2.0 * math.pi * np.cumsum(np.broadcast_to(frequency, t.shape)) / RATE
    if shape == "triangle":
        return 2.0 / math.pi * np.arcsin(np.sin(phase))
    if shape == "square":
        return np.tanh(4.0 * np.sin(phase))
    return np.sin(phase)


def place(buffer, sound, start_seconds):
    start = int(start_seconds * RATE)
    end = min(len(buffer), start + len(sound))
    buffer[start:end] += sound[: end - start]


def finish(signal, peak=0.8):
    fade = min(len(signal), int(0.005 * RATE))
    signal[:fade] *= np.linspace(0.0, 1.0, fade)
    signal[-fade:] *= np.linspace(1.0, 0.0, fade)
    return signal / max(1e-6, np.max(np.abs(signal))) * peak


def hook_throw():
    t = timeline(0.38)
    sweep = 500 + 1900 * np.sin(np.clip(t / 0.38, 0, 1) * math.pi) ** 1.5
    return bandpass(noise(len(t)), sweep, 1.6) * envelope(t, 0.12, 0.12)


def metal_click(seconds, partials, decay):
    t = timeline(seconds)
    click = sum(math.exp(-k * 0.5) * np.sin(2 * math.pi * f * t + rng.uniform(0, 6)) for k, f in enumerate(partials))
    return click * np.exp(-t / decay) + 0.3 * noise(len(t)) * np.exp(-t / 0.002)


def chain_rattle():
    buffer = np.zeros(int(0.42 * RATE))
    start = 0.0
    for i in range(10):
        partials = rng.uniform(2400, 7200, 3)
        place(buffer, metal_click(0.05, partials, 0.012) * (1.0 - i * 0.07), start)
        start += rng.uniform(0.025, 0.045)
    return buffer


def hook_clank():
    t = timeline(0.45)
    partials = [(523, 0.28), (1290, 0.18), (2210, 0.12), (3650, 0.07)]
    ring = sum(np.sin(2 * math.pi * f * t) * np.exp(-t / d) / (k + 1) for k, (f, d) in enumerate(partials))
    return ring + 0.8 * lowpass(noise(len(t)), 5000) * np.exp(-t / 0.006)


def hit_thwack():
    t = timeline(0.3)
    thump = tone(t, 150 * np.exp(-t / 0.05) + 55) * envelope(t, 0.002, 0.09)
    slap = bandpass(noise(len(t)), 1600, 1.2) * envelope(t, 0.001, 0.035)
    return 1.2 * thump + 0.9 * slap


def splash():
    t = timeline(0.7)
    body = lowpass(noise(len(t)), 6000 * np.exp(-t / 0.18) + 600) * envelope(t, 0.01, 0.2)
    for _ in range(6):
        start = rng.uniform(0.08, 0.45)
        bt = timeline(0.06)
        blip = tone(bt, 500 + 900 * bt / 0.06) * envelope(bt, 0.003, 0.02) * 0.25
        place(body, blip, start)
    return body


def poof():
    t = timeline(0.45)
    air = lowpass(noise(len(t)), 1300) * envelope(t, 0.02, 0.12)
    pop = tone(t, 180 * np.exp(-t / 0.04) + 70) * envelope(t, 0.002, 0.05)
    return air + 0.6 * pop


def arpeggio(notes, step, hold, shape="triangle", vibrato=0.0):
    total = step * (len(notes) - 1) + hold
    buffer = np.zeros(int(total * RATE))
    for i, frequency in enumerate(notes):
        length = hold if i == len(notes) - 1 else step * 1.6
        t = timeline(length)
        wobble = 1.0 + vibrato * np.sin(2 * math.pi * 5.5 * t)
        note = tone(t, frequency * wobble, shape) * envelope(t, 0.008, length * 0.45)
        note += 0.3 * tone(t, frequency * 2 * wobble) * envelope(t, 0.005, length * 0.25)
        place(buffer, note, i * step)
    return buffer


def spawn():
    return arpeggio([523.25, 659.25, 783.99, 1046.5], 0.07, 0.35)


def coin():
    return arpeggio([987.77, 1318.51], 0.07, 0.22, shape="square")


def victory():
    return arpeggio([523.25, 659.25, 783.99, 1046.5, 1046.5], 0.13, 0.75, vibrato=0.006)


def defeat():
    return lowpass(arpeggio([392.0, 349.23, 311.13, 261.63], 0.2, 0.7, vibrato=0.01), 2500)


def kill_ding():
    t = timeline(0.45)
    return (np.sin(2 * math.pi * 1568 * t) + 0.6 * np.sin(2 * math.pi * 2093 * t)) * envelope(t, 0.003, 0.12)


def powerup():
    chime = arpeggio([783.99, 987.77, 1174.66, 1567.98], 0.05, 0.4, vibrato=0.004)
    t = timeline(len(chime) / RATE)
    shimmer = bandpass(noise(len(t)), 7000, 3.0) * envelope(t, 0.05, 0.25) * 0.4
    return chime + shimmer


def shield_pop():
    t = timeline(0.3)
    pop = tone(t, 300 + 1400 * np.clip(t / 0.05, 0, 1)) * envelope(t, 0.002, 0.04)
    fizz = bandpass(noise(len(t)), 3500, 1.5) * envelope(t, 0.005, 0.08) * 0.6
    return pop + fizz


def arrow_shot():
    t = timeline(0.3)
    zing = tone(t, 900 + 2600 * np.clip(t / 0.12, 0, 1)) * envelope(t, 0.004, 0.08) * 0.6
    air = bandpass(noise(len(t)), 5000, 1.2) * envelope(t, 0.01, 0.07)
    return zing + air


def stun_hit():
    buffer = np.zeros(int(0.6 * RATE))
    t = timeline(0.12)
    place(buffer, (tone(t, 620) + 0.5 * tone(t, 1480)) * envelope(t, 0.001, 0.03), 0.0)
    for i, start in enumerate((0.14, 0.24, 0.34)):
        ct = timeline(0.08)
        chirp = tone(ct, 2600 + 900 * (ct / 0.08) * (1 if i % 2 == 0 else -1) + 400 * i) * envelope(ct, 0.005, 0.025) * 0.45
        place(buffer, chirp, start)
    return buffer


def trap_set():
    buffer = np.zeros(int(0.45 * RATE))
    for i in range(5):
        place(buffer, metal_click(0.04, rng.uniform(1800, 4200, 3), 0.01) * 0.8, 0.05 + i * 0.045)
    t = timeline(0.2)
    place(buffer, tone(t, 120 * np.exp(-t / 0.05) + 60) * envelope(t, 0.002, 0.06), 0.3)
    return buffer


def trap_snap():
    t = timeline(0.45)
    clang = sum(np.sin(2 * math.pi * f * t) * np.exp(-t / d) for f, d in ((880, 0.12), (1950, 0.08), (3300, 0.05)))
    crack = bandpass(noise(len(t)), 2500, 0.9) * envelope(t, 0.001, 0.02) * 2.0
    thud = tone(t, 140 * np.exp(-t / 0.04) + 50) * envelope(t, 0.002, 0.08)
    return clang * 0.5 + crack + thud


def ui_click():
    t = timeline(0.05)
    return tone(t, 2000) * envelope(t, 0.001, 0.008)


SOUNDS = {
    "hook_throw": (hook_throw, 0.7), "chain_rattle": (chain_rattle, 0.55), "hook_clank": (hook_clank, 0.7),
    "hit_thwack": (hit_thwack, 0.9), "splash": (splash, 0.75), "poof": (poof, 0.7), "spawn": (spawn, 0.5),
    "coin": (coin, 0.45), "victory": (victory, 0.6), "defeat": (defeat, 0.6), "kill_ding": (kill_ding, 0.5),
    "ui_click": (ui_click, 0.35), "powerup": (powerup, 0.55), "shield_pop": (shield_pop, 0.65),
    "arrow_shot": (arrow_shot, 0.6), "stun_hit": (stun_hit, 0.65),
    "trap_set": (trap_set, 0.6), "trap_snap": (trap_snap, 0.8),
}


def write(name, signal):
    pcm = (np.clip(signal, -1.0, 1.0) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT_DIR, name + ".wav"), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(pcm.tobytes())


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, (build, peak) in SOUNDS.items():
        signal = finish(build().astype(np.float64), peak)
        rms = float(np.sqrt(np.mean(signal ** 2)))
        print(f"{name:13s} {len(signal) / RATE:4.2f}s peak={np.max(np.abs(signal)):.2f} rms={rms:.3f}")
        write(name, signal)


main()
