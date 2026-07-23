"""Prepare nominal Soil Type predictors with verified Workflow 1 lineage."""

from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path

import geopandas as gpd
import numpy as np
import pandas as pd
import rasterio
from rasterio.enums import MergeAlg
from rasterio.features import rasterize


ROOT = Path(__file__).resolve().parents[4]
PROJECT = ROOT / "projects" / "AKS_2026"
SOIL_FILE = PROJECT / "01_THIET_KE_LAY_MAU" / "01_DAU_VAO" / "soil_type.geojson"
POINT_FILE = PROJECT / "_NOI_BO" / "work" / "interpolation" / "sample_actual_clean.csv"
PC_DIR = PROJECT / "_NOI_BO" / "work" / "interpolation"
ALIGNED_DIR = PROJECT / "_NOI_BO" / "work" / "interpolation"
QA_DIR = PROJECT / "_NOI_BO" / "work" / "interpolation" / "qa"
SETTINGS_FILE = PROJECT / "01_THIET_KE_LAY_MAU" / "01_DAU_VAO" / "sampling.yml"
MANIFEST_FILE = PROJECT / "_NOI_BO" / "config" / "raster_manifest_with_soil.csv"
DESIGN_SOIL_QA_FILE = PROJECT / "_NOI_BO" / "work" / "design" / "qa" / "soil_group_summary.json"
DESIGN_SOIL_RASTER_FILE = PROJECT / "_NOI_BO" / "work" / "design" / "Soil_Group_Code.tif"

MIN_SAMPLES = 5
NODATA = 255
DESIGN_SCHEMA_VERSION = "3.0.0"
DESIGN_ENCODING = "nominal_factor_codes_v1; codes are labels, not ordinal values"
MODEL_ENCODING = "reference_dummy_v2; nominal categories; codes are not ordinal values"
INVALID_LABELS = {"", "nan", "none", "null", "na"}
RESERVED_TECHNICAL_LABELS = {"unmapped", "other"}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def canonical_sha256(value: object) -> str:
    payload = json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def setting(name: str, default: str) -> str:
    if not SETTINGS_FILE.exists():
        return default
    text = SETTINGS_FILE.read_text(encoding="utf-8")
    match = re.search(rf"(?m)^[ \t]*{re.escape(name)}[ \t]*:[ \t]*([^#\r\n]+)", text)
    return match.group(1).strip().strip("\"'") if match else default


def project_path(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT.resolve())).replace("\\", "/")
    except ValueError:
        return str(path.resolve()).replace("\\", "/")


def write_byte_raster(path: Path, array: np.ndarray, profile: dict, nodata: int = NODATA) -> None:
    out_profile = profile.copy()
    out_profile.update(
        driver="GTiff", count=1, dtype="uint8", nodata=nodata,
        compress="LZW", tiled=True, blockxsize=256, blockysize=256,
        BIGTIFF="IF_SAFER",
    )
    with rasterio.open(path, "w", **out_profile) as destination:
        destination.write(array.astype("uint8"), 1)


def verify_workflow1_lineage(field: str) -> dict:
    try:
        summary = json.loads(DESIGN_SOIL_QA_FILE.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, UnicodeDecodeError, OSError) as exc:
        raise ValueError("Workflow 1 Soil Type QA is missing or invalid; rerun Workflow 1") from exc
    checks = {
        "schema_version": str(summary.get("schema_version")) == DESIGN_SCHEMA_VERSION,
        "soil_input_present": summary.get("soil_input_present") is True,
        "source_field": summary.get("source_field") == field,
        "encoding": summary.get("encoding") == DESIGN_ENCODING,
        "source_sha256": summary.get("soil_source_sha256") == sha256_file(SOIL_FILE),
        "output_sha256": (
            DESIGN_SOIL_RASTER_FILE.exists()
            and summary.get("soil_group_raster_sha256") == sha256_file(DESIGN_SOIL_RASTER_FILE)
        ),
        "overlap_qa": isinstance(summary.get("whole_domain_overlap_qa"), dict)
        and summary["whole_domain_overlap_qa"].get("passed") is True,
    }
    code_labels = summary.get("code_labels")
    normalized = (
        {str(key): str(value) for key, value in code_labels.items()}
        if isinstance(code_labels, dict) else {}
    )
    checks["code_map_sha256"] = bool(normalized) and (
        summary.get("code_map_sha256") == canonical_sha256(normalized)
    )
    failed = [name for name, passed in checks.items() if not passed]
    if failed:
        raise ValueError(
            "Workflow 1 Soil Type lineage is stale ("
            + ", ".join(failed)
            + "); rerun Workflow 1 before interpolation"
        )
    return {
        "verified": True,
        "checks": checks,
        "soil_group_summary_sha256": sha256_file(DESIGN_SOIL_QA_FILE),
        "soil_source_sha256": sha256_file(SOIL_FILE),
        "design_soil_group_raster_sha256": sha256_file(DESIGN_SOIL_RASTER_FILE),
        "design_code_map_sha256": summary["code_map_sha256"],
        "source_registry_metadata": summary.get("source_registry_metadata"),
    }


