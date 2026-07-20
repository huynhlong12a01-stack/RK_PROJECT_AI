"""Build PC rasters block-by-block to avoid loading the project grid into RAM."""

import json
import os
from pathlib import Path

import geopandas as gpd
import numpy as np
import rasterio
from rasterio.features import rasterize


ROOT = Path(__file__).resolve().parents[4]
PROJECT = ROOT / "projects" / "PHU_YEN_MOCK"
WORK = PROJECT / "_NOI_BO" / "work" / "design"
ALIGNED = WORK / "_aligned"
REFERENCE = PROJECT / "_NOI_BO" / "config" / "pca_model_reference.json"
TEMPLATE = WORK / "grid_template.tif"
ROI = PROJECT / "00_XAC_LAP_VUNG_MIA" / "01_DAU_VAO" / "roi_field_area.geojson"
FEATURES = ["CHIRPS", "DEM", "NDVI", "Slope", "TWI"]
NODATA = -9999.0


def same_grid(dataset, template):
    return (
        dataset.crs == template.crs
        and dataset.width == template.width
        and dataset.height == template.height
        and dataset.transform.almost_equals(template.transform)
    )


def main():
    required = [REFERENCE, TEMPLATE, ROI] + [ALIGNED / f"{x}.tif" for x in FEATURES]
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise FileNotFoundError("Missing streaming PCA input(s): " + ", ".join(missing))

    ref = json.loads(REFERENCE.read_text(encoding="utf-8"))
    if ref.get("feature_order") != FEATURES:
        raise ValueError("Frozen PCA feature order does not match streaming inputs.")
    means = np.asarray(ref["scaler_mean"], dtype="float64")
    scales = np.asarray(ref["scaler_scale"], dtype="float64")
    components = np.asarray(ref["pca_components"], dtype="float64")
    if means.shape != (5,) or scales.shape != (5,) or components.shape != (5, 5):
        raise ValueError("Expected a frozen 5-input, 5-component PCA reference.")
    if np.any(~np.isfinite(scales)) or np.any(scales == 0):
        raise ValueError("PCA scales contain zero or non-finite values.")

    sources = []
    outputs = []
    temp_paths = [WORK / f"PC{i}.building.tif" for i in range(1, 6)]
    final_paths = [WORK / f"PC{i}.tif" for i in range(1, 6)]
    try:
        with rasterio.open(TEMPLATE) as template:
            sources = [rasterio.open(ALIGNED / f"{name}.tif") for name in FEATURES]
            if not all(same_grid(src, template) for src in sources):
                raise ValueError("Aligned covariates do not match the computational grid.")

            roi = gpd.read_file(ROI)
            if roi.crs is None:
                raise ValueError("ROI has no CRS.")
            roi = roi.to_crs(template.crs)
            roi = roi[roi.geometry.notna() & ~roi.geometry.is_empty]
            mask = rasterize(
                [(geom, 1) for geom in roi.geometry],
                out_shape=(template.height, template.width),
                transform=template.transform,
                fill=0,
                all_touched=True,
                dtype="uint8",
            )

            profile = template.profile.copy()
            profile.update(
                driver="GTiff",
                count=1,
                dtype="float32",
                nodata=NODATA,
                compress="LZW",
                tiled=True,
                blockxsize=256,
                blockysize=256,
                BIGTIFF="IF_SAFER",
            )
            for path in temp_paths:
                if path.exists():
                    path.unlink()
                outputs.append(rasterio.open(path, "w", **profile))

            for _, window in template.block_windows(1):
                bands = np.stack(
                    [src.read(1, window=window).astype("float64") for src in sources],
                    axis=-1,
                )
                valid = np.all(np.isfinite(bands), axis=-1)
                for col, src in enumerate(sources):
                    if src.nodata is not None:
                        valid &= bands[:, :, col] != src.nodata
                r0, c0 = int(window.row_off), int(window.col_off)
                valid &= (
                    mask[
                        r0 : r0 + int(window.height),
                        c0 : c0 + int(window.width),
                    ]
                    == 1
                )
                scores = ((bands - means) / scales) @ components.T
                for col, dst in enumerate(outputs):
                    values = np.where(valid, scores[:, :, col], NODATA).astype(
                        "float32"
                    )
                    dst.write(values, 1, window=window)

        for dataset in outputs:
            dataset.close()
        outputs = []
        for temporary, final in zip(temp_paths, final_paths):
            os.replace(temporary, final)
    finally:
        for dataset in outputs:
            dataset.close()
        for dataset in sources:
            dataset.close()
        for path in temp_paths:
            if path.exists():
                path.unlink()

    print("Streaming PCA rasters ready: PC1-PC5 on the computational grid.")


if __name__ == "__main__":
    main()
