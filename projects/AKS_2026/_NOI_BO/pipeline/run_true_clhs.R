#!/usr/bin/env Rscript

# Run the CRAN clhs optimiser on a deterministic candidate population.
# The Python design engine owns the spatial candidate mask and FULL-plan
# augmentation; this script owns only the conditioned-LHS core selection.

args <- commandArgs(trailingOnly = TRUE)

parse_args <- function(x) {
  out <- list()
  i <- 1L
  while (i <= length(x)) {
    key <- x[[i]]
    if (!startsWith(key, "--") || i == length(x)) {
      stop("Arguments must use --name value pairs; got: ", key)
    }
    out[[substring(key, 3L)]] <- x[[i + 1L]]
    i <- i + 2L
  }
  out
}

opt <- parse_args(args)
required <- c("input", "output-index", "output-meta", "size", "iter",
              "restarts", "seed", "min-spacing-m")
missing <- setdiff(required, names(opt))
if (length(missing)) stop("Missing argument(s): ", paste(missing, collapse = ", "))

as_bool <- function(x, default = FALSE) {
  if (is.null(x)) return(default)
  tolower(trimws(x)) %in% c("1", "true", "yes", "y")
}

script_arg <- commandArgs(FALSE)
script_flag <- grep("^--file=", script_arg, value = TRUE)
script_file <- if (length(script_flag)) sub("^--file=", "", script_flag[[1]]) else NA_character_
pipeline_dir <- if (is.na(script_file)) getwd() else dirname(normalizePath(script_file, winslash = "/"))
internal_dir <- normalizePath(file.path(pipeline_dir, ".."), winslash = "/", mustWork = FALSE)
local_lib <- file.path(internal_dir, "R_library")
dir.create(local_lib, recursive = TRUE, showWarnings = FALSE)
.libPaths(unique(c(local_lib, .libPaths())))

auto_install <- as_bool(opt[["auto-install"]], TRUE)
repository <- if (is.null(opt$repository)) "https://cloud.r-project.org" else opt$repository
install_status <- "already_available"
if (!requireNamespace("clhs", quietly = TRUE) && auto_install) {
  install_status <- "installed_during_run"
  tryCatch(
    install.packages("clhs", lib = local_lib, repos = repository,
                     dependencies = NA, quiet = TRUE),
    error = function(e) message("clhs installation failed: ", conditionMessage(e))
  )
}
if (!requireNamespace("clhs", quietly = TRUE)) {
  stop("CRAN package 'clhs' is unavailable after dependency check.")
}
if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("Package 'jsonlite' is required to write cLHS provenance.")
}

input_file <- normalizePath(opt$input, winslash = "/", mustWork = TRUE)
output_index <- normalizePath(opt[["output-index"]], winslash = "/", mustWork = FALSE)
output_meta <- normalizePath(opt[["output-meta"]], winslash = "/", mustWork = FALSE)
dir.create(dirname(output_index), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(output_meta), recursive = TRUE, showWarnings = FALSE)

size <- as.integer(opt$size)
iterations <- as.integer(opt$iter)
restarts <- as.integer(opt$restarts)
base_seed <- as.integer(opt$seed)
min_spacing_m <- as.numeric(opt[["min-spacing-m"]])
use_cpp <- as_bool(opt[["use-cpp"]], TRUE)
weight_numeric <- as.numeric(if (is.null(opt[["weight-numeric"]])) 1 else opt[["weight-numeric"]])
weight_factor <- as.numeric(if (is.null(opt[["weight-factor"]])) 1 else opt[["weight-factor"]])
weight_correlation <- as.numeric(if (is.null(opt[["weight-correlation"]])) 1 else opt[["weight-correlation"]])

if (any(!is.finite(c(size, iterations, restarts, base_seed, min_spacing_m)))) {
  stop("Non-finite cLHS configuration value.")
}
if (size < 2L || iterations < 1L || restarts < 1L || min_spacing_m < 0) {
  stop("Invalid cLHS size/iteration/restart/spacing configuration.")
}

