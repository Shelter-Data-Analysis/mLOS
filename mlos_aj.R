# mLOS - Aalen-Johansen Competing-Risk analysis
# =======================================================================
# Uses .OUTCOME_COLORS, .OUTCOME_STATE_LEVELS, .outcome_label, .outcome_state_colors,
#      .STRATIFIED_COLORS, .with_png, .png_lwd, .get_series_colors,
#      .map_period_subsets, .plot_csv_filename, .write_plot_csv, .forward_fill,
#      .cif_normalized_rmean, .prepend_restricted_mean_row,
#      .ci_ribbon_stair_xy,
#      .strata_info, .stratum_gaps,
#      .mass_bin_edges, .cumulative_bin_masses, .MASS_REMAINDER_COLOR,
#      .plot_grid
#      from mlos_common.R

#' Build AJ CIF results table and conditional remaining probabilities
#'
#' @param period_data Data frame from break_down_by_period
#' @param max_time Maximum day to report/plot (default: max observed AJ time)
#' @param print_summary Whether to print summary
#' @param rmean_cap Horizon (in days) for the restricted-mean-days-by-state
#'   table (RMST/RMTL); callers pass references$restricted_stay_cap. NULL
#'   (the default) skips that table.
#' @return List containing AJ fit and CIF results by day
compute_aj_cif_results <- function(period_data,
                                   max_time = NULL,
                                   print_summary = TRUE,
                                   rmean_cap = NULL) {
  # Event coding for the multistate model: first level must be censoring state.
  event_state <- as.character(period_data$outcome_type)
  event_state[is.na(event_state) | period_data$event == 0] <- "Censor"
  outcome_states <- intersect(.OUTCOME_STATE_LEVELS, unique(event_state))

  if (length(outcome_states) == 0) {
    if (isTRUE(print_summary)) {
      cat("\nNo observed outcomes available for competing-risk CIF\n")
    }
    return(list(has_analysis = FALSE, message = "no observed outcomes"))
  }

  event_factor <- factor(event_state, levels = c("Censor", outcome_states))

  # A factor status makes Surv() build the multistate object directly; the
  # older type = "mstate" spelling is deprecated as of survival 3.8 and its
  # survfit path breaks there. The per-row id keeps each row its own subject:
  # rows are independent at-risk intervals, not chained per-animal
  # trajectories (see the math methods document, section 7.1).
  aj_fit <- survival::survfit(
    survival::Surv(period_data$time_start, period_data$time_end, event_factor) ~ 1,
    id = seq_along(event_factor)
  )

  if (is.null(max_time)) {
    max_time <- floor(max(aj_fit$time, na.rm = TRUE))
  }
  max_time <- as.integer(max_time)
  days <- 0:max_time

  # Build daily CIF table via forward-fill from event times.
  pstate_names <- colnames(aj_fit$pstate)
  pstate_names <- pstate_names[!is.na(pstate_names)]
  cif_states <- setdiff(pstate_names, "(s0)")

  cif_matrix   <- matrix(0, nrow = length(days), ncol = length(cif_states))
  lower_matrix <- matrix(0, nrow = length(days), ncol = length(cif_states))
  upper_matrix <- matrix(0, nrow = length(days), ncol = length(cif_states))
  colnames(cif_matrix)   <- paste0("cif_", cif_states)
  colnames(lower_matrix) <- paste0("ci_lower_", cif_states)
  colnames(upper_matrix) <- paste0("ci_upper_", cif_states)

  # $lower/$upper may lack dimnames, so locate each state's column via pstate.
  pstate_cols <- colnames(aj_fit$pstate)
  for (s in cif_states) {
    j <- match(s, pstate_cols)
    cif_matrix[,   paste0("cif_", s)]      <- .forward_fill(aj_fit$time, aj_fit$pstate[, j], days, 0)
    lower_matrix[, paste0("ci_lower_", s)] <- .forward_fill(aj_fit$time, aj_fit$lower[, j],  days, 0)
    upper_matrix[, paste0("ci_upper_", s)] <- .forward_fill(aj_fit$time, aj_fit$upper[, j],  days, 0)
  }

  # Pointwise CI for cif_Any, ready-made from the same fit: cif_Any = 1 minus
  # the in-care probability P(s0), so its bounds are the complements of the
  # (s0) state's bounds, with upper and lower swapping roles. Fill value 1
  # (all in care before the first event) maps to zero-width bounds at 0,
  # matching cif_Any itself.
  j0 <- match("(s0)", pstate_cols)
  if (!is.na(j0)) {
    any_lower <- 1 - .forward_fill(aj_fit$time, aj_fit$upper[, j0], days, 1)
    any_upper <- 1 - .forward_fill(aj_fit$time, aj_fit$lower[, j0], days, 1)
  } else {
    any_lower <- rep(NA_real_, length(days))
    any_upper <- rep(NA_real_, length(days))
  }

  # Build cif_df with only CIF columns first so cif_Any and CondRem are unaffected by CI columns.
  cif_df <- data.frame(days = days, cif_matrix, check.names = FALSE)
  cif_cols <- setdiff(names(cif_df), "days")
  cif_df$cif_Any <- rowSums(cif_df[, cif_cols, drop = FALSE], na.rm = TRUE)

  # Conditional remaining outcome distribution up to cap/max_time:
  # P(outcome = k occurs after day x and by day tau | still at risk at day x)
  # Uses denominator 1 - cif_Any(x), so sums can stay below 1 if some remain undetermined at tau.
  # The epsilon treats a denominator that is zero up to floating-point error
  # as zero: an in-care probability below 1e-9 cannot arise from data (that
  # would take on the order of a billion animals), only from accumulated
  # rounding in the CIF sums, which otherwise admits spurious trailing days
  # whose values are ratios of rounding error. Survival-package versions
  # differ in whether the final cif_Any lands exactly on 1 or a few 1e-13
  # short of it; the guard makes the defined-days boundary version-stable.
  tau <- max_time
  tau_idx <- match(tau, cif_df$days)
  tau_vals <- cif_df[tau_idx, , drop = FALSE]
  at_risk_x <- 1 - cif_df$cif_Any
  cond_cols <- paste0("condrem_", cif_states)
  for (s in cif_states) {
    num <- tau_vals[[paste0("cif_", s)]] - cif_df[[paste0("cif_", s)]]
    cif_df[[paste0("condrem_", s)]] <- ifelse(at_risk_x > 1e-9, num / at_risk_x, NA_real_)
  }

  # Append CI columns after all probability calculations are complete.
  cif_df <- data.frame(cif_df, lower_matrix, upper_matrix,
                       ci_lower_Any = any_lower, ci_upper_Any = any_upper,
                       check.names = FALSE)

  # Restricted mean days in each state within the cap, ready-made from the
  # same fit: summary(aj_fit, rmean = cap)$table reports, per state, the
  # integral of the state-occupancy probability up to the cap with its
  # (infinitesimal-jackknife) standard error, extending the fitted curves
  # flat from the last event to the cap, the same convention as the KM
  # restricted mean. The "(s0)" row is the restricted mean days still in
  # care, identical to the KM RMST (the AJ in-care probability IS the KM
  # curve); each outcome row is the competing-risks "restricted mean time
  # lost" (RMTL) to that outcome, here better read as days already departed
  # via it. The state rows sum to the cap exactly; the appended "Any" row is
  # the summed outcome rows (= cap - RMST) and carries the "(s0)" standard
  # error, since Var(cap - int S) = Var(int S). See math methods 7.7.
  rmtl <- NULL
  if (!is.null(rmean_cap)) {
    rm_tbl <- tryCatch(summary(aj_fit, rmean = rmean_cap)$table, error = function(e) NULL)
    if (!is.null(rm_tbl) && "rmean" %in% colnames(rm_tbl)) {
      rmtl <- data.frame(
        state = rownames(rm_tbl),
        rmean = as.numeric(rm_tbl[, "rmean"]),
        se    = as.numeric(rm_tbl[, "se(rmean)"]),
        stringsAsFactors = FALSE
      )
      is_out <- rmtl$state != "(s0)"
      rmtl <- rbind(rmtl, data.frame(
        state = "Any",
        rmean = sum(rmtl$rmean[is_out]),
        se    = rmtl$se[!is_out][1],
        stringsAsFactors = FALSE
      ))
      rmtl$ci_lower <- rmtl$rmean - 1.96 * rmtl$se
      rmtl$ci_upper <- rmtl$rmean + 1.96 * rmtl$se
    }
  }

  if (isTRUE(print_summary)) {
    cat("\nOutcome states in AJ model: ", paste(cif_states, collapse = ", "), "\n", sep = "")
    cat("Max time used for CIF: ", max_time, " days\n", sep = "")
  }

  return(list(
    has_analysis = TRUE,
    aj_fit = aj_fit,
    outcome_states = cif_states,
    max_time = max_time,
    cif_df = cif_df,
    cond_cols = cond_cols,
    rmtl = rmtl,
    rmtl_cap = if (!is.null(rmtl)) rmean_cap else NULL
  ))
}


