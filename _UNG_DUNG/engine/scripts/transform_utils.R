# ============================================================
# Target transform helpers for Regression Kriging.
# These functions are intentionally lightweight so they can be unit-tested
# without running the full raster engine.
# ============================================================

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x
}

rk_transform_values <- function(x, transform) {
  x <- suppressWarnings(as.numeric(x))
  transform <- tolower(as.character(transform %||% "none")[1])
  if (identical(transform, "log1p")) return(log1p(x))
  x
}

rk_back_transform_values <- function(x, transform, variance = NULL, bias_correction = FALSE) {
  x <- suppressWarnings(as.numeric(x))
  transform <- tolower(as.character(transform %||% "none")[1])
  if (!identical(transform, "log1p")) return(x)

  if (isTRUE(bias_correction) && !is.null(variance)) {
    v <- pmax(suppressWarnings(as.numeric(variance)), 0)
    return(exp(x + 0.5 * v) - 1)
  }

  expm1(x)
}

rk_back_transform_variance_values <- function(variance, mean_model_scale, transform, bias_correction = FALSE) {
  variance <- pmax(suppressWarnings(as.numeric(variance)), 0)
  mean_model_scale <- suppressWarnings(as.numeric(mean_model_scale))
  transform <- tolower(as.character(transform %||% "none")[1])
  if (identical(transform, "log1p")) {
    bias_term <- if (isTRUE(bias_correction)) 0.5 * variance else 0
    return(variance * exp(2 * (mean_model_scale + bias_term)))
  }
  variance
}

rk_back_transform_raster <- function(r, transform, variance_raster = NULL, bias_correction = FALSE) {
  transform <- tolower(as.character(transform %||% "none")[1])
  if (!identical(transform, "log1p")) return(r)

  if (isTRUE(bias_correction) && !is.null(variance_raster)) {
    x <- c(r, variance_raster)
    names(x) <- c("mu", "variance")
    return(terra::lapp(x, fun = function(mu, variance) exp(mu + 0.5 * pmax(variance, 0)) - 1))
  }

  terra::app(r, fun = expm1)
}

rk_back_transform_variance_raster <- function(variance_raster, mean_model_raster, transform, bias_correction = FALSE) {
  transform <- tolower(as.character(transform %||% "none")[1])
  if (identical(transform, "log1p")) {
    x <- c(mean_model_raster, variance_raster)
    names(x) <- c("mu", "variance")
    return(terra::lapp(x, fun = function(mu, variance) {
      variance <- pmax(variance, 0)
      bias_term <- if (isTRUE(bias_correction)) 0.5 * variance else 0
      variance * exp(2 * (mu + bias_term))
    }))
  }
  variance_raster
}

resolve_target_transform <- function(target_field, values) {
  requested <- if (exists("TARGET_TRANSFORM")) TARGET_TRANSFORM else "auto"
  requested <- tolower(as.character(requested[1]))
  if (!(requested %in% c("auto", "none", "log1p"))) {
    stop("TARGET_TRANSFORM must be 'auto', 'none', or 'log1p'.")
  }

  profiles <- load_evaluation_profiles(EVALUATION_PROFILE_FILE %||% "_UNG_DUNG/engine/config/evaluation_profiles.R")
  profile_override <- if (exists("TARGET_PROFILE_OVERRIDE"))
    TARGET_PROFILE_OVERRIDE else NULL
  if (!is.null(profile_override) && profile_override %in% names(profiles)) {
    profile <- profiles[[profile_override]]
    profile$profile_name <- profile_override
    profile$profile_matched <- TRUE
    profile$profile_ambiguous <- FALSE
  } else {
    profile <- match_indicator_profile(target_field, profiles)
  }
  recommendation <- rk_eval_transform_recommendation(values, profile)
  selected <- if (identical(requested, "auto")) recommendation$transform else requested
  selected <- tolower(as.character(selected %||% "none"))
  if (!(selected %in% c("none", "log1p"))) selected <- "none"

  x <- suppressWarnings(as.numeric(values))
  x <- x[is.finite(x)]
  warning <- NULL
  requires_nonnegative <- isTRUE(profile$transform_requires_nonnegative %||% FALSE)

  if (identical(selected, "log1p") && requires_nonnegative && any(x < 0, na.rm = TRUE)) {
    warning <- "TARGET_TRANSFORM resolved to log1p, but this profile requires non-negative values and negative target values were found; falling back to none."
    selected <- "none"
  }

  if (identical(selected, "log1p") && any(x <= -1, na.rm = TRUE)) {
    warning <- "TARGET_TRANSFORM resolved to log1p, but values <= -1 were found; falling back to none because log1p is undefined."
    selected <- "none"
  }

  list(
    requested = requested,
    selected = selected,
    profile_name = profile$profile_name %||% target_field,
    recommendation = recommendation,
    requires_nonnegative = requires_nonnegative,
    warning = warning
  )
}