candidates <- utils::read.csv(input_file, stringsAsFactors = FALSE,
                              check.names = FALSE)
pc_names <- paste0("PC", 1:5)
required_columns <- c("candidate_id", "X_UTM", "Y_UTM", pc_names,
                      "soil_group_code", "soil_group")
missing_columns <- setdiff(required_columns, names(candidates))
if (length(missing_columns)) {
  stop("Candidate file lacks: ", paste(missing_columns, collapse = ", "))
}
if (nrow(candidates) < size) stop("Candidate population is smaller than sample size.")
if (anyDuplicated(candidates$candidate_id)) stop("candidate_id must be unique.")

for (name in c("X_UTM", "Y_UTM", pc_names)) {
  candidates[[name]] <- as.numeric(candidates[[name]])
}
if (any(!is.finite(as.matrix(candidates[c("X_UTM", "Y_UTM", pc_names)])))) {
  stop("Candidate coordinates/PC values must all be finite.")
}

# PC1-PC5 are the continuous exhaustive ancillary variables. Soil Type is
# deliberately a factor, never a numeric distance. A single synthetic "All"
# class is omitted because it contributes no categorical information.
design_data <- candidates[pc_names]
soil_levels <- sort(unique(as.character(candidates$soil_group)))
soil_factor_used <- length(soil_levels) > 1L
if (soil_factor_used) {
  design_data$Soil_Type <- factor(as.character(candidates$soil_group),
                                  levels = soil_levels)
}

weights <- list(
  numeric = weight_numeric,
  factor = weight_factor,
  correlation = weight_correlation
)

spacing_metrics <- function(index) {
  xy <- as.matrix(candidates[index, c("X_UTM", "Y_UTM"), drop = FALSE])
  d <- as.matrix(stats::dist(xy))
  diag(d) <- Inf
  list(
    nearest_neighbor_min_m = min(d),
    spacing_violation_pairs = sum(d[lower.tri(d)] < min_spacing_m),
    minimum_spacing_target_met = min(d) >= min_spacing_m
  )
}

runs <- vector("list", restarts)
successful <- list()
for (restart in seq_len(restarts)) {
  run_seed <- as.integer(base_seed + (restart - 1L) * 100003L)
  set.seed(run_seed)
  started <- proc.time()[["elapsed"]]
  result <- tryCatch(
    clhs::clhs(
      x = design_data,
      size = size,
      iter = iterations,
      use.cpp = use_cpp,
      weights = weights,
      simple = FALSE,
      progress = FALSE,
      use.coords = FALSE
    ),
    error = function(e) e
  )
  elapsed <- proc.time()[["elapsed"]] - started
  if (inherits(result, "error")) {
    runs[[restart]] <- list(
      restart = restart,
      seed = run_seed,
      status = "failed",
      error = conditionMessage(result),
      elapsed_seconds = unname(elapsed)
    )
    next
  }
  index <- as.integer(result$index_samples)
  if (length(index) != size || anyDuplicated(index) ||
      any(index < 1L | index > nrow(candidates))) {
    stop("clhs returned invalid sample indices on restart ", restart, ".")
  }
  objective_trace <- as.numeric(result$obj)
  objective_trace <- objective_trace[is.finite(objective_trace)]
  objective_final <- if (length(objective_trace)) tail(objective_trace, 1L) else NA_real_
  spacing <- spacing_metrics(index)
  record <- c(list(
    restart = restart,
    seed = run_seed,
    status = "ok",
    objective_final = objective_final,
    elapsed_seconds = unname(elapsed)
  ), spacing)
  runs[[restart]] <- record
  successful[[length(successful) + 1L]] <- list(index = index, record = record)
}

if (!length(successful)) stop("All CRAN clhs optimisation restarts failed.")

