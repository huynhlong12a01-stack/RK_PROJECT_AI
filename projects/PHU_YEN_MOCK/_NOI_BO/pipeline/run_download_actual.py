"""Launch the project's privacy-gated GEE support downloader."""

import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
PROJECT = ROOT / "projects" / "PHU_YEN_MOCK"
ENGINE_FILE = PROJECT / "_NOI_BO" / "pipeline" / "02_download_gee_support.py"

spec = importlib.util.spec_from_file_location("project_download_actual_engine", ENGINE_FILE)
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)
engine.main()