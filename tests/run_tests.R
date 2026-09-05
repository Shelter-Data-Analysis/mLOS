# mLOS - Validation Test Suite
# =======================================================================
# Runs each fixture under tests/cases/<name>/ (data.csv + settings.yaml +
# expected.R) through the production analysis functions and checks the
# results against known, hand-derived expected values.
#
# This script only reads the production mlos_*.R files via source(), the
# same way mlos_run_complete.R does. It does not modify any production
# code, data, or settings.
#
# What a case tests is driven entirely by which expected_* objects its
# expected.R defines -- there is no separate "which parts to test" flag.
# Defining expected_km runs and checks the unified KM analysis; adding
# expected_stratified_km, expected_census, expected_cox, expected_aj,
# expected_aj_period, expected_period_stats, expected_preparation, and/or
# expected_stratum_stats turns on the corresponding checks too. A case can define any subset. See the
# flatten_*() functions below for the exact field names each analysis
# exposes for comparison.
#
# After the fixtures, a settings/data-validation section (expect_error)
# asserts the exact error messages of the settings parsers and the
# row-level data checks -- these paths cannot be reached through fixtures
# because a fixture that trips them would abort its own run.
#
# By default this writes no files. Pass --generate-outputs to additionally
# run every analysis (KM, Cox, stratified KM, AJ, AJ by period) against every
# fixture and render their plots and CSVs to tests/results/<case_name>/, for
# visual inspection -- regardless of which expected_* objects a case defines.
# This deliberately runs analyses a fixture wasn't built to test: small,
# idiomatic edge-case data (single period, one outcome type, no groups, ...)
# is exactly where a production analysis is likely to have an unhandled
# degenerate case, and real shelter data can hit the same edge cases. Every
# analysis is expected to either produce a result or report has_analysis =
# FALSE for "not applicable" -- never crash -- so a crash surfaced here is a
# production bug worth fixing (see mlos_cox.R's no-predictor skip), not a
# reason to avoid calling that analysis on that fixture.
#
# --generate-outputs additionally (a) writes the consolidated Excel
# workbook per fixture and checks a few cells read back from it against
# the in-memory results (openxlsx required; skipped with a note if not
# installed), and (b) compares every generated CSV byte-for-byte against
# the committed golden copy under tests/golden/<case_name>/ and checks
# that every PNG listed in that case's png_manifest.txt was produced
# (PNG bytes can vary across R/graphics versions, so only their existence
# is checked). Pass --update-golden (implies --generate-outputs) after an
# INTENDED output change to regenerate the golden files; review the git
# diff of tests/golden/ before committing it. A full regeneration also
# records the package versions it ran under in tests/golden/environment.txt,
# which every --generate-outputs run prints beside the live ones.
#
# --prefix <value> restricts the run to the fixture cases whose directory
# name starts with <value> (e.g. --prefix sim runs only the sim_* simulation
# cases). A prefixed run is fixtures-only: the settings/data-validation and
# entry-point sections belong to the full suite and are skipped. Omitting
# --prefix (or giving it an empty value) runs everything. --prefix combines
# with --generate-outputs/--update-golden, so the goldens of a single case
# can be regenerated without touching the others.
#
# Tolerances: expected values are compared with an absolute tolerance of
# 1e-6 by default (exact, hand-derived fixtures). A case whose expected
# values are statistical -- e.g. the sim_* fixtures, checked against the
# parameters that generated their data rather than hand-derived exact
# values -- can widen this by defining in its expected.R:
#   tolerance <- 0.05                      # case-wide default
#   expected_km <- list(
#     median_los = 8,                      # uses the case-wide tolerance
#     restricted_mean = c(11.2, 0.5)       # c(value, tol) per-field override
#   )
#
# Usage (from the project root):
#   Rscript tests/run_tests.R
#   Rscript tests/run_tests.R --generate-outputs
#   Rscript tests/run_tests.R --update-golden
#   Rscript tests/run_tests.R --prefix sim
#   Rscript tests/run_tests.R --only km
#   Rscript tests/run_tests.R --prefix sim_weibull_truncation --update-golden

cli_args <- commandArgs(trailingOnly = TRUE)
update_golden <- "--update-golden" %in% cli_args
generate_outputs <- "--generate-outputs" %in% cli_args || update_golden

case_prefix <- ""
prefix_idx <- which(cli_args == "--prefix")
if (length(prefix_idx) > 0) {
  if (prefix_idx[1] == length(cli_args)) {
    stop("--prefix requires a value (e.g. --prefix sim)")
  }
  case_prefix <- cli_args[prefix_idx[1] + 1]
}

# --only <value> restricts reporting to the checks whose label contains
# <value> ("km", "cox_stratified", "in_care"). Unlike --prefix it does not
# make the run shorter: the analyses are shared between checks, so there is
# nothing to skip without also skipping checks that were asked for. What it
# does is cut the output down to the section being worked on.
only_filter <- ""
only_idx <- which(cli_args == "--only")
if (length(only_idx) > 0) {
  if (only_idx[1] == length(cli_args)) {
    stop("--only requires a value (e.g. --only km)")
  }
  only_filter <- cli_args[only_idx[1] + 1]
}
.only_matched <- FALSE

suite_dir <- normalizePath(dirname(sub("^--file=", "", grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))))
if (length(suite_dir) == 0 || is.na(suite_dir) || suite_dir == "") {
  # Fallback for interactive use: assume the working directory is the project root.
  suite_dir <- normalizePath(file.path(getwd(), "tests"))
}
project_root <- normalizePath(file.path(suite_dir, ".."))

source(file.path(project_root, "mlos_common.R"))
source(file.path(project_root, "mlos_setup.R"))
source(file.path(project_root, "mlos_data.R"))
source(file.path(project_root, "mlos_km.R"))
source(file.path(project_root, "mlos_cox.R"))
source(file.path(project_root, "mlos_aj.R"))
source(file.path(project_root, "mlos_results.R"))
source(file.path(project_root, "mlos_excel_export.R"))

# -----------------------------------------------------------------------
# Minimal assertion helpers
# -----------------------------------------------------------------------

.n_pass <- 0L
.n_fail <- 0L
.n_error <- 0L

# Whether a check reports, under --only. Matching on the label rather than on
# a function name is what the shape of this file allows: the fixture checks
# are inline code inside one loop, not named functions, and the label prefix
# ("<case>: km", "<case>: cox_stratified_group") is already the name each
# section goes by in the output.
.selected <- function(label) {
  if (!nzchar(only_filter)) return(TRUE)
  if (grepl(only_filter, label, fixed = TRUE)) {
    .only_matched <<- TRUE
    return(TRUE)
  }
  FALSE
}

# A section that stopped, recorded as a failure rather than ending the run.
# Without this an error anywhere in a fixture aborts the script: the cases
# after it never run, and the summary that would say what did pass never
# prints. The error is a result like any other, so it is counted and the run
# carries on to the next case.
errored <- function(label, message) {
  .n_fail <<- .n_fail + 1L
  .n_error <<- .n_error + 1L
  cat(sprintf("  [ERROR] %s: %s\n", label, message))
}

# Evaluate `expr` with its errors contained. `expr` is a promise, forced
# inside the handler, so the caller writes an ordinary call.
run_guarded <- function(label, expr) {
  msg <- tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))
  if (!is.na(msg)) errored(label, msg)
  invisible(NULL)
}

expect_equal <- function(label, actual, expected, tol = 1e-6) {
  if (!.selected(label)) return(invisible(NULL))
  actual   <- if (length(actual) == 0)   NA_real_ else as.numeric(actual)
  expected <- if (length(expected) == 0) NA_real_ else as.numeric(expected)

  ok <- if (is.na(expected)) {
    is.na(actual)
  } else {
    !is.na(actual) && abs(actual - expected) <= tol
  }

  if (ok) {
    .n_pass <<- .n_pass + 1L
    cat(sprintf("  [PASS] %s = %s\n", label, format(actual)))
  } else {
    .n_fail <<- .n_fail + 1L
    cat(sprintf("  [FAIL] %s: expected %s, got %s\n", label, format(expected), format(actual)))
  }
}

# Assert that evaluating `expr` stops with an error whose message contains
# `pattern` (fixed string, not regex). Used by the settings/data-validation
# section: these stop() paths abort a run, so no fixture can reach them.
expect_error <- function(label, expr, pattern) {
  if (!.selected(label)) return(invisible(NULL))
  msg <- tryCatch({ force(expr); NA_character_ }, error = function(e) conditionMessage(e))
  ok <- !is.na(msg) && grepl(pattern, msg, fixed = TRUE)
  if (ok) {
    .n_pass <<- .n_pass + 1L
    cat(sprintf("  [PASS] %s\n", label))
  } else {
    .n_fail <<- .n_fail + 1L
    if (is.na(msg)) {
      cat(sprintf("  [FAIL] %s: expected an error containing %s, but no error was raised\n",
                  label, dQuote(pattern)))
    } else {
      cat(sprintf("  [FAIL] %s: error message %s does not contain %s\n",
                  label, dQuote(msg), dQuote(pattern)))
    }
  }
}

# Compare every named field in `expected` against `actual_flat[[field]]`.
# `actual_flat` is either a results list whose fields are already scalars
# (e.g. km_unified_period()'s return value) or the output of one of the
# flatten_*() helpers below. `tol` is the case-wide tolerance (the
# `tolerance` scalar from the case's expected.R, defaulting to the exact
# 1e-6); a field whose expected value is a length-2 vector c(value, tol)
# overrides it for that field alone.
check_fields <- function(prefix, actual_flat, expected, tol = 1e-6) {
  for (field in names(expected)) {
    exp_val   <- expected[[field]]
    field_tol <- tol
    if (length(exp_val) == 2) {
      field_tol <- as.numeric(exp_val[[2]])
      exp_val   <- exp_val[[1]]
    }
    expect_equal(
      label    = paste0(prefix, ": ", field),
      actual   = actual_flat[[field]],
      expected = exp_val,
      tol      = field_tol
    )
  }
}

# -----------------------------------------------------------------------
# Flatteners: reduce each analysis's result object to named scalars so
# expected.R fixtures can reference them the same way expected_km does.
# -----------------------------------------------------------------------

# cox_regression_analysis() -> n, n_events, concordance, HR_<rowname> per
# coefficient row (rowname matches cox_results$hr_table$variable, e.g.
# "animal_groupBIG", the same names printed under "Hazard Ratios"). When there
# is no qualifying predictor (single period, no intake_type/animal_group),
# cox_regression_analysis() skips the fit and returns has_analysis = FALSE.
#
# Reads the bundle node (.cox_bundle), not the fit, so a fixture pins the value
# that reaches results.json and the workbook rather than one derived alongside
# it.
flatten_cox <- function(cox_results) {
  cox <- .cox_bundle(cox_results)
  flat <- list(has_analysis = as.numeric(isTRUE(cox$has_analysis)))
  if (!isTRUE(cox$has_analysis)) return(flat)

  flat$n           <- cox$n
  flat$n_events    <- cox$n_events
  flat$concordance <- cox$concordance

  hr <- cox$hr_table
  if (!is.null(hr) && nrow(hr) > 0) {
    for (i in seq_len(nrow(hr))) {
      flat[[paste0("HR_", hr$variable[i])]] <- hr$hr[i]
    }
  }
  flat
}

# .weibull_regression_analysis() -> has_analysis, n, n_events, shape,
# TR_<Variable> (LOS ratio, exp(beta)) and HRw_<Variable> (implied hazard
# ratio, LOS_ratio^(-k)) per coefficient row; Variable names match the Cox
# hr_table's. Lives under cox_results$weibull when parametric_regression is
# WEIBULL (NULL otherwise, which flattens to has_analysis = 0). The unified
# companion (intercept + period only) adds shape_crude,
# crude_same_as_main, and TR_crude_<Variable> per period row.
# Takes the bundle node, as flatten_cox does.
flatten_weibull <- function(weibull_results) {
  weibull_results <- .weibull_bundle(weibull_results)
  flat <- list(has_analysis = as.numeric(isTRUE(weibull_results$has_analysis)))
  if (!isTRUE(weibull_results$has_analysis)) return(flat)

  flat$n        <- weibull_results$n
  flat$n_events <- weibull_results$n_events
  flat$shape    <- weibull_results$shape
  lt <- weibull_results$los_table
  for (i in seq_len(nrow(lt))) {
    flat[[paste0("TR_", lt$variable[i])]] <- lt$los_ratio[i]
  }
  ht <- weibull_results$hr_table
  for (i in seq_len(nrow(ht))) {
    flat[[paste0("HRw_", ht$variable[i])]] <- ht$hr[i]
  }
  uni <- weibull_results$crude
  if (isTRUE(uni$has_analysis)) {
    flat$shape_crude        <- uni$shape
    flat$crude_same_as_main <- as.numeric(isTRUE(uni$same_as_main))
    for (i in seq_len(nrow(uni$los_table))) {
      flat[[paste0("TR_crude_", uni$los_table$variable[i])]] <- uni$los_table$los_ratio[i]
    }
  }
  flat
}

# One per-predictor Weibull shape variant (built inside
# .weibull_regression_analysis alongside the pooled fit and
# reachable at cox_results$weibull$shape_variants$<id>) -> has_analysis, n,
# n_events, shape (baseline k at the reference combination), SR_<Variable>
# (LOS ratio, this predictor's own rows of los_table) and SHAPE_<Variable>
# (shape ratio, the OTHER predictors' rows of shape_table). Variable names
# match flatten_weibull's TR_/HRw_ convention. Reads the bundle node via
# .weibull_shape_variant_for (mlos_results.R), as flatten_weibull does for
# the pooled fit via .weibull_bundle.
flatten_stratifier_weibull <- function(cox_results, stratifier_id) {
  wres <- .weibull_shape_variant_for(cox_results, stratifier_id)
  flat <- list(has_analysis = as.numeric(isTRUE(wres$has_analysis)))
  if (!isTRUE(wres$has_analysis)) return(flat)

  flat$n        <- wres$n
  flat$n_events <- wres$n_events
  flat$shape    <- wres$shape_reference$k

  lt <- wres$los_table
  for (i in seq_len(nrow(lt))) {
    flat[[paste0("SR_", lt$variable[i])]] <- lt$los_ratio[i]
  }
  st <- wres$shape_table
  for (i in seq_len(nrow(st))) {
    flat[[paste0("SHAPE_", st$variable[i])]] <- st$shape_ratio[i]
  }
  # Which shape formula produced the numbers, and by how much the crossed one
  # beat the additive when it was used. Exposed because a fixture cannot
  # otherwise see the crossing decision at all, and because the statistic has an
  # invariant worth pinning: the additive model is nested in the crossed one, so
  # a negative value means one of the two fits missed its own optimum.
  cross <- wres$shape_crossing
  flat$crossed <- as.numeric(isTRUE(cross$crossed))
  if (isTRUE(cross$crossed) && !is.null(cross$lr)) {
    flat$crossing_lr_stat <- cross$lr$stat
    flat$crossing_lr_df   <- cross$lr$df
  }
  flat
}

# One per-stratifier stratified Cox variant (built by
# .cox_stratified_variants alongside the pooled fit and reachable at
# cox_results$stratified_variants$<id>) -> has_analysis, n, n_events,
# n_strata, n_strata_with_events, concordance, lr_stat, lr_df and HR_<Variable>
# for this stratifier's own rows, which are the only rows the fit produces (the
# other stratifiers are in strata() and have no coefficients). HR_ names match
# flatten_cox's, so a fixture can set the pooled and the stratified hazard ratio
# for the same level side by side and see the two move together. Reads the
# bundle node via .cox_stratified_variant_for (mlos_results.R), as flatten_cox
# does for the pooled fit via .cox_bundle.
#
# lr_p is deliberately absent: on a real dataset the p-values underflow to 0 and
# pin nothing. lr_stat carries the same information with room to move.
flatten_cox_stratified <- function(cox_results, stratifier_id) {
  cv <- .cox_stratified_variant_for(cox_results, stratifier_id)
  flat <- list(has_analysis = as.numeric(isTRUE(cv$has_analysis)))
  if (!isTRUE(cv$has_analysis)) return(flat)

  flat$n                    <- cv$n
  flat$n_events             <- cv$n_events
  flat$n_strata             <- cv$n_strata
  flat$n_strata_with_events <- cv$n_strata_with_events
  flat$concordance          <- cv$concordance

  lr <- cv$tests[cv$tests$test == "Likelihood ratio", ]
  flat$lr_stat <- lr$statistic[1]
  flat$lr_df   <- lr$df[1]

  hr <- cv$hr_table
  for (i in seq_len(nrow(hr))) {
    flat[[paste0("HR_", hr$variable[i])]] <- hr$hr[i]
  }
  flat
}

# One entry per (column, day) cell of a cif_df actually populated, named
# "<prefix><column>_day<day>". Shared by flatten_aj and flatten_aj_stratum.
flatten_cif_cells <- function(df, prefix = "") {
  flat <- list()
  value_cols <- setdiff(names(df), "days")
  for (col in value_cols) {
    for (i in seq_len(nrow(df))) {
      val <- df[[col]][i]
      if (!is.na(val)) {
        flat[[paste0(prefix, col, "_day", df$days[i])]] <- val
      }
    }
  }
  flat
}

# aj_competing_risk_analysis() -> has_analysis, max_time, n_outcome_states,
# and one entry per (column, day) cell of cif_df actually populated, named
# "<column>_day<day>", e.g. "cif_L_day10", "condrem_N_day5", "cif_Any_day3".
flatten_aj <- function(aj_results, references) {
  aj <- .aj_bundle(aj_results, references)
  flat <- list(has_analysis = as.numeric(isTRUE(aj$has_analysis)))
  if (!isTRUE(aj$has_analysis)) return(flat)

  flat$max_time         <- aj$max_time
  flat$n_outcome_states <- length(aj$outcome_states)
  c(flat, flatten_cif_cells(aj_results$cif_df))
}

# stratified_km_analysis() -> one entry per (stratifier, stratum) for n,
# events, median, rmean, and pos, named "<stratifier>.<stratum>.<field>", e.g.
# "group.BIG.median", "period.Period_1.rmean" (stratifier ids: period, intake,
# group; stratum names have the "column=" prefix stripped, matching plots/CSVs).
# rmean is the restricted mean at restricted_stay_cap, the same
# summary(fit, rmean = cap) statistic km_unified_period reports for the
# pooled fit. pos is the stratum's 1-based position in the KM output order --
# the order the plot legend and CSV columns use -- so a fixture can pin it
# (e.g. period strata must come out chronological, not alphabetical).
# `stratifiers` is the definition list the analysis ran with;
# pass stratified_results$stratifiers, as the production plot code does.
flatten_stratified_km <- function(stratified_results, stratifiers, restricted_stay_cap) {
  flat <- list()
  for (stratifier in stratifiers) {
    fit <- stratified_results[[stratifier$km_result_key]]
    if (is.null(fit)) next
    tbl <- summary(fit, rmean = restricted_stay_cap)$table
    if (is.null(dim(tbl))) next  # single stratum shouldn't occur (skipped upstream); guard anyway

    strata_names   <- .strip_stratum_prefix(rownames(tbl))
    stratifier_id  <- stratifier$id
    for (i in seq_along(strata_names)) {
      key_prefix <- paste0(stratifier_id, ".", strata_names[i])
      flat[[paste0(key_prefix, ".n")]]      <- tbl[i, "records"]
      flat[[paste0(key_prefix, ".events")]] <- tbl[i, "events"]
      flat[[paste0(key_prefix, ".median")]] <- tbl[i, "median"]
      flat[[paste0(key_prefix, ".rmean")]]  <- if ("rmean" %in% colnames(tbl)) tbl[i, "rmean"] else NA_real_
      flat[[paste0(key_prefix, ".pos")]]    <- i
    }
  }

  # Per-stratum observation gaps: n_strata_gaps plus one start/end pair per
  # gap, named "gap.<stratifier label>.<stratum>.start"/".end".
  gaps <- stratified_results$gaps
  flat$n_strata_gaps <- if (is.null(gaps)) 0 else nrow(gaps)
  if (!is.null(gaps) && nrow(gaps) > 0) {
    for (i in seq_len(nrow(gaps))) {
      key <- paste0("gap.", gaps$stratifier[i], ".", gaps$stratum[i])
      flat[[paste0(key, ".start")]] <- gaps$gap_start[i]
      flat[[paste0(key, ".end")]]   <- gaps$gap_end[i]
    }
  }
  flat
}

# The data-preparation register carried on the prepared data (see
# read_and_prepare_data) -> its scalar counts, plus one entry per value-map
# pair named "<setting>.<from>" giving the rows that pair transformed, and a
# "<setting>.n_pairs" count of the pairs recorded at all. The pair count is
# what lets an expected.R assert the "zeros included" contract: a configured
# map records EVERY pair, so a key matching nothing is present with a count of
# 0 rather than missing, which is the only signal a user gets that a key is
# spelled wrong.
flatten_preparation <- function(data) {
  prep <- attr(data, "preparation")
  flat <- list(
    rows_read       = prep$rows_read,
    rows_prepared   = prep$rows_prepared,
    recoded_in_care = prep$recoded_in_care
  )
  for (setting in c("mapped_intake_type", "mapped_animal_group")) {
    counts <- prep[[setting]]
    flat[[paste0(setting, ".n_pairs")]] <- nrow(counts)
    for (i in seq_len(nrow(counts))) {
      flat[[paste0(setting, ".", counts$from[i])]] <- counts$rows_mapped[i]
    }
  }
  flat
}