# Every restart is an unmodified CRAN-clhs solution. Multi-start selection first
# minimises spacing violations, then the cLHS objective. It does not silently
# move or replace any point after optimisation.
violation <- vapply(successful, function(x) x$record$spacing_violation_pairs, numeric(1))
objective <- vapply(successful, function(x) x$record$objective_final, numeric(1))
objective[!is.finite(objective)] <- Inf
min_distance <- vapply(successful, function(x) x$record$nearest_neighbor_min_m, numeric(1))
best <- order(violation, objective, -min_distance)[[1]]
selected <- successful[[best]]
selected_rows <- candidates[selected$index, , drop = FALSE]
selected_output <- data.frame(
  selection_rank = seq_len(nrow(selected_rows)),
  candidate_id = selected_rows$candidate_id
)
utils::write.csv(selected_output, output_index, row.names = FALSE,
                 fileEncoding = "UTF-8")

package_path <- find.package("clhs")
description_path <- file.path(package_path, "DESCRIPTION")
metadata <- list(
  schema_version = "1.0.0",
  status = "success",
  backend_used = "r_clhs_cran",
  algorithm = "conditioned_latin_hypercube_simulated_annealing",
  package = list(
    name = "clhs",
    version = as.character(utils::packageVersion("clhs")),
    repository = repository,
    project_url = "https://github.com/pierreroudier/clhs/",
    installed_path = normalizePath(package_path, winslash = "/"),
    description_md5 = unname(tools::md5sum(description_path)),
    install_status = install_status
  ),
  scientific_reference = list(
    citation = paste(
      "Minasny, B. and McBratney, A.B. (2006). A conditioned Latin",
      "hypercube method for sampling in the presence of ancillary information."
    ),
    doi = "10.1016/j.cageo.2005.12.009"
  ),
  candidate_count = nrow(candidates),
  sample_size = size,
  continuous_covariates = pc_names,
  continuous_space = "PCA_full_rank_rotation_PC1_PC5",
  soil_type = list(
    supplied_to_optimizer = soil_factor_used,
    representation = if (soil_factor_used) "categorical_factor" else "omitted_single_level",
    levels = soil_levels
  ),
  coordinates_in_clhs_objective = FALSE,
  spatial_candidate_constraints_applied_before_optimizer = c(
    "inside_inner_buffered_ROI", "valid_PC1_PC5", "valid_Soil_Group_Code"
  ),
  optimiser = list(
    implementation = if (use_cpp) "clhs_C++" else "clhs_R",
    iterations_per_restart = iterations,
    restarts_requested = restarts,
    successful_restarts = length(successful),
    base_seed = base_seed,
    deterministic_restart_seed_increment = 100003L,
    weights = weights
  ),
  multi_start_selection = list(
    rule = paste(
      "lexicographic: fewest minimum-spacing violation pairs, lowest final",
      "cLHS objective, largest minimum nearest-neighbour distance"
    ),
    selected_restart = selected$record$restart,
    selected_seed = selected$record$seed,
    minimum_spacing_target_m = min_spacing_m,
    selected_spacing_violation_pairs = selected$record$spacing_violation_pairs,
    selected_nearest_neighbor_min_m = selected$record$nearest_neighbor_min_m,
    minimum_spacing_target_met = selected$record$minimum_spacing_target_met,
    no_post_optimisation_point_replacement = TRUE
  ),
  runs = runs,
  interpretation = paste(
    "The REDUCED core is an unmodified result from the CRAN clhs optimiser.",
    "The optimiser is stochastic and heuristic; this is not a proof of a global optimum.",
    "Spatial infill and short-lag points are added later and are not direct cLHS outputs."
  )
)
jsonlite::write_json(metadata, output_meta, auto_unbox = TRUE, pretty = TRUE,
                     null = "null", digits = NA)

cat("TRUE_CLHS_OK package=clhs version=",
    as.character(utils::packageVersion("clhs")),
    " selected_seed=", selected$record$seed,
    " spacing_violations=", selected$record$spacing_violation_pairs, "\n", sep = "")