def safe_dummy_name(group: str, code: int) -> str:
    safe = "".join(ch if ch.isalnum() else "_" for ch in group).strip("_") or "Group"
    return f"SoilDummy_{code:03d}_{safe}"


def output_inventory(paths: list[Path]) -> dict:
    return {
        project_path(path): {"size_bytes": path.stat().st_size, "sha256": sha256_file(path)}
        for path in paths if path.exists()
    }


def main() -> None:
    for path in (SOIL_FILE, POINT_FILE, PC_DIR / "PC1.tif"):
        if not path.exists():
            raise FileNotFoundError(path)
    ALIGNED_DIR.mkdir(parents=True, exist_ok=True)
    QA_DIR.mkdir(parents=True, exist_ok=True)

    field = setting("soil_group_field", "Ma1")
    design_lineage = verify_workflow1_lineage(field)
    soil = gpd.read_file(SOIL_FILE)
    if soil.crs is None:
        raise ValueError("Soil Type file has no CRS")
    if field not in soil.columns:
        raise ValueError(f"Soil Type file must contain field '{field}'.")
    soil = soil[[field, "geometry"]].copy()
    soil[field] = soil[field].fillna("").astype(str).str.strip()
    invalid = soil[field].str.casefold().isin(INVALID_LABELS)
    soil = soil[soil.geometry.notna() & ~soil.geometry.is_empty & ~invalid].copy()
    if soil.empty:
        raise ValueError("Soil Type has no valid polygon/class pair")
    reserved = sorted(
        label for label in soil[field].unique()
        if label.casefold() in RESERVED_TECHNICAL_LABELS
    )
    if reserved:
        raise ValueError(
            "Soil Type source uses reserved technical label(s): "
            + ", ".join(reserved)
            + ". Rename them; Unmapped and Other are reserved."
        )
    source_label_to_code = {
        label: index + 1 for index, label in enumerate(sorted(soil[field].unique()))
    }
    soil["_source_code"] = soil[field].map(source_label_to_code).astype("uint32")

    points = pd.read_csv(POINT_FILE)
    pts = gpd.GeoDataFrame(
        points, geometry=gpd.points_from_xy(points.lon, points.lat), crs="EPSG:4326"
    ).to_crs(soil.crs)
    joined = gpd.sjoin(
        pts[["code", "geometry"]], soil[[field, "geometry"]],
        how="left", predicate="within",
    )
    if len(joined) != len(points):
        raise ValueError("Soil polygons overlap at one or more sample locations.")
    joined[field] = joined[field].fillna("Unmapped")

    source_counts = joined[field].value_counts()
    mapped_counts = source_counts[source_counts.index != "Unmapped"]
    reference = str(mapped_counts.index[0]) if len(mapped_counts) else "Unmapped"
    retained = [str(group) for group, count in mapped_counts.items() if int(count) >= MIN_SAMPLES]
    if reference != "Unmapped" and reference not in retained:
        retained.insert(0, reference)
    non_reference = [group for group in retained if group != reference]
    collapsed_source_groups = sorted(set(soil[field].astype(str)) - set(retained))

    soil["model_group"] = soil[field].where(soil[field].isin(retained), "Other")
    sample_model_group = joined[field].where(
        joined[field].eq("Unmapped") | joined[field].isin(retained),
        "Other",
    )
    model_sample_counts = sample_model_group.value_counts()
    levels = list(dict.fromkeys([reference] + non_reference + ["Other", "Unmapped"]))
    if len(levels) >= NODATA:
        raise ValueError(f"Too many modeled Soil Type levels for uint8 encoding: {len(levels)}")
    group_to_code = {group: index + 1 for index, group in enumerate(levels)}
    soil["group_code"] = soil.model_group.map(group_to_code).astype("uint8")

    with rasterio.open(PC_DIR / "PC1.tif") as template:
        profile = template.profile.copy()
        pc = template.read(1)
        pc_valid = np.isfinite(pc)
        if template.nodata is not None and np.isfinite(template.nodata):
            pc_valid &= pc != template.nodata
        soil_grid = soil.to_crs(template.crs)
        coverage_count = rasterize(
            ((geom, 1) for geom in soil_grid.geometry if geom is not None and not geom.is_empty),
            out_shape=(template.height, template.width), transform=template.transform,
            fill=0, all_touched=False, dtype="uint32", merge_alg=MergeAlg.add,
        )
        feature_overlap_count = int(np.sum(pc_valid & (coverage_count > 1)))
        coverage_shapes = sorted(
            (
                (geom, int(code))
                for geom, code in zip(soil_grid.geometry, soil_grid["_source_code"])
                if geom is not None and not geom.is_empty
            ),
            key=lambda item: item[1],
        )
        lowest_label = rasterize(
            reversed(coverage_shapes),
            out_shape=(template.height, template.width), transform=template.transform,
            fill=0, all_touched=False, dtype="uint32",
        )
        highest_label = rasterize(
            coverage_shapes,
            out_shape=(template.height, template.width), transform=template.transform,
            fill=0, all_touched=False, dtype="uint32",
        )
        conflicting = pc_valid & (lowest_label > 0) & (highest_label > 0) & (
            lowest_label != highest_label
        )
        overlap_count = int(conflicting.sum())
        shapes = (
            (geom, int(code))
            for geom, code in zip(soil_grid.geometry, soil_grid.group_code)
            if geom is not None and not geom.is_empty
        )
        group = rasterize(
            shapes, out_shape=(template.height, template.width),
            transform=template.transform, fill=0, all_touched=True, dtype="uint8",
        )
    if overlap_count:
        failure_summary = {
            "schema_version": "3.0.0",
            "status": "FAILED_OVERLAPPING_SOIL_POLYGONS",
            "created_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
            "soil_source": project_path(SOIL_FILE),
            "soil_source_sha256": sha256_file(SOIL_FILE),
            "source_field": field,
            "workflow1_soil_lineage": design_lineage,
            "whole_domain_overlap_qa": {
                "method": "forward_reverse_label_conflict_at_pixel_centers_on_PC1_grid",
                "resolution_limit": "overlaps smaller than a PC1 grid cell may not be detected",
                "feature_overlap_pixel_count_any_label": feature_overlap_count,
                "conflicting_label_overlap_pixel_count": overlap_count,
                "overlap_pixel_count": overlap_count,
                "overlap_fraction_of_pc_domain": (
                    overlap_count / int(pc_valid.sum()) if int(pc_valid.sum()) else None
                ),
                "passed": False,
            },
        }
        (QA_DIR / "soil_predictor_summary.json").write_text(
            json.dumps(failure_summary, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        raise ValueError(
            f"Soil Type is ambiguous over {overlap_count} PC-grid pixel(s); "
            "fix polygon overlaps and rerun Workflow 1."
        )

    for pattern in ("Soil_*.tif", "SoilDummy_*.tif"):
        for existing in PC_DIR.glob(pattern):
            existing.unlink()

    unmapped_mask = pc_valid & (group == 0)
    unmapped_count = int(unmapped_mask.sum())
    group[unmapped_mask] = group_to_code["Unmapped"]
    group[~pc_valid] = NODATA
    group_raster = ALIGNED_DIR / "Soil_Group_Code.tif"
    write_byte_raster(group_raster, group, profile)

    dummy_names = []
    dummy_files = []
    unsupported_prediction_groups = []
    for model_group in levels:
        if model_group == reference:
            continue
        domain_count = int(np.sum(group == group_to_code[model_group]))
        sample_count = int(model_sample_counts.get(model_group, 0))
        if domain_count == 0:
            continue
        if sample_count == 0:
            unsupported_prediction_groups.append(model_group)
            continue
        layer_name = safe_dummy_name(model_group, group_to_code[model_group])
        dummy = np.where(group == group_to_code[model_group], 1, 0).astype("uint8")
        dummy[~pc_valid] = NODATA
        path = PC_DIR / f"{layer_name}.tif"
        write_byte_raster(path, dummy, profile)
        dummy_names.append(layer_name)
        dummy_files.append(path)

    manifest_rows = [
        {"layer": f"PC{i}", "file": f"PC{i}.tif", "type": "continuous", "resampling": "bilinear", "provenance": "PCA Workflow 1 frozen reference"}
        for i in range(1, 6)
    ]
    manifest_rows += [
        {"layer": name, "file": f"{name}.tif", "type": "categorical", "resampling": "near", "provenance": f"{field} reference-dummy nominal encoding"}
        for name in dummy_names
    ]
    pd.DataFrame(manifest_rows).to_csv(MANIFEST_FILE, index=False)

    point_groups = joined[["code", field]].copy()
    point_groups["soil_source_group"] = joined[field]
    point_groups["soil_model_group"] = sample_model_group
    point_groups_file = QA_DIR / "soil_predictor_point_groups.csv"
    point_groups.to_csv(point_groups_file, index=False)

    valid_pc_count = int(pc_valid.sum())
    code_labels = {str(code): group for group, code in group_to_code.items()}
    sparse_groups = {
        str(group): int(count) for group, count in model_sample_counts.items()
        if int(count) < MIN_SAMPLES
    }
    summary = {
        "schema_version": "3.0.0",
        "status": "READY",
        "created_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "soil_source": project_path(SOIL_FILE),
        "soil_source_sha256": sha256_file(SOIL_FILE),
        "source_field": field,
        "source_registry_metadata": design_lineage.get("source_registry_metadata"),
        "workflow1_soil_lineage": design_lineage,
        "source_sample_counts": {str(group): int(count) for group, count in source_counts.items()},
        "model_sample_counts": {str(group): int(count) for group, count in model_sample_counts.items()},
        "minimum_samples_to_retain_mapped_group": MIN_SAMPLES,
        "reference_group": reference,
        "retained_mapped_groups": retained,
        "collapsed_mapped_source_groups": collapsed_source_groups,
        "technical_group_semantics": {
            "Unmapped": "outside valid Soil Type polygon coverage; never a soil class",
            "Other": "pooled mapped source classes with insufficient sample support; never includes Unmapped",
        },
        "model_group_levels": levels,
        "model_group_code_labels": code_labels,
        "model_group_code_map_sha256": canonical_sha256(code_labels),
        "dummy_predictors": dummy_names,
        "encoding": MODEL_ENCODING,
        "unsupported_prediction_groups_assigned_reference_effect": unsupported_prediction_groups,
        "unsupported_group_policy": (
            "audit category remains explicit in Soil_Group_Code; no unestimable dummy is added, "
            "so the regression branch uses the reference-group soil effect and QA must be reviewed"
        ),
        "sparse_sample_groups": sparse_groups,
        "pc_valid_cells": valid_pc_count,
        "unmapped_cells": unmapped_count,
        "unmapped_percent_of_pc_domain": (
            100.0 * unmapped_count / valid_pc_count if valid_pc_count else None
        ),
        "whole_domain_overlap_qa": {
            "method": "forward_reverse_label_conflict_at_pixel_centers_on_PC1_grid",
            "resolution_limit": "overlaps smaller than a PC1 grid cell may not be detected",
            "feature_overlap_pixel_count_any_label": feature_overlap_count,
            "conflicting_label_overlap_pixel_count": overlap_count,
            "overlap_pixel_count": overlap_count,
            "overlap_fraction_of_pc_domain": overlap_count / valid_pc_count if valid_pc_count else None,
            "passed": overlap_count == 0,
        },
    }
    output_paths = [group_raster, *dummy_files, point_groups_file, MANIFEST_FILE]
    summary["output_file_sha256"] = output_inventory(output_paths)
    summary_file = QA_DIR / "soil_predictor_summary.json"
    summary_file.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(
        f"Soil predictors ready. Reference={reference}; dummies={','.join(dummy_names)}; "
        f"Unmapped cells={unmapped_count}; unsupported={','.join(unsupported_prediction_groups)}"
    )


if __name__ == "__main__":
    main()