#' Run Aalen-Johansen competing-risk analysis and compute CIF curves
#'
#' @param period_data Data frame from break_down_by_period
#' @param max_time Maximum day to report/plot (default: max observed AJ time)
#' @param rmean_cap Horizon for the restricted-mean-days-by-state table
#'   (RMST/RMTL); callers pass references$restricted_stay_cap. NULL skips it.
#' @return List containing AJ fit and CIF results by day
aj_competing_risk_analysis <- function(period_data, max_time = NULL, rmean_cap = NULL) {
  cat("\n=======================================================================\n")
  cat("AALEN-JOHANSEN COMPETING-RISK CIF\n")
  cat("=======================================================================\n")

  results <- compute_aj_cif_results(
    period_data = period_data,
    max_time = max_time,
    print_summary = TRUE,
    rmean_cap = rmean_cap
  )

  # Restricted mean days by state (see compute_aj_cif_results for the
  # construction and conventions). The per-state table, its bounds and the
  # additivity note are on the By_* sheets and in the bundle; the console
  # reports that it was computed and over what horizon.
  if (isTRUE(results$has_analysis) && !is.null(results$rmtl)) {
    cat("Restricted mean days by state computed within cap = ", results$rmtl_cap,
        " days\n", sep = "")
  }

  return(results)
}

.export_aj_cif_csv <- function(aj_results, filename) {
  export_df <- aj_results$cif_df
  export_df$days <- as.character(export_df$days)

  cif_cols <- grep("^cif_", names(export_df), value = TRUE)
  rmeans <- lapply(setNames(cif_cols, cif_cols),
                   function(col) .cif_normalized_rmean(export_df[[col]]))
  export_df <- .prepend_restricted_mean_row(export_df, rmeans)

  .write_plot_csv(export_df, filename)
}

.export_aj_conditional_outcomes <- function(aj_results, filename) {
  df <- aj_results$cif_df
  cond_cols <- aj_results$cond_cols
  keep <- stats::complete.cases(df[, cond_cols, drop = FALSE])

  export_df <- df[keep, c("days", cond_cols), drop = FALSE]
  names(export_df) <- sub("^condrem_", "conditional_", names(export_df))

  .write_plot_csv(export_df, filename)
}


