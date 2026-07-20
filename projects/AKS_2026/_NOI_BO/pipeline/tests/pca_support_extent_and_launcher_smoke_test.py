"""Offline regression for support-grid expansion and fail-closed launcher wiring."""

import importlib.util
import json
import shutil
import sys
import types
from pathlib import Path
from types import SimpleNamespace

import numpy as np
import rasterio
from affine import Affine
from rasterio.crs import CRS


ROOT = Path(__file__).resolve().parents[5]
ENGINE = ROOT / "projects" / "AKS_2026" / "_NOI_BO" / "pipeline" / "02_download_gee_support.py"

# Import stays fully offline; this smoke never calls Earth Engine/geemap APIs.
sys.modules["ee"] = types.ModuleType("ee")
sys.modules["geemap"] = types.ModuleType("geemap")

spec = importlib.util.spec_from_file_location("support_grid_engine", ENGINE)
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)


class _FakeGeometry:
    def notna(self):
        return np.array([True])

    @property
    def is_empty(self):
        return np.array([False])


class _FakeBuffers:
    geometry = _FakeGeometry()
    empty = False
    # Extends on every side and is deliberately not aligned to 10 m cells.
    total_bounds = np.array([943.0, 1947.0, 1157.0, 2163.0])

    def to_crs(self, _crs):
        return self

    def __getitem__(self, _mask):
        return self


legacy = SimpleNamespace(
    transform=Affine(10.0, 0.0, 1000.0, 0.0, -10.0, 2100.0),
    crs=CRS.from_epsg(32649),
    width=10,
    height=10,
    profile={
        "driver": "GTiff",
        "width": 10,
        "height": 10,
        "count": 1,
        "dtype": "float32",
        "crs": CRS.from_epsg(32649),
        "transform": Affine(10.0, 0.0, 1000.0, 0.0, -10.0, 2100.0),
    },
)
original_reader = engine.gpd.read_file
engine.gpd.read_file = lambda _path: _FakeBuffers()
try:
    expanded = engine.build_aligned_union_grid(legacy, "offline-fixture")
finally:
    engine.gpd.read_file = original_reader

west, south, east, north = rasterio.transform.array_bounds(
    expanded.height, expanded.width, expanded.transform
)
assert west <= 943.0 and south <= 1947.0 and east >= 1157.0 and north >= 2163.0
assert west <= 1000.0 and south <= 2000.0 and east >= 1100.0 and north >= 2100.0
assert np.isclose((west - 1000.0) % 10.0, 0.0)
assert np.isclose((north - 2100.0) % 10.0, 0.0)
assert expanded.width > 10 and expanded.height > 10

# The GEE support layer must be preflight-certified and must never contain
# actual sample coordinates or identifiers. Use only tiny local fixtures here;
# the real AKS ROI is intentionally not parsed by this offline test.
original_roi_file = engine.ROI_FILE
original_privacy_file = engine.SUPPORT_GEOMETRY_PROVENANCE_FILE
test_tmp_root = ROOT / ".tmp" / "privacy_smoke"
test_tmp_root.mkdir(parents=True, exist_ok=True)


