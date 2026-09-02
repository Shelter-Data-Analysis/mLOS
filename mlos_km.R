# mLOS - Kaplan-Meier analysis (Unified and Stratified)
# =======================================================================
# Uses .STRATIFIED_COLORS, .with_png, .png_lwd, .get_series_colors,
#      .make_surv_obj, .extract_km_survival, .extract_stratum_survival,
#      .plot_csv_filename, .write_plot_csv, .stratum_ci_steps,
#      .ci_ribbon_stair_xy, .prepend_restricted_mean_row,
#      stratifiers, .strata_info, .find_observation_gaps, .stratum_gaps,
#      .total_window_days, .binom_prop_ci
#      from mlos_common.R
# Uses calculate_period_flow_metrics from mlos_data.R (sourced earlier by
#      both entry points) for the census-by-tenure intake rates


#' Perform Kaplan-Meier analysis on all data for the unified period
#'
#' @param period_data Data frame from break_down_by_period (with capping already applied)
#' @param references List with reference values; uses references$restricted_stay_cap for reporting
#' @return List containing KM fit object and summary statistics
km_unified_period <- function(period_data, references) {

  # Create Surv object for left-truncated, right-censored data
  # Note: time_end has already been capped in break_down_by_period
  surv_obj <- .make_surv_obj(period_data)

  # Fit Kaplan-Meier curve
  # Use rmean parameter to get restricted mean automatically
  km_fit <- survival::survfit(surv_obj ~ 1, data = period_data)

  # Check for gaps in observation (see .find_observation_gaps). Through a
  # gap the KM curve cannot recover -- if the pre-gap risk set empties via
  # an event, S hits 0 and every post-gap event multiplies an already-zero
  # curve -- so the curve and the restricted mean are unreliable from the
  # first gap onward. Statistics are NOT adjusted; gaps are reported here,
  # in the Excel General sheet, and per stratum in
  # stratified_km_analysis. Remedies are in the User Guide.
  gaps <- .find_observation_gaps(period_data$time_start, period_data$time_end,
                                 references$restricted_stay_cap)
  gap_detected <- nrow(gaps) > 0
  if (gap_detected) {
    for (i in seq_len(nrow(gaps))) {
      cat("\n*** WARNING: Gap in observations from day ", gaps$gap_start[i],
          " to day ", gaps$gap_end[i], " ***\n", sep = "")
    }
    cat("No animals are at risk during such a stretch. The KM curve cannot\n")
    cat("recover after a gap, so the curve and the restricted mean are\n")
    cat("unreliable from the first gap onward. See 'Observation gaps' in\n")
    cat("the User Guide for remedies.\n\n")
  }

  # Calculate median survival time with CI
  median_surv <- summary(km_fit)$table

  # Calculate 90th percentile (time when 90% have had outcomes, 10% still in
  # care). quantile() also returns the CI bounds, obtained like the median's by
  # inverting the curve's pointwise confidence bounds.
  q90 <- quantile(km_fit, probs = 0.90)
  percentile_90 <- q90$quantile

  # Determine x-axis limit for plots
  max_time <- max(km_fit$time)

  # Extract restricted mean and its standard error from survfit
  rmean_table <- summary(km_fit, rmean = references$restricted_stay_cap)$table
  restricted_mean <- if ("rmean" %in% names(rmean_table)) as.numeric(rmean_table["rmean"]) else NA_real_
  restricted_mean_se <- if ("se(rmean)" %in% names(rmean_table)) as.numeric(rmean_table["se(rmean)"]) else NA_real_

  # Calculate fraction exceeding cap (from capped observations), with an
  # exact binomial (Clopper-Pearson) 95% CI; the independence assumption
  # this adds is stated in math methods 8.2.
  fraction_capped <- sum(period_data$capped_at_rmean) / nrow(period_data)
  fraction_capped_ci <- .binom_prop_ci(sum(period_data$capped_at_rmean), nrow(period_data))

  # The fitted counterpart of fraction_capped: the KM curve's terminal value,
  # the estimated probability a stay is still in care once it has accrued the
  # full cap. It does NOT replace fraction_capped, which is a direct count of
  # the rows that reached the cap; the pair is observed beside fitted, exactly
  # as mean_census_inventory sits beside expected_census.
  #
  # Read at elapsed day `cap`, NOT at cap - 1 where the reported day grids stop.
  # Both reasons point the same way. On the merits, the elapsed clock and the
  # inclusive LOS clock differ by one (math methods 4), so S(cap) = P(LOS > cap),
  # which is exactly the event fraction_capped counts by tallying rows;
  # S(cap - 1) is P(LOS > cap - 1) and sits above it.
  # On the arithmetic, the Aalen-Johansen grid runs 0..cap while the KM day grid
  # runs 0..cap - 1, so `cap` is the only point at which the two routes are
  # comparable at all.
  #
  # Equal to 1 - the Aalen-Johansen cif_Any there, by two independent fits; the
  # suite asserts it per stratum. The difference between the two candidate days
  # is invisible on most datasets, because nothing happens on the last day and
  # the curve is flat across it. The sim_intake_mix_shift fixture has an exit on
  # exactly that day, which is what makes the distinction measurable.
  cap_day <- references$restricted_stay_cap
  still_in_care_at_cap <- .extract_km_survival(km_fit, cap_day)
  still_in_care_ci_lower <- .extract_km_survival(km_fit, cap_day, km_fit$lower)
  still_in_care_ci_upper <- .extract_km_survival(km_fit, cap_day, km_fit$upper)

  # Return results
  results <- list(
    km_fit = km_fit,
    median_los = median_surv["median"],
    median_los_ci_lower = median_surv["0.95LCL"],
    median_los_ci_upper = median_surv["0.95UCL"],
    percentile_90 = percentile_90,
    percentile_90_ci_lower = as.numeric(q90$lower),
    percentile_90_ci_upper = as.numeric(q90$upper),
    restricted_mean = restricted_mean,
    restricted_mean_se = restricted_mean_se,
    restricted_mean_ci_lower = restricted_mean - 1.96 * restricted_mean_se,
    restricted_mean_ci_upper = restricted_mean + 1.96 * restricted_mean_se,
    restricted_stay_cap = references$restricted_stay_cap,
    max_time = max_time,
    gap_detected = gap_detected,
    gap_start = if (gap_detected) gaps$gap_start[1] else NA_real_,
    gap_end   = if (gap_detected) gaps$gap_end[1] else NA_real_,
    gaps = gaps,
    fraction_capped = fraction_capped,
    fraction_capped_ci_lower = fraction_capped_ci[1],
    fraction_capped_ci_upper = fraction_capped_ci[2],
    still_in_care_at_cap = still_in_care_at_cap,
    still_in_care_at_cap_ci_lower = still_in_care_ci_lower,
    still_in_care_at_cap_ci_upper = still_in_care_ci_upper,
    n_total = nrow(period_data),
    n_events = sum(period_data$event),
    n_censored = sum(!period_data$event),
    n_capped = sum(period_data$capped_at_rmean)
  )

  return(results)
}

.export_km_curve_csv <- function(km_results, filename) {
  days <- 0:(km_results$restricted_stay_cap - 1)
  km_fit <- km_results$km_fit
  km_table <- data.frame(
    days                      = as.character(days),
    probability_still_in_care = .extract_km_survival(km_fit, days),
    lower_ci                  = .extract_km_survival(km_fit, days, km_fit$lower),
    upper_ci                  = .extract_km_survival(km_fit, days, km_fit$upper),
    stringsAsFactors = FALSE
  )

  # km_results$restricted_mean was computed by km_unified_period from the
  # same fit and cap; no need to recompute it here.
  km_table <- .prepend_restricted_mean_row(
    km_table,
    list(probability_still_in_care = km_results$restricted_mean)
  )

  .write_plot_csv(km_table, filename)
}


# The three statistics the unified KM-family plots mark, in the order their
# legend rows appear, each with the color it carries on every one of those
# plots. One curve per plot, three marks on it, same three colors: a reader
# who has learned the survival plot's red line reads the tenure profile's red
# line without being told again.
.MARKER_KEYS   <- c("median", "p90", "mean")
.MARKER_COLORS <- c(median = "red", p90 = "orange", mean = "green3")

