import json
import re
from pathlib import Path

import geopandas as gpd
import numpy as np
import pandas as pd
import rasterio
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


def setting(name, default):
    if not SETTINGS_FILE.exists():
        return default
    text = SETTINGS_FILE.read_text(encoding="utf-8")
    match = re.search(rf"(?m)^\s*{re.escape(name)}\s*:\s*([^#\r\n]+)", text)
    return match.group(1).strip().strip("\"'") if match else default


MIN_SAMPLES = 5
NODATA = 255


def write_byte_raster(path, array, profile, nodata=NODATA):
    out_profile = profile.copy()
    out_profile.update(
        driver="GTiff",
        count=1,
        dtype="uint8",
        nodata=nodata,
        compress="LZW",
        tiled=True,
        blockxsize=256,
        blockysize=256,
        BIGTIFF="IF_SAFER",
    )
    with rasterio.open(path, "w", **out_profile) as dst:
        dst.write(array.astype("uint8"), 1)


def main():
    for path in (SOIL_FILE, POINT_FILE, PC_DIR / "PC1.tif"):
        if not path.exists():
            raise FileNotFoundError(path)
    ALIGNED_DIR.mkdir(parents=True, exist_ok=True)
    QA_DIR.mkdir(parents=True, exist_ok=True)

    soil = gpd.read_file(SOIL_FILE)
    field = setting("soil_group_field", "Ma1")
    if field not in soil.columns:
        raise ValueError(f"Soil Type file must contain field '{field}'.")
    soil = soil[[field, "geometry"]].copy()
    soil[field] = soil[field].astype(str).str.strip()
    soil = soil[soil.geometry.notna() & ~soil.geometry.is_empty].copy()

    points = pd.read_csv(POINT_FILE)
    pts = gpd.GeoDataFrame(
        points,
        geometry=gpd.points_from_xy(points.lon, points.lat),
        crs="EPSG:4326",
    ).to_crs(soil.crs)
    joined = gpd.sjoin(
        pts[["code", "geometry"]], soil[[field, "geometry"]],
        how="left", predicate="within"
    )
    if len(joined) != len(points):
        raise ValueError("Soil polygons overlap at one or more sample locations.")
    joined[field] = joined[field].fillna("Other")

    counts = joined[field].value_counts()
    known_counts = counts[counts.index != "Other"]
    reference = str(known_counts.index[0]) if len(known_counts) else "Other"
    retained = [str(k) for k, n in known_counts.items() if int(n) >= MIN_SAMPLES]
    if reference != "Other" and reference not in retained:
        retained.insert(0, reference)
    non_reference = [k for k in retained if k != reference]
    levels = list(dict.fromkeys([reference] + non_reference + ["Other"]))

    soil["model_group"] = soil[field].where(soil[field].isin(retained), "Other")
    group_to_code = {group: idx + 1 for idx, group in enumerate(levels)}
    soil["group_code"] = soil.model_group.map(group_to_code).astype("uint8")

    with rasterio.open(PC_DIR / "PC1.tif") as template:
        profile = template.profile.copy()
        pc = template.read(1)
        pc_valid = np.isfinite(pc)
        if template.nodata is not None and np.isfinite(template.nodata):
            pc_valid &= pc != template.nodata
        soil_utm = soil.to_crs(template.crs)
        shapes = (
            (geom, int(code))
            for geom, code in zip(soil_utm.geometry, soil_utm.group_code)
            if geom is not None and not geom.is_empty
        )
        group = rasterize(
            shapes,
            out_shape=(template.height, template.width),
            transform=template.transform,
            fill=0,
            all_touched=True,
            dtype="uint8",
        )

    for pattern in ("Soil_*.tif", "SoilDummy_*.tif"):
        for existing in PC_DIR.glob(pattern):
            existing.unlink()

    missing_soil = pc_valid & (group == 0)
    missing_count = int(missing_soil.sum())
    # Unknown soil cells are conservatively assigned to Other so the soil layer
    # does not remove otherwise valid PC cells. Their proportion is reported.
    group[missing_soil] = group_to_code["Other"]
    group[~pc_valid] = NODATA
    write_byte_raster(ALIGNED_DIR / "Soil_Group_Code.tif", group, profile)

    dummy_names = []
    for model_group in levels:
        if model_group == reference:
            continue
        safe = "".join(ch if ch.isalnum() else "_" for ch in model_group)
        layer_name = f"SoilDummy_{safe}"
        dummy = np.where(group == group_to_code[model_group], 1, 0).astype("uint8")
        dummy[~pc_valid] = NODATA
        write_byte_raster(PC_DIR / f"{layer_name}.tif", dummy, profile)
        dummy_names.append(layer_name)
    manifest_rows = [
        {"layer": f"PC{i}", "file": f"PC{i}.tif", "type": "continuous", "resampling": "bilinear", "provenance": "PCA workflow 1 reference"} for i in range(1, 6)
    ]
    manifest_rows += [{"layer": name, "file": f"{name}.tif", "type": "categorical", "resampling": "near", "provenance": f"{field} reference-dummy encoding"} for name in dummy_names]
    pd.DataFrame(manifest_rows).to_csv(MANIFEST_FILE, index=False)

    point_groups = joined[["code", field]].copy()
    point_groups["soil_model_group"] = point_groups[field].where(
        point_groups[field].isin(retained), "Other"
    )
    point_groups.to_csv(QA_DIR / "soil_predictor_point_groups.csv", index=False)

    valid_pc_count = int(pc_valid.sum())
    summary = {
        "soil_source": str(SOIL_FILE).replace("\\", "/"),
        "source_field": field,
        "sample_counts": {str(k): int(v) for k, v in counts.items()},
        "minimum_samples_to_retain_group": MIN_SAMPLES,
        "reference_group": reference,
        "retained_groups": retained,
        "collapsed_group": "Other",
        "model_group_levels": levels,
        "dummy_predictors": dummy_names,
        "encoding": "reference dummy encoding; soil codes are not ordinal",
        "pc_valid_cells": valid_pc_count,
        "soil_unknown_cells_assigned_other": missing_count,
        "soil_unknown_percent_of_pc_domain": (
            100.0 * missing_count / valid_pc_count if valid_pc_count else None
        ),
    }
    (QA_DIR / "soil_predictor_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(
        f"Soil predictors ready. Reference={reference}; "
        f"dummies={','.join(dummy_names)}; unknown_cells={missing_count}"
    )


if __name__ == "__main__":
    main()
