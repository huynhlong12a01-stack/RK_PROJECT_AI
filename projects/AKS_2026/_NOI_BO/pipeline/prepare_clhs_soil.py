import json
import re
from pathlib import Path

import geopandas as gpd
import numpy as np
import rasterio
from rasterio.features import rasterize


ROOT = Path(__file__).resolve().parents[4]
PROJECT = ROOT / "projects" / "AKS_2026"
INPUT_DIR = PROJECT / "01_THIET_KE_LAY_MAU" / "01_DAU_VAO"
WORK_DIR = PROJECT / "_NOI_BO" / "work" / "design"
SOIL_FILE = INPUT_DIR / "soil_type.geojson"
SETTINGS_FILE = INPUT_DIR / "sampling.yml"
TEMPLATE_FILE = WORK_DIR / "PC1.tif"
OUTPUT_FILE = WORK_DIR / "Soil_Group_Code.tif"
QA_FILE = WORK_DIR / "qa" / "soil_group_summary.json"
NODATA = 255


def setting(name, default):
    if not SETTINGS_FILE.exists():
        return default
    text = SETTINGS_FILE.read_text(encoding="utf-8")
    match = re.search(rf"(?m)^\s*{re.escape(name)}\s*:\s*([^#\r\n]+)", text)
    return match.group(1).strip().strip('"\'') if match else default


def main():
    if not TEMPLATE_FILE.exists():
        raise FileNotFoundError(f"PCA raster is missing: {TEMPLATE_FILE}")
    with rasterio.open(TEMPLATE_FILE) as template:
        profile = template.profile.copy()
        pc = template.read(1)
        valid = np.isfinite(pc)
        if template.nodata is not None and np.isfinite(template.nodata):
            valid &= pc != template.nodata
        values = np.zeros((template.height, template.width), dtype="uint8")
        code_labels = {1: "All"}
        mode = "without_soil_type"
        retained = []

        if SOIL_FILE.exists():
            field = setting("soil_group_field", "Ma1")
            soil = gpd.read_file(SOIL_FILE)
            if field not in soil.columns:
                raise ValueError(f"Soil Type exists but field '{field}' is missing.")
            soil = soil[[field, "geometry"]].copy()
            soil[field] = soil[field].astype(str).str.strip()
            soil = soil[soil.geometry.notna() & ~soil.geometry.is_empty].copy()
            if soil.empty:
                raise ValueError("Soil Type kh?ng c? polygon h?p l?.")
            soil = soil.to_crs(template.crs)
            area_by_class = soil.assign(_area=soil.geometry.area).groupby(field)._area.sum().sort_values(ascending=False)
            retained = [str(x) for x in area_by_class.index[:2]]
            code_labels = {1: retained[0]}
            if len(retained) > 1:
                code_labels[2] = retained[1]
            code_labels[3] = "Other"
            class_to_code = {label: code for code, label in code_labels.items() if label != "Other"}
            soil["_code"] = soil[field].map(class_to_code).fillna(3).astype("uint8")
            values = rasterize(
                ((geom, int(code)) for geom, code in zip(soil.geometry, soil._code)),
                out_shape=(template.height, template.width),
                transform=template.transform,
                fill=0,
                all_touched=True,
                dtype="uint8",
            )
            values[valid & (values == 0)] = 3
            mode = "with_soil_type"
        else:
            values[valid] = 1

    values[~valid] = NODATA
    profile.update(driver="GTiff", count=1, dtype="uint8", nodata=NODATA, compress="LZW", tiled=True, blockxsize=256, blockysize=256, BIGTIFF="IF_SAFER")
    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    QA_FILE.parent.mkdir(parents=True, exist_ok=True)
    with rasterio.open(OUTPUT_FILE, "w", **profile) as dst:
        dst.write(values, 1)
    counts = {str(code_labels[code]): int(np.sum(values == code)) for code in code_labels}
    QA_FILE.write_text(json.dumps({"mode": mode, "soil_file": str(SOIL_FILE), "code_labels": {str(k): v for k, v in code_labels.items()}, "pixel_counts": counts, "retained_classes": retained}, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Soil grouping ready: {mode}")


if __name__ == "__main__":
    main()
