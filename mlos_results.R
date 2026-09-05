# mLOS - Results bundle: every reported number, computed once
# =======================================================================
#
# The boundary between producing results and displaying them. Everything a
# report shows is computed here (or in the analysis modules this calls) and
# handed on as plain named matrices and lists; the Excel writer, the JSON
# export, and the test suite are all consumers of the same values, so no two
# of them can disagree about a number.
#
# Nothing in this file knows about worksheets, styles, row positions, or
# section titles. Nothing in mlos_excel_export.R computes.
#
# THE COMPLETENESS CONTRACT. results.json is read downstream to build reports
# and slide decks, so what the bundle omits is what those cannot show. Two
# rules follow:
#
#   1. The JSON is a superset of the workbook, by construction rather than by
#      discipline: the Excel writer reads the bundle and computes nothing, and
#      mlos_render.R rebuilds the whole workbook from a saved results.json
#      alone (the suite requires the two to match cell for cell). Dropping a
#      section from the Excel therefore never removes it from the JSON; it
#      only stops one consumer from showing it.
#   2. Every computed value reaches one of two places: the bundle, or a plot
#      companion CSV described by the `outputs` manifest. The manifest is the
#      link for the curve day grids, which stay CSV-only on purpose -- they are
#      bulk, they are what the CSVs exist for, and a consumer that wants them
#      is pointed at the file, told what its columns mean and how its summary
#      row follows from its grid. Everything else belongs here. A value is lost
#      only when the pipeline stops computing it, never because some particular
#      consumer had no room for it; that is why `data_preparation` and
#      `settings$presentation` are carried although no report shows them today.
#
# The bundle is assembled before anything is rendered, so the rendering step
# takes its summary values from here rather than deriving them a second time.
# The one exception is the output manifest, which records what rendering wrote
# and so is attached afterwards; see attach_output_manifest.
#
# Uses .stratum_levels_present, .total_window_days, .poisson_rate_ci,
# .binom_prop_ci, .cif_normalized_rmean, emitted_outputs (mlos_common.R);
# calculate_period_observation_stats, calculate_daily_mean_total_in_care_days,
# calculate_period_flow_metrics, calculate_unified_stay_counts,
# .stratum_outcome_matrices (mlos_data.R); stratum_km_summary,
# stratum_census_aggregates (mlos_km.R).

# Look up one value per period label from a metric data frame, by name rather
# than position: the metric functions and the label vector are built
# independently, so nothing guarantees their row orders match. An empty period
# has no row, hence the [[1L]] form, which yields NA rather than erroring.
.period_lookup <- function(values, label_col, period_labels) {
  lookup <- setNames(values, as.character(label_col))
  sapply(period_labels, function(lbl) lookup[lbl][[1L]])
}

# Observation counts, census, and flow metrics per stratum, as one matrix with
# a row per measure and a column per label. Values come from the same
# calculate_* functions used by the console summary, so the two reports cannot
# drift apart. For non-period cols, days_lookup and window_days carry the
# whole-window denominator (the per-subset fallbacks inside the three
# functions only work for periods).
#
# duration_days leads: the denominator in days behind each column's census and
# daily-rate figures. days_lookup already holds exactly this per-column value,
# the period's own duration when grouping by period and the whole study window
# (identical across columns) otherwise.
.build_stratum_observation_matrix <- function(period_data, labels, days_lookup,
                                              col = "period_label", window_days = NULL) {
  obs_stats <- calculate_period_observation_stats(period_data, labels, days_lookup, col = col)
  stat_cols <- c(
    total_observations            = "total_observations",
    events                        = "events",
    censored                      = "censored",
    left_truncated                = "left_truncated",
    right_censored                = "right_censored",
    capped_at_restricted_stay_cap = "capped_at_rmean",
    mean_days_at_risk             = "mean_days_at_risk",
    total_animal_days             = "total_animal_days",
    mean_census_inventory         = "mean_census"
  )
  obs_matrix <- t(as.matrix(obs_stats[, stat_cols]))
  rownames(obs_matrix) <- names(stat_cols)
  colnames(obs_matrix) <- labels

  daily_mean_df <- calculate_daily_mean_total_in_care_days(period_data, col = col,
                                                           window_days = window_days)
  flow_df <- calculate_period_flow_metrics(period_data, col = col, window_days = window_days)

  rbind(
    duration_days = as.numeric(days_lookup[labels]),
    obs_matrix,
    total_in_care_days_sum        = .period_lookup(daily_mean_df$total_in_care_days_sum,
                                                   daily_mean_df$period_label, labels),
    daily_mean_total_in_care_days = .period_lookup(daily_mean_df$daily_mean_total_in_care_days,
                                                   daily_mean_df$period_label, labels),
    total_intakes       = .period_lookup(flow_df$total_intakes,       flow_df$period_label, labels),
    total_outcomes      = .period_lookup(flow_df$total_outcomes,      flow_df$period_label, labels),
    mean_daily_intakes  = .period_lookup(flow_df$mean_daily_intakes,  flow_df$period_label, labels),
    mean_daily_outcomes = .period_lookup(flow_df$mean_daily_outcomes, flow_df$period_label, labels)
  )
}

