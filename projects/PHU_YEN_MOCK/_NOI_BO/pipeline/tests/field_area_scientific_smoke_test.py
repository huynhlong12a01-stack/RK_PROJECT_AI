#!/usr/bin/env python3
"""Offline scientific gates for field-area interpretation."""

from __future__ import annotations

import importlib.util
import json
import sys
import contextlib
from pathlib import Path

import geopandas as gpd
import pandas as pd
from shapely.geometry import box


SCRIPT = Path(__file__).resolve().parents[1] / "interpret_sugarcane_area.py"
SPEC = importlib.util.spec_from_file_location("field_area_core", SCRIPT)
assert SPEC and SPEC.loader
CORE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = CORE
SPEC.loader.exec_module(CORE)


def settings(project: Path) -> None:
    target = project / "00_XAC_LAP_VUNG_MIA" / "01_DAU_VAO"
    target.mkdir(parents=True, exist_ok=True)
    target.joinpath("interpretation.yml").write_text(
        "target_year: 2026\nhistory_years: 2\nresolution_m: 10\ncrs_epsg: 32649\n"
        "spatial_folds: 5\nspatial_block_m: 1000\nmin_groups_per_class: 3\n"
        "min_outer_test_per_class: 1\nreference_max_points: 10\n",
        encoding="utf-8",
    )


def main() -> None:
    schema = CORE.feature_schema_for(CORE.DEFAULTS)
    assert schema["sentinel_1"]["input_unit"] == "dB"
    assert schema["sentinel_1"]["additional_log_transform"] is False
    assert schema["missing_data_policy"] == "masked predictor pixels are not converted to zero"
    assert "10 m computational/export cell" in schema["native_resolution_warning"]
    config_30m = {**CORE.DEFAULTS, "resolution_m": 30}
    schema_30m = CORE.feature_schema_for(config_30m)
    assert schema_30m["computational_grid_m"] == 30
    assert "30 m computational/export cell" in schema_30m["native_resolution_warning"]
    assert "30 m native detail" in schema_30m["native_resolution_warning"]
    threshold, metrics = CORE.best_threshold([0, 0, 1, 1], [0.1, 0.3, 0.7, 0.9], 0.55)
    assert 0.3 < threshold <= 0.7 and metrics["f1"] == 1.0

    test_tmp = Path.cwd() / ".tmp"
    test_tmp.mkdir(parents=True, exist_ok=True)
    test_root = test_tmp / "field_area_scientific_smoke"
    test_root.mkdir(parents=True, exist_ok=True)
    with contextlib.nullcontext(str(test_root)) as raw:
        root = Path(raw)
        direct = root / "DIRECT"
        settings(direct)
        paths = CORE.ProjectPaths.from_project(direct)
        paths.ensure()
        field = gpd.GeoDataFrame(
            {"name": ["a", "b"]},
            geometry=[box(108.50, 13.90, 108.51, 13.91), box(108.52, 13.92, 108.53, 13.93)],
            crs="EPSG:4326",
        )
        field_path = paths.input / "roi_field_area.geojson"
        field.to_file(field_path, driver="GeoJSON")
        config, config_path = CORE.config_for(paths)
        qa = CORE.approve_direct_field_area(paths, field_path, config, config_path)
        assert qa["status"] == "APPROVED_FOR_SAMPLE_DESIGN"
        card = json.loads((paths.work / "reference_package" / "model_card.json").read_text(encoding="utf-8"))
        assert card["artifact_type"] == "positive_reference_only"
        assert card["binary_classifier_trained"] is False
        assert card["transferable_validated_model"] is False

        positive = root / "POSITIVE_ONLY"
        settings(positive)
        paths = CORE.ProjectPaths.from_project(positive)
        paths.ensure()
        search = gpd.GeoDataFrame({"name": ["search"]}, geometry=[box(108.4, 13.8, 108.8, 14.2)], crs=4326)
        search_path = paths.input / "roi_search.geojson"
        search.to_file(search_path, driver="GeoJSON")
        label_path = paths.input / "sugarcane_labels.csv"
        pd.DataFrame(
            {
                "code": ["P1", "P2", "P3"],
                "lat": [13.9, 14.0, 14.1],
                "lon": [108.5, 108.6, 108.7],
                "label": [1, 1, 1],
                "group_id": ["a", "b", "c"],
            }
        ).to_csv(label_path, index=False)
        config, config_path = CORE.config_for(paths)
        qa = CORE.run_supervised(paths, search_path, label_path, config, config_path, True)
        assert qa["status"] == "BLOCKED_POSITIVE_AND_NEGATIVE_LABELS_REQUIRED"
        assert qa["scientific_guards"]["random_points_used_as_verified_absence"] is False

    print("[OK] field-area scientific smoke tests passed")


if __name__ == "__main__":
    main()