# stratified_km_analysis() census-by-tenure companion (math methods 5.7) ->
# one entry per (stratifier, stratum) for the intake rate and the predicted
# census, plus one per day of the tenure grid, named "<id>.<stratum>.lambda",
# "<id>.<stratum>.predicted_census", and "<id>.<stratum>.day<d>". Computed
# through the production helpers (.compute_census_by_tenure on
# stratified_results$intake_rates), the same path the census CSVs take, so
# predicted_census pins the Little's-law identity: intake rate x restricted
# mean.
flatten_census <- function(stratified_results, references) {
  flat <- list()
  tau <- references$restricted_stay_cap
  for (stratifier in stratified_results$stratifiers) {
    fit <- stratified_results[[stratifier$km_result_key]]
    if (is.null(fit)) next
    rates  <- stratified_results$intake_rates[[stratifier$id]]
    census <- .compute_census_by_tenure(fit, tau, rates)
    for (stratum in setdiff(names(census), "days")) {
      key_prefix <- paste0(stratifier$id, ".", stratum)
      flat[[paste0(key_prefix, ".lambda")]]           <- rates[stratum][[1L]]
      flat[[paste0(key_prefix, ".predicted_census")]] <- sum(census[[stratum]], na.rm = TRUE)
      for (i in seq_len(nrow(census))) {
        flat[[paste0(key_prefix, ".day", census$days[i])]] <- census[[stratum]][i]
      }
    }
  }
  flat
}

# aj_by_stratifier() -> has_analysis, a stratum count, and one entry per
# (stratum, column, day) cell actually populated, named
# "<stratum>.<column>_day<day>", e.g. "Period_1.CIF_L_day10", "LARGE.CIF_L_day10".
# `count_key` names the count field so each stratifier reads naturally in its
# expected.R ("n_periods", "n_intake_types", "n_animal_groups"); the stratum
# names themselves already distinguish the rest.
flatten_aj_stratum <- function(aj_stratum_results, count_key) {
  flat <- list(has_analysis = as.numeric(isTRUE(aj_stratum_results$has_analysis)))
  if (!isTRUE(aj_stratum_results$has_analysis)) return(flat)

  flat[[count_key]] <- aj_stratum_results$n_strata
  for (stratum_name in names(aj_stratum_results$per_stratum)) {
    flat <- c(flat, flatten_cif_cells(aj_stratum_results$per_stratum[[stratum_name]]$cif_df,
                                      prefix = paste0(stratum_name, ".")))
  }
  flat
}

# One entry per (column, row) of an observation matrix, named
# "<prefix><label>.<field>".
flatten_observation_matrix <- function(m, prefix = "") {
  flat <- list()
  for (lbl in colnames(m)) {
    for (row_name in rownames(m)) {
      flat[[paste0(prefix, lbl, ".", row_name)]] <- m[row_name, lbl]
    }
  }
  flat
}

# Per-period counts/census/flow metrics -> one entry per (period, field),
# named "<period_label>.<field>", e.g. "Period_1.total_animal_days",
# "Period_2.daily_mean_total_in_care_days". Built through
# .build_stratum_observation_matrix, so this is the same matrix the results
# bundle carries and the workbook displays, not a parallel derivation of it.
flatten_period_stats <- function(period_data, references) {
  labels <- as.character(references$periods$period_label)
  days_lookup <- setNames(as.numeric(references$periods$duration_days), labels)
  flatten_observation_matrix(
    .build_stratum_observation_matrix(period_data, labels, days_lookup,
                                      col = "period_label", window_days = NULL)
  )
}

# Per-stratum counterpart of flatten_period_stats, grouped by each stratifier
# column with the whole-window day denominator (total days across all periods),
# exactly as the bundle's intake/group nodes are built. Keys are
# "<id>.<stratum>.<field>", e.g. "group.SMALL.total_animal_days",
# "intake.STRAY.total_intakes", "group.SMALL.total_stays". A missing stratifier
# column contributes no entries, so expecting NA for one of its fields works as
# an absence assertion.
flatten_stratum_stats <- function(period_data, references) {
  flat <- list()
  window_days <- .total_window_days(references$periods)
  for (stratifier in stratifiers) {
    if (identical(stratifier$id, "period")) next
    if (is.null(period_data[[stratifier$col]])) next
    labels <- .stratum_levels_present(period_data[[stratifier$col]])
    if (length(labels) == 0) next
    days_lookup <- setNames(rep(window_days, length(labels)), labels)

    flat <- c(flat, flatten_observation_matrix(
      .build_stratum_observation_matrix(period_data, labels, days_lookup,
                                        col = stratifier$col, window_days = window_days),
      prefix = paste0(stratifier$id, ".")
    ))

    # Each stay counted once, in contrast with the row-level counts above.
    unified <- calculate_unified_stay_counts(period_data, labels, stratifier$col)
    for (i in seq_len(nrow(unified))) {
      for (col in c("total_stays", "left_truncated_stays", "right_censored_stays")) {
        flat[[paste0(stratifier$id, ".", unified$period_label[i], ".", col)]] <- unified[[col]][i]
      }
    }
  }
  flat
}

# Arithmetic invariants of the results bundle, checked on every case under
# --generate-outputs and independently of any fixture: relations that must hold
# between measures no matter what the data looks like. These used to be checked
# by reading cells back out of the saved workbook, which was the only place the
# numbers existed; they are now checked where they are computed.
#
# Every stratifying dimension in the bundle is checked, so By_Period, the
# pooled whole-sample node, and each stratum node all get the same treatment.
check_bundle_invariants <- function(case_name, bundle) {
  cap <- bundle$settings$restricted_stay_cap

  # The data-preparation register must reconcile as a chain: each step starts
  # where the one before it finished, the first starts at the file's row count,
  # and the last ends at the prepared-stay count. That is worth asserting
  # rather than assuming, because it is exactly what a future row-removing step
  # added without a matching drop_step call would break: the rows would vanish
  # between two recorded steps and the chain would no longer join up. The check
  # therefore guards the register's completeness, not just its arithmetic.
  #
  # has_register is asserted rather than used as a gate. Every fixture's
  # period_data comes from break_down_by_period, which always attaches the
  # register, so an absent one means the attribute was dropped somewhere in
  # between -- and skipping quietly on absence would retire the whole chain
  # check at exactly the moment it stopped being able to run.
  prep <- bundle$data_preparation
  expect_equal(paste0(case_name, ": data_preparation: register present"),
               as.numeric(isTRUE(prep$has_register)), 1)
  if (isTRUE(prep$has_register)) {
    steps <- prep$attrition
    plbl  <- paste0(case_name, ": data_preparation")
    expect_equal(paste0(plbl, ": chain starts at rows_read"),
                 steps$rows_before[1], prep$rows_read)
    expect_equal(paste0(plbl, ": chain ends at rows_prepared"),
                 steps$rows_after[nrow(steps)], prep$rows_prepared)
    for (i in seq_len(nrow(steps))) {
      expect_equal(paste0(plbl, ": step ", steps$step[i], " removed count"),
                   steps$rows_before[i] - steps$rows_after[i], steps$rows_removed[i])
      if (i > 1) {
        expect_equal(paste0(plbl, ": step ", steps$step[i], " joins the one before"),
                     steps$rows_before[i], steps$rows_after[i - 1])
      }
    }

    # The ledger the attrition register above is projected from, checked on the
    # three things the projection cannot show: that it too joins up (through the
    # recodes and the period split, which attrition does not carry), that it
    # ends where the analysis actually starts, and that the attrition steps are
    # exactly its row-removing ones.
    lg <- prep$ledger
    expect_equal(paste0(plbl, ": ledger starts at rows_read"),
                 lg$rows_in[1], prep$rows_read)
    expect_equal(paste0(plbl, ": ledger ends at rows_analyzed"),
                 lg$rows_out[nrow(lg)], prep$rows_analyzed)
    for (i in seq_len(nrow(lg))) {
      if (i > 1) {
        expect_equal(paste0(plbl, ": ledger step ", lg$step[i], " joins the one before"),
                     lg$rows_in[i], lg$rows_out[i - 1])
      }
      # Only `split` may end with more rows than it began with; everything else
      # either removes rows or leaves the count alone.
      expect_equal(paste0(plbl, ": ledger step ", lg$step[i], " does not gain rows"),
                   as.numeric(lg$rows_out[i] <= lg$rows_in[i] ||
                              identical(lg$action[i], "split")), 1)
    }
    # attrition stops at rows_prepared, so it is the LEADING row-removing stages
    # of the ledger: the two that break_down_by_period appends after the split
    # remove rows too, but from the animal-period rows rather than the stays.
    expect_equal(paste0(plbl, ": attrition is the ledger's leading row-removing steps"),
                 as.numeric(identical(
                   steps$step,
                   head(lg$name[lg$action %in% c("cut", "dedup")], nrow(steps)))), 1)

    # The column contract this file shares with ShelterDataPrep's statistics
    # table, written out literally. There is no cross-repo machinery keeping the
    # two emitters aligned and there does not need to be: the list is short and
    # settled, so a rename on either side fails that side's own suite instead of
    # surfacing months later when someone tries to read the two files together.
    # The format is documented in the ShelterDataPrep README under "The
    # statistics table"; mLOS's additions to its vocabulary are in the User Guide.
    expect_equal(paste0(plbl, ": ledger CSV column contract"),
                 as.numeric(identical(
                   names(build_screening_ledger(prep)),
                   c("section", "step", "action", "column", "role", "value", "scope",
                     "detail", "rows_in", "rows_affected", "rows_out",
                     "animal_id_in", "animal_id_affected", "animal_id_out"))), 1)
  }

  for (id in names(bundle$strata)) {
    m <- bundle$strata[[id]]
    labels <- m$labels
    obs <- m$observations
    cen <- m$census
    km  <- m$km
    ci  <- m$ci
    lbl <- paste0(case_name, ": bundle[", id, "]")

    row_of <- function(mat, name, i) {
      if (is.null(mat) || !(name %in% rownames(mat))) return(NA_real_)
      as.numeric(mat[name, i])
    }
    ratio <- function(num, den) if (!is.na(den) && den > 0) num / den else NA_real_

    # Every "<X>_ci_lower" implies an "<X>_ci_upper" and an "<X>" estimate,
    # ordered lower <= estimate <= upper. Checked generically, so a triplet
    # added later is exercised without editing this function.
    lo_names <- unique(grep("_ci_lower$", rownames(ci), value = TRUE))
    for (lo_name in lo_names) {
      base_name <- sub("_ci_lower$", "", lo_name)
      hi_name   <- paste0(base_name, "_ci_upper")
      if (!(hi_name %in% rownames(ci)) || !(base_name %in% rownames(ci))) next
      for (i in seq_along(labels)) {
        lo <- row_of(ci, lo_name, i); hi <- row_of(ci, hi_name, i)
        est <- row_of(ci, base_name, i)
        if (is.na(lo) || is.na(hi) || is.na(est)) next
        expect_equal(paste0(lbl, ": ", base_name, " lower <= estimate <= upper (", labels[i], ")"),
                     as.numeric(lo <= est + 1e-6 && est <= hi + 1e-6), 1)
      }
    }

    for (i in seq_along(labels)) {
      col <- labels[i]

      # Census aggregates:
      #  - Little's law: expected_census = mean_daily_intakes x km_restricted_mean
      #  - future - past = census
      #  - the three per-resident ratios take the right numerator over the right
      #    denominator (a zero/NA denominator yields NA on both sides, so the
      #    assertion still holds)
      pred <- row_of(cen, "expected_census", i)
      past <- row_of(cen, "expected_past_animal_days", i)
      futr <- row_of(cen, "expected_future_animal_days", i)
      expect_equal(paste0(lbl, ": predicted census = intakes x rmean (", col, ")"),
                   pred,
                   row_of(obs, "mean_daily_intakes", i) * row_of(km, "km_restricted_mean", i))
      expect_equal(paste0(lbl, ": future - past = census (", col, ")"), futr - past, pred)
      expect_equal(paste0(lbl, ": per-resident in-care days = in-care days / census (", col, ")"),
                   row_of(cen, "per_resident_in_care_days", i),
                   ratio(row_of(cen, "daily_mean_total_in_care_days", i),
                         row_of(cen, "mean_census_inventory", i)))
      expect_equal(paste0(lbl, ": per-resident past days = past days / expected census (", col, ")"),
                   row_of(cen, "per_resident_past_days", i), ratio(past, pred))
      expect_equal(paste0(lbl, ": per-resident future days = future days / expected census (", col, ")"),
                   row_of(cen, "per_resident_future_days", i), ratio(futr, pred))

      # The KM curve's terminal value against the Aalen-Johansen route to the
      # same quantity: still in care at the cap is 1 - cif_Any. Two independent
      # fits, so this is a real cross-check rather than a restatement. The AJ
      # window can stop short of the cap when a stratum's last event does, but
      # its CIF is flat from there on, so its final value is also its value at
      # the cap and the comparison stays like for like.
      still <- row_of(km, "km_still_in_care_at_cap", i)
      if (!is.na(still) && !is.null(m$aj_final_cif) &&
          "aj_final_cif_Any" %in% rownames(m$aj_final_cif)) {
        cif_any <- row_of(m$aj_final_cif, "aj_final_cif_Any", i)
        if (!is.na(cif_any)) {
          expect_equal(paste0(lbl, ": still in care at cap = 1 - AJ cif_Any (", col, ")"),
                       still, 1 - cif_any, tol = 1e-8)
        }
      }
      # A probability, bracketed by its bounds where survfit defines them. It
      # leaves them undefined once the curve reaches zero, exactly as the
      # km_survival CSV's lower_ci/upper_ci columns go NA there, so a missing
      # bound is a legitimate answer rather than a failure.
      still_lo <- row_of(km, "km_still_in_care_at_cap_ci_lower", i)
      still_hi <- row_of(km, "km_still_in_care_at_cap_ci_upper", i)
      expect_equal(paste0(lbl, ": still in care at cap is a bounded probability (", col, ")"),
                   as.numeric(isTRUE(is.na(still) ||
                                (still >= 0 && still <= 1 &&
                                   (is.na(still_lo) || still_lo <= still) &&
                                   (is.na(still_hi) || still_hi >= still)))), 1)

      # Resident-tenure quantiles: whole days, ordered, and inside the capped
      # grid they are read off. They cannot be "not reached" (the tenure
      # distribution is proper on 0..cap-1), so a NA here means an empty
      # stratum, and then the mean they accompany is NA too.
      res_med <- row_of(cen, "per_resident_past_days_restricted_median", i)
      res_p90 <- row_of(cen, "per_resident_past_days_restricted_p90", i)
      if (is.na(res_med) || is.na(res_p90)) {
        expect_equal(paste0(lbl, ": resident tenure quantiles NA only with an NA mean (", col, ")"),
                     as.numeric(is.na(row_of(cen, "per_resident_past_days", i))), 1)
      } else {
        expect_equal(paste0(lbl, ": resident tenure median <= p90, whole days within the cap (", col, ")"),
                     as.numeric(res_med >= 0 && res_med <= res_p90 && res_p90 <= cap - 1 &&
                                  res_med == round(res_med) && res_p90 == round(res_p90)), 1)
      }

      # Count-based intervals, recomputed from the counts they are built on,
      # to catch a swapped numerator/denominator that monotonicity would miss.
      capped_n <- row_of(obs, "capped_at_restricted_stay_cap", i)
      total_n  <- row_of(obs, "total_observations", i)
      days_i   <- row_of(obs, "duration_days", i)
      expect_equal(paste0(lbl, ": fraction_capped CI lower (", col, ")"),
                   row_of(ci, "fraction_capped_ci_lower", i),
                   .binom_prop_ci(capped_n, total_n)[1])
      expect_equal(paste0(lbl, ": fraction_capped CI upper (", col, ")"),
                   row_of(ci, "fraction_capped_ci_upper", i),
                   .binom_prop_ci(capped_n, total_n)[2])
      for (flow in c("intakes", "outcomes")) {
        n_flow <- row_of(obs, paste0("total_", flow), i)
        expect_equal(paste0(lbl, ": mean_daily_", flow, " CI lower (", col, ")"),
                     row_of(ci, paste0("mean_daily_", flow, "_ci_lower"), i),
                     .poisson_rate_ci(n_flow, days_i)[1])
        expect_equal(paste0(lbl, ": mean_daily_", flow, " CI upper (", col, ")"),
                     row_of(ci, paste0("mean_daily_", flow, "_ci_upper"), i),
                     .poisson_rate_ci(n_flow, days_i)[2])
      }

      # expected_census: the log-scale delta-method interval is symmetric in
      # log(L) (est*exp(-h), est*exp(+h)), so lower*upper == estimate^2
      # exactly -- an identity that holds without needing the SE.
      est <- row_of(ci, "expected_census", i)
      lo  <- row_of(ci, "expected_census_ci_lower", i)
      hi  <- row_of(ci, "expected_census_ci_upper", i)
      if (!is.na(est) && !is.na(lo) && !is.na(hi)) {
        expect_equal(paste0(lbl, ": expected_census CI is log-symmetric (", col, ")"),
                     lo * hi, est^2)
      }

      # AJ restricted mean days by state (math methods 7.7): the in-care row
      # equals the KM restricted mean, and in-care + Any equals the cap.
      rmst     <- row_of(m$aj_rmtl, "aj_rmst_stay", i)
      rmtl_any <- row_of(m$aj_rmtl, "aj_rmtl_Any", i)
      km_rmean <- row_of(km, "km_restricted_mean", i)
      if (!is.na(rmst) && !is.na(km_rmean)) {
        expect_equal(paste0(lbl, ": aj_rmst_stay = km_restricted_mean (", col, ")"),
                     rmst, km_rmean)
      }
      if (!is.na(rmst) && !is.na(rmtl_any)) {
        expect_equal(paste0(lbl, ": aj_rmst_stay + aj_rmtl_Any = cap (", col, ")"),
                     rmst + rmtl_any, cap)
      }

      # Per-outcome mix and incidence intervals, over whichever outcome codes
      # this dataset carries, plus the RMTL additivity across them.
      outcome_codes <- sub("^outcome_(.*)_events$", "\\1",
                           grep("^outcome_.*_events$", rownames(m$outcomes), value = TRUE))
      total_completed   <- row_of(m$outcomes, "completed_outcomes_total", i)
      total_animal_days <- row_of(obs, "total_animal_days", i)
      events_overall    <- row_of(obs, "events", i)
      if (!is.na(events_overall) && !is.na(total_animal_days)) {
        expect_equal(paste0(lbl, ": Incidence_overall CI lower (", col, ")"),
                     row_of(ci, "incidence_overall_per_100_animal_days_ci_lower", i),
                     .poisson_rate_ci(events_overall, total_animal_days)[1] * 100)
        expect_equal(paste0(lbl, ": Incidence_overall CI upper (", col, ")"),
                     row_of(ci, "incidence_overall_per_100_animal_days_ci_upper", i),
                     .poisson_rate_ci(events_overall, total_animal_days)[2] * 100)
      }
      rmtl_sum <- 0
      rmtl_any_seen <- FALSE
      for (code in outcome_codes) {
        ejk <- row_of(m$outcomes, paste0("outcome_", code, "_events"), i)
        if (!is.na(ejk) && !is.na(total_completed)) {
          expect_equal(paste0(lbl, ": outcome_mix_", code, " CI lower (", col, ")"),
                       row_of(ci, paste0("outcome_mix_", code, "_ci_lower"), i),
                       .binom_prop_ci(ejk, total_completed)[1])
          expect_equal(paste0(lbl, ": outcome_mix_", code, " CI upper (", col, ")"),
                       row_of(ci, paste0("outcome_mix_", code, "_ci_upper"), i),
                       .binom_prop_ci(ejk, total_completed)[2])
        }
        if (!is.na(ejk) && !is.na(total_animal_days)) {
          expect_equal(paste0(lbl, ": incidence_", code, " CI lower (", col, ")"),
                       row_of(ci, paste0("incidence_", code, "_per_100_animal_days_ci_lower"), i),
                       .poisson_rate_ci(ejk, total_animal_days)[1] * 100)
          expect_equal(paste0(lbl, ": incidence_", code, " CI upper (", col, ")"),
                       row_of(ci, paste0("incidence_", code, "_per_100_animal_days_ci_upper"), i),
                       .poisson_rate_ci(ejk, total_animal_days)[2] * 100)
        }
        rmtl_k <- row_of(m$aj_rmtl, paste0("aj_rmtl_", code), i)
        if (!is.na(rmtl_k)) { rmtl_sum <- rmtl_sum + rmtl_k; rmtl_any_seen <- TRUE }
      }
      if (rmtl_any_seen && !is.na(rmtl_any)) {
        expect_equal(paste0(lbl, ": aj_rmtl_Any = sum of per-outcome RMTL (", col, ")"),
                     rmtl_any, rmtl_sum)
      }
    }
  }

  # The palette a downstream chart would use must be the palette the tool's own
  # plots use, and must be portable: R color names are not (its "purple" is
  # #A020F0 where CSS purple is #800080, and "gold3" has no meaning outside R),
  # so the JSON carries hex.
  pal <- bundle$palette
  expect_equal(paste0(case_name, ": palette: one entry per stratified color"),
               length(pal$stratum_colors), length(.STRATIFIED_COLORS))
  expect_equal(paste0(case_name, ": palette: stratum colors match the plots"),
               as.numeric(identical(pal$stratum_colors, .palette_hex(.STRATIFIED_COLORS))), 1)
  expect_equal(paste0(case_name, ": palette: every color is #RRGGBB"),
               as.numeric(all(grepl("^#[0-9A-F]{6}$", c(pal$stratum_colors, pal$outcome_colors)))), 1)
  expect_equal(paste0(case_name, ": palette: outcome colors keyed by code"),
               as.numeric(identical(names(pal$outcome_colors), .OUTCOME_STATE_LEVELS)), 1)
  expect_equal(paste0(case_name, ": palette: outcome colors match the plots"),
               as.numeric(identical(unname(pal$outcome_colors),
                                    .palette_hex(.OUTCOME_COLORS))), 1)
  # The plot code assigns stratum colors positionally and never recycles, which
  # only holds while the palette is at least as long as the strata cap.
  expect_equal(paste0(case_name, ": palette: long enough for the plot strata cap"),
               as.numeric(length(pal$stratum_colors) >= .MAX_PLOT_STRATA_LIMIT), 1)
  expect_equal(paste0(case_name, ": palette: outcome order is canonical"),
               as.numeric(identical(pal$outcome_order, .OUTCOME_STATE_LEVELS)), 1)

  invisible(NULL)
}