# Every measure of one stratifying dimension: the whole content of a By_Period
# / By_All / By_Intake_Type / By_Animal_Group report, as named matrices with
# one column per label.
#
# Measure sets are deterministic functions of the FULL dataset (outcome rows
# come from all event rows, never from what one stratum happened to observe),
# so the same dataset yields the same rows in the same order for every
# stratifier. That is what lets a consumer put every dimension on the same
# lines and compare columns across them.
#
# Returns a list whose elements are either a matrix or NULL when the
# underlying analysis was not available:
#   observations        always present; duration_days first
#   outcomes/mix/incidence  NULL together when no classified events exist
#   km                  always present; all rows, estimates and bounds
#   census              always present
#   aj_final_cif / aj_restricted_mean / aj_rmtl / aj_window   NULL together
#                       without AJ; aj_window carries the per-stratum horizon
#                       the first two are measured against
#   ci                  always present; estimate/lower/upper triplets
compute_stratum_measures <- function(period_data, col, labels, km_results,
                                     aj_stratum_results, days_lookup, window_days = NULL) {
  obs_matrix <- .build_stratum_observation_matrix(period_data, labels, days_lookup,
                                                  col = col, window_days = window_days)

  total_animal_days <- as.numeric(obs_matrix["total_animal_days", ])
  names(total_animal_days) <- labels
  events_overall <- as.numeric(obs_matrix["events", ])
  names(events_overall) <- labels

  outcomes <- .stratum_outcome_matrices(period_data, labels, col, total_animal_days,
                                        events_overall)
  have_outcome_stats <- !is.null(outcomes)

  # Validated as a positive integer in extract_references; no fallback needed.
  km_cap <- km_results$restricted_stay_cap
  km_matrix <- stratum_km_summary(period_data, col, labels, km_cap)

  mean_daily_intakes <- as.numeric(obs_matrix["mean_daily_intakes", ])
  census_matrix <- stratum_census_aggregates(
    km_summary            = km_matrix,
    mean_daily_intakes    = mean_daily_intakes,
    mean_census_inventory = as.numeric(obs_matrix["mean_census_inventory", ]),
    daily_in_care_days    = as.numeric(obs_matrix["daily_mean_total_in_care_days", ]),
    labels                = labels
  )

  # The resident-view rows ride along on the KM matrix only far enough to reach
  # the census aggregates, which is their reporting home. Dropping them here
  # keeps them out of the KM block, where sitting beside km_median_los would
  # invite reading them as intake-cohort figures: the median stay of an arriving
  # animal, the median tenure of one currently in care, and the further stay
  # that one expects are three different quantities, and on skewed strata they
  # differ by a lot.
  km_matrix <- km_matrix[setdiff(rownames(km_matrix), RESIDENT_VIEW_ROWS), ,
                         drop = FALSE]

  # The stratified AJ analysis computes for every dimension that has any level
  # at all, so its per-stratum results are simply used; there is no case left
  # where this layer has to fit an AJ curve of its own.
  aj_per_stratum <- if (!is.null(aj_stratum_results) && isTRUE(aj_stratum_results$has_analysis))
                      aj_stratum_results$per_stratum else NULL
  valid_aj_available <- !is.null(aj_per_stratum) && length(aj_per_stratum) > 0 &&
    any(sapply(aj_per_stratum, function(x) isTRUE(x$has_analysis)))

  # One value per label from a named vector, in label order, with anything
  # missing or empty flattened to NA.
  metric_row <- function(values_named) {
    sapply(labels, function(lbl) {
      v <- values_named[[lbl]]
      if (is.null(v) || length(v) == 0 || is.na(v)) return(NA_real_)
      as.numeric(v)
    })
  }

  # Estimate/lower/upper triplets, gathered rather than sitting beside their
  # estimates: consumers that show them all in one block keep the estimate
  # sections narrow. Order mirrors the measure sections above (observation-block
  # rates, outcome mix, incidence rates, KM block, expected census, then the AJ
  # blocks appended below). KM and AJ bounds are the ready-made intervals of the
  # fits; the count-based bounds are exact Poisson (rates) and exact binomial
  # (proportions) intervals; the expected-census bounds are an INDICATIVE
  # delta-method interval (see below). The added assumptions of all three are
  # stated in math methods 8.2. The AJ restricted means carry no CI (a ratio of
  # correlated CIF estimates with no ready-made interval), so they have no
  # triplet here.
  ci_rows <- list()
  add_ci_triplet <- function(name, est, bounds) {
    ci_rows[[name]] <<- est
    ci_rows[[paste0(name, "_ci_lower")]] <<- bounds[1, ]
    ci_rows[[paste0(name, "_ci_upper")]] <<- bounds[2, ]
  }
  per_label <- function(f) vapply(seq_along(labels), f, numeric(2))

  # Observation block: fraction capped (binomial over the stratum's rows) and
  # the daily intake/outcome rates (Poisson counts over the window days).
  days_vec  <- as.numeric(days_lookup[labels])
  capped_n  <- as.numeric(obs_matrix["capped_at_restricted_stay_cap", ])
  total_n   <- as.numeric(obs_matrix["total_observations", ])
  intake_n  <- as.numeric(obs_matrix["total_intakes", ])
  outcome_n <- as.numeric(obs_matrix["total_outcomes", ])
  add_ci_triplet("fraction_capped",
                 ifelse(total_n > 0, capped_n / total_n, NA_real_),
                 per_label(function(i) .binom_prop_ci(capped_n[i], total_n[i])))
  add_ci_triplet("mean_daily_intakes",
                 mean_daily_intakes,
                 per_label(function(i) .poisson_rate_ci(intake_n[i], days_vec[i])))
  add_ci_triplet("mean_daily_outcomes",
                 as.numeric(obs_matrix["mean_daily_outcomes", ]),
                 per_label(function(i) .poisson_rate_ci(outcome_n[i], days_vec[i])))

  # Outcome mix (binomial within the completed-outcome total) and incidence
  # rates (Poisson events over animal-days, on the per-100 scale). Estimates
  # restate the mix/incidence matrices computed above.
  if (have_outcome_stats) {
    for (outcome in outcomes$outcome_levels) {
      idx <- which(outcomes$outcome_levels == outcome)
      ejk <- as.numeric(outcomes$counts[idx, ])
      add_ci_triplet(paste0("outcome_mix_", outcome),
                     outcomes$mix[paste0("outcome_mix_", outcome), ],
                     per_label(function(i) .binom_prop_ci(ejk[i], outcomes$totals[i])))
    }
    add_ci_triplet("incidence_overall_per_100_animal_days",
                   outcomes$incidence["incidence_overall_per_100_animal_days", ],
                   per_label(function(i) .poisson_rate_ci(events_overall[i], total_animal_days[i])) * 100)
    for (outcome in outcomes$outcome_levels) {
      idx <- which(outcomes$outcome_levels == outcome)
      ejk <- as.numeric(outcomes$counts[idx, ])
      add_ci_triplet(paste0("incidence_", outcome, "_per_100_animal_days"),
                     outcomes$incidence[paste0("incidence_", outcome, "_per_100_animal_days"), ],
                     per_label(function(i) .poisson_rate_ci(ejk[i], total_animal_days[i])) * 100)
    }
  }

  # KM block: bounds captured with the per-stratum fits.
  for (nm in c("km_median_los", "km_median_los_ci_lower", "km_median_los_ci_upper",
               "km_p90_los", "km_p90_los_ci_lower", "km_p90_los_ci_upper",
               "km_restricted_mean", "km_restricted_mean_ci_lower",
               "km_restricted_mean_ci_upper",
               "km_still_in_care_at_cap", "km_still_in_care_at_cap_ci_lower",
               "km_still_in_care_at_cap_ci_upper")) {
    ci_rows[[nm]] <- km_matrix[nm, ]
  }

  # Census-aggregates block: an INDICATIVE interval for the expected census
  # only. L = rate x RMST is a product of two estimates; on the log scale a
  # first-order delta method gives var(log L) ~= 1/N_intakes +
  # (se_RMST/RMST)^2, ASSUMING the two factors are independent. We do not
  # believe they are: they are likely positively correlated, which would
  # widen the true interval (math methods 8.2); a joint treatment is left
  # for future versions. The other census aggregates carry no interval.
  predicted_census <- as.numeric(census_matrix["expected_census", ])
  rmean_est   <- as.numeric(km_matrix["km_restricted_mean", ])
  rmean_se_v  <- as.numeric(km_matrix["km_restricted_mean_se", ])
  log_var     <- ifelse(intake_n > 0 & rmean_est > 0 & !is.na(rmean_se_v),
                        1 / intake_n + (rmean_se_v / rmean_est)^2, NA_real_)
  census_half <- 1.96 * sqrt(log_var)
  add_ci_triplet("expected_census",
                 predicted_census,
                 rbind(predicted_census * exp(-census_half),
                       predicted_census * exp(census_half)))

  aj_ci_rows <- list()
  aj_final_cif <- NULL
  aj_restricted_mean <- NULL
  aj_rmtl <- NULL
  aj_window <- NULL

  if (valid_aj_available) {
    # The AJ row set comes from the full dataset's event rows (outcome_levels
    # above), NOT from the union of per-stratum outcome_states, so every
    # stratifier carries identical AJ rows even if one stratum never saw an
    # outcome type (its cell is then NA). The two sets coincide whenever every
    # event row lands in a stratum whose AJ fit ran, which subsetting by a
    # complete, NA-free column guarantees.
    # "Any" is prepended (not a real outcome code - see compute_aj_cif_results in
    # mlos_aj.R, which only ever derives outcome_states from observed
    # outcome_type values) so the cif_Any/aj_final_cif_Any row is computed by the
    # same loop as the per-outcome rows, ahead of them to match prior row order.
    outcome_levels <- if (have_outcome_stats) outcomes$outcome_levels else character(0)
    all_outcomes <- c("Any", outcome_levels)

    # Last defined value of one cif_df column for one stratum: the CIF (or CI
    # bound) at the end of that stratum's day grid. NA when the stratum's AJ
    # fit didn't run or never saw the column's outcome.
    last_cif_value <- function(lbl, col_name) {
      res <- aj_per_stratum[[lbl]]
      if (is.null(res) || !isTRUE(res$has_analysis) || !col_name %in% names(res$cif_df)) return(NA_real_)
      vals <- res$cif_df[[col_name]]
      vals <- vals[!is.na(vals)]
      if (length(vals) == 0) return(NA_real_)
      tail(vals, 1)
    }

    cif_rows <- list()
    rmean_rows <- list()

    for (outcome in all_outcomes) {
      col_name <- paste0("cif_", outcome)
      final_vals <- sapply(labels, last_cif_value, col_name)
      rmean_vals <- sapply(labels, function(lbl) {
        res <- aj_per_stratum[[lbl]]
        if (is.null(res) || !isTRUE(res$has_analysis) || !col_name %in% names(res$cif_df)) return(NA_real_)
        .cif_normalized_rmean(res$cif_df[[col_name]])
      })
      cif_rows[[paste0("aj_final_cif_", outcome)]] <- metric_row(as.list(final_vals))
      rmean_rows[[paste0("aj_restricted_mean_", outcome)]] <- metric_row(as.list(rmean_vals))

      # The bounds are the pointwise 95% CI of the CIF at the same final day
      # ("Any" uses the complement of the in-care state's bounds; see
      # compute_aj_cif_results).
      aj_ci_rows[[paste0("aj_final_cif_", outcome)]] <- metric_row(as.list(final_vals))
      aj_ci_rows[[paste0("aj_final_cif_", outcome, "_ci_lower")]] <-
        metric_row(as.list(sapply(labels, last_cif_value, paste0("ci_lower_", outcome))))
      aj_ci_rows[[paste0("aj_final_cif_", outcome, "_ci_upper")]] <-
        metric_row(as.list(sapply(labels, last_cif_value, paste0("ci_upper_", outcome))))
    }

    aj_final_cif <- do.call(rbind, cif_rows)
    aj_restricted_mean <- do.call(rbind, rmean_rows)

    # Restricted mean days by state (see compute_aj_cif_results): the in-care
    # row is the RMST (identical to km_restricted_mean above), the departed
    # rows are the competing-risks RMTL per outcome, and the rows are
    # additive to the cap (In_Care + Any = cap).
    rmtl_value <- function(lbl, state, field) {
      res <- aj_per_stratum[[lbl]]
      if (is.null(res) || !isTRUE(res$has_analysis) || is.null(res$rmtl)) return(NA_real_)
      i <- match(state, res$rmtl$state)
      if (is.na(i)) return(NA_real_)
      res$rmtl[[field]][i]
    }
    rmtl_states <- c(list(aj_rmst_stay = "(s0)", aj_rmtl_Any = "Any"),
                     setNames(as.list(outcome_levels), paste0("aj_rmtl_", outcome_levels)))
    rmtl_rows <- list()
    for (row_name in names(rmtl_states)) {
      st  <- rmtl_states[[row_name]]
      est <- metric_row(as.list(sapply(labels, rmtl_value, st, "rmean")))
      rmtl_rows[[row_name]] <- est
      aj_ci_rows[[row_name]] <- est
      aj_ci_rows[[paste0(row_name, "_ci_lower")]] <-
        metric_row(as.list(sapply(labels, rmtl_value, st, "ci_lower")))
      aj_ci_rows[[paste0(row_name, "_ci_upper")]] <-
        metric_row(as.list(sapply(labels, rmtl_value, st, "ci_upper")))
    }
    aj_rmtl <- do.call(rbind, rmtl_rows)

    # The horizon the two AJ blocks above are measured against: each stratum's
    # own last fitted time (max_time in compute_aj_cif_results). Callers leave
    # it ragged on purpose, so it differs from column to column, and every
    # aj_final_cif and aj_restricted_mean value is "by the end of this
    # stratum's window". Reading those rows across strata means knowing it,
    # and the workbook, which shows the estimates but not the horizon, is not
    # where it can be found. The RMTL block is the exception: it runs to the
    # restricted stay cap instead, the same for every column, and is in
    # settings.
    aj_window <- rbind(aj_analysis_window_days = metric_row(as.list(
      sapply(labels, function(lbl) {
        res <- aj_per_stratum[[lbl]]
        if (is.null(res) || !isTRUE(res$has_analysis)) return(NA_real_)
        res$max_time
      })
    )))
  }

  # The conditional outcome mix read at the three resident-tenure statistics,
  # the same three the census block reports and the remaining-LOS curve is
  # already read at. It answers what the curves cannot be read off by eye: for
  # an animal that has been here as long as the median resident, which way is
  # it going to leave.
  #
  # Here rather than in a consumer because the numbers are a day grid's rows,
  # and that grid is CSV-only. A report wanting these would have to open
  # aj_cif_unified.csv and reproduce the day convention, which is what
  # .grid_value_at exists to keep in one place: the mix and the remaining-LOS
  # figure beside it name the same day, and both name the day a vertical line
  # at that tenure crosses.
  #
  # The columns of one tenure's rows sum to less than 1. The shortfall is the
  # stays still in care when the AJ window closes, which is aj_window above,
  # and no consumer needs it stored: it is one minus a sum of numbers already
  # here.
  aj_condrem_at_tenure <- NULL
  if (valid_aj_available) {
    tenure_rows <- c(median_tenure = "per_resident_past_days_restricted_median",
                     mean_tenure   = "per_resident_past_days",
                     p90_tenure    = "per_resident_past_days_restricted_p90")
    condrem_at <- function(lbl, outcome, tenure_row) {
      res <- aj_per_stratum[[lbl]]
      if (is.null(res) || !isTRUE(res$has_analysis)) return(NA_real_)
      column <- paste0("condrem_", outcome)
      if (!column %in% names(res$cif_df)) return(NA_real_)
      if (!tenure_row %in% rownames(census_matrix)) return(NA_real_)
      .grid_value_at(res$cif_df[[column]], census_matrix[tenure_row, lbl])
    }
    condrem_rows <- list()
    for (point in names(tenure_rows)) {
      for (outcome in outcome_levels) {
        condrem_rows[[paste0("aj_condrem_", outcome, "_at_", point)]] <-
          metric_row(as.list(sapply(labels, condrem_at, outcome,
                                    tenure_rows[[point]])))
      }
    }
    if (length(condrem_rows) > 0) {
      aj_condrem_at_tenure <- do.call(rbind, condrem_rows)
      rownames(aj_condrem_at_tenure) <- names(condrem_rows)
      colnames(aj_condrem_at_tenure) <- labels
    }
  }

  ci_matrix <- do.call(rbind, c(ci_rows, aj_ci_rows))
  colnames(ci_matrix) <- labels

  list(
    labels             = labels,
    observations       = obs_matrix,
    outcomes           = if (have_outcome_stats)
                           rbind(completed_outcomes_total = outcomes$totals, outcomes$counts)
                         else NULL,
    mix                = if (have_outcome_stats) outcomes$mix else NULL,
    incidence          = if (have_outcome_stats) outcomes$incidence else NULL,
    km                 = km_matrix,
    census             = census_matrix,
    aj_final_cif       = aj_final_cif,
    aj_restricted_mean = aj_restricted_mean,
    aj_rmtl            = aj_rmtl,
    aj_window          = aj_window,
    aj_condrem_at_tenure = aj_condrem_at_tenure,
    ci                 = ci_matrix
  )
}


