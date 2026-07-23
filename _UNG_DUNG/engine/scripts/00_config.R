# ============================================================
# 00_config.R
# Internal defaults for Regression Kriging (project launchers provide paths).
# ============================================================

TARGET_FIELD <- "auto"
# TARGET_FIELD <- "pH_H2O"
# TARGET_FIELD <- "OM_pct"
# TARGET_FIELD <- "CEC"

CODE_COL <- "code"
LAT_COL  <- "lat"
LON_COL  <- "lon"

POINT_FILE <- NA_character_

# ROI is not used in this pipeline. PC rasters are assumed to be pre-masked/cropped with the desired buffer.

# Use all detected PC*.tif files.
# There is no fixed PC count.
RASTER_DIR <- NA_character_
RASTER_PATTERN <- "^PC.*\\.tif$"
# Optional manifest columns: layer, file, type (continuous/categorical), resampling.
# When absent, PC*.tif layers are treated as continuous PCA scores.
RASTER_MANIFEST_FILE <- NA_character_

OUTPUT_ROOT <- NA_character_
ASK_OUTPUT_FOLDER <- TRUE
OUTPUT_NAME_PREFIX <- ""

# Set a numeric EPSG when the study area is fixed, or use "auto" to infer
# the UTM zone from the sample point centroid.
UTM_EPSG <- 32649

# "auto" = use first PC raster resolution after projection to UTM.
OUTPUT_RESOLUTION <- "auto"

EXPORT_EPSG <- 4326

# Use only pixels where all detected PC rasters have values.
USE_COMPLETE_PC_MASK <- TRUE

# NULL means: target ~ all detected PC rasters.
REGRESSION_FORMULA <- NULL

# Variogram mode:
# "manual"      = use MANUAL_* parameters for kriging. Recommended for soil data.
# "auto_select" = try candidate models and choose lowest SSE.
# "auto"        = fit one model from manual initial values.
VARIOGRAM_MODE <- "manual"

# Manual variogram used when VARIOGRAM_MODE <- "manual"
# Suggested workflow:
# 1. Run once.
# 2. Open the variogram report in the active project result directory.
# 3. Adjust model/nugget/psill/range.
# 4. Copy suggested config back here.
VARIOGRAM_MODEL <- "Exp"
MANUAL_NUGGET <- 0.10
MANUAL_PSILL  <- 0.80
MANUAL_RANGE  <- 4000

# Experimental variogram settings.
# Keep cutoff not too far for soil properties to avoid fitting long-range noise.
VARIOGRAM_CUTOFF <- 12000
VARIOGRAM_WIDTH  <- 1000

# Candidate models for suggestion/HTML/reference.
VARIOGRAM_CANDIDATE_MODELS <- c("Exp", "Sph", "Gau")

# Constrained range search for auto suggestions.
# Adjust these based on expected spatial continuity of soil property.
VARIOGRAM_RANGE_MIN <- 1000
VARIOGRAM_RANGE_MAX <- 8000

VARIOGRAM_INITIAL_RANGE_FACTORS  <- c(0.2, 0.4, 0.6)
VARIOGRAM_INITIAL_NUGGET_FACTORS <- c(0.0, 0.1, 0.25)
VARIOGRAM_INITIAL_PSILL_FACTORS  <- c(0.5, 0.8, 1.0)

# Always export candidate suggestion table even when using manual mode.
EXPORT_VARIogram_SUGGESTIONS <- TRUE

# Kriging residual settings.
# AUTO_NEIGHBORS lets the pipeline choose a defensible nmax/search radius
# by spatial CV before the final RK map is created.
AUTO_NEIGHBORS <- TRUE
NMAX_NEIGHBORS <- 12
SEARCH_RADIUS  <- 12000
AUTO_NEIGHBOR_NMAX_CANDIDATES <- c(8, 12, 16, 20, 24, 32)
AUTO_NEIGHBOR_SEARCH_RADIUS_CANDIDATES <- c(6000, 8000, 10000, 12000, 15000, 18000)
AUTO_NEIGHBOR_CV_METHOD <- "spatial_kmeans"
AUTO_NEIGHBOR_MAX_CANDIDATES <- 50

