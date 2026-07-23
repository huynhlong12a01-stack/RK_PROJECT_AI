suppressPackageStartupMessages({
  library(terra)
  library(sf)
  library(yaml)
  library(jsonlite)
})

args <- commandArgs(trailingOnly = TRUE)
read_arg <- function(name, default = NULL) {
  hit <- which(args == name)
  if (length(hit) == 0 || hit[1] == length(args)) return(default)
  args[hit[1] + 1]
}

run_dir <- read_arg("--run_dir")
if (is.null(run_dir) || !dir.exists(run_dir)) {
  stop("Provide a valid RK run folder with --run_dir.")
}
cfg <- yaml::read_yaml("projects/AKS_BLIND_ROI_TEST/_NOI_BO/config/project.yml")
roi_file <- cfg$source$roi_file
input_dir <- file.path(run_dir, "05_final_rk")
if (!dir.exists(input_dir)) stop("Run folder has no 05_final_rk directory: ", run_dir)

output_dir <- read_arg(
  "--output_dir",
  file.path(cfg$runtime$report_dir, "final_roi", basename(normalizePath(run_dir)))
)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

files <- list.files(input_dir, pattern = "\\.tif$", full.names = TRUE, ignore.case = TRUE)
if (length(files) == 0) stop("No final GeoTIFF found in: ", input_dir)
roi <- terra::vect(sf::st_make_valid(sf::st_read(roi_file, quiet = TRUE)))

outputs <- character(0)
for (file in files) {
  r <- rast(file)
  roi_r <- terra::project(roi, terra::crs(r))
  masked <- terra::mask(r, roi_r, touches = FALSE)
  output <- file.path(output_dir, basename(file))
  writeRaster(
    masked, output, overwrite = TRUE,
    gdal = c("COMPRESS=LZW", "BIGTIFF=IF_SAFER")
  )
  outputs <- c(outputs, output)
}

summary <- list(
  source_run = normalizePath(run_dir, winslash = "/", mustWork = TRUE),
  roi = normalizePath(roi_file, winslash = "/", mustWork = TRUE),
  output_dir = normalizePath(output_dir, winslash = "/", mustWork = FALSE),
  files = normalizePath(outputs, winslash = "/", mustWork = FALSE),
  policy = "final deliverables masked to original sugarcane ROI; outside support buffers excluded"
)
jsonlite::write_json(
  summary, file.path(output_dir, "final_roi_mask_summary.json"),
  pretty = TRUE, auto_unbox = TRUE
)
cat("Final ROI masking complete: ", output_dir, "\n", sep = "")
