# ============================================================
# Inventory local user-provided or open-access research files.
# Does not upload files, does not commit raw documents, does not extract text.
# ============================================================

source("scripts/agent_utils.R")

parse_args <- function(args) {
  out <- list()
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

safe_doc_id <- function(path) {
  x <- tools::file_path_sans_ext(basename(path))
  x <- gsub("[^A-Za-z0-9_-]+", "_", x)
  x <- gsub("_+", "_", x)
  x <- gsub("^_|_$", "", x)
  if (!nzchar(x)) x <- "local_doc"
  x
}

hash_algorithm <- function() "sha256"

hash_files <- function(files) {
  agent_require_package("digest")
  if (length(files) == 0) return(character(0))
  vapply(files, digest::digest, character(1), file = TRUE, algo = "sha256")
}

make_unique <- function(x) {
  out <- character(length(x))
  seen <- new.env(parent = emptyenv())
  for (i in seq_along(x)) {
    base <- x[[i]]
    candidate <- base
    n <- 1L
    while (exists(candidate, envir = seen, inherits = FALSE)) {
      n <- n + 1L
      candidate <- paste0(base, "_", n)
    }
    assign(candidate, TRUE, envir = seen)
    out[[i]] <- candidate
  }
  out
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
library_dir <- args$library %||% "knowledge/library"
inventory_out <- args$inventory %||% "knowledge/metadata/local_library_inventory.csv"
draft_out <- args$draft %||% "knowledge/metadata/local_source_metadata_draft.csv"

if (!dir.exists(library_dir)) dir.create(library_dir, recursive = TRUE, showWarnings = FALSE)
agent_ensure_dir(dirname(inventory_out))
agent_ensure_dir(dirname(draft_out))

files <- list.files(library_dir, recursive = TRUE, full.names = TRUE, all.files = FALSE)
files <- files[file.info(files)$isdir == FALSE]
files <- files[grepl("\\.(pdf|txt|md|docx|html?)$", files, ignore.case = TRUE)]
algo <- hash_algorithm()

if (length(files) == 0) {
  inventory <- data.frame(
    doc_id = character(0), relative_path = character(0), file_name = character(0), extension = character(0),
    size_bytes = numeric(0), modified_time = character(0), file_hash = character(0), hash_algorithm = character(0),
    metadata_status = character(0), copyright_status = character(0), stringsAsFactors = FALSE
  )
  draft <- data.frame(
    doc_id = character(0), title = character(0), authors = character(0), year = character(0), source_type = character(0),
    journal_or_publisher = character(0), doi = character(0), url = character(0), access_date = character(0), language = character(0),
    topic_tags = character(0), soil_indicators = character(0), geography = character(0), method_tags = character(0),
    quality_level = character(0), license_or_access_note = character(0), notes = character(0), local_relative_path = character(0),
    file_hash = character(0), hash_algorithm = character(0), stringsAsFactors = FALSE
  )
} else {
  info <- file.info(files)
  root <- normalizePath(library_dir, winslash = "/", mustWork = FALSE)
  rel <- gsub("\\\\", "/", substring(normalizePath(files, winslash = "/", mustWork = FALSE), nchar(root) + 2L))
  doc_ids <- make_unique(vapply(files, safe_doc_id, character(1)))
  file_hash <- hash_files(files)
  inventory <- data.frame(
    doc_id = doc_ids,
    relative_path = rel,
    file_name = basename(files),
    extension = tolower(tools::file_ext(files)),
    size_bytes = info$size,
    modified_time = format(info$mtime, "%Y-%m-%d %H:%M:%S"),
    file_hash = file_hash,
    hash_algorithm = algo,
    metadata_status = "needs_review",
    copyright_status = "user_provided_or_open_access_required",
    stringsAsFactors = FALSE
  )
  draft <- data.frame(
    doc_id = doc_ids,
    title = tools::file_path_sans_ext(basename(files)),
    authors = "",
    year = "",
    source_type = "peer_reviewed_paper",
    journal_or_publisher = "",
    doi = "",
    url = "",
    access_date = format(Sys.Date(), "%Y-%m-%d"),
    language = "en",
    topic_tags = "needs_tagging",
    soil_indicators = "",
    geography = "",
    method_tags = "",
    quality_level = "weak",
    license_or_access_note = "Local file supplied by user or open-access source; verify usage rights before indexing or quoting.",
    notes = "Draft metadata generated from local library inventory; verify title/authors/year/DOI before using as evidence.",
    local_relative_path = rel,
    file_hash = file_hash,
    hash_algorithm = algo,
    stringsAsFactors = FALSE
  )
}

agent_write_csv(inventory, inventory_out)
agent_write_csv(draft, draft_out)

result <- list(
  library_dir = agent_norm_path(library_dir),
  n_files = nrow(inventory),
  inventory_csv = agent_norm_path(inventory_out),
  draft_metadata_csv = agent_norm_path(draft_out),
  hash_algorithm = algo,
  note = "Raw files remain local and ignored by Git. Verify draft metadata before using documents as evidence."
)
agent_write_json(result, "agent/responses/rag_inventory_result.json")
cat("[INFO] Local library files: ", nrow(inventory), "\n", sep = "")
cat("[INFO] Hash algorithm: ", algo, "\n", sep = "")
cat("[INFO] Inventory CSV: ", agent_norm_path(inventory_out), "\n", sep = "")
cat("[INFO] Draft metadata CSV: ", agent_norm_path(draft_out), "\n", sep = "")
