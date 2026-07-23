#!/usr/bin/env python3
"""Prepare leakage-audited 1,000-point inputs for AKS_BLIND_ROI_TEST.

The script reads only the approved positive_reference point package and its
atomic transfer receipt.  It never reads sample_actual, the source model card,
or the known AKS roi_field_area geometry.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import tempfile
from datetime import datetime, timezone
from pathlib import Path

import geopandas as gpd
import pandas as pd


EXPECTED_POINTS = 1000
EXPECTED_RECEIPT_STATUS = "PASS_ATOMIC_BEFORE_EXTERNAL_TRANSFER"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def atomic_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    handle, raw = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
    os.close(handle)
    temporary = Path(raw)
    try:
        temporary.write_text(
            json.dumps(value, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def atomic_csv(path: Path, frame: pd.DataFrame) -> None:
    handle, raw = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
    os.close(handle)
    temporary = Path(raw)
    try:
        frame.to_csv(temporary, index=False, encoding="utf-8", lineterminator="\n")
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def atomic_geojson(path: Path, frame: gpd.GeoDataFrame) -> None:
    temporary = path.with_name(path.stem + ".building.geojson")
    temporary.unlink(missing_ok=True)
    try:
        frame.to_file(temporary, driver="GeoJSON")
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def validate_reference(reference_path: Path, receipt_path: Path) -> tuple[gpd.GeoDataFrame, dict]:
    if not reference_path.is_file() or not receipt_path.is_file():
        raise FileNotFoundError("Approved AKS 1,000-point reference package is incomplete")
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    if receipt.get("status") != EXPECTED_RECEIPT_STATUS:
        raise ValueError("AKS positive-reference receipt is not approved")
    if receipt.get("source_project") != "AKS_2026":
        raise ValueError("Positive-reference receipt belongs to another source project")
    if int(receipt.get("actual_reference_points", -1)) != EXPECTED_POINTS:
        raise ValueError("Receipt does not certify exactly 1,000 reference points")
    if int(receipt.get("maximum_reference_points", -1)) != EXPECTED_POINTS:
        raise ValueError("Receipt maximum is not the approved 1,000-point boundary")
    actual_hash = sha256_file(reference_path)
    if actual_hash != str(receipt.get("positive_reference_sha256", "")).lower():
        raise ValueError("Positive-reference hash does not match the approved receipt")

    reference = gpd.read_file(reference_path)
    required = {
        "source_feature_index",
        "label",
        "label_name",
        "label_basis",
        "evaluation_eligible",
        "source_project",
        "geometry",
    }
    missing = required - set(reference.columns)
    if missing:
        raise ValueError(f"Positive-reference package is missing columns: {sorted(missing)}")
    if len(reference) != EXPECTED_POINTS:
        raise ValueError(f"Expected 1,000 points, found {len(reference)}")
    if reference.crs is None or reference.to_crs(4326).crs.to_epsg() != 4326:
        raise ValueError("Positive-reference CRS cannot be normalized to EPSG:4326")
    reference = reference.to_crs(4326)
    if (
        reference.geometry.isna().any()
        or reference.geometry.is_empty.any()
        or not reference.geom_type.eq("Point").all()
    ):
        raise ValueError("Every approved reference must be a non-empty point")
    if not reference.geometry.to_wkb().is_unique:
        raise ValueError("Approved reference points contain duplicate geometry")
    if not pd.to_numeric(reference["label"], errors="coerce").eq(1).all():
        raise ValueError("Approved reference contains a non-positive label")
    if not reference["label_name"].astype(str).str.strip().eq("sugarcane").all():
        raise ValueError("Approved reference contains an unexpected crop label")
    if not reference["source_project"].astype(str).eq("AKS_2026").all():
        raise ValueError("Approved reference contains another source project")
    return reference, receipt


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-dir", required=True)
    parser.add_argument("--buffer-m", type=float, default=5000.0)
    args = parser.parse_args()

    project = Path(args.project_dir).resolve()
    if project.name != "AKS_BLIND_ROI_TEST":
        raise ValueError("This preparer is restricted to AKS_BLIND_ROI_TEST")
    root = project.parents[1]
    package = (
        root
        / "projects"
        / "AKS_2026"
        / "_NOI_BO"
        / "work"
        / "field_area"
        / "reference_package"
    )
    reference_path = package / "positive_reference.geojson"
    receipt_path = package / "external_transfer_consent_receipt.json"
    input_dir = project / "00_XAC_LAP_VUNG_MIA" / "01_DAU_VAO"
    result_dir = project / "00_XAC_LAP_VUNG_MIA" / "02_KET_QUA"
    input_dir.mkdir(parents=True, exist_ok=True)
    result_dir.mkdir(parents=True, exist_ok=True)

    forbidden = sorted(input_dir.glob("roi_field_area.*"))
    if forbidden:
        raise RuntimeError(
            "Blind inference refuses a known roi_field_area in its input: "
            + ", ".join(item.name for item in forbidden)
        )

    reference, receipt = validate_reference(reference_path, receipt_path)
    projected = reference.to_crs(32649)
    search_geometry = projected.geometry.union_all().convex_hull.buffer(
        float(args.buffer_m),
        quad_segs=30,
    )
    if search_geometry.is_empty or not search_geometry.is_valid:
        raise ValueError("Cannot create a valid ROI_search from the approved 1,000 points")
    search = gpd.GeoDataFrame(
        {
            "search_id": ["AKS_1000_POINT_HULL_BUFFER"],
            "source_point_count": [EXPECTED_POINTS],
            "buffer_m": [float(args.buffer_m)],
        },
        geometry=[search_geometry],
        crs=32649,
    ).to_crs(4326)

    labels = pd.DataFrame(
        {
            "code": [f"AKS_BLIND_REF_{index + 1:04d}" for index in range(EXPECTED_POINTS)],
            "lat": reference.geometry.y.to_numpy(),
            "lon": reference.geometry.x.to_numpy(),
            "label": 1,
            "group_id": "",
            "label_source": "AKS_2026_approved_positive_reference_point",
            "observation_date": "",
            "reviewer": "approved_reference_package",
            "note": (
                "Positive evidence only; no non-sugarcane label or independent validation implied."
            ),
        }
    )

    roi_path = input_dir / "roi_search.geojson"
    labels_path = input_dir / "sugarcane_labels.csv"
    atomic_geojson(roi_path, search)
    atomic_csv(labels_path, labels)
    manifest = {
        "schema_version": "aks-blind-inference-input-v2",
        "created_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "project_id": project.name,
        "source_reference_package": str(package.resolve()),
        "source_reference_sha256": sha256_file(reference_path),
        "source_receipt_sha256": sha256_file(receipt_path),
        "source_receipt_status": receipt["status"],
        "n_positive_points": EXPECTED_POINTS,
        "verified_negative_points": 0,
        "roi_search_method": "approved_positive_point_convex_hull_plus_projected_buffer",
        "roi_search_buffer_m": float(args.buffer_m),
        "roi_search_area_ha": float(search.to_crs(32649).geometry.area.sum() / 10000.0),
        "roi_search_sha256": sha256_file(roi_path),
        "labels_sha256": sha256_file(labels_path),
        "sample_actual_read_by_preparer": False,
        "source_model_card_read_by_preparer": False,
        "known_roi_field_area_read_by_preparer": False,
        "known_roi_field_area_present_in_inference_input": False,
        "search_extent_independent_of_source_roi": False,
        "warning": (
            "The 1,000 positive points were originally selected from the known AKS field-area source. "
            "This is a blind polygon-reconstruction test, not independent accuracy assessment."
        ),
    }
    atomic_json(result_dir / "blind_inference_input_manifest.json", manifest)
    print(
        f"[OK] Blind inputs: {EXPECTED_POINTS} approved positive points; "
        f"ROI_search={manifest['roi_search_area_ha']:.1f} ha; known ROI not read"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
