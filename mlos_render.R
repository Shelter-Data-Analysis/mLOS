# mLOS - Render a saved results bundle
# =======================================================================
#
# Rebuild the Excel workbook from a results.json written by an earlier run,
# without repeating the analysis:
#
#   Rscript mlos_render.R [JSON_FILE] [EXCEL_FILE]
#
# Defaults: results/results.json -> results/analysis_results.xlsx.
#
# Two things this is for. It makes changes to the workbook's layout a
# one-second edit-and-look loop instead of a full re-run, and it is the
# standing proof that results.json really is sufficient to reproduce the
# workbook: if a number ever stops travelling in the JSON, rendering from the
# file stops matching the run that produced it, and the test suite says so.

source("mlos_common.R")
source("mlos_results.R")
source("mlos_excel_export.R")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 2) {
  stop("Usage: Rscript mlos_render.R [JSON_FILE] [EXCEL_FILE]")
}
json_file  <- if (length(args) >= 1) args[1] else file.path("results", "results.json")
excel_file <- if (length(args) >= 2) args[2] else file.path("results", "analysis_results.xlsx")

if (!file.exists(json_file)) {
  stop("No results JSON at '", json_file, "'. Run mlos_run_complete.R first, ",
       "or pass the path as the first argument.")
}

cat("Reading results bundle: ", json_file, "\n", sep = "")
bundle <- read_results_json(json_file)

if (!identical(bundle$schema_version, MLOS_RESULTS_SCHEMA_VERSION)) {
  cat("*** WARNING: this file was written by schema version ",
      format(bundle$schema_version), "; this code expects ",
      format(MLOS_RESULTS_SCHEMA_VERSION), " ***\n", sep = "")
}
cat("Run generated at: ", bundle$run$generated_at, "\n", sep = "")
# Absent from a bundle written before the tool recorded its version, which
# still renders: the field says which version computed the numbers, and an old
# archived run is honest about not knowing.
if (!is.null(bundle$run$mlos_version)) {
  cat("mLOS version:     ", bundle$run$mlos_version, "\n", sep = "")
}
cat("Data file:        ", bundle$run$data_file, "\n", sep = "")

write_results_excel(excel_file, bundle)
