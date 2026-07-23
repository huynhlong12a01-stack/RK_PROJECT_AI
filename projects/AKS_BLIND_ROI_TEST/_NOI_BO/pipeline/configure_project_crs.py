#!/usr/bin/env python3
"""Derive a metric projected CRS from the project ROI and synchronize configs."""

from __future__ import annotations

import argparse
import json
import math
import os
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import geopandas as gpd
from pyproj import CRS


def read_flat_value(path: Path, key: str, default: str = "") -> str:
    if not path.exists():
        return default
    match = re.search(
        rf"(?m)^[ \t]*{re.escape(key)}[ \t]*:[ \t]*([^#\r\n]+)",
        path.read_text(encoding="utf-8"),
    )
    return match.group(1).strip().strip('"').strip("'") if match else default


def atomic_update(path: Path, values: dict[str, Any]) -> dict[str, str]:
    if not path.exists():
        return {}
    text = path.read_text(encoding="utf-8")
    previous: dict[str, str] = {}
    for key, value in values.items():
        pattern = re.compile(rf"(?m)^([ \t]*{re.escape(key)}[ \t]*:[ \t]*).*$")
        match = pattern.search(text)
        if match:
            previous[key] = match.group(0).split(":", 1)[1].strip()
            text = pattern.sub(lambda item: f"{item.group(1)}{value}", text, count=1)
        else:
            previous[key] = "<missing>"
            text = text.rstrip() + f"\n{key}: {value}\n"
    temporary = path.with_name(path.name + ".crs.tmp")
    temporary.write_text(text, encoding="utf-8", newline="\n")
    os.replace(temporary, path)
    return previous


def locate_roi(project: Path) -> Path | None:
    source = project / "00_XAC_LAP_VUNG_MIA" / "01_DAU_VAO"
    candidates = (
        source / "roi_field_area.geojson",
        source / "roi_search.geojson",
        source / "roi_search.gpkg",
        source / "roi_search.shp",
    )
    return next((path for path in candidates if path.is_file()), None)


def derive_utm_epsg(roi_path: Path) -> tuple[int, dict[str, float]]:
    frame = gpd.read_file(roi_path)
    if frame.empty or frame.crs is None:
        raise ValueError(f"ROI is empty or has no CRS: {roi_path}")
    frame = frame[frame.geometry.notna() & ~frame.geometry.is_empty]
    if frame.empty:
        raise ValueError(f"ROI has no valid geometry: {roi_path}")
    west, south, east, north = (float(value) for value in frame.to_crs(4326).total_bounds)
    if not all(math.isfinite(value) for value in (west, south, east, north)):
        raise ValueError("ROI bounds are not finite.")
    if west < -180 or east > 180 or south < -90 or north > 90 or west >= east or south >= north:
        raise ValueError(f"Invalid WGS84 ROI bounds: {(west, south, east, north)}")
    if east - west > 6.0:
        raise ValueError(
            "ROI spans more than 6 degrees longitude; one automatic UTM zone is unsafe. "
            "Set crs_mode: manual and a reviewed metric projected crs_epsg in THONG_SO_DU_AN.yml."
        )
    longitude = (west + east) / 2.0
    latitude = (south + north) / 2.0
    zone = max(1, min(60, int(math.floor((longitude + 180.0) / 6.0)) + 1))
    epsg = (32600 if latitude >= 0 else 32700) + zone
    return epsg, {
        "west": west,
        "south": south,
        "east": east,
        "north": north,
        "center_longitude": longitude,
        "center_latitude": latitude,
        "utm_zone": zone,
    }


def validate_metric_projected_crs(epsg: int) -> dict[str, Any]:
    try:
        crs = CRS.from_epsg(epsg)
    except Exception as exc:
        raise ValueError(f"crs_epsg is not a valid EPSG code: {epsg}") from exc
    if not crs.is_projected:
        raise ValueError(
            f"EPSG:{epsg} is not projected. Distance, buffer and area calculations require a projected CRS in metres."
        )
    axes = list(crs.axis_info)
    if not axes or any(
        axis.unit_conversion_factor is None
        or not math.isclose(float(axis.unit_conversion_factor), 1.0, rel_tol=0.0, abs_tol=1e-12)
        for axis in axes[:2]
    ):
        units = sorted({str(axis.unit_name or "unknown") for axis in axes})
        raise ValueError(
            f"EPSG:{epsg} does not use metre linear units on its horizontal axes: {units}."
        )
    return {
        "name": crs.name,
        "is_projected": True,
        "horizontal_unit": str(axes[0].unit_name),
        "unit_conversion_factor": float(axes[0].unit_conversion_factor),
    }