# A mark's value as its legend row spells it, with a note when the mark falls
# outside the plotted range. Such a mark keeps its row rather than losing it
# with its line: the value is often the finding (a standing population whose
# 90th percentile tenure lies beyond the right edge is exactly the long tail
# these plots are drawn to show), and a row whose line cannot be found on the
# plot has to say why it cannot.
.marker_days <- function(x, x_max) {
  off_scale <- isTRUE(is.finite(x)) && !is.null(x_max) && isTRUE(x > x_max)
  paste0(round(x, 1), " days", if (off_scale) ", off scale" else "")
}

# Draw a vertical dashed mark at each of `values[[key]]`, skipping any that is
# absent or NA, and return the legend rows describing them: `labels[[key]]` is
# the row's text, with its numbers already in it, because what a mark means
# differs by plot (a tenure on one, a remaining stay read off at that tenure on
# another) while where it sits and how it is drawn do not.
#
# Drawing and legend building are one call returning rows, rather than two
# calls, because the marks have to go down before the curve is drawn over them
# while the legend has to go up last. Two calls would leave the same key set to
# be filtered identically in two places, which is exactly how a mark ends up
# drawn in one color and described in another.
.plot_marker_lines <- function(values, labels) {
  keys <- .MARKER_KEYS[.MARKER_KEYS %in% names(values)]
  keys <- keys[vapply(keys, function(k) isTRUE(is.finite(values[[k]])), logical(1))]
  for (k in keys) {
    abline(v = values[[k]], lty = 2, col = .MARKER_COLORS[[k]], lwd = .png_lwd(2))
  }
  list(items = vapply(keys, function(k) labels[[k]], character(1), USE.NAMES = FALSE),
       cols  = unname(.MARKER_COLORS[keys]),
       lty   = rep(2, length(keys)),
       lwd   = rep(.png_lwd(2), length(keys)))
}

#' Plot Kaplan-Meier survival curve
#'
#' @param km_results Results from km_unified_period
#' @param references References list; uses references$plot_stay_cap for x-axis limit
#' @param title Optional plot title
#' @param save_file Optional filename to save plot
plot_km_curve <- function(km_results, references, title = "Kaplan-Meier Survival Curve - Length of Stay",
                          save_file = NULL) {

  x_limit <- references$plot_stay_cap

  .with_png(save_file, {
    # Plot KM curve (main estimate only; CI is drawn as a shaded ribbon below)
    plot(km_results$km_fit,
         conf.int = FALSE,
         xlab = "Days Already in Care",
         ylab = "Probability Still in Care",
         main = title,
         col = "blue",
         lty = 1,
         lwd = .png_lwd(3),
         mark.time = FALSE,                # No censoring marks
         xlim = c(0, x_limit),
         ylim = c(0, 1),
         cex.main = 1.2)

    # Add grid (behind the curve)
    .plot_grid()
    # Shaded CI ribbon, drawn as a true stair shape so its edges align exactly with
    # the KM curve's own step jumps (see .ci_ribbon_stair_xy in mlos_common.R).
    raw  <- .stratum_ci_steps(km_results$km_fit, 1)
    poly <- .ci_ribbon_stair_xy(raw$time, raw$lower, raw$upper, x_limit)
    graphics::polygon(poly$x, poly$y, col = grDevices::adjustcolor("blue", alpha.f = 0.15), border = NA)

    # The three marks, each a vertical line only: no horizontal line, and no
    # text in the plot box, the value being spelled out in the legend instead.
    # A median or 90th percentile the curve never reaches is NA and is skipped
    # by .plot_marker_lines, along with its legend row.
    marks <- .plot_marker_lines(
      values = list(median = km_results$median_los,
                    p90    = km_results$percentile_90,
                    mean   = km_results$restricted_mean),
      labels = list(median = paste0("Median (", .marker_days(km_results$median_los, x_limit), ")"),
                    p90    = paste0("P90 (", .marker_days(km_results$percentile_90, x_limit), ")"),
                    mean   = paste0("Restricted mean (", .marker_days(km_results$restricted_mean, x_limit), ")")))

    # Redraw the curve on top of grid, ribbon, and reference lines
    lines(km_results$km_fit, conf.int = FALSE,
          col = "blue",
          lty = 1,
          lwd = .png_lwd(3),
          mark.time = FALSE)

    # The curve's own row, then the marks' rows in the order they were drawn
    legend("topright",
           legend = c("KM estimate", marks$items),
           col = c("blue", marks$cols),
           lty = c(1, marks$lty),
           lwd = c(.png_lwd(3), marks$lwd),
           bg = "white")
  })

  if (!is.null(save_file)) {
    cat("\nPlot saved to:", save_file, "\n")
    .export_km_curve_csv(km_results, .plot_csv_filename(save_file))
  }
}


# =======================================================================
# Stratified Kaplan-Meier analysis
# =======================================================================

# Strip the "colname=" prefix that survival::survfit adds to stratum names
# (e.g. "intake_type=stray" -> "stray"). Handles multi-variable strata
# (e.g. "period_label=Period_1, intake_type=stray" -> "Period_1, stray").
.strip_stratum_prefix <- function(strata_names) {
  vapply(strata_names, function(nm) {
    parts <- strsplit(nm, ",\\s*")[[1]]
    parts <- sub("^[^=]+=", "", parts)
    paste(parts, collapse = ", ")
  }, character(1), USE.NAMES = FALSE)
}

# Column names for the day-grid tables built off a KM fit: the stratum labels
# for a stratified fit, and a single whole-sample column for an unstratified
# one. survfit records no $strata in the unstratified case, so that label has to
# be supplied here; .extract_stratum_survival already reads index 1 of such a fit
# as the whole curve, which is what makes one column the right answer. "All" is
# the label the results bundle's whole-sample node and the workbook's By_All
# sheet already use, so a unified companion CSV's column heading matches them.
.km_series_names <- function(km_fit, label = "All") {
  if (is.null(km_fit$strata)) label else .strip_stratum_prefix(names(km_fit$strata))
}

# Restricted mean per stratum, the daily step-sum sum_{d=0}^{tau-1} S(d) (math
# methods 5.3): the value the stratified KM CSV reports as its own
# restricted_mean row. Also used, independently of .compute_remaining_los, for
# the Remaining LOS companion CSV's own restricted_mean row (math methods 5.6,
# 8.1): that row is computed here from the survival curve, not read off
# Remaining_LOS(0), so the two rows cross-check the identity
# Remaining_LOS(0) = RMST rather than one restating the other.
.stratum_rmst_map <- function(km_fit, strata_names, tau) {
  days <- 0:(tau - 1)
  setNames(
    lapply(seq_along(strata_names), function(i) {
      sum(.extract_stratum_survival(km_fit, i, days), na.rm = TRUE)
    }),
    strata_names
  )
}

.export_stratified_km_csv <- function(km_fit, filename, tau, rmst_map = NULL) {
  days <- 0:(tau - 1)
  strata_names <- .strip_stratum_prefix(names(km_fit$strata))
  plot_table <- data.frame(days = as.character(days), check.names = FALSE)

  for (stratum_idx in seq_along(strata_names)) {
    plot_table[[strata_names[stratum_idx]]] <- .extract_stratum_survival(
      km_fit,
      stratum_idx,
      days
    )
  }

  # The pointwise CI bounds of those same curves, in their own block to the
  # right of the estimate grid (see .ci_bound_names). They are forward-filled
  # onto the day grid exactly as the estimates are, and they are the numbers
  # the optional per-stratum ribbons are drawn from, so the file holds
  # everything the plot can show whether or not the ribbons were drawn. The
  # restricted_mean row leaves them empty: a column sum of a pointwise bound is
  # not the bound of the restricted mean, and the workbook carries that one.
  for (stratum_idx in seq_along(strata_names)) {
    ci <- .ci_bound_names(strata_names[stratum_idx])
    plot_table[[ci[["lower"]]]] <- .extract_stratum_survival(
      km_fit, stratum_idx, days, km_fit$lower
    )
    plot_table[[ci[["upper"]]]] <- .extract_stratum_survival(
      km_fit, stratum_idx, days, km_fit$upper
    )
  }

  plot_table <- .prepend_restricted_mean_row(
    plot_table, if (is.null(rmst_map)) .stratum_rmst_map(km_fit, strata_names, tau) else rmst_map
  )

  .write_plot_csv(plot_table, filename)
}