# =======================================================================
# The results bundle
# =======================================================================

# Bump when a field changes meaning or disappears, so a downstream consumer
# reading a saved results.json can tell what it is looking at. Adding a field
# does not require a bump.
#
# 2: matrices and tables carry a "type" tag (see .json_prepare), so the file
#    is self-describing and read_results_json can restore the bundle exactly.
# 3: cox$hr_table loses hr_formatted / ci_formatted / p_formatted. They were
#    pre-rendered display strings for a console table that no longer exists, so
#    the tool stops computing them; cox$hr_table now matches weibull$hr_table
#    column for column. Every number they encoded is still there, unrounded, in
#    hr / ci_lower / ci_upper / p_value.
# 4: weibull$unified becomes weibull$crude, the group-free companion fit named
#    for what it is rather than for a word this project reserves for
#    whole-sample outputs. And aj$cif_df leaves the bundle: it was the unified
#    AJ day grid riding along inside a whole-object serialization, 41% of the
#    file, read by nothing, and every number in it is in aj_cif_unified.csv.
#    Per-day grids now live only in the companion CSVs, as the manifest says.
# 5: weibull$shape_variants[[id]]$shape_crossing gains `applicable` and
#    `enabled`, and the pair it already carried no longer says on its own which
#    shape formula produced the numbers. crossed = FALSE with no
#    fallback_reason used to mean one thing, a variant with a single other
#    predictor and so nothing to cross; it now also covers the ordinary case of
#    weibull_shape_crossing left off, where an additive shape formula is the
#    one asked for. A reader that wants the distinction takes it from the two
#    new fields. Alongside them, and merely added: every published Weibull fit
#    carries `fit_unstable`, .fit_weibull's verdict on whether its confidence
#    intervals are exact or approximations.
MLOS_RESULTS_SCHEMA_VERSION <- 5L

# Cox fit -> the plain values a report shows. summary() is called once here
# rather than by each consumer.
#
# The robust score test exists only for clustered fits (and can be missing even
# then in degenerate cases); it is reported as NA rather than as fabricated
# zeros, matching the console output's "Robust = not available".
.cox_bundle <- function(cox_results) {
  # The declining branch carries the reason it computed, matching the Weibull
  # bundle below; the workbook writes its own wording for the cell it has room
  # for, so without this the computed message reached the log and nothing else.
  if (!isTRUE(cox_results$has_analysis)) {
    return(list(has_analysis = FALSE, message = cox_results$message))
  }

  s <- summary(cox_results$cox_model)
  robscore <- if (is.null(s$robscore)) c(NA_real_, NA_real_, NA_real_) else s$robscore

  list(
    has_analysis = TRUE,
    formula = paste(deparse(stats::formula(cox_results$cox_model)), collapse = " "),
    n = cox_results$cox_model$n,
    n_events = cox_results$cox_model$nevent,
    concordance = unname(s$concordance[1]),
    # concordance[2] is already the standard error (matches the console output)
    concordance_se = unname(s$concordance[2]),
    # Clustering on animal_id is unconditional (ids are auto-generated when absent)
    uses_clustered_se = TRUE,
    xlevels = cox_results$cox_model$xlevels,
    tests = data.frame(
      test = c("Likelihood ratio", "Wald", "Score (logrank)", "Robust score"),
      statistic = unname(c(s$logtest[1], s$waldtest[1], s$sctest[1], robscore[1])),
      df = unname(c(s$logtest[2], s$waldtest[2], s$sctest[2], robscore[2])),
      p_value = unname(c(s$logtest[3], s$waldtest[3], s$sctest[3], robscore[3])),
      stringsAsFactors = FALSE
    ),
    hr_table = cox_results$hr_table,
    # The per-predictor stratified fits (see .cox_stratified_variants in
    # mlos_cox.R), already plain: each carries the same field set as this
    # bundle, never a coxph object. Empty when fewer than two stratifiers
    # qualified as predictors. Their tests and concordance are computed against
    # a stratified baseline and so are NOT comparable with the ones above; the
    # hazard ratios are.
    stratified_variants = cox_results$stratified_variants
  )
}

# The serializable half of .weibull_regression_analysis's value: everything
# except the flexsurvreg fit, which carries calls and environments. The unified
# companion is already plain (it never holds its own fit).
.weibull_bundle <- function(wres) {
  if (is.null(wres) || !isTRUE(wres$has_analysis)) {
    return(list(has_analysis = FALSE,
                message = if (is.null(wres)) NULL else wres$message))
  }
  wres$fit <- NULL
  wres
}

# A stratifier's Weibull shape variant (the per-predictor fits
# .weibull_regression_analysis bundles inside
# cox_results$weibull$shape_variants), or a declined placeholder when no
# variant was built for it. Four ways that happens, and the fallback message
# lists all four because from here they are indistinguishable, the entry
# simply being absent: this stratifier is not one of the pooled model's
# predictors (single-level or absent), the pooled model has fewer than two
# qualifying predictors so no variant is attempted at all,
# parametric_regression is not WEIBULL (cox_results$weibull is NULL then), or
# the POOLED fit itself failed, in which case .weibull_regression_analysis
# returned before reaching the variants -- the case
# tests/cases/truncation_censoring_split exercises. A variant that was
# attempted and failed on its own is not this path: it carries its own
# has_analysis = FALSE entry with the fit error.
#
# Already plain (shape_variants entries never carry a flexsurvreg fit), so
# unlike .weibull_bundle there is nothing to strip.
#' A stratifier's stratified Cox variant (the per-predictor fits
#' .cox_stratified_variants builds into cox_results$stratified_variants), or a
#' declined placeholder when no variant was built for it. Three ways that
#' happens, and the fallback message lists all three because from here they are
#' indistinguishable, the entry simply being absent: this stratifier is not one
#' of the pooled model's predictors (single-level or absent), fewer than two
#' predictors qualify so no variant is attempted at all, or the pooled Cox
#' regression was skipped outright. A variant that was attempted and failed on
#' its own is not this path: it carries its own has_analysis = FALSE entry with
#' the fit error.
#'
#' Mirrors .weibull_shape_variant_for above, and for the same reason: the
#' per-stratum node should say why a fit is missing rather than omit the key.
.cox_stratified_variant_for <- function(cox_results, stratifier_id) {
  cv <- cox_results$stratified_variants[[stratifier_id]]
  if (!is.null(cv)) return(cv)
  list(has_analysis = FALSE,
       message = paste("not a predictor in the pooled Cox regression,",
                       "fewer than two qualifying predictors,",
                       "or Cox regression was skipped"))
}

.weibull_shape_variant_for <- function(cox_results, stratifier_id) {
  wv <- cox_results$weibull$shape_variants[[stratifier_id]]
  if (!is.null(wv)) return(wv)
  list(has_analysis = FALSE,
       message = paste("not a predictor in the pooled Weibull regression,",
                       "fewer than two qualifying predictors,",
                       "parametric_regression is not WEIBULL,",
                       "or the pooled Weibull fit failed"))
}

