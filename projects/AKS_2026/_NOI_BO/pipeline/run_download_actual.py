import importlib.util
import re
import sys
import types
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
PROJECT = ROOT / "projects" / "AKS_2026"
CONFIG = PROJECT / "_NOI_BO" / "config" / "project.yml"


def value(name, default):
    text = CONFIG.read_text(encoding="utf-8")
    match = re.search(rf"(?m)^\s*{re.escape(name)}\s*:\s*([^#\r\n]+)", text)
    return match.group(1).strip().strip('"\'') if match else default


engine_file = PROJECT / "_NOI_BO" / "pipeline" / "02_download_gee_support.py"
cfg = {
    "project_id": "AKS_2026",
    "crs_epsg": int(float(value("crs_epsg", "32649"))),
    "resolution_m": float(value("resolution_m", "10")),
    "source": {"legacy_pca_dir": str(PROJECT / "_NOI_BO" / "work" / "design")},
    "legacy_parameters": {
        "start_date": value("start_date", "2026-01-01"),
        "end_date": value("end_date", "2026-04-01"),
    },
    "runtime": {
        "support_buffers_gpkg": str(PROJECT / "_NOI_BO" / "work" / "interpolation" / "covariate_support_buffers.gpkg"),
        "expanded_covariate_dir": str(PROJECT / "_NOI_BO" / "work" / "interpolation"),
        "qa_dir": str(PROJECT / "_NOI_BO" / "work" / "interpolation" / "qa"),
    },
}
yaml_shim = types.ModuleType("yaml")
yaml_shim.safe_load = lambda _text: cfg
sys.modules["yaml"] = yaml_shim
spec = importlib.util.spec_from_file_location("project_download_actual_engine", engine_file)
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)
engine.BUFFER_FILE = Path(cfg["runtime"]["support_buffers_gpkg"])
engine.SOURCE_DIR = Path(cfg["runtime"]["expanded_covariate_dir"])
engine.QA_DIR = Path(cfg["runtime"]["qa_dir"])
engine.TEMPLATE_FILE = Path(cfg["source"]["legacy_pca_dir"]) / "PC1.tif"
engine.TILE_DIR = PROJECT / "_NOI_BO" / "work" / "interpolation" / "qa" / "download_tiles"
engine.GEE_PROJECT_ID = value("gee_project_id", "rkapp-492504")
engine.main()
