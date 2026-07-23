import importlib.util
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
PROJECT = ROOT / "projects" / "{{PROJECT_ID}}"
CONFIG = PROJECT / "_NOI_BO" / "config" / "project.yml"


def value(name, default):
    text = CONFIG.read_text(encoding="utf-8")
    match = re.search(rf"(?m)^[ \t]*{re.escape(name)}[ \t]*:[ \t]*([^#\r\n]+)", text)
    return match.group(1).strip().strip('"\'') if match else default


grid_file = PROJECT / "_NOI_BO" / "work" / "design" / "grid_template.tif"
# Every download gets a fresh grid derived from the current reviewed ROI and
# synchronized CRS/resolution. Reusing an old template can silently preserve a
# former ROI extent even when ForceDownload was requested.
grid_script = PROJECT / "_NOI_BO" / "pipeline" / "initialize_grid.py"
grid_spec = importlib.util.spec_from_file_location("project_grid", grid_script)
grid = importlib.util.module_from_spec(grid_spec)
grid_spec.loader.exec_module(grid)
grid.main()

engine_path = PROJECT / "_NOI_BO" / "pipeline" / "download_sampling_satellite.py"
spec = importlib.util.spec_from_file_location("project_download_clhs_engine", engine_path)
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)
engine.ROI_FILE = PROJECT / "00_XAC_LAP_VUNG_MIA" / "01_DAU_VAO" / "roi_field_area.geojson"
engine.TEMPLATE_FILE = grid_file
engine.OUTPUT_DIR = PROJECT / "_NOI_BO" / "work" / "design"
engine.TILE_DIR = PROJECT / "_NOI_BO" / "work" / "design" / "qa" / "download_tiles"
engine.QA_FILE = PROJECT / "_NOI_BO" / "work" / "design" / "qa" / "download_summary.json"
engine.gee_support.SOURCE_DIR = engine.OUTPUT_DIR
engine.gee_support.TILE_DIR = engine.TILE_DIR
engine.cfg["project_id"] = "{{PROJECT_ID}}"
engine.cfg["crs_epsg"] = int(float(value("crs_epsg", "32649")))
engine.cfg["resolution_m"] = float(value("resolution_m", "10"))
engine.gee_support.CRS = f"EPSG:{int(float(value('crs_epsg', '32649')))}"
engine.gee_support.START_DATE = value("start_date", "2026-01-01")
engine.gee_support.END_DATE = value("end_date", "2026-04-01")
engine.GEE_PROJECT_ID = value("gee_project_id", "rkapp-492504")
engine.main()