# How the CSV's rows became the animal-period rows every other section counts.
#
# The pieces travel as attributes of period_data: `preparation` is the register
# read_and_prepare_data builds (see there), extended by break_down_by_period
# with the three animal_id-keyed counts that explain why the animal-period row
# count exceeds the stay count, and the two
# dropped_invalid_* attributes are break_down_by_period's own count of rows the
# period split could not keep, which happens when capping or truncation leaves
# a row with no time at risk.
#
# Worth carrying because nothing else in the run records it. The counts are
# printed to the log as they happen and then discarded, so a report that wants
# to state how many stays the analysis rests on, or why the analyzed total is
# smaller than the file's, has had to re-read the source data and re-derive the
# cleaning rules. They are also the stay-level and animal-level figures in
# the bundle: everywhere else counts animal-period rows, so rows_analyzed below
# is not comparable with rows_prepared above it, and the two are reported as the
# different quantities they are. The three animal_id-keyed counts are what say
# why they differ, and they separate the two reasons a stay count and a row
# count come apart (a stay split by a period boundary, and an animal that came
# back for a separate later stay), which a single number cannot.
#
# A caller that assembled period_data some other way carries no register, which
# is reported as absent rather than guessed at.
.data_preparation_bundle <- function(period_data) {
  prep <- attr(period_data, "preparation")
  if (is.null(prep)) return(list(has_register = FALSE))

  c(list(has_register = TRUE), prep, list(
    # Rows the period split dropped for having no time at risk, and the
    # animal-period row count every stratum section is denominated in.
    dropped_invalid_times_total     = attr(period_data, "dropped_invalid_total"),
    dropped_invalid_times_by_period = attr(period_data, "dropped_invalid_by_period"),
    rows_analyzed                   = nrow(period_data)
  ))
}

#' The screening ledger in the ShelterDataPrep statistics-table format
#'
#' One frame with two sections stacked, matching column for column the
#' `<name>_stats.csv` that ShelterDataPrep writes. Matching it is the whole
#' point: one reader opens both files and concatenates them into a single flow
#' from the raw extract to the rows the models ran on. The format is documented
#' in that project's README under "The statistics table"; mLOS's two additions
#' to its vocabulary, the `split` action and the `pass` role, are in the User
#' Guide.
#'
#' `section` selects between the two. A `stage` row is one screening step with
#' the row and animal counts on either side of it; a `detail` row is one value a
#' setting names, counted within the rows that step touched. Each section leaves
#' the other's columns empty, which is what keeps this one CSV rather than two.
#'
#' Two columns of the register are deliberately not emitted. `name` is mLOS's
#' internal name for a stage, and upstream identifies a stage by action, column
#' and detail instead; emitting it would add a column the other file does not
#' have, which is exactly what breaks a concatenation. The animal columns are
#' emitted but empty throughout when the CSV supplied no animal_id, since the
#' generated ids are one per row and counting them would restate `rows_*`.
#'
#' @param prep The data_preparation node of a results bundle
#' @return A data frame, or NULL when the bundle carries no register
build_screening_ledger <- function(prep) {
  if (!isTRUE(prep$has_register) || is.null(prep$ledger) || nrow(prep$ledger) == 0) {
    return(NULL)
  }
  stages <- prep$ledger
  detail <- prep$ledger_detail
  n_s    <- nrow(stages)

  out <- data.frame(
    section            = rep("stage", n_s),
    step               = stages$step,
    action             = stages$action,
    column             = stages$column,
    role               = rep("", n_s),
    value              = rep("", n_s),
    scope              = rep("", n_s),
    detail             = stages$detail,
    rows_in            = stages$rows_in,
    rows_affected      = stages$rows_affected,
    rows_out           = stages$rows_out,
    animal_id_in       = stages$animal_id_in,
    animal_id_affected = stages$animal_id_affected,
    animal_id_out      = stages$animal_id_out,
    stringsAsFactors   = FALSE
  )

  if (is.null(detail) || nrow(detail) == 0) return(out)
  n_d <- nrow(detail)
  rbind(out, data.frame(
    section            = rep("detail", n_d),
    step               = detail$step,
    action             = detail$action,
    column             = detail$column,
    role               = detail$role,
    value              = detail$value,
    scope              = detail$scope,
    detail             = rep("", n_d),
    rows_in            = rep(NA_integer_, n_d),
    rows_affected      = detail$rows_affected,
    rows_out           = rep(NA_integer_, n_d),
    animal_id_in       = rep(NA_integer_, n_d),
    animal_id_affected = detail$animal_id_affected,
    animal_id_out      = rep(NA_integer_, n_d),
    stringsAsFactors   = FALSE
  ))
}

#' Write the screening ledger to its own CSV
#'
#' A CSV and not a worksheet because the file exists to be read beside
#' ShelterDataPrep's, and a sheet inside a workbook cannot be. The same table
#' is also on the Data_Preparation sheet for a human reading the workbook, and
#' the whole register is in results.json; all three are renderings of one frame.
#'
#' Missing counts are written as empty cells, matching what pandas writes for
#' the nullable-integer columns of the upstream file, so the two stack without
#' a reader having to special-case either one.
#'
#' @param bundle A results bundle
#' @param csv_file Destination path
#' @return TRUE when written, FALSE when the bundle carries no register
write_screening_ledger_csv <- function(bundle, csv_file) {
  ledger <- build_screening_ledger(bundle$data_preparation)
  if (is.null(ledger)) {
    cat("\n*** WARNING: no data-preparation register in the bundle",
        "- skipping the screening ledger CSV ***\n")
    return(FALSE)
  }
  utils::write.csv(ledger, csv_file, row.names = FALSE, na = "")
  cat("\nData preparation stats exported to:", csv_file, "\n")
  TRUE
}

# The binned probability mass as one matrix: a row per interval, a column per
# outcome, the row total beside them, and a last row for the stays still in
# care when the window closes.
#
# It travels in the bundle rather than in a companion CSV because it is a
# summary and not a day grid: schema 4 moved the AJ day grid out to the CSVs,
# and a dozen interval masses is the other kind of thing. The figure that draws
# it ships no CSV, so these are the only copy.
#
# The remainder row is empty under each outcome, since none of them claims it,
# and carries its value in Total. That column then sums to exactly 1: the whole
# distribution, intervals and leftover together.
#
# NULL when probability_mass_width is 0, which is what an absent setting means.
.aj_probability_mass_matrix <- function(aj, references) {
  mass <- aj_probability_mass(aj, references)
  if (is.null(mass)) return(NULL)
  m <- cbind(mass$masses, Total = rowSums(mass$masses))
  rbind(m, still_in_care_at_cap = c(rep(NA_real_, length(mass$states)),
                                    mass$remainder))
}

# The serializable half of a compute_aj_cif_results value: everything except
# the fit object itself.
.aj_bundle <- function(aj, references) {
  if (is.null(aj) || !isTRUE(aj$has_analysis)) return(list(has_analysis = FALSE))
  list(
    has_analysis = TRUE,
    outcome_states = aj$outcome_states,
    max_time = aj$max_time,
    rmtl = aj$rmtl,
    rmtl_cap = aj$rmtl_cap,
    probability_mass = .aj_probability_mass_matrix(aj, references)
  )
}

# =======================================================================
# The output manifest
# =======================================================================

# Every plot ships with an identically named companion CSV holding the data
# behind it, and that pairing is deliberate: a reader who wants dots instead of
# lines, two strata on one panel, or the unified curve drawn over a stratified
# one takes the CSV and plots it their way, including pasting columns across
# files. So the CSVs are standard output, not a debugging aid, and the JSON
# does not duplicate their day grids.
#
# What the JSON owes them is a description. Which files a run emits depends on
# the output flags and on which stratifiers the data supports, so a consumer
# that hard-codes filenames is guessing; and neither the filename nor the
# header says what the numbers mean or what units they are in.
#
# One entry per family below, expanded to concrete filenames by stratifier and
# outcome code and then filtered to what the run actually wrote. `scope` says
# how to expand: "unified" is a single file, "stratified" one per stratifier,
# "stratified_outcome" one per stratifier and outcome code.
#
# `aggregate_rule` says how the summary row above the grid follows from the
# grid itself. It is not the same rule everywhere: the survival, census, and
# tenure grids sum down their column to their aggregate, an AJ CIF column
# reaches its restricted mean through the normalized form in
# .cif_normalized_rmean, and the remaining-LOS grid is not reduced at all but
# READ, at the day the mean in-care tenure falls in. Declaring the rule lets a
# consumer rederive the value and lets the suite check that the two routes
# agree. "at_mean_tenure" is the one rule that needs a number from outside its
# own file, the per_resident_past_days of the same stratum, which is in the
# in-care tenure CSV's summary row and in the JSON's census block.
#
# `x_note` states each family's own day-grid extent, because it is not the
# same everywhere: the KM-derived grids run 0..restricted_stay_cap - 1, the
# AJ CIF grids stop at the AJ analysis window (the last fitted time, at most
# the cap), and the AJ conditional grids carry only the days where the
# conditional probabilities are defined.
# The three day-grid extents (see the x_note comment above).
.X_NOTE_KM   <- "integer tenure; the grid runs 0..restricted_stay_cap - 1"
.X_NOTE_AJ   <- "integer tenure; the grid runs 0..the AJ analysis window (the last fitted time, at most restricted_stay_cap)"
.X_NOTE_COND <- "integer tenure; only the days within the AJ analysis window where the conditional probabilities are defined"
.X_NOTE_MASS <- "right-closed day intervals at the probability_mass_width setting, the last running to restricted_stay_cap, followed by a remainder bar that is not an interval"

# What the remaining-LOS families' summary row is, said once for both scopes.
# What the two stratified families that have pointwise bounds say about their
# columns. The bounds are a block to the right of the whole estimate grid rather
# than a pair beside each column they bound, so a consumer that wants the curves
# alone reads the first 1 + n columns and stops. Only these two families have
# bounds: the KM-derived companions (remaining LOS, census, tenure) are
# transforms with no interval of their own, and the conditional probabilities are
# a ratio of CIF differences the fit gives no interval for.
.COLUMNS_STRATIFIED_CI <- paste(
  "one per stratum, then their pointwise 95% CI bounds as a block to the right",
  "of the estimate grid, <stratum>_ci_lower and <stratum>_ci_upper paired per",
  "stratum in the same order. The summary row above the grid leaves the bound",
  "columns empty: it aggregates the estimates, and aggregating a pointwise",
  "bound would not give the bound of the aggregate")

