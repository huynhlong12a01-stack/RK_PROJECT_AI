# Project-local UTF-8 startup for Windows Rscript.
if (identical(.Platform$OS.type, "windows")) {
  candidates <- c(
    "Vietnamese_Vietnam.utf8",
    "English_United States.utf8"
  )
  for (candidate in candidates) {
    active <- suppressWarnings(try(
      Sys.setlocale("LC_CTYPE", candidate), silent = TRUE))
    if (!inherits(active, "try-error") &&
        grepl("utf8|utf-8", active, ignore.case = TRUE)) break
  }
}
options(encoding = "UTF-8")
