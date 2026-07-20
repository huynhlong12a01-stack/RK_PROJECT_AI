#!/usr/bin/env python3
"""Fail-fast import check for the operational Python environment."""
from __future__ import annotations
import argparse
import importlib
import json
from datetime import datetime, timezone
from pathlib import Path

MODULES = {
    "affine": "affine", "earthengine-api": "ee", "geemap": "geemap",
    "geopandas": "geopandas", "numpy": "numpy", "pandas": "pandas",
    "pyogrio": "pyogrio", "pyproj": "pyproj", "PyYAML": "yaml",
    "rasterio": "rasterio", "scipy": "scipy", "shapely": "shapely",
}

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="_UNG_DUNG/runtime/python_dependency_check.json")
    args = parser.parse_args()
    rows = []
    for package, module_name in MODULES.items():
        try:
            module = importlib.import_module(module_name)
            rows.append({"package": package, "module": module_name, "installed": True, "version": getattr(module, "__version__", None)})
        except Exception as error:
            rows.append({"package": package, "module": module_name, "installed": False, "error": f"{type(error).__name__}: {error}"})
    missing = [row["package"] for row in rows if not row["installed"]]
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps({
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "status": "PASS" if not missing else "FAIL",
        "n_packages": len(rows), "n_missing": len(missing),
        "missing": missing, "packages": rows,
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if missing:
        print("Missing Python packages: " + ", ".join(missing))
        return 1
    print(f"Python dependency check passed: {len(rows)}/{len(rows)} packages.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())