#' Perform stratified Kaplan-Meier analysis by period, intake type, or animal group
#'
#' Creates separate KM curves for each level of the stratifying variable
#' Multiple curves are shown on the same plot (without confidence intervals)
#'
#' @param period_data Data frame from break_down_by_period
#' @param references References list; uses has_period, has_intake_type, has_animal_group, plot_stay_cap
#' @return List containing KM fits for each stratifying variable
stratified_km_analysis <- function(period_data, references) {

  cat("\n=======================================================================\n")
  cat("STRATIFIED KAPLAN-MEIER ANALYSIS\n")
  cat("=======================================================================\n")

  surv_obj <- .make_surv_obj(period_data)

  # Initialize results list; gaps collects per-stratum observation gaps
  # (see .find_observation_gaps) for the Excel General section.
  results <- list(stratifiers = stratifiers)
  results$gaps <- data.frame(stratifier = character(0), stratum = character(0),
                             gap_start = numeric(0), gap_end = numeric(0),
                             stringsAsFactors = FALSE)

  # -------------------------------------------------------------------------
  # Check which stratifying variables are available
  # -------------------------------------------------------------------------

  # All stratifier availability (period, intake type, animal group) comes from references

  cat("\nStratifying variables available:\n")
  for (stratifier in stratifiers) {
    info <- .strata_info(stratifier, references)
    availability <- ifelse(info$has,
                           paste(info$n, tolower(stratifier$label)),
                           "Not available")
    cat("  ", stratifier$label, ": ", availability, "\n", sep = "")
  }

  # -------------------------------------------------------------------------
  # KM by stratifying variable
  # -------------------------------------------------------------------------

  for (stratifier in stratifiers) {
    cat("\n=== Kaplan-Meier by ", stratifier$label, " ===\n", sep = "")

    info <- .strata_info(stratifier, references)

    if (info$has) {
      km_formula <- stats::as.formula(paste("surv_obj ~", stratifier$col))
      results[[stratifier$km_result_key]] <- survival::survfit(km_formula, data = period_data)

      # Intake rates for the census-by-tenure companion outputs; stored here
      # so plot_stratified_km does not need period_data.
      results$intake_rates[[stratifier$id]] <- .stratum_intake_rates(period_data, stratifier, references)

      cat("Fitted KM curves for ", info$n, " ", tolower(stratifier$label), "\n", sep = "")

      # Per-stratum gap check (see .stratum_gaps): a small stratum can have an
      # observation gap even when the pooled data does not, same rationale and
      # consequences as the unified check in km_unified_period.
      stratum_gaps <- .stratum_gaps(period_data, stratifier, references$restricted_stay_cap)
      for (i in seq_len(nrow(stratum_gaps))) {
        cat("*** WARNING: Gap in observations for ", stratum_gaps$stratifier[i], " '",
            stratum_gaps$stratum[i], "' from day ", stratum_gaps$gap_start[i],
            " to day ", stratum_gaps$gap_end[i], " ***\n", sep = "")
      }
      results$gaps <- rbind(results$gaps, stratum_gaps)
    } else {
      cat("Skipped - not available or only one level\n")
    }
  }

  if (nrow(results$gaps) > 0) {
    cat("\nThe affected strata's KM curves and restricted means are unreliable\n")
    cat("from their first gap onward. See 'Observation gaps' in the User Guide\n")
    cat("for remedies.\n")
  }

  return(results)
}


# Compute Remaining LOS for each stratum across all X from 0 to tau-1.
#
# Remaining_LOS(X) = 1 + (1/S(X)) * sum_{t=X+1}^{tau-1} S(t)
#
# At X=0 this equals sum_{t=0}^{tau-1} S(t) = restricted mean (consistency check).
#
# Returns a data frame with columns Days (0..tau-1) and one column per stratum.
.compute_remaining_los <- function(km_fit, tau) {
  days         <- 0:(tau - 1)
  strata_names <- .km_series_names(km_fit)
  result       <- data.frame(days = days, check.names = FALSE)

  for (stratum_idx in seq_along(strata_names)) {
    result[[strata_names[stratum_idx]]] <- .remaining_los_from_survival(
      .extract_stratum_survival(km_fit, stratum_idx, days))
  }

  result
}

# The formula above on one already-tabulated survival grid S(0..tau-1), which is
# the form stratum_km_summary needs: it holds a grid rather than a fit index,
# and the value it reports (the curve read at the stratum's mean in-care tenure)
# has to be the same number the plot draws, not a second derivation of it.
.remaining_los_from_survival <- function(s) {
  # rev_cumsum[i] = sum_{t = i}^{tau-1} S(t);  shift by one to get sum from X+1
  rev_cs   <- rev(cumsum(rev(s)))          # rev_cs[i] = sum_{t=i-1}^{tau-1} S(t) (1-indexed)
  tail_sum <- c(rev_cs[-1], 0)             # tail_sum[i] = sum_{t=i}^{tau-1} S(t) (0-indexed X)

  s_x <- ifelse(s > 0, s, NA_real_)        # avoid division by zero when no animals remain
  1 + tail_sum / s_x
}

# The part of a KM survival plot's own filename that says which curve it is, and
# so the part a companion substitutes its own stem for: "survival" in both
# km_survival_unified and km_survival_by_period. ONE spelling across both scopes
# is what lets a single substitution serve every companion; it was two ("curve"
# unified, "stratified" per stratifier) until the survival family's filenames
# were brought into line with its manifest kind, which is why the substitution
# needed to be told which spelling to expect.
.KM_FILENAME_TOKEN <- "survival"

# Derive a companion filename (stem "remaining_los", "census_by_tenure", or
# "in_care_tenure") from a KM survival plot's filename by substituting the token
# above for the stem, in the basename only. Substituting in the full path (sub()
# replaces only the first match) would instead corrupt an enclosing directory
# name if it happens to also contain the token (e.g. a case directory literally
# named "survival_km_<something>"). So km_survival_by_period yields
# km_remaining_los_by_period, and km_survival_unified yields
# km_remaining_los_unified.
.km_companion_filename <- function(filename, stem) {
  file.path(dirname(filename), sub(.KM_FILENAME_TOKEN, stem, basename(filename)))
}

# The two resident-tenure quantile rows, named once because they are produced
# by stratum_km_summary, relocated by build_stratum_measures, and consumed as a
# family (with the per_resident_past_days mean) by the census section.
RESIDENT_TENURE_QUANTILE_ROWS <- c("per_resident_past_days_restricted_median",
                                   "per_resident_past_days_restricted_p90")

# The remaining-LOS curve read at each of those three tenure statistics, in the
# order the census section reports them, which mirrors the order the tenures
# themselves appear in it: the mean (per_resident_past_days), then the median,
# then the 90th percentile. Produced, relocated and consumed exactly as the
# quantile rows above are, and marked on the pooled remaining-LOS plot.
#
# Each answers "an animal that has already been here as long as <this
# statistic> says, how much longer does it expect", which is a statement about
# an animal. The curve's own values have no median or mean worth taking: it is a
# function of tenure, not a distribution over animals, so any average of its
# column would be an average over a day grid (math methods 5.6).
#
# Do not read remaining_days_at_mean_tenure as the average remaining stay of the
# in-care population. That average is per_resident_future_days, in this same
# section, and it equals per_resident_past_days + 1 exactly; the two differ by a
# Jensen gap that is wide wherever the curve is far from straight.
REMAINING_AT_TENURE_ROWS <- c("remaining_days_at_mean_tenure",
                              "remaining_days_at_median_tenure",
                              "remaining_days_at_p90_tenure")

# Both families at once, in reporting order: the rows stratum_km_summary
# computes off the survival grid but that belong to the census section, so the
# one function that hands them over and the one that drops them from the KM
# block name the same set.
RESIDENT_VIEW_ROWS <- c(RESIDENT_TENURE_QUANTILE_ROWS, REMAINING_AT_TENURE_ROWS)

# One value off a tabulated remaining-LOS curve, at a tenure that need not be a
# whole day: the mean tenure lands between two days. The convention is
# .grid_value_at's, shared with the conditional outcome mix read at the same
# three tenures, so the two report the same day as each other and as the plots.
.remaining_los_at <- function(remaining, x) .grid_value_at(remaining, x)

