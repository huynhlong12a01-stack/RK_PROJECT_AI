#!/usr/bin/env python3
"""Post-hoc geometric comparison for AKS blind reconstruction.

The withheld field-area polygon is opened only after a candidate exists.  The
reported overlaps are diagnostics, not independent classification accuracy.
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


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def atomic_json(path: Path, value: dict) -> None:
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


def union_projected(path: Path, epsg: int):
    frame = gpd.read_file(path)
    if frame.empty or frame.crs is None:
        raise ValueError(f"Empty or CRS-less geometry: {path}")
    projected = frame.to_crs(epsg=epsg)
    projected.geometry = projected.geometry.make_valid()
    return projected.geometry.union_all()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-dir", required=True)
    parser.add_argument("--withheld-roi", required=True)
    parser.add_argument("--crs-epsg", type=int, default=32649)
    args = parser.parse_args()

    project = Path(args.project_dir).resolve()
    input_dir = project / "00_XAC_LAP_VUNG_MIA" / "01_DAU_VAO"
    result_dir = project / "00_XAC_LAP_VUNG_MIA" / "02_KET_QUA"
    forbidden = sorted(input_dir.glob("roi_field_area.*"))
    if forbidden:
        raise RuntimeError("Withheld comparison refuses ROI geometry in inference input")
    candidate_path = result_dir / "roi_field_area_candidate.geojson"
    search_path = input_dir / "roi_search.geojson"
    qa_path = result_dir / "field_area_QA.json"
    manifest_path = result_dir / "blind_inference_input_manifest.json"
    withheld_path = Path(args.withheld_roi).resolve()
    for path in (candidate_path, search_path, qa_path, manifest_path, withheld_path):
        if not path.is_file():
            raise FileNotFoundError(path)

    qa = json.loads(qa_path.read_text(encoding="utf-8"))
    if qa.get("status") != "POSITIVE_ONLY_CANDIDATE_REQUIRES_MANUAL_REVIEW":
        raise RuntimeError("Inference did not finish with a positive-only candidate")
    if (
        qa.get("scientific_guards", {})
        .get("known_roi_field_area_used_for_inference", True)
        is not False
    ):
        raise RuntimeError("Inference QA does not prove the known ROI was excluded")

    search = union_projected(search_path, args.crs_epsg)
    candidate = union_projected(candidate_path, args.crs_epsg).intersection(search)
    reference = union_projected(withheld_path, args.crs_epsg).intersection(search)
    overlap = candidate.intersection(reference)
    union = candidate.union(reference)

    candidate_area = float(candidate.area)
    reference_area = float(reference.area)
    overlap_area = float(overlap.area)
    union_area = float(union.area)
    comparison = {
        "schema_version": "aks-blind-posthoc-comparison-v1",
        "created_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "project_id": project.name,
        "inference_completed_before_withheld_roi_opened": True,
        "withheld_roi_role": "post_hoc_geometric_reference_only",
        "withheld_roi_sha256": sha256_file(withheld_path),
        "candidate_sha256": sha256_file(candidate_path),
        "search_sha256": sha256_file(search_path),
        "areas_ha_within_roi_search": {
            "candidate": candidate_area / 10000.0,
            "withheld_reference": reference_area / 10000.0,
            "intersection": overlap_area / 10000.0,
        },
        "geometric_overlap": {
            "reference_coverage_fraction": overlap_area / reference_area if reference_area else 0.0,
            "candidate_overlap_fraction": overlap_area / candidate_area if candidate_area else 0.0,
            "intersection_over_union": overlap_area / union_area if union_area else 0.0,
        },
        "scientific_interpretation": {
            "independent_validation": False,
            "classification_precision_or_recall_reported": False,
            "reason": (
                "The field points and withheld polygon belong to the same ROI-informed AKS campaign; "
                "overlap measures reconstruction only and cannot estimate map accuracy."
            ),
        },
    }
    output = result_dir / "blind_reconstruction_comparison.json"
    atomic_json(output, comparison)
    print(
        "[OK] Post-hoc overlap: "
        f"reference coverage={comparison['geometric_overlap']['reference_coverage_fraction']:.3f}; "
        f"candidate overlap={comparison['geometric_overlap']['candidate_overlap_fraction']:.3f}; "
        f"IoU={comparison['geometric_overlap']['intersection_over_union']:.3f}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