.AGGREGATE_AT_MEAN_TENURE <- paste(
  "the curve read at the mean in-care tenure (per_resident_past_days) of the",
  "same stratum, truncated to the day step it falls in: what an animal of",
  "average tenure still expects. NOT the average remaining stay over the",
  "in-care population, which is per_resident_future_days = per_resident_past_days + 1")

.OUTPUT_FAMILIES <- list(
  list(kind = "km_survival", scope = "unified", stem = "km_survival_unified",
       x_note = .X_NOTE_KM,
       columns = "probability_still_in_care and its 95% CI bounds",
       value_units = "probability",
       value_meaning = "probability a stay is still in care at tenure d",
       aggregate = "restricted_mean", aggregate_units = "days",
       aggregate_meaning = "restricted mean stay, the column sum of the survival grid",
       aggregate_rule = "column_sum",
       description = "Unified Kaplan-Meier survival curve over all data."),
  list(kind = "km_survival", scope = "stratified", stem = "km_survival",
       x_note = .X_NOTE_KM,
       columns = .COLUMNS_STRATIFIED_CI,
       value_units = "probability",
       value_meaning = "probability a stay is still in care at tenure d",
       aggregate = "restricted_mean", aggregate_units = "days",
       aggregate_meaning = "restricted mean stay, the column sum of the survival grid",
       aggregate_rule = "column_sum",
       description = "Kaplan-Meier survival curve per stratum."),
  list(kind = "km_remaining_los", scope = "unified", stem = "km_remaining_los_unified",
       x_note = .X_NOTE_KM,
       columns = "a single All column, the whole dataset pooled",
       value_units = "days",
       value_meaning = "expected remaining stay for an animal that has already been in care d days",
       aggregate = "remaining_days_at_mean_tenure", aggregate_units = "days",
       aggregate_meaning = .AGGREGATE_AT_MEAN_TENURE,
       aggregate_rule = "at_mean_tenure",
       description = "Remaining length of stay by tenure, over all data."),
  list(kind = "km_remaining_los", scope = "stratified", stem = "km_remaining_los",
       x_note = .X_NOTE_KM,
       columns = "one per stratum",
       value_units = "days",
       value_meaning = "expected remaining stay for an animal that has already been in care d days",
       aggregate = "remaining_days_at_mean_tenure", aggregate_units = "days",
       aggregate_meaning = .AGGREGATE_AT_MEAN_TENURE,
       aggregate_rule = "at_mean_tenure",
       description = "Remaining length of stay by tenure, per stratum."),
  list(kind = "km_census_by_tenure", scope = "unified", stem = "km_census_by_tenure_unified",
       x_note = .X_NOTE_KM,
       columns = "a single All column, the whole dataset pooled",
       value_units = "animals",
       value_meaning = "expected number in care with current tenure d, at steady state",
       aggregate = "expected_census", aggregate_units = "animals",
       aggregate_meaning = "expected total census, the column sum of the grid (Little's law)",
       aggregate_rule = "column_sum",
       description = "Steady-state census by tenure, over all data."),
  list(kind = "km_census_by_tenure", scope = "stratified", stem = "km_census_by_tenure",
       x_note = .X_NOTE_KM,
       columns = "one per stratum",
       value_units = "animals",
       value_meaning = "expected number in care with current tenure d, at steady state",
       aggregate = "expected_census", aggregate_units = "animals",
       aggregate_meaning = "expected total census, the column sum of the grid (Little's law)",
       aggregate_rule = "column_sum",
       description = "Steady-state census by tenure, per stratum."),
  list(kind = "km_in_care_tenure", scope = "unified", stem = "km_in_care_tenure_unified",
       x_note = .X_NOTE_KM,
       columns = "a single All column, the whole dataset pooled",
       value_units = "proportion",
       value_meaning = "share of the in-care population with tenure of at least d days",
       aggregate = "per_resident_past_days", aggregate_units = "days",
       aggregate_meaning = "mean tenure of the in-care population, the column sum of the grid",
       aggregate_rule = "column_sum",
       description = "In-care tenure profile, over all data."),
  list(kind = "km_in_care_tenure", scope = "stratified", stem = "km_in_care_tenure",
       x_note = .X_NOTE_KM,
       columns = "one per stratum",
       value_units = "proportion",
       value_meaning = "share of the in-care population with tenure of at least d days",
       aggregate = "per_resident_past_days", aggregate_units = "days",
       aggregate_meaning = "mean tenure of the in-care population, the column sum of the grid",
       aggregate_rule = "column_sum",
       description = "In-care tenure profile, per stratum."),
  list(kind = "aj_cif", scope = "unified", stem = "aj_cif_unified",
       x_note = .X_NOTE_AJ,
       columns = "CIF and conditional-remaining columns per outcome, plus CI bounds",
       value_units = "probability",
       value_meaning = "cumulative incidence of each outcome by day d",
       aggregate = "restricted_mean", aggregate_units = "days",
       aggregate_meaning = "mean days to each column's outcome among the stays that reach it within the window",
       aggregate_rule = "cif_normalized_rmean",
       description = "Unified Aalen-Johansen competing-risk cumulative incidence."),
  list(kind = "aj_conditional", scope = "unified", stem = "aj_conditional_unified",
       x_note = .X_NOTE_COND,
       columns = "one per outcome",
       value_units = "probability",
       value_meaning = "probability that a stay still in care at the end of day d ends with this outcome by the end of the AJ analysis window; the columns can sum to less than 1, the shortfall being stays still unresolved at the window's end",
       aggregate = NULL,
       description = "Conditional outcome mix by day, all outcomes on one grid."),
  # The two stack plots are PNG-only by design: each draws the same numbers as
  # its line counterpart, whose companion CSV sits beside it.
  #
  # They also carry variant = "stack", which is what keeps a manifest entry
  # identifiable. Everywhere else kind + stratifier + outcome names exactly one
  # output; here two plots of the same data differ only in how they are drawn,
  # and a consumer asking for "the unified conditional plot" would otherwise
  # get whichever came first. The default is "lines", so the field means
  # something on every entry rather than appearing only where it is needed.
  list(kind = "aj_cif", scope = "unified", stem = "aj_cif_unified_stack",
       variant = "stack",
       x_note = .X_NOTE_AJ,
       columns = "one band per outcome",
       value_units = "probability",
       value_meaning = "cumulative incidence of each outcome by day d, stacked; the top of the stack is the probability of having departed and the space above it the probability of still being in care",
       aggregate = NULL,
       description = "Unified cumulative incidence as a stack. Same data as aj_cif_unified.csv."),
  list(kind = "aj_conditional", scope = "unified", stem = "aj_conditional_unified_stack",
       variant = "stack",
       x_note = .X_NOTE_COND,
       columns = "one band per outcome",
       value_units = "probability",
       value_meaning = "probability that a stay still in care at the end of day d ends with this outcome by the end of the AJ analysis window; the columns can sum to less than 1, the shortfall being stays still unresolved at the window's end",
       aggregate = NULL,
       description = "Conditional outcome mix as a stack. Same data as aj_conditional_unified.csv."),
  # PNG-only for a different reason from the two stack families above: this one
  # draws numbers that appear in no CSV at all. They are a binned summary rather
  # than a day grid, so they travel in the bundle (aj$probability_mass), which
  # is where a consumer reads them.
  list(kind = "aj_mass", scope = "unified", stem = "aj_mass_unified_stack",
       variant = "stack",
       x_column = "interval",
       x_note = .X_NOTE_MASS,
       columns = "one band per outcome, stacked, plus a remainder bar",
       value_units = "probability",
       value_meaning = "probability that a stay ends with this outcome having been in care for a length of time inside this interval; a bar's total is the fall in the KM survival curve across the same interval, and the remainder bar is the probability of still being in care at the cap, so every bar together sums to 1",
       aggregate = NULL,
       description = "Unified competing-risk probability mass by interval, as a stack. Numbers in aj$probability_mass."),
  # The share companion to the mass stack: the same intervals, each normalised
  # to its own total. No bundle field of its own, since every number in it is
  # aj$probability_mass divided by its row sum.
  list(kind = "aj_fraction", scope = "unified", stem = "aj_fraction_unified_stack",
       variant = "stack",
       x_column = "interval",
       x_note = .X_NOTE_MASS,
       columns = "one band per outcome, stacked to full height",
       value_units = "probability",
       value_meaning = "share of the stays ending inside this interval that end with this outcome; each bar is labelled with the interval's own share of every stay, and the bar at the cap is empty because a normalised remainder would be full height by construction",
       aggregate = NULL,
       description = "Unified outcome share within each interval, as a stack. Row-normalised aj$probability_mass."),
  list(kind = "aj_cif", scope = "stratified_outcome", stem = "aj_cif",
       x_note = .X_NOTE_AJ,
       columns = .COLUMNS_STRATIFIED_CI,
       value_units = "probability",
       value_meaning = "cumulative incidence of this outcome by day d",
       aggregate = "restricted_mean", aggregate_units = "days",
       aggregate_meaning = "mean days to this outcome among the stays that reach it within the window",
       aggregate_rule = "cif_normalized_rmean",
       description = "Aalen-Johansen cumulative incidence for one outcome, per stratum."),
  list(kind = "aj_conditional", scope = "stratified_outcome", stem = "aj_conditional",
       x_note = .X_NOTE_COND,
       columns = "one per stratum",
       value_units = "probability",
       value_meaning = "probability that a stay still in care at the end of day d ends with this outcome by the end of the AJ analysis window; the columns can sum to less than 1, the shortfall being stays still unresolved at the window's end",
       aggregate = NULL,
       description = "Conditional probability of one outcome by day, per stratum.")
)