# The output manifest must describe exactly the files the run wrote: every CSV
# and PNG on disk appears in it, and every file it names exists. This is what
# keeps the family table in mlos_results.R honest -- a new output, or a renamed
# one, shows up here rather than silently going undescribed.
check_output_manifest <- function(case_name, bundle, results_dir) {
  manifest <- bundle$outputs
  listed_csv <- unlist(lapply(manifest, function(e) e$csv))
  listed_png <- unlist(lapply(manifest, function(e) e$plot))
  # Two CSVs are rightly absent from the manifest. cox_hazard_ratios.csv is
  # written by this suite (see write_case_outputs), not by the pipeline. And the
  # manifest describes the plot companions, documenting each one's day grid,
  # units and aggregate rule; data_preparation_stats.csv is neither a plot nor a
  # grid, so it is named beside the workbook and the log instead (see
  # archive_previous_outputs).
  not_manifested <- c("cox_hazard_ratios.csv", "data_preparation_stats.csv")
  on_disk_csv <- setdiff(list.files(results_dir, pattern = "\\.csv$"), not_manifested)
  on_disk_png <- list.files(results_dir, pattern = "\\.png$")

  undescribed <- setdiff(on_disk_csv, listed_csv)
  if (length(undescribed) > 0) cat("  CSVs missing from the manifest:", paste(undescribed, collapse = ", "), "\n")
  expect_equal(paste0(case_name, ": manifest: every CSV described"),
               length(undescribed), 0)
  undescribed_png <- setdiff(on_disk_png, listed_png)
  if (length(undescribed_png) > 0) cat("  PNGs missing from the manifest:", paste(undescribed_png, collapse = ", "), "\n")
  expect_equal(paste0(case_name, ": manifest: every plot described"),
               length(undescribed_png), 0)
  # kind + stratifier + outcome + variant must name exactly one output. Without
  # variant the two stack plots collide with their line counterparts, and a
  # consumer asking for a plot by what it IS gets whichever entry happens to
  # come first. That is the whole reason the manifest exists, so it is asserted
  # rather than assumed.
  keys <- vapply(manifest, function(e) paste(e$kind,
                                             if (is.null(e$stratifier)) "" else e$stratifier,
                                             if (is.null(e$outcome)) "" else e$outcome,
                                             if (is.null(e$variant)) "" else e$variant,
                                             sep = "|"), character(1))
  dupes <- unique(keys[duplicated(keys)])
  if (length(dupes) > 0) cat("  duplicated manifest keys:", paste(dupes, collapse = ", "), "\n")
  expect_equal(paste0(case_name, ": manifest: kind/stratifier/outcome/variant is unique"),
               as.numeric(length(dupes) == 0), 1)
  expect_equal(paste0(case_name, ": manifest: every entry declares a variant"),
               as.numeric(all(vapply(manifest, function(e) !is.null(e$variant), logical(1)))), 1)
  # Every entry names a stratifier, a whole-sample file naming "all" rather than
  # leaving it out. That is what lets a consumer key straight into strata
  # without translating an absent value first, so it is asserted here rather
  # than left to each consumer to discover.
  expect_equal(paste0(case_name, ": manifest: every entry names a stratifier in strata"),
               as.numeric(all(vapply(manifest,
                                     function(e) !is.null(e$stratifier) &&
                                       e$stratifier %in% names(bundle$strata),
                                     logical(1)))), 1)

  expect_equal(paste0(case_name, ": manifest: no CSV named that was not written"),
               length(setdiff(listed_csv, on_disk_csv)), 0)
  expect_equal(paste0(case_name, ": manifest: no plot named that was not written"),
               length(setdiff(listed_png, on_disk_png)), 0)

  # Archiving a previous run falls back to .MLOS_OUTPUT_FILE_PATTERN when there
  # is no manifest to read, so an output family named outside that pattern would
  # quietly stop being archived and start lingering as a stale file. Catch that
  # here, where a new output family is introduced, rather than a year later.
  for (f in c(listed_csv, listed_png)) {
    expect_equal(paste0(case_name, ": manifest: ", f, " matches the archive pattern"),
                 as.numeric(grepl(.MLOS_OUTPUT_FILE_PATTERN, f)), 1)
  }

  # Each entry has to be usable on its own: a consumer reads the file name, the
  # x column, and what the values mean without consulting anything else.
  for (e in manifest) {
    label <- if (!is.null(e$csv)) e$csv else e$plot
    expect_equal(paste0(case_name, ": manifest: ", label, " is described"),
                 as.numeric(nzchar(e$kind) && nzchar(e$description) &&
                            nzchar(e$x$column) && nzchar(e$values$units)), 1)
  }
  invisible(NULL)
}

# Cross-check between the companion CSVs and the bundle. Both carry the same
# summary quantities by different routes, and this asserts they agree.
#
# The point of the two routes is that they are independent. The bundle reaches
# the expected census through Little's law, mean daily intakes x restricted
# mean, while the CSV reaches it by summing the census-by-tenure profile day by
# day; the restricted mean itself comes from a per-subset survfit in the bundle
# and from summing the survival grid in the CSV. Same theorem, different
# arithmetic, so a fault in a grid, a day range, or a stratum alignment breaks
# one and not the other. That is worth keeping, and the codebase already takes
# this position for the remaining-LOS row (see .stratum_rmst_map in mlos_km.R).
# What was missing was an assertion that the two actually land in the same
# place.
#
# Tolerance is relative and generous: the observed disagreement is at the
# floating-point noise floor (about 3e-15), while any real fault would be
# orders of magnitude out.
.CSV_BUNDLE_TOLERANCE <- 1e-9

check_csv_aggregates <- function(case_name, bundle, results_dir) {
  rel_equal <- function(a, b) {
    if (is.na(a) || is.na(b)) return(NA)
    abs(a - b) <= .CSV_BUNDLE_TOLERANCE * max(1, abs(b))
  }
  # Where the bundle keeps the same quantity, by output kind. NULL means the
  # bundle carries no directly comparable value for that family.
  bundle_value <- function(entry, column) {
    # A whole-sample file names "all" as its stratifier, so no translation is
    # needed: strata$all is the whole dataset as a single stratum, under the
    # same "All" heading the file's one column carries, and it cross-checks
    # exactly as the stratified files do. The unified KM survival and AJ files
    # have no such column and are handled below.
    strata <- bundle$strata[[entry$stratifier]]
    at <- function(mat, row) {
      if (is.null(mat) || !(row %in% rownames(mat)) || !(column %in% colnames(mat))) return(NULL)
      mat[row, column]
    }
    switch(entry$kind,
      # The unified survival file's column is the curve itself, not a stratum
      # heading, so it reads its restricted mean from the unified node instead.
      km_survival = if (identical(entry$stratifier, "all")) bundle$unified$restricted_mean
                    else at(strata$km, "km_restricted_mean"),
      km_remaining_los    = at(strata$census, "remaining_days_at_mean_tenure"),
      km_census_by_tenure = at(strata$census, "expected_census"),
      km_in_care_tenure    = at(strata$census, "per_resident_past_days"),
      # Only the per-outcome stratified files map cleanly; the unified AJ file
      # spreads several outcomes across its columns.
      aj_cif = if (identical(entry$stratifier, "all") || is.null(entry$outcome)) NULL
               else at(strata$aj_restricted_mean, paste0("aj_restricted_mean_", entry$outcome)),
      NULL
    )
  }

  for (entry in bundle$outputs) {
    if (is.null(entry$csv) || is.null(entry$aggregate)) next
    path <- file.path(results_dir, entry$csv)
    if (!file.exists(path)) next
    df <- utils::read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
    agg_row <- which(df[[1]] == entry$aggregate$row)[1]
    if (is.na(agg_row)) {
      expect_equal(paste0(case_name, ": csv: ", entry$csv, " has its ",
                          entry$aggregate$row, " row"), 0, 1)
      next
    }
    grid <- df[-seq_len(agg_row), , drop = FALSE]

    for (column in names(df)[-1]) {
      stated <- suppressWarnings(as.numeric(df[[column]][agg_row]))
      if (is.na(stated)) next
      values <- suppressWarnings(as.numeric(grid[[column]]))
      values <- values[!is.na(values)]
      if (length(values) == 0) next

      derived <- switch(entry$aggregate$derivation,
        column_sum = sum(values),
        # The one rule that reads rather than reduces, and the one that needs a
        # number from outside the file: the grid row at the day the stratum's
        # mean in-care tenure falls in. Taken from the JSON's census block, so
        # this rederives the summary row from the two published outputs exactly
        # as a consumer following the manifest would.
        at_mean_tenure = {
          census <- bundle$strata[[entry$stratifier]]$census
          tenure <- if (!is.null(census) && "per_resident_past_days" %in% rownames(census) &&
                        column %in% colnames(census))
                      census["per_resident_past_days", column] else NA_real_
          row <- if (is.na(tenure)) NA_integer_ else match(as.character(floor(tenure)), grid[[1]])
          if (is.na(row)) NA_real_ else suppressWarnings(as.numeric(grid[[column]][row]))
        },
        cif_normalized_rmean = {
          final <- values[length(values)]
          if (isTRUE(all.equal(final, 0))) NA_real_ else sum(final - values) / final
        },
        NA_real_
      )
      if (!is.na(derived)) {
        expect_equal(paste0(case_name, ": csv: ", entry$csv, " ", column, " ",
                            entry$aggregate$row, " = ", entry$aggregate$derivation,
                            " of its grid"),
                     as.numeric(isTRUE(rel_equal(stated, derived))), 1)
      }

      in_bundle <- bundle_value(entry, column)
      if (!is.null(in_bundle) && length(in_bundle) == 1 && !is.na(in_bundle)) {
        expect_equal(paste0(case_name, ": csv: ", entry$csv, " ", column, " ",
                            entry$aggregate$row, " agrees with the bundle"),
                     as.numeric(isTRUE(rel_equal(stated, in_bundle))), 1)
      }
    }
  }
  invisible(NULL)
}

# results.json must be sufficient to rebuild the workbook. Renders a second
# copy from the file alone (read_results_json -> write_results_excel, the path
# mlos_render.R takes) and compares it with the workbook rendered from the live
# bundle, cell for cell across every sheet. A value that stops travelling in
# the JSON, or a shape the encoder mangles, shows up here as a mismatched cell
# -- which is how the outcome-type mapping's lost names were caught.
check_json_round_trip <- function(case_name, excel_file, json_file, results_dir) {
  if (!file.exists(json_file)) {
    expect_equal(paste0(case_name, ": json: results.json written"), 0, 1)
    return(invisible(NULL))
  }
  rendered <- file.path(results_dir, "from_json.xlsx")
  from_file <- read_results_json(json_file)
  write_results_excel(rendered, from_file)

  expect_equal(paste0(case_name, ": json: schema version round-trips"),
               from_file$schema_version, MLOS_RESULTS_SCHEMA_VERSION)

  # The golden comparison blanks this field, so nothing there would notice it
  # disappearing. Checked here, against the constant, on every case.
  expect_equal(paste0(case_name, ": json: tool version recorded"),
               as.numeric(identical(from_file$run$mlos_version, MLOS_VERSION)), 1)

  # Blanked by the golden comparison for the same reason and checked here for
  # the same reason: a golden that pinned them would fail on every machine
  # whose packages moved, whether or not a number did.
  expected_versions <- c(r = as.character(getRversion()), mlos_package_versions())
  names(expected_versions) <- paste0(names(expected_versions), "_version")
  expect_equal(paste0(case_name, ": json: package versions recorded"),
               as.numeric(identical(unlist(from_file$run[names(expected_versions)]),
                                    expected_versions)), 1)

  live_sheets <- openxlsx::getSheetNames(excel_file)
  file_sheets <- openxlsx::getSheetNames(rendered)
  expect_equal(paste0(case_name, ": json: same sheets"),
               as.numeric(identical(live_sheets, file_sheets)), 1)

  read_raw <- function(f, sheet) openxlsx::read.xlsx(f, sheet = sheet, colNames = FALSE,
                                                     skipEmptyRows = FALSE, skipEmptyCols = FALSE)
  for (sheet in intersect(live_sheets, file_sheets)) {
    a <- read_raw(excel_file, sheet)
    b <- read_raw(rendered, sheet)
    same_shape <- identical(dim(a), dim(b))
    expect_equal(paste0(case_name, ": json: ", sheet, " same shape"),
                 as.numeric(same_shape), 1)
    if (!same_shape) next
    # Compare as text: both sides came from the same numbers, so any
    # difference is a rehydration fault, not a formatting one.
    mismatches <- sum(mapply(function(x, y) !identical(as.character(x), as.character(y)),
                             unlist(a), unlist(b)))
    expect_equal(paste0(case_name, ": json: ", sheet, " identical to live render"),
                 mismatches, 0)
  }
  unlink(rendered)
  invisible(NULL)
}