# Always retain audit rasters. RK_final is clamped only when this legacy switch
# is TRUE; unclamped output and a clipping mask are exported in all cases.
CLAMP_TO_SAMPLE_RANGE <- TRUE
MAX_CLIPPED_AREA_PERCENT_WARNING <- 5
MAX_CLIPPED_AREA_PERCENT_HARD_FAIL <- 20
# "auto" uses the evaluation profile/recommendation; options: "auto", "none", "log1p".
TARGET_TRANSFORM <- "auto"
# If TRUE and TARGET_TRANSFORM resolves to log1p, OK/RK back-transform means use exp(mu + 0.5*sigma^2) - 1 when model-scale variance is available.
LOG_BACKTRANSFORM_BIAS_CORRECTION <- FALSE
# ============================================================
# Scientific validation and model comparison
# ============================================================

RUN_CROSS_VALIDATION <- TRUE
CV_K_FOLDS <- 5
CV_RANDOM_SEED <- 42

# Primary development metrics come from outer held-out spatial CV; this is not independent field validation.
# All tuning happens only inside each outer-training partition.
CV_EVALUATION_MODE <- "nested_spatial"
CV_OUTER_METHOD <- "spatial_block"
CV_OUTER_FOLDS <- 5
CV_OUTER_REPEATS <- 5
CV_OUTER_BLOCK_SIZE <- "auto"
CV_INNER_METHOD <- "spatial_block"
CV_INNER_FOLDS <- 4
CV_INNER_NEIGHBOR_MAX_CANDIDATES <- 18
CV_TRANSFORM_CANDIDATES <- c("none", "log1p")
# Keep model comparison on the same median-scale back-transform.
# Kept for request compatibility. Nested CV always forces FALSE so
# Regression-only, OK and RK use the same direct inverse transform.
CV_LOG_BACKTRANSFORM_BIAS_CORRECTION <- FALSE

# Secondary diagnostics only. Random CV must not determine the final grade.
# Supported: random, spatial_kmeans, spatial_block, buffer, nndm.
CV_METHODS <- c("random", "spatial_kmeans")

# Refit variograms inside each CV fold. This is slower but avoids
# leaking variogram information from test points into training folds.
CV_REFIT_VARIOGRAM <- TRUE

# If a kriging prediction has no neighbor inside SEARCH_RADIUS,
# report it as missing instead of silently extrapolating.
CV_REQUIRE_KRIGING_NEIGHBORS <- TRUE

# Warning thresholds used in the report.
MIN_SAMPLE_POINTS_WARNING <- 80
MIN_PAIRS_PER_VARIOGRAM_BIN <- 20
MIN_VARIOGRAM_BINS_WARNING <- 8
REGRESSION_R2_WARNING <- 0.20
MAX_PRACTICAL_RANGE_FACTOR_OF_CUTOFF <- 0.80
MAX_NUGGET_SILL_RATIO_WARNING <- 0.75
PURE_NUGGET_RATIO_THRESHOLD <- 0.95
PURE_NUGGET_POLICY <- "regression_only"
VARIOGRAM_ROBUST_CRESSIE <- TRUE
VARIOGRAM_EXPORT_CLOUD <- TRUE
VARIOGRAM_DIRECTIONAL_ALPHAS <- c(0, 45, 90, 135)
VARIOGRAM_DIRECTIONAL_TOLERANCE <- 22.5
ANISOTROPY_RATIO_WARNING <- 1.5
ANISOTROPY_RATIO_MANUAL_REVIEW <- 2.0

# Uncertainty is residual-kriging uncertainty only and is not scored until
# total predictive intervals have been calibrated.
UNCERTAINTY_HIGH_THRESHOLD_MODE <- "profile_or_cv_rmse"
UNCERTAINTY_SD_IQR_THRESHOLD <- 0.50

# Input/model safety diagnostics.
DUPLICATE_COORDINATE_POLICY <- "stop_conflicts"
REGRESSION_MIN_SAMPLES_PER_PREDICTOR_WARNING <- 10
REGRESSION_MIN_SAMPLES_PER_PREDICTOR_HARD_FAIL <- 5
RUN_AOA_DIAGNOSTICS <- TRUE
AOA_MAX_OUTSIDE_PERCENT_WARNING <- 20
AOA_MAX_OUTSIDE_PERCENT_HARD_FAIL <- 40
# Evaluation profile config for RK quality reporting.
EVALUATION_PROFILE_FILE <- "_UNG_DUNG/engine/config/evaluation_profiles.R"
TARGET_METADATA_FILE <- NA_character_
# Keep report compact. Set TRUE only when you need raw internal CV tables.
EXPORT_RAW_CV_TABLES <- FALSE