# Quantiles of the in-care tenure distribution p(d) = S(d) / sum_d S(d),
# d = 0..cap-1 (math methods 5.7), whose mean is the per_resident_past_days the
# census aggregates report. They are read off that distribution's complementary
# CDF G(x) = sum_{d>x} S(d) / sum_d S(d) by exactly the convention the KM
# quantiles use on S: the smallest tenure at which the curve has fallen to or
# below the tail probability.
#
# Because p(d) is a proper distribution on the capped grid, G(cap - 1) = 0 by
# construction and these are ALWAYS reached: unlike km_median_los there is no
# "not reached" NA to plumb. The price is that they are restricted quantiles,
# silently truncated at the cap with no NA to say so, which is why the rows
# carry "restricted" in their names. A cap that binds drags the 90th percentile
# down toward it; the median is far less exposed.
.resident_tenure_quantile <- function(s_grid, tail_prob) {
  total <- sum(s_grid, na.rm = TRUE)
  if (!is.finite(total) || total <= 0) return(NA_real_)
  # tail_g[x + 1] = sum_{d > x} S(d) / total, on the same 0-based day grid:
  # exactly the G(x) the in-care tenure profile plots and .compute_in_care_tenure
  # builds, which is why the quantile convention itself lives one function down.
  .tail_curve_quantile((total - cumsum(s_grid)) / total, tail_prob)
}

# The convention above, applied to a complementary-CDF curve already in hand:
# the smallest day at which it has fallen to or below the tail probability, on
# a 0-based day grid. Separated out so the tenure quantiles the workbook reports
# and the marks drawn on the tenure profile are the same rule read off the same
# shape, rather than two spellings of it that could drift by a day.
.tail_curve_quantile <- function(g, tail_prob) {
  hit <- which(g <= tail_prob)
  if (length(hit) == 0) return(NA_real_)
  as.numeric(hit[1L] - 1L)
}

# Per-stratum KM summary: one column per label, rows in a fixed order. Fits
# each stratum's own survival curve (not a subset of the pooled stratified
# fit) so a stratifier with a single level is summarized the same way as one
# with many, and a label with no rows yields an all-NA column rather than an
# error.
#
# The 95% CI bounds for the median and p90 come from the same summary table
# and quantile() call that supply the point estimates; the restricted-mean CI
# is rmean +/- 1.96 * the se(rmean) survfit reports.
#
# The last two rows are per unit intake rate, within the cap (math methods
# 5.7), from the census-by-tenure profile N(d) = rate * S(d), d = 0..cap-1:
# the elapsed animal-days sum_d d * S(d) (backward-looking) and the future
# animal-days sum_d (d+1) * S(d) (forward-looking). Scaling them by the
# stratum's mean daily intake rate (stratum_census_aggregates) yields
# Expected_past/expected_future_animal_days, matching the km_census_by_* CSV
# (which reads S(d) from the equivalent stratum of the pooled stratified fit).
# Their difference is sum_d S(d) = the restricted mean, so Expected_future -
# Expected_past = expected_census by construction.
#
# The final five rows are the resident-tenure quantiles and the remaining-LOS
# curve read at each of the three tenure statistics. They are computed here
# because this is where the survival grid lives, but they are reported with the
# resident-view rows rather than the intake-cohort ones: build_stratum_measures
# (mlos_results.R) moves them into the census matrix, next to the
# per_resident_past_days mean they are the median, 90th percentile, and readouts
# of.
stratum_km_summary <- function(period_data, col, labels, cap) {
  col_values <- as.character(period_data[[col]])
  row_names <- c("km_median_los", "km_p90_los", "km_restricted_mean",
                 "km_past_days_per_intake", "km_future_days_per_intake",
                 "km_median_los_ci_lower", "km_median_los_ci_upper",
                 "km_p90_los_ci_lower", "km_p90_los_ci_upper",
                 "km_restricted_mean_ci_lower", "km_restricted_mean_ci_upper",
                 "km_restricted_mean_se",
                 "km_still_in_care_at_cap", "km_still_in_care_at_cap_ci_lower",
                 "km_still_in_care_at_cap_ci_upper",
                 RESIDENT_TENURE_QUANTILE_ROWS, REMAINING_AT_TENURE_ROWS)

  as.matrix(sapply(labels, function(lbl) {
    subset_data <- period_data[!is.na(col_values) & col_values == lbl, , drop = FALSE]
    if (nrow(subset_data) == 0) {
      return(setNames(rep(NA_real_, length(row_names)), row_names))
    }
    surv_obj <- .make_surv_obj(subset_data)
    fit <- survival::survfit(surv_obj ~ 1, data = subset_data)

    fit_tbl <- summary(fit)$table
    median_los <- if ("median" %in% names(fit_tbl)) as.numeric(fit_tbl["median"]) else NA_real_
    median_lo  <- if ("0.95LCL" %in% names(fit_tbl)) as.numeric(fit_tbl["0.95LCL"]) else NA_real_
    median_hi  <- if ("0.95UCL" %in% names(fit_tbl)) as.numeric(fit_tbl["0.95UCL"]) else NA_real_
    q90 <- suppressWarnings(quantile(fit, probs = 0.90))
    p90    <- as.numeric(q90$quantile)
    p90_lo <- as.numeric(q90$lower)
    p90_hi <- as.numeric(q90$upper)
    rmean_tbl <- summary(fit, rmean = cap)$table
    rmean_val <- if ("rmean" %in% names(rmean_tbl)) as.numeric(rmean_tbl["rmean"]) else NA_real_
    rmean_se  <- if ("se(rmean)" %in% names(rmean_tbl)) as.numeric(rmean_tbl["se(rmean)"]) else NA_real_

    days_grid <- 0:(cap - 1)
    s_grid    <- .extract_km_survival(fit, days_grid)
    past_per_intake   <- sum(days_grid * s_grid, na.rm = TRUE)
    future_per_intake <- sum((days_grid + 1) * s_grid, na.rm = TRUE)

    # The curve's terminal value and its pointwise bounds. Read at day `cap`,
    # one past the end of days_grid, which is why this extracts rather than
    # taking that grid's last entry (see km_unified_period for the quantity and
    # for why the extra day matters).
    still_at_cap <- .extract_km_survival(fit, cap)
    still_lo <- .extract_km_survival(fit, cap, fit$lower)
    still_hi <- .extract_km_survival(fit, cap, fit$upper)

    resident_quantiles <- setNames(
      c(.resident_tenure_quantile(s_grid, 0.50),
        .resident_tenure_quantile(s_grid, 0.10)),
      RESIDENT_TENURE_QUANTILE_ROWS)

    # The remaining-LOS curve read at those three tenures. The mean tenure is
    # formed here exactly as the census section forms per_resident_past_days,
    # elapsed animal-days over census with the intake rate cancelling, so the
    # reported value is the curve read at the tenure the row above it states
    # rather than at a second estimate of that tenure.
    remaining <- .remaining_los_from_survival(s_grid)
    mean_tenure <- if (isTRUE(is.finite(rmean_val)) && rmean_val > 0)
                     past_per_intake / rmean_val else NA_real_
    remaining_at_tenure <- setNames(
      c(.remaining_los_at(remaining, mean_tenure),
        .remaining_los_at(remaining, resident_quantiles[[1L]]),
        .remaining_los_at(remaining, resident_quantiles[[2L]])),
      REMAINING_AT_TENURE_ROWS)

    c(km_median_los = median_los, km_p90_los = p90, km_restricted_mean = rmean_val,
      km_past_days_per_intake = past_per_intake, km_future_days_per_intake = future_per_intake,
      km_median_los_ci_lower = median_lo, km_median_los_ci_upper = median_hi,
      km_p90_los_ci_lower = p90_lo, km_p90_los_ci_upper = p90_hi,
      km_restricted_mean_ci_lower = rmean_val - 1.96 * rmean_se,
      km_restricted_mean_ci_upper = rmean_val + 1.96 * rmean_se,
      km_restricted_mean_se = rmean_se,
      km_still_in_care_at_cap = still_at_cap,
      km_still_in_care_at_cap_ci_lower = still_lo,
      km_still_in_care_at_cap_ci_upper = still_hi,
      resident_quantiles, remaining_at_tenure)
  }))
}

