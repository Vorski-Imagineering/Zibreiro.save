#!/usr/bin/env python3
"""Generate Zibreiro's deterministic 128x128 single-channel blue-noise tile."""

from pathlib import Path
import numpy as np


SIZE = 128
SEED = 0x5A494252
OUTPUT = Path(__file__).resolve().parents[1] / "Resources" / "blue-noise-128.raw"


def rank_uniform(field: np.ndarray) -> np.ndarray:
    order = np.argsort(field, axis=None)
    ranks = np.empty(field.size, dtype=np.float64)
    ranks[order] = (np.arange(field.size) + 0.5) / field.size - 0.5
    return ranks.reshape(field.shape)


def main() -> None:
    rng = np.random.default_rng(SEED)
    field = rng.standard_normal((SIZE, SIZE))
    fy = np.fft.fftfreq(SIZE)[:, None]
    fx = np.fft.fftfreq(SIZE)[None, :]
    radius = np.sqrt(fx * fx + fy * fy)

    # Remove low frequencies isotropically and give higher spatial frequencies
    # progressively more energy. Repeated rank normalization provides an exact
    # uniform histogram without reintroducing the low-frequency components.
    shaping = (1.0 - np.exp(-((radius / 0.085) ** 4))) * np.sqrt(radius + 1e-9)
    shaping[0, 0] = 0.0
    for _ in range(8):
        spectrum = np.fft.fft2(rank_uniform(field))
        field = np.fft.ifft2(spectrum * shaping).real

    uniform = rank_uniform(field) + 0.5
    tile = np.floor(uniform * 256.0).clip(0, 255).astype(np.uint8)
    OUTPUT.write_bytes(tile.tobytes())
    print(f"Wrote {OUTPUT} ({OUTPUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