# Workbook checks (only under --generate-outputs): the workbook must be
# written, carry the sheets the run calls for, and transcribe the bundle
# faithfully. What is checked here is what only the workbook can be wrong
# about -- which sheets exist, what sits on which row, what the reference
# column and the notes say -- plus a spot check per sheet family that a cell
# holds the bundle's value. The arithmetic behind those values is checked in
# check_bundle_invariants, not through the spreadsheet.
check_excel_workbook <- function(case_name, excel_file, bundle) {
  expect_equal(paste0(case_name, ": excel: workbook written"),
               as.numeric(file.exists(excel_file)), 1)
  if (!file.exists(excel_file)) return(invisible(NULL))

  all_sheets <- openxlsx::getSheetNames(excel_file)
  read_sheet <- function(name) openxlsx::read.xlsx(excel_file, sheet = name, colNames = FALSE,
                                                   skipEmptyRows = FALSE)
  # Value of one measure row, as the sheet holds it.
  sheet_cell <- function(df, row_name, i) {
    ri <- which(df[[1]] == row_name)[1]
    if (is.na(ri) || ncol(df) < i + 1) return(NA_real_)
    suppressWarnings(as.numeric(df[ri, i + 1][[1]]))
  }
  # A sheet transcribes the bundle: spot-check one row from each measure block.
  check_transcription <- function(sheet_name, df, measures) {
    spot <- list(
      total_animal_days = measures$observations,
      km_restricted_mean = measures$km,
      expected_census = measures$census,
      completed_outcomes_total = measures$outcomes,
      aj_final_cif_Any = measures$aj_final_cif,
      fraction_capped_ci_lower = measures$ci
    )
    for (row_name in names(spot)) {
      mat <- spot[[row_name]]
      if (is.null(mat) || !(row_name %in% rownames(mat))) next
      for (i in seq_along(measures$labels)) {
        expect_equal(paste0(case_name, ": excel: ", sheet_name, " ", row_name, " matches bundle (",
                            measures$labels[i], ")"),
                     sheet_cell(df, row_name, i), as.numeric(mat[row_name, i]))
      }
    }
  }

  # By_All is the whole-sample sheet and is always written; it is also the
  # alignment reference the other stratum sheets are compared against, since it
  # is the one sheet guaranteed to be there.
  expect_equal(paste0(case_name, ": excel: By_All always present"),
               as.numeric("By_All" %in% all_sheets), 1)
  ba <- read_sheet("By_All")
  check_transcription("By_All", ba, bundle$strata$all)

  # By_Period is an ordinary stratifier sheet: present exactly when there are
  # two or more periods to compare. With one period it would only restate
  # By_All under the period's label.
  by_period_expected <- isTRUE(bundle$settings$coverage$period$included)
  expect_equal(paste0(case_name, ": excel: By_Period present iff 2+ periods"),
               as.numeric("By_Period" %in% all_sheets), as.numeric(by_period_expected))
  if (by_period_expected) {
    check_transcription("By_Period", read_sheet("By_Period"), bundle$strata$period)
  }

  # stratum sheets (By_Intake_Type, By_Animal_Group): present exactly when
  # the stratifier is available, row-aligned with By_All (the same measure
  # must sit on the same worksheet line, so columns can be cut and pasted
  # across sheets -- checked via anchor rows from every section, where a
  # which()[1] of NA on BOTH sheets also passes, covering sections that are
  # legitimately absent everywhere).
  for (stratifier in stratifiers) {
    if (identical(stratifier$id, "period")) next
    measures <- bundle$strata[[stratifier$id]]
    expect_equal(paste0(case_name, ": excel: ", stratifier$sheet_name, " present iff available"),
                 as.numeric(stratifier$sheet_name %in% all_sheets), as.numeric(!is.null(measures)))
    if (is.null(measures) || !(stratifier$sheet_name %in% all_sheets)) next

    ss <- read_sheet(stratifier$sheet_name)
    anchors <- c("total_observations", "total_animal_days", "outcome_L_events",
                 "km_median_los", "expected_census",
                 "completed_outcomes_total",
                 "incidence_overall_per_100_animal_days",
                 "aj_final_cif_Any", "aj_restricted_mean_Any")
    for (anchor in anchors) {
      expect_equal(paste0(case_name, ": excel: ", stratifier$sheet_name, " aligned with By_All (", anchor, ")"),
                   as.numeric(identical(which(ss[[1]] == anchor)[1], which(ba[[1]] == anchor)[1])), 1)
    }

    check_transcription(stratifier$sheet_name, ss, measures)

    # Unified-across-periods counts occupy the sheet's top section (rows 3-5,
    # the slot the period-metadata table has on By_Period).
    unified <- measures$unified_stay_counts
    unified_fields <- c(unified_total_stays    = "total_stays",
                        unified_left_truncated = "left_truncated_stays",
                        unified_right_censored = "right_censored_stays")
    for (j in seq_along(unified_fields)) {
      row_name <- names(unified_fields)[j]
      row_idx <- which(ss[[1]] == row_name)[1]
      expect_equal(paste0(case_name, ": excel: ", stratifier$sheet_name, " ", row_name, " on row ", j + 2),
                   as.numeric(identical(row_idx, as.integer(j + 2))), 1)
      for (i in seq_len(nrow(unified))) {
        actual <- if (!is.na(row_idx) && ncol(ss) >= i + 1) ss[row_idx, i + 1][[1]] else NA
        expect_equal(paste0(case_name, ": excel: ", stratifier$sheet_name, " ", row_name, " ",
                            unified$period_label[i]),
                     actual, unified[[unified_fields[j]]][i])
      }
    }
  }

  # Observation-gaps section: present on every run, and its green "no gaps"
  # status line must appear exactly when the analyses found none.
  os <- read_sheet("General")
  expect_equal(paste0(case_name, ": excel: observation-gaps section present"),
               as.numeric(any(grepl("Observation gaps", os[[1]], fixed = TRUE), na.rm = TRUE)), 1)
  has_gaps <- nrow(bundle$unified$gaps) > 0
  expect_equal(paste0(case_name, ": excel: gaps section matches analysis (",
                      if (has_gaps) "gaps found" else "clean", ")"),
               as.numeric(any(grepl("No observation gaps detected", os[[1]], fixed = TRUE), na.rm = TRUE)),
               as.numeric(!has_gaps))

  cs <- read_sheet("Cox_Regression")
  cox <- bundle$cox
  if (isTRUE(cox$has_analysis)) {
    rob_idx <- which(cs[[1]] == "Robust score")[1]
    rob_cols <- c("statistic", "df", "p_value")
    for (j in seq_along(rob_cols)) {
      actual <- if (!is.na(rob_idx) && ncol(cs) >= j + 1) cs[rob_idx, j + 1][[1]] else NA
      expect_equal(paste0(case_name, ": excel: robust score ", rob_cols[j]),
                   actual, cox$tests[[rob_cols[j]]][4])
    }
    conc_idx <- which(cs[[1]] == "concordance_se")[1]
    conc_actual <- if (!is.na(conc_idx) && ncol(cs) >= 2) cs[conc_idx, 2][[1]] else NA
    expect_equal(paste0(case_name, ": excel: Concordance_SE is summary()'s se (no sqrt)"),
                 conc_actual, cox$concordance_se)

    # Reference column (col 3): each predictor row must show the level the fit
    # actually used -- the first xlevels level -- and stay blank when the term
    # is not in the model. The period levels are the period labels themselves.
    xlev <- cox$xlevels
    ref_expected <- c(
      "Predictor groups: period"       = if ("period" %in% names(xlev)) xlev$period[1] else NA_character_,
      "Predictor groups: intake_type"  = if ("intake_type" %in% names(xlev)) xlev$intake_type[1] else NA_character_,
      "Predictor groups: animal_group" = if ("animal_group" %in% names(xlev)) xlev$animal_group[1] else NA_character_
    )
    blank_if_na <- function(v) if (length(v) == 0 || is.na(v)) "" else as.character(v)
    for (metric in names(ref_expected)) {
      row_i <- which(cs[[1]] == metric)[1]
      actual <- if (!is.na(row_i) && ncol(cs) >= 3) cs[row_i, 3][[1]] else NA
      expect_equal(paste0(case_name, ": excel: reference level, ", metric),
                   as.numeric(identical(blank_if_na(actual), blank_if_na(ref_expected[[metric]]))), 1)
    }

    # Hazard-ratio block: every level of every predictor must appear
    # (the reference as a definitional hr = 1 row), and each predictor's
    # rows must run in canonical order -- chronological for period,
    # alphabetical for intake_type/animal_group -- matching the
    # By_Period / By_Intake_Type / By_Animal_Group column order.
    canon_for <- function(term, lev) {
      if (identical(term, "period")) {
        canon <- as.character(bundle$settings$periods$period_label)
        canon[canon %in% lev]
      } else {
        sort(lev)
      }
    }
    for (term in names(xlev)) {
      canon <- canon_for(term, xlev[[term]])
      idxs <- match(paste0(term, canon), cs[[1]])
      expect_equal(paste0(case_name, ": excel: all ", term, " levels in HR block"),
                   as.numeric(!anyNA(idxs)), 1)
      expect_equal(paste0(case_name, ": excel: ", term, " HR rows in canonical order"),
                   as.numeric(!is.unsorted(idxs, strictly = TRUE)), 1)
      ref_idx <- match(paste0(term, xlev[[term]][1]), cs[[1]])
      ref_val <- if (!is.na(ref_idx) && ncol(cs) >= 2) cs[ref_idx, 2][[1]] else NA
      expect_equal(paste0(case_name, ": excel: ", term, " reference row hr = 1"),
                   ref_val, 1)
    }
  } else {
    expect_equal(paste0(case_name, ": excel: no-analysis note present"),
                 as.numeric(any(grepl("Cox regression not available", cs[[1]], fixed = TRUE))), 1)
  }

  # Weibull sheet: present exactly when parametric_regression is WEIBULL.
  # When the fit ran, pin the exported LOS ratios, implied hazard ratios, and
  # shape to the bundle's values.
  weibull_on <- identical(bundle$settings$parametric_regression, "WEIBULL")
  expect_equal(paste0(case_name, ": excel: Weibull sheet present iff enabled"),
               as.numeric("Weibull_Regression" %in% all_sheets), as.numeric(weibull_on))
  if (weibull_on && "Weibull_Regression" %in% all_sheets) {
    ws <- read_sheet("Weibull_Regression")
    wres <- bundle$weibull
    if (isTRUE(wres$has_analysis)) {
      hr_title <- which(as.character(ws[[1]]) == "Hazard ratios")[1]
      for (i in seq_len(nrow(wres$hr_table))) {
        expect_equal(paste0(case_name, ": excel: implied HR ", wres$hr_table$variable[i]),
                     ws[hr_title + 1 + i, 2][[1]], wres$hr_table$hr[i])
      }
      los_title <- which(ws[[1]] == "LOS ratios")[1]
      for (i in seq_len(nrow(wres$los_table))) {
        expect_equal(paste0(case_name, ": excel: LOS ratio ", wres$los_table$variable[i]),
                     ws[los_title + 1 + i, 2][[1]], wres$los_table$los_ratio[i])
      }
      # Its own headed section, the value on the row below labeled with the
      # bundle's own name, estimate/lower/upper in three numeric cells under
      # the same columns the LOS-ratio table above uses. The bounds used to be
      # one formatted string in column 3, and the whole thing used to be a bold
      # data row sitting where a heading belongs.
      shape_head <- which(ws[[1]] == "Weibull shape (k)")[1]
      expect_equal(paste0(case_name, ": excel: Weibull shape section present"),
                   as.numeric(!is.na(shape_head)), 1)
      if (!is.na(shape_head)) {
        expect_equal(paste0(case_name, ": excel: Weibull shape row labeled shape"),
                     as.numeric(identical(as.character(ws[shape_head + 1, 1][[1]]), "shape")), 1)
        shape_cells <- c(shape = wres$shape, shape_lo = wres$shape_lo, shape_hi = wres$shape_hi)
        for (j in seq_along(shape_cells)) {
          expect_equal(paste0(case_name, ": excel: Weibull ", names(shape_cells)[j],
                              " is numeric in col ", j + 1),
                       suppressWarnings(as.numeric(ws[shape_head + 1, j + 1][[1]])),
                       shape_cells[[j]])
        }
      }
      # Unified block at the sheet's bottom: when the unified fit is
      # distinct from the main model, its shape cell must mirror the
      # bundle's value; when the main model already is the unified fit
      # (no group terms), the note must say so instead.
      uni <- wres$unified
      if (isTRUE(uni$has_analysis) && !isTRUE(uni$same_as_main)) {
        uni_row <- which(ws[[1]] == "Unified Weibull shape (k)")[1]
        uni_cells <- c(shape = uni$shape, shape_lo = uni$shape_lo, shape_hi = uni$shape_hi)
        for (j in seq_along(uni_cells)) {
          expect_equal(paste0(case_name, ": excel: unified Weibull ", names(uni_cells)[j],
                              " is numeric in col ", j + 1),
                       if (!is.na(uni_row)) suppressWarnings(as.numeric(ws[uni_row, j + 1][[1]])) else NA_real_,
                       uni_cells[[j]])
        }
      } else if (isTRUE(uni$same_as_main)) {
        expect_equal(paste0(case_name, ": excel: unified same-as-main note present"),
                     as.numeric(any(grepl("already is the unified fit", ws[[1]], fixed = TRUE))), 1)
      }
    } else {
      expect_equal(paste0(case_name, ": excel: weibull no-analysis note present"),
                   as.numeric(any(grepl("Weibull regression not available", ws[[1]], fixed = TRUE))), 1)
    }
  }

  # Per-predictor shape variants, in both the places they surface: the
  # dedicated Weibull_By_... sheet and the compact companion section that
  # closes the stratifier's own By_... sheet. Worth checking rather than
  # trusting, because these two are the only sections in the workbook whose
  # availability varies from sheet to sheet within one run, which is exactly
  # what put the compact section below every alignment anchor -- and the
  # alignment anchors above therefore do not cover it.
  for (stratifier in stratifiers) {
    sheet_name <- stratifier$sheet_name
    if (!(sheet_name %in% all_sheets)) next
    weibull_sheet <- .STRATIFIER_ID_TO_WEIBULL_SHEET[[stratifier$id]]
    expect_equal(paste0(case_name, ": excel: ", weibull_sheet, " present iff Weibull enabled"),
                 as.numeric(weibull_sheet %in% all_sheets), as.numeric(weibull_on))

    wv <- bundle$strata[[stratifier$id]]$weibull_shape
    ss <- read_sheet(sheet_name)
    # The compact section is checked below whatever happened to the Weibull
    # fit: with the parametric fit off it carries the Cox rows and a footnote,
    # and with it on but declined it carries empty Weibull rows. Only the
    # dedicated sheet's own checks depend on a variant that ran.
    variant_ran <- weibull_on && isTRUE(wv$has_analysis)
    if (weibull_on) {
      wvs <- read_sheet(weibull_sheet)
      if (!variant_ran) {
        expect_equal(paste0(case_name, ": excel: ", weibull_sheet, " declined note present"),
                     as.numeric(any(grepl("Weibull shape regression not available",
                                          wvs[[1]], fixed = TRUE))), 1)
      }
    }
    if (variant_ran) {
      # Baseline shape: its own headed section, one row carrying the bundle's own
      # name for the node, three numeric cells lined up with the shape_ratio /
      # ci_95_lower / ci_95_upper columns of the table under it. Asserting the
      # bounds as numbers is what stops a future edit folding them back into
      # prose.
      base_head <- which(as.character(wvs[[1]]) == "Baseline Weibull shape (k)")[1]
      expect_equal(paste0(case_name, ": excel: ", weibull_sheet, " baseline shape section present"),
                   as.numeric(!is.na(base_head)), 1)
      if (!is.na(base_head)) {
        expect_equal(paste0(case_name, ": excel: ", weibull_sheet, " baseline row labeled shape_reference"),
                     as.numeric(identical(as.character(wvs[base_head + 1, 1][[1]]), "shape_reference")), 1)
        ref <- wv$shape_reference
        ref_keys <- c("k", "k_lo", "k_hi")
        for (j in seq_along(ref_keys)) {
          expect_equal(paste0(case_name, ": excel: ", weibull_sheet, " baseline ",
                              ref_keys[j], " is numeric in col ", j + 1),
                       suppressWarnings(as.numeric(wvs[base_head + 1, j + 1][[1]])),
                       ref[[ref_keys[j]]])
        }
      }

      # Every section on this sheet is a bold phrase in column 1 with its
      # clarification beside it in column 2, never folded into the phrase in
      # parentheses -- the house layout the sheet did not originally follow.
      for (head in c("Weibull shape regression", "Model tests", "LOS ratios",
                     "Baseline Weibull shape (k)", "Shape ratios")) {
        hr <- which(as.character(wvs[[1]]) == head)[1]
        expect_equal(paste0(case_name, ": excel: ", weibull_sheet, " section '", head, "' present"),
                     as.numeric(!is.na(hr)), 1)
        if (!is.na(hr)) {
          expect_equal(paste0(case_name, ": excel: ", weibull_sheet, " section '", head,
                              "' carries its note in col 2"),
                       as.numeric(!is.na(wvs[hr, 2][[1]]) && nzchar(as.character(wvs[hr, 2][[1]]))), 1)
        }
      }

      # Dedicated sheet: the shape-ratio table is the one thing that lives
      # nowhere else in the workbook, so pin every row of it to the bundle.
      shape_title <- which(as.character(wvs[[1]]) == "Shape ratios")[1]
      expect_equal(paste0(case_name, ": excel: ", weibull_sheet, " shape-ratio block present"),
                   as.numeric(!is.na(shape_title)), 1)
      if (!is.na(shape_title)) {
        for (i in seq_len(nrow(wv$shape_table))) {
          expect_equal(paste0(case_name, ": excel: ", weibull_sheet, " shape ratio ",
                              wv$shape_table$variable[i]),
                       wvs[shape_title + 1 + i, 2][[1]], wv$shape_table$shape_ratio[i])
        }
      }

    }

    # Compact companion, now two blocks: within each, the values are meant to
    # be comparable with one another. That only works if the rows really are
    # this stratifier's own levels, in the sheet's column order -- the rows are
    # matched by level name across separately fitted tables, so a
    # canonical-order drift between them would land a level's number under a
    # neighbor's column. The stratified Cox, freed-shape Weibull and KM rows
    # are pinned to the bundle; the pooled Cox row is checked against the Cox
    # sheet's own cells rather than against the bundle a second time.
    term   <- .STRATIFIER_ID_TO_TERM[[stratifier$id]]
    labels <- bundle$strata[[stratifier$id]]$labels
    cv     <- bundle$strata[[stratifier$id]]$cox_stratified
    for (i in seq_along(labels)) {
      if (isTRUE(cox$has_analysis)) {
        cox_i <- which(cs[[1]] == paste0(term, labels[i]))[1]
        cox_v <- if (!is.na(cox_i) && ncol(cs) >= 2) suppressWarnings(as.numeric(cs[cox_i, 2][[1]])) else NA_real_
        expect_equal(paste0(case_name, ": excel: ", sheet_name,
                            " cox_pooled_hazard_ratio matches Cox sheet (", labels[i], ")"),
                     sheet_cell(ss, "cox_pooled_hazard_ratio", i), cox_v)
      }
      # The stratified Cox variant is this section's only home in the workbook,
      # so it is pinned to the bundle directly. A variant that declined leaves
      # the row present and empty, which is what the NA asserts.
      strat_v <- if (isTRUE(cv$has_analysis)) {
        as.numeric(cv$hr_table$hr[match(paste0(term, labels[i]), cv$hr_table$variable)])
      } else {
        NA_real_
      }
      expect_equal(paste0(case_name, ": excel: ", sheet_name,
                          " cox_stratified_hazard_ratio (", labels[i], ")"),
                   sheet_cell(ss, "cox_stratified_hazard_ratio", i), strat_v)

      # The KM ratio is unadjusted but still needs the Cox fit to name its
      # denominator, so its rows are absent from the bundle's KM matrix
      # altogether when no reference level resolved, and the sheet shows empty.
      km <- bundle$strata[[stratifier$id]]$km
      km_v <- if ("km_restricted_mean_ratio" %in% rownames(km)) {
        as.numeric(km["km_restricted_mean_ratio", labels[i]])
      } else {
        NA_real_
      }
      expect_equal(paste0(case_name, ": excel: ", sheet_name,
                          " km_restricted_mean_ratio (", labels[i], ")"),
                   sheet_cell(ss, "km_restricted_mean_ratio", i), km_v)

      # Weibull rows: present and carrying the variant's number when the fit
      # ran, present and empty when it was asked for and declined, and absent
      # altogether when it was never asked for -- sheet_cell reads a missing
      # row as NA, so the last two cases are told apart by the footnote below
      # rather than here.
      if (weibull_on) {
        los_v <- if (variant_ran) {
          as.numeric(wv$los_table$los_ratio[match(paste0(term, labels[i]), wv$los_table$variable)])
        } else {
          NA_real_
        }
        expect_equal(paste0(case_name, ": excel: ", sheet_name,
                            " weibull_freed_shape_los_ratio (", labels[i], ")"),
                     sheet_cell(ss, "weibull_freed_shape_los_ratio", i), los_v)
      }
    }

    # Both blocks are always headed, whatever ran: the Cox and KM rows do not
    # depend on the parametric fit, and a missing heading is how the section
    # used to vanish.
    for (block in c("Hazard ratios", "LOS ratios")) {
      expect_equal(paste0(case_name, ": excel: ", sheet_name, " '", block, "' block present"),
                   as.numeric(any(as.character(ss[[1]]) == block, na.rm = TRUE)), 1)
    }

    # With the parametric fit off the Weibull rows are not written at all, and
    # a footnote under each block's values says why -- one per block, since the
    # blocks are meant to be read and cut one at a time. Checked both ways
    # round: no footnote when the fit ran, so a future edit cannot leave one
    # standing under numbers it contradicts.
    expect_equal(paste0(case_name, ": excel: ", sheet_name,
                        " a Weibull-off footnote under each block iff Weibull off"),
                 sum(grepl("Weibull regression is off", ss[[1]], fixed = TRUE)),
                 if (weibull_on) 0L else 2L)
    for (row_name in c("weibull_pooled_hazard_ratio", "weibull_pooled_los_ratio")) {
      expect_equal(paste0(case_name, ": excel: ", sheet_name, " ", row_name,
                          " row present iff Weibull on"),
                   as.numeric(any(as.character(ss[[1]]) == row_name, na.rm = TRUE)),
                   as.numeric(weibull_on))
    }
  }

  # House layout, every sheet: what follows a blank row is a section heading,
  # so such a row carries a phrase in column 1 and at most a clarifying note in
  # column 2 -- never data. A bold row of numbers sitting where a heading
  # belongs is the defect this catches; it has been introduced twice, once by
  # the baseline shape and once by the pooled Weibull shape, and both times it
  # read as a heading while behaving as data. Numbers are looked for from
  # column 3 on, since a note legitimately occupies column 2.
  for (sheet_name in all_sheets) {
    df <- read_sheet(sheet_name)
    if (is.null(df) || nrow(df) == 0 || ncol(df) < 3) next
    col1 <- as.character(df[[1]])
    col1[is.na(col1)] <- ""
    heads <- which(nzchar(col1) & !nzchar(c("", utils::head(col1, -1))))
    offenders <- Filter(function(i) {
      vals <- suppressWarnings(as.numeric(as.character(unlist(df[i, 3:ncol(df)]))))
      any(!is.na(vals))
    }, heads)
    expect_equal(paste0(case_name, ": excel: ", sheet_name,
                        " heading rows carry no data past col 2"),
                 as.numeric(length(offenders)),
                 0)
  }

  # By_All has no stratifying predicate for any of these ratios to be about, so
  # each of its two slots carries a "not applicable" note rather than a section
  # or a silent skip -- the difference that misaligned every row below it once
  # already. Unconditional now that the blocks outlive the parametric fit: with
  # Weibull off the other sheets still carry Cox and KM ratios, By_All neither.
  for (block in c("Hazard ratios", "LOS ratios")) {
    expect_equal(paste0(case_name, ": excel: By_All '", block, "' not-applicable note"),
                 as.numeric(any(grepl(paste0(block, " not applicable"), ba[[1]], fixed = TRUE))), 1)
  }

  invisible(NULL)
}

# Under --generate-outputs: render every analysis's plots and CSVs into
# results_dir, then write the consolidated Excel workbook and run its
# smoke checks (see check_excel_workbook above). The has_analysis checks
# distinguish a legitimately-skipped analysis (nothing to plot) from a bug.
write_case_outputs <- function(case_name, results_dir,
                               km_results, cox_results, stratified_results,
                               aj_results, aj_strat_results,
                               period_data, references, data_file, settings_file) {
  # Start from an empty directory: tests/results is not cleared between runs, so
  # an output that a code change stops producing would otherwise linger and be
  # compared against the goldens as if this run had written it.
  unlink(results_dir, recursive = TRUE)
  dir.create(results_dir, recursive = TRUE, showWarnings = FALSE)

  # One process runs every fixture, so the emission register has to start clean
  # per case or the manifest would carry the previous fixture's outputs.
  reset_emitted_outputs()

  # Bundle first, as in mlos_run_complete.R: everything is computed before
  # anything is rendered, so the companion CSVs can take their summary rows
  # from it rather than deriving them a second time.
  bundle <- build_results_bundle(
    cox_results       = cox_results,
    km_results        = km_results,
    aj_results        = aj_results,
    aj_strat_results  = aj_strat_results,
    period_data       = period_data,
    stratified_results = stratified_results,
    references        = references,
    data_filename     = data_file,
    settings_filename = settings_file,
    output_dir        = results_dir,
    log_path          = "(none: test-suite run)"
  )

  # Each plot_*() call also writes its companion CSV automatically
  # (same basename, .csv extension -- see .plot_csv_filename()).
  plot_km_curve(km_results, references,
                save_file = file.path(results_dir, "km_survival_unified.png"))

  plot_unified_km_companions(km_results, references,
                             base_filename = file.path(results_dir, "km_survival_unified.png"),
                             measures = bundle$strata$all)

  plot_stratified_km(stratified_results, references,
                      save_prefix = file.path(results_dir, "km_survival"),
                      measures_by_stratifier = bundle$strata)

  if (isTRUE(cox_results$has_analysis)) {
    # No dedicated exporter exists for the Cox hazard-ratio table outside
    # the full Excel workbook; dump it directly since it's already computed.
    utils::write.csv(cox_results$hr_table, file.path(results_dir, "cox_hazard_ratios.csv"), row.names = FALSE)
  }

  if (isTRUE(aj_results$has_analysis)) {
    plot_aj_cif(aj_results, references, save_file = file.path(results_dir, "aj_cif_unified.png"))
    plot_aj_cif_unified_stack(aj_results, references,
                              save_file = file.path(results_dir, "aj_cif_unified_stack.png"))
    plot_aj_conditional_unified_stack(aj_results, references,
                                      save_file = file.path(results_dir, "aj_conditional_unified_stack.png"))
    plot_aj_conditional_unified(aj_results, references,
                                save_file = file.path(results_dir, "aj_conditional_unified.png"))
  }

  # One pair of plot sets per available stratifier, filenames keyed by the
  # registry suffix (aj_cif_by_period, aj_cif_by_intake_type, ...).
  for (stratifier in stratifiers) {
    aj_stratum_results <- aj_strat_results[[stratifier$id]]
    if (!isTRUE(aj_stratum_results$has_analysis)) next
    # As in mlos_run_complete.R: a single-level stratifier is computed but not
    # plotted, its curves being the unified ones redrawn.
    if (!isTRUE(.strata_info(stratifier, references)$has)) next
    plot_aj_cif_by_stratum_lines(
      aj_stratum_results, references = references,
      save_prefix = file.path(results_dir, paste0("aj_cif", stratifier$suffix)))
    plot_aj_conditional_by_stratum_lines(
      aj_stratum_results, references = references,
      save_prefix = file.path(results_dir, paste0("aj_conditional", stratifier$suffix)))
  }

  # Only now can the manifest record what was written.
  bundle <- attach_output_manifest(bundle)
  write_results_json(bundle, file.path(results_dir, "results.json"))
  # Written here rather than through the manifest, as in mlos_run_complete.R:
  # the manifest describes the plot companions, and this is neither a plot nor a
  # grid. It lands in results_dir with the CSVs, so the golden comparison holds
  # it to the byte like every other one -- which is what pins the column set
  # this file shares with ShelterDataPrep's.
  write_screening_ledger_csv(bundle, file.path(results_dir, "data_preparation_stats.csv"))
  check_bundle_invariants(case_name, bundle)
  check_output_manifest(case_name, bundle, results_dir)
  check_csv_aggregates(case_name, bundle, results_dir)

  if (requireNamespace("openxlsx", quietly = TRUE)) {
    excel_file <- file.path(results_dir, "analysis_results.xlsx")
    write_results_excel(excel_file, bundle)
    check_excel_workbook(case_name, excel_file, bundle)
    check_json_round_trip(case_name, excel_file, file.path(results_dir, "results.json"),
                          results_dir)
  } else {
    cat("  [SKIP] openxlsx not installed -- Excel smoke checks skipped\n")
  }
  invisible(bundle)
}

