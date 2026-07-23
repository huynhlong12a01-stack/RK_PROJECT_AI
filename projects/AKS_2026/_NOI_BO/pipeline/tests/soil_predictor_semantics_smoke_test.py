"""Small end-to-end test for nominal Unmapped/Other predictor semantics."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import geopandas as gpd
import numpy as np
import pandas as pd
import rasterio
from rasterio.transform import from_origin
from shapely.geometry import Polygon


PIPELINE = Path(__file__).resolve().parents[1]
ROOT = Path(__file__).resolve().parents[5]
spec = importlib.util.spec_from_file_location(
    "soil_predictor_engine_test", PIPELINE / "02b_prepare_soil_predictors_v2.py"
)
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)
fixture = ROOT / "_UNG_DUNG" / "runtime" / "tests" / "soil_predictor_semantics"
input_dir = fixture / "input"
work_dir = fixture / "work"
qa_dir = work_dir / "qa"
design_qa_dir = fixture / "design" / "qa"
for folder in (input_dir, work_dir, qa_dir, design_qa_dir):
    folder.mkdir(parents=True, exist_ok=True)

old = {
    name: getattr(engine, name)
    for name in (
        "SOIL_FILE", "POINT_FILE", "PC_DIR", "ALIGNED_DIR", "QA_DIR",
        "SETTINGS_FILE", "MANIFEST_FILE", "DESIGN_SOIL_QA_FILE",
        "DESIGN_SOIL_RASTER_FILE",
    )
}
try:
    engine.SOIL_FILE = input_dir / "soil_type.geojson"
    engine.POINT_FILE = work_dir / "sample_actual_clean.csv"
    engine.PC_DIR = work_dir
    engine.ALIGNED_DIR = work_dir
    engine.QA_DIR = qa_dir
    engine.SETTINGS_FILE = input_dir / "sampling.yml"
    engine.MANIFEST_FILE = fixture / "raster_manifest_with_soil.csv"
    engine.DESIGN_SOIL_QA_FILE = design_qa_dir / "soil_group_summary.json"
    engine.DESIGN_SOIL_RASTER_FILE = fixture / "design" / "Soil_Group_Code.tif"

    soil = gpd.GeoDataFrame(
        {"Ma1": ["A", "B"]},
        geometry=[
            Polygon([(0.0, 0.0), (1.8, 0.0), (1.8, 4.0), (0.0, 4.0)]),
            Polygon([(2.2, 0.0), (2.8, 0.0), (2.8, 4.0), (2.2, 4.0)]),
        ],
        crs="EPSG:4326",
    )
    soil.to_file(engine.SOIL_FILE, driver="GeoJSON")
    engine.SETTINGS_FILE.write_text("soil_group_field: Ma1\n", encoding="utf-8")
    points = pd.DataFrame(
        {
            "code": [f"S{i}" for i in range(1, 8)],
            "lon": [0.3, 0.6, 0.9, 1.2, 1.5, 2.5, 3.8],
            "lat": [0.5, 1.0, 1.5, 2.0, 2.5, 1.0, 1.0],
        }
    )
    points.to_csv(engine.POINT_FILE, index=False)
    profile = {
        "driver": "GTiff", "height": 4, "width": 4, "count": 1,
        "dtype": "float32", "crs": "EPSG:4326",
        "transform": from_origin(0, 4, 1, 1), "nodata": -9999.0,
    }
    with rasterio.open(work_dir / "PC1.tif", "w", **profile) as destination:
        destination.write(np.ones((4, 4), dtype="float32"), 1)
    engine.DESIGN_SOIL_RASTER_FILE.parent.mkdir(parents=True, exist_ok=True)
    engine.DESIGN_SOIL_RASTER_FILE.write_bytes(b"design-soil-raster")
    code_labels = {"1": "A", "2": "B", "3": "Unmapped"}
    design_summary = {
        "schema_version": "3.0.0",
        "soil_input_present": True,
        "soil_source_sha256": engine.sha256_file(engine.SOIL_FILE),
        "source_field": "Ma1",
        "encoding": engine.DESIGN_ENCODING,
        "code_labels": code_labels,
        "code_map_sha256": engine.canonical_sha256(code_labels),
        "soil_group_raster_sha256": engine.sha256_file(engine.DESIGN_SOIL_RASTER_FILE),
        "whole_domain_overlap_qa": {"passed": True},
        "source_registry_metadata": {"source_documentation_status": "TEST"},
    }
    engine.DESIGN_SOIL_QA_FILE.write_text(
        json.dumps(design_summary), encoding="utf-8"
    )

    engine.main()
    summary_file = qa_dir / "soil_predictor_summary.json"
    summary = json.loads(summary_file.read_text(encoding="utf-8"))
    assert summary["workflow1_soil_lineage"]["verified"] is True
    assert summary["retained_mapped_groups"] == ["A"]
    assert summary["collapsed_mapped_source_groups"] == ["B"]
    assert summary["technical_group_semantics"]["Other"].endswith("never includes Unmapped")
    assert summary["model_sample_counts"]["Other"] == 1
    assert summary["model_sample_counts"]["Unmapped"] == 1
    assert summary["whole_domain_overlap_qa"]["passed"] is True
    assert summary["output_file_sha256"]
    for path_text, record in summary["output_file_sha256"].items():
        path = ROOT / path_text
        assert path.exists() and engine.sha256_file(path) == record["sha256"]
    groups = pd.read_csv(qa_dir / "soil_predictor_point_groups.csv")
    assert groups.loc[groups.code == "S6", "soil_model_group"].iloc[0] == "Other"
    assert groups.loc[groups.code == "S7", "soil_model_group"].iloc[0] == "Unmapped"
finally:
    for name, value in old.items():
        setattr(engine, name, value)
    if fixture.exists():
        for path in sorted(fixture.rglob("*"), reverse=True):
            if path.is_file():
                path.unlink()
            elif path.is_dir():
                path.rmdir()
        fixture.rmdir()

preflight_files = (
    ROOT / "projects" / "AKS_2026" / "_NOI_BO" / "pipeline" / "preflight_actual.R",
    ROOT / "projects" / "AKS_BLIND_ROI_TEST" / "_NOI_BO" / "pipeline" / "preflight_actual.R",
    ROOT / "_UNG_DUNG" / "project_template" / "_NOI_BO" / "pipeline" / "preflight_actual.R",
)
for preflight_file in preflight_files:
    source = preflight_file.read_text(encoding="utf-8")
    assert '<- "Unmapped"' in source
    assert 'soil_source_class == "Unmapped", "Unmapped"' in source
    assert 'rare_mapped_class_collapsed' in source
    assert 'soil_unmapped = soil_unmapped' in source
    assert 'n_soil_unmapped = sum(soil_unmapped' in source
print("[OK] Soil predictor keeps Unmapped distinct from mapped-class Other and hashes outputs")