# The census-aggregates matrix shared by every stratified report, in a fixed
# order: observed census and accumulated in-care days; the KM-implied census and
# its elapsed/future animal-days; three days-per-resident ratios; then the rows
# `carried` supplies, the median and 90th percentile of the same in-care tenure
# distribution whose mean is per_resident_past_days, and the remaining-LOS curve
# read at each of those three tenures. One column per group. Deriving the ratios
# here (guarding a zero or NA census with NA, the > 0 idiom used for the
# incidence-rate rows) keeps the row set and order identical across reports, so
# a whole-sample column maps row-for-row onto the stratum columns.
#
# Each of the five computed inputs is a numeric vector over the columns (length
# 1 for a whole-sample section, or one entry per stratum). `carried` is a matrix
# of rows that arrive ready-made from stratum_km_summary, which has the survival
# grid they are read off; they are appended in its row order, so the order the
# section reports them in is that function's row order and not a second listing
# here to be kept in step with it.
.census_aggregate_matrix <- function(mean_census_inventory, daily_in_care_days,
                                     expected_census, expected_past_animal_days,
                                     expected_future_animal_days,
                                     carried, col_labels) {
  per_resident_in_care <- ifelse(mean_census_inventory > 0,
                                 daily_in_care_days / mean_census_inventory, NA_real_)
  per_resident_past    <- ifelse(expected_census > 0,
                                 expected_past_animal_days / expected_census, NA_real_)
  per_resident_future  <- ifelse(expected_census > 0,
                                 expected_future_animal_days / expected_census, NA_real_)
  m <- rbind(
    mean_census_inventory         = mean_census_inventory,
    daily_mean_total_in_care_days = daily_in_care_days,
    expected_census               = expected_census,
    expected_past_animal_days     = expected_past_animal_days,
    expected_future_animal_days   = expected_future_animal_days,
    per_resident_in_care_days     = per_resident_in_care,
    per_resident_past_days        = per_resident_past,
    per_resident_future_days      = per_resident_future
  )
  m <- rbind(m, matrix(as.numeric(carried), nrow = nrow(carried),
                       dimnames = list(rownames(carried), NULL)))
  colnames(m) <- col_labels
  m
}

# Scale the per-intake KM helpers by each stratum's mean daily intake rate to
# get the expected census and its elapsed/future animal-days (Little's law,
# math methods 5.7), then assemble the census-aggregates matrix beside the
# observed counts. km_summary is stratum_km_summary's matrix, still carrying its
# resident-view rows, which pass through unscaled: neither a quantile of the
# tenure distribution nor a reading off the remaining-LOS curve depends on the
# intake rate, which cancels in both. The three observed vectors run over the
# same columns.
stratum_census_aggregates <- function(km_summary, mean_daily_intakes,
                                      mean_census_inventory, daily_in_care_days, labels) {
  .census_aggregate_matrix(
    mean_census_inventory       = mean_census_inventory,
    daily_in_care_days          = daily_in_care_days,
    expected_census             = mean_daily_intakes *
                                    as.numeric(km_summary["km_restricted_mean", ]),
    expected_past_animal_days   = mean_daily_intakes *
                                    as.numeric(km_summary["km_past_days_per_intake", ]),
    expected_future_animal_days = mean_daily_intakes *
                                    as.numeric(km_summary["km_future_days_per_intake", ]),
    carried                     = km_summary[RESIDENT_VIEW_ROWS, , drop = FALSE],
    col_labels                  = labels
  )
}

# Mean daily intakes per stratum for one stratifier, as a named vector
# (stratum label -> intakes/day). Period strata use each period's own
# duration as denominator; intake-type and animal-group strata use the
# whole observation window, exactly as the Excel stratum sheets do.
# Consumers must look up by name, never by position: the survfit strata and
# these flow rows are built independently, so nothing guarantees their row
# order matches (even now that both are chronological for period).
.stratum_intake_rates <- function(period_data, stratifier, references) {
  flow_df <- if (identical(stratifier$id, "period")) {
    calculate_period_flow_metrics(period_data)
  } else {
    calculate_period_flow_metrics(
      period_data,
      col = stratifier$col,
      window_days = .total_window_days(references$periods)
    )
  }
  # period_label holds the group label for non-period cols too
  setNames(flow_df$mean_daily_intakes, as.character(flow_df$period_label))
}

# Compute the steady-state census-by-tenure profile for each stratum:
#
#   N(d) = mean_daily_intakes * S(d),  d = 0..tau-1
#
# the expected number of animals in care with current tenure d, assuming
# intakes arrive at the observed mean daily rate and stays follow the
# fitted KM curve (see math methods 5.7). Column sums give the predicted
# mean census (inventory convention), i.e. Little's law:
# L = mean_daily_intakes * restricted mean.
#
# Returns a data frame with columns Days (0..tau-1) and one column per stratum.
.compute_census_by_tenure <- function(km_fit, tau, intake_rates) {
  days         <- 0:(tau - 1)
  strata_names <- .km_series_names(km_fit)
  result       <- data.frame(days = days, check.names = FALSE)

  for (stratum_idx in seq_along(strata_names)) {
    s    <- .extract_stratum_survival(km_fit, stratum_idx, days)
    rate <- intake_rates[strata_names[stratum_idx]][[1L]]  # NA_real_ if label absent
    result[[strata_names[stratum_idx]]] <- rate * s
  }

  result
}

# Build the CSV form of the census-by-tenure and in-care tenure tables: one
# summary row prepended above the day grid, matching the single-header-row
# convention of the other plot CSVs. Both companions summarize by the same
# statistic -- each stratum's column sum of the plotted series -- placed
# under `label`; only its meaning differs:
#   expected_census        sum_d N(d) = rate * restricted mean (Little's law)
#   per_resident_past_days sum_x G(x) = sum_d d*S(d) / sum_d S(d), the mean
#                          tenure of the in-care population
# (The remaining-LOS companion is the odd one out and does not come through
# here: no reduction of its column means anything, so its summary row is the
# curve read at a tenure instead. See .remaining_at_mean_tenure_map.)
# For census by tenure, the two other aggregates the workbook reports are
# recoverable from the grid rather than carried here: the scale factor is
# the day-0 row N(0) = rate (since S(0) = 1), and the future workload is
# sum_d (d+1) * N(d). Dividing a day row by N(0) recovers S(d); dividing by
# expected_census gives the tenure distribution of the in-care population.
# `values` supplies the summary row from the results bundle, so the CSV and the
# workbook print the same number for the same quantity. Left NULL (a direct
# caller with no bundle to hand) it falls back to the column sums, which is what
# the bundle's value equals to within floating-point noise; the test suite
# asserts the two agree.
.km_companion_csv_table <- function(companion_table, label, values = NULL) {
  strata_names <- setdiff(names(companion_table), "days")
  sums <- if (is.null(values)) {
    lapply(setNames(strata_names, strata_names),
           function(nm) sum(companion_table[[nm]], na.rm = TRUE))
  } else {
    lapply(setNames(strata_names, strata_names), function(nm) values[[nm]])
  }

  out <- companion_table
  out$days <- as.character(out$days)
  .prepend_restricted_mean_row(out, sums, label = label)
}

# The summary row of a remaining-LOS companion CSV: each column's curve read at
# that column's own mean in-care tenure, the sum of its tenure profile G.
#
# The row it replaced was the restricted mean, which is the same number the KM
# survival CSV beside it already carries, reached through the identity
# Remaining_LOS(0) = RMST. This row is instead a value the file alone holds, and
# the one the pooled plot's green mark stands at.
#
# Derived from the two grids rather than taken from the bundle, for the callers
# that have no bundle; where there is one, the caller passes the census row
# remaining_days_at_mean_tenure instead, which is this same reading made off the
# same curve at the stratum's own fit.
.remaining_at_mean_tenure_map <- function(rlos_table, in_care_table, series_names) {
  setNames(
    lapply(series_names, function(nm) {
      .remaining_los_at(rlos_table[[nm]], sum(in_care_table[[nm]], na.rm = TRUE))
    }),
    series_names
  )
}