#' Plot AJ competing-risk CIF curves
#'
#' @param aj_results Results from aj_competing_risk_analysis
#' @param references References list; uses references$plot_stay_cap for x-axis limit
#' @param save_file Optional filename for PNG output
plot_aj_cif <- function(aj_results, references, save_file = NULL) {
  if (!isTRUE(aj_results$has_analysis)) {
    cat("No AJ CIF results available to plot.\n")
    return(invisible(NULL))
  }

  cif_df <- aj_results$cif_df
  cif_cols <- grep("^cif_", names(cif_df), value = TRUE)
  cif_cols <- setdiff(cif_cols, "cif_Any")

  states <- sub("^cif_", "", cif_cols)
  cols <- .outcome_state_colors(states)
  x_limit <- references$plot_stay_cap

  .with_png(save_file, {
    lwd <- .png_lwd(2)
    plot(cif_df$days, cif_df[[cif_cols[1]]], type = "n",
         xlab = "Days Already in Care", ylab = "Cumulative Incidence",
         main = "AJ Competing-Risk CIF", xlim = c(0, x_limit), ylim = c(0, 1))

    # CIFs are step functions (jumps at event times), like the KM curve, so
    # draw true steps (type = "s": each day's value holds until the next day)
    # with stair-shaped CI ribbons. The stairs end at the last tabulated day
    # (tau*), never extended flat to the plot limit -- an AJ curve held flat
    # past its last observation would misrepresent unresolved cases.
    ribbon_x_max <- min(x_limit, max(cif_df$days))
    # Crop the drawn series to x_limit: lines() clips at the plot region,
    # which pads ~4% past xlim, so an uncropped curve would run past the
    # ribbon's end when the data extend beyond plot_stay_cap.
    in_plot <- cif_df$days <= x_limit
    for (i in seq_along(cif_cols)) {
      state <- states[i]
      lo_col <- paste0("ci_lower_", state)
      hi_col <- paste0("ci_upper_", state)
      if (lo_col %in% names(cif_df) && hi_col %in% names(cif_df)) {
        ribbon_col <- grDevices::adjustcolor(cols[i], alpha.f = 0.15)
        poly <- .ci_ribbon_stair_xy(cif_df$days, cif_df[[lo_col]], cif_df[[hi_col]],
                                    ribbon_x_max, y0 = 0)
        graphics::polygon(poly$x, poly$y, col = ribbon_col, border = NA)
      }
      lines(cif_df$days[in_plot], cif_df[[cif_cols[i]]][in_plot],
            lwd = lwd, col = cols[i], type = "s")
    }

    .plot_grid()
    legend_labels <- sapply(states, .outcome_label)
    legend("topleft", legend = legend_labels, col = cols, lwd = lwd, bg = "white")
  })
  if (!is.null(save_file)) {
    cat("\nPlot saved to:", save_file, "\n")
    .export_aj_cif_csv(aj_results, .plot_csv_filename(save_file))
  }

  invisible(NULL)
}


#' Plot conditional remaining outcome distribution as stacked areas
#'
#' @param aj_results Results from aj_competing_risk_analysis
#' @param references References list; uses references$plot_stay_cap for x-axis limit
#' @param save_file Optional filename for PNG output
# Shared renderer for the stacked-band plots. Takes the per-outcome series as
# a matrix (one column per state, in the order they should stack from the
# bottom) and fills the area between successive cumulative sums.
#
# Stack plots deliberately carry no companion CSV: they draw the same numbers
# as their line counterpart, whose CSV is right beside them. They also carry no
# confidence-interval ribbons, since bands stacked on top of one another leave
# nowhere to put them and their overlap would be unreadable.
#
# legend_pos is per caller because the bands fill the panel: wherever the legend
# goes it covers data, so it belongs over the flattest part of the stack, which
# differs between the two plots.
.plot_outcome_stack <- function(x, y, states, references, main, ylab, save_file,
                                legend_pos = "bottomleft") {
  cols <- .outcome_state_colors(states)
  x_limit <- references$plot_stay_cap

  .with_png(save_file, {
    plot(c(0, x_limit), c(0, 1), type = "n",
         xlab = "Days Already in Care (x)", ylab = ylab, main = main)
    .plot_grid()
    y_cum <- matrix(0, nrow = nrow(y), ncol = ncol(y))
    for (j in seq_len(ncol(y))) {
      y_cum[, j] <- rowSums(y[, seq_len(j), drop = FALSE], na.rm = TRUE)
    }

    # Band boundaries are drawn as straight lines between the day points, NOT
    # as staircases, and that is a fixed choice rather than a setting. The
    # underlying series really do change only on integer days, which is why the
    # line plots draw them as steps; but a stack of stepped bands puts a
    # sawtooth edge on every boundary at once, and the eye reads the resulting
    # ripple as structure that is not there. Interpolating is purely a
    # presentation choice: the numbers behind these two figures are the same
    # ones their line counterparts plot, and those CSVs are right beside them.
    #
    # All boundaries share the same day grid, so consecutive traces align
    # exactly and no gap can open between bands. The stack ends at the last
    # defined day rather than being extended to the plot limit, since an AJ
    # curve held flat past its last observation would misrepresent the cases
    # still unresolved there.
    in_plot <- x <= min(x_limit, max(x))
    xs      <- x[in_plot]
    base_y  <- rep(0, length(xs))
    for (j in seq_len(ncol(y))) {
      top_y <- y_cum[in_plot, j]
      polygon(c(xs, rev(xs)), c(base_y, rev(top_y)), col = cols[j], border = NA)
      base_y <- top_y
    }

    legend_labels <- sapply(states, .outcome_label)
    legend(legend_pos, legend = legend_labels, fill = cols, bg = "white")
  })
  if (!is.null(save_file)) {
    cat("\nPlot saved to:", save_file, "\n")
  }
  invisible(NULL)
}


#' Plot the conditional remaining outcome distribution as a stack
#'
#' The stacked companion to plot_aj_conditional_unified: identical numbers,
#' read as composition rather than as separate curves. Conditional
#' probabilities sum to 1 on every day, so the bands fill the panel.
#'
#' @param aj_results Results from aj_competing_risk_analysis
#' @param references References list; uses references$plot_stay_cap for x-axis limit
#' @param save_file Optional filename for PNG output
plot_aj_conditional_unified_stack <- function(aj_results, references, save_file = NULL) {
  if (!isTRUE(aj_results$has_analysis)) {
    cat("No AJ results available for conditional distribution plot.\n")
    return(invisible(NULL))
  }

  df <- aj_results$cif_df
  cond_cols <- aj_results$cond_cols
  if (is.null(cond_cols) || length(cond_cols) == 0) {
    cat("No conditional distribution columns available to plot.\n")
    return(invisible(NULL))
  }

  # Use days where conditional probabilities are defined.
  keep <- stats::complete.cases(df[, cond_cols, drop = FALSE])
  if (!any(keep)) {
    cat("No valid days for conditional distribution plot.\n")
    return(invisible(NULL))
  }

  .plot_outcome_stack(
    x = df$days[keep],
    y = as.matrix(df[keep, cond_cols, drop = FALSE]),
    states = sub("^condrem_", "", cond_cols),
    references = references,
    main = "Outcome Type Stack After Day x",
    ylab = "Conditional Probability by Outcome Type",
    save_file = save_file
  )
}


