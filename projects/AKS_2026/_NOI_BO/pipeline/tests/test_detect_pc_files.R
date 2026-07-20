main_expressions <- parse("_UNG_DUNG/engine/scripts/main.R")
is_detect_assignment <- vapply(
  main_expressions,
  function(expr) {
    is.call(expr) && identical(expr[[1]], as.name("<-")) &&
      identical(expr[[2]], as.name("detect_pc_files"))
  },
  logical(1)
)
stopifnot(sum(is_detect_assignment) == 1L)
eval(main_expressions[[which(is_detect_assignment)]], envir = .GlobalEnv)

run_test <- function() {
  fixture <- file.path(
    "_UNG_DUNG/runtime/tests",
    paste0("rk-raster-sort-", Sys.getpid())
  )
  dir.create(fixture, recursive = TRUE)
  on.exit(unlink(fixture, recursive = TRUE, force = TRUE), add = TRUE)

  input_names <- c(
    "SoilDummy_Unmapped.tif", "PC10.tif", "PC2.tif",
    "SoilDummy_Fa.tif", "PC1.tif"
  )
  stopifnot(all(file.create(file.path(fixture, input_names))))
  RASTER_DIR <<- fixture
  RASTER_PATTERN <<- "\\.tif$"
  files <- detect_pc_files()

  stopifnot(length(files) == length(input_names))
  stopifnot(
    identical(
      basename(unname(files)),
      c(
        "PC1.tif", "PC2.tif", "PC10.tif",
        "SoilDummy_Fa.tif", "SoilDummy_Unmapped.tif"
      )
    )
  )
  stopifnot(setequal(basename(unname(files)), input_names))
  cat("Raster discovery test passed: nonnumeric SoilDummy names are retained and sorted.\n")
}

run_test()
