.project_cfg <- yaml::read_yaml("projects/{{PROJECT_ID}}/_NOI_BO/config/project.yml")
POINT_FILE <- "projects/{{PROJECT_ID}}/_NOI_BO/work/models/input/soil_points.csv"
RASTER_DIR <- "projects/{{PROJECT_ID}}/_NOI_BO/work/interpolation"
RASTER_PATTERN <- "^(PC[1-5]|SoilDummy_.+)\\.tif$"
RASTER_MANIFEST_FILE <- "projects/{{PROJECT_ID}}/_NOI_BO/config/raster_manifest_with_soil.csv"
OUTPUT_ROOT <- "projects/{{PROJECT_ID}}/_NOI_BO/work/models/PC_PLUS_SOIL"
OUTPUT_NAME_PREFIX <- "{{PROJECT_ID}}_PC_SOIL_"
TARGET_FIELD <- Sys.getenv("RK_TARGET_FIELD", unset = "auto")
RUN_NAME_OVERRIDE <- Sys.getenv("RK_RUN_NAME", unset = "")
TARGET_METADATA_FILE <- "projects/{{PROJECT_ID}}/02_NOI_SUY_BAN_DO/01_DAU_VAO/indicator_metadata.yml"
POINT_SUPPORT_METADATA_FILE <- "projects/{{PROJECT_ID}}/_NOI_BO/work/interpolation/qa/sample_roi_status.csv"
ASK_OUTPUT_FOLDER <- FALSE
UTM_EPSG <- as.integer(.project_cfg$crs_epsg)
OUTPUT_RESOLUTION <- as.numeric(.project_cfg$resolution_m)
EXPORT_EPSG <- 4326
USE_COMPLETE_PC_MASK <- TRUE
REGRESSION_FORMULA <- NULL