# Expand the families into one entry per file this run wrote. The filter is the
# emission register (see reset_emitted_outputs in mlos_common.R), not the
# directory listing: results/ is not cleared between runs, so an earlier run's
# files linger and reading the directory would describe them as if they were
# this run's. A suppressed output flag, a stratifier the data cannot support,
# and an analysis that declined all drop out here the same way, by not having
# been written.
.build_output_manifest <- function(emitted, outcome_states) {
  entry <- function(family, stem, stratifier_id = NULL, outcome = NULL) {
    csv <- paste0(stem, ".csv")
    png <- paste0(stem, ".png")
    has_csv <- csv %in% emitted
    has_png <- png %in% emitted
    if (!has_csv && !has_png) return(NULL)
    list(
      csv         = if (has_csv) csv else NULL,
      plot        = if (has_png) png else NULL,
      kind        = family$kind,
      stratifier  = stratifier_id,
      outcome     = outcome,
      variant     = if (is.null(family$variant)) "lines" else family$variant,
      description = family$description,
      # Days unless the family says otherwise: every grid is indexed by day,
      # but a binned figure is indexed by interval and would otherwise claim a
      # column its data does not have.
      x = list(column = if (is.null(family$x_column)) "days" else family$x_column,
               units = "days since intake",
               note = family$x_note),
      values = list(columns = family$columns, units = family$value_units,
                    meaning = family$value_meaning),
      # The row between the header and the day grid. Every consumer that reads
      # the grid must skip it; every consumer that wants the summary can read
      # it here instead of recomputing.
      aggregate = if (is.null(family$aggregate)) NULL else
        list(row = family$aggregate, units = family$aggregate_units,
             meaning = family$aggregate_meaning,
             # How the aggregate follows from the grid printed below it, so a
             # consumer can rederive it and the test suite can check that the
             # two agree. "column_sum" is the sum down the column,
             # "cif_normalized_rmean" sum(CIF(last) - CIF(d)) / CIF(last) over
             # the column's defined values, and "at_mean_tenure" the row at the
             # day this stratum's per_resident_past_days falls in.
             derivation = family$aggregate_rule)
    )
  }

  entries <- list()
  for (family in .OUTPUT_FAMILIES) {
    if (identical(family$scope, "unified")) {
      # A unified file's stratifier is "all", the same name the data half of
      # this bundle gives the whole sample (strata$all, a genuine stratifier
      # with one level). It was NULL until every consumer had written the same
      # translation back to strata$all, at which point the null was just a
      # question the bundle asked and then answered somewhere else. "unified"
      # stays the vocabulary for the SCOPE and for the filenames; "all" is the
      # population, and it is the same population either way.
      entries <- c(entries, list(entry(family, family$stem, "all")))
      next
    }
    for (stratifier in stratifiers) {
      base <- paste0(family$stem, stratifier$suffix)
      if (identical(family$scope, "stratified")) {
        entries <- c(entries, list(entry(family, base, stratifier$id)))
      } else {
        for (code in outcome_states) {
          entries <- c(entries, list(entry(family, paste0(base, "_outcome_", code),
                                           stratifier$id, code)))
        }
      }
    }
  }
  entries[!vapply(entries, is.null, logical(1))]
}

# =======================================================================
# Archiving the previous run
# =======================================================================

# Filenames this tool generates, other than the three whose names the run
# configures (the workbook, the log, and the JSON). Used only as a fallback
# when the previous run left no manifest to read; every plot and companion CSV
# is named for the analysis that produced it, so the prefix identifies ours
# without a bare *.csv sweep that would catch a user's own files. A test asserts
# every manifest entry matches this, so an output family added under a new
# prefix fails loudly rather than quietly stopping being archived.
.MLOS_OUTPUT_FILE_PATTERN <- "^(km|aj)_.*\\.(csv|png)$"

# Directory name for this run's archive: mLOS_<date>_<ordinal>, the ordinal
# counting runs within the date. Width 3 is a display choice, not a limit --
# formatC widens rather than truncating past 999, so a counter can never abort
# a run.
.next_archive_dir <- function(output_dir, today = Sys.Date()) {
  prefix   <- paste0("mLOS_", format(today, "%Y%m%d"), "_")
  existing <- list.dirs(output_dir, recursive = FALSE, full.names = FALSE)
  used     <- suppressWarnings(as.integer(sub(prefix, "", existing[startsWith(existing, prefix)],
                                              fixed = TRUE)))
  used     <- used[!is.na(used)]
  next_n   <- if (length(used) == 0) 1L else max(used) + 1L
  file.path(output_dir, paste0(prefix, formatC(next_n, width = 3, flag = "0")))
}

# What a previous run left behind, by that run's own account. Its results.json
# lists every plot and CSV it wrote, so this needs no pattern matching and
# cannot mistake a user's file for ours. Returns character(0) when there is no
# readable manifest: a first run, a directory written before manifests existed,
# or a run whose JSON export was skipped for want of jsonlite.
.previous_run_outputs <- function(output_dir, json_file) {
  path <- file.path(output_dir, json_file)
  if (!file.exists(path) || !requireNamespace("jsonlite", quietly = TRUE)) return(character(0))
  manifest <- tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE)$outputs,
                       error = function(e) NULL)
  if (is.null(manifest)) return(character(0))
  unlist(lapply(manifest, function(e) c(e$csv, e$plot)), use.names = FALSE)
}

#' Move the previous run's outputs into a dated subdirectory
#'
#' Called before a run writes anything, so the directory it writes into holds
#' that run and nothing else. Two problems go away together: an output the new
#' run does not produce can no longer linger and be read as current, and a
#' result you wanted is no longer silently overwritten (the workbook and log
#' are written with overwrite semantics today, so anything at those paths is
#' lost without warning).
#'
#' Only this tool's own files move. The four configured names are taken from
#' the caller, which reads them from the same variables the writers use, and
#' the plots and CSVs come from the previous run's manifest, falling back to
#' .MLOS_OUTPUT_FILE_PATTERN. The screening ledger CSV is named here with the
#' workbook and the log rather than reached through the manifest: the manifest
#' describes the plot companions, whose grids and units it documents, and the
#' ledger is neither a plot nor a grid. Everything else in the directory is left alone:
#' people keep notes and their own spreadsheets beside their results, and a
#' `--results` pointed at a directory full of other work must not disturb it.
#'
#' The archive is a subdirectory of the output directory rather than a sibling
#' so that it stays in view; old runs accumulate until you delete them, and
#' that is easier to remember when they are sitting in the folder you already
#' open.
#'
#' Note that an early failure still archives, since this must run before the
#' log file is opened for writing (opening truncates it, which would destroy
#' the previous run's log before it could be saved). Nothing is lost when that
#' happens, the previous outputs are simply in the archive rather than beside
#' the new ones.
#'
#' @return NULL when there was nothing to archive, otherwise a list with the
#'   archive directory and the number of files moved
archive_previous_outputs <- function(output_dir, excel_file, log_file, json_file,
                                     stats_file = NULL) {
  if (!dir.exists(output_dir)) return(NULL)

  generated <- .previous_run_outputs(output_dir, json_file)
  if (length(generated) == 0) {
    generated <- list.files(output_dir, pattern = .MLOS_OUTPUT_FILE_PATTERN)
  }

  candidates <- unique(c(excel_file, log_file, json_file, stats_file, generated))
  paths      <- file.path(output_dir, candidates)
  # Directories are never swept: that keeps earlier archives out of the new one.
  keep       <- file.exists(paths) & !dir.exists(paths)
  if (!any(keep)) return(NULL)

  archive_dir <- .next_archive_dir(output_dir)
  dir.create(archive_dir, recursive = TRUE, showWarnings = FALSE)
  moved <- file.rename(paths[keep], file.path(archive_dir, candidates[keep]))
  if (!all(moved)) {
    # A file held open elsewhere (a workbook still open in Excel, say) is worth
    # a note but not worth stopping a run over: it is about to be overwritten
    # as it would have been before this existed.
    cat("*** WARNING: could not archive: ",
        paste(candidates[keep][!moved], collapse = ", "), " ***\n", sep = "")
  }
  list(dir = archive_dir, n = sum(moved))
}

#' Assemble every reported result into one bundle
#'
#' The single object every downstream report reads. Takes the analysis results
#' as they come out of the pipeline and returns plain lists, data frames, and
#' matrices: no fit objects, no environments, nothing that needs R to
#' interpret it. What goes in is what any consumer may show; deciding what to
#' show, and how, is the consumer's business.
#'
#' The `strata` node holds one entry per stratifying dimension, each the full
#' output of compute_stratum_measures:
#'   all     the whole sample as a single pooled column; always present
#'   period  one column per period, each period's own duration as denominator;
#'           always computed, though a consumer may choose not to show it when
#'           there is a single period and it says nothing `all` does not
#'   intake / group  present when the column exists with 2+ levels
#'
#' This runs before any plot or CSV is written, so that the rendering step can
#' take its summary values from here rather than deriving them a second time.
#' The `outputs` manifest is therefore empty at this point; call
#' attach_output_manifest once rendering is done.
#'
#' Curve grids: the unified KM scalars and the AJ CIF grids travel here, but
#' the plot companion grids (stratified KM, census by tenure, remaining LOS,
#' in-care tenure) are still produced inside the plotting path and remain
#' CSV-only for now.
#'
#' @return A nested list; see MLOS_RESULTS_SCHEMA_VERSION for versioning
# The rows a restricted-mean ratio adds to a stratifier's KM matrix, and the
# level everything in them is divided by.
KM_RATIO_ROWS <- c("km_restricted_mean_ratio",
                   "km_restricted_mean_ratio_ci_lower",
                   "km_restricted_mean_ratio_ci_upper")

