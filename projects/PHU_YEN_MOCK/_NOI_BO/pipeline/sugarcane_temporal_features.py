#!/usr/bin/env python3
"""Leakage-safe rolling temporal features for sugarcane interpretation.

Band names use relative periods (T01..Tnn) while provenance stores the exact
absolute dates.  Only completed quarters are accepted, so a future/partial
quarter cannot silently become a fully masked band and remove every sample.
"""

from __future__ import annotations

import calendar
from datetime import date, datetime
from typing import Any


S2_COLLECTION = "COPERNICUS/S2_SR_HARMONIZED"
S2_QA_COLLECTION = "GOOGLE/CLOUD_SCORE_PLUS/V1/S2_HARMONIZED"
S1_COLLECTION = "COPERNICUS/S1_GRD"
WORLD_COVER = "ESA/WorldCover/v200"


def parse_iso_date(value: Any) -> date:
    if isinstance(value, date):
        return value
    try:
        return date.fromisoformat(str(value))
    except ValueError as exc:
        raise ValueError(f"Invalid ISO date: {value!r}; expected YYYY-MM-DD") from exc


def quarter_start(value: date) -> date:
    month = ((value.month - 1) // 3) * 3 + 1
    return date(value.year, month, 1)


def shift_months(value: date, months: int) -> date:
    index = value.year * 12 + value.month - 1 + months
    year, month0 = divmod(index, 12)
    month = month0 + 1
    day = min(value.day, calendar.monthrange(year, month)[1])
    return date(year, month, day)


def rolling_periods(config: dict[str, Any], today: date | None = None) -> tuple[list[dict[str, str]], dict[str, Any]]:
    today = today or date.today()
    latest_complete_end = quarter_start(today)
    explicit = str(config.get("feature_end_date_exclusive", "")).strip()
    end_exclusive = parse_iso_date(explicit) if explicit else latest_complete_end
    if end_exclusive != quarter_start(end_exclusive):
        raise ValueError("feature_end_date_exclusive must be the first day of a calendar quarter")
    if end_exclusive > latest_complete_end:
        raise ValueError(
            f"feature_end_date_exclusive={end_exclusive} includes a future/incomplete quarter; "
            f"latest allowed is {latest_complete_end}"
        )
    n_periods = int(config.get("temporal_quarters", int(config.get("history_years", 2)) * 4))
    if n_periods < 4:
        raise ValueError("temporal_quarters must be at least 4")
    start = shift_months(end_exclusive, -3 * n_periods)
    periods = []
    for index in range(n_periods):
        period_start = shift_months(start, 3 * index)
        period_end = shift_months(period_start, 3)
        periods.append(
            {
                "id": f"T{index + 1:02d}",
                "start": period_start.isoformat(),
                "end_exclusive": period_end.isoformat(),
            }
        )
    provenance = {
        "period_definition": "rolling_complete_calendar_quarters",
        "feature_end_date_exclusive": end_exclusive.isoformat(),
        "latest_complete_end_at_run": latest_complete_end.isoformat(),
        "n_periods": n_periods,
        "periods": periods,
        "relative_band_suffixes": True,
        "future_or_partial_periods_included": False,
    }
    return periods, provenance


def phenology_gate(config: dict[str, Any]) -> dict[str, Any]:
    confirmed = bool(config.get("phenology_alignment_confirmed", False))
    source = str(config.get("crop_calendar_source", "")).strip()
    note = str(config.get("crop_calendar_note", "")).strip()
    return {
        "confirmed": confirmed,
        "crop_calendar_source": source,
        "crop_calendar_note": note,
        "pass": confirmed and bool(source),
        "reason": (
            "confirmed local crop calendar/phenology alignment"
            if confirmed and source
            else "confirm local crop calendar and document crop_calendar_source before supervised inference"
        ),
    }


def build_temporal_stack(config: dict[str, Any], roi_geometry: Any) -> tuple[Any, list[str], dict[str, Any]]:
    import ee

    periods, temporal = rolling_periods(config)
    overall_start = ee.Date(periods[0]["start"])
    overall_end = ee.Date(periods[-1]["end_exclusive"])
    s2 = (
        ee.ImageCollection(S2_COLLECTION)
        .filterBounds(roi_geometry)
        .filterDate(overall_start, overall_end)
        .filter(ee.Filter.lt("CLOUDY_PIXEL_PERCENTAGE", float(config.get("cloudy_scene_percentage", 80))))
    )
    cloud_score = (
        ee.ImageCollection(S2_QA_COLLECTION)
        .filterBounds(roi_geometry)
        .filterDate(overall_start, overall_end)
    )

    def prep_s2(image: Any) -> Any:
        image = ee.Image(image)
        clear = image.select("cs_cdf").gte(float(config.get("cloud_score_threshold", 0.60)))
        sr = image.select(["B2", "B3", "B4", "B5", "B8", "B11", "B12"]).multiply(0.0001)
        ndvi = sr.normalizedDifference(["B8", "B4"]).rename("NDVI")
        evi = sr.expression(
            "2.5*(nir-red)/(nir+6*red-7.5*blue+1)",
            {"nir": sr.select("B8"), "red": sr.select("B4"), "blue": sr.select("B2")},
        ).rename("EVI")
        ndmi = sr.normalizedDifference(["B8", "B11"]).rename("NDMI")
        ndre = sr.normalizedDifference(["B8", "B5"]).rename("NDRE")
        nbr2 = sr.normalizedDifference(["B11", "B12"]).rename("NBR2")
        return ee.Image.cat([ndvi, evi, ndmi, ndre, nbr2]).updateMask(clear).copyProperties(
            image, ["system:time_start"]
        )

    s2_ready = s2.linkCollection(cloud_score, ["cs_cdf"]).map(prep_s2)
    s1 = (
        ee.ImageCollection(S1_COLLECTION)
        .filterBounds(roi_geometry)
        .filterDate(overall_start, overall_end)
        .filter(ee.Filter.eq("instrumentMode", "IW"))
        .filter(ee.Filter.listContains("transmitterReceiverPolarisation", "VV"))
        .filter(ee.Filter.listContains("transmitterReceiverPolarisation", "VH"))
        .select(["VV", "VH"])
    )

    def prep_s1(image: Any) -> Any:
        # Values are already calibrated/terrain-corrected dB in COPERNICUS/S1_GRD.
        vv = image.select("VV")
        vh = image.select("VH")
        return ee.Image.cat([vv.rename("VV"), vh.rename("VH"), vv.subtract(vh).rename("VVminusVH")]).copyProperties(
            image, ["system:time_start"]
        )

    s1_ready = s1.map(prep_s1)
    images = []
    bands: list[str] = []
    period_counts = []
    for period in periods:
        start = ee.Date(period["start"])
        end = ee.Date(period["end_exclusive"])
        suffix = period["id"]
        s2_period = s2_ready.filterDate(start, end)
        s1_period = s1_ready.filterDate(start, end)
        s2_names = [f"{name}_{suffix}" for name in ("NDVI", "EVI", "NDMI", "NDRE", "NBR2")]
        s1_names = [f"{name}_{suffix}" for name in ("VV", "VH", "VVminusVH")]
        images.extend(
            [
                s2_period.select(["NDVI", "EVI", "NDMI", "NDRE", "NBR2"]).median().rename(s2_names),
                s2_period.select("NDVI").count().rename(f"S2_count_{suffix}"),
                s1_period.select(["VV", "VH", "VVminusVH"]).median().rename(s1_names),
            ]
        )
        bands.extend(s2_names + [f"S2_count_{suffix}"] + s1_names)
        period_counts.append(
            {
                **period,
                "s2_scene_count": int(s2_period.size().getInfo()),
                "s1_scene_count": int(s1_period.size().getInfo()),
            }
        )

    empty_periods = [
        row["id"] for row in period_counts if row["s2_scene_count"] == 0 or row["s1_scene_count"] == 0
    ]
    if empty_periods:
        raise ValueError(
            "No silent masked periods are allowed; missing Sentinel-1 or Sentinel-2 scenes in "
            + ", ".join(empty_periods)
        )
    dem = ee.Image("USGS/SRTMGL1_003").select("elevation").rename("elevation_m")
    slope = ee.Terrain.slope(dem).rename("slope_deg")
    worldcover = ee.ImageCollection(WORLD_COVER).first().select("Map").rename("worldcover_class")
    images.extend([dem, slope, worldcover])
    bands.extend(["elevation_m", "slope_deg", "worldcover_class"])
    stack = ee.Image.cat(images).select(bands).clip(roi_geometry)
    metadata = {
        **temporal,
        "period_scene_counts": period_counts,
        "empty_periods": [],
        "band_count": len(bands),
        "sentinel_1_input_unit": "dB",
        "sentinel_1_additional_log_transform": False,
        "predictor_missing_values_unmasked_to_zero": False,
        "worldcover_role": "predictor_only_not_hard_mask",
        "phenology_alignment": phenology_gate(config),
    }
    return stack, bands, metadata


if __name__ == "__main__":
    example, provenance = rolling_periods(
        {"feature_end_date_exclusive": "2026-07-01", "temporal_quarters": 8},
        today=date(2026, 7, 14),
    )
    assert example[0]["id"] == "T01" and example[-1]["id"] == "T08"
    assert provenance["future_or_partial_periods_included"] is False
    print("[OK] rolling temporal period smoke test passed")