# results.json with everything that legitimately changes between runs blanked,
# so the file can be compared literally: the generation timestamp, the project
# root that prefixes every path in the run block, the tool version, and the R
# and package versions beside it. All of them are honest provenance in a real
# run, so they are normalized here rather than in mlos_results.R -- what has to
# be portable is the committed golden, not the file a user gets. Without the
# root substitution the goldens only match on the machine that generated them;
# without the tool-version substitution a release would rewrite every golden,
# which teaches whoever regenerates them to stop reading the diff; and pinning
# the package versions here would fail every machine whose packages moved,
# whether or not a number did. Which versions the goldens came from is recorded
# once, in tests/golden/environment.txt. The fields are checked instead in
# check_json_round_trip, where a missing one fails rather than normalizing to
# nothing. Every other value in the file is a deterministic function of the
# fixture.
.golden_json_lines <- function(json_file) {
  if (!file.exists(json_file)) return(character(0))
  lines <- readLines(json_file, warn = FALSE)
  lines <- sub('"generated_at": ".*"', '"generated_at": "(run time)"', lines)
  lines <- sub('"mlos_version": ".*"', '"mlos_version": "(version)"', lines)
  lines <- sub(paste0('"(', paste(c("r", MLOS_PACKAGES), collapse = "|"),
                      ')_version": ".*"'),
               '"\\1_version": "(version)"', lines)
  gsub(project_root, "(project root)", lines, fixed = TRUE)
}

# Golden-file regression against golden_dir: CSVs byte-for-byte, PNGs by
# existence via png_manifest.txt. (The .xlsx is excluded: it embeds a
# generation timestamp.) With update = TRUE, regenerates the golden copies
# from results_dir instead of comparing.
check_golden <- function(case_name, results_dir, golden_dir, update) {
  if (update) {
    unlink(golden_dir, recursive = TRUE)
    dir.create(golden_dir, recursive = TRUE, showWarnings = FALSE)
    csvs <- list.files(results_dir, pattern = "\\.csv$")
    file.copy(file.path(results_dir, csvs), file.path(golden_dir, csvs), overwrite = TRUE)
    writeLines(sort(list.files(results_dir, pattern = "\\.png$")),
               file.path(golden_dir, "png_manifest.txt"))
    writeLines(.golden_json_lines(file.path(results_dir, "results.json")),
               file.path(golden_dir, "results.json"))
    cat("  [GOLDEN] updated:", length(csvs), "CSV file(s) + PNG manifest + results.json\n")
  } else if (dir.exists(golden_dir)) {
    golden_csvs <- sort(list.files(golden_dir, pattern = "\\.csv$"))
    gen_csvs    <- sort(list.files(results_dir, pattern = "\\.csv$"))
    if (!identical(golden_csvs, gen_csvs)) {
      missing_csvs <- setdiff(golden_csvs, gen_csvs)
      extra_csvs   <- setdiff(gen_csvs, golden_csvs)
      if (length(missing_csvs) > 0) cat("  golden CSVs not generated:", paste(missing_csvs, collapse = ", "), "\n")
      if (length(extra_csvs) > 0)   cat("  generated CSVs with no golden:", paste(extra_csvs, collapse = ", "), "\n")
    }
    expect_equal(paste0(case_name, ": golden: same CSV file set"),
                 as.numeric(identical(golden_csvs, gen_csvs)), 1)
    for (f in intersect(golden_csvs, gen_csvs)) {
      same <- identical(readLines(file.path(golden_dir, f), warn = FALSE),
                        readLines(file.path(results_dir, f), warn = FALSE))
      expect_equal(paste0(case_name, ": golden: ", f), as.numeric(same), 1)
    }
    manifest_file <- file.path(golden_dir, "png_manifest.txt")
    if (file.exists(manifest_file)) {
      expected_pngs <- readLines(manifest_file, warn = FALSE)
      missing_pngs  <- expected_pngs[!file.exists(file.path(results_dir, expected_pngs))]
      if (length(missing_pngs) > 0) cat("  expected PNGs not generated:", paste(missing_pngs, collapse = ", "), "\n")
      expect_equal(paste0(case_name, ": golden: all expected PNGs exist"),
                   as.numeric(length(missing_pngs) == 0), 1)
    }
    golden_json <- file.path(golden_dir, "results.json")
    if (file.exists(golden_json)) {
      same <- identical(readLines(golden_json, warn = FALSE),
                        .golden_json_lines(file.path(results_dir, "results.json")))
      expect_equal(paste0(case_name, ": golden: results.json"), as.numeric(same), 1)
    }
  } else {
    cat("  [GOLDEN] no golden dir for this case; run --update-golden to create it\n")
  }
  invisible(NULL)
}

# -----------------------------------------------------------------------
# The environment the goldens were built in
# -----------------------------------------------------------------------
# The byte-for-byte comparison pins more than the code: the packages named in
# MLOS_PACKAGES decide the last digits of every curve and fit, the layout of
# results.json and how a settings value parses, and R itself decides how a
# double is written out. A golden diff is evidence of a code change only when
# it comes from the environment the goldens were written in, so --update-golden
# records that environment next to them and a comparison run reports it.
#
# The report is a report, not a check. Golden failures are the signal that the
# numbers moved; this says whether the environment is the likely reason. A
# newer survival that happens to shift nothing would fail a version assertion
# while every golden passed, which is a false alarm, and one that would land on
# Colab (newest CRAN survival) on every run.
golden_environment_file <- file.path(suite_dir, "golden", "environment.txt")

current_golden_environment <- function() {
  versions <- c(R = as.character(getRversion()), mlos_package_versions())
  paste0(names(versions), ": ", versions)
}

# Set when the live environment differs from the recorded one, so the summary
# can repeat it: by then the banner has scrolled past the failures it explains.
golden_environment_differs <- FALSE

report_golden_environment <- function() {
  current   <- current_golden_environment()
  recorded  <- if (file.exists(golden_environment_file)) {
    readLines(golden_environment_file, warn = FALSE)
  } else NULL

  cat("\n=== golden environment ===\n")
  cat("  this run:  ", paste(current, collapse = ",  "), "\n", sep = "")

  # A prefixed update rewrites one case. Writing the whole tree's environment
  # record from it would claim the other 28 cases came from here too, so the
  # record is written only by a full regeneration, and a prefixed one on a
  # different environment says what it is about to leave behind.
  if (update_golden && !nzchar(case_prefix)) {
    writeLines(current, golden_environment_file)
    cat("  recorded in ", golden_environment_file, "\n", sep = "")
    return(invisible(NULL))
  }

  if (is.null(recorded)) {
    cat("  [GOLDEN] no environment record; run --update-golden without --prefix to write one\n")
    return(invisible(NULL))
  }

  cat("  goldens:   ", paste(recorded, collapse = ",  "), "\n", sep = "")
  if (identical(current, recorded)) return(invisible(NULL))

  golden_environment_differs <<- TRUE
  moved <- setdiff(current, recorded)
  cat("  [GOLDEN] environment differs from the goldens': ",
      paste(moved, collapse = ",  "), "\n", sep = "")
  if (update_golden) {
    cat("  [GOLDEN] --prefix regenerates this case here while the rest stay on the\n")
    cat("           recorded environment; regenerate all of them, or none.\n")
  } else {
    cat("  [GOLDEN] treat golden failures as unexplained only after ruling this out.\n")
  }
  invisible(NULL)
}

if (generate_outputs) report_golden_environment()

# -----------------------------------------------------------------------
# Discover and run each fixture
# -----------------------------------------------------------------------

last_bundle <- NULL

cases_dir <- file.path(suite_dir, "cases")
case_dirs <- sort(list.dirs(cases_dir, recursive = FALSE))
if (nzchar(case_prefix)) {
  case_dirs <- case_dirs[startsWith(basename(case_dirs), case_prefix)]
}

if (length(case_dirs) == 0) {
  if (nzchar(case_prefix)) {
    cat("No test cases under", cases_dir, "match --prefix", case_prefix, "\n")
  } else {
    cat("No test cases found under", cases_dir, "\n")
  }
}

# One fixture, as a function rather than a loop body, for two reasons that
# amount to the same one: tryCatch cannot wrap a block that uses `next`, and
# a case that stops partway should cost that case rather than every case
# after it. The results objects below are local to the call, which is what
# they always effectively were -- nothing outside the loop read them, and
# last_bundle, the one thing that does escape, still does through `<<-`.
run_fixture_case <- function(case_dir) {
  case_name     <- basename(case_dir)
  data_file     <- file.path(case_dir, "data.csv")
  settings_file <- file.path(case_dir, "settings.yaml")
  expected_file <- file.path(case_dir, "expected.R")

  cat("\n=== ", case_name, " ===\n", sep = "")

  missing <- c("data.csv", "settings.yaml", "expected.R")[
    !file.exists(c(data_file, settings_file, expected_file))
  ]
  if (length(missing) > 0) {
    cat("  [SKIP] missing:", paste(missing, collapse = ", "), "\n")
    return(invisible(NULL))
  }

  expected_env <- new.env()
  source(expected_file, local = expected_env)

  # Case-wide tolerance (see the header): absent means the exact 1e-6.
  case_tol <- if (!is.null(expected_env$tolerance)) {
    as.numeric(expected_env$tolerance)
  } else {
    1e-6
  }

  settings    <- read_settings(settings_file)
  references  <- extract_references(settings, define_periods(settings))
  data        <- read_and_prepare_data(data_file, references)
  references  <- detect_optional_columns(data, references)
  period_data <- break_down_by_period(data, references)

  # Checked before any analysis, since it describes what the analyses were
  # handed rather than anything they computed.
  if (!is.null(expected_env$expected_preparation)) {
    check_fields(paste0(case_name, ": preparation"), flatten_preparation(data),
                 expected_env$expected_preparation, tol = case_tol)
  }

  # Presence of the corresponding expected_* object is what turns each
  # analysis on; --generate-outputs turns all of them on regardless, so a
  # full output set can be produced for any fixture. Both AJ analyses use
  # km_results$max_time as their horizon (matching mlos_run_complete.R),
  # so either of them also pulls in the KM run.
  any_aj_stratifier <- any(vapply(stratifiers, function(stratifier) {
    !is.null(expected_env[[paste0("expected_aj_", stratifier$id)]])
  }, logical(1)))
  need_km <- !is.null(expected_env$expected_km) ||
             !is.null(expected_env$expected_aj) ||
             any_aj_stratifier ||
             generate_outputs
  # The per-stratifier regression variants ride along inside cox_results, so
  # asking for one has to pull in the Cox run the same way expected_cox does.
  # Without this a fixture naming only a variant would have its check skipped
  # rather than run, which reads as a pass.
  any_regression_stratifier <- any(vapply(stratifiers, function(stratifier) {
    !is.null(expected_env[[paste0("expected_stratifier_weibull_", stratifier$id)]]) ||
      !is.null(expected_env[[paste0("expected_cox_stratified_", stratifier$id)]])
  }, logical(1)))
  need_cox        <- !is.null(expected_env$expected_cox) ||
                     !is.null(expected_env$expected_weibull) ||
                     any_regression_stratifier || generate_outputs
  need_stratified <- !is.null(expected_env$expected_stratified_km) ||
                     !is.null(expected_env$expected_census) || generate_outputs
  need_aj         <- !is.null(expected_env$expected_aj) || generate_outputs

  if (need_km) {
    km_results <- km_unified_period(period_data, references)
    if (!is.null(expected_env$expected_km)) {
      check_fields(paste0(case_name, ": km"), km_results, expected_env$expected_km,
                   tol = case_tol)
    }
  }

  if (need_cox) {
    cox_results <- cox_regression_analysis(period_data, references)
    if (!is.null(expected_env$expected_cox)) {
      check_fields(paste0(case_name, ": cox"), flatten_cox(cox_results), expected_env$expected_cox,
                   tol = case_tol)
    }
    if (!is.null(expected_env$expected_weibull)) {
      check_fields(paste0(case_name, ": weibull"), flatten_weibull(cox_results$weibull),
                   expected_env$expected_weibull, tol = case_tol)
    }

    # One per-predictor Weibull shape variant, each turned on by its own
    # expected_stratifier_weibull_<id> object (expected_stratifier_weibull_period,
    # _intake, _group). No extra fit needed here (unlike the AJ stratifier
    # loop below): the shape variants are already computed as part of
    # cox_regression_analysis above, riding along inside cox_results$weibull.
    for (stratifier in stratifiers) {
      expected_obj <- expected_env[[paste0("expected_stratifier_weibull_", stratifier$id)]]
      if (!is.null(expected_obj)) {
        flat_variant <- flatten_stratifier_weibull(cox_results, stratifier$id)
        check_fields(paste0(case_name, ": stratifier_weibull_", stratifier$id),
                     flat_variant, expected_obj, tol = case_tol)
        # Invariant, checked wherever a crossing happened rather than only where
        # a fixture thought to pin it: the additive shape model is nested inside
        # the crossed one, so the crossed fit cannot be the worse of the two. A
        # negative statistic means a fit missed its own optimum, which is a
        # fitting fault and not a property of the data.
        if (isTRUE(flat_variant$crossed) || identical(flat_variant$crossed, 1)) {
          expect_equal(paste0(case_name, ": stratifier_weibull_", stratifier$id,
                              ": crossing beats additive"),
                       as.numeric(flat_variant$crossing_lr_stat >= 0), 1)
        }
      }
    }

    # One per-stratifier stratified Cox variant, each turned on by its own
    # expected_cox_stratified_<id> object. Like the Weibull variants above these
    # ride along inside cox_results, so no extra fit is needed here; unlike them
    # they do not depend on parametric_regression, so a fixture can ask for
    # these without asking for Weibull at all.
    for (stratifier in stratifiers) {
      expected_obj <- expected_env[[paste0("expected_cox_stratified_", stratifier$id)]]
      if (!is.null(expected_obj)) {
        check_fields(paste0(case_name, ": cox_stratified_", stratifier$id),
                     flatten_cox_stratified(cox_results, stratifier$id),
                     expected_obj, tol = case_tol)
      }
    }
  }

  if (need_stratified) {
    stratified_results <- stratified_km_analysis(period_data, references)
    if (!is.null(expected_env$expected_stratified_km)) {
      check_fields(paste0(case_name, ": stratified_km"),
                   flatten_stratified_km(stratified_results, stratified_results$stratifiers,
                                         references$restricted_stay_cap),
                   expected_env$expected_stratified_km, tol = case_tol)
    }
    if (!is.null(expected_env$expected_census)) {
      check_fields(paste0(case_name, ": census"),
                   flatten_census(stratified_results, references),
                   expected_env$expected_census, tol = case_tol)
    }

    # Every KM fit the companion grids are built from, the unified one included:
    # it has its own remaining-LOS and in-care-tenure outputs, read as a single
    # unlabeled series by .km_series_names, and the invariants below hold there
    # exactly as they do per stratum. The unified fit joins only when the KM run
    # happened, which a fixture asking for the stratified checks alone does not
    # imply.
    km_fits <- list()
    if (need_km) km_fits <- list(list(id = "unified", fit = km_results$km_fit))
    for (stratifier in stratified_results$stratifiers) {
      fit <- stratified_results[[stratifier$km_result_key]]
      if (is.null(fit)) next
      km_fits[[length(km_fits) + 1L]] <- list(id = stratifier$id, fit = fit)
    }

    # In-care tenure profile invariants (independent of the golden CSVs): each
    # series' G(x) is a valid survival-style curve (in [0,1], non-increasing),
    # and its column sum -- the CSV's per_resident_past_days -- equals the mean
    # tenure computed directly, sum_d d*S(d) / sum_d S(d). The latter pins the
    # tail-sum in .compute_in_care_tenure against an off-by-one.
    in_care_tau  <- references$restricted_stay_cap
    in_care_days <- 0:(in_care_tau - 1)
    for (km_fit_entry in km_fits) {
      fit <- km_fit_entry$fit
      in_care <- .compute_in_care_tenure(fit, in_care_tau)
      series_names <- .km_series_names(fit)
      for (k in seq_along(series_names)) {
        s <- .extract_stratum_survival(fit, k, in_care_days)
        if (sum(s) <= 0) next
        g   <- in_care[[series_names[k]]]
        key <- paste0(case_name, ": in_care ", km_fit_entry$id, ".", series_names[k])
        expect_equal(paste0(key, ": per_resident_past_days = sum d*S / sum S"),
                     sum(g, na.rm = TRUE), sum(in_care_days * s) / sum(s))
        expect_equal(paste0(key, ": G valid (in [0,1], non-increasing)"),
                     as.numeric(all(g >= -1e-9 & g <= 1 + 1e-9) && all(diff(g) <= 1e-9)), 1)
      }
    }

    # Remaining_LOS(0) = RMST invariant (math methods 5.6), independent of the
    # golden CSVs: .compute_remaining_los's day-0 value for each series must
    # equal .stratum_rmst_map's daily step-sum restricted mean computed
    # directly from the survival curve -- the same value the Remaining_LOS
    # companion CSV's own restricted_mean row now carries (math methods 8.1),
    # computed there independently of .compute_remaining_los so the CSV's two
    # numbers cross-check this identity rather than one restating the other.
    for (km_fit_entry in km_fits) {
      fit <- km_fit_entry$fit
      rlos <- .compute_remaining_los(fit, in_care_tau)
      series_names <- .km_series_names(fit)
      rmst_map <- .stratum_rmst_map(fit, series_names, in_care_tau)
      for (series_name in series_names) {
        key <- paste0(case_name, ": remaining_los ", km_fit_entry$id, ".", series_name)
        expect_equal(paste0(key, ": Remaining_LOS(0) = RMST"),
                     rlos[[series_name]][rlos$days == 0], rmst_map[[series_name]])
      }
    }
  }

  if (need_aj) {
    aj_results <- aj_competing_risk_analysis(period_data, max_time = km_results$max_time,
                                             rmean_cap = references$restricted_stay_cap)
    if (!is.null(expected_env$expected_aj)) {
      check_fields(paste0(case_name, ": aj"), flatten_aj(aj_results, references), expected_env$expected_aj,
                   tol = case_tol)
    }

    # The probability-mass bins, checked on every fixture that fits an AJ
    # rather than on the ones whose settings ask for them. The width is forced
    # here for the same reason --generate-outputs runs every analysis on every
    # fixture: the interesting inputs for binning are the awkward ones (a cap
    # of a few days, a single outcome state, one constant length of stay), and
    # none of those fixtures would otherwise reach this code.
    #
    # What is asserted is the closure property rather than any particular
    # number: the intervals plus the remainder are the whole distribution, so
    # they sum to 1 whatever the fit did, and no interval can hold negative
    # mass because a CIF cannot fall.
    for (width in c(1, 7, references$restricted_stay_cap)) {
      mass <- aj_probability_mass(aj_results,
                                  modifyList(references,
                                             list(probability_mass_width = width)))
      if (is.null(mass)) next
      label <- paste0(case_name, ": aj mass w=", width)
      expect_equal(paste0(label, ": bins and remainder sum to 1"),
                   sum(mass$masses) + mass$remainder, 1, tol = 1e-9)
      expect_equal(paste0(label, ": no negative mass"),
                   as.numeric(any(mass$masses < -1e-12)), 0)
      expect_equal(paste0(label, ": one row per interval"),
                   nrow(mass$masses), length(mass$edges) - 1)
    }
  }

  # One AJ run per stratifier in the registry, each turned on by its own
  # expected_aj_<id> object (expected_aj_period, expected_aj_intake,
  # expected_aj_group) or by --generate-outputs. A stratifier whose column is
  # absent or single-level returns has_analysis = FALSE from its own gate.
  aj_strat_results <- list()
  for (stratifier in stratifiers) {
    expected_obj <- expected_env[[paste0("expected_aj_", stratifier$id)]]
    if (is.null(expected_obj) && !generate_outputs) next
    # max_time left NULL, as in mlos_run_complete.R: each stratum's grid ends
    # at its own largest fitted time.
    aj_strat_results[[stratifier$id]] <- aj_by_stratifier(period_data, references, stratifier)
    if (!is.null(expected_obj)) {
      check_fields(paste0(case_name, ": aj_", stratifier$id),
                   flatten_aj_stratum(aj_strat_results[[stratifier$id]], stratifier$n_field),
                   expected_obj, tol = case_tol)
    }
  }

  # No analysis to run: period_data is already computed, so this is a pure
  # check of the shared per-period metric functions in mlos_data.R.
  if (!is.null(expected_env$expected_period_stats)) {
    check_fields(paste0(case_name, ": period_stats"), flatten_period_stats(period_data, references),
                 expected_env$expected_period_stats, tol = case_tol)
  }
  if (!is.null(expected_env$expected_stratum_stats)) {
    check_fields(paste0(case_name, ": stratum_stats"),
                 flatten_stratum_stats(period_data, references),
                 expected_env$expected_stratum_stats, tol = case_tol)
  }

  if (generate_outputs) {
    # need_cox/need_stratified/need_aj are all forced TRUE by generate_outputs
    # (see above), and the AJ stratifier loop runs every registry entry under
    # it, so cox_results/stratified_results/aj_results/aj_strat_results are
    # guaranteed to exist here.
    results_dir <- file.path(suite_dir, "results", case_name)
    # Kept for the suite-level JSON precision check below, which needs a
    # realistic bundle but does not care which case produced it.
    last_bundle <<- write_case_outputs(case_name, results_dir,
                       km_results, cox_results, stratified_results,
                       aj_results, aj_strat_results,
                       period_data, references, data_file, settings_file)
    check_golden(case_name, results_dir,
                 golden_dir = file.path(suite_dir, "golden", case_name),
                 update     = update_golden)
    cat("  [OUTPUTS] written to", results_dir, "\n")
  }
  invisible(NULL)
}

