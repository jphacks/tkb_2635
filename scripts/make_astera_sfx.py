#!/usr/bin/env python3
"""Astera 向けの短い効果音を、外部ライブラリなしで WAV に書き出す。"""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path


SAMPLE_RATE = 44_100
PEAK_TARGET = 0.62  # 約 -4.2 dBFS。再生側の効果音音量で最終調整する。
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "App/Resources/Audio/SE"
PREVIEW = ROOT / "docs/design/sound-effects/preview.wav"


def smooth_envelope(age: float, duration: float, attack: float, release: float) -> float:
    if age < 0 or age >= duration:
        return 0.0
    a = min(1.0, age / max(attack, 1e-4))
    r = min(1.0, (duration - age) / max(release, 1e-4))
    return math.sin(a * math.pi / 2) * min(1.0, r * r * (3 - 2 * r))


def add_bell(left: list[float], right: list[float], start: float, duration: float,
             frequency: float, amplitude: float, pan: float = 0.0, seed: int = 0) -> None:
    """少し不均等な倍音と減衰を重ねた、ガラスベル風の音。"""
    rng = random.Random(seed)
    start_index = max(0, round(start * SAMPLE_RATE))
    end_index = min(len(left), round((start + duration) * SAMPLE_RATE))
    partials = ((1.0, 1.0, 0.34), (2.756, 0.28, 0.22), (5.404, 0.095, 0.13), (8.933, 0.025, 0.09))
    pan_left = math.sqrt((1 - pan) / 2)
    pan_right = math.sqrt((1 + pan) / 2)
    phases = [rng.random() * math.tau for _ in partials]
    detune = 1 + rng.uniform(-0.0012, 0.0012)

    for index in range(start_index, end_index):
        age = (index - start_index) / SAMPLE_RATE
        attack = min(1.0, age / 0.006)
        value = 0.0
        for phase, (ratio, weight, decay) in zip(phases, partials):
            value += weight * math.sin(math.tau * frequency * ratio * detune * age + phase) * math.exp(-age / decay)
        value *= amplitude * attack * smooth_envelope(age, duration, 0.006, min(0.2, duration * 0.24))
        left[index] += value * pan_left
        right[index] += value * pan_right


def add_sine(left: list[float], right: list[float], start: float, duration: float,
             frequency: float, amplitude: float, pan: float = 0.0,
             end_frequency: float | None = None, attack: float = 0.04,
             release: float = 0.12, decay: float | None = None, phase: float = 0.0) -> None:
    start_index = max(0, round(start * SAMPLE_RATE))
    end_index = min(len(left), round((start + duration) * SAMPLE_RATE))
    pan_left = math.sqrt((1 - pan) / 2)
    pan_right = math.sqrt((1 + pan) / 2)
    for index in range(start_index, end_index):
        age = (index - start_index) / SAMPLE_RATE
        progress = age / max(duration, 1e-6)
        if end_frequency is None:
            current_frequency = frequency
            phase_value = math.tau * current_frequency * age + phase
        else:
            current_frequency = frequency * (end_frequency / frequency) ** progress
            phase_value = math.tau * duration * frequency * ((end_frequency / frequency) ** progress - 1) / math.log(end_frequency / frequency) if end_frequency != frequency else math.tau * frequency * age
        envelope = smooth_envelope(age, duration, attack, release)
        if decay is not None:
            envelope *= math.exp(-age / decay)
        value = amplitude * envelope * math.sin(phase_value + phase)
        left[index] += value * pan_left
        right[index] += value * pan_right


def add_filtered_air(left: list[float], right: list[float], start: float, duration: float,
                     amplitude: float, seed: int, attack: float = 0.03, release: float = 0.12,
                     brightness: float = 0.12, pan: float = 0.0) -> None:
    rng = random.Random(seed)
    start_index = max(0, round(start * SAMPLE_RATE))
    end_index = min(len(left), round((start + duration) * SAMPLE_RATE))
    noise_l = noise_r = 0.0
    pan_left = math.sqrt((1 - pan) / 2)
    pan_right = math.sqrt((1 + pan) / 2)
    for index in range(start_index, end_index):
        noise_l += brightness * (rng.uniform(-1, 1) - noise_l)
        noise_r += brightness * (rng.uniform(-1, 1) - noise_r)
        age = (index - start_index) / SAMPLE_RATE
        envelope = smooth_envelope(age, duration, attack, release)
        left[index] += noise_l * amplitude * envelope * pan_left
        right[index] += noise_r * amplitude * envelope * pan_right


def add_soft_reverb(left: list[float], right: list[float], amount: float = 0.22) -> tuple[list[float], list[float]]:
    # 反射を左右交互に少量加え、長すぎない透明な余韻にする。
    taps = ((0.037, 0.16), (0.071, 0.11), (0.113, 0.075), (0.169, 0.05), (0.241, 0.032))
    out_l, out_r = left[:], right[:]
    for delay, gain in taps:
        offset = round(delay * SAMPLE_RATE)
        scaled = gain * amount
        for index in range(offset, len(left)):
            out_l[index] += right[index - offset] * scaled
            out_r[index] += left[index - offset] * scaled
    return out_l, out_r


def normalize_and_write(path: Path, left: list[float], right: list[float]) -> None:
    peak = max(max(map(abs, left), default=0), max(map(abs, right), default=0), 1e-9)
    gain = PEAK_TARGET / peak
    path.parent.mkdir(parents=True, exist_ok=True)
    rng = random.Random(9173)
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(2)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        frames = bytearray()
        for l_value, r_value in zip(left, right):
            for value in (l_value * gain, r_value * gain):
                # ごく少量のディザで、フェード末尾の量子化ノイズを散らす。
                dither = rng.uniform(-0.5, 0.5) / 32768
                sample = max(-1.0, min(1.0, value + dither))
                frames.extend(struct.pack("<h", round(sample * 32767)))
        wav.writeframes(frames)