def parse_positive_epsg(raw: str, source: str) -> int:
    try:
        epsg = int(raw)
    except ValueError as exc:
        raise ValueError(f"{source} requires an integer crs_epsg.") from exc
    if epsg <= 0:
        raise ValueError(f"{source} requires a positive crs_epsg.")
    return epsg


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-dir", required=True)
    args = parser.parse_args()
    project = Path(args.project_dir).resolve()
    if not project.is_dir():
        raise FileNotFoundError(f"Project directory not found: {project}")

    project_settings = project / "THONG_SO_DU_AN.yml"
    sampling = project / "01_THIET_KE_LAY_MAU" / "01_DAU_VAO" / "sampling.yml"
    interpretation = project / "00_XAC_LAP_VUNG_MIA" / "01_DAU_VAO" / "interpretation.yml"
    internal = project / "_NOI_BO" / "config" / "project.yml"

    sampling_mode = read_flat_value(sampling, "crs_mode", "auto").lower()
    interpretation_mode = read_flat_value(interpretation, "crs_mode", "auto").lower()
    for name, value in (("sampling.yml", sampling_mode), ("interpretation.yml", interpretation_mode)):
        if value not in {"auto", "manual"}:
            raise ValueError(f"crs_mode in {name} must be auto or manual.")

    if project_settings.exists():
        mode = read_flat_value(project_settings, "crs_mode", "auto").lower()
        if mode not in {"auto", "manual"}:
            raise ValueError("crs_mode in THONG_SO_DU_AN.yml must be auto or manual.")
        if "manual" in {sampling_mode, interpretation_mode} and mode != "manual":
            raise ValueError(
                "A stage file requests manual CRS while THONG_SO_DU_AN.yml is auto. "
                "Edit only THONG_SO_DU_AN.yml so the project has one source of truth."
            )
        if mode == "manual":
            configured_epsg = parse_positive_epsg(
                read_flat_value(project_settings, "crs_epsg", ""),
                "Manual CRS mode in THONG_SO_DU_AN.yml",
            )
            for path, stage_mode in ((sampling, sampling_mode), (interpretation, interpretation_mode)):
                if stage_mode == "manual":
                    stage_epsg = parse_positive_epsg(
                        read_flat_value(path, "crs_epsg", ""),
                        f"Manual CRS mode in {path.name}",
                    )
                    if stage_epsg != configured_epsg:
                        raise ValueError(
                            f"Conflicting manual CRS: THONG_SO_DU_AN.yml uses EPSG:{configured_epsg}, "
                            f"but {path.name} uses EPSG:{stage_epsg}."
                        )
        else:
            configured_epsg = None
    else:
        manual_files = [
            path
            for path, stage_mode in ((sampling, sampling_mode), (interpretation, interpretation_mode))
            if stage_mode == "manual"
        ]
        manual_epsgs = {
            parse_positive_epsg(read_flat_value(path, "crs_epsg", ""), f"Manual CRS mode in {path.name}")
            for path in manual_files
        }
        if len(manual_epsgs) > 1:
            raise ValueError("sampling.yml and interpretation.yml specify conflicting manual CRS values.")
        mode = "manual" if manual_files else "auto"
        configured_epsg = next(iter(manual_epsgs)) if manual_epsgs else None

    roi_path = locate_roi(project)
    if mode == "manual":
        if configured_epsg is None:
            configured_epsg = parse_positive_epsg(
                read_flat_value(internal, "crs_epsg", ""),
                "Manual CRS mode",
            )
        epsg = configured_epsg
        bounds: dict[str, float] | None = None
        source = "manual_reviewed_configuration"
    else:
        if roi_path is None:
            print("[CRS] Waiting for roi_field_area or roi_search; automatic CRS has not run.")
            return 0
        epsg, bounds = derive_utm_epsg(roi_path)
        source = "automatic_utm_from_roi_bounds_center"

    crs_metadata = validate_metric_projected_crs(epsg)
    changes = {
        str(path.relative_to(project)).replace("\\", "/"): atomic_update(
            path, {"crs_mode": mode, "crs_epsg": epsg}
        )
        for path in (project_settings, sampling, interpretation, internal)
        if path.exists()
    }
    qa_path = project / "_NOI_BO" / "work" / "field_area" / "qa" / "crs_configuration.json"
    qa_path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "schema_version": "1.1",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "project_id": project.name,
        "crs_mode": mode,
        "crs_epsg": epsg,
        "crs": crs_metadata,
        "selection_source": source,
        "roi_path": str(roi_path.relative_to(project)).replace("\\", "/") if roi_path else None,
        "roi_bounds_wgs84": bounds,
        "files_synchronized": changes,
        "warning": "Projected CRS controls metric distance/area calculations; source raster resolution is unchanged.",
    }
    temporary = qa_path.with_name(qa_path.name + ".tmp")
    temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, qa_path)
    print(f"[CRS] {mode}: EPSG:{epsg} ({source}; {crs_metadata['name']})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
