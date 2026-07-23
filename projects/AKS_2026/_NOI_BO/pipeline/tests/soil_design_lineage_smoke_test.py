"""Small Workflow 1 Soil Type lineage and overlap-QA test."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path

import geopandas as gpd
import numpy as np
import rasterio
from rasterio.transform import from_origin
from shapely.geometry import Polygon


PIPELINE = Path(__file__).resolve().parents[1]
ROOT = Path(__file__).resolve().parents[5]
spec = importlib.util.spec_from_file_location(
    "prepare_clhs_soil_test", PIPELINE / "prepare_clhs_soil.py"
)
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)
fixture = ROOT / "_UNG_DUNG" / "runtime" / "tests" / "soil_design_lineage"
fixture.mkdir(parents=True, exist_ok=True)
old = {
    name: getattr(engine, name)
    for name in (
        "SOIL_FILE", "SETTINGS_FILE", "TEMPLATE_FILE", "OUTPUT_FILE", "QA_FILE",
        "SHARED_SOIL_PROVENANCE_FILE",
    )
}
try:
    engine.SOIL_FILE = fixture / "soil_type.geojson"
    engine.SETTINGS_FILE = fixture / "sampling.yml"
    engine.TEMPLATE_FILE = fixture / "PC1.tif"
    engine.OUTPUT_FILE = fixture / "Soil_Group_Code.tif"
    engine.QA_FILE = fixture / "qa" / "soil_group_summary.json"
    engine.SHARED_SOIL_PROVENANCE_FILE = fixture / "provenance.yml"
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
    engine.SHARED_SOIL_PROVENANCE_FILE.write_text(
        "dataset_id: fixture\nsha256: " + "a" * 64 + "\n"
        "source:\n  status: USER_DOCUMENTATION_REQUIRED\n  license: null\n"
        "application_use:\n  external_publication_status: BLOCKED\n",
        encoding="utf-8",
    )
    profile = {
        "driver": "GTiff", "height": 4, "width": 4, "count": 1,
        "dtype": "float32", "crs": "EPSG:4326",
        "transform": from_origin(0, 4, 1, 1), "nodata": -9999.0,
    }
    with rasterio.open(engine.TEMPLATE_FILE, "w", **profile) as destination:
        destination.write(np.ones((4, 4), dtype="float32"), 1)

    engine.main()
    summary = json.loads(engine.QA_FILE.read_text(encoding="utf-8"))
    assert summary["schema_version"] == "3.0.0"
    assert summary["soil_source_sha256"] == engine.sha256_file(engine.SOIL_FILE)
    assert summary["source_field"] == "Ma1"
    assert summary["encoding"] == engine.ENCODING
    assert summary["code_map_sha256"] == engine.canonical_sha256(summary["code_labels"])
    assert summary["soil_group_raster_sha256"] == engine.sha256_file(engine.OUTPUT_FILE)
    assert "Unmapped" in summary["code_labels"].values()
    assert "Other" not in summary["code_labels"].values()
    assert summary["whole_domain_overlap_qa"]["passed"] is True
    assert summary["source_registry_metadata"]["metadata_readable"] is True
    assert summary["source_registry_metadata"]["license"] is None
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

print("[OK] Workflow 1 Soil Type QA locks source/field/encoding/code-map/output hashes")