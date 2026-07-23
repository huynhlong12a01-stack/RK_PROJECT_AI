# ============================================================
# Lightweight unit smoke tests for target transform helpers.
# Does not run the full raster/geostatistical engine.
# ============================================================

source("_UNG_DUNG/engine/rk_evaluation/evaluation.R")
source("_UNG_DUNG/engine/scripts/transform_utils.R")

ok <- function(label) cat("[OK] ", label, "\n", sep = "")
fail <- function(label) stop(paste0("[FAIL] ", label), call. = FALSE)

x <- c(0, 1, 10, 50)
z <- rk_transform_values(x, "log1p")
back <- rk_back_transform_values(z, "log1p")
if (max(abs(back - x), na.rm = TRUE) > 1e-10) fail("log1p round-trip did not recover original values")
ok("log1p round-trip returns original units")

v <- c(0, 0.01, 0.05, 0.20)
back_direct <- rk_back_transform_values(z, "log1p", variance = v, bias_correction = FALSE)
back_corrected <- rk_back_transform_values(z, "log1p", variance = v, bias_correction = TRUE)
if (any(back_corrected[v > 0] <= back_direct[v > 0])) fail("bias-corrected log back-transform should increase means when variance > 0")
ok("bias correction increases log back-transformed means when variance is positive")

var_direct <- rk_back_transform_variance_values(v, z, "log1p", bias_correction = FALSE)
var_corrected <- rk_back_transform_variance_values(v, z, "log1p", bias_correction = TRUE)
if (any(var_corrected[v > 0] < var_direct[v > 0])) fail("bias-corrected variance should not be smaller under delta approximation")
ok("variance back-transform honors bias-correction setting")

TARGET_TRANSFORM <- "log1p"
EVALUATION_PROFILE_FILE <- "_UNG_DUNG/engine/config/evaluation_profiles.R"
res <- resolve_target_transform("P_Olsen_mgkg", c(1, 2, 8, 30, 120))
if (!identical(res$selected, "log1p")) fail("P_Olsen profile with positive values should allow log1p")
if (!isTRUE(res$requires_nonnegative)) fail("P_Olsen profile should require non-negative values")
ok("profile-based log1p transform resolves for positive nutrient values")

res_neg <- resolve_target_transform("P_Olsen_mgkg", c(-0.1, 1, 2, 3))
if (!identical(res_neg$selected, "none") || is.null(res_neg$warning)) fail("negative nutrient values should fallback from log1p to none")
ok("profile-based nonnegative rule protects log1p from negative nutrient values")

custom_profiles <- rk_eval_default_profiles()
custom_profiles$generic_continuous$transform_requires_nonnegative <- FALSE
EVALUATION_PROFILES <- custom_profiles
res_math <- resolve_target_transform("generic_continuous", c(-0.5, 0, 1))
if (!identical(res_math$selected, "log1p")) fail("generic profile with x > -1 should allow log1p when nonnegative rule is disabled")
res_math_bad <- resolve_target_transform("generic_continuous", c(-1, 0, 1))
if (!identical(res_math_bad$selected, "none")) fail("values <= -1 must fallback because log1p is undefined")
ok("mathematical log1p domain check works independently from soil nonnegative rule")

cat("[OK] Transform smoke test completed.\n")
