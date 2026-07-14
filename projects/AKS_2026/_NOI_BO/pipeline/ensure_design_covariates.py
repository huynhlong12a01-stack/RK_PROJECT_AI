"""Validate full-area design covariates and import a verified legacy source if needed."""

import hashlib
import json
import os
import shutil
from pathlib import Path

import geopandas as gpd
import numpy as np
import rasterio
from rasterio.features import rasterize


ROOT = Path(__file__).resolve().parents[4]
PROJECT = ROOT / "projects" / "AKS_2026"
WORK = PROJECT / "_NOI_BO" / "work" / "design"
QA_FILE = WORK / "qa" / "raw_covariate_coverage.json"
ROI_FILE = PROJECT / "01_THIET_KE_LAY_MAU" / "01_DAU_VAO" / "roi.geojson"
TEMPLATE_FILE = WORK / "grid_template.tif"
LEGACY_SOURCE = (
    Path("D:/apps/POINT_PLANNING_APP/data/projects")
    / PROJECT.name
    / "covariates"
)
FEATURES = ["CHIRPS", "DEM", "NDVI", "Slope", "TWI"]
MIN_COVERAGE = 0.99


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def signature(dataset):
    return (
        dataset.crs.to_wkt() if dataset.crs else None,
        tuple(dataset.transform),
        dataset.width,
        dataset.height,
    )


def assessment(folder, names, roi):
    paths = [folder / f"{name}.tif" for name in names]
    missing = [str(path) for path in paths if not path.exists()]
    if missing:
        return {"valid": False, "missing": missing, "coverage_fraction": 0.0}
    datasets = [rasterio.open(path) for path in paths]
    try:
        first = datasets[0]
        sig = signature(first)
        common_grid = all(signature(ds) == sig for ds in datasets)
        if not common_grid:
            return {
                "valid": False,
                "common_grid": False,
                "coverage_fraction": 0.0,
            }
        projected = roi.to_crs(first.crs)
        mask = rasterize(
            [(geom, 1) for geom in projected.geometry if geom is not None and not geom.is_empty],
            out_shape=(first.height, first.width),
            transform=first.transform,
            fill=0,
            all_touched=True,
            dtype="uint8",
        )
        roi_cells = int(mask.sum())
        common_valid = 0
        for _, window in first.block_windows(1):
            arrays = [ds.read(1, window=window) for ds in datasets]
            valid = np.ones(arrays[0].shape, dtype=bool)
            for values, ds in zip(arrays, datasets):
                valid &= np.isfinite(values)
                if ds.nodata is not None and np.isfinite(ds.nodata):
                    valid &= values != ds.nodata
            r0, c0 = int(window.row_off), int(window.col_off)
            inside = mask[
                r0 : r0 + int(window.height),
                c0 : c0 + int(window.width),
            ] == 1
            common_valid += int(np.sum(valid & inside))
        fraction = common_valid / roi_cells if roi_cells else 0.0
        return {
            "valid": bool(roi_cells > 0 and fraction >= MIN_COVERAGE),
            "common_grid": True,
            "crs": str(first.crs),
            "crs_wkt": first.crs.to_wkt() if first.crs else None,
            "transform": list(first.transform),
            "width": first.width,
            "height": first.height,
            "bounds": list(first.bounds),
            "roi_cell_count": roi_cells,
            "common_valid_roi_count": common_valid,
            "coverage_fraction": fraction,
            "minimum_required_fraction": MIN_COVERAGE,
        }
    finally:
        for dataset in datasets:
            dataset.close()


def pca_assessment(roi):
    if not TEMPLATE_FILE.exists():
        return {"valid": False, "coverage_fraction": 0.0}
    with rasterio.open(TEMPLATE_FILE) as template:
        expected = signature(template)
    result = assessment(WORK, [f"PC{i}" for i in range(1, 6)], roi)
    result["matches_computational_grid"] = bool(
        result.get("common_grid")
        and result.get("crs_wkt") == expected[0]
        and result.get("transform") == list(expected[1])
        and result.get("width") == expected[2]
        and result.get("height") == expected[3]
        and result.get("crs") is not None
    )
    result["valid"] = bool(result.get("valid") and result["matches_computational_grid"])
    return result


def write_summary(payload):
    QA_FILE.parent.mkdir(parents=True, exist_ok=True)
    QA_FILE.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )


def main():
    if not ROI_FILE.exists():
        raise FileNotFoundError(f"Missing ROI: {ROI_FILE}")
    roi = gpd.read_file(ROI_FILE)
    if roi.crs is None:
        raise ValueError("ROI has no CRS.")
    roi = roi[roi.geometry.notna() & ~roi.geometry.is_empty].copy()

    current = assessment(WORK, FEATURES, roi)
    imported = False
    source = None
    if not current.get("valid"):
        source = assessment(LEGACY_SOURCE, FEATURES, roi)
        if source.get("valid"):
            WORK.mkdir(parents=True, exist_ok=True)
            for name in FEATURES:
                src = LEGACY_SOURCE / f"{name}.tif"
                tmp = WORK / f"{name}.importing.tif"
                dst = WORK / f"{name}.tif"
                shutil.copy2(src, tmp)
                os.replace(tmp, dst)
            current = dict(source)
            imported = True
        else:
            payload = {
                "schema_version": "1.0.0",
                "status": "full_area_source_required",
                "raw_files_changed": False,
                "current_assessment": current,
                "legacy_source_assessment": source,
            }
            write_summary(payload)
            print("Design covariates are sparse and no verified full-area source exists.")
            raise SystemExit(20)

    inventory = {
        name: {
            "path": str((WORK / f"{name}.tif").resolve()).replace("\\", "/"),
            "size_bytes": (WORK / f"{name}.tif").stat().st_size,
            "sha256": sha256_file(WORK / f"{name}.tif"),
        }
        for name in FEATURES
    }
    legacy_lineage = None
    legacy_paths = [LEGACY_SOURCE / f"{name}.tif" for name in FEATURES]
    if all(path.exists() for path in legacy_paths):
        source_hashes = {
            name: sha256_file(LEGACY_SOURCE / f"{name}.tif") for name in FEATURES
        }
        if all(
            source_hashes[name] == inventory[name]["sha256"] for name in FEATURES
        ):
            legacy_lineage = {
                "relationship": "byte_identical_to_verified_legacy_full_area_source",
                "source": str(LEGACY_SOURCE.resolve()).replace("\\", "/"),
                "sha256": source_hashes,
            }
    pca = pca_assessment(roi)
    payload = {
        "schema_version": "1.0.0",
        "status": "ready",
        "materialization_mode": (
            "imported_verified_legacy_full_area_source"
            if imported
            else "reused_verified_full_area_workspace"
        ),
        "materialization_source": (
            str(LEGACY_SOURCE.resolve()).replace("\\", "/")
            if imported
            else str(WORK.resolve()).replace("\\", "/")
        ),
        "raw_files_changed": imported,
        "raw_covariates": current,
        "pca_assessment_before_rebuild": pca,
        "pca_grid_ready": pca.get("valid", False),
        "file_inventory": inventory,
        "verified_source_lineage": legacy_lineage,
    }
    write_summary(payload)
    print(
        "Design covariate gate passed: "
        f"coverage={current['coverage_fraction']:.6f}; "
        f"mode={payload['materialization_mode']}"
    )


if __name__ == "__main__":
    main()
