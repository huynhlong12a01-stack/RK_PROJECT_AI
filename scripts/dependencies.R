# ============================================================
# Dependency manifest for RK_R_Project
# ============================================================

RK_DEPENDENCIES <- list(
  core = c(
    "sf",
    "terra",
    "gstat",
    "sp",
    "jsonlite",
    "digest",
    "yaml",
    "blockCV",
    "CAST",
    "lmtest"
  ),
  sampling_design = c(
    "clhs"
  ),
  tidy_io = c(
    "readr",
    "openxlsx2",
    "dplyr",
    "purrr",
    "stringr",
    "tibble",
    "rlang"
  ),
  agent = c(
    "jsonlite",
    "readr",
    "digest",
    "yaml"
  ),
  rag = c(
    "pdftools",
    "digest",
    "jsonlite",
    "stringr",
    "tibble",
    "dplyr",
    "purrr",
    "readr"
  ),
  geostat_extra = c(
    "automap"
  ),
  spatial_cv = c(
    "blockCV",
    "CAST",
    "rsample"
  ),
  modeling = c(
    "mgcv",
    "ranger",
    "randomForest",
    "xgboost",
    "caret"
  )
)

rk_dependency_profiles <- function() {
  c(names(RK_DEPENDENCIES), "all")
}

rk_dependency_packages <- function(profile = "all") {
  profile <- unique(profile)
  if ("all" %in% profile) {
    return(unique(unlist(RK_DEPENDENCIES, use.names = FALSE)))
  }
  unknown <- setdiff(profile, names(RK_DEPENDENCIES))
  if (length(unknown) > 0) {
    stop(paste0("Unknown dependency profile(s): ", paste(unknown, collapse = ", ")))
  }
  unique(unlist(RK_DEPENDENCIES[profile], use.names = FALSE))
}

rk_check_dependencies <- function(profile = "all") {
  pkgs <- rk_dependency_packages(profile)
  installed <- rownames(utils::installed.packages())
  data.frame(
    package = pkgs,
    installed = pkgs %in% installed,
    stringsAsFactors = FALSE
  )
}