# The level the regressions measure this stratifier's other levels against,
# taken from the fitted model rather than from the setting that asked for it:
# `period_reference` names a POLICY (OLDEST/NEWEST), the level it resolves to
# depends on which periods hold data, and a reference the model actually used
# is the only one the ratios can be compared against. xlevels carries the
# reference first, which is what relevel() means.
#
# NA where there is no fit, no such term, or a term with no levels, in which
# case no ratios are computed: a ratio against an unknown denominator is worse
# than an absent one.
.model_reference_level <- function(cox_results, stratifier_id) {
  if (!isTRUE(cox_results$has_analysis)) return(NA_character_)
  term <- .stratifier_model_terms()[[stratifier_id]]
  levels_used <- cox_results$cox_model$xlevels[[term]]
  if (is.null(levels_used) || length(levels_used) == 0) return(NA_character_)
  as.character(levels_used[[1L]])
}

# Each level's restricted mean stay as a multiple of the reference level's,
# with a 95% interval, appended to the KM matrix.
#
# It is the KM answer to the question the two regressions answer with a time
# ratio, and it is the only one of the three that adjusts for nothing: each
# level's own curve against another level's own curve, mix and all. That is
# what makes it worth reporting beside them rather than instead of them, and
# what the deck's notes have to say out loud.
#
# The interval is a first-order delta method on the log ratio, from the two
# restricted means' own standard errors, ASSUMING the two levels are
# independent. That is a simplifying approximation, not a property of the
# data: one animal can have stays in both levels, and on OC2 a quarter of the
# stays belong to animals that span more than one intake type. What it also
# ignores is that both curves are restricted at the same cap. The direction of
# the net error is not worth guessing at here -- dropping the covariance
# between two positively correlated levels widens the interval, while the
# repeat animals inside each level, which the Greenwood standard errors count
# as independent (math methods section 9), narrow it.
#
# The reference level's own row is exactly 1 with no bounds, the same
# convention .reference_row_for uses in the regression tables: it is the
# denominator, not an estimate.
.with_restricted_mean_ratios <- function(km_matrix, reference_label) {
  if (is.null(km_matrix) || is.na(reference_label) ||
      !(reference_label %in% colnames(km_matrix))) {
    return(km_matrix)
  }
  estimate <- as.numeric(km_matrix["km_restricted_mean", ])
  se       <- as.numeric(km_matrix["km_restricted_mean_se", ])
  names(estimate) <- names(se) <- colnames(km_matrix)

  ref_estimate <- estimate[[reference_label]]
  ref_se       <- se[[reference_label]]
  if (!isTRUE(is.finite(ref_estimate)) || ref_estimate <= 0) return(km_matrix)

  ratio <- estimate / ref_estimate
  log_se <- sqrt((se / estimate)^2 + (ref_se / ref_estimate)^2)
  half   <- 1.96 * log_se
  lower  <- ratio * exp(-half)
  upper  <- ratio * exp(half)

  is_reference <- colnames(km_matrix) == reference_label
  ratio[is_reference] <- 1
  lower[is_reference] <- NA_real_
  upper[is_reference] <- NA_real_

  block <- rbind(ratio, lower, upper)
  rownames(block) <- KM_RATIO_ROWS
  colnames(block) <- colnames(km_matrix)
  rbind(km_matrix, block)
}


build_results_bundle <- function(cox_results,
                                 km_results,
                                 aj_results,
                                 aj_strat_results,
                                 period_data,
                                 stratified_results,
                                 references,
                                 data_filename,
                                 settings_filename,
                                 output_dir,
                                 log_path) {
  periods <- references$periods

  # Gaps: stretches of days with no animal at risk, detected in the unified KM
  # and per stratum in the stratified KM. Statistics are NOT adjusted for them;
  # carrying them here is what lets every report say so.
  unified_gaps <- km_results$gaps
  strat_gaps   <- stratified_results$gaps
  gaps <- rbind(
    if (!is.null(unified_gaps) && nrow(unified_gaps) > 0)
      data.frame(analysis = "Unified KM", stratum = "(all data)",
                 gap_start_day = unified_gaps$gap_start,
                 gap_end_day = unified_gaps$gap_end, stringsAsFactors = FALSE),
    if (!is.null(strat_gaps) && nrow(strat_gaps) > 0)
      data.frame(analysis = paste("KM by", strat_gaps$stratifier),
                 stratum = strat_gaps$stratum,
                 gap_start_day = strat_gaps$gap_start,
                 gap_end_day = strat_gaps$gap_end, stringsAsFactors = FALSE)
  )
  if (is.null(gaps)) gaps <- data.frame(analysis = character(0), stratum = character(0),
                                        gap_start_day = numeric(0), gap_end_day = numeric(0),
                                        stringsAsFactors = FALSE)

  strata <- list()

  period_labels <- as.character(periods$period_label)
  strata$period <- compute_stratum_measures(
    period_data, "period_label", period_labels, km_results, aj_strat_results$period,
    days_lookup = setNames(as.numeric(periods$duration_days), period_labels),
    window_days = NULL
  )
  strata$period$weibull_shape   <- .weibull_shape_variant_for(cox_results, "period")
  strata$period$cox_stratified  <- .cox_stratified_variant_for(cox_results, "period")

  window_days <- .total_window_days(periods)

  # The whole dataset as a single stratum, so the pooled analysis is
  # structurally identical to the stratified ones and maps onto them row for
  # row. The unified AJ is wrapped as the single stratum's result so it is
  # reused rather than refitted. Built unconditionally: this is THE whole-sample
  # view, and every run has one whatever its period structure.
  period_data_all <- period_data
  period_data_all$all_data <- factor("All")
  aj_all <- if (!is.null(aj_results))
    list(has_analysis = isTRUE(aj_results$has_analysis), per_stratum = list(All = aj_results))
  else NULL
  strata$all <- compute_stratum_measures(
    period_data_all, "all_data", "All", km_results, aj_all,
    days_lookup = setNames(window_days, "All"), window_days = window_days
  )
  strata$all$unified_stay_counts <-
    calculate_unified_stay_counts(period_data_all, "All", "all_data")

  strata$period$km <- .with_restricted_mean_ratios(
    strata$period$km, .model_reference_level(cox_results, "period"))

  for (stratifier in stratifiers) {
    if (identical(stratifier$id, "period")) next
    if (!isTRUE(.strata_info(stratifier, references)$has)) next
    labels <- .stratum_levels_present(period_data[[stratifier$col]])
    strata[[stratifier$id]] <- compute_stratum_measures(
      period_data, stratifier$col, labels, km_results, aj_strat_results[[stratifier$id]],
      days_lookup = setNames(rep(window_days, length(labels)), labels),
      window_days = window_days
    )
    # Each stay counted once, in contrast with the row-level counts every other
    # section reports (a stay spanning periods contributes one row per period).
    strata[[stratifier$id]]$unified_stay_counts <-
      calculate_unified_stay_counts(period_data, labels, stratifier$col)
    strata[[stratifier$id]]$weibull_shape <-
      .weibull_shape_variant_for(cox_results, stratifier$id)
    strata[[stratifier$id]]$cox_stratified <-
      .cox_stratified_variant_for(cox_results, stratifier$id)
    strata[[stratifier$id]]$km <- .with_restricted_mean_ratios(
      strata[[stratifier$id]]$km,
      .model_reference_level(cox_results, stratifier$id))
  }

  # Provenance, one flat field per version. Every other entry in this block is
  # a scalar, and a reader after one version reaches it by name rather than by
  # unpacking a container. The set is fixed by MLOS_PACKAGES, so a machine
  # missing an optional package writes "not installed" in its field instead of
  # writing a shorter block.
  package_fields <- as.list(setNames(mlos_package_versions(),
                                     paste0(MLOS_PACKAGES, "_version")))

  list(
    schema_version = MLOS_RESULTS_SCHEMA_VERSION,
    run = c(
      list(
        mlos_version = MLOS_VERSION,
        generated_at = as.character(Sys.time()),
        r_version    = as.character(getRversion())
      ),
      package_fields,
      list(
        data_file     = data_filename,
        settings_file = settings_filename,
        output_dir    = output_dir,
        log_file      = log_path
      )
    ),
    # Substantive settings first: those that affect the computation or the
    # interpretation of results. The plot-only cosmetics and the
    # output-emission flags change no number, so they stay out of this list and
    # sit apart under `presentation` below; they are carried rather than
    # dropped because nothing else records them.
    settings = list(
      restricted_stay_cap      = references$restricted_stay_cap,
      # Substantive rather than presentational: it sets the intervals of
      # aj$probability_mass, so it is in the settings the workbook shows.
      probability_mass_width   = references$probability_mass_width,
      period_reference         = references$period_reference,
      intake_type_reference    = references$intake_type_reference,
      animal_group_reference   = references$animal_group_reference,
      animal_group_columns     = references$animal_group_columns,
      parametric_regression    = references$parametric_regression,
      weibull_shape_crossing   = references$weibull_shape_crossing,
      discard_bad_rows         = references$discard_bad_rows,
      discard_overlapping_rows = references$discard_overlapping_rows,
      intake_filter            = references$intake_filter,
      animal_group_filter      = references$animal_group_filter,
      other_filter             = references$other_filter,
      outcome_type_delete      = references$outcome_type_delete,
      outcome_type_in_care     = references$outcome_type_in_care,
      outcome_type_mapping     = references$outcome_type_mapping,
      periods                  = periods,
      window_days              = window_days,
      # Periods that actually have data, which is what decides whether a
      # multi-period caveat applies: a defined-but-empty period contributes no
      # rows, so this can be smaller than coverage$period$n.
      n_periods_present        = length(unique(period_data$period_label)),
      coverage = list(
        period = list(label = "Period",       included = references$has_period,
                      n = references$n_periods),
        intake = list(label = "Intake type",  included = references$has_intake_type,
                      n = references$n_intake_types),
        group  = list(label = "Animal group", included = references$has_animal_group,
                      n = references$n_animal_groups)
      ),
      # How this run drew and emitted things. None of it changes a result, and
      # the workbook shows none of it, which is exactly why it is here: a
      # downstream figure that wants to match the tool's own (the same x-axis
      # truncation, the same stratum limit) has no other way to learn these,
      # and the emission flags are what explain a file the manifest does not
      # list. output_flags is a named c(png=, csv=) per output family (see
      # .output_flag in mlos_common.R).
      presentation = list(
        plot_stay_cap          = references$plot_stay_cap,
        max_plot_strata        = references$max_plot_strata,
        show_km_ci_ribbons     = references$show_km_ci_ribbons,
        show_aj_cif_ci_ribbons = references$show_aj_cif_ci_ribbons,
        png_pointsize_factor   = references$png_pointsize_factor,
        png_line_width_factor  = references$png_line_width_factor,
        output_flags           = references$output_flags
      )
    ),
    unified = list(
      study_start              = as.character(min(period_data$period_start)),
      study_end                = as.character(max(period_data$period_end)),
      restricted_stay_cap      = km_results$restricted_stay_cap,
      max_time                 = km_results$max_time,
      n_total                  = km_results$n_total,
      n_events                 = km_results$n_events,
      n_censored               = km_results$n_censored,
      n_capped                 = km_results$n_capped,
      fraction_capped          = unname(km_results$fraction_capped),
      fraction_capped_ci_lower = unname(km_results$fraction_capped_ci_lower),
      fraction_capped_ci_upper = unname(km_results$fraction_capped_ci_upper),
      still_in_care_at_cap     = unname(km_results$still_in_care_at_cap),
      still_in_care_at_cap_ci_lower = unname(km_results$still_in_care_at_cap_ci_lower),
      still_in_care_at_cap_ci_upper = unname(km_results$still_in_care_at_cap_ci_upper),
      median_los               = unname(km_results$median_los),
      median_los_ci_lower      = unname(km_results$median_los_ci_lower),
      median_los_ci_upper      = unname(km_results$median_los_ci_upper),
      percentile_90            = unname(km_results$percentile_90),
      percentile_90_ci_lower   = unname(km_results$percentile_90_ci_lower),
      percentile_90_ci_upper   = unname(km_results$percentile_90_ci_upper),
      restricted_mean          = unname(km_results$restricted_mean),
      restricted_mean_se       = unname(km_results$restricted_mean_se),
      restricted_mean_ci_lower = unname(km_results$restricted_mean_ci_lower),
      restricted_mean_ci_upper = unname(km_results$restricted_mean_ci_upper),
      gaps                     = gaps
    ),
    # The plot palette, so a downstream chart can use the same colors the tool's
    # own figures use. Hex rather than R color names, which are not portable
    # (see .palette_hex).
    palette = list(
      # Assigned to strata POSITIONALLY, in the order each measures node lists
      # its labels: the first stratum takes the first color, and so on, never
      # recycling (max_plot_strata is capped at the palette length). A stratum
      # therefore keeps its color across runs as long as the level set does.
      # No I() needed on these two: both are fixed-length constants longer than
      # one element, so auto_unbox cannot collapse them to a bare scalar.
      stratum_colors = .palette_hex(.STRATIFIED_COLORS),
      # Keyed by outcome code rather than positional: an outcome keeps its
      # color even in a report that shows only some of them.
      outcome_colors = setNames(.palette_hex(.OUTCOME_COLORS), names(.OUTCOME_COLORS)),
      outcome_labels = setNames(vapply(.OUTCOME_STATE_LEVELS, .outcome_label, character(1)),
                                .OUTCOME_STATE_LEVELS),
      # The canonical outcome order, best outcome first, used by every plot,
      # table, and stack in the tool. Not alphabetical, which would read L, N, T.
      outcome_order = .OUTCOME_STATE_LEVELS
    ),
    # The attrition from CSV rows to analyzed rows; see
    # .data_preparation_bundle. Reported by no other output.
    data_preparation = .data_preparation_bundle(period_data),
    cox     = .cox_bundle(cox_results),
    weibull = .weibull_bundle(cox_results$weibull),
    aj      = .aj_bundle(aj_results, references),
    strata  = strata,
    # Filled in by attach_output_manifest once rendering has happened; the
    # manifest records what was written, which is not known yet.
    outputs = list()
  )
}