def make_cue(name: str, duration: float, voices: list[tuple], reverb: float = 0.22) -> tuple[Path, list[float], list[float]]:
    frame_count = round(duration * SAMPLE_RATE)
    left = [0.0] * frame_count
    right = [0.0] * frame_count
    for kind, args in voices:
        if kind == "bell":
            add_bell(left, right, **args)
        elif kind == "sine":
            add_sine(left, right, **args)
        elif kind == "air":
            add_filtered_air(left, right, **args)
    if reverb:
        left, right = add_soft_reverb(left, right, reverb)
    path = OUTPUT / f"{name}.wav"
    normalize_and_write(path, left, right)
    return path, left, right


def bell(start: float, duration: float, frequency: float, amplitude: float, pan: float = 0.0, seed: int = 0):
    return ("bell", dict(start=start, duration=duration, frequency=frequency, amplitude=amplitude, pan=pan, seed=seed))


def sine(start: float, duration: float, frequency: float, amplitude: float, **kwargs):
    return ("sine", dict(start=start, duration=duration, frequency=frequency, amplitude=amplitude, **kwargs))


def air(start: float, duration: float, amplitude: float, **kwargs):
    return ("air", dict(start=start, duration=duration, amplitude=amplitude, **kwargs))


def build_preview(cues: list[tuple[Path, list[float], list[float]]]) -> None:
    gap = round(0.45 * SAMPLE_RATE)
    preview_left: list[float] = []
    preview_right: list[float] = []
    for _, left, right in cues:
        preview_left.extend(left)
        preview_right.extend(right)
        preview_left.extend([0.0] * gap)
        preview_right.extend([0.0] * gap)
    normalize_and_write(PREVIEW, preview_left, preview_right)


def main() -> None:
    cues = [
        make_cue("01_app_start", 1.50, [
            sine(0.00, 0.75, 110.0, 0.065, pan=-0.1, attack=0.25, release=0.55),
            sine(0.05, 0.82, 164.81, 0.035, pan=0.12, attack=0.32, release=0.55),
            sine(0.10, 0.72, 220.0, 0.018, pan=0.0, attack=0.4, release=0.42),
            bell(0.24, 1.18, 1046.5, 0.22, pan=-0.3, seed=1),
            bell(0.42, 1.05, 1318.5, 0.16, pan=0.18, seed=2),
            bell(0.61, 0.88, 1568.0, 0.13, pan=0.32, seed=3),
            air(0.05, 1.05, 0.014, seed=4, brightness=0.07, attack=0.4, release=0.5),
        ], reverb=0.32),
        make_cue("02_map_open", 1.20, [
            sine(0.0, 0.95, 130.81, 0.12, end_frequency=261.63, attack=0.18, release=0.38),
            sine(0.08, 0.9, 196.0, 0.065, end_frequency=523.25, pan=-0.15, attack=0.2, release=0.35),
            sine(0.2, 0.75, 392.0, 0.034, end_frequency=784.0, pan=0.18, attack=0.15, release=0.32),
            air(0.0, 0.92, 0.045, seed=5, brightness=0.045, attack=0.45, release=0.42),
            bell(0.78, 0.34, 1568.0, 0.04, pan=0.24, seed=6),
        ], reverb=0.30),
        make_cue("03_pin_tap", 0.30, [
            bell(0.0, 0.29, 1568.0, 0.28, pan=0.08, seed=7),
            bell(0.012, 0.23, 2093.0, 0.075, pan=-0.12, seed=8),
        ], reverb=0.12),
        make_cue("04_celestial_select", 0.60, [
            bell(0.0, 0.50, 1174.7, 0.19, pan=-0.18, seed=9),
            bell(0.13, 0.46, 1396.9, 0.17, pan=0.05, seed=10),
            bell(0.27, 0.33, 1760.0, 0.12, pan=0.22, seed=11),
        ], reverb=0.24),
        make_cue("05_time_tick", 0.12, [
            sine(0.0, 0.085, 1820.0, 0.16, end_frequency=1460.0, attack=0.002, release=0.035, decay=0.055, phase=0.1),
            air(0.0, 0.035, 0.035, seed=12, brightness=0.42, attack=0.001, release=0.023),
        ], reverb=0.0),
        make_cue("06_location_found", 1.40, [
            sine(0.0, 0.28, 196.0, 0.12, attack=0.004, release=0.2, decay=0.12),
            bell(0.12, 1.14, 523.25, 0.14, pan=-0.2, seed=13),
            bell(0.31, 0.97, 659.25, 0.15, pan=-0.04, seed=14),
            bell(0.51, 0.78, 783.99, 0.15, pan=0.12, seed=15),
            bell(0.73, 0.58, 1046.5, 0.16, pan=0.24, seed=16),
            bell(0.92, 0.40, 1318.5, 0.08, pan=0.3, seed=17),
        ], reverb=0.32),
        make_cue("07_view_move", 0.25, [
            sine(0.0, 0.23, 260.0, 0.08, end_frequency=520.0, pan=-0.1, attack=0.035, release=0.11),
            sine(0.015, 0.20, 390.0, 0.045, end_frequency=620.0, pan=0.14, attack=0.04, release=0.10),
            air(0.0, 0.20, 0.05, seed=18, brightness=0.055, attack=0.03, release=0.10),
        ], reverb=0.10),
    ]
    build_preview(cues)
    for path, _, _ in cues:
        print(path)
    print(PREVIEW)


if __name__ == "__main__":
    main()
