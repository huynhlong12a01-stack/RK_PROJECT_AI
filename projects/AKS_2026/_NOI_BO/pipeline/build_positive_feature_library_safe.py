#!/usr/bin/env python3
"""Run the positive extractor with rolling complete-period features."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path


HERE = Path(__file__).resolve().parent


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


FINAL = load("positive_field_area_final", HERE / "interpret_sugarcane_area_final.py")
EXTRACTOR = load("positive_extractor_core", HERE / "build_positive_feature_library.py")


def safe_core_loader(path):
    return FINAL.CORE


EXTRACTOR.load_core = safe_core_loader


if __name__ == "__main__":
    raise SystemExit(EXTRACTOR.main())