#' The competing-risk probability mass, binned into intervals
#'
#' The CIF curves answer how much has happened by day d; this answers how much
#' happens between one day and the next boundary, which is the quantity an
#' audience hears as "how many leave in the first week". Each bin holds the
#' rise in each outcome's CIF across it, so summing a bin over the outcomes
#' gives the fall in the KM survival curve across the same interval.
#'
#' `remainder` is the probability of still being in care when the analysis
#' window closes, the one part of the distribution no interval can hold.
#' Bin masses and remainder together sum to 1.
#'
#' @param aj_results Results from compute_aj_cif_results
#' @param references References list; uses references$probability_mass_width,
#'   references$plot_stay_cap and references$restricted_stay_cap
#' @return NULL when the width setting is 0 or the fit has nothing to bin;
#'   otherwise a list of edges, masses (a bin-by-outcome matrix), remainder,
#'   and states
aj_probability_mass <- function(aj_results, references) {
  if (!isTRUE(aj_results$has_analysis)) return(NULL)

  edges <- .mass_bin_edges(references$probability_mass_width,
                           references$plot_stay_cap,
                           references$restricted_stay_cap)
  if (is.null(edges)) return(NULL)

  df <- aj_results$cif_df
  # cif_Any is the sum of the per-outcome CIFs, so it is the top of the stack
  # rather than a band in it, and it serves here as the departed-by-now total
  # the remainder is measured against.
  cif_cols <- setdiff(grep("^cif_", names(df), value = TRUE), "cif_Any")
  if (length(cif_cols) == 0) return(NULL)

  masses <- .cumulative_bin_masses(df$days, df[, cif_cols, drop = FALSE], edges)
  colnames(masses) <- sub("^cif_", "", cif_cols)

  last_edge <- edges[length(edges)]
  departed <- .forward_fill(df$days, df$cif_Any, last_edge, 0)
  list(
    edges     = edges,
    masses    = masses,
    remainder = 1 - departed,
    states    = colnames(masses)
  )
}


# Shared renderer for a stacked probability-mass histogram: one bar per bin,
# segments stacked in the order the columns arrive, and a final bar for the
# remainder set apart by a gap and drawn in the remainder color.
#
# The remainder earns a bar rather than being left as the space under a y-axis
# fixed at 1. Its own height is what a reader needs, and on a population that
# mostly leaves early an axis running to 1 spends most of the panel on nothing.
# It is annotated with its value because it can be a hairline: on OC2 it is
# 0.34% of the distribution against a first bar of 59%.
#
# Bars touch, since neighbouring intervals do, and a bin holding no mass shows
# as a gap in a row of bars rather than as missing furniture. The bar for the
# final interval is drawn the same width as the rest while spanning many times
# their days, which is why the axis is labelled with interval ends.
.plot_mass_stack <- function(masses, edges, remainder, states, main, ylab, xlab,
                             remainder_label, remainder_tick, save_file) {
  cols <- c(.outcome_state_colors(states), .MASS_REMAINDER_COLOR)

  # Rows are stack segments and columns are bars, which is the layout barplot
  # stacks. The remainder is a segment present only in its own bar, so it takes
  # a row of its own that is zero everywhere else.
  height <- rbind(t(masses), 0)
  height <- cbind(height, c(rep(0, length(states)), remainder))
  ticks <- c(as.character(edges[-1]), remainder_tick)
  # The remainder bar stands off the row by two bar widths. It is not on the
  # day axis the others sit on, and the gap is also what leaves its label room
  # beside the last interval's end, which is the widest label on the axis.
  space <- c(rep(0, nrow(masses)), 2)
  ylim  <- c(0, max(colSums(height, na.rm = TRUE), na.rm = TRUE) * 1.12)

  # Which interval ends get printed. Left to barplot, a narrow width crowds the
  # axis and R drops whichever labels collide, which took the last interval's
  # end with it: the one bar that spans a different number of days from its
  # neighbours lost the only thing that said so. Thinning from the right
  # instead keeps that end whatever the width, and the remainder bar is always
  # labelled since it stands apart from the axis it is not on.
  n_bin <- nrow(masses)
  step  <- ceiling(n_bin / .MASS_MAX_TICKS)
  shown <- rev(seq(n_bin, 1L, by = -step))

  .with_png(save_file, {
    bar_x <- barplot(height, col = cols, border = NA, space = space,
                     names.arg = rep("", ncol(height)), las = 1, ylim = ylim,
                     xlab = xlab, ylab = ylab, main = main)
    # mtext rather than axis: axis drops labels it judges to collide, and at a
    # narrow width the two it dropped were the last interval's end and the
    # remainder, the two the reader most needs. Thinning is decided above.
    at <- c(shown, n_bin + 1L)
    mtext(ticks[at], side = 1, at = bar_x[at], line = .PLOT_MGP[2])
    # Drawn between two identical bar passes so the grid sits behind the bars:
    # barplot has no panel.first, and a grid over solid fills reads as texture.
    .plot_grid()
    barplot(height, col = cols, border = NA, space = space,
            names.arg = rep("", ncol(height)), axes = FALSE, add = TRUE)

    text(bar_x[length(bar_x)], remainder, pos = 3,
         labels = sprintf("%.2f%%", 100 * remainder))

    legend("topright",
           legend = c(sapply(states, .outcome_label), remainder_label),
           fill = cols, bg = "white")
  })
  if (!is.null(save_file)) {
    cat("\nPlot saved to:", save_file, "\n")
  }
  invisible(NULL)
}