# Compute the in-care tenure profile for each stratum: the fraction of the
# steady-state in-care population whose current tenure (days already in care)
# exceeds x,
#
#   G(x) = sum_{d>x} S(d) / sum_d S(d),   x = 0..tau-1
#
# the complementary CDF of the tenure distribution p(d) = S(d)/RMST of math
# methods 5.7. The intake rate cancels, so this is a pure normalized transform
# of the stratum's KM curve S: G(x) is the survival function of the equilibrium
# (age) distribution. Comparing it against the KM curve shows how the standing
# population's tenure differs from the intake cohort's length of stay (for a
# memoryless LOS the two coincide; a decreasing hazard lifts G above the KM, an
# increasing hazard drops it below). Its column sum sum_x G(x) is the mean
# tenure of the in-care population, which equals the per_resident_past_days the
# workbook reports.
#
# Returns a data frame with columns Days (0..tau-1) and one column per stratum.
.compute_in_care_tenure <- function(km_fit, tau) {
  days         <- 0:(tau - 1)
  strata_names <- .km_series_names(km_fit)
  result       <- data.frame(days = days, check.names = FALSE)

  for (stratum_idx in seq_along(strata_names)) {
    s        <- .extract_stratum_survival(km_fit, stratum_idx, days)  # S(0..tau-1)
    rev_cs   <- rev(cumsum(rev(s)))       # rev_cs[i] = sum_{d>=i-1} S(d) (1-indexed)
    tail_gt  <- c(rev_cs[-1], 0)          # tail_gt[x+1] = sum_{d>x} S(d) (0-indexed x)
    rmst     <- sum(s)
    result[[strata_names[stratum_idx]]] <- if (rmst > 0) tail_gt / rmst else NA_real_
  }

  result
}

# Plot one KM-derived companion table (remaining LOS, census by tenure, or
# in-care tenure) as staircase curves, one per series, and export its companion
# CSV. The companions share everything except the computed table, the y axis,
# and the CSV form, so one helper serves all of them from a spec (see
# `companions` in plot_stratified_km and plot_unified_km_companions): `table` is
# the day-grid data frame, `ylim` NULL means "from the data" (the tenure profile
# fixes c(0, 1) instead: it is a fraction), `csv_table` maps the table to its CSV
# form, `markers` is NULL or the values and labels .plot_marker_lines draws,
# `legend_pos` is NULL for the usual top right corner or names one of its own
# (the remaining-LOS curve climbs into the top right, so its legend sits at the
# bottom right instead), and `draw`/`filename`/`csv_file` gate the outputs
# exactly as draw_png/filename/csv_file do in .plot_single_stratified.
.plot_km_companion <- function(spec, n_series, references) {
  companion_table <- spec$table
  series_names    <- setdiff(names(companion_table), "days")
  cols            <- .get_series_colors(n_series)
  x_vals          <- companion_table$days
  in_plot         <- x_vals <= references$plot_stay_cap

  if (isTRUE(spec$draw)) .with_png(spec$filename, {
    # Y scaled to the part of the curves the plot shows: the table runs out to
    # restricted_stay_cap, but only the rows within plot_stay_cap are drawn, and
    # a remaining-LOS curve that keeps climbing past the cap would otherwise
    # flatten everything visible into the bottom of the panel.
    y_lim <- if (is.null(spec$ylim)) {
      c(0, max(unlist(companion_table[in_plot, series_names, drop = FALSE]), na.rm = TRUE))
    } else {
      spec$ylim
    }
    # Initialise an empty plot with the right axes
    plot(NULL,
         xlim = c(0, references$plot_stay_cap),
         ylim = y_lim,
         xlab = "Days Already in Care",
         ylab = spec$ylab,
         main = spec$title)

    .plot_grid()
    # Marks first, so the curves are drawn over them (see .plot_marker_lines).
    # Only the unified companions carry any; a stratified panel has one set of
    # statistics per stratum and no single curve to hang them on.
    marks <- if (is.null(spec$markers)) NULL else
      .plot_marker_lines(spec$markers$values, spec$markers$labels)

    for (i in seq_along(series_names)) {
      y_vals <- companion_table[[series_names[i]]]
      lines(x_vals[in_plot], y_vals[in_plot], col = cols[i], lty = 1, lwd = .png_lwd(2), type = "s")
    }

    # A lone curve needs no legend row of its own: it is the whole-data curve,
    # which the title already says. Only the unified companions reach that
    # case, a single-level stratifier never being plotted at all. Their marks
    # do need rows, so the legend appears whenever there is anything to say.
    legend_items <- if (length(series_names) > 1) series_names else character(0)
    legend_cols  <- if (length(series_names) > 1) cols[seq_along(series_names)] else character(0)
    legend_lty   <- rep(1, length(legend_items))
    legend_lwd   <- rep(.png_lwd(2), length(legend_items))
    if (!is.null(marks)) {
      legend_items <- c(legend_items, marks$items)
      legend_cols  <- c(legend_cols, marks$cols)
      legend_lty   <- c(legend_lty, marks$lty)
      legend_lwd   <- c(legend_lwd, marks$lwd)
    }
    if (length(legend_items) > 0) {
      legend(if (is.null(spec$legend_pos)) "topright" else spec$legend_pos,
             legend = legend_items,
             col    = legend_cols,
             lty    = legend_lty,
             lwd    = legend_lwd,
             bg     = "white")
    }
  })

  if (!is.null(spec$filename)) {
    cat(paste0("\n", spec$label, " plot saved to:"), spec$filename, "\n")
  }
  if (!is.null(spec$csv_file)) {
    .write_plot_csv(spec$csv_table(companion_table), spec$csv_file,
                    paste(spec$label, "data"))
  }
}


# The three in-care tenure statistics the two unified companions are marked at:
# the mean tenure of the standing population and the median and 90th percentile
# of the same tenure distribution (math methods 5.7, 5.8). Taken from the
# results bundle's census matrix when there is one, so the marks, the workbook
# and the deck quote one number; read off the plotted G(x) otherwise, which is
# the same rule applied to the same curve, since sum_x G(x) is that mean and
# .tail_curve_quantile is the convention the bundle's rows are built with.
#
# Unlike the survival plot's median and 90th percentile these are always
# reached, G being a proper distribution's tail on the capped grid, and always
# restricted: a binding cap pulls the 90th percentile toward it with no NA to
# say so (see .resident_tenure_quantile).
.tenure_marks <- function(g, census_mat = NULL, label = NULL) {
  from_bundle <- function(row) {
    if (is.null(census_mat) || is.null(label) ||
        !(row %in% rownames(census_mat)) || !(label %in% colnames(census_mat))) return(NULL)
    as.numeric(census_mat[row, label])
  }
  or_else <- function(row, fallback) {
    value <- from_bundle(row)
    if (is.null(value) || !is.finite(value)) fallback else value
  }
  list(
    median = or_else(RESIDENT_TENURE_QUANTILE_ROWS[1L], .tail_curve_quantile(g, 0.50)),
    p90    = or_else(RESIDENT_TENURE_QUANTILE_ROWS[2L], .tail_curve_quantile(g, 0.10)),
    mean   = or_else("per_resident_past_days", sum(g, na.rm = TRUE))
  )
}

# What the marks say on the in-care tenure profile: the tenure itself, the
# statistic being a statistic OF the quantity that plot's x axis carries.
.tenure_labels <- function(tenure, x_max) {
  list(median = paste0("Median tenure (", .marker_days(tenure$median, x_max), ")"),
       p90    = paste0("P90 tenure (", .marker_days(tenure$p90, x_max), ")"),
       mean   = paste0("Mean tenure (", .marker_days(tenure$mean, x_max), ")"))
}

# The pooled mean daily intake rate, from the results bundle's observations
# matrix. The census-by-tenure profile is the survival curve scaled by it, so
# without it there is no animals scale and the unified companion is not drawn
# at all rather than drawn on some other axis.
#
# Read by name from the same node the marks come from, never off the data
# again: a second count of the intakes here could disagree with the one the
# workbook publishes, and the number is the plot's entire y scale.
.unified_intake_rate <- function(measures, label) {
  obs <- measures$observations
  if (is.null(obs) || !("mean_daily_intakes" %in% rownames(obs)) ||
      !(label %in% colnames(obs))) return(NA_real_)
  as.numeric(obs["mean_daily_intakes", label])
}

