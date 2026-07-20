"""Generate deterministic MOCK lab values from the FULL sampling plan.

The output exists only to exercise the interpolation workflow. Values are
formula-generated from PC covariates, broad soil groups and seeded noise; they
are not observations and must not be used for agronomic interpretation.
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd
import rasterio


PROJECT = Path(__file__).resolve().parents[2]
PLAN = PROJECT / "01_THIET_KE_LAY_MAU" / "02_KET_QUA" / "sample_cLHS_FULL.csv"
DESIGN_WORK = PROJECT / "_NOI_BO" / "work" / "design"
INPUT_DIR = PROJECT / "02_NOI_SUY_BAN_DO" / "01_DAU_VAO"
SAMPLE_ACTUAL = INPUT_DIR / "sample_actual.csv"
SYNTHETIC_COPY = INPUT_DIR / "SYNTHETIC_sample_actual_DO_NOT_USE.csv"
METADATA = INPUT_DIR / "indicator_metadata.yml"
QA = PROJECT / "_NOI_BO" / "work" / "interpolation" / "qa" / "synthetic_lab_generation_QA.json"
MANIFEST = PROJECT / "MOCK_RUN_MANIFEST.json"
SEED = 20260715


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def sample_pcs(plan: pd.DataFrame) -> np.ndarray:
    coordinates = list(zip(plan["X_UTM"].astype(float), plan["Y_UTM"].astype(float)))
    columns = []
    for index in range(1, 6):
        path = DESIGN_WORK / f"PC{index}.tif"
        if not path.exists():
            raise FileNotFoundError(f"Missing PCA raster: {path}")
        with rasterio.open(path) as dataset:
            values = np.asarray([row[0] for row in dataset.sample(coordinates)], dtype=float)
            if dataset.nodata is not None:
                values[np.isclose(values, dataset.nodata)] = np.nan
        if not np.isfinite(values).all():
            raise ValueError(f"PC{index} has missing values at one or more FULL samples")
        columns.append(values)
    return np.column_stack(columns)


def zscore(values: np.ndarray) -> np.ndarray:
    mean = values.mean(axis=0)
    sd = values.std(axis=0, ddof=1)
    sd[~np.isfinite(sd) | (sd <= 0)] = 1
    return (values - mean) / sd


def main() -> None:
    if not PLAN.exists():
        raise FileNotFoundError("Run Stage 1 before generating mock laboratory values")
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if manifest.get("non_operational") is not True or manifest.get("map_use_prohibited") is not True:
        raise ValueError("Refusing to generate synthetic lab values without manifest safety flags")

    plan = pd.read_csv(PLAN)
    if len(plan) < 30:
        raise ValueError("FULL plan is too small for the interpolation smoke fixture")
    pcs = zscore(sample_pcs(plan))
    rng = np.random.default_rng(SEED)
    soil_name = plan["soil_group"].fillna("Other").astype(str)
    soil_ph = soil_name.map({"Fa": -0.25, "Xa": 0.15}).fillna(0).to_numpy()
    soil_om = soil_name.map({"Fa": 0.30, "Xa": -0.10}).fillna(0).to_numpy()
    soil_p = soil_name.map({"Fa": -0.12, "Xa": 0.18}).fillna(0).to_numpy()
    soil_k = soil_name.map({"Fa": 0.10, "Xa": -0.08}).fillna(0).to_numpy()
    east = (plan["X_UTM"].to_numpy() - plan["X_UTM"].mean()) / plan["X_UTM"].std(ddof=1)
    north = (plan["Y_UTM"].to_numpy() - plan["Y_UTM"].mean()) / plan["Y_UTM"].std(ddof=1)

    ph = 5.45 + 0.30 * pcs[:, 0] - 0.18 * pcs[:, 1] + 0.10 * east + soil_ph
    ph += rng.normal(0, 0.14, len(plan))
    om = 2.40 - 0.28 * pcs[:, 0] + 0.35 * pcs[:, 2] - 0.08 * north + soil_om
    om += rng.normal(0, 0.22, len(plan))
    log_p = np.log(13.0) + 0.24 * pcs[:, 1] - 0.18 * pcs[:, 3] + soil_p
    log_p += rng.normal(0, 0.20, len(plan))
    log_k = np.log(145.0) + 0.25 * pcs[:, 0] + 0.20 * pcs[:, 4] + soil_k
    log_k += rng.normal(0, 0.18, len(plan))

    output = pd.DataFrame(
        {
            "code": "MOCK_" + plan["Point_ID"].astype(str),
            "lat": plan["Latitude"].round(8),
            "lon": plan["Longitude"].round(8),
            "pH_H2O": np.clip(ph, 3.8, 7.8).round(2),
            "OM_pct": np.clip(om, 0.4, 9.0).round(2),
            "P_Olsen_mgkg": np.clip(np.exp(log_p), 1, 150).round(1),
            "K_available_mgkg": np.clip(np.exp(log_k), 20, 700).round(1),
        }
    )
    INPUT_DIR.mkdir(parents=True, exist_ok=True)
    output.to_csv(SAMPLE_ACTUAL, index=False, encoding="utf-8")
    output.to_csv(SYNTHETIC_COPY, index=False, encoding="utf-8")

    metadata_text = """# MOCK ONLY - FORMULA-GENERATED VALUES, NOT LABORATORY RESULTS
