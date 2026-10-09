# Proportional-hazards tests for the Cox fits of a run, outside the run: the
# scaled Schoenfeld residual test of survival::cox.zph on the same pooled fit
# mLOS reports (math methods §6.1) and on each per-predictor stratified fit
# (§6.8). cox_zph_table in mlos_cox.R builds the table.
#
# Usage (from the mLOS working copy):
#   Rscript tools/cox_zph.R [--settings FILE] [--data FILE] [--results DIR]
#
# The time transform is cox.zph's default, the Kaplan-Meier transform. The
# `model` column names the fit: "pooled", or "stratified:<stratifier>" for the
# variant that estimates that stratifier with the others in strata(). For each
# fit the table gives three kinds of test, named in its `test` column: one per
# coefficient (terms = FALSE), so each non-reference level of a factor gets its
# own row; one per factor (terms = TRUE); and the global test. A stratified
# variant has one factor, so its factor and global tests coincide. A
# per-coefficient test depends on the choice of reference level, since a dummy
# for a different reference is a different contrast; the per-factor and global
# tests do not. A rejection says that the hazard ratio is an average over
# tenure rather than a constant multiplier (math methods §9). The pooled test
# of a factor assumes proportional hazards for the other predictors; the
# stratified variant's test of the same factor does not, but compares levels
# within baseline strata only, so sparse strata cost it power.
# cox_zph_inputs.csv records the mLOS version and input hashes, as
# tools/histlos_by_period.R does for its own output.

suppressMessages({
  source("mlos_common.R"); source("mlos_setup.R")
  source("mlos_data.R");   source("mlos_km.R"); source("mlos_cox.R")
})

args <- commandArgs(trailingOnly = TRUE)
opt <- list(settings = file.path("data", "OC2_settings.yaml"),
            data     = file.path("data", "OC2_data.csv"),
            results  = file.path("results", "cox_zph"))
for (i in seq(1, length(args), by = 2)) opt[[sub("^--", "", args[i])]] <- args[i + 1]
dir.create(opt$results, recursive = TRUE, showWarnings = FALSE)
out <- function(f) file.path(opt$results, f)

settings <- read_settings(opt$settings)
settings$parametric_regression <- FALSE    # the test needs the Cox fit only
references <- extract_references(settings, define_periods(settings))
invisible(capture.output({
  data        <- read_and_prepare_data(opt$data, references)
  references  <- detect_optional_columns(data, references)
  period_data <- break_down_by_period(data, references)
  cox_results <- cox_regression_analysis(period_data, references)
}))
if (!isTRUE(cox_results$has_analysis)) stop("No pooled Cox model was fitted for this data and settings.")

tab <- cox_zph_table(cox_results)
.write_plot_csv(tab, out("cox_zph.csv"), "Proportional-hazards test")
cat("Events:", cox_results$cox_model$nevent, "\n")
print(transform(tab, chisq = round(chisq, 2), p = signif(p, 3)), row.names = FALSE)

.write_plot_csv(data.frame(mlos_version    = MLOS_VERSION,
                           data_file       = opt$data,
                           data_sha256     = mlos_file_sha256(opt$data),
                           settings_file   = opt$settings,
                           settings_sha256 = mlos_file_sha256(opt$settings)),
                out("cox_zph_inputs.csv"), "Inputs")