#' Plot the competing-risk probability mass as a stack
#'
#' One bar per interval, each split by outcome, with a remainder bar for the
#' stays still in care at the cap. Stacking is what lets one figure carry both
#' readings: a bar's total is the KM mass over that interval, and its segments
#' divide that total among the outcomes.
#'
#' Carries no companion CSV. Its numbers are neither a day grid nor anywhere
#' else on disk, so they travel in the results bundle instead, where the
#' workbook and every downstream reader can reach them.
#'
#' @param aj_results Results from compute_aj_cif_results
#' @param references References list; see aj_probability_mass
#' @param save_file Optional filename for PNG output
plot_aj_probability_mass_stack <- function(aj_results, references, save_file = NULL) {
  mass <- aj_probability_mass(aj_results, references)
  if (is.null(mass)) {
    cat("No AJ probability-mass bins to plot.\n")
    return(invisible(NULL))
  }

  cap <- references$restricted_stay_cap
  .plot_mass_stack(
    masses = mass$masses,
    edges = mass$edges,
    remainder = mass$remainder,
    states = mass$states,
    main = "AJ Probability Mass Stack",
    ylab = "Probability Mass by Outcome Type",
    xlab = "Days Already in Care (x), interval upper end",
    remainder_label = paste0("still in care at ", cap),
    remainder_tick = "in care",
    save_file = save_file
  )
}


#' Plot the competing-risk cumulative incidence as a stack
#'
#' The stacked companion to plot_aj_cif: the same per-outcome CIF curves, read
#' as composition. The bands sum to the overall CIF, so the top of the stack is
#' the probability of having departed by that day and the space above it is the
#' probability of still being in care. Unlike the line version this carries no
#' confidence-interval ribbons; see .plot_outcome_stack.
#'
#' @param aj_results Results from aj_competing_risk_analysis
#' @param references References list; uses references$plot_stay_cap for x-axis limit
#' @param save_file Optional filename for PNG output
plot_aj_cif_unified_stack <- function(aj_results, references, save_file = NULL) {
  if (!isTRUE(aj_results$has_analysis)) {
    cat("No AJ CIF results available to plot.\n")
    return(invisible(NULL))
  }

  df <- aj_results$cif_df
  # cif_Any is the sum of the per-outcome CIFs, which is exactly the top of the
  # stack, so stacking it too would double the height.
  cif_cols <- setdiff(grep("^cif_", names(df), value = TRUE), "cif_Any")
  if (length(cif_cols) == 0) {
    cat("No CIF columns available to plot.\n")
    return(invisible(NULL))
  }

  keep <- stats::complete.cases(df[, cif_cols, drop = FALSE])
  if (!any(keep)) {
    cat("No valid days for the CIF stack plot.\n")
    return(invisible(NULL))
  }

  .plot_outcome_stack(
    x = df$days[keep],
    y = as.matrix(df[keep, cif_cols, drop = FALSE]),
    states = sub("^cif_", "", cif_cols),
    references = references,
    main = "AJ Cumulative Incidence Stack",
    ylab = "Cumulative Incidence by Outcome Type",
    save_file = save_file,
    # Bottom right: the early days at the left are where the bands rise and
    # their boundaries carry the information, while the right of the stack is
    # flat and solid.
    legend_pos = "bottomright"
  )
}


#' Plot conditional remaining outcome distribution as separate lines
#'
#' @param aj_results Results from aj_competing_risk_analysis
#' @param references References list; uses references$plot_stay_cap for x-axis limit
#' @param save_file Optional filename for PNG output
plot_aj_conditional_unified <- function(aj_results, references, save_file = NULL) {
  if (!isTRUE(aj_results$has_analysis)) {
    cat("No AJ results available for conditional distribution plot.\n")
    return(invisible(NULL))
  }

  df <- aj_results$cif_df
  cond_cols <- aj_results$cond_cols
  if (is.null(cond_cols) || length(cond_cols) == 0) {
    cat("No conditional distribution columns available to plot.\n")
    return(invisible(NULL))
  }

  # Use days where conditional probabilities are defined.
  keep <- stats::complete.cases(df[, cond_cols, drop = FALSE])
  if (!any(keep)) {
    cat("No valid days for conditional distribution plot.\n")
    return(invisible(NULL))
  }

  x <- df$days[keep]
  y <- as.matrix(df[keep, cond_cols, drop = FALSE])
  states <- sub("^condrem_", "", cond_cols)
  cols <- .outcome_state_colors(states)

  x_limit <- references$plot_stay_cap

  .with_png(save_file, {
    lwd <- .png_lwd(2)
    plot(c(0, x_limit), c(0, 1), type = "n",
         xlab = "Days Already in Care (x)",
         ylab = "Conditional Probability by Outcome Type",
         main = "Conditional Remaining Outcome Probability")
    .plot_grid()
    in_plot <- x <= x_limit
    for (j in seq_len(ncol(y))) {
      lines(x[in_plot], y[in_plot, j], lwd = lwd, col = cols[j], type = "s")
    }

    legend_labels <- sapply(states, .outcome_label)
    legend("topleft", legend = legend_labels, col = cols, lwd = lwd, bg = "white")
  })
  if (!is.null(save_file)) {
    cat("\nPlot saved to:", save_file, "\n")
    .export_aj_conditional_outcomes(aj_results, .plot_csv_filename(save_file))
  }

  invisible(NULL)
}


# =======================================================================
# AJ Conditional Outcomes by stratum
# =======================================================================