for (case_dir in case_dirs) {
  run_guarded(paste0(basename(case_dir), ": fixture aborted"),
              run_fixture_case(case_dir))
}

# The whole-suite checks, in a function for the same reason a fixture is one:
# so that one of them stopping is a recorded failure rather than the end of
# the run, taking the summary with it.
run_suite_checks <- function() {

  # -----------------------------------------------------------------------
  # Settings and data-validation error checks
  # -----------------------------------------------------------------------
  # These stop() paths cannot be exercised by fixtures (a fixture tripping
  # one would abort its own run), so they are asserted directly here with
  # the exact user-facing message text. Several pin past fixes: the doubled
  # "outcome_type_outcome_type_L" prefix and the "<=" vs "<" wording in the
  # invalid-outcome_date message.

  cat("\n=== settings and data validation errors ===\n")

  refs_for <- function(settings) extract_references(settings, define_periods(settings))
  base_settings <- list(period_dates = c("2024-01-01", "2024-06-01"), restricted_stay_cap = 100)
  with_base <- function(...) c(base_settings, list(...))
  write_temp_csv <- function(lines) {
    f <- tempfile(fileext = ".csv")
    writeLines(lines, f)
    f
  }

  expect_error("missing period_dates",
               define_periods(list()),
               "period_dates not found in settings file")
  expect_error("single period date",
               define_periods(list(period_dates = "2024-01-01")),
               "period_dates must contain at least 2 dates")
  expect_error("unparseable period date",
               define_periods(list(period_dates = c("2024-01-01", "2024-13-01"))),
               "Error parsing period_dates")
  expect_error("period_labels count mismatch",
               define_periods(list(period_dates = c("2024-01-01", "2024-06-01", "2024-12-01"),
                                   period_labels = list("Early"))),
               "period_labels must contain exactly 2 label(s), one per period (found: 1)")
  expect_error("duplicate period_labels",
               define_periods(list(period_dates = c("2024-01-01", "2024-06-01", "2024-12-01"),
                                   period_labels = list("Same", "Same"))),
               "period_labels contains duplicate labels: Same")
  expect_error("YAML-boolean period label",
               define_periods(list(period_dates = c("2024-01-01", "2024-06-01"),
                                   period_labels = list(TRUE))),
               "period_labels contains a value YAML parsed as boolean")
  expect_error("blank period label",
               define_periods(list(period_dates = c("2024-01-01", "2024-06-01"),
                                   period_labels = list("  "))),
               "period_labels contains an empty value")
  expect_error("period label with comma",
               define_periods(list(period_dates = c("2024-01-01", "2024-06-01"),
                                   period_labels = list("Early, late"))),
               "period_labels must not contain commas or equals signs")
  expect_error("missing restricted_stay_cap",
               refs_for(list(period_dates = c("2024-01-01", "2024-06-01"))),
               "restricted_stay_cap must be a single positive integer")
  expect_error("non-integer restricted_stay_cap",
               refs_for(list(period_dates = c("2024-01-01", "2024-06-01"), restricted_stay_cap = 10.5)),
               "restricted_stay_cap must be a positive integer (found: 10.5)")
  expect_error("plot_stay_cap above restricted_stay_cap",
               refs_for(with_base(plot_stay_cap = 200)),
               "plot_stay_cap must be less than or equal to restricted_stay_cap")
  expect_error("non-integer max_plot_strata",
               refs_for(with_base(max_plot_strata = 2.5)),
               "max_plot_strata must be a positive integer (found: 2.5)")
  expect_error("zero max_plot_strata (1 is the 'no stratified plots' value)",
               refs_for(with_base(max_plot_strata = 0)),
               "max_plot_strata must be a positive integer (found: 0)")
  expect_error("max_plot_strata above the palette-size hard cap",
               refs_for(with_base(max_plot_strata = 999)),
               "max_plot_strata cannot exceed")
  expect_error("missing outcome_type_T (all-or-none rule; message has single prefix)",
               refs_for(with_base(outcome_type_L = list("Adopted"), outcome_type_N = list("Euth"))),
               "outcome_type_T is missing or empty")
  expect_error("YAML-boolean raw label",
               refs_for(with_base(outcome_type_L = list(TRUE),
                                  outcome_type_T = list("Transf"),
                                  outcome_type_N = list("Euth"))),
               "outcome_type_L contains a value YAML parsed as boolean")
  expect_error("blank raw label",
               refs_for(with_base(outcome_type_L = list("  "),
                                  outcome_type_T = list("Transf"),
                                  outcome_type_N = list("Euth"))),
               "outcome_type_L contains an empty value")
  expect_error("raw label duplicated across two codes",
               refs_for(with_base(outcome_type_L = list("Same"),
                                  outcome_type_T = list("Same"),
                                  outcome_type_N = list("Euth"))),
               "Raw outcome labels appear under more than one code: Same")
  expect_error("raw label duplicated across mapping and delete",
               refs_for(with_base(outcome_type_L = list("Adopted"),
                                  outcome_type_T = list("Transf"),
                                  outcome_type_N = list("Euth"),
                                  outcome_type_delete = list("Adopted"))),
               "Raw outcome labels appear in more than one outcome_type_* setting")
  expect_error("outcome_type_delete present but empty",
               refs_for(with_base(outcome_type_delete = list())),
               "outcome_type_delete is present but empty")
  expect_error("non-logical discard_bad_rows",
               refs_for(with_base(discard_bad_rows = "yes")),
               "discard_bad_rows must be true or false")
  expect_error("non-logical show_km_ci_ribbons",
               refs_for(with_base(show_km_ci_ribbons = 5)),
               "show_km_ci_ribbons must be true or false")
  expect_error("invalid stratified-output flag value",
               refs_for(with_base(km_survival_by_stratifier = "MAYBE")),
               "km_survival_by_stratifier must be one of TRUE, FALSE, PNG, or CSV (found: MAYBE)")
  expect_error("multi-value stratified-output flag",
               refs_for(with_base(aj_cif_by_stratifier = list("PNG", "CSV"))),
               "aj_cif_by_stratifier must be a single value: TRUE, FALSE, PNG, or CSV")
  expect_error("both pass and cut for one filter",
               refs_for(with_base(intake_filter_pass = list("STRAY"),
                                  intake_filter_cut = list("OWNER"))),
               "At most one of intake_filter_pass and intake_filter_cut may be present")
  expect_error("empty filter list",
               refs_for(with_base(animal_group_filter_pass = list())),
               "animal_group_filter_pass is present but empty")
  expect_error("YAML-boolean filter value",
               refs_for(with_base(intake_filter_cut = list(TRUE))),
               "intake_filter_cut contains a value YAML parsed as boolean")
  expect_error("other_filter column without list",
               refs_for(with_base(other_filter_column_name = "coat")),
               "other_filter_column_name and one of other_filter_pass / other_filter_cut must be provided together")
  expect_error("other_filter list without column",
               refs_for(with_base(other_filter_pass = list("black"))),
               "other_filter_column_name and one of other_filter_pass / other_filter_cut must be provided together")
  # Value maps. The YAML list-of-pairs form arrives as a list of one-element
  # named lists, which is what these mimic; the malformed shapes are the ways
  # that form goes wrong in a hand-written settings file.
  expect_error("value map with duplicate keys",
               refs_for(with_base(animal_group_map = list(list(XL = "LRG"), list(XL = "SML")))),
               "animal_group_map has duplicate keys: XL")
  expect_error("value map entry with two pairs (a missing list dash)",
               refs_for(with_base(animal_group_map = list(list(XL = "LRG", TOY = "SML")))),
               "animal_group_map entry 1 must be a single \"from: to\" pair")
  expect_error("value map entry with no target (a missing colon)",
               refs_for(with_base(intake_type_map = list(list(STRAY = "OWNER"), "TRANSFER"))),
               "intake_type_map entry 2 must be a single \"from: to\" pair")
  expect_error("value map that is not a list of pairs at all",
               refs_for(with_base(intake_type_map = "STRAY")),
               "intake_type_map must be a non-empty list of \"from: to\" pairs")
  expect_error("empty value map",
               refs_for(with_base(intake_type_map = list())),
               "intake_type_map must be a non-empty list of \"from: to\" pairs")
  expect_error("YAML-boolean value map target",
               refs_for(with_base(intake_type_map = list(list(STRAY = FALSE)))),
               "intake_type_map entry 1 (STRAY) contains a value YAML parsed as boolean")
  expect_error("blank value map target",
               refs_for(with_base(intake_type_map = list(list(STRAY = "  ")))),
               "intake_type_map entry 1 (STRAY) contains an empty value")
  expect_error("value map target that is a list",
               refs_for(with_base(intake_type_map = list(list(STRAY = list("A", "B"))))),
               "intake_type_map entry 1 (STRAY) must map to exactly one value")
  expect_error("non-positive png_line_width_factor",
               refs_for(with_base(png_line_width_factor = -2)),
               "png_line_width_factor must be a single positive number")
  expect_error("non-character animal_group_columns",
               refs_for(with_base(animal_group_columns = 42)),
               "animal_group_columns must be a non-empty list of column name strings")

  val_refs <- refs_for(base_settings)

  expect_error("missing mandatory column",
               read_and_prepare_data(write_temp_csv(c(
                 "intake_date,outcome_date",
                 "2024-02-01,2024-02-10")), val_refs),
               "Missing mandatory columns: outcome_type")
  expect_error("invalid intake_date stops when discard_bad_rows is false",
               read_and_prepare_data(write_temp_csv(c(
                 "intake_date,outcome_date,outcome_type",
                 "oops,2024-02-10,L")), val_refs),
               "invalid or missing intake_date")
  expect_error("outcome before intake stops with '<' wording",
               read_and_prepare_data(write_temp_csv(c(
                 "intake_date,outcome_date,outcome_type",
                 "2024-02-10,2024-02-01,L")), val_refs),
               "outcome_date=2024-02-01 < intake_date=2024-02-10")
  expect_error("unrecognized outcome_type",
               read_and_prepare_data(write_temp_csv(c(
                 "intake_date,outcome_date,outcome_type",
                 "2024-02-01,2024-02-10,Zebra")), val_refs),
               "unrecognized outcome_type: Zebra")
  expect_error("outcome_type with no outcome_date",
               read_and_prepare_data(write_temp_csv(c(
                 "intake_date,outcome_date,outcome_type",
                 "2024-02-01,2024-02-10,L",
                 "2024-02-02,,L",
                 "2024-02-03,,N")), val_refs),
               "2 row(s) have an outcome_type but no outcome_date: L (1), N (1)")
  # The same rows must NOT stop the run when a setting declares their code to
  # mean the animal is still in care: the check runs after that recode, and
  # this is the assertion that it stays there. Returns normally, so the test is
  # that both rows survive with the outcome type cleared.
  in_care_refs <- refs_for(with_base(outcome_type_in_care = list("HOLD")))
  in_care_data <- read_and_prepare_data(write_temp_csv(c(
    "intake_date,outcome_date,outcome_type",
    "2024-02-01,2024-02-10,L",
    "2024-02-02,,HOLD")), in_care_refs)
  expect_equal("outcome_type_in_care shields a blank outcome_date from the check",
               nrow(in_care_data), 2)
  expect_equal("the shielded row is still in care", sum(in_care_data$in_care), 1)
  expect_error("animal_group_columns column absent from CSV",
               read_and_prepare_data(write_temp_csv(c(
                 "intake_date,outcome_date,outcome_type",
                 "2024-02-01,2024-02-10,L")),
                 refs_for(with_base(animal_group_columns = "nope"))),
               "animal_group_columns: column(s) not found in CSV: nope")
  expect_error("intake_type filter without an intake_type column",
               read_and_prepare_data(write_temp_csv(c(
                 "intake_date,outcome_date,outcome_type",
                 "2024-02-01,2024-02-10,L")),
                 refs_for(with_base(intake_filter_pass = list("STRAY")))),
               "The intake_type filter is configured, but the column 'intake_type' does not exist")
  expect_error("other filter naming a column absent from CSV",
               read_and_prepare_data(write_temp_csv(c(
                 "intake_date,outcome_date,outcome_type",
                 "2024-02-01,2024-02-10,L")),
                 refs_for(with_base(other_filter_column_name = "coat",
                                    other_filter_cut = list("black")))),
               "The other (coat) filter is configured, but the column 'coat' does not exist")
  expect_error("filter that removes every row",
               read_and_prepare_data(write_temp_csv(c(
                 "intake_date,outcome_date,outcome_type,intake_type",
                 "2024-02-01,2024-02-10,L,STRAY")),
                 refs_for(with_base(intake_filter_pass = list("OWNER")))),
               "The intake_type filter (pass) removed every row")
  # Integrity ordering: value filters run AFTER the overlapping-stay screen, so a
  # filter cannot hide an overlap by dropping one leg of the pair. Here the two
  # stays of animal X overlap but carry different intake_type; without the late
  # ordering, intake_filter_pass STRAY would delete the OWNER leg and the overlap
  # would go unseen. The overlap error firing proves the screen saw both rows.
  expect_error("value filter does not hide an overlapping-stay conflict",
               read_and_prepare_data(write_temp_csv(c(
                 "animal_id,intake_date,outcome_date,outcome_type,intake_type",
                 "X,2024-02-01,2024-02-15,L,STRAY",
                 "X,2024-02-10,2024-02-20,L,OWNER")),
                 refs_for(with_base(intake_filter_pass = list("STRAY")))),
               "row(s) overlap another stay of the same animal_id")

  # discard_bad_rows: true must drop exactly the four bad rows and keep the
  # good one (this path returns normally, so expect_equal rather than
  # expect_error). The last of the four is the outcome_type carrying no
  # outcome_date, which is dropped from a later point in the function than the
  # other three; the fixture case outcome_type_without_date covers what the
  # surviving rows then produce.
  discard_refs <- refs_for(with_base(discard_bad_rows = TRUE))
  discard_data <- read_and_prepare_data(write_temp_csv(c(
    "intake_date,outcome_date,outcome_type",
    "2024-02-01,2024-02-10,L",
    "oops,2024-02-10,L",
    "2024-02-10,2024-02-01,L",
    "2024-02-01,2024-02-10,Zebra",
    "2024-02-04,,L")), discard_refs)
  expect_equal("discard_bad_rows drops bad rows, keeps good ones", nrow(discard_data), 1)

  # .fill_missing_level: optional stratification columns must never carry NA.
  # Blanks become an explicit "_UNKNOWN_" level; the label grows an underscore
  # on each side until it matches no value the user already has in the column.
  fill_data <- read_and_prepare_data(write_temp_csv(c(
    "intake_date,outcome_date,outcome_type,intake_type",
    "2024-02-01,2024-02-10,L,stray",
    "2024-02-02,2024-02-11,L,",
    "2024-02-03,2024-02-12,L,_UNKNOWN_")), val_refs)
  expect_equal("blank intake_type filled with escalated _UNKNOWN_ label",
               as.numeric(identical(sort(levels(fill_data$intake_type)),
                                    sort(c("stray", "_UNKNOWN_", "__UNKNOWN__")))), 1)
  expect_equal("no NA intake_type remains after fill",
               sum(is.na(fill_data$intake_type)), 0)

  # Constructed animal_group: missing source parts are filled per column BEFORE
  # concatenation (a raw NA would otherwise embed the text "NA" in the name).
  # Gender + size, matching the documentation's example (F__UNKNOWN_ = a female
  # of unknown size).
  ag_fill_refs <- refs_for(with_base(animal_group_columns = c("gender", "size")))
  ag_fill_data <- read_and_prepare_data(write_temp_csv(c(
    "intake_date,outcome_date,outcome_type,gender,size",
    "2024-02-01,2024-02-10,L,F,LARGE",
    "2024-02-02,2024-02-11,L,F,")), ag_fill_refs)
  expect_equal("constructed animal_group fills missing source parts",
               as.numeric(identical(sort(levels(ag_fill_data$animal_group)),
                                    sort(c("F_LARGE", "F__UNKNOWN_")))), 1)

  # Value maps: the rewritten value replaces the original everywhere, so a
  # mapped-away value leaves NO level behind (the difference between a map and
  # a filter, which empties a level but keeps it). The "_UNKNOWN_" fill is a
  # usable key, since the maps run after the fill. The pairs do not chain:
  # LRG -> MED must not catch the animals XL -> LRG just produced, so LRG ends
  # up with two rows and MED with the one that started there.
  map_refs <- refs_for(with_base(
    animal_group_map = list(list(XL = "LRG"), list(LRG = "MED"), list(GIANT = "LRG")),
    intake_type_map  = list(list(`_UNKNOWN_` = "OTHER"))))
  map_data <- read_and_prepare_data(write_temp_csv(c(
    "intake_date,outcome_date,outcome_type,intake_type,animal_group",
    "2024-02-01,2024-02-10,L,STRAY,XL",
    "2024-02-02,2024-02-11,L,STRAY,XL",
    "2024-02-03,2024-02-12,L,,LRG")), map_refs)
  expect_equal("value map leaves no level behind for a mapped-away value",
               as.numeric(identical(sort(levels(map_data$animal_group)),
                                    c("LRG", "MED"))), 1)
  expect_equal("value map does not chain (XL -> LRG is not then LRG -> MED)",
               sum(map_data$animal_group == "LRG"), 2)
  expect_equal("value map key may be the _UNKNOWN_ fill",
               sum(map_data$intake_type == "OTHER"), 1)

  # Every configured pair is counted, a key that matched nothing included: an
  # absent key is legitimate (maps may name rare labels), so its zero count is
  # the user's only signal that a key is misspelled. Reported in the register,
  # and so in results.json.
  map_counts <- attr(map_data, "preparation")$mapped_animal_group
  expect_equal("value-map counts record every pair, zeros included",
               nrow(map_counts), 3)
  expect_equal("value-map counts record the rows each pair transformed",
               as.numeric(identical(map_counts$rows_mapped, c(2L, 1L, 0L))), 1)
  expect_equal("an unconfigured value map records no pairs",
               nrow(attr(fill_data, "preparation")$mapped_intake_type), 0)

  # Ordering: the maps run BEFORE the value filters, so a filter must list the
  # mapped value. Cutting "XL" here would keep both rows (nothing is called XL
  # by then); cutting "LRG" removes them, which is what pins the order.
  map_then_filter <- read_and_prepare_data(write_temp_csv(c(
    "intake_date,outcome_date,outcome_type,animal_group",
    "2024-02-01,2024-02-10,L,XL",
    "2024-02-02,2024-02-11,L,SML")),
    refs_for(with_base(animal_group_map = list(list(XL = "LRG")),
                       animal_group_filter_cut = list("LRG"))))
  expect_equal("value filters match the mapped values, not the raw ones",
               nrow(map_then_filter), 1)

  expect_error("value map configured without its column",
               read_and_prepare_data(write_temp_csv(c(
                 "intake_date,outcome_date,outcome_type",
                 "2024-02-01,2024-02-10,L")),
                 refs_for(with_base(animal_group_map = list(list(XL = "LRG"))))),
               "The animal_group_map setting is configured, but the column 'animal_group' does not exist")

  # The filled level is a real, analyzable stratum: detect_optional_columns
  # counts it, so Cox and the stratified KM include those rows instead of
  # silently dropping them (the old NA behavior).
  expect_equal("filled intake_type counts as an analyzable level",
               detect_optional_columns(fill_data, val_refs)$n_intake_types, 3)

  # A stray all-blank row (",,") is dropped with a count under BOTH
  # discard_bad_rows settings -- under the default false it previously
  # stopped the whole run as an invalid intake_date.
  blank_row_csv <- write_temp_csv(c(
    "intake_date,outcome_date,outcome_type",
    "2024-02-01,2024-02-10,L",
    ",,"))
  expect_equal("all-blank row dropped under default discard_bad_rows: false",
               nrow(read_and_prepare_data(blank_row_csv, val_refs)), 1)
  expect_equal("all-blank row dropped under discard_bad_rows: true",
               nrow(read_and_prepare_data(blank_row_csv, discard_refs)), 1)

  # Duplicate-stay removal: rows sharing (animal_id, intake_date, outcome_date)
  # collapse to their LAST occurrence (the presumed re-classification). A
  # different outcome_date is a genuine separate stay and survives; two blank
  # outcome dates compare equal and collapse too.
  dup_data <- read_and_prepare_data(write_temp_csv(c(
    "intake_date,outcome_date,outcome_type,animal_id",
    "2024-02-01,2024-02-01,L,A1",
    "2024-02-01,2024-02-01,N,A1",
    "2024-02-05,2024-02-09,L,A1",
    "2024-02-01,2024-02-01,L,A2",
    "2024-02-10,,,A3",
    "2024-02-10,,,A3")), val_refs)
  expect_equal("duplicate stays collapse to one row per (id, intake, outcome) triple",
               nrow(dup_data), 4)
  expect_equal("duplicate stays: the LAST row of a set is the one kept",
               as.numeric(dup_data$outcome_type[dup_data$animal_id == "A1" &
                            dup_data$intake_date == as.Date("2024-02-01")] == "N"), 1)

  # Without a supplied animal_id, auto-generated ids make every row its own
  # animal: identical rows are NOT collapsed (the check is a structural no-op).
  expect_equal("identical rows without animal_id are not collapsed",
               nrow(read_and_prepare_data(write_temp_csv(c(
                 "intake_date,outcome_date,outcome_type",
                 "2024-02-01,2024-02-01,L",
                 "2024-02-01,2024-02-01,L")), val_refs)), 2)

  # Overlapping stays (discard_overlapping_rows): two stays of the same animal
  # overlap when each begins strictly before the other ends; a stay beginning
  # the day another ends is a legitimate same-day departure-and-return and is
  # never flagged. Under the default false the run stops; under true the
  # shorter stay of each overlapping pair is dropped (blank outcome date =
  # longest possible stay; equal lengths drop the earlier file row) and the
  # survivors keep their original file order.
  overlap_csv <- write_temp_csv(c(
    "intake_date,outcome_date,outcome_type,animal_id",
    "2024-02-01,2024-02-10,L,A1",   # long stay: kept
    "2024-02-03,2024-02-06,L,A1",   # strictly inside the long stay: dropped
    "2024-02-10,2024-02-15,L,A1",   # starts the day the long stay ends: kept
    "2024-03-01,2024-03-03,L,A2",   # equal-length overlapping pair:
    "2024-03-02,2024-03-04,L,A2",   #   earlier file row dropped, this one kept
    "2024-04-01,,,A3",              # still in care (unbounded): kept
    "2024-04-05,2024-04-07,L,A3"))  # inside the open stay: dropped
  expect_error("overlapping stays stop under default discard_overlapping_rows: false",
               read_and_prepare_data(overlap_csv, val_refs),
               "row(s) overlap another stay of the same animal_id")
  overlap_refs <- refs_for(with_base(discard_overlapping_rows = TRUE))
  overlap_data <- read_and_prepare_data(overlap_csv, overlap_refs)
  expect_equal("overlap filter drops the shorter stay of each overlapping pair",
               nrow(overlap_data), 4)
  expect_equal("overlap survivors keep original file order",
               as.numeric(identical(format(overlap_data$intake_date),
                                    c("2024-02-01", "2024-02-10",
                                      "2024-03-02", "2024-04-01"))), 1)
  expect_error("non-logical discard_overlapping_rows",
               refs_for(with_base(discard_overlapping_rows = "yes")),
               "discard_overlapping_rows must be true or false")

  # Zero rows surviving the study-window filter must stop with a clear message,
  # not crash downstream ("attempt to set an attribute on NULL" was the old
  # failure in break_down_by_period).
  expect_error("empty study window stops gracefully",
               read_and_prepare_data(write_temp_csv(c(
                 "intake_date,outcome_date,outcome_type",
                 "2023-01-01,2023-02-01,L")), val_refs),
               "No records remain within the study window")

  # .outcome_state_colors fails loud on a code outside L/T/N (a programming
  # error if reached -- read_and_prepare_data pins the factor levels).
  expect_error("unknown outcome state code fails loud",
               .outcome_state_colors(c("L", "X")),
               "Unknown outcome state code(s): X")

  # Reference-level semantics (see .relevel_and_report in mlos_cox.R):
  # a NAMED reference that is absent from the data is a settings typo and must
  # stop the run, not silently reparametrize the model around a different
  # baseline; an invalid period_reference string likewise stops instead of the
  # old warn-and-use-OLDEST.
  expect_error("invalid period_reference string stops",
               refs_for(with_base(period_reference = "NEWST")),
               "period_reference must be 'OLDEST' or 'NEWEST' (found: NEWST)")
  expect_error("lowercase period_reference stops (values are case-sensitive)",
               refs_for(with_base(period_reference = "oldest")),
               "period_reference must be 'OLDEST' or 'NEWEST' (found: oldest)")

  # parametric_regression names a distribution or is false -- a typo and a bare
  # true both stop (the distribution must always be explicit); values are
  # case-sensitive like every other setting, so lowercase weibull stops too;
  # absent means FALSE.
  expect_error("misspelled parametric_regression stops",
               refs_for(with_base(parametric_regression = "WIEBULL")),
               "parametric_regression must be false or WEIBULL (found: WIEBULL)")
  expect_error("bare true parametric_regression stops",
               refs_for(with_base(parametric_regression = TRUE)),
               "parametric_regression must be false or WEIBULL (found: TRUE)")
  expect_error("lowercase weibull parametric_regression stops (values are case-sensitive)",
               refs_for(with_base(parametric_regression = "weibull")),
               "parametric_regression must be false or WEIBULL (found: weibull)")
  expect_equal("parametric_regression defaults to FALSE",
               as.numeric(identical(val_refs$parametric_regression, FALSE)), 1)

  # Settings-file typo protection: an unrecognized key must stop the run
  # rather than be silently ignored (the tool would otherwise behave as if
  # the misspelled setting were never given).
  expect_error("unrecognized settings key stops",
               refs_for(with_base(plot_stay_capp = 60)),
               "Unrecognized setting(s) in the settings file: plot_stay_capp")
  expect_error("out-of-order period_dates stop",
               define_periods(list(period_dates = c("2024-06-01", "2024-01-01"))),
               "period_dates must be strictly increasing")
  expect_error("duplicate period_dates stop",
               define_periods(list(period_dates = c("2024-01-01", "2024-01-01"))),
               "period_dates must be strictly increasing")
  expect_error("list-valued restricted_stay_cap stops",
               refs_for(list(period_dates = c("2024-01-01", "2024-06-01"),
                             restricted_stay_cap = c(100, 200))),
               "restricted_stay_cap must be a single positive integer")
  expect_error("list-valued intake_type_reference stops",
               refs_for(with_base(intake_type_reference = c("stray", "owner"))),
               "intake_type_reference must be a single value (found 2)")

  typo_refs <- refs_for(with_base(intake_type_reference = "Stray"))
  typo_data <- read_and_prepare_data(write_temp_csv(c(
    "intake_date,outcome_date,outcome_type,intake_type",
    "2024-02-01,2024-02-10,L,stray",
    "2024-02-02,2024-02-11,L,owner")), typo_refs)
  typo_refs <- detect_optional_columns(typo_data, typo_refs)
  expect_error("named-but-absent intake_type_reference stops",
               cox_regression_analysis(break_down_by_period(typo_data, typo_refs), typo_refs),
               "Intake type reference 'Stray' not found in the data (available: owner, stray)")

  # period_reference OLDEST/NEWEST is a POLICY resolved against the periods
  # that contain data (original pre-refactor semantics, restored). Period 1 is
  # empty here and period 3 is the most frequent, so OLDEST must land on
  # period 2 -- distinguishing oldest-with-data from both "period 1" and
  # "most frequent".
  ep_refs <- refs_for(list(
    period_dates = c("2024-01-01", "2024-02-01", "2024-03-01", "2024-04-01"),
    restricted_stay_cap = 100))
  ep_data <- read_and_prepare_data(write_temp_csv(c(
    "intake_date,outcome_date,outcome_type",
    "2024-02-01,2024-02-05,L",
    "2024-03-02,2024-03-06,L",
    "2024-03-10,2024-03-15,L",
    "2024-03-20,2024-03-24,L")), ep_refs)
  ep_refs <- detect_optional_columns(ep_data, ep_refs)
  ep_cox <- cox_regression_analysis(break_down_by_period(ep_data, ep_refs), ep_refs)
  expect_equal("empty period 1: Cox still runs",
               as.numeric(isTRUE(ep_cox$has_analysis)), 1)
  expect_equal("OLDEST resolves to oldest period with data (2), not most frequent (3)",
               as.numeric(ep_cox$cox_model$xlevels$period[1] == "Period_2"), 1)

  # Two periods defined but only one with data, and no other predictors: Cox
  # must skip cleanly (a single-level period factor used to crash coxph).
  op_refs <- refs_for(list(
    period_dates = c("2024-01-01", "2024-02-01", "2024-03-01"),
    restricted_stay_cap = 100))
  op_data <- read_and_prepare_data(write_temp_csv(c(
    "intake_date,outcome_date,outcome_type",
    "2024-02-05,2024-02-10,L")), op_refs)
  op_refs <- detect_optional_columns(op_data, op_refs)
  op_cox <- cox_regression_analysis(break_down_by_period(op_data, op_refs), op_refs)
  expect_equal("one period with data, no other predictors: Cox skipped, not crashed",
               as.numeric(isTRUE(op_cox$has_analysis)), 0)

  # Weibull unified companion with a period-only model: the main fit already
  # has no group terms, so it IS the unified fit and must be recognized as
  # such (same_as_main), not silently refit. The two formula strings used to
  # differ ("surv_obj ~ 1 + period" vs "surv_obj ~ period"), which made the
  # same_as_main branch unreachable and the worksheet repeat identical
  # numbers as a "distinct" unified block.
  if (requireNamespace("flexsurv", quietly = TRUE)) {
    pw_refs <- refs_for(list(period_dates = c("2024-01-01", "2024-02-01", "2024-03-01"),
                             restricted_stay_cap = 60,
                             parametric_regression = "WEIBULL"))
    pw_data <- read_and_prepare_data(write_temp_csv(c(
      "intake_date,outcome_date,outcome_type",
      "2024-01-02,2024-01-05,L",
      "2024-01-03,2024-01-10,L",
      "2024-01-05,2024-01-06,L",
      "2024-01-10,2024-01-22,L",
      "2024-01-15,2024-01-18,L",
      "2024-01-20,2024-02-02,L",
      "2024-02-02,2024-02-05,L",
      "2024-02-03,2024-02-12,L",
      "2024-02-05,2024-02-07,L",
      "2024-02-10,2024-02-24,L",
      "2024-02-15,2024-02-17,L",
      "2024-02-20,2024-02-28,L")), pw_refs)
    pw_refs <- detect_optional_columns(pw_data, pw_refs)
    invisible(capture.output(
      pw_cox <- cox_regression_analysis(break_down_by_period(pw_data, pw_refs), pw_refs)
    ))
    pw_uni <- pw_cox$weibull$crude
    expect_equal("period-only Weibull: crude fit recognized as the main fit",
                 as.numeric(isTRUE(pw_uni$same_as_main)), 1)
    expect_equal("period-only Weibull: crude shape equals main shape",
                 pw_uni$shape, pw_cox$weibull$shape)
  }

  # The starting-value retry is inert on a fit that works. This is the property
  # The grid now runs on every fit, not only after a failure, because a start
  # that stops early while reporting success is the commoner fault (see
  # .fit_weibull). What keeps that from re-baselining every number is
  # .WEIBULL_START_TOL: a start has to beat the default materially, and two
  # starts at the same optimum differ by about 1e-11 here, far under the bar.
  # So the inertness pinned below is still inertness, and it now says something
  # sharper than it did: not that the grid was skipped, but that it ran, found
  # nothing worth taking, and left the default's fit alone.
  # The outright failure the grid also exists for needs a particular data shape
  # -- 40 random synthetic draws did not reproduce it, and the real reproducer
  # is an Orange County subset rather than anything a fixture carries -- so the
  # recovery itself is still not pinned here.
  if (requireNamespace("flexsurv", quietly = TRUE)) {
    ri_refs <- refs_for(list(period_dates = c("2024-01-01", "2024-02-01", "2024-03-01"),
                             restricted_stay_cap = 60,
                             parametric_regression = "WEIBULL"))
    ri_lines <- "intake_date,outcome_date,outcome_type"
    for (i in seq_len(30)) {
      start <- as.Date("2024-01-02") + (i %% 25)
      ri_lines <- c(ri_lines, paste(format(start), format(start + 1L + (i %% 9L)), "L", sep = ","))
    }
    ri_data <- read_and_prepare_data(write_temp_csv(ri_lines), ri_refs)
    ri_refs <- detect_optional_columns(ri_data, ri_refs)
    ri_pd   <- break_down_by_period(ri_data, ri_refs)
    surv_obj <- .make_surv_obj(ri_pd)
    ri <- .fit_weibull("surv_obj ~ 1", ri_pd, environment())
    expect_equal("weibull retry: an ordinary fit succeeds on the default starts",
                 as.numeric(!inherits(ri$fit, "error")), 1)
    expect_equal("weibull retry: the grid finds nothing better, so the fit stands",
                 as.numeric(isTRUE(ri$retried)), 0)
  }

  # Crossed Weibull shape variants, which no fixture reaches: the four cases
  # that enable parametric_regression have at most TWO qualifying predictors, so
  # every variant there has a single "other" term and the crossed and additive
  # shape formulas are the same string. Three predictors is what makes the
  # crossing branch of .weibull_regression_analysis live, so it is built here.
  #
  # Deterministic rows rather than a seeded draw: the assertions are about which
  # formula was chosen and which rows the tables carry, and a fixed dataset
  # keeps a flexsurv version change from moving them.
  if (requireNamespace("flexsurv", quietly = TRUE)) {
    cs_settings <- list(period_dates = c("2024-01-01", "2024-02-01", "2024-03-01"),
                        restricted_stay_cap = 60,
                        animal_group_columns = "animal_size",
                        parametric_regression = "WEIBULL",
                        weibull_shape_crossing = TRUE)
    cs_header <- "intake_date,outcome_date,outcome_type,intake_type,animal_size"
    # One stay per (month, intake type, size, i), with a length that depends on
    # the cell, so the shapes have something to differ by. `per_cell` is how
    # many go in each intake x size combination, split over the two months, and
    # it has to clear .WEIBULL_CROSSING_MIN_EVENTS for the crossing to be
    # attempted at all -- 20 per month against a floor of 5.
    cs_rows <- function(sizes_by_intake, per_cell = 20L) {
      out <- character(0)
      for (m in c(1L, 2L)) {
        for (it in names(sizes_by_intake)) {
          for (sz in sizes_by_intake[[it]]) {
            for (i in seq_len(per_cell)) {
              start <- as.Date(sprintf("2024-%02d-01", m)) + (i %% 14L)
              los   <- 1L + ((i * (if (identical(sz, "BIG")) 2L else 1L) +
                              (if (identical(it, "OWNER")) 3L else 0L)) %% 11L)
              out <- c(out, paste(format(start), format(start + los), "L", it, sz, sep = ","))
            }
          }
        }
      }
      out
    }
    cs_variant_for <- function(lines, settings) {
      refs <- refs_for(settings)
      dat  <- read_and_prepare_data(write_temp_csv(c(cs_header, lines)), refs)
      refs <- detect_optional_columns(dat, refs)
      invisible(capture.output(
        cox <- cox_regression_analysis(break_down_by_period(dat, refs), refs)
      ))
      cox$weibull$shape_variants$period
    }

    # Every cell occupied: the crossed formula is the one used.
    cs_full <- cs_variant_for(cs_rows(list(STRAY = c("BIG", "SMALL"),
                                           OWNER = c("BIG", "SMALL"))), cs_settings)
    expect_equal("crossed shape: the period variant crosses the other two predictors",
                 as.numeric(grepl("shape(intake_type * animal_group)",
                                  cs_full$formula, fixed = TRUE)), 1)
    expect_equal("crossed shape: crossing recorded as used",
                 as.numeric(isTRUE(cs_full$shape_crossing$crossed)), 1)
    expect_equal("crossed shape: nested test against the additive shape formula reported",
                 as.numeric(!is.null(cs_full$shape_crossing$lr) &&
                            cs_full$shape_crossing$lr$df > 0), 1)
    # The crossed fit estimates an interaction per cell, but the shape table is
    # main effects only -- .insert_reference_rows has no slot for a product term,
    # and mlos_review recovers a level from the END of a term name, which an
    # interaction row would satisfy by accident.
    expect_equal("crossed shape: no interaction rows reach the shape table",
                 as.numeric(any(grepl(":", cs_full$shape_table$variable, fixed = TRUE))), 0)
    # They are published, just not there: the products go to a table of their
    # own, which is the whole fitted shape model minus what the main table
    # already holds. One per non-reference pairing, so 1 x 1 here.
    expect_equal("crossed shape: interaction rows are published in their own table",
                 nrow(cs_full$shape_interaction_table), 1)
    expect_equal("crossed shape: and every row there IS a product term",
                 as.numeric(all(grepl(":", cs_full$shape_interaction_table$variable,
                                      fixed = TRUE))), 1)
    expect_equal("crossed shape: the interaction table carries a ratio and an interval",
                 as.numeric(all(c("shape_ratio", "ci_lower", "ci_upper", "p_value") %in%
                                names(cs_full$shape_interaction_table))), 1)
    expect_equal("crossed shape: shape table still carries every other predictor's levels",
                 as.numeric(sum(cs_full$shape_table$variable %in%
                                c("intake_typeOWNER", "intake_typeSTRAY",
                                  "animal_groupBIG", "animal_groupSMALL"))), 4)
    # Own k is the baseline times the ratio, so the multiplication a reader
    # would do by hand is pinned against the column the fit publishes.
    cs_own <- cs_full$shape_table
    cs_est <- !is.na(cs_own$ci_lower)
    expect_equal("crossed shape: own k is the baseline times the level's ratio",
                 max(abs(cs_own$shape_own[cs_est] -
                         cs_full$shape_reference$k * cs_own$shape_ratio[cs_est])), 0,
                 tol = 1e-9)
    # And the interval is NOT the ratio's interval rescaled: it carries the
    # baseline's variance and the covariance too, so it must differ.
    expect_equal("crossed shape: own k's interval is not the ratio's rescaled",
                 as.numeric(any(abs(cs_own$shape_own_upper[cs_est] -
                                    cs_full$shape_reference$k *
                                    cs_own$ci_upper[cs_est]) > 1e-6)), 1)
    # A reference level's own shape is the baseline itself, interval included,
    # rather than a gap in an otherwise complete column.
    cs_ref <- !cs_est & !is.na(cs_own$shape_ratio)
    expect_equal("crossed shape: a reference level's own k is the baseline",
                 max(abs(cs_own$shape_own[cs_ref] - cs_full$shape_reference$k)), 0,
                 tol = 1e-12)

    # One combination absent (OWNER animals are never SMALL). Refused on the
    # count, which reads an absent combination as zero outcomes, so it never
    # reaches flexsurvreg to fail there as a singular matrix. Either way it must
    # cost the crossing and not the variant: the additive shape formula is
    # reported instead, with the reason recorded.
    cs_gap <- cs_variant_for(cs_rows(list(STRAY = c("BIG", "SMALL"),
                                          OWNER = "BIG")), cs_settings)
    expect_equal("crossed shape: an empty cell falls back rather than losing the variant",
                 as.numeric(isTRUE(cs_gap$has_analysis)), 1)
    expect_equal("crossed shape: fallback reported as not crossed",
                 as.numeric(isTRUE(cs_gap$shape_crossing$crossed)), 0)
    expect_equal("crossed shape: fallback records why",
                 as.numeric(!is.na(cs_gap$shape_crossing$fallback_reason)), 1)
    expect_equal("crossed shape: fallback reports the additive formula it used",
                 as.numeric(grepl("shape(intake_type) + shape(animal_group)",
                                  cs_gap$formula, fixed = TRUE)), 1)
    # An additive fit estimates no products, so the table is present and empty
    # rather than absent: the bundle loses a value only when the tool stops
    # computing one, and here there was nothing to compute.
    expect_equal("crossed shape: a fallback publishes an empty interaction table",
                 nrow(cs_gap$shape_interaction_table), 0)
    expect_equal("crossed shape: an absent cell is refused as zero outcomes",
                 as.numeric(grepl("at 0)", cs_gap$shape_crossing$fallback_reason,
                                  fixed = TRUE)), 1)

    # Every combination present, one of them thin: four outcomes against a
    # floor of five. This is the case the count guard exists for, and the one
    # the fit alone would not have refused -- four is enough for flexsurvreg to
    # return a shape, just not one worth reporting.
    cs_thin_rows <- c(cs_rows(list(STRAY = c("BIG", "SMALL"), OWNER = "BIG")),
                      cs_rows(list(OWNER = "SMALL"), per_cell = 2L))
    cs_thin <- cs_variant_for(cs_thin_rows, cs_settings)
    expect_equal("crossed shape: a thin cell falls back to the additive formula",
                 as.numeric(grepl("shape(intake_type) + shape(animal_group)",
                                  cs_thin$formula, fixed = TRUE)), 1)
    expect_equal("crossed shape: the thin-cell reason names the floor and the cell",
                 as.numeric(grepl("fewer than 5 outcomes", cs_thin$shape_crossing$fallback_reason,
                                  fixed = TRUE) &&
                            grepl("OWNER x SMALL at 4", cs_thin$shape_crossing$fallback_reason,
                                  fixed = TRUE)), 1)
    # And the floor is the only thing standing in the way: the same design with
    # the thin cell filled crosses.
    cs_filled <- cs_variant_for(c(cs_rows(list(STRAY = c("BIG", "SMALL"), OWNER = "BIG")),
                                  cs_rows(list(OWNER = "SMALL"), per_cell = 10L)),
                                cs_settings)
    expect_equal("crossed shape: the same design crosses once the cell clears the floor",
                 as.numeric(isTRUE(cs_filled$shape_crossing$crossed)), 1)

    # The default. Same fully occupied design, same three predictors, with
    # weibull_shape_crossing left out of the settings: the additive shape
    # formula is fitted, and nothing about it is reported as a refusal. The
    # distinction matters downstream, where a fallback disqualifies a variant
    # from the deck's shape recommendation and this does too, while a variant
    # with nothing to cross does not.
    cs_default_settings <- cs_settings
    cs_default_settings$weibull_shape_crossing <- NULL
    cs_default <- cs_variant_for(cs_rows(list(STRAY = c("BIG", "SMALL"),
                                              OWNER = c("BIG", "SMALL"))),
                                 cs_default_settings)
    expect_equal("crossed shape: off by default, so the shape formula is additive",
                 as.numeric(grepl("shape(intake_type) + shape(animal_group)",
                                  cs_default$formula, fixed = TRUE)), 1)
    expect_equal("crossed shape: the default is not recorded as crossed",
                 as.numeric(isTRUE(cs_default$shape_crossing$crossed)), 0)
    expect_equal("crossed shape: and not as a refusal either",
                 as.numeric(is.na(cs_default$shape_crossing$fallback_reason)), 1)
    expect_equal("crossed shape: the default says crossing was available",
                 as.numeric(isTRUE(cs_default$shape_crossing$applicable)), 1)
    expect_equal("crossed shape: the default says the setting declined it",
                 as.numeric(isFALSE(cs_default$shape_crossing$enabled)), 1)
    # No crossed fit was made, so there is no nested test to report.
    expect_equal("crossed shape: the default reports no crossing test",
                 as.numeric(is.null(cs_default$shape_crossing$lr)), 1)
  }

  # -----------------------------------------------------------------------
  # Entry-point script checks (mlos_run_complete.R)
  # -----------------------------------------------------------------------
  # These pin behavior of the run script itself, which fixtures cannot reach
  # because run_tests.R sources the analysis files directly. Both pin past
  # bugs: (a) an unrecognized CLI argument used to be skipped silently, so a
  # typo ran the analysis on the default files; (b) an error raised while the
  # log sinks were active used to either vanish into the log file or be
  # masked as "invalid connection" by the sink/connection teardown.

  # -----------------------------------------------------------------------
  # Filter invariance: cutting one stratum leaves the others untouched
  # -----------------------------------------------------------------------
  # Each stratum's KM/AJ/observation stats are computed from that stratum's
  # own rows, so filtering OUT one intake type must not move any result for
  # the intake types that remain. (Cox is deliberately not checked: it is a
  # joint model over all levels, so dropping one legitimately changes it --
  # the retained level survives there only as a phantom row, see the
  # value_filters fixture.) A dataset with three intake types is run whole and
  # again with TRANSFER cut; STRAY and OWNER must match bit-for-bit.
  cat("\n=== filter invariance (stratified results) ===\n")

  fi_intake <- Filter(function(s) identical(s$id, "intake"), stratifiers)[[1]]
  fi_csv <- write_temp_csv(c(
    "intake_date,outcome_date,outcome_type,intake_type",
    "2021-01-01,2021-01-05,L,STRAY",
    "2021-01-02,2021-01-10,T,STRAY",
    "2021-01-03,2021-01-08,N,STRAY",
    "2021-01-04,2021-01-20,L,STRAY",
    "2021-01-05,2021-01-07,L,OWNER",
    "2021-01-06,2021-01-16,T,OWNER",
    "2021-01-07,2021-01-12,N,OWNER",
    "2021-01-08,2021-02-01,L,OWNER",
    "2021-01-10,2021-01-11,L,TRANSFER",
    "2021-01-11,2021-01-25,T,TRANSFER",
    "2021-01-12,2021-01-14,N,TRANSFER",
    "2021-01-13,2021-02-10,L,TRANSFER"))

  fi_quiet <- function(expr) { capture.output(res <- expr); res }
  fi_run <- function(cut = NULL) {
    s <- list(period_dates = c("2021-01-01", "2021-04-01"), restricted_stay_cap = 60)
    if (!is.null(cut)) s$intake_filter_cut <- as.list(cut)
    refs <- refs_for(s)
    d    <- read_and_prepare_data(fi_csv, refs)
    refs <- detect_optional_columns(d, refs)
    pd   <- break_down_by_period(d, refs)
    list(refs  = refs,
         strat = stratified_km_analysis(pd, refs),
         aj    = aj_by_stratifier(pd, refs, fi_intake),
         obs   = calculate_period_observation_stats(pd, col = fi_intake$col))
  }
  fi_full <- fi_quiet(fi_run())
  fi_filt <- fi_quiet(fi_run(cut = "TRANSFER"))

  # The filter must actually have removed TRANSFER (guards against a vacuous
  # pass) while leaving the setup at three-then-two intake types.
  expect_equal("filter invariance: full run has all three intake types",
               fi_full$refs$n_intake_types, 3)
  expect_equal("filter invariance: filtered run has two intake types",
               fi_filt$refs$n_intake_types, 2)
  expect_equal("filter invariance: TRANSFER present whole, absent filtered",
               as.numeric(("TRANSFER" %in% fi_full$aj$strata) &&
                          !("TRANSFER" %in% fi_filt$aj$strata)), 1)

  fi_km_surv <- function(res, name, days) {
    fit <- res$strat[[fi_intake$km_result_key]]
    idx <- match(name, .strip_stratum_prefix(names(fit$strata)))
    .extract_stratum_survival(fit, idx, days)
  }
  fi_days <- 0:60
  fi_obs_row <- function(res, name) {
    row <- res$obs[res$obs$period_label == name, , drop = FALSE]
    rownames(row) <- NULL
    row
  }
  for (lvl in c("STRAY", "OWNER")) {
    expect_equal(paste0("filter invariance: KM survival unchanged for ", lvl),
                 as.numeric(isTRUE(all.equal(fi_km_surv(fi_full, lvl, fi_days),
                                             fi_km_surv(fi_filt, lvl, fi_days)))), 1)
    expect_equal(paste0("filter invariance: AJ CIF table unchanged for ", lvl),
                 as.numeric(isTRUE(all.equal(fi_full$aj$per_stratum[[lvl]]$cif_df,
                                             fi_filt$aj$per_stratum[[lvl]]$cif_df))), 1)
    expect_equal(paste0("filter invariance: per-stratum observation stats unchanged for ", lvl),
                 as.numeric(isTRUE(all.equal(fi_obs_row(fi_full, lvl),
                                             fi_obs_row(fi_filt, lvl)))), 1)
    expect_equal(paste0("filter invariance: intake rate unchanged for ", lvl),
                 as.numeric(isTRUE(all.equal(fi_full$strat$intake_rates[[fi_intake$id]][[lvl]],
                                             fi_filt$strat$intake_rates[[fi_intake$id]][[lvl]]))), 1)
  }

  cat("\n=== results.json precision ===\n")

  # Every number in results.json is written at .JSON_DIGITS significant
  # digits. This guards that setting from both sides: at .JSON_DIGITS the
  # values come back bit-for-bit, and at jsonlite's default they do not, so the
  # test cannot pass vacuously if the argument is dropped. The adversarial
  # constants are there for the same reason -- most of a bundle's doubles are
  # counts and short decimals that survive almost any encoding, and it was a
  # value like these that exposed digits = NA as 15 digits rather than full
  # precision.
  if (requireNamespace("jsonlite", quietly = TRUE) && !is.null(last_bundle)) {
    leaves <- suppressWarnings(as.numeric(unlist(last_bundle, use.names = FALSE)))
    leaves <- c(leaves[!is.na(leaves)],
                3.3805132312521902, 0.645161290322580977, pi, 1 / 3, exp(1) * 1e12)
    round_trip <- function(...) as.numeric(jsonlite::fromJSON(jsonlite::toJSON(leaves, ...)))
    expect_equal("results.json: full precision survives the round trip",
                 as.numeric(identical(round_trip(digits = .JSON_DIGITS), leaves)), 1)
    expect_equal("results.json: jsonlite's default would lose precision",
                 as.numeric(!identical(round_trip(), leaves)), 1)
    cat("  (", length(leaves), " doubles checked)\n", sep = "")
  }

  cat("\n=== stratifier registry wiring ===\n")

  # The registry's model_term field is what mlos_cox.R and mlos_excel_export.R
  # both read for their term/id lookups, so those two stay in step by
  # construction. What cannot be derived is the Cox predictor list, which names
  # its terms by hand; .assert_stratifier_model_wiring is what makes a
  # registry entry with no wiring there an error rather than a stratifier that
  # quietly never enters the model. Checked by adding a fourth stratifier and
  # confirming the guard refuses it, since a guard that never fires in the
  # suite is a guard nobody knows still works.
  expect_equal("stratifier wiring: the three known terms are accepted",
               as.numeric(isTRUE(.assert_stratifier_model_wiring(
                 c("period", "intake_type", "animal_group")))), 1)

  local({
    saved <- stratifiers
    on.exit(assign("stratifiers", saved, envir = globalenv()), add = TRUE)
    assign("stratifiers", c(saved, list(list(
      id = "breed", col = "breed_group", label = "Breed Group",
      km_result_key = "km_breed", suffix = "_by_breed_group",
      sheet_name = "By_Breed_Group", model_term = "breed_group",
      has_field = "has_breed_group", n_field = "n_breed_groups"
    ))), envir = globalenv())

    err <- tryCatch({
      .assert_stratifier_model_wiring(c("period", "intake_type", "animal_group"))
      NULL
    }, error = function(e) conditionMessage(e))
    expect_equal("stratifier wiring: a fourth stratifier with no predictor wiring is refused",
                 as.numeric(!is.null(err)), 1)
    expect_equal("stratifier wiring: the refusal names the unwired term",
                 as.numeric(!is.null(err) && grepl("breed_group", err, fixed = TRUE)), 1)
    # The derived lookups must have picked the newcomer up on their own; if they
    # had not, the guard above would be masking a second, separate gap.
    expect_equal("stratifier wiring: term/id lookups follow the registry unaided",
                 as.numeric(identical(unname(.stratifier_ids_by_model_term()[["breed_group"]]),
                                      "breed")), 1)
  })

  cat("\n=== probability-mass bins ===\n")

  # The edge rules, on the cases that decide them. Everything else about the
  # binning is checked against real fits in the fixture loop above; what is
  # here is the arithmetic that picks the boundaries, where the awkward inputs
  # are easier to state than to find in a dataset.
  local({
    expect_equal("mass bins: width 0 is the off switch",
                 as.numeric(is.null(.mass_bin_edges(0, 58, 365))), 1)
    # The bin holding plot_stay_cap is kept whole, so 58 is covered by (56,63]
    # and the tail runs from there.
    same <- function(actual, expected) as.numeric(identical(as.numeric(actual),
                                                            as.numeric(expected)))
    expect_equal("mass bins: the bin containing plot_stay_cap is kept whole",
                 same(.mass_bin_edges(7, 58, 365),
                      c(0, 7, 14, 21, 28, 35, 42, 49, 56, 63, 365)), 1)
    # With the two caps equal there is no tail to speak of, and the last full
    # width would leave a one-day sliver at 364. It is absorbed instead.
    expect_equal("mass bins: no sliver at the right-hand end",
                 same(tail(.mass_bin_edges(7, 365, 365), 2), c(357, 365)), 1)
    expect_equal("mass bins: a width wider than the cap gives one interval",
                 same(.mass_bin_edges(400, 58, 365), c(0, 365)), 1)
    expect_equal("mass bins: labels name the intervals they bound",
                 as.numeric(identical(.mass_bin_labels(c(0, 7, 365)),
                                      c("(0,7]", "(7,365]"))), 1)
    # Read as step functions: an edge past the end of the grid takes the last
    # fitted value rather than falling off it, which is what lets the tail edge
    # sit at the cap while a curve stops short of it.
    cum <- cbind(A = c(0, 0.4, 0.6, 0.6))
    masses <- .cumulative_bin_masses(0:3, cum, c(0, 1, 3, 10))
    expect_equal("mass bins: a cumulative grid differences into its intervals",
                 max(abs(as.numeric(masses[, "A"]) - c(0.4, 0.2, 0))), 0)
  })

  cat("\n=== output family naming ===\n")

  # A family's filename stem is built from the three fields that identify it:
  # its manifest kind, "_unified" when the scope is pooled, and the variant when
  # that is anything but the default "lines" (the two stack plots). Not a
  # cosmetic rule: the companion filenames are derived from the survival plot's
  # name by substituting .KM_FILENAME_TOKEN, and the archiving fallback matches
  # names by pattern, so a stem that goes its own way breaks two mechanisms
  # quietly rather than one loudly. The survival family was the only violation
  # (km_curve_unified and km_stratified) until it was renamed, which is why this
  # is asserted over the whole table rather than trusted to review.
  local({
    offenders <- character(0)
    for (family in .OUTPUT_FAMILIES) {
      expected <- family$kind
      if (identical(family$scope, "unified")) expected <- paste0(expected, "_unified")
      if (!is.null(family$variant) && !identical(family$variant, "lines")) {
        expected <- paste0(expected, "_", family$variant)
      }
      if (!identical(family$stem, expected)) {
        offenders <- c(offenders, paste0(family$stem, " (expected ", expected, ")"))
      }
    }
    if (length(offenders) > 0) cat("  offenders:", paste(offenders, collapse = ", "), "\n")
    expect_equal("output families: every stem is its kind, plus _unified when pooled",
                 length(offenders), 0)
    # And the token the companions substitute must actually appear in the
    # survival family's stems, or the substitution silently returns the name
    # unchanged and two families would write to one file.
    survival_stems <- vapply(Filter(function(f) identical(f$kind, "km_survival"),
                                    .OUTPUT_FAMILIES),
                             function(f) f$stem, character(1))
    expect_equal("output families: the companion token appears in every survival stem",
                 as.numeric(length(survival_stems) > 0 &&
                              all(grepl(.KM_FILENAME_TOKEN, survival_stems, fixed = TRUE))), 1)
  })

  cat("\n=== collation order ===\n")

  # Stratum order is the byte order of the level labels, and byte order is only
  # what sorting gives under the C locale. Any UTF-8 locale collates punctuation
  # ahead of letters, which moves the "_UNKNOWN_" fill from last to first among
  # upper-case labels and swaps composite animal_group values against each
  # other. That reorders plot colors, CSV columns, and worksheet columns, and
  # breaks the Cox frequency tie the other way, so mlos_common.R pins
  # LC_COLLATE. Checked here as a setting and as behaviour, because the pin is
  # one line with nothing else pointing at it.
  expect_equal("collation: LC_COLLATE is pinned to C",
               as.numeric(identical(Sys.getlocale("LC_COLLATE"), "C")), 1)

  fill_labels <- c("SMALL", "_UNKNOWN_", "LARGE")
  expect_equal("collation: the _UNKNOWN_ fill sorts after upper-case labels",
               as.numeric(identical(levels(factor(fill_labels)),
                                    c("LARGE", "SMALL", "_UNKNOWN_"))), 1)

  composite_labels <- c("F__UNKNOWN_", "F_LARGE")
  expect_equal("collation: composite group labels sort by byte",
               as.numeric(identical(sort(composite_labels),
                                    c("F_LARGE", "F__UNKNOWN_"))), 1)

  # The pin has to survive a hostile ambient locale, which is the case that
  # actually bites: a shell exporting LANG. Move collation away, confirm the
  # order really does flip (so the check has teeth), then re-source the file
  # that pins it and confirm it comes back. mlos_common.R defines constants and
  # functions only, so sourcing it twice changes nothing else.
  suppressWarnings(Sys.setlocale("LC_COLLATE", "C.UTF-8"))
  # Whether that took is not what Sys.setlocale reports: an exported LC_ALL
  # overrides LC_COLLATE and the call still returns the name it was given. The
  # order itself is the only honest signal, so ask it.
  if (identical(levels(factor(fill_labels))[1], "_UNKNOWN_")) {
    source(file.path(project_root, "mlos_common.R"))
    expect_equal("collation: sourcing mlos_common.R restores the C order",
                 as.numeric(identical(Sys.getlocale("LC_COLLATE"), "C") &&
                              identical(levels(factor(fill_labels)),
                                        c("LARGE", "SMALL", "_UNKNOWN_"))), 1)
  } else {
    suppressWarnings(Sys.setlocale("LC_COLLATE", "C"))
    cat("  [SKIP] collation: no reordering locale reachable here",
        "(C.UTF-8 missing, or LC_ALL pins collation)\n")
  }

  cat("\n=== release metadata ===\n")

  # One repository, one tag, one archive, so one version number. Three files
  # declare it and nothing else holds them together, which is exactly the drift
  # a citation cannot survive: the pair a reader checks is the DOI and the
  # version a run log reported.
  citation_file <- file.path(project_root, "CITATION.cff")
  expect_equal("release: CITATION.cff exists",
               as.numeric(file.exists(citation_file)), 1)
  if (file.exists(citation_file)) {
    cff <- yaml::read_yaml(citation_file)
    expect_equal("release: CITATION.cff version matches MLOS_VERSION",
                 as.numeric(identical(cff$version, MLOS_VERSION)), 1)
    expect_equal("release: CITATION.cff carries a release date",
                 as.numeric(grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$",
                                  as.character(cff$`date-released`))), 1)
  }

  pyproject <- file.path(project_root, "pyproject.toml")
  py_version <- sub('^version *= *"([^"]*)".*$', "\\1",
                    grep('^version *= *"', readLines(pyproject, warn = FALSE),
                         value = TRUE)[1])
  expect_equal("release: pyproject.toml version matches MLOS_VERSION",
               as.numeric(identical(py_version, MLOS_VERSION)), 1)

  # The console log is where a reader of a saved run meets the version, so the
  # header has to carry it rather than merely the constant existing.
  header_line <- grep("MLOS Length of Stay Tool",
                      readLines(file.path(project_root, "mlos_run_complete.R"),
                                warn = FALSE), value = TRUE)[1]
  expect_equal("release: log header prints the version",
               as.numeric(grepl("MLOS_VERSION", header_line, fixed = TRUE)), 1)

  cat("\n=== entry-point script checks ===\n")

  rscript_bin <- file.path(R.home("bin"), "Rscript")
  run_script  <- file.path(project_root, "mlos_run_complete.R")
  run_entry_point <- function(...) {
    # system2 goes through a shell, so every path argument needs shQuote
    # (the project path contains spaces).
    suppressWarnings(system2(rscript_bin, c(shQuote(run_script), ...),
                             stdout = TRUE, stderr = TRUE))
  }

  cli_out <- run_entry_point("--setting", "typo.yaml")
  expect_equal("CLI: unrecognized argument is rejected with usage",
               as.numeric(any(grepl("Unrecognized argument", cli_out, fixed = TRUE))), 1)

  err_out <- run_entry_point("--settings", shQuote(file.path(tempdir(), "no_such_settings.yaml")),
                             "--results",  shQuote(file.path(tempdir(), "mlos_entry_point_check")))
  expect_equal("run script: real error reaches the console, not the log",
               as.numeric(any(grepl("Settings file not found", err_out, fixed = TRUE))), 1)
  expect_equal("run script: error not masked by 'invalid connection'",
               as.numeric(any(grepl("invalid connection", err_out, fixed = TRUE))), 0)
  invisible(NULL)
}

# A --prefix run is fixtures-only: the settings/data-validation and
# entry-point checks belong to the full suite and are skipped; the summary
# and exit status below run either way.
if (nzchar(case_prefix)) {
  cat("\n(--prefix ", case_prefix,
      ": settings-validation and entry-point checks skipped)\n", sep = "")
} else {
  run_guarded("suite checks aborted", run_suite_checks())
}

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------

if (nzchar(only_filter) && !.only_matched) {
  cat("\n--only \"", only_filter, "\" matched no check.\n", sep = "")
  if (!interactive()) quit(save = "no", status = 1)
}

cat("\n=======================================================================\n")
summary_line <- sprintf("SUMMARY: %d passed, %d failed", .n_pass, .n_fail)
if (.n_error > 0) {
  summary_line <- sprintf("%s (%d of them stopped)", summary_line, .n_error)
}
cat(summary_line, "\n", sep = "")
if (golden_environment_differs && .n_fail > 0) {
  cat("This run's package versions are not the goldens'; see the golden environment section.\n")
}
cat("=======================================================================\n")

if (!interactive()) {
  quit(save = "no", status = if (.n_fail > 0) 1 else 0)
}