# What they say on the remaining-LOS curve: the tenure the mark stands at, and
# the remaining stay the curve reads there.
#
# The marks are borrowed from the tenure profile because this curve has no
# median or 90th percentile of its own to draw. Remaining LOS is a function of
# tenure, not a distribution over animals: the numbers in its column are one
# value per day of tenure, and a median of them would be the median over a day
# grid, answering nothing anyone asked. Remaining LOS AT the median tenure is a
# statement about an animal, the one in the middle of the standing population,
# and that is what these marks report.
#
# Read through .remaining_los_at, the same reading the workbook's
# remaining_days_at_*_tenure rows are made with, so the legend and the reported
# row cannot disagree about which day step a fractional tenure falls in.
#
# Note what the mean mark is NOT. Reading the curve at the mean tenure is not
# the mean remaining stay over residents: that average is sum_d p(d) R(d) =
# 1 + mean tenure exactly, which the tool already reports as
# per_resident_future_days. The gap between the two is Jensen's, and on a
# heavy-tailed shelter it is large. Hence "At mean tenure" rather than "Mean".
.remaining_los_labels <- function(tenure, remaining_los, x_max) {
  phrase <- function(name, x) {
    paste0("At ", name, " tenure (", .marker_days(x, x_max), "): ",
           round(.remaining_los_at(remaining_los, x), 1), " remaining")
  }
  list(median = phrase("median", tenure$median),
       p90    = phrase("P90", tenure$p90),
       mean   = phrase("mean", tenure$mean))
}

#' Plot the unified KM companion curves
#'
#' The whole-data counterparts of the remaining-LOS and in-care-tenure plots
#' plot_stratified_km draws per stratum, from the same unstratified fit that
#' plot_km_curve draws. Both are pure transforms of that one survival curve, so
#' nothing is refitted here.
#'
#' The census-by-tenure companion is drawn here too, and it is the one whose
#' pooled form takes an argument. Its curve is the unified KM curve scaled by a
#' single constant, so as a SHAPE it says nothing the survival plot does not.
#' What the constant buys is the y axis: the curve is then the expected number
#' of animals in care at each day of tenure, it starts at the daily intake
#' rate, and the area under it is the expected census, none of which a
#' probability axis states. That is also the reading the remaining-LOS
#' companion beside it needs, since the future workload is this curve times
#' that one, day by day.
#'
#' Its marks are the in-care tenure statistics, the same three the other two
#' companions carry, because the tenure distribution of the standing population
#' is this curve normalized: N(d) over its own sum. The distinction to hold on
#' to is that N(d) is the DENSITY of that distribution and the in-care tenure
#' profile is its tail, so the median tenure sits where the profile crosses a
#' half but has no such landmark here.
#'
#' Unlike the stratified companions these are not gated by the output flags,
#' which govern the stratified outputs only (see extract_references).
#'
#' @param km_results Results from km_unified_period
#' @param references References list; uses restricted_stay_cap and plot_stay_cap
#' @param base_filename The unified KM plot's filename (km_survival_unified.png);
#'   the companion names are derived from it by substitution. NULL draws to the
#'   active device and writes no CSV.
#' @param measures The results bundle's whole-sample `strata$all` node. When
#'   supplied, the in-care tenure CSV takes its summary row and both plots take
#'   their marks from there rather than deriving them here, so the workbook, the
#'   CSV and the legends print the same numbers rather than several routes to
#'   them. NULL falls back to reading them off the tenure grid, which is the same
#'   rule applied to the same curve (see .tenure_marks).
plot_unified_km_companions <- function(km_results, references, base_filename = NULL,
                                       measures = NULL) {
  km_fit <- km_results$km_fit
  tau    <- references$restricted_stay_cap
  label  <- .km_series_names(km_fit)

  rlos_base    <- if (!is.null(base_filename)) .km_companion_filename(base_filename, "remaining_los") else NULL
  in_care_base <- if (!is.null(base_filename)) .km_companion_filename(base_filename, "in_care_tenure") else NULL
  census_base  <- if (!is.null(base_filename)) .km_companion_filename(base_filename, "census_by_tenure") else NULL

  in_care_table <- .compute_in_care_tenure(km_fit, tau)
  rlos_table    <- .compute_remaining_los(km_fit, tau)

  # The pooled rate, and with it the pooled census profile. NA where the bundle
  # was not supplied or does not carry the rate, in which case this companion
  # drops out below: its y axis IS the rate.
  intake_rate  <- .unified_intake_rate(measures, label)
  census_table <- .compute_census_by_tenure(km_fit, tau,
                                            setNames(list(intake_rate), label))

  # The three in-care tenure statistics, from the bundle where there is one.
  # The mean also feeds the tenure CSV's summary row, and the curve read at it
  # feeds the remaining-LOS CSV's, both looked up by the same label the grid
  # column carries.
  tenure     <- .tenure_marks(in_care_table[[label]], measures$census, label)
  tenure_map <- setNames(list(tenure$mean), label)
  rlos_map   <- setNames(list(.remaining_los_at(rlos_table[[label]], tenure$mean)), label)
  # The census CSV's summary row, from the bundle by the same rule as the
  # others: NULL where the bundle has no such row, which sends
  # .km_companion_csv_table to the column sum the row equals anyway.
  census_map <- if (!is.null(measures$census) &&
                    "expected_census" %in% rownames(measures$census) &&
                    label %in% colnames(measures$census))
                  setNames(list(as.numeric(measures$census["expected_census", label])),
                           label) else NULL

  companions <- list(
    list(label     = "Remaining LOS",
         # Named for what its marks are, because they are not its own. See
         # .remaining_los_labels for why this curve has no statistics of its own
         # to mark.
         title     = "Expected Remaining LOS (tied to in-care tenure statistics)",
         ylab      = "Expected Remaining Days in Care",
         ylim      = NULL,
         # The one companion whose curve climbs into the top right corner.
         legend_pos = "bottomright",
         table     = rlos_table,
         csv_table = function(t) .prepend_restricted_mean_row(
                                   t, rlos_map, label = REMAINING_AT_TENURE_ROWS[1L]),
         markers   = list(values = tenure,
                          labels = .remaining_los_labels(tenure, rlos_table[[label]],
                                                         references$plot_stay_cap)),
         draw      = TRUE,
         filename  = rlos_base,
         csv_file  = if (!is.null(rlos_base)) .plot_csv_filename(rlos_base) else NULL),
    list(label     = "In-care tenure",
         title     = "In-Care Tenure Profile",
         ylab      = "Fraction of In-Care Population With Longer Tenure",
         ylim      = c(0, 1),
         table     = in_care_table,
         csv_table = function(t) .km_companion_csv_table(t, "per_resident_past_days", tenure_map),
         markers   = list(values = tenure,
                          labels = .tenure_labels(tenure, references$plot_stay_cap)),
         draw      = TRUE,
         filename  = in_care_base,
         csv_file  = if (!is.null(in_care_base)) .plot_csv_filename(in_care_base) else NULL),
    list(label     = "Census by tenure",
         title     = "Expected Animals in Care by Tenure",
         ylab      = "Expected Number in Care",
         ylim      = NULL,
         table     = census_table,
         csv_table = function(t) .km_companion_csv_table(t, "expected_census", census_map),
         # The same three marks as the profile above, for the same reason: this
         # curve is that distribution's density and the statistics are the
         # distribution's. What they cannot be read off here is the curve
         # itself; the legend carries their values.
         markers   = list(values = tenure,
                          labels = .tenure_labels(tenure, references$plot_stay_cap)),
         draw      = is.finite(intake_rate),
         filename  = census_base,
         csv_file  = if (!is.null(census_base)) .plot_csv_filename(census_base) else NULL)
  )

  for (spec in companions) .plot_km_companion(spec, length(label), references)
}


