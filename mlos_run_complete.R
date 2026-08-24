# mLOS - Complete Analysis Pipeline (end-to-end demonstration run)
# =======================================================================

source("mlos_common.R")
source("mlos_setup.R")
source("mlos_data.R")
source("mlos_km.R")
source("mlos_cox.R")
source("mlos_aj.R")
source("mlos_results.R")
source("mlos_excel_export.R")

# Rscript passes --file=<script>; when this script is instead source()d into
# a live session (e.g. the Colab notebook), the session's own command line is
# not addressed to this script and must be ignored -- a Jupyter/IRkernel
# launch leaves its connection file in commandArgs(), which the strict
# argument check below would otherwise reject. quit() is also only
# appropriate under Rscript; in a live session it would kill the session.
run_via_rscript <- any(grepl("^--file=", commandArgs()))

# Check required packages once at startup
for (pkg in c("survival", "yaml")) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    cat("\n*** ERROR: required package '", pkg, "' is not installed ***\n", sep = "")
    cat("Install with: install.packages('", pkg, "')\n", sep = "")
    if (run_via_rscript) quit(save = "no", status = 1)
    stop("required package '", pkg, "' is not installed")
  }
}

# Configurable file paths: command-line args > environment variables > defaults
# Usage: Rscript mlos_run_complete.R [--settings FILE] [--data FILE] [--results DIR]
cli_args <- if (run_via_rscript) commandArgs(trailingOnly = TRUE) else character(0)
cli <- list()
i <- 1
while (i <= length(cli_args)) {
  if (cli_args[i] %in% c("--settings", "--data", "--results") && i < length(cli_args)) {
    cli[[sub("^--", "", cli_args[i])]] <- cli_args[i + 1]
    i <- i + 2
  } else {
    # Stop rather than skip: a typo like --setting would otherwise silently
    # run the analysis on the default files.
    stop("Unrecognized argument (or option missing its value): ", cli_args[i],
         "\nUsage: Rscript mlos_run_complete.R [--settings FILE] [--data FILE] [--results DIR]")
  }
}

settings_filename <- if (!is.null(cli$settings)) cli$settings else
                     Sys.getenv("MLOS_SETTINGS_FILE", unset = file.path("data", "OC2_settings.yaml"))

data_filename <- if (!is.null(cli$data)) cli$data else
                 Sys.getenv("MLOS_DATA_FILE", unset = file.path("data", "OC2_data.csv"))

output_dir <- if (!is.null(cli$results)) cli$results else
              Sys.getenv("MLOS_OUTPUT_DIR", unset = "results")
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
}
output_path <- function(filename) file.path(output_dir, filename)
log_filename <- Sys.getenv("MLOS_LOG_FILE", unset = "analysis_log.txt")
log_path <- output_path(log_filename)
excel_filename <- Sys.getenv("MLOS_EXCEL_FILE", unset = "analysis_results.xlsx")
excel_path <- output_path(excel_filename)
json_filename <- Sys.getenv("MLOS_JSON_FILE", unset = "results.json")
json_path <- output_path(json_filename)
stats_filename <- "data_preparation_stats.csv"
stats_path <- output_path(stats_filename)

# Move the previous run's outputs aside before anything is written, so this
# run's directory holds this run alone. Must happen before the log connection
# is opened: opening it "wt" truncates the file, which would destroy the
# previous run's log before it could be archived. The result is reported into
# the log below, once there is a log to report it into.
archived <- archive_previous_outputs(output_dir, excel_filename, log_filename,
                                     json_filename, stats_filename)

