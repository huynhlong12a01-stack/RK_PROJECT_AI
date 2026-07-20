"""Rasterize every valid Ma1 level for PHU_YEN_MOCK sample design.

Unlike the legacy top-two/Other helper, this project-local implementation
preserves every mapped soil class as a nominal cLHS factor. Unmapped cells are
reported and excluded from the cLHS candidate population rather than silently
folded into an artificial Other class.
"""

from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path

import geopandas as gpd
import numpy as np
import rasterio
from rasterio.features import rasterize


ROOT = Path(__file__).resolve().parents[4]
PROJECT = ROOT / "projects" / "PHU_YEN_MOCK"
INPUT_DIR = PROJECT / "01_THIET_KE_LAY_MAU" / "01_DAU_VAO"
WORK_DIR = PROJECT / "_NOI_BO" / "work" / "design"
SOIL_FILE = INPUT_DIR / "soil_type.geojson"
SETTINGS_FILE = INPUT_DIR / "sampling.yml"
TEMPLATE_FILE = WORK_DIR / "PC1.tif"
OUTPUT_FILE = WORK_DIR / "Soil_Group_Code.tif"
QA_FILE = WORK_DIR / "qa" / "soil_group_summary.json"
NODATA = 255


def setting(name: str, default: str) -> str:
    if not SETTINGS_FILE.exists():
        return default
    text = SETTINGS_FILE.read_text(encoding="utf-8")
    match = re.search(rf"(?m)^[ \t]*{re.escape(name)}[ \t]*:[ \t]*([^#\r\n]+)", text)
    return match.group(1).strip().strip("\"'") if match else default


def main() -> None:
    if not TEMPLATE_FILE.exists():
        raise FileNotFoundError(f"PCA raster is missing: {TEMPLATE_FILE}")
    if not SOIL_FILE.exists():
        raise FileNotFoundError(f"Soil Type is required for this fixture: {SOIL_FILE}")

    field = setting("soil_group_field", "Ma1")
    soil = gpd.read_file(SOIL_FILE)
    if field not in soil.columns:
        raise ValueError(f"Soil Type exists but field '{field}' is missing")
    soil = soil[[field, "geometry"]].copy()
    soil[field] = soil[field].fillna("").astype(str).str.strip()
    soil = soil[
        soil.geometry.notna()
        & ~soil.geometry.is_empty
        & ~soil[field].isin(["", "nan", "None", "NULL"])
    ].copy()
    if soil.empty:
        raise ValueError("Soil Type has no valid polygon/class pairs")

    with rasterio.open(TEMPLATE_FILE) as template:
        profile = template.profile.copy()
        pc = template.read(1)
        pc_valid = np.isfinite(pc)
        if template.nodata is not None and np.isfinite(template.nodata):
            pc_valid &= pc != template.nodata
        soil_projected = soil.to_crs(template.crs)
        soil_projected["_area_m2"] = soil_projected.geometry.area
        area_table = (
            soil_projected.groupby(field, as_index=False)["_area_m2"]
            .sum()
            .sort_values(["_area_m2", field], ascending=[False, True])
            .reset_index(drop=True)
        )
        labels = area_table[field].astype(str).tolist()
        if len(labels) > 253:
            raise ValueError(f"Too many Soil Type levels for uint8: {len(labels)}")
        label_to_code = {label: index + 1 for index, label in enumerate(labels)}
        code_to_label = {code: label for label, code in label_to_code.items()}
        soil_projected["_code"] = soil_projected[field].map(label_to_code).astype("uint8")
        values = rasterize(
            (
                (geometry, int(code))
                for geometry, code in zip(soil_projected.geometry, soil_projected["_code"])
                if geometry is not None and not geometry.is_empty
            ),
            out_shape=(template.height, template.width),
            transform=template.transform,
            fill=NODATA,
            all_touched=True,
            dtype="uint8",
        )
        values[~pc_valid] = NODATA

    mapped = pc_valid & (values != NODATA)
    unmapped = pc_valid & (values == NODATA)
    mapped_count = int(mapped.sum())
    pc_valid_count = int(pc_valid.sum())
    if mapped_count == 0:
        raise ValueError("No valid Soil Type pixel overlaps the PC/ROI domain")

    profile.update(
        driver="GTiff",
        count=1,
        dtype="uint8",
        nodata=NODATA,
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

    class_rows = []
    total_vector_area = float(area_table["_area_m2"].sum())
    for _, row in area_table.iterrows():
        label = str(row[field])
        code = label_to_code[label]
        pixel_count = int(np.sum(values == code))
        area_m2 = float(row["_area_m2"])
        class_rows.append(
            {
                "code": code,
                "label": label,
                "source_polygon_area_ha": area_m2 / 10_000,
                "source_polygon_area_fraction": area_m2 / total_vector_area,
                "mapped_roi_pixel_count": pixel_count,
                "mapped_roi_pixel_fraction": pixel_count / mapped_count,
                "pc_roi_pixel_fraction": pixel_count / pc_valid_count,
            }
        )
    qa = {
        "schema_version": 2,
        "created_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "project_id": "PHU_YEN_MOCK",
        "mode": "with_soil_type_all_valid_levels",
        "soil_file": str(SOIL_FILE).replace("\\", "/"),
        "source_field": field,
        "encoding": "nominal_factor_codes; codes are not ordinal",
        "dtype": "uint8",
        "nodata": NODATA,
        "all_valid_levels_preserved": True,
        "top_n_or_other_collapse_applied": False,
        "n_source_features": int(len(soil)),
        "n_levels": int(len(labels)),
        "code_labels": {str(code): label for code, label in code_to_label.items()},
        "classes": class_rows,
        "pc_valid_roi_pixels": pc_valid_count,
        "mapped_soil_roi_pixels": mapped_count,
        "mapped_soil_roi_fraction": mapped_count / pc_valid_count,
        "unmapped_soil_roi_pixels": int(unmapped.sum()),
        "unmapped_soil_roi_fraction": int(unmapped.sum()) / pc_valid_count,
        "unmapped_policy": "excluded_from_cLHS_candidate_population_as_nodata",
        "mock_only": True,
    }
    QA_FILE.write_text(json.dumps(qa, ensure_ascii=False, indent=2), encoding="utf-8")
    print(
        f"Soil grouping ready: {len(labels)} levels; "
        f"mapped PC/ROI fraction={mapped_count / pc_valid_count:.6f}"
    )


if __name__ == "__main__":
    main()