#' Plot stratified KM curves
#'
#' @param stratified_results Results from stratified_km_analysis
#' @param references References list; uses references$plot_stay_cap for x-axis limit and
#'   references$show_km_ci_ribbons to toggle per-stratum CI ribbons
#' @param save_prefix Optional prefix for saved plot filenames
# `measures_by_stratifier` is the results bundle's `strata` node, keyed by
# stratifier id. When supplied, the companion CSVs take their summary rows from
# it rather than deriving them here, so a value printed in the workbook and the
# same value printed in a CSV are the same number rather than two routes to it.
# NULL keeps the standalone behavior, deriving each summary from its own grid.
plot_stratified_km <- function(stratified_results, references, save_prefix = NULL,
                               measures_by_stratifier = NULL) {

  # Helper function to plot a single stratified KM
  .plot_single_stratified <- function(km_fit, n_strata, title, filename = NULL, csv_file = NULL,
                                      draw_png = TRUE, rmst_map = NULL) {
    cols <- .get_series_colors(n_strata)
    if (isTRUE(draw_png)) .with_png(filename, {
      plot(km_fit,
           conf.int = FALSE,
           xlab = "Days Already in Care",
           ylab = "Probability Still in Care",
           main = title,
           col = cols,
           lty = 1,
           lwd = .png_lwd(2),
           mark.time = FALSE,
           xlim = c(0, references$plot_stay_cap),
           ylim = c(0, 1))

      .plot_grid()
      # Optional shaded CI ribbons per stratum, drawn as true stair shapes so their
      # edges align exactly with the KM curves' own step jumps (see .ci_ribbon_stair_xy).
      if (isTRUE(references$show_km_ci_ribbons)) {
        x_max <- references$plot_stay_cap
        for (i in seq_along(km_fit$strata)) {
          raw  <- .stratum_ci_steps(km_fit, i)
          poly <- .ci_ribbon_stair_xy(raw$time, raw$lower, raw$upper, x_max)
          ribbon_col <- grDevices::adjustcolor(cols[i], alpha.f = 0.15)
          graphics::polygon(poly$x, poly$y, col = ribbon_col, border = NA)
        }
      }

      # Redraw curves on top of grid (and ribbons)
      lines(km_fit,
            conf.int = FALSE,
            col = cols,
            lty = 1,
            lwd = .png_lwd(2),
            mark.time = FALSE)

      # Add legend
      legend("topright",
             legend = .strip_stratum_prefix(names(km_fit$strata)),
             col = cols,
             lty = 1,
             lwd = .png_lwd(2),
             bg = "white")
    })
    if (!is.null(filename)) cat("\nPlot saved to:", filename, "\n")
    if (!is.null(csv_file)) .export_stratified_km_csv(km_fit, csv_file, references$restricted_stay_cap, rmst_map)
  }

  for (stratifier in stratified_results$stratifiers) {
    info <- .strata_info(stratifier, references)
    if (!info$has) next

    km_fit          <- stratified_results[[stratifier$km_result_key]]
    intake_rates    <- stratified_results$intake_rates[[stratifier$id]]

    # Base PNG paths, derived from save_prefix independently of the emission
    # flags: the companion (remaining-LOS/census/tenure) names are built from
    # the km_survival name by substitution, so that stem is needed even when
    # the km_survival PNG itself is switched off.
    base_filename <- if (!is.null(save_prefix)) paste0(save_prefix, stratifier$suffix, ".png") else NULL
    rlos_base     <- if (!is.null(base_filename)) .km_companion_filename(base_filename, "remaining_los") else NULL
    census_base   <- if (!is.null(base_filename)) .km_companion_filename(base_filename, "census_by_tenure") else NULL
    in_care_base  <- if (!is.null(base_filename)) .km_companion_filename(base_filename, "in_care_tenure") else NULL

    # Per-combo emission flags. draw_* gates the PNG (skip the plot entirely
    # when off, rather than spilling it onto the active device); *_file is the
    # PNG path passed on (NULL when the PNG is off, or when there is no
    # save_prefix -- an interactive fit still draws to the device); *_csv is
    # the companion CSV path (NULL when the CSV is off).
    f_km      <- .output_flag(references, "km_survival_by_stratifier")
    f_rlos    <- .output_flag(references, "km_remaining_los_by_stratifier")
    f_census  <- .output_flag(references, "km_census_by_tenure_by_stratifier")
    f_in_care <- .output_flag(references, "km_in_care_tenure_by_stratifier")

    draw_km      <- isTRUE(f_km[["png"]])
    draw_rlos    <- isTRUE(f_rlos[["png"]])
    draw_census  <- isTRUE(f_census[["png"]])
    draw_in_care <- isTRUE(f_in_care[["png"]])

    filename         <- if (draw_km)      base_filename else NULL
    rlos_filename    <- if (draw_rlos)    rlos_base     else NULL
    census_filename  <- if (draw_census)  census_base   else NULL
    in_care_filename <- if (draw_in_care) in_care_base  else NULL

    csv_file    <- if (isTRUE(f_km[["csv"]])      && !is.null(base_filename)) .plot_csv_filename(base_filename) else NULL
    rlos_csv    <- if (isTRUE(f_rlos[["csv"]])    && !is.null(rlos_base))     .plot_csv_filename(rlos_base)     else NULL
    census_csv  <- if (isTRUE(f_census[["csv"]])  && !is.null(census_base))   .plot_csv_filename(census_base)   else NULL
    in_care_csv <- if (isTRUE(f_in_care[["csv"]]) && !is.null(in_care_base))  .plot_csv_filename(in_care_base)  else NULL

    # One spec per companion output derived from this stratifier's KM fit,
    # consumed by .plot_km_companion in both branches below.
    tau          <- references$restricted_stay_cap
    strata_names <- .strip_stratum_prefix(names(km_fit$strata))

    # Summary rows from the bundle where it was supplied. Looked up by stratum
    # name, never by position: the survfit strata and the bundle's columns are
    # built independently.
    measures <- measures_by_stratifier[[stratifier$id]]
    from_bundle <- function(mat_name, row) {
      m <- measures[[mat_name]]
      if (is.null(m) || !(row %in% rownames(m))) return(NULL)
      vals <- as.list(setNames(as.numeric(m[row, ]), colnames(m)))
      if (!all(strata_names %in% names(vals))) return(NULL)
      vals[strata_names]
    }
    rlos_table    <- .compute_remaining_los(km_fit, tau)
    in_care_table <- .compute_in_care_tenure(km_fit, tau)

    rmst_map     <- from_bundle("km", "km_restricted_mean")
    census_map   <- from_bundle("census", "expected_census")
    tenure_map   <- from_bundle("census", "per_resident_past_days")
    rlos_map     <- from_bundle("census", REMAINING_AT_TENURE_ROWS[1L])
    if (is.null(rmst_map)) rmst_map <- .stratum_rmst_map(km_fit, strata_names, tau)
    if (is.null(rlos_map))
      rlos_map <- .remaining_at_mean_tenure_map(rlos_table, in_care_table, strata_names)
    companions <- list(
      list(label     = "Remaining LOS",
           title     = paste("Expected Remaining LOS by", stratifier$label),
           ylab      = "Expected Remaining Days in Care",
           ylim      = NULL,
           table     = rlos_table,
           csv_table = function(t) .prepend_restricted_mean_row(
                                     t, rlos_map, label = REMAINING_AT_TENURE_ROWS[1L]),
           draw      = draw_rlos,
           filename  = rlos_filename,
           csv_file  = rlos_csv),
      list(label     = "Census by tenure",
           title     = paste("Expected Animals in Care by", stratifier$label),
           ylab      = "Expected Number in Care",
           ylim      = NULL,
           table     = .compute_census_by_tenure(km_fit, tau, intake_rates),
           csv_table = function(t) .km_companion_csv_table(t, "expected_census", census_map),
           draw      = draw_census,
           filename  = census_filename,
           csv_file  = census_csv),
      list(label     = "In-care tenure",
           title     = paste("In-Care Tenure Profile by", stratifier$label),
           ylab      = "Fraction of In-Care Population With Longer Tenure",
           ylim      = c(0, 1),
           table     = in_care_table,
           csv_table = function(t) .km_companion_csv_table(t, "per_resident_past_days", tenure_map),
           draw      = draw_in_care,
           filename  = in_care_filename,
           csv_file  = in_care_csv)
    )

    if (info$n > references$max_plot_strata) {
      cat("\nSkipping KM plot by ", stratifier$label, ": ", info$n,
          " strata exceeds the ", references$max_plot_strata, " strata plot limit.",
          if (!is.null(csv_file)) " CSV still written.", "\n", sep = "")
      if (!is.null(csv_file))
        .export_stratified_km_csv(km_fit, csv_file, references$restricted_stay_cap, rmst_map)
      # Companion CSVs are still written; their PNGs are skipped with the rest.
      for (spec in companions) {
        spec$draw     <- FALSE
        spec$filename <- NULL
        .plot_km_companion(spec, info$n, references)
      }
    } else {
      .plot_single_stratified(
        km_fit,
        info$n,
        paste("Kaplan-Meier Curves by", stratifier$label),
        filename,
        csv_file,
        draw_png = draw_km,
        rmst_map = rmst_map
      )
      for (spec in companions) .plot_km_companion(spec, info$n, references)
    }
  }
}
