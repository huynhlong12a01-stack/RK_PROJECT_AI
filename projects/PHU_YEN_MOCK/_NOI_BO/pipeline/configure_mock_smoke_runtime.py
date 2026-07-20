"""Apply the bounded, still-nested CV grid used by PHU_YEN_MOCK idempotently."""

from __future__ import annotations

import json
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[2]
CONFIGS = [
    PROJECT / "_NOI_BO" / "config" / "rk_pc.R",
    PROJECT / "_NOI_BO" / "config" / "rk_pc_soil.R",
]
MANIFEST = PROJECT / "MOCK_RUN_MANIFEST.json"
MARKER = "# PHU_YEN_MOCK_BOUNDED_SMOKE_RUNTIME_V2"
BLOCK = """

# PHU_YEN_MOCK_BOUNDED_SMOKE_RUNTIME_V2
# Nested spatial CV is retained; only the search breadth is bounded for the mock.
AUTO_NEIGHBOR_NMAX_CANDIDATES <- c(8, 16)
AUTO_NEIGHBOR_SEARCH_RADIUS_CANDIDATES <- c(6000, 12000)
AUTO_NEIGHBOR_MAX_CANDIDATES <- 4
CV_OUTER_FOLDS <- 4
CV_OUTER_REPEATS <- 2
CV_INNER_FOLDS <- 3
CV_INNER_NEIGHBOR_MAX_CANDIDATES <- 4
CV_RANDOM_SEED <- 20260715
RUN_CROSS_VALIDATION <- TRUE
CV_EVALUATION_MODE <- "nested_spatial"
CV_REFIT_VARIOGRAM <- TRUE
"""


def main() -> None:
    for path in CONFIGS:
        text = path.read_text(encoding="utf-8")
        if MARKER not in text:
            path.write_text(text.rstrip() + BLOCK + "\n", encoding="utf-8")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    manifest["runtime"]["smoke_cv_configuration"] = {
        "non_operational": True,
        "nested_spatial_cv": True,
        "outer_folds": 4,
        "outer_repeats": 2,
        "inner_folds": 3,
        "inner_neighbor_max_candidates": 4,
        "auto_neighbor_max_candidates": 4,
        "variogram_refit": True,
        "comparison_models": ["PC_ONLY", "PC_PLUS_SOIL"],
        "production_strength_validation": False,
    }
    manifest.pop("outstanding_shared_issues", None)
    MANIFEST.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print("Applied bounded project-local nested-spatial smoke settings.")


if __name__ == "__main__":
    main()
