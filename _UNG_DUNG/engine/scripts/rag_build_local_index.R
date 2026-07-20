# ============================================================
# Build local-only text chunks from user-provided/open-access files.
# Outputs are ignored by Git. Does not download anything.
# ============================================================

source("_UNG_DUNG/engine/scripts/agent_utils.R")

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

read_text_file <- function(path) {
  ext <- tolower(tools::file_ext(path))
  if (ext %in% c("txt", "md", "html", "htm")) {
    return(paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n"))
  }
  if (ext == "pdf") {
    if (!requireNamespace("pdftools", quietly = TRUE)) {
      stop("PDF extraction requires R package 'pdftools'. Install it with install.packages('pdftools') if your license permits local text indexing.")
    }
    return(paste(pdftools::pdf_text(path), collapse = "\n\n"))
  }
  stop(paste0("Unsupported file type for text extraction: ", ext))
}

chunk_text <- function(txt, chunk_chars = 2500L, overlap_chars = 250L) {
  txt <- gsub("[\r\t]+", " ", txt)
  txt <- gsub("\n{3,}", "\n\n", txt)
  n <- nchar(txt, type = "chars")
  if (n == 0) return(character(0))
  starts <- seq(1L, n, by = max(1L, chunk_chars - overlap_chars))
  chunks <- character(length(starts))
  for (i in seq_along(starts)) {
    s <- starts[[i]]
    e <- min(n, s + chunk_chars - 1L)
    chunks[[i]] <- substr(txt, s, e)
  }
  chunks[nzchar(trimws(chunks))]
}

args <- parse_args(commandArgs(trailingOnly = TRUE))
inventory_csv <- args$inventory %||% "knowledge/metadata/local_library_inventory.csv"
out_dir <- args$output %||% "knowledge/index/local_chunks"
chunk_chars <- as.integer(args$chunk_chars %||% 2500L)
overlap_chars <- as.integer(args$overlap_chars %||% 250L)

if (!file.exists(inventory_csv)) stop(paste0("Inventory not found: ", inventory_csv, ". Run .\\run_rag_inventory.ps1 first."))
agent_require_package("readr")
inv <- as.data.frame(readr::read_csv(inventory_csv, show_col_types = FALSE, progress = FALSE))
agent_ensure_dir(out_dir)
chunks_file <- file.path(out_dir, "chunks.jsonl")
manifest_file <- "knowledge/index/local_chunks_manifest.json"

con <- file(chunks_file, open = "w", encoding = "UTF-8")
on.exit(close(con), add = TRUE)

errors <- character(0)
written <- 0L
processed <- 0L

for (i in seq_len(nrow(inv))) {
  path <- file.path("knowledge/library", inv$relative_path[[i]])
  if (!file.exists(path)) {
    errors <- c(errors, paste0("Missing local file: ", path))
    next
  }
  txt <- tryCatch(read_text_file(path), error = function(e) e)
  if (inherits(txt, "error")) {
    errors <- c(errors, paste0(inv$doc_id[[i]], ": ", txt$message))
    next
  }
  chunks <- chunk_text(txt, chunk_chars, overlap_chars)
  processed <- processed + 1L
  if (length(chunks) == 0) next
  for (j in seq_along(chunks)) {
    rec <- list(
      chunk_id = paste(inv$doc_id[[i]], sprintf("%04d", j), sep = "_"),
      doc_id = inv$doc_id[[i]],
      local_relative_path = inv$relative_path[[i]],
      chunk_index = j,
      text = chunks[[j]]
    )
    writeLines(agent_to_json(rec, pretty = FALSE), con = con, useBytes = TRUE)
    written <- written + 1L
  }
}

manifest <- list(
  status = if (length(errors) == 0) "completed" else "completed_with_warnings",
  created_at = as.character(Sys.time()),
  inventory_csv = agent_norm_path(inventory_csv),
  chunks_file = agent_norm_path(chunks_file),
  n_documents_in_inventory = nrow(inv),
  n_documents_processed = processed,
  n_chunks = written,
  chunk_chars = chunk_chars,
  overlap_chars = overlap_chars,
  errors = errors,
  copyright_note = "Local chunks may contain copyrighted text supplied by the user. They are ignored by Git and must not be shared or quoted beyond allowed limits."
)
agent_write_json(manifest, manifest_file)
cat("[INFO] Local chunks: ", written, "\n", sep = "")
cat("[INFO] Manifest: ", agent_norm_path(manifest_file), "\n", sep = "")
if (length(errors) > 0) cat("[WARN] ", paste(errors, collapse = "\n[WARN] "), "\n", sep = "")