schema_version: 1
mock_only: true
non_operational: true
sample_support:
  interpretation: one_synthetic_average_result_per_sample
  one_row_per_sample: true
product_policy:
  nutrient_content_maps_only: true
  fertilizer_recommendation_enabled: false
  map_use_prohibited: true
targets:
  pH_H2O:
    confirmed: true
    profile_name: pH_H2O
    unit: "pH unit"
    laboratory_method: "SYNTHETIC_MOCK_FORMULA_NOT_LAB"
    extraction_ratio: "NOT_APPLICABLE_MOCK"
    classification: &mock_classification
      approved: false
      source: "MOCK_ONLY"
      version: "20260715"
      approved_by:
  OM_pct:
    confirmed: true
    profile_name: OM_pct
    unit: "%"
    laboratory_method: "SYNTHETIC_MOCK_FORMULA_NOT_LAB"
    extraction_ratio: "NOT_APPLICABLE_MOCK"
    classification: *mock_classification
  P_Olsen_mgkg:
    confirmed: true
    profile_name: P_Olsen_mgkg
    unit: "mg/kg"
    laboratory_method: "SYNTHETIC_MOCK_FORMULA_NOT_LAB"
    extraction_ratio: "NOT_APPLICABLE_MOCK"
    classification: *mock_classification
  K_available_mgkg:
    confirmed: true
    profile_name: K_available_mgkg
    unit: "mg/kg"
    laboratory_method: "SYNTHETIC_MOCK_FORMULA_NOT_LAB"
    extraction_ratio: "NOT_APPLICABLE_MOCK"
    classification: *mock_classification
"""
    METADATA.write_text(metadata_text, encoding="utf-8")

    qa = {
        "schema_version": 1,
        "created_utc": utc_now(),
        "project_id": "PHU_YEN_MOCK",
        "status": "SYNTHETIC_FIXTURE_READY",
        "non_operational": True,
        "map_use_prohibited": True,
        "random_seed": SEED,
        "n_samples": int(len(output)),
        "source_plan": "sample_cLHS_FULL.csv",
        "formula_predictors": ["PC1", "PC2", "PC3", "PC4", "PC5", "soil_group", "coordinates"],
        "targets": {
            column: {
                "minimum": float(output[column].min()),
                "maximum": float(output[column].max()),
                "mean": float(output[column].mean()),
            }
            for column in ("pH_H2O", "OM_pct", "P_Olsen_mgkg", "K_available_mgkg")
        },
        "interpretation": "software-test fixture only; not laboratory observations",
    }
    QA.parent.mkdir(parents=True, exist_ok=True)
    QA.write_text(json.dumps(qa, ensure_ascii=False, indent=2), encoding="utf-8")
    manifest["runtime"]["stage1_status"] = "PASS_MOCK_FULL105_REDUCED79_TRUE_CLHS_CORE"
    manifest["runtime"]["stage2_status"] = "SYNTHETIC_SAMPLE_ACTUAL_READY"
    manifest["synthetic_lab_generation"] = qa
    MANIFEST.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps(qa, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
