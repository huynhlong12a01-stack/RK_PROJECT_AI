"""Prepare nominal Soil Type factors for cLHS without collapsing classes."""

from __future__ import annotations

import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path

import geopandas as gpd
import numpy as np
import rasterio
import yaml
from rasterio.enums import MergeAlg
from rasterio.features import rasterize


ROOT = Path(__file__).resolve().parents[4]
PROJECT = ROOT / "projects" / "{{PROJECT_ID}}"
INPUT_DIR = PROJECT / "01_THIET_KE_LAY_MAU" / "01_DAU_VAO"
WORK_DIR = PROJECT / "_NOI_BO" / "work" / "design"
SOIL_FILE = INPUT_DIR / "soil_type.geojson"
SETTINGS_FILE = INPUT_DIR / "sampling.yml"
TEMPLATE_FILE = WORK_DIR / "PC1.tif"
OUTPUT_FILE = WORK_DIR / "Soil_Group_Code.tif"
QA_FILE = WORK_DIR / "qa" / "soil_group_summary.json"
SHARED_SOIL_PROVENANCE_FILE = ROOT / "shared_data" / "soil_type_vietnam" / "provenance.yml"
NODATA = np.iinfo("uint16").max
ENCODING = "nominal_factor_codes_v1; codes are labels, not ordinal values"
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


def source_registry_metadata() -> dict:
    if not SHARED_SOIL_PROVENANCE_FILE.exists():
        return {"metadata_present": False}
    result = {
        "metadata_present": True,
        "metadata_file": str(SHARED_SOIL_PROVENANCE_FILE.relative_to(ROOT)).replace("\\", "/"),
        "metadata_sha256": sha256_file(SHARED_SOIL_PROVENANCE_FILE),
    }
    try:
        payload = yaml.safe_load(
            SHARED_SOIL_PROVENANCE_FILE.read_text(encoding="utf-8")
        ) or {}
    except (yaml.YAMLError, UnicodeDecodeError, OSError) as exc:
        result.update({"metadata_readable": False, "warning": str(exc)})
        return result
    source = payload.get("source") if isinstance(payload.get("source"), dict) else {}
    application = (
        payload.get("application_use")
        if isinstance(payload.get("application_use"), dict) else {}
    )
    registered_hash = payload.get("sha256")
    result.update(
        {
            "metadata_readable": True,
            "dataset_id": payload.get("dataset_id"),
            "registered_raw_file": payload.get("local_file"),
            "registered_raw_sha256": registered_hash,
            "source_documentation_status": source.get("status"),
            "license": source.get("license"),
            "external_publication_status": application.get("external_publication_status"),
            "project_soil_matches_registered_raw": (
                SOIL_FILE.exists()
                and isinstance(registered_hash, str)
                and sha256_file(SOIL_FILE) == registered_hash.lower()
            ),
            "interpretation": (
                "informational registry only; the project Soil Type bytes are "
                "independently locked below and processing is not blocked by an unknown license"
            ),
        }
    )
    return result


def setting(name: str, default: str) -> str:
    if not SETTINGS_FILE.exists():
        return default
    text = SETTINGS_FILE.read_text(encoding="utf-8")
    match = re.search(rf"(?m)^[ \t]*{re.escape(name)}[ \t]*:[ \t]*([^#\r\n]+)", text)
    return match.group(1).strip().strip("\"'") if match else default


def pc_valid_mask(template: rasterio.io.DatasetReader) -> np.ndarray:
    pc = template.read(1)
    valid = np.isfinite(pc)
    if template.nodata is not None and np.isfinite(template.nodata):
        valid &= pc != template.nodata
    return valid