#' Run AJ conditional-outcome analysis within each level of one stratifier
#'
#' Fits an independent AJ model per stratum (see compute_aj_cif_results, which
#' is stratifier-agnostic) and assembles the per-stratum CIF and conditional
#' series into one long-form frame for plotting and export.
#'
#' Note what a stratum means here, which differs by stratifier: see
#' .map_period_subsets in mlos_common.R. A period subset is censored at the
#' period boundary and so describes that window; an intake_type or
#' animal_group subset keeps all of an animal's rows and so spans the study.
#'
#' @param period_data Data frame from break_down_by_period
#' @param references References list; uses the stratifier's has_field and
#'   references$plot_stay_cap and references$restricted_stay_cap
#' @param stratifier One entry from the `stratifiers` registry in mlos_common.R
#' @param max_time Maximum day to report/plot. Left NULL by callers so each
#'   stratum's grid ends at its own last fitted time. This is safe to leave
#'   ragged: a CIF is flat past its last event, so CIF(tau) - and with it every
#'   CondRem value and .cif_normalized_rmean - is unchanged by any larger tau.
#' @return List containing per-stratum AJ results and long-form conditional data
aj_by_stratifier <- function(period_data,
                             references,
                             stratifier,
                             max_time = NULL) {
  cat("\n=======================================================================\n")
  cat("AJ CONDITIONAL OUTCOMES BY ", toupper(stratifier$label), "\n", sep = "")
  cat("=======================================================================\n")

  # Compute wherever there is something to compute. Whether the result is worth
  # PLOTTING is a separate question, answered by the caller through
  # .strata_info: curves for a single-level stratifier are the unified curves
  # redrawn, so they are not worth a figure, but the numbers behind them are
  # still needed (a single-period run's By_Period column, for instance). This
  # gate therefore asks only whether the column exists with any level at all.
  levels_present <- if (is.null(period_data[[stratifier$col]])) character(0)
                    else .stratum_levels_present(period_data[[stratifier$col]])
  if (length(levels_present) == 0) {
    cat("\nNo ", tolower(stratifier$label), " levels present - skipping\n", sep = "")
    return(list(has_analysis = FALSE))
  }

  # Per-stratum gap check (see .stratum_gaps): the KM and AJ risk sets are the
  # same rows, so these are the same gaps stratified_km_analysis reports. Worth
  # repeating here because the consequence for AJ is its own: a stratum with no
  # one at risk contributes no events, so its CIF stalls and its conditional
  # probabilities understate what follows, from the first gap onward.
  stratum_gaps <- .stratum_gaps(period_data, stratifier, references$restricted_stay_cap)
  for (i in seq_len(nrow(stratum_gaps))) {
    cat("*** WARNING: Gap in observations for ", stratum_gaps$stratifier[i], " '",
        stratum_gaps$stratum[i], "' from day ", stratum_gaps$gap_start[i],
        " to day ", stratum_gaps$gap_end[i],
        " - its AJ curves are unreliable from there on ***\n", sep = "")
  }

  per_stratum <- list()
  cond_long_list <- list()
  all_outcomes <- character(0)

  stratum_runs <- .map_period_subsets(period_data, function(subset_df, stratum_name) {
    cat("\n--- ", stratifier$label, ": ", stratum_name, " (n=", nrow(subset_df), ") ---\n", sep = "")
    res <- compute_aj_cif_results(
      period_data = subset_df,
      max_time = max_time,
      print_summary = FALSE,
      rmean_cap = references$restricted_stay_cap
    )
    if (!isTRUE(res$has_analysis)) {
      cat("  skipped: no analyzable outcomes\n")
      return(NULL)
    }
    cat("  outcomes: ", paste(res$outcome_states, collapse = ", "), "\n", sep = "")
    res
  }, col = stratifier$col)

  for (stratum_name in names(stratum_runs)) {
    res <- stratum_runs[[stratum_name]]
    if (is.null(res) || !isTRUE(res$has_analysis)) next
    per_stratum[[stratum_name]] <- res
    all_outcomes <- union(all_outcomes, res$outcome_states)
    for (outcome in res$outcome_states) {
      cond_col <- paste0("condrem_", outcome)
      cond_long_list[[length(cond_long_list) + 1]] <- data.frame(
        stratum = stratum_name,
        days = res$cif_df$days,
        Outcome = outcome,
        conditional_probability = res$cif_df[[cond_col]],
        cif_Any = res$cif_df$cif_Any,
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(per_stratum) == 0 || length(cond_long_list) == 0) {
    cat("\nNo usable AJ results by ", stratifier$label, "\n", sep = "")
    return(list(has_analysis = FALSE))
  }

  cond_long <- do.call(rbind, cond_long_list)

  return(list(
    has_analysis = TRUE,
    stratifier = stratifier,
    strata = names(per_stratum),
    n_strata = length(per_stratum),
    outcome_states = intersect(.OUTCOME_STATE_LEVELS, all_outcomes),
    per_stratum = per_stratum,
    cond_long = cond_long,
    gaps = stratum_gaps,
    plot_xlim = references$plot_stay_cap,
    max_plot_strata = references$max_plot_strata
  ))
}


# Wide-form export: one column per stratum over the union of their days. A
# stratum whose grid ends earlier (its last event came sooner) gets NA in the
# tail rather than a filled-in value, matching the estimator's own refusal to
# extend a CIF past its last observation.
#
# ci_lower_col/ci_upper_col name the columns of `plot_df` holding the pointwise
# bounds, and add a block of paired bound columns to the right of the whole
# estimate grid (see .ci_bound_names). NULL, or a metric whose `plot_df` carries
# no such columns, writes the estimates alone: the conditional probabilities are
# a ratio of CIF differences and the fit gives them no interval, so that family
# has no bounds to write and its plots draw no ribbons.
.export_aj_metric_by_stratum_plot_csv <- function(plot_df, strata, value_col, filename,
                                                  include_restricted_mean = FALSE,
                                                  ci_lower_col = NULL, ci_upper_col = NULL) {
  all_days <- sort(unique(plot_df$days))
  export_df <- data.frame(days = as.character(all_days), check.names = FALSE)

  # One stratum's column of `col`, laid out on the union day grid.
  on_day_grid <- function(stratum_df, col) {
    values <- rep(NA_real_, length(all_days))
    if (nrow(stratum_df) > 0) {
      day_index <- match(all_days, stratum_df$days)
      matched <- !is.na(day_index)
      values[matched] <- stratum_df[[col]][day_index[matched]]
    }
    values
  }

  stratum_rows <- lapply(setNames(strata, strata),
                         function(nm) plot_df[plot_df$stratum == nm, , drop = FALSE])

  for (stratum_name in strata) {
    export_df[[stratum_name]] <- on_day_grid(stratum_rows[[stratum_name]], value_col)
  }

  has_ci <- !is.null(ci_lower_col) && !is.null(ci_upper_col) &&
    all(c(ci_lower_col, ci_upper_col) %in% names(plot_df))
  if (has_ci) {
    for (stratum_name in strata) {
      ci <- .ci_bound_names(stratum_name)
      export_df[[ci[["lower"]]]] <- on_day_grid(stratum_rows[[stratum_name]], ci_lower_col)
      export_df[[ci[["upper"]]]] <- on_day_grid(stratum_rows[[stratum_name]], ci_upper_col)
    }
  }

  if (isTRUE(include_restricted_mean)) {
    rmeans <- lapply(setNames(strata, strata),
                     function(stratum_name) .cif_normalized_rmean(export_df[[stratum_name]]))
    export_df <- .prepend_restricted_mean_row(export_df, rmeans)
  }

  .write_plot_csv(export_df, filename)
}


#' Internal helper: plot one AJ metric by stratum as overlapping lines (one plot per outcome)
#'
#' @param aj_stratum_results Results from aj_by_stratifier
#' @param save_prefix Optional filename prefix for PNG outputs
#' @param value_col Column name in cif_df to plot (e.g. "condrem_L" or "cif_L")
#' @param ylab Y-axis label
#' @param main_prefix Plot title prefix (outcome code is appended)
#' @param main_suffix Plot title suffix, appended after the outcome
#' @param outcome_formatter Optional function to format outcome code for the title
#' @param include_restricted_mean Whether to prepend a restricted_mean row (the
#'   normalized CIF restricted mean per stratum, see .cif_normalized_rmean) to the
#'   companion CSV; the plot itself is unaffected
#' @param show_ci_ribbons Whether to draw a shaded CI ribbon per stratum. Affects
#'   the plot only: the bounds go to the companion CSV either way, since whether
#'   a band is legible on a panel says nothing about whether the reader wants
#'   the numbers
#' @param ci_lower_col Column name in cond_long holding the CI lower bound
#' @param ci_upper_col Column name in cond_long holding the CI upper bound
.plot_aj_metric_by_stratum_lines <- function(aj_stratum_results,
                                             save_prefix = NULL,
                                             value_col,
                                             ylab,
                                             main_prefix,
                                             main_suffix = "",
                                             outcome_formatter = NULL,
                                             include_restricted_mean = FALSE,
                                             show_ci_ribbons = FALSE,
                                             ci_lower_col = NULL,
                                             ci_upper_col = NULL,
                                             emit_png = TRUE,
                                             emit_csv = TRUE) {
  if (!isTRUE(aj_stratum_results$has_analysis)) {
    cat("No by-stratum AJ results available to plot.\n")
    return(invisible(NULL))
  }

  x_limit <- aj_stratum_results$plot_xlim
  label <- aj_stratum_results$stratifier$label

  strata <- aj_stratum_results$strata
  # Counts strata that produced usable AJ results, whereas the KM limit counts
  # the stratifier's levels. The two differ only when a stratum has no
  # analyzable outcomes at all, in which case KM can skip a plot that AJ still
  # draws. Rare enough to leave alone; noted in the User Guide.
  max_strata <- aj_stratum_results$max_plot_strata
  too_many <- length(strata) > max_strata
  if (too_many) {
    cat("\nSkipping AJ plots by ", label, ": ", length(strata), " strata exceeds the ",
        max_strata, " strata plot limit.",
        if (emit_csv) " CSVs still written.", "\n", sep = "")
  }
  cols <- .get_series_colors(length(strata))
  for (outcome in aj_stratum_results$outcome_states) {
    plot_df <- aj_stratum_results$cond_long[
      aj_stratum_results$cond_long$Outcome == outcome &
      !is.na(aj_stratum_results$cond_long[[value_col]]), , drop = FALSE
    ]

    if (nrow(plot_df) == 0) {
      cat("No data to plot for outcome:", outcome, "\n")
      next
    }

    # Scaled to the days the panel shows, not the whole tabulated range: the
    # series run to restricted_stay_cap while lines() below crops them at
    # x_limit, and a CIF still climbing past the cap would squash the visible
    # part of every stratum into the bottom of the panel. A stratum whose
    # values all sit past the cap falls back to the full range, there being
    # nothing in view to scale to.
    y_vals <- plot_df[[value_col]][plot_df$days <= x_limit]
    y_vals <- y_vals[is.finite(y_vals)]
    if (length(y_vals) == 0) {
      y_vals <- plot_df[[value_col]]
      y_vals <- y_vals[is.finite(y_vals)]
    }
    if (length(y_vals) == 0) {
      cat("No finite y-values to plot for outcome:", outcome, "\n")
      next
    }
    y_min <- min(y_vals, na.rm = TRUE)
    y_max <- max(y_vals, na.rm = TRUE)
    if (isTRUE(all.equal(y_min, y_max))) {
      pad <- if (isTRUE(all.equal(y_min, 0))) 0.05 else max(0.01, abs(y_min) * 0.05)
      y_min <- y_min - pad
      y_max <- y_max + pad
    }

    png_file <- if (!is.null(save_prefix) && !too_many && emit_png) paste0(save_prefix, "_outcome_", outcome, ".png") else NULL
    csv_file <- if (!is.null(save_prefix) && emit_csv) .plot_csv_filename(paste0(save_prefix, "_outcome_", outcome, ".png")) else NULL
    outcome_title <- if (is.null(outcome_formatter)) outcome else outcome_formatter(outcome)
    if (!too_many && emit_png) {
      .with_png(png_file, {
        plot(c(0, x_limit), c(y_min, y_max), type = "n",
             xlab = "Days Already in Care (x)",
             ylab = ylab,
             main = paste0(main_prefix, outcome_title, main_suffix))
        .plot_grid()
        legend_labels <- character(0)
        legend_cols <- character(0)

        for (i in seq_along(strata)) {
          stratum_name <- strata[i]
          stratum_df <- plot_df[plot_df$stratum == stratum_name, , drop = FALSE]
          if (nrow(stratum_df) == 0) next
          # Step rendering (type = "s" and stair ribbons), matching the pooled
          # CIF plot: these series are step functions of the day, and the
          # stairs end at the stratum's own last tabulated day rather than
          # being extended flat to the plot limit.
          if (isTRUE(show_ci_ribbons) &&
              !is.null(ci_lower_col) && !is.null(ci_upper_col) &&
              ci_lower_col %in% names(stratum_df) && ci_upper_col %in% names(stratum_df) &&
              !all(is.na(stratum_df[[ci_lower_col]])) && !all(is.na(stratum_df[[ci_upper_col]]))) {
            ribbon_col <- grDevices::adjustcolor(cols[i], alpha.f = 0.10)
            poly <- .ci_ribbon_stair_xy(stratum_df$days,
                                        stratum_df[[ci_lower_col]],
                                        stratum_df[[ci_upper_col]],
                                        min(x_limit, max(stratum_df$days)), y0 = 0)
            graphics::polygon(poly$x, poly$y, col = ribbon_col, border = NA)
          }
          # Crop to x_limit like the pooled CIF plot: lines() clips at the
          # plot region, which pads ~4% past xlim, so an uncropped series
          # would run past the ribbon's end.
          in_plot <- stratum_df$days <= x_limit
          lines(stratum_df$days[in_plot], stratum_df[[value_col]][in_plot],
                col = cols[i], lwd = .png_lwd(2), type = "s")
          legend_labels <- c(legend_labels, stratum_name)
          legend_cols <- c(legend_cols, cols[i])
        }

        if (length(legend_labels) > 0) {
          legend("bottomright", legend = legend_labels, col = legend_cols,
                 lwd = .png_lwd(2), bg = "white")
        }
      })
      if (!is.null(png_file)) cat("Plot saved to:", png_file, "\n")
    }
    if (!is.null(csv_file)) {
      .export_aj_metric_by_stratum_plot_csv(
        plot_df = plot_df,
        strata = strata,
        value_col = value_col,
        filename = csv_file,
        include_restricted_mean = include_restricted_mean,
        ci_lower_col = ci_lower_col,
        ci_upper_col = ci_upper_col
      )
    }
  }

  invisible(NULL)
}

#' Plot AJ conditional outcome probability by stratum (one plot per outcome)
#'
#' @param aj_stratum_results Results from aj_by_stratifier
#' @param references References list; uses references$output_flags to toggle
#'   the PNG/CSV outputs (aj_conditional_by_stratifier). NULL emits both.
#' @param save_prefix Optional filename prefix for PNG outputs
plot_aj_conditional_by_stratum_lines <- function(aj_stratum_results, references = NULL, save_prefix = NULL) {
  if (!isTRUE(aj_stratum_results$has_analysis)) {
    cat("No by-stratum AJ results available to plot.\n")
    return(invisible(NULL))
  }
  flag <- .output_flag(references, "aj_conditional_by_stratifier")
  # The stratifier goes in the title, not just the legend: the same outcome is
  # plotted once per stratifier, so the titles would otherwise be identical.
  .plot_aj_metric_by_stratum_lines(
    aj_stratum_results = aj_stratum_results,
    save_prefix = save_prefix,
    value_col = "conditional_probability",
    ylab = "Conditional Probability",
    main_prefix = "P(",
    main_suffix = paste0(" after day x | in care on day x) by ",
                         aj_stratum_results$stratifier$label),
    outcome_formatter = .outcome_label,
    emit_png = isTRUE(flag[["png"]]),
    emit_csv = isTRUE(flag[["csv"]])
  )
}


#' Plot AJ CIF by stratum (one plot per outcome)
#'
#' @param aj_stratum_results Results from aj_by_stratifier
#' @param references References list; uses references$show_aj_cif_ci_ribbons to toggle CI ribbons
#' @param save_prefix Optional filename prefix for PNG outputs
plot_aj_cif_by_stratum_lines <- function(aj_stratum_results, references = NULL, save_prefix = NULL) {
  if (!isTRUE(aj_stratum_results$has_analysis)) {
    cat("No by-stratum AJ results available to plot.\n")
    return(invisible(NULL))
  }

  cif_long <- aj_stratum_results$cond_long
  cif_long$CIF <- NA_real_
  cif_long$ci_lower <- NA_real_
  cif_long$ci_upper <- NA_real_
  for (stratum_name in names(aj_stratum_results$per_stratum)) {
    res <- aj_stratum_results$per_stratum[[stratum_name]]
    if (is.null(res) || !isTRUE(res$has_analysis)) next
    for (outcome in res$outcome_states) {
      cif_col <- paste0("cif_", outcome)
      if (!cif_col %in% names(res$cif_df)) next
      idx <- cif_long$stratum == stratum_name & cif_long$Outcome == outcome
      if (!any(idx)) next
      cif_long$CIF[idx] <- res$cif_df[[cif_col]]

      lo_col <- paste0("ci_lower_", outcome)
      hi_col <- paste0("ci_upper_", outcome)
      if (lo_col %in% names(res$cif_df) && hi_col %in% names(res$cif_df)) {
        cif_long$ci_lower[idx] <- res$cif_df[[lo_col]]
        cif_long$ci_upper[idx] <- res$cif_df[[hi_col]]
      }
    }
  }

  aj_cif_stratum_results <- aj_stratum_results
  aj_cif_stratum_results$cond_long <- cif_long

  flag <- .output_flag(references, "aj_cif_by_stratifier")
  .plot_aj_metric_by_stratum_lines(
    aj_stratum_results = aj_cif_stratum_results,
    save_prefix = save_prefix,
    value_col = "CIF",
    ylab = "CIF",
    main_prefix = "AJ CIF: ",
    main_suffix = paste0(" by ", aj_stratum_results$stratifier$label),
    outcome_formatter = .outcome_label,
    include_restricted_mean = TRUE,
    show_ci_ribbons = isTRUE(references$show_aj_cif_ci_ribbons),
    ci_lower_col = "ci_lower",
    ci_upper_col = "ci_upper",
    emit_png = isTRUE(flag[["png"]]),
    emit_csv = isTRUE(flag[["csv"]])
  )
}
