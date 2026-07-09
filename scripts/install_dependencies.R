# ============================================================
# Install project dependencies from CRAN.
# ============================================================

source("scripts/dependencies.R")

parse_args <- function(args) {
  out <- list(profile = "core,agent", repos = "https://cloud.r-project.org")
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
pkgs <- rk_dependency_packages(profiles)
installed <- rownames(utils::installed.packages())
missing <- setdiff(pkgs, installed)

cat("Dependency profile: ", paste(profiles, collapse = ", "), "\n", sep = "")
cat("Packages requested: ", length(pkgs), "\n", sep = "")
cat("Missing packages: ", length(missing), "\n", sep = "")

if (length(missing) == 0) {
  cat("All requested packages are already installed.\n")
  quit(status = 0)
}

cat("Installing from CRAN: ", args$repos, "\n", sep = "")
cat(paste0("- ", missing), sep = "\n")
cat("\n")

utils::install.packages(missing, repos = args$repos, dependencies = TRUE)

check <- rk_check_dependencies(profiles)
still_missing <- check$package[!check$installed]
if (length(still_missing) > 0) {
  cat("Still missing after install:\n")
  cat(paste0("- ", still_missing), sep = "\n")
  cat("\n")
  quit(status = 1)
}

cat("Dependency installation completed successfully.\n")