def main() -> None:
    if not TEMPLATE_FILE.exists():
        raise FileNotFoundError(f"PCA raster is missing: {TEMPLATE_FILE}")

    with rasterio.open(TEMPLATE_FILE) as template:
        profile = template.profile.copy()
        valid = pc_valid_mask(template)
        valid_count = int(valid.sum())
        if valid_count == 0:
            raise ValueError("PC1 has no valid sampling-domain pixel")

        if not SOIL_FILE.exists():
            values = np.full((template.height, template.width), NODATA, dtype="uint16")
            values[valid] = 1
            labels = ["All"]
            code_labels = {1: "All"}
            source_feature_count = 0
            source_area = {}
            mapped_count = valid_count
            unmapped_count = 0
            unmapped_code = None
            mode = "without_soil_type"
            field = None
            overlap_count = 0
            feature_overlap_count = 0
            overlap_method = "not_applicable_no_soil_input"
        else:
            field = setting("soil_group_field", "Ma1")
            soil = gpd.read_file(SOIL_FILE)
            if field not in soil.columns:
                raise ValueError(f"Soil Type exists but field '{field}' is missing")
            soil = soil[[field, "geometry"]].copy()
            soil[field] = soil[field].fillna("").astype(str).str.strip()
            invalid_label = soil[field].str.lower().isin({"", "nan", "none", "null", "na"})
            soil = soil[
                soil.geometry.notna() & ~soil.geometry.is_empty & ~invalid_label
            ].copy()
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
                    + ". Rename them before Workflow 1; Unmapped and Other are reserved."
                )

            soil = soil.to_crs(template.crs)
            # Rank source classes with a metric equal-area CRS. The raster
            # template can legitimately be geographic in tests or future
            # projects, where geometry.area would otherwise be square degrees.
            soil["_area_m2"] = soil.to_crs("EPSG:6933").geometry.area.to_numpy()
            area_table = (
                soil.groupby(field, as_index=False)["_area_m2"]
                .sum()
                .sort_values(["_area_m2", field], ascending=[False, True])
                .reset_index(drop=True)
            )
            labels = area_table[field].astype(str).tolist()
            # Reserve one code for the explicit Unmapped factor and one for nodata.
            if len(labels) > NODATA - 2:
                raise ValueError(
                    f"Too many Soil Type levels for uint16 encoding: {len(labels)}"
                )
            label_to_code = {label: index + 1 for index, label in enumerate(labels)}
            soil["_code"] = soil[field].map(label_to_code).astype("uint16")
            # Whole-domain ambiguity check at PC1 grid resolution. Pixel centres
            # avoid treating shared polygon boundaries as overlap.
            coverage_count = rasterize(
                (
                    (geometry, 1)
                    for geometry in soil.geometry
                    if geometry is not None and not geometry.is_empty
                ),
                out_shape=(template.height, template.width),
                transform=template.transform,
                fill=0,
                all_touched=False,
                dtype="uint32",
                merge_alg=MergeAlg.add,
            )
            feature_overlap_count = int(np.sum(valid & (coverage_count > 1)))
            coverage_shapes = sorted(
                (
                    (geometry, int(code))
                    for geometry, code in zip(soil.geometry, soil["_code"])
                    if geometry is not None and not geometry.is_empty
                ),
                key=lambda item: item[1],
            )
            lowest_label = rasterize(
                reversed(coverage_shapes),
                out_shape=(template.height, template.width),
                transform=template.transform,
                fill=0,
                all_touched=False,
                dtype="uint16",
            )
            highest_label = rasterize(
                coverage_shapes,
                out_shape=(template.height, template.width),
                transform=template.transform,
                fill=0,
                all_touched=False,
                dtype="uint16",
            )
            conflicting = valid & (lowest_label > 0) & (highest_label > 0) & (
                lowest_label != highest_label
            )
            overlap_count = int(conflicting.sum())
            overlap_method = "forward_reverse_label_conflict_at_pixel_centers_on_PC1_grid"
            values = rasterize(
                (
                    (geometry, int(code))
                    for geometry, code in zip(soil.geometry, soil["_code"])
                    if geometry is not None and not geometry.is_empty
                ),
                out_shape=(template.height, template.width),
                transform=template.transform,
                fill=int(NODATA),
                all_touched=True,
                dtype="uint16",
            )
            values[~valid] = NODATA
            mapped_before_unmapped = valid & (values != NODATA)
            mapped_count = int(mapped_before_unmapped.sum())
            unmapped = valid & (values == NODATA)
            unmapped_count = int(unmapped.sum())
            unmapped_code = len(labels) + 1
            values[unmapped] = unmapped_code
            code_labels = {
                **{code: label for label, code in label_to_code.items()},
                unmapped_code: "Unmapped",
            }
            source_feature_count = int(len(soil))
            source_area = dict(zip(area_table[field].astype(str), area_table["_area_m2"]))
            mode = "with_soil_type_all_valid_levels"

        values[~valid] = NODATA
        profile.update(
            driver="GTiff",
            count=1,
            dtype="uint16",
            nodata=int(NODATA),
            compress="LZW",
            tiled=True,
            blockxsize=256,
            blockysize=256,
            BIGTIFF="IF_SAFER",
        )

    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    QA_FILE.parent.mkdir(parents=True, exist_ok=True)
    with rasterio.open(OUTPUT_FILE, "w", **profile) as destination:
        destination.write(values, 1)

    code_label_payload = {str(code): label for code, label in code_labels.items()}
    source_area_total = float(sum(source_area.values())) if source_area else 0.0
    classes = []
    for code, label in code_labels.items():
        count = int(np.sum(values == code))
        area_m2 = source_area.get(label)
        classes.append(
            {
                "code": int(code),
                "label": label,
                "source_polygon_area_ha": (
                    float(area_m2) / 10_000 if area_m2 is not None else None
                ),
                "source_polygon_area_fraction": (
                    float(area_m2) / source_area_total
                    if area_m2 is not None and source_area_total > 0
                    else None
                ),
                "candidate_domain_pixel_count": count,
                "candidate_domain_pixel_fraction": count / valid_count,
                "present_in_candidate_domain": count > 0,
                "missingness_factor": label == "Unmapped",
            }
        )

    qa = {
        "schema_version": "3.0.0",
        "created_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "project_id": "{{PROJECT_ID}}",
        "mode": mode,
        "soil_file": str(SOIL_FILE.relative_to(ROOT)).replace("\\", "/") if SOIL_FILE.exists() else None,
        "soil_input_present": SOIL_FILE.exists(),
        "soil_source_sha256": sha256_file(SOIL_FILE) if SOIL_FILE.exists() else None,
        "source_registry_metadata": source_registry_metadata(),
        "source_field": field,
        "encoding": ENCODING,
        "technical_labels": {
            "unmapped": "outside valid Soil Type polygon coverage",
            "other": "reserved for later model pooling of mapped classes; not used in cLHS design",
        },
        "dtype": "uint16",
        "nodata": int(NODATA),
        "all_valid_levels_preserved": True,
        "top_n_or_other_collapse_applied": False,
        "n_source_features": source_feature_count,
        "n_source_levels": len(labels) if SOIL_FILE.exists() else 0,
        "n_levels_in_candidate_domain": sum(
            row["present_in_candidate_domain"] for row in classes
        ),
        "code_labels": code_label_payload,
        "code_map_sha256": canonical_sha256(code_label_payload),
        "soil_group_raster": str(OUTPUT_FILE.relative_to(ROOT)).replace("\\", "/"),
        "soil_group_raster_sha256": sha256_file(OUTPUT_FILE),
        "classes": classes,
        "pc_valid_roi_pixels": valid_count,
        "mapped_soil_roi_pixels": mapped_count,
        "mapped_soil_roi_fraction": mapped_count / valid_count,
        "unmapped_soil_roi_pixels": unmapped_count,
        "unmapped_soil_roi_fraction": unmapped_count / valid_count,
        "unmapped_factor_code": unmapped_code,
        "unmapped_factor_label": "Unmapped" if unmapped_code is not None else None,
        "unmapped_policy": (
            "retained_as_explicit_nominal_factor_level"
            if SOIL_FILE.exists()
            else "not_applicable_no_soil_input"
        ),
        "candidate_domain_retained_fraction": 1.0,
        "target_population_reduced_due_to_missing_soil": False,
        "whole_domain_overlap_qa": {
            "method": overlap_method,
            "resolution_limit": (
                "overlaps smaller than a PC1 grid cell may not be detected"
                if SOIL_FILE.exists() else None
            ),
            "feature_overlap_pixel_count_any_label": feature_overlap_count,
            "conflicting_label_overlap_pixel_count": overlap_count,
            "overlap_pixel_count": overlap_count,
            "overlap_fraction_of_pc_domain": overlap_count / valid_count,
            "passed": overlap_count == 0,
        },
    }
    QA_FILE.write_text(
        json.dumps(qa, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    if overlap_count:
        raise ValueError(
            f"Soil Type is ambiguous: {overlap_count} PC-grid pixel(s) are covered "
            "by more than one polygon. See soil_group_summary.json."
        )
    if SOIL_FILE.exists():
        print(
            f"Soil grouping ready: {len(labels)} source levels + Unmapped; "
            f"mapped PC/ROI fraction={mapped_count / valid_count:.6f}; "
            "candidate-domain retention=100%"
        )
    else:
        print("Soil grouping ready: no Soil Type input; single All factor")


if __name__ == "__main__":
    main()
