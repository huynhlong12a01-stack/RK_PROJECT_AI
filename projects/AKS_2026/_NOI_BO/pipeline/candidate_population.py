"""Exact, deterministic uniform thinning of valid raster sampling candidates."""

from __future__ import annotations

import numpy as np


def _valid_block(sources, soil_src, core_mask, window):
    bands = np.stack([src.read(1, window=window) for src in sources], axis=-1)
    band_valid = np.all(np.isfinite(bands), axis=-1)
    for index, src in enumerate(sources):
        nodata = getattr(src, "nodata", None)
        if nodata is not None and np.isfinite(nodata):
            band_valid &= bands[..., index] != nodata
    soil = soil_src.read(1, window=window)
    row0, col0 = int(window.row_off), int(window.col_off)
    core = core_mask[
        row0 : row0 + int(window.height),
        col0 : col0 + int(window.width),
    ] == 1
    valid = core & band_valid & (soil >= 1) & (soil <= 3)
    return bands, soil, valid, row0, col0


def sample_valid_candidates(
    *, sources, soil_src, core_mask, transform, max_candidates, rng
):
    """Return an exact uniform sample from all valid inner-ROI raster cells.

    A first block pass counts the target population. A second pass maps a fixed,
    sorted set of uniformly drawn population ranks back to cells. This avoids
    bias and severe undersampling when the raster bounding box is much larger
    than a fragmented agricultural ROI.
    """
    windows = [window for _, window in sources[0].block_windows(1)]
    block_counts = []
    total_valid = 0
    for window in windows:
        _, _, valid, _, _ = _valid_block(sources, soil_src, core_mask, window)
        count = int(np.count_nonzero(valid))
        block_counts.append(count)
        total_valid += count
    if total_valid == 0:
        raise RuntimeError("No valid candidate cell exists in the inner sampling ROI.")

    n_selected = min(int(max_candidates), total_valid)
    selected_ranks = np.sort(
        rng.choice(total_valid, size=n_selected, replace=False).astype(np.int64)
    )
    feature_chunks, coord_chunks, soil_chunks = [], [], []
    population_offset = 0
    for window, count in zip(windows, block_counts):
        next_offset = population_offset + count
        left = int(np.searchsorted(selected_ranks, population_offset, side="left"))
        right = int(np.searchsorted(selected_ranks, next_offset, side="left"))
        if right > left:
            bands, soil, valid, row0, col0 = _valid_block(
                sources, soil_src, core_mask, window
            )
            rows, cols = np.where(valid)
            local_rank = selected_ranks[left:right] - population_offset
            rows = rows[local_rank]
            cols = cols[local_rank]
            global_rows = rows + row0
            global_cols = cols + col0
            xs = transform.c + transform.a * (global_cols + 0.5)
            ys = transform.f + transform.e * (global_rows + 0.5)
            feature_chunks.append(bands[rows, cols, :])
            coord_chunks.append(np.column_stack([xs, ys]))
            soil_chunks.append(soil[rows, cols])
        population_offset = next_offset

    features = np.vstack(feature_chunks)
    coords = np.vstack(coord_chunks)
    soils = np.concatenate(soil_chunks).astype(int)
    if len(features) != n_selected:
        raise RuntimeError(
            f"Candidate rank mapping failed: {len(features)}/{n_selected} selected."
        )
    metadata = {
        "candidate_population_valid_inner_roi_cells": int(total_valid),
        "candidate_count_supplied_to_optimizer": int(n_selected),
        "candidate_thinning_method": "two_pass_exact_uniform_without_replacement",
        "candidate_thinning_seeded": True,
        "candidate_sampling_fraction": float(n_selected / total_valid),
        "raster_bbox_cell_count_not_used_as_population_denominator": True,
    }
    return features, coords, soils, metadata
