.project_cfg <- yaml::read_yaml("projects/PHU_YEN_MOCK/_NOI_BO/config/project.yml")
POINT_FILE <- "projects/PHU_YEN_MOCK/_NOI_BO/work/models/input/soil_points.csv"
RASTER_DIR <- "projects/PHU_YEN_MOCK/_NOI_BO/work/interpolation"
RASTER_PATTERN <- "^PC[1-5]\\.tif$"
RASTER_MANIFEST_FILE <- "projects/PHU_YEN_MOCK/_NOI_BO/config/raster_manifest.csv"
OUTPUT_ROOT <- "projects/PHU_YEN_MOCK/_NOI_BO/work/models/PC_ONLY"
OUTPUT_NAME_PREFIX <- "PHU_YEN_MOCK_PC_"
TARGET_FIELD <- Sys.getenv("RK_TARGET_FIELD", unset = "auto")
RUN_NAME_OVERRIDE <- Sys.getenv("RK_RUN_NAME", unset = "")
TARGET_METADATA_FILE <- "projects/PHU_YEN_MOCK/02_NOI_SUY_BAN_DO/01_DAU_VAO/indicator_metadata.yml"
POINT_SUPPORT_METADATA_FILE <- "projects/PHU_YEN_MOCK/_NOI_BO/work/interpolation/qa/sample_roi_status.csv"
ASK_OUTPUT_FOLDER <- FALSE
UTM_EPSG <- as.integer(.project_cfg$crs_epsg)
OUTPUT_RESOLUTION <- as.numeric(.project_cfg$resolution_m)
EXPORT_EPSG <- 4326
USE_COMPLETE_PC_MASK <- TRUE

# PHU_YEN_MOCK_SMOKE_RUNTIME_V1
# Non-operational smoke configuration: preserves nested spatial CV and inner
# tuning but reduces repetition/grid breadth. Do not copy to production.
AUTO_NEIGHBOR_NMAX_CANDIDATES <- c(8, 12, 20)
AUTO_NEIGHBOR_SEARCH_RADIUS_CANDIDATES <- c(6000, 12000, 18000)
AUTO_NEIGHBOR_MAX_CANDIDATES <- 9
CV_OUTER_FOLDS <- 4
CV_OUTER_REPEATS <- 2
CV_INNER_FOLDS <- 3
CV_INNER_NEIGHBOR_MAX_CANDIDATES <- 6
CV_RANDOM_SEED <- 20260715
RUN_CROSS_VALIDATION <- TRUE
CV_EVALUATION_MODE <- "nested_spatial"
CV_REFIT_VARIOGRAM <- TRUE

# PHU_YEN_MOCK_BOUNDED_SMOKE_RUNTIME_V2
# Still nested spatial CV with inner tuning and variogram refit; tuning breadth
# is intentionally bounded for eight non-operational audit models.
AUTO_NEIGHBOR_NMAX_CANDIDATES <- c(8, 16)
AUTO_NEIGHBOR_SEARCH_RADIUS_CANDIDATES <- c(6000, 12000)
AUTO_NEIGHBOR_MAX_CANDIDATES <- 4
CV_OUTER_FOLDS <- 4
CV_OUTER_REPEATS <- 2
CV_INNER_FOLDS <- 3
CV_INNER_NEIGHBOR_MAX_CANDIDATES <- 4
CV_RANDOM_SEED <- 20260715
RUN_CROSS_VALIDATION <- TRUE
CV_EVALUATION_MODE <- "nested_spatial"
CV_REFIT_VARIOGRAM <- TRUE
