import importlib.util
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
PROJECT = ROOT / "projects" / "AKS_2026"
CONFIG = PROJECT / "_NOI_BO" / "config" / "project.yml"


def value(name, default):
    text = CONFIG.read_text(encoding="utf-8")
    match = re.search(rf"(?m)^\s*{re.escape(name)}\s*:\s*([^#\r\n]+)", text)
    return match.group(1).strip().strip('"\'') if match else default


grid_file = PROJECT / "_NOI_BO" / "work" / "design" / "grid_template.tif"
if not grid_file.exists():
    grid_script = PROJECT / "_NOI_BO" / "pipeline" / "initialize_grid.py"
    grid_spec = importlib.util.spec_from_file_location("project_grid", grid_script)
    grid = importlib.util.module_from_spec(grid_spec)
    grid_spec.loader.exec_module(grid)
    grid.main()

engine_path = PROJECT / "_NOI_BO" / "pipeline" / "download_sampling_satellite.py"
spec = importlib.util.spec_from_file_location("project_download_clhs_engine", engine_path)
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)
engine.ROI_FILE = PROJECT / "01_THIET_KE_LAY_MAU" / "01_DAU_VAO" / "roi.geojson"
engine.TEMPLATE_FILE = grid_file
engine.OUTPUT_DIR = PROJECT / "_NOI_BO" / "work" / "design"
engine.TILE_DIR = PROJECT / "_NOI_BO" / "work" / "design" / "qa" / "download_tiles"
engine.QA_FILE = PROJECT / "_NOI_BO" / "work" / "design" / "qa" / "download_summary.json"
engine.gee_support.SOURCE_DIR = engine.OUTPUT_DIR
engine.gee_support.TILE_DIR = engine.TILE_DIR
engine.cfg["project_id"] = "AKS_2026"
engine.cfg["crs_epsg"] = int(float(value("crs_epsg", "32649")))
engine.cfg["resolution_m"] = float(value("resolution_m", "10"))
engine.gee_support.CRS = f"EPSG:{int(float(value('crs_epsg', '32649')))}"
engine.gee_support.START_DATE = value("start_date", "2026-01-01")
engine.gee_support.END_DATE = value("end_date", "2026-04-01")
engine.GEE_PROJECT_ID = value("gee_project_id", "rkapp-492504")
engine.main()
