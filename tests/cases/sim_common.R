# Shared finalize-and-write helper for the sim_* data generators.
# =======================================================================
# Every tests/cases/sim_*/generator.R builds a data.frame with columns
# intake_date, outcome_date, outcome_type (and optionally a stratifier
# column), then snapshots it at the export date and writes data.csv next
# to itself. That tail was copied verbatim into each generator; it lives
# here so there is a single copy to maintain.
#
# finalize_and_write(data, export_date, id_prefix, out_dir)
#   - blanks the outcome of any stay still open on export_date, so it
#     lands in data.csv as a right-censored record (empty outcome_type
#     and outcome_date);
#   - formats the date columns as plain YYYY-MM-DD character text (blank
#     for the censored outcome_date);
#   - assigns a stable animal_id "<id_prefix>_NNNN" in row order;
#   - writes data.csv into out_dir (no quoting, no row names) and prints
#     a one-line summary.
# Called for its side effects; returns nothing.
#
# Each generator resolves its own directory once (the commandArgs trick
# that reads the Rscript --file= path) both to source this helper and to
# pass as out_dir.

finalize_and_write <- function(data, export_date, id_prefix, out_dir) {
  # Snapshot at the export date: a stay still open then has no outcome yet.
  in_care <- data$outcome_date >= export_date
  data$outcome_type[in_care] <- ""
  data$outcome_date <- ifelse(in_care, "", format(data$outcome_date))
  data$intake_date  <- format(data$intake_date)
  data$animal_id    <- sprintf(paste0(id_prefix, "_%04d"), seq_len(nrow(data)))

  out_file <- file.path(out_dir, "data.csv")
  write.csv(data, out_file, row.names = FALSE, quote = FALSE)
  cat("Wrote", nrow(data), "rows (", sum(in_care), "still in care at export ) to",
      out_file, "\n")
}