# Significant digits for every number in the file. 17 is the IEEE 754
# guarantee: 17 significant decimal digits identify a double uniquely, so a
# value written and read back is bit-for-bit what it was.
#
# Neither obvious alternative works. jsonlite's default is 4 significant
# digits, which would degrade every value in the file. digits = NA reads like
# "full precision" but gives 15, which is enough for most values and silently
# wrong for the rest: a Cox likelihood-ratio statistic came back differing in
# its last bits, which is how this was caught.
.JSON_DIGITS <- 17L

#' Record what the run rendered
#'
#' The manifest describes the plots and companion CSVs a run produced, so it
#' cannot be assembled until they have been. Everything else in the bundle is
#' computed before any rendering starts, which is what lets the CSV writers take
#' their summary values from it; this second step closes the loop afterwards.
#'
#' @param bundle The bundle from build_results_bundle
#' @return The bundle with its `outputs` manifest filled in
attach_output_manifest <- function(bundle) {
  bundle$outputs <- .build_output_manifest(emitted_outputs(), .OUTCOME_STATE_LEVELS)
  bundle
}

#' Write the results bundle to JSON
#'
#' Numbers are written at full double precision (see .JSON_DIGITS).
#' na = "null" keeps missing values distinguishable from zero rather than
#' dropping them; note that JSON has one way to say "no value", so an NA and an
#' absent field both come back empty. Matrices, tables, and named vectors are
#' tagged so the file describes its own shapes (see .json_prepare).
#'
#' @return TRUE when written, FALSE when jsonlite is unavailable
write_results_json <- function(bundle, json_file) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    cat("\n*** WARNING: jsonlite package not installed - skipping JSON export ***\n")
    cat("Install with: install.packages('jsonlite')\n")
    return(FALSE)
  }
  writeLines(
    jsonlite::toJSON(.json_prepare(bundle), digits = .JSON_DIGITS, na = "null", null = "null",
                     auto_unbox = TRUE, dataframe = "columns", pretty = TRUE),
    json_file
  )
  cat("\nJSON results exported to:", json_file, "\n")
  TRUE
}

# Make the bundle self-describing before encoding. JSON has objects and arrays
# and nothing else, so a reader cannot otherwise tell a measure matrix or a
# table from an ordinary group of settings. Two tagged shapes carry that:
#
#   {"type": "matrix", "rows": [...], "columns": [...], "values": [[...]]}
#   {"type": "table",  "columns": {"<name>": [...], ...}}
#
# A matrix's row name is the measure's identity, so it has to survive the trip;
# both shapes are also the natural input to a data frame in any language
# (pandas takes values/rows/columns and the column object directly).
#
# A third shape covers named vectors:
#
#   {"type": "named_vector", "names": [...], "values": [...]}
#
# needed because a bare JSON array carries no names, and the outcome-type
# mapping is exactly a set of names (the shelter's own labels) pointing at
# values (the canonical codes). Encoding it as a plain object would work in
# JSON but would be indistinguishable from a group of settings on the way back.
#
# I() marks the vectors that must stay arrays: without it a single-column
# matrix or a single-row table would auto-unbox to bare scalars and change
# shape depending on the data.
.json_prepare <- function(x) {
  if (is.matrix(x)) {
    return(list(
      type    = "matrix",
      rows    = I(rownames(x)),
      columns = I(colnames(x)),
      values  = unname(lapply(seq_len(nrow(x)), function(i) I(unname(x[i, ]))))
    ))
  }
  if (is.data.frame(x)) {
    return(list(type = "table", columns = lapply(as.list(x), I)))
  }
  # Must come after the matrix and data-frame cases: a matrix is atomic too.
  if (is.atomic(x) && !is.null(names(x))) {
    return(list(type = "named_vector", names = I(names(x)), values = I(unname(x))))
  }
  if (is.list(x)) return(lapply(x, .json_prepare))
  x
}

#' Read a results bundle back from JSON
#'
#' The inverse of write_results_json: returns the bundle in the form
#' build_results_bundle produced it, so a consumer reading a saved run gets
#' exactly what a consumer reading a live one gets. This is what makes
#' results.json the input to the workbook rather than a second artifact
#' alongside it.
#'
#' Two things JSON cannot carry are restored by convention rather than
#' recovered: numeric matrices come back as double even where every value was a
#' whole number or NA (JSON has one number type, and jsonlite narrows), and a
#' table with zero rows comes back with its columns named but untyped, which is
#' all any consumer of an empty table needs. Dates were written as ISO strings
#' and stay strings; every consumer formats them anyway.
#'
#' @param json_file Path to a results.json written by write_results_json
#' @return The bundle, with matrices and data frames rehydrated
read_results_json <- function(json_file) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("package 'jsonlite' is required to read a results JSON file")
  }
  .json_rehydrate(jsonlite::fromJSON(json_file, simplifyVector = TRUE))
}

.json_rehydrate <- function(x) {
  if (is.list(x) && identical(x$type, "matrix")) {
    values <- x$values
    if (!is.matrix(values)) {
      # A matrix whose rows all decoded to bare vectors (or none at all).
      values <- matrix(unlist(values), nrow = length(x$rows), byrow = TRUE)
    }
    storage.mode(values) <- "double"
    dimnames(values) <- list(x$rows, x$columns)
    return(values)
  }
  if (is.list(x) && identical(x$type, "named_vector")) {
    return(setNames(x$values, x$names))
  }
  if (is.list(x) && identical(x$type, "table")) {
    cols <- lapply(x$columns, function(col) if (is.list(col) && length(col) == 0) character(0) else col)
    return(data.frame(cols, check.names = FALSE, stringsAsFactors = FALSE))
  }
  if (is.list(x)) return(lapply(x, .json_rehydrate))
  x
}
