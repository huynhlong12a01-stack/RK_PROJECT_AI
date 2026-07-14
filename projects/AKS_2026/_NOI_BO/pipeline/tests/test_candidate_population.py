"""Unit test for exact two-pass candidate thinning."""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from affine import Affine
from rasterio.windows import Window


PIPELINE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PIPELINE))
from candidate_population import sample_valid_candidates  # noqa: E402


class ArraySource:
    def __init__(self, data, windows):
        self.data = data
        self.windows = windows

    def block_windows(self, band):
        del band
        return enumerate(self.windows)

    def read(self, band, window):
        del band
        row0, col0 = int(window.row_off), int(window.col_off)
        return self.data[
            row0 : row0 + int(window.height),
            col0 : col0 + int(window.width),
        ]


def run(seed):
    rows, cols = 10, 12
    identity = np.arange(rows * cols, dtype=float).reshape(rows, cols)
    windows = [
        Window(0, 0, 6, 5),
        Window(6, 0, 6, 5),
        Window(0, 5, 6, 5),
        Window(6, 5, 6, 5),
    ]
    sources = [ArraySource(identity + band * 1000, windows) for band in range(5)]
    soil = np.resize(np.asarray([1, 2, 3], dtype=np.uint8), rows * cols).reshape(rows, cols)
    core = np.ones((rows, cols), dtype=np.uint8)
    core[:, ::4] = 0
    soil_source = ArraySource(soil, windows)
    return sample_valid_candidates(
        sources=sources,
        soil_src=soil_source,
        core_mask=core,
        transform=Affine(10, 0, 100, 0, -10, 1000),
        max_candidates=25,
        rng=np.random.default_rng(seed),
    )


def main():
    first = run(42)
    second = run(42)
    features, coords, soils, metadata = first
    assert len(features) == 25
    assert features.shape == (25, 5)
    assert coords.shape == (25, 2)
    assert len(soils) == 25
    assert metadata["candidate_population_valid_inner_roi_cells"] == 90
    assert metadata["candidate_count_supplied_to_optimizer"] == 25
    assert metadata["candidate_thinning_method"] == "two_pass_exact_uniform_without_replacement"
    assert np.array_equal(first[0], second[0])
    assert np.array_equal(first[1], second[1])
    assert np.array_equal(first[2], second[2])
    assert all(int(value) % 4 != 0 for value in features[:, 0])
    print("Candidate population smoke test passed: exact count and deterministic ranks.")


if __name__ == "__main__":
    main()
