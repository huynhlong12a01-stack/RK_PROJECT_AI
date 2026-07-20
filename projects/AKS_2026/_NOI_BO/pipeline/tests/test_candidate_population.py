"""Unit test for exact two-pass candidate thinning and all Soil Type levels."""

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
    def __init__(self, data, windows, nodata=None):
        self.data = data
        self.windows = windows
        self.nodata = nodata

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


def run(seed, max_candidates=25):
    rows, cols = 10, 12
    identity = np.arange(rows * cols, dtype=float).reshape(rows, cols)
    windows = [
        Window(0, 0, 6, 5),
        Window(6, 0, 6, 5),
        Window(0, 5, 6, 5),
        Window(6, 5, 6, 5),
    ]
    sources = [ArraySource(identity + band * 1000, windows) for band in range(5)]
    # Codes 4 and 17 prove that valid levels above the legacy top-three cap
    # survive; 65535 proves that declared nodata remains excluded.
    soil = np.resize(
        np.asarray([1, 2, 3, 4, 17, 65535], dtype=np.uint16), rows * cols
    ).reshape(rows, cols)
    core = np.ones((rows, cols), dtype=np.uint8)
    core[:, ::4] = 0
    soil_source = ArraySource(soil, windows, nodata=65535)
    result = sample_valid_candidates(
        sources=sources,
        soil_src=soil_source,
        core_mask=core,
        transform=Affine(10, 0, 100, 0, -10, 1000),
        max_candidates=max_candidates,
        rng=np.random.default_rng(seed),
    )
    expected_population = int(np.sum((core == 1) & (soil >= 1) & (soil != 65535)))
    return result, expected_population


def main():
    first, expected_population = run(42)
    second, _ = run(42)
    features, coords, soils, metadata = first
    assert len(features) == 25
    assert features.shape == (25, 5)
    assert coords.shape == (25, 2)
    assert len(soils) == 25
    assert metadata["candidate_population_valid_inner_roi_cells"] == expected_population
    assert metadata["candidate_count_supplied_to_optimizer"] == 25
    assert metadata["candidate_thinning_method"] == "two_pass_exact_uniform_without_replacement"
    assert metadata["soil_factor_top_n_filter_applied"] is False
    assert np.array_equal(first[0], second[0])
    assert np.array_equal(first[1], second[1])
    assert np.array_equal(first[2], second[2])
    assert all(int(value) % 4 != 0 for value in features[:, 0])

    all_candidates, _ = run(42, max_candidates=1000)
    all_soils = set(all_candidates[2].tolist())
    assert {1, 2, 3, 4, 17}.issubset(all_soils)
    assert 65535 not in all_soils
    assert len(all_candidates[0]) == expected_population
    print(
        "Candidate population smoke test passed: deterministic ranks, nodata "
        "excluded, and Soil Type levels above code 3 retained."
    )


if __name__ == "__main__":
    main()
