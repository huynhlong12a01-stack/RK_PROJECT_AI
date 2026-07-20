# ============================================================
# Check project dependencies.
# ============================================================

source("_UNG_DUNG/engine/scripts/dependencies.R")

parse_args <- function(args) {
  out <- list(profile = "all", output = "_UNG_DUNG/runtime/dependency_check.json")
  i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (startsWith(key, "--")) {
      nm <- sub("^--", "", key)
      val <- TRUE
      if (i + 1L <= length(args) && !startsWith(args[[i + 1L]], "--")) {
        val <- args[[i + 1L]]
        i <- i + 1L
      }
      out[[nm]] <- val
    }
    i <- i + 1L
  }
  out
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
profiles <- trimws(unlist(strsplit(args$profile, "[,;]"), use.names = FALSE))
profiles <- profiles[nzchar(profiles)]
result <- rk_check_dependencies(profiles)
missing <- result$package[!result$installed]

cat("Dependency profile: ", paste(profiles, collapse = ", "), "\n", sep = "")
cat("Installed: ", sum(result$installed), "/", nrow(result), "\n", sep = "")
if (length(missing) > 0) {
  cat("Missing packages:\n")
  cat(paste0("- ", missing), sep = "\n")
  cat("\n")
} else {
  cat("All packages are installed.\n")
}

out <- list(
  profile = profiles,
  n_packages = nrow(result),
  n_installed = sum(result$installed),
  n_missing = length(missing),
  missing = missing,
  packages = result
)

if (!requireNamespace("jsonlite", quietly = TRUE)) stop("Required package jsonlite is missing; install the core dependency profile first.")
dir.create(dirname(args$output), recursive = TRUE, showWarnings = FALSE)
jsonlite::write_json(out, args$output, auto_unbox = TRUE, pretty = TRUE, null = "null")

if (length(missing) > 0) quit(status = 1)
