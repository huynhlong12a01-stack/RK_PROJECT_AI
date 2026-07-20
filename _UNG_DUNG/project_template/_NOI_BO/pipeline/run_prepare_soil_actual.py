import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
PROJECT = ROOT / "projects" / "{{PROJECT_ID}}"
ENGINE = PROJECT / "_NOI_BO" / "pipeline" / "02b_prepare_soil_predictors_v2.py"
spec = importlib.util.spec_from_file_location("project_soil_engine", ENGINE)
engine = importlib.util.module_from_spec(spec)
spec.loader.exec_module(engine)
engine.SOIL_FILE = PROJECT / "01_THIET_KE_LAY_MAU" / "01_DAU_VAO" / "soil_type.geojson"
engine.POINT_FILE = PROJECT / "_NOI_BO" / "work" / "interpolation" / "sample_actual_clean.csv"
engine.PC_DIR = PROJECT / "_NOI_BO" / "work" / "interpolation"
engine.ALIGNED_DIR = PROJECT / "_NOI_BO" / "work" / "interpolation"
engine.QA_DIR = PROJECT / "_NOI_BO" / "work" / "interpolation" / "qa"
engine.main()
