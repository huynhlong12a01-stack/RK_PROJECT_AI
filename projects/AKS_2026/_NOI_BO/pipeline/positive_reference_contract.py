#!/usr/bin/env python3
"""Fail-closed contract and privacy checks for AKS positive references."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any, Iterable

import pandas as pd


PRIVACY_ASSERTION_KEYS = {"coordinates_included", "geometry_included"}
WKT_VALUE = re.compile(
    r"\b(?:POINT|MULTIPOINT|LINESTRING|MULTILINESTRING|POLYGON|MULTIPOLYGON|GEOMETRYCOLLECTION)\s*\(",
    re.IGNORECASE,
)


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def canonical_json_sha256(value: Any) -> str:
    encoded = json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def normalized_text_sha256(path: Path) -> str:
    text = path.read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n")
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def expected_predictor_bands(contract: dict[str, Any]) -> list[str]:
    required = contract["required_feature_contract"]
    periods = required["temporal"]["periods"]
    per_period = required["band_layout"]["per_period_prefixes"]
    ancillary = required["band_layout"]["ancillary_bands"]
    bands = [f"{prefix}_{period['id']}" for period in periods for prefix in per_period]
    bands.extend(ancillary)
    expected_count = int(required["predictor_band_count"])
    if len(bands) != expected_count or len(set(bands)) != len(bands):
        raise ValueError(
            f"Invalid predictor layout in contract: {len(bands)} bands, expected {expected_count}"
        )
    return bands


def _same_number(left: Any, right: Any, tolerance: float = 1e-12) -> bool:
    try:
        return abs(float(left) - float(right)) <= tolerance
    except (TypeError, ValueError):
        return False


def _require_equal(actual: Any, expected: Any, label: str) -> None:
    if actual != expected:
        raise ValueError(f"Feature contract mismatch for {label}: {actual!r} != {expected!r}")


def _require_number(actual: Any, expected: Any, label: str) -> None:
    if not _same_number(actual, expected):
        raise ValueError(f"Feature contract mismatch for {label}: {actual!r} != {expected!r}")


def find_mock_or_synthetic(value: Any, path: str = "root") -> list[str]:
    """Return provenance paths that identify mock/synthetic/non-operational data."""
    findings: list[str] = []
    if isinstance(value, dict):
        for key, child in value.items():
            child_path = f"{path}.{key}"
            normalized = str(key).strip().lower()
            if any(marker in normalized for marker in ("mock", "synthetic")):
                if child not in (False, None, "", 0, "false", "FALSE"):
                    findings.append(child_path)
            if normalized == "non_operational" and child is True:
                findings.append(child_path)
            findings.extend(find_mock_or_synthetic(child, child_path))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            findings.extend(find_mock_or_synthetic(child, f"{path}[{index}]"))
    elif isinstance(value, str):
        lowered = value.lower()
        if re.search(r"\b(?:mock|synthetic|gia\s*lap|giả\s*lập)\b", lowered):
            findings.append(path)
    return sorted(set(findings))


def reject_mock_or_synthetic(label: str, *values: Any) -> None:
    findings: list[str] = []
    for index, value in enumerate(values):
        findings.extend(find_mock_or_synthetic(value, f"{label}[{index}]"))
    if findings:
        preview = ", ".join(sorted(set(findings))[:8])
        raise ValueError(f"Mock/synthetic provenance is prohibited ({preview})")


def validate_feature_schema(
    contract: dict[str, Any], schema: dict[str, Any], temporal_engine_path: Path
) -> dict[str, Any]:
    """Validate the complete schema, period, formula-source and unit contract."""
    required = contract["required_feature_contract"]
    _require_equal(schema.get("schema_version"), contract["required_schema_version"], "schema_version")
    _require_equal(schema.get("method_id"), contract["required_method_id"], "method_id")

    expected_semantic_hash = required["feature_schema_semantic_sha256"]
    actual_semantic_hash = canonical_json_sha256(schema)
    _require_equal(actual_semantic_hash, expected_semantic_hash, "feature_schema_semantic_sha256")

    temporal = schema.get("temporal", {})
    expected_temporal = required["temporal"]
    for key in (
        "period_definition",
        "feature_end_date_exclusive",
        "n_periods",
        "periods",
        "relative_band_suffixes",
        "future_or_partial_periods_included",
    ):
        _require_equal(temporal.get(key), expected_temporal.get(key), f"temporal.{key}")

    s2 = schema.get("sentinel_2", {})
    required_s2 = required["sentinel_2"]
    for key in ("collection", "quality_collection", "cloud_score_band", "period_features"):
        _require_equal(s2.get(key), required_s2.get(key), f"sentinel_2.{key}")
    for key in ("surface_reflectance_scale_factor", "cloud_score_threshold"):
        _require_number(s2.get(key), required_s2.get(key), f"sentinel_2.{key}")

    s1 = schema.get("sentinel_1", {})
    required_s1 = required["sentinel_1"]
    for key in ("collection", "input_unit", "additional_log_transform", "filters", "period_features"):
        _require_equal(s1.get(key), required_s1.get(key), f"sentinel_1.{key}")

    ancillary = schema.get("ancillary", {})
    _require_equal(ancillary, required["ancillary"]["schema"], "ancillary")
    _require_equal(schema.get("missing_data_policy"), required["missing_data_policy"], "missing_data_policy")
    _require_number(schema.get("computational_grid_m"), required["computational_grid_m"], "computational_grid_m")

    actual_engine_hash = normalized_text_sha256(temporal_engine_path)
    _require_equal(
        actual_engine_hash,
        required["temporal_engine_normalized_sha256"],
        "temporal_engine_normalized_sha256",
    )
    bands = expected_predictor_bands(contract)
    return {
        "feature_schema_semantic_sha256": actual_semantic_hash,
        "temporal_engine_normalized_sha256": actual_engine_hash,
        "predictor_band_count": len(bands),
        "predictor_bands": bands,
    }


def runtime_overrides(contract: dict[str, Any]) -> dict[str, Any]:
    required = contract["required_feature_contract"]
    return {
        "feature_end_date_exclusive": required["temporal"]["feature_end_date_exclusive"],
        "temporal_quarters": required["temporal"]["n_periods"],
        "cloud_score_threshold": required["sentinel_2"]["cloud_score_threshold"],
        "cloudy_scene_percentage": required["sentinel_2"]["cloudy_scene_percentage_lt"],
        "resolution_m": required["computational_grid_m"],
    }


def build_extraction_snapshot(
    contract: dict[str, Any],
    schema: dict[str, Any],
    temporal_engine_path: Path,
    bands: list[str],
    runtime: dict[str, Any],
    scene_counts: dict[str, Any],
) -> dict[str, Any]:
    gate = validate_feature_schema(contract, schema, temporal_engine_path)
    _require_equal(bands, gate["predictor_bands"], "runtime predictor band order")
    required_runtime = runtime_overrides(contract)
    for key, expected in required_runtime.items():
        if isinstance(expected, (float, int)) and not isinstance(expected, bool):
            _require_number(runtime.get(key), expected, f"runtime.{key}")
        else:
            _require_equal(runtime.get(key), expected, f"runtime.{key}")
    _require_equal(scene_counts.get("band_count"), len(bands), "scene_counts.band_count")
    _require_equal(
        scene_counts.get("periods"),
        contract["required_feature_contract"]["temporal"]["periods"],
        "scene_counts.periods",
    )
    _require_equal(scene_counts.get("empty_periods"), [], "scene_counts.empty_periods")
    _require_equal(scene_counts.get("sentinel_1_input_unit"), "dB", "scene_counts.sentinel_1_input_unit")
    _require_equal(
        scene_counts.get("sentinel_1_additional_log_transform"),
        False,
        "scene_counts.sentinel_1_additional_log_transform",
    )
    return {
        "status": "EXACT_FEATURE_CONTRACT_CAPTURED",
        "contract_version": contract["contract_version"],
        "feature_schema_semantic_sha256": gate["feature_schema_semantic_sha256"],
        "temporal_engine_normalized_sha256": gate["temporal_engine_normalized_sha256"],
        "predictor_band_count": len(bands),
        "predictor_bands": list(bands),
        "runtime": {key: runtime[key] for key in required_runtime},
        "feature_contract": contract["required_feature_contract"],
        "scene_counts": scene_counts,
    }


def validate_extraction_snapshot(
    contract: dict[str, Any],
    schema: dict[str, Any],
    temporal_engine_path: Path,
    snapshot: dict[str, Any],
) -> list[str]:
    gate = validate_feature_schema(contract, schema, temporal_engine_path)
    _require_equal(snapshot.get("status"), "EXACT_FEATURE_CONTRACT_CAPTURED", "snapshot.status")
    _require_equal(snapshot.get("contract_version"), contract["contract_version"], "snapshot.contract_version")
    _require_equal(snapshot.get("feature_schema_semantic_sha256"), gate["feature_schema_semantic_sha256"], "snapshot feature schema hash")
    _require_equal(snapshot.get("temporal_engine_normalized_sha256"), gate["temporal_engine_normalized_sha256"], "snapshot temporal engine hash")
    _require_equal(snapshot.get("predictor_band_count"), len(gate["predictor_bands"]), "snapshot predictor count")
    _require_equal(snapshot.get("predictor_bands"), gate["predictor_bands"], "snapshot predictor order")
    _require_equal(snapshot.get("runtime"), runtime_overrides(contract), "snapshot runtime")
    _require_equal(snapshot.get("feature_contract"), contract["required_feature_contract"], "snapshot feature contract")
    scene_counts = snapshot.get("scene_counts", {})
    _require_equal(scene_counts.get("band_count"), len(gate["predictor_bands"]), "snapshot scene band count")
    _require_equal(scene_counts.get("periods"), contract["required_feature_contract"]["temporal"]["periods"], "snapshot periods")
    _require_equal(scene_counts.get("empty_periods"), [], "snapshot empty periods")
    return gate["predictor_bands"]


def privacy_name_reason(name: str, policy: dict[str, Any]) -> str | None:
    lowered = str(name).strip().lower()
    exact = {str(value).strip().lower() for value in policy.get("forbidden_columns_case_insensitive", [])}
    if lowered in exact:
        return "exact coordinate/geometry name"
    for marker in policy.get("forbidden_name_substrings_case_insensitive", []):
        if str(marker).lower() in lowered:
            return f"forbidden substring {marker!r}"
    tokens = {token for token in re.split(r"[^a-z0-9]+", lowered) if token}
    forbidden_tokens = {
        str(value).strip().lower() for value in policy.get("forbidden_name_tokens_case_insensitive", [])
    }
    matched = sorted(tokens.intersection(forbidden_tokens))
    if matched:
        return f"forbidden token {matched[0]!r}"
    return None


def privacy_findings(value: Any, policy: dict[str, Any], path: str = "root") -> list[str]:
    findings: list[str] = []
    if isinstance(value, dict):
        for key, child in value.items():
            key_text = str(key)
            child_path = f"{path}.{key_text}"
            reason = privacy_name_reason(key_text, policy)
            if reason:
                if key_text in PRIVACY_ASSERTION_KEYS and child is False:
                    pass
                else:
                    findings.append(f"{child_path}: {reason}")
            findings.extend(privacy_findings(child, policy, child_path))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            findings.extend(privacy_findings(child, policy, f"{path}[{index}]"))
    elif isinstance(value, str) and WKT_VALUE.search(value):
        findings.append(f"{path}: WKT geometry value")
    return findings


def audit_table_privacy(table: pd.DataFrame, policy: dict[str, Any], label: str) -> None:
    findings = []
    for column in table.columns:
        reason = privacy_name_reason(str(column), policy)
        if reason:
            findings.append(f"{label}.{column}: {reason}")
    object_columns = table.select_dtypes(include=["object", "string"]).columns
    for column in object_columns:
        for row_index, value in table[column].items():
            if isinstance(value, str) and WKT_VALUE.search(value):
                findings.append(f"{label}.{column}[{row_index}]: WKT geometry value")
                if len(findings) >= 20:
                    break
    if findings:
        raise ValueError("Privacy audit failed: " + "; ".join(findings[:20]))


def assert_output_has_no_unexpected_entries(output: Path, expected_files: Iterable[str]) -> None:
    if not output.exists():
        return
    if not output.is_dir():
        raise ValueError(f"Knowledge output exists but is not a directory: {output}")
    expected = set(expected_files)
    unexpected = []
    for entry in output.rglob("*"):
        if entry.is_dir() or entry.relative_to(output).as_posix() not in expected:
            unexpected.append(entry.relative_to(output).as_posix())
    if unexpected:
        raise ValueError(
            "Knowledge output contains unexpected old entries; inspect/remove them before retrying: "
            + ", ".join(sorted(unexpected)[:20])
        )


def audit_output_directory(output: Path, expected_files: Iterable[str], policy: dict[str, Any]) -> None:
    expected = set(expected_files)
    actual = {
        entry.relative_to(output).as_posix()
        for entry in output.rglob("*")
        if entry.is_file()
    }
    if actual != expected:
        missing = sorted(expected - actual)
        extra = sorted(actual - expected)
        raise RuntimeError(f"Knowledge output inventory mismatch; missing={missing}; extra={extra}")
    findings: list[str] = []
    for relative in sorted(expected):
        path = output / relative
        if path.suffix.lower() == ".json":
            findings.extend(privacy_findings(read_json(path), policy, relative))
        elif path.suffix.lower() == ".csv":
            try:
                audit_table_privacy(pd.read_csv(path), policy, relative)
            except ValueError as error:
                findings.append(str(error))
    if findings:
        raise RuntimeError("Recursive post-write privacy audit failed: " + "; ".join(findings[:20]))