def run_privacy_fixture():
    temporary = test_tmp_root / "fixture"
    shutil.rmtree(temporary, ignore_errors=True)
    temporary.mkdir(parents=True, exist_ok=True)
    roi_fixture = temporary / "roi.geojson"
    roi_fixture.write_text('{"type":"FeatureCollection","features":[]}', encoding="utf-8")
    support_fixture = temporary / "support.gpkg"
    privacy_fixture = temporary / "support_geometry_privacy.json"
    safe_support = engine.gpd.GeoDataFrame(
        {
            "support_geometry_policy": [engine.SUPPORT_GEOMETRY_POLICY],
            "support_buffer_m": [engine.SUPPORT_BUFFER_M],
            "contains_sample_attributes": [False],
        },
        geometry=engine.gpd.GeoSeries.from_wkt([
            "POLYGON ((0 0, 25000 0, 25000 25000, 0 25000, 0 0))"
        ], crs=engine.CRS),
    )

    def write_support(frame):
        support_fixture.unlink(missing_ok=True)
        frame.to_file(support_fixture, layer="roi_fixed_covariate_support", driver="GPKG")

    def write_privacy(support_hash):
        payload = {
            "schema_version": "1.0.0",
            "provenance_type": "privacy_preserving_support_geometry",
            "status": "certified_by_preflight",
            "project_id": str(engine.CFG["project_id"]),
            "support_geometry_policy": engine.SUPPORT_GEOMETRY_POLICY,
            "geometry_source": "reviewed_roi_bounding_envelope_plus_fixed_metric_buffer",
            "geometry_derivation": "sf_projected_bbox_then_st_buffer_nQuadSegs_30",
            "coverage_guarantee": "contains_the_fixed_metric_buffer_of_the_reviewed_roi",
            "project_crs": engine.CRS,
            "support_buffer_m": engine.SUPPORT_BUFFER_M,
            "feature_count": 1,
            "attribute_schema": [
                "support_geometry_policy", "support_buffer_m",
                "contains_sample_attributes",
            ],
            "contains_sample_attributes": False,
            "sample_coordinates_or_identifiers_used_to_define_geometry": False,
            "sample_coordinates_or_identifiers_in_attributes": False,
            "roi_field_area_sha256": engine.sha256_file(roi_fixture),
            "support_geometry_file_sha256": support_hash,
        }
        privacy_fixture.write_text(json.dumps(payload), encoding="utf-8")

    engine.ROI_FILE = roi_fixture
    engine.SUPPORT_GEOMETRY_PROVENANCE_FILE = privacy_fixture
    try:
        write_support(safe_support)
        write_privacy(engine.sha256_file(support_fixture))
        privacy = engine.validate_privacy_preserving_support_geometry(support_fixture)
        assert privacy["sample_coordinates_or_identifiers_sent"] is False
        assert privacy["coverage_guarantee"] == (
            "contains_the_fixed_metric_buffer_of_the_reviewed_roi"
        )
        assert privacy["geometry_certified_by_preflight_hash_chain"] is True
        assert privacy["attribute_schema_exact_and_privacy_minimal"] is True

        tile_template = SimpleNamespace(
            transform=Affine(10.0, 0.0, 0.0, 0.0, -10.0, 25000.0),
            crs=CRS.from_epsg(32649), width=2500, height=2500,
        )
        windows = engine.aligned_windows(support_fixture, tile_template)
        assert len(windows) == 9
        assert all(window.width <= 1024 and window.height <= 1024 for window in windows)
        assert all(window.width * window.height <= 1024 * 1024 for window in windows)

        unsafe_support = safe_support.copy()
        unsafe_support["code"] = ["PRIVATE_SAMPLE"]
        write_support(unsafe_support)
        write_privacy(engine.sha256_file(support_fixture))
        try:
            engine.validate_privacy_preserving_support_geometry(support_fixture)
            raise AssertionError("sample-derived support field was not rejected")
        except RuntimeError as error:
            assert "prohibited sample-derived fields" in str(error)

        write_support(safe_support)
        write_privacy("0" * 64)
        try:
            engine.validate_privacy_preserving_support_geometry(support_fixture)
            raise AssertionError("tampered support hash was not rejected")
        except RuntimeError as error:
            assert "support_hash" in str(error)
    finally:
        engine.ROI_FILE = original_roi_file
        engine.SUPPORT_GEOMETRY_PROVENANCE_FILE = original_privacy_file
        shutil.rmtree(temporary, ignore_errors=True)


run_privacy_fixture()

for relative in (
    "projects/AKS_2026/_NOI_BO/run_interpolation_workflow.ps1",
    "projects/PHU_YEN_MOCK/_NOI_BO/run_interpolation_workflow.ps1",
    "_UNG_DUNG/project_template/_NOI_BO/run_interpolation_workflow.ps1",
):
    text = (ROOT / relative).read_text(encoding="utf-8")
    assert "danh dau DRAFT" not in text
    assert "current_pca_provenance_valid" in text
    assert "Certify-Workflow1PcaCopy" in text
    assert "khong co che do DRAFT" in text

for relative in (
    "projects/AKS_2026/_NOI_BO/pipeline/preflight_actual.R",
    "projects/PHU_YEN_MOCK/_NOI_BO/pipeline/preflight_actual.R",
    "_UNG_DUNG/project_template/_NOI_BO/pipeline/preflight_actual.R",
):
    text = (ROOT / relative).read_text(encoding="utf-8")
    assert "!support_download_provenance_valid" in text
    assert "pca_support_validate_current" in text
    assert "support_points <-" not in text
    assert "fixed_roi_buffer_no_sample_geometry" in text
    assert "support_envelope <- st_as_sfc(st_bbox(support_roi))" in text
    assert "geometry_source = \"reviewed_roi_bounding_envelope_plus_fixed_metric_buffer\"" in text
    assert "contains_sample_attributes = FALSE" in text

print("[OK] support extent, fixed-ROI privacy gate and fail-closed launchers passed")
