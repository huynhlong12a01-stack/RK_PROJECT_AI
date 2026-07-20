#!/usr/bin/env python3
"""Permanent guard: synthetic PHU_YEN_MOCK data may never become references."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-dir", required=True)
    args = parser.parse_args()
    project = Path(args.project_dir).resolve()
    contract_path = project / "MOCK_CONTRACT.json"
    if not contract_path.is_file():
        print("[BLOCKED] Missing PHU_YEN_MOCK safety contract.", file=sys.stderr)
        return 2
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    if contract.get("project_id") != "PHU_YEN_MOCK":
        print("[BLOCKED] This extractor is disabled inside the mock project.", file=sys.stderr)
        return 2
    print(
        "[BLOCKED] PHU_YEN_MOCK is synthetic; reference extraction, external transfer "
        "and knowledge-library ingestion are prohibited.",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
