suppressPackageStartupMessages({
  library(terra)
  library(readr)
  library(jsonlite)
})

base <- "projects/AKS_2026"
internal <- file.path(base, "_NOI_BO")
ref_file <- file.path(internal, "config/pca_model_reference.json")
point_file <- file.path(internal, "work/interpolation/sample_actual_clean.csv")
design_dir <- file.path(internal, "work/design")
current_dir <- file.path(internal, "work/interpolation")
qa_dir <- file.path(current_dir, "qa")
sidecar_file <- file.path(qa_dir, "pca_current_provenance.json")
tolerance <- 1e-3

if (!requireNamespace("digest", quietly = TRUE)) stop("Package 'digest' is required.")
ref <- jsonlite::read_json(ref_file, simplifyVector = TRUE)
ref_hash <- as.character(ref$reference_hash)
if (length(ref_hash) != 1L || !grepl("^[0-9a-f]{64}$", ref_hash)) {
  stop("PCA reference_hash is missing or is not SHA-256.")
}
if (!isTRUE(ref$reference_frozen)) stop("PCA reference is not frozen.")
if (is.null(ref$reference_version) || !nzchar(as.character(ref$reference_version))) {
  stop("PCA reference_version is missing.")
}
if (!file.exists(point_file)) stop("Run actual-sample preflight first.")

points <- as.data.frame(readr::read_csv(point_file, show_col_types = FALSE, progress = FALSE))
pts <- terra::vect(points, geom = c("lon", "lat"), crs = "EPSG:4326")
pts <- terra::project(pts, "EPSG:32649")

extract_files <- function(files) {
  if (!all(file.exists(files))) return(NULL)
  values <- lapply(files, function(path) terra::extract(rast(path)[[1]], pts)[, 2])
  as.matrix(as.data.frame(values, stringsAsFactors = FALSE))
}

current_files <- file.path(current_dir, paste0("PC", 1:5, ".tif"))
design_files <- file.path(design_dir, paste0("PC", 1:5, ".tif"))
raw_files <- file.path(current_dir, paste0(as.character(ref$feature_order), ".tif"))
current <- extract_files(current_files)
design <- extract_files(design_files)
raw <- extract_files(raw_files)
if (is.null(current) || is.null(design) || is.null(raw)) stop("PCA provenance verification inputs are incomplete.")

raw_complete <- stats::complete.cases(raw)
design_complete <- stats::complete.cases(design)
current_complete <- stats::complete.cases(current)
z <- sweep(raw, 2, as.numeric(ref$scaler_mean), "-")
z <- sweep(z, 2, as.numeric(ref$scaler_scale), "/")
raw_pc <- z %*% t(as.matrix(ref$pca_components))

expected <- matrix(NA_real_, nrow = nrow(points), ncol = 5L)
verification_source <- rep("unavailable", nrow(points))
expected[design_complete, ] <- design[design_complete, , drop = FALSE]
verification_source[design_complete] <- "workflow1_frozen_pca_raster"
use_raw <- !design_complete & raw_complete
expected[use_raw, ] <- raw_pc[use_raw, , drop = FALSE]
verification_source[use_raw] <- "raw_covariates_recomputed_with_frozen_reference"
expected_complete <- stats::complete.cases(expected)
if (any(!current_complete)) stop("Current interpolation PC rasters are incomplete at ", sum(!current_complete), " sample(s).")
if (any(!expected_complete)) stop("Cannot independently verify PCA provenance at ", sum(!expected_complete), " sample(s).")

abs_error <- abs(current - expected)
max_error_by_pc <- apply(abs_error, 2, max, na.rm = TRUE)
if (any(max_error_by_pc > tolerance)) {
  stop(
    "Current PCA rasters do not match the frozen reference; max errors: ",
    paste(signif(max_error_by_pc, 6), collapse = ", ")
  )
}

pc_hashes <- setNames(
  vapply(current_files, digest::digest, character(1), file = TRUE, algo = "sha256"),
  basename(current_files)
)
point_verification <- data.frame(
  code = points$code,
  verification_source = verification_source,
  maximum_absolute_pc_error = apply(abs_error, 1, max, na.rm = TRUE),
  stringsAsFactors = FALSE
)
dir.create(qa_dir, recursive = TRUE, showWarnings = FALSE)
readr::write_csv(point_verification, file.path(qa_dir, "pca_current_provenance_points.csv"), na = "")
jsonlite::write_json(
  list(
    project_id = "AKS_2026",
    pca_reference_hash = ref_hash,
    reference_frozen = TRUE,
    reference_version = as.character(ref$reference_version),
    verification_status = "verified_against_workflow1_or_recomputed_raw_covariates",
    verification_tolerance = tolerance,
    n_points = nrow(points),
    n_verified_against_workflow1 = sum(design_complete),
    n_verified_by_raw_recomputation = sum(use_raw),
    n_verified_total = sum(expected_complete),
    max_absolute_error_by_pc = as.list(setNames(max_error_by_pc, paste0("PC", 1:5))),
    pc_file_sha256 = as.list(pc_hashes),
    generated_utc = format(Sys.time(), tz = "UTC", usetz = TRUE)
  ),
  sidecar_file, pretty = TRUE, auto_unbox = TRUE
)
cat("Current PCA provenance verified for ", nrow(points), " samples.\n", sep = "")