# Tee all console output/messages to a log file while keeping console output visible
log_con <- file(log_path, open = "wt")
output_sink_before <- sink.number()
message_sink_before <- sink.number(type = "message")
sink(log_con, split = TRUE)
sink(log_con, type = "message")
tryCatch({

cat("=======================================================================\n")
cat("MLOS Length of Stay Tool ", MLOS_VERSION, " - Demonstration\n", sep = "")
cat("=======================================================================\n")
cat("Log file: ", log_path, "\n", sep = "")
if (!is.null(archived)) {
  cat("Previous outputs archived to: ", archived$dir, " (", archived$n, " files)\n", sep = "")
}

# Start the emission register clean so the results manifest describes this
# run's outputs, not any left in the directory by an earlier one.
reset_emitted_outputs()

cat("\n>>> Reading settings and defining periods...\n")
settings <- read_settings(settings_filename)
references <- extract_references(settings, define_periods(settings))
options(mlos.png.pointsize_factor = references$png_pointsize_factor)
options(mlos.png.line_width_factor = references$png_line_width_factor)

cat("\n=== Period Definitions ===\n")
print(references$periods)

cat("\n=== Reference Values ===\n")
print(unlist(references))

cat("\n\n>>> Reading CSV and preparing data...\n")
data <- read_and_prepare_data(data_filename, references)
references <- detect_optional_columns(data, references)
display_data_summary(data)

cat("\n\n>>> Breaking data down by period...\n")
period_data <- break_down_by_period(data, references)
display_period_breakdown_summary(period_data)

cat("\n\n>>> Kaplan-Meier analysis on unified period...\n")

km_results <- km_unified_period(period_data, references)

# The headline figures, as a brief report. Their confidence bounds, the study
# window and the capped fraction are on the General sheet and in results.json;
# an NA here prints as NA, which reads as "not reached" without a branch for it.
cat("\n=== KM summary ===\n")
cat("Observations:", km_results$n_total, " events:", km_results$n_events,
    " censored:", km_results$n_censored, " capped:", km_results$n_capped, "\n")
cat("Median LOS:", round(km_results$median_los, 1),
    " P90:", round(km_results$percentile_90, 1),
    " restricted mean:", round(km_results$restricted_mean, 1),
    " days (cap:", km_results$restricted_stay_cap, "days)\n")

cat("\n\n>>> Cox regression analysis...\n")

cox_results <- cox_regression_analysis(period_data, references)

cat("\n\n>>> Stratified Kaplan-Meier analysis...\n")

stratified_results <- stratified_km_analysis(period_data, references)

# AJ competing-risk CIF
cat("\n\n>>> AJ competing-risk CIF...\n")
aj_results <- aj_competing_risk_analysis(period_data, max_time = km_results$max_time,
                                         rmean_cap = references$restricted_stay_cap)

# AJ conditional outcomes within each stratifier (period, intake type, animal
# group; see the `stratifiers` registry in mlos_common.R). A stratifier whose
# column is absent from the data skips itself, so a dataset without intake_type
# or animal_group produces exactly the by-period output it did before.
#
# max_time is left NULL so each stratum's daily grid ends at that stratum's own
# largest fitted time, rather than being held flat to the unified horizon. This
# costs nothing: a CIF is flat past its last event, so no CondRem value and no
# restricted mean depends on where beyond that the grid stops.
aj_strat_results <- list()
for (stratifier in stratifiers) {
  cat("\n\n>>> AJ conditional outcomes by ", tolower(stratifier$label), "...\n", sep = "")
  aj_strat_results[[stratifier$id]] <- aj_by_stratifier(period_data, references, stratifier)
}

# ---- Results ----------------------------------------------------------
# Everything is computed by this point. The bundle is assembled before anything
# is drawn or written so that the rendering below can take its values from one
# place, rather than each output deriving its own summaries a second time.

cat("\n\n>>> Assembling results bundle...\n")
results_bundle <- build_results_bundle(
  cox_results = cox_results,
  km_results = km_results,
  aj_results = aj_results,
  aj_strat_results = aj_strat_results,
  period_data = period_data,
  stratified_results = stratified_results,
  references = references,
  data_filename = data_filename,
  settings_filename = settings_filename,
  output_dir = output_dir,
  log_path = log_path
)

# ---- Rendering --------------------------------------------------------

cat("\n>>> Generating Kaplan-Meier plot...\n")
plot_km_curve(km_results, references, save_file = output_path("km_survival_unified.png"))

cat("\n>>> Generating unified KM companion plots...\n")
plot_unified_km_companions(km_results, references,
                           base_filename = output_path("km_survival_unified.png"),
                           measures = results_bundle$strata$all)

cat("\n>>> Generating stratified KM plots...\n")
plot_stratified_km(stratified_results, references,
                   save_prefix = output_path("km_survival"),
                   measures_by_stratifier = results_bundle$strata)

if (isTRUE(aj_results$has_analysis)) {
  cat("\n>>> Generating AJ CIF plot...\n")
  plot_aj_cif(aj_results, references, save_file = output_path("aj_cif_unified.png"))

  cat("\n>>> Generating stacked CIF plot...\n")
  plot_aj_cif_unified_stack(aj_results, references, save_file = output_path("aj_cif_unified_stack.png"))

  cat("\n>>> Generating conditional outcome distribution plot...\n")
  plot_aj_conditional_unified_stack(aj_results, references,
                                    save_file = output_path("aj_conditional_unified_stack.png"))

  cat("\n>>> Generating unified conditional outcome line plot...\n")
  plot_aj_conditional_unified(aj_results, references, save_file = output_path("aj_conditional_unified.png"))
}

for (stratifier in stratifiers) {
  res <- aj_strat_results[[stratifier$id]]
  if (!isTRUE(res$has_analysis)) next
  # A single-level stratifier's curves are the unified curves redrawn, so no
  # figure (and no companion CSV) is emitted for it. Its numbers still reach
  # the results bundle and the workbook.
  if (!isTRUE(.strata_info(stratifier, references)$has)) {
    cat("Only one ", tolower(stratifier$label), " level - computed, not plotted\n", sep = "")
    next
  }

  cat("\n>>> Generating AJ CIF line plots by ", stratifier$label, "...\n", sep = "")
  plot_aj_cif_by_stratum_lines(
    res,
    references = references,
    save_prefix = output_path(paste0("aj_cif", stratifier$suffix))
  )

  cat("\n>>> Generating AJ conditional line plots by ", stratifier$label, "...\n", sep = "")
  plot_aj_conditional_by_stratum_lines(
    res,
    references = references,
    save_prefix = output_path(paste0("aj_conditional", stratifier$suffix))
  )
}

# The manifest records what rendering just wrote, so it is the one part of the
# bundle that cannot be filled in before the drawing happens.
results_bundle <- attach_output_manifest(results_bundle)

cat("\n>>> Writing results JSON...\n")
write_results_json(results_bundle, json_path)

cat("\n>>> Writing data preparation stats CSV...\n")
write_screening_ledger_csv(results_bundle, stats_path)

cat("\n>>> Exporting consolidated Excel workbook...\n")
write_results_excel(excel_path, results_bundle)

cat("\n=======================================================================\n")
cat("ANALYSIS COMPLETE\n")
cat("=======================================================================\n")

}, error = function(e) {
  # R prints an unhandled error at signal time, before unwinding reaches the
  # finally block -- so the sinks must come down HERE, before re-signalling,
  # or the error text vanishes into the log instead of reaching the console.
  # Only the sinks: closing log_con here too would leave finally touching a
  # destroyed connection, which masks the real error with "invalid connection".
  while (sink.number(type = "message") > message_sink_before) sink(type = "message")
  while (sink.number() > output_sink_before) sink()
  stop(e)
}, finally = {
  # After normal completion or the handler above. The sink loops are no-ops
  # when the handler already ran; the connection is closed exactly once here.
  while (sink.number(type = "message") > message_sink_before) sink(type = "message")
  while (sink.number() > output_sink_before) sink()
  flush(log_con)
  close(log_con)
})
