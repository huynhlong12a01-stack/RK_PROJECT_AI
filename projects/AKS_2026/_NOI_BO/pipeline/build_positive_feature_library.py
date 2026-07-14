#!/usr/bin/env python3
"""Extract a bounded Sentinel-1/2 feature library for confirmed AKS positives.

This is a positive-class reference table, not a fitted classifier.  It is useful
for inspecting temporal signatures and may augment a future training fold only
after the labels are re-confirmed for the target year/region.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import geopandas as gpd
import numpy as np
import pandas as pd


def load_core(path: Path):
    spec = importlib.util.spec_from_file_location("field_area_core_for_features", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load field-area core: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-dir", required=True)
    args = parser.parse_args()
    project = Path(args.project_dir).resolve()
    internal = project / "_NOI_BO"
    core = load_core(internal / "pipeline" / "interpret_sugarcane_area.py")
    paths = core.ProjectPaths.from_project(project)
    config, config_path = core.config_for(paths)
    package = paths.work / "reference_package"
    reference_path = package / "positive_reference.geojson"
    card_path = package / "model_card.json"
    if not reference_path.exists() or not card_path.exists():
        raise FileNotFoundError("Run field-area workflow first to build the bounded positive reference package")

    card = json.loads(card_path.read_text(encoding="utf-8"))
    if card.get("artifact_type") != "positive_reference_only":
        raise ValueError("This extractor is restricted to a positive_reference_only package")
    references = gpd.read_file(reference_path).to_crs(4326)
    references["reference_id"] = [f"AKS_POS_{i + 1:04d}" for i in range(len(references))]
    references["label"] = 1
    references["evaluation_eligible"] = False

    import ee

    ee.Initialize(project=str(config["gee_project_id"]) or None)
    roi_path = project / "01_THIET_KE_LAY_MAU" / "01_DAU_VAO" / "roi.geojson"
    roi = core.read_vector(roi_path).to_crs(4326)
    roi_geom = core.gdf_to_ee(roi).geometry()
    stack, bands, scene_counts = core.gee_feature_stack(config, roi_geom)
    reference_fc = core.gdf_to_ee(references)
    sampled = stack.sampleRegions(
        collection=reference_fc,
        properties=["reference_id", "label", "evaluation_eligible", "source_project", "label_basis"],
        scale=int(config["resolution_m"]),
        geometries=True,
        tileScale=8,
    )
    payload = sampled.getInfo()
    rows = []
    for feature in payload.get("features", []):
        props = feature.get("properties", {})
        coordinates = feature.get("geometry", {}).get("coordinates", [None, None])
        row = {
            "reference_id": props.get("reference_id"),
            "lon": coordinates[0],
            "lat": coordinates[1],
            "label": 1,
            "evaluation_eligible": False,
            "source_project": props.get("source_project", project.name),
            "label_basis": props.get("label_basis", "inside_confirmed_field_area"),
        }
        for band in bands:
            row[band] = props.get(band)
        rows.append(row)
    table = pd.DataFrame(rows)
    complete = table[bands].notna().all(axis=1) if not table.empty else pd.Series(dtype=bool)
    table["feature_complete"] = complete
    output_path = package / "positive_temporal_features.csv"
    table.to_csv(output_path, index=False, encoding="utf-8")

    summaries = {}
    for band in bands:
        values = pd.to_numeric(table[band], errors="coerce").dropna()
        summaries[band] = {
            "n": int(len(values)),
            "p01": float(values.quantile(0.01)) if len(values) else None,
            "median": float(values.median()) if len(values) else None,
            "p99": float(values.quantile(0.99)) if len(values) else None,
        }
    domain_path = package / "positive_feature_domain.json"
    domain = {
        "schema_version": core.SCHEMA_VERSION,
        "status": "POSITIVE_CLASS_DOMAIN_ONLY",
        "not_binary_aoa": True,
        "feature_schema_sha256": sha256_file(package / "feature_schema.json"),
        "target_year": int(config["target_year"]),
        "scene_counts": scene_counts,
        "features": summaries,
    }
    core.write_json(domain_path, domain)

    card["positive_feature_library"] = {
        "status": "POSITIVE_CLASS_TEMPORAL_FEATURES_EXTRACTED",
        "path": str(output_path.resolve()),
        "sha256": sha256_file(output_path),
        "n_reference_points": int(len(references)),
        "n_sampled": int(len(table)),
        "n_complete": int(complete.sum()) if len(complete) else 0,
        "target_year": int(config["target_year"]),
        "scene_counts": scene_counts,
        "evaluation_eligible": False,
        "binary_classifier_trained": False,
        "warning": "Positive features alone cannot estimate a sugarcane/non-sugarcane decision boundary.",
    }
    core.write_json(card_path, card)
    qa = {
        "schema_version": core.SCHEMA_VERSION,
        "created_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "status": "POSITIVE_FEATURE_LIBRARY_READY",
        "artifact_semantics": "positive_reference_only",
        "binary_classifier_trained": False,
        "transferable_validated_model": False,
        "input_reference_sha256": sha256_file(reference_path),
        "config_sha256": sha256_file(config_path),
        "feature_table_sha256": sha256_file(output_path),
        "n_reference_points": int(len(references)),
        "n_rows": int(len(table)),
        "n_complete": int(complete.sum()) if len(complete) else 0,
        "scene_counts": scene_counts,
        "next_requirement": "verified local non-sugarcane and sugarcane labels in the new project",
    }
    core.write_json(paths.result / "positive_feature_library_QA.json", qa)
    print(
        f"[OK] Positive temporal feature library: {qa['n_complete']}/{qa['n_rows']} complete; "
        "no binary classifier was trained"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
