#!/usr/bin/env python3
"""Lightweight beat and section analysis for the Habibi Groove visualizer."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

import numpy as np
from scipy import ndimage, signal


ROOT = Path(__file__).resolve().parent
AUDIO = ROOT / "habibi-groove.mp3"
SAMPLE_RATE = 22_050
HOP = 512
FRAME = 2_048


def decode_audio() -> np.ndarray:
    command = [
        "ffmpeg",
        "-v",
        "error",
        "-i",
        str(AUDIO),
        "-f",
        "f32le",
        "-acodec",
        "pcm_f32le",
        "-ac",
        "1",
        "-ar",
        str(SAMPLE_RATE),
        "-",
    ]
    raw = subprocess.check_output(command)
    return np.frombuffer(raw, dtype="<f4").astype(np.float64)


def frame_audio(samples: np.ndarray) -> np.ndarray:
    count = 1 + (len(samples) - FRAME) // HOP
    shape = (count, FRAME)
    strides = (samples.strides[0] * HOP, samples.strides[0])
    return np.lib.stride_tricks.as_strided(samples, shape=shape, strides=strides)


def estimate_tempo(onset: np.ndarray, fps: float) -> tuple[float, list[dict[str, float]]]:
    centered = onset - np.mean(onset)
    autocorr = signal.fftconvolve(centered, centered[::-1], mode="full")
    autocorr = autocorr[len(centered) - 1 :]
    min_bpm, max_bpm = 70.0, 180.0
    min_lag = int(round(fps * 60.0 / max_bpm))
    max_lag = int(round(fps * 60.0 / min_bpm))
    region = autocorr[min_lag : max_lag + 1]
    peaks, _ = signal.find_peaks(region, distance=max(1, int(fps * 0.08)))
    candidates: list[tuple[float, float]] = []
    for peak in peaks:
        lag = peak + min_lag
        bpm = 60.0 * fps / lag
        weight = float(region[peak])
        # Techno is usually felt in the 115–145 BPM band.
        if 115 <= bpm <= 145:
            weight *= 1.15
        candidates.append((weight, bpm))
    candidates.sort(reverse=True)
    top = [
        {"bpm": round(bpm, 2), "strength": round(weight / max(candidates[0][0], 1e-9), 3)}
        for weight, bpm in candidates[:8]
    ]
    return candidates[0][1], top


def section_boundaries(
    rms: np.ndarray,
    centroid: np.ndarray,
    low_ratio: np.ndarray,
    fps: float,
    duration: float,
) -> list[dict[str, float]]:
    seconds = np.arange(0.0, duration, 1.0)
    frame_times = np.arange(len(rms)) / fps
    features = np.vstack(
        [
            np.interp(seconds, frame_times, rms),
            np.interp(seconds, frame_times, centroid),
            np.interp(seconds, frame_times, low_ratio),
        ]
    )
    features = (features - np.median(features, axis=1, keepdims=True)) / (
        np.std(features, axis=1, keepdims=True) + 1e-9
    )
    smooth = ndimage.gaussian_filter1d(features, sigma=2.0, axis=1)
    novelty = np.linalg.norm(np.diff(smooth, axis=1), axis=0)
    novelty = ndimage.gaussian_filter1d(novelty, sigma=1.0)
    peaks, properties = signal.find_peaks(
        novelty,
        distance=12,
        prominence=max(0.12, float(np.percentile(novelty, 65)) * 0.55),
    )
    ranked = sorted(
        zip(peaks + 1, properties["prominences"]),
        key=lambda item: item[1],
        reverse=True,
    )
    chosen: list[tuple[int, float]] = []
    for second, prominence in ranked:
        if second < 8 or second > duration - 8:
            continue
        if all(abs(second - existing) >= 14 for existing, _ in chosen):
            chosen.append((int(second), float(prominence)))
        if len(chosen) == 8:
            break
    chosen.sort()
    scale = max((prominence for _, prominence in chosen), default=1.0)
    return [
        {"time": second, "strength": round(prominence / scale, 3)}
        for second, prominence in chosen
    ]


def main() -> None:
    samples = decode_audio()
    duration = len(samples) / SAMPLE_RATE
    frames = frame_audio(samples)
    window = np.hanning(FRAME)
    windowed = frames * window
    rms = np.sqrt(np.mean(windowed * windowed, axis=1) + 1e-12)

    spectrum = np.abs(np.fft.rfft(windowed, axis=1))
    frequencies = np.fft.rfftfreq(FRAME, 1 / SAMPLE_RATE)
    log_spectrum = np.log1p(spectrum)
    flux = np.maximum(0.0, np.diff(log_spectrum, axis=0)).sum(axis=1)
    flux = np.concatenate(([0.0], flux))
    flux = ndimage.gaussian_filter1d(flux, sigma=1.0)
    onset = np.maximum(0.0, flux - ndimage.median_filter(flux, size=31))

    spectral_sum = spectrum.sum(axis=1) + 1e-12
    centroid = (spectrum * frequencies).sum(axis=1) / spectral_sum
    low_ratio = spectrum[:, frequencies < 180].sum(axis=1) / spectral_sum

    fps = SAMPLE_RATE / HOP
    tempo, candidates = estimate_tempo(onset, fps)
    min_peak_distance = max(1, int(round(fps * 60.0 / tempo * 0.55)))
    beat_peaks, properties = signal.find_peaks(
        onset,
        distance=min_peak_distance,
        prominence=float(np.percentile(onset, 65)) * 0.55,
    )
    beat_times = beat_peaks / fps
    beat_prominence = properties["prominences"]
    strongest_order = np.argsort(beat_prominence)[::-1][:24]
    strongest_beats = sorted(round(float(beat_times[index]), 3) for index in strongest_order)

    report = {
        "duration_seconds": round(duration, 3),
        "sample_rate": SAMPLE_RATE,
        "estimated_bpm": round(float(tempo), 2),
        "tempo_candidates": candidates,
        "mean_rms_dbfs": round(float(20 * np.log10(np.mean(rms) + 1e-12)), 2),
        "peak_sample_dbfs": round(float(20 * np.log10(np.max(np.abs(samples)) + 1e-12)), 2),
        "detected_beats": int(len(beat_peaks)),
        "strongest_beat_times": strongest_beats,
        "section_boundaries": section_boundaries(
            rms, centroid, low_ratio, fps, duration
        ),
    }
    output = ROOT / "audio-analysis.json"
    output.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
