# mLOS - Shared Constants and Helpers
# ========================================================
# Source this file first when running the pipeline.
# Defines: MLOS_VERSION,
#          .STRATIFIED_COLORS, .OUTCOME_STATE_LEVELS, .OUTCOME_COLORS,
#          .outcome_label, .outcome_state_colors, .palette_hex, .make_surv_obj,
#          stratifiers, .strata_info, .stratum_levels_present,
#          .total_window_days, .find_observation_gaps, .stratum_gaps,
#          .with_png, .png_lwd, .get_series_colors, .map_period_subsets,
#          .forward_fill, .stratum_range,
#          .extract_km_survival, .extract_stratum_survival,
#          .plot_csv_filename, .write_plot_csv, .output_flag,
#          .poisson_rate_ci, .binom_prop_ci,
#          .stratum_ci_steps, .stair_step_xy, .ci_ribbon_stair_xy,
#          .cif_normalized_rmean, .prepend_restricted_mean_row

# Version of the tool, reported in the console log, in results.json, and on the
# Excel cover sheet. A published result is checkable only as a pair: the DOI of
# the archive and the version a run reported. One number covers the whole
# repository, R side and Python side alike, because one tag produces one
# archive with one DOI; the test suite holds MLOS_VERSION, CITATION.cff, and
# pyproject.toml equal. Bump it when the work of a release is done, then tag.
MLOS_VERSION <- "0.1.2"

# Color palette for stratified curves (period, intake type, animal group).
# One distinct color per stratum: the plot assigns colors positionally and
# never recycles, because max_plot_strata is hard-capped at the palette length
# (see .MAX_PLOT_STRATA_LIMIT below and its enforcement in mlos_setup.R). Leads
# with green/blue/red, then the long-standing rest; extend by appending, never
# reordering, so a given stratum keeps its color across runs.
.STRATIFIED_COLORS <- c("darkgreen", "blue", "red", "orange", "purple",
                        "brown", "pink", "gray40", "cyan", "magenta",
                        "black", "gold3", "turquoise4")

# Canonical outcome-state order: community-live, transfer, non-live -- the
# logical preference order (best outcome first), not alphabetical (which
# would read L, N, T). This is THE ordering: read_and_prepare_data factors
# outcome_type against it at construction (mlos_data.R), and every place that
# lists, plots, or tabulates outcomes downstream (AJ CIF/conditional plots
# and their CSVs, Excel outcome sheets) must derive its order from this
# vector rather than re-sorting the data, so canonical order holds everywhere.
.OUTCOME_STATE_LEVELS <- c("L", "T", "N")

# Outcome type colors (L=community live, T=transfer, N=non-live), drawn from
# the first three entries of .STRATIFIED_COLORS so the outcome-state palette
# and the stratified-curve palette (which includes the stacked area plot,
# CIF plot, and conditional-unified plot) stay in sync from one source.
.OUTCOME_COLORS <- setNames(.STRATIFIED_COLORS[seq_along(.OUTCOME_STATE_LEVELS)],
                             .OUTCOME_STATE_LEVELS)

# The probability-mass histogram's remainder bar: the stays still in care when
# the analysis window closes, which belong to no outcome. Light enough to read
# as the absence of an outcome beside the three filled ones, and outside
# .STRATIFIED_COLORS so it can never collide with an outcome color.
.MASS_REMAINDER_COLOR <- "gray85"

# How many interval ends the probability-mass axis prints before it starts
# thinning them. Twelve is what fits across the standard canvas at the standard
# type size without labels touching.
.MASS_MAX_TICKS <- 12L

# The x-axis tick under the remainder bar. Deliberately not "capped": this
# project already uses that word for fraction_capped, the OBSERVED count of
# stays that reached the cap, while the bar draws the fitted probability of
# still being in care there. On OC2 they read 0.32% and 0.34%, and the user
# guide keeps them apart on purpose. "at cap" names where the bar sits without
# claiming either reading; the legend spells out which one it is.
.MASS_REMAINDER_TICK <- "at cap"

# A probability as a percentage, for a plot label. Two decimals below one
# percent, where the remainder bar usually lands and a single decimal would
# round a real quantity to nothing.
.mass_percent <- function(p) {
  pct <- 100 * p
  ifelse(is.na(pct), "", sprintf(ifelse(pct < 1, "%.2f%%", "%.1f%%"), pct))
}

# Type size for the interval plots' legend and per-bar labels, and the share of
# the panel kept clear above the bars for that legend. One bar label has to fit
# inside one bar's width, and the legend spans the panel in a single row, so
# both are set below the axis type rather than at it.
.MASS_LABEL_CEX <- 0.8
.MASS_HEADROOM  <- 1.22

# The share of the panel between the last interval's bar and the remainder bar,
# and the bar widths that come to. barplot measures spacing in bar widths, which
# is the wrong unit here: a gap fixed at that scale is 15% of the panel at ten
# intervals and 6% at thirty, so it wastes the panel where bars are wide and
# closes where they are narrow. Held at a fixed share instead, it stays the same
# on the page whatever the width, which is what the two ticks either side of it
# need: at thirty intervals "365" and "at cap" are 210 px apart, and they want
# about 165.
.MASS_GAP_FRACTION <- 0.06
.mass_gap_units <- function(n_bars) {
  .MASS_GAP_FRACTION * n_bars / (1 - .MASS_GAP_FRACTION)
}

# Human-readable outcome labels for legends, tables, and plot titles
# @param code Outcome code: "L", "T", or "N"
.outcome_label <- function(code) {
  switch(code, "L" = "L community live", "T" = "T other live", "N" = "N non-live", code)
}

# Resolve R color names to "#RRGGBB". R's color names are not portable: its
# "purple" is #A020F0 where CSS purple is #800080, and names like "gold3" and
# "turquoise4" exist only in R. Downstream renderers therefore get hex, which
# means the same thing in every language and on every platform.
.palette_hex <- function(colors) {
  vapply(colors, function(col) {
    rgb <- grDevices::col2rgb(col)
    sprintf("#%02X%02X%02X", rgb[1], rgb[2], rgb[3])
  }, character(1), USE.NAMES = FALSE)
}

# Colors for a vector of outcome-state codes. States can only be L/T/N here:
# read_and_prepare_data forces outcome_type to factor(levels = .OUTCOME_STATE_LEVELS),
# so an unknown code reaching this point is a programming error, not a data
# condition -- fail loud rather than silently assigning a fallback color.
.outcome_state_colors <- function(states) {
  cols <- .OUTCOME_COLORS[states]
  if (anyNA(cols)) {
    stop("Unknown outcome state code(s): ",
         paste(states[is.na(cols)], collapse = ", "))
  }
  unname(cols)
}

# Hard cap on max_plot_strata. Plotting more strata than the palette has colors
# would recycle colors (indistinguishable curves), so the setting cannot exceed
# the number of colors; mlos_setup.R rejects a larger value.
.MAX_PLOT_STRATA_LIMIT <- length(.STRATIFIED_COLORS)

# Default maximum number of strata for which stratified plots are produced,
# overridable per run via the max_plot_strata setting (references$max_plot_strata,
# which is what the plot code reads; this is only the fallback). When a
# stratifier (period, intake type, or animal group) has more levels than the
# limit, the plot is skipped and only the companion CSV is written. analysis
# (KM fits, Cox regression, AJ) always runs on all strata regardless, so this
# is purely a legibility knob: how many curves stay readable on one panel
# depends on how well they separate, on whether CI ribbons are drawn, and on
# the reader's own preference, none of which the tool can judge.
.MAX_PLOT_STRATA <- 10

# Registry of stratifying dimensions, shared by the stratified KM and AJ
# analyses and the Excel stratum sheets. Each entry carries everything the
# analysis, plotting, export, and test code needs: a short id, the
# period_data column, display label, filename suffix, Excel worksheet name,
# and the names of the references fields holding availability (has_field)
# and level count (n_field). `km_result_key` is the key the stratified KM
# analysis files its fit under; it is KM-specific, since AJ names its
# results by stratifier id instead. Adding a stratifier is one entry here
# plus its references fields (see detect_optional_columns in mlos_data.R,
# which sets has_/n_ for the optional columns).
# model_term is the name this dimension goes by in the Cox and Weibull model
# formulae, which is `col` for every stratifier except period: there the model
# runs on the temporary `period` factor cox_regression_analysis builds from
# period_label, so coefficients read "periodQ2_2024". It is here rather than in
# the two files that need it (mlos_cox.R builds term -> id, mlos_excel_export.R
# the inverse) so those cannot drift apart, and so a stratifier added to this
# registry arrives with its term already known to both.
stratifiers <- list(
  list(id = "period", col = "period_label", label = "Period",       km_result_key = "km_period",
       suffix = "_by_period",       sheet_name = "By_Period",       model_term = "period",
       has_field = "has_period",       n_field = "n_periods"),
  list(id = "intake", col = "intake_type",  label = "Intake Type",  km_result_key = "km_intake",
       suffix = "_by_intake_type",  sheet_name = "By_Intake_Type",  model_term = "intake_type",
       has_field = "has_intake_type",  n_field = "n_intake_types"),
  list(id = "group",  col = "animal_group", label = "Animal Group", km_result_key = "km_group",
       suffix = "_by_animal_group", sheet_name = "By_Animal_Group", model_term = "animal_group",
       has_field = "has_animal_group", n_field = "n_animal_groups")
)

# stratifier id -> its model-formula term, and the inverse. Both are derived
# from the registry above, so neither can fall out of step with it.
.stratifier_model_terms <- function() {
  stats::setNames(vapply(stratifiers, function(s) s$model_term, character(1)),
                  vapply(stratifiers, function(s) s$id, character(1)))
}

.stratifier_ids_by_model_term <- function() {
  terms <- .stratifier_model_terms()
  stats::setNames(names(terms), unname(terms))
}

# Guard for a place the registry cannot wire itself up: the Cox/Weibull
# predictor list, which names its terms and their availability tests one by one
# (a new dimension needs its own has_/relevel handling, so it cannot simply be
# looped over). Called by cox_regression_analysis with the terms it is prepared
# to handle. Without this, a stratifier added to the registry but not wired in
# there would silently never enter either model, and its Weibull_By_... sheet
# would report "not a predictor in the pooled Weibull regression" -- true, but
# as a consequence of the omission rather than of the data, which is exactly
# the kind of wrong answer that looks like a right one.
.assert_stratifier_model_wiring <- function(handled_terms) {
  registry_terms <- unname(.stratifier_model_terms())
  if (!setequal(handled_terms, registry_terms)) {
    stop("The stratifiers registry and the regression predictor wiring disagree.\n",
         "  registry model_terms: ", paste(sort(registry_terms), collapse = ", "), "\n",
         "  wired in cox_regression_analysis: ", paste(sort(handled_terms), collapse = ", "), "\n",
         "A stratifier added to the registry must also be given a predictor entry, an ",
         "availability test and a reference-level rule in cox_regression_analysis (mlos_cox.R), ",
         "or it will be absent from the Cox and Weibull models without any error.",
         call. = FALSE)
  }
  invisible(TRUE)
}

# Retrieve availability (has, n) for a stratifier from references
.strata_info <- function(stratifier, references) {
  list(has = references[[stratifier$has_field]],
       n   = references[[stratifier$n_field]])
}

# Canonical present-level order for a stratum column. The factor levels set
# once at data construction are THE canonical order: chronological for
# period_label (break_down_by_period), alphabetical for intake_type and
# animal_group (read_and_prepare_data).
#
# Why those two orders differ: periods are intervals of dates with a natural
# sequence, and a user shown anything else would rightly read it as wrong
# (Period_10 before Period_2). Intake types and animal groups have NO
# natural order, so alphabetical is chosen purely as a stable convention:
# on a fixed set of categories it never changes from run to run. Ordering
# them by frequency was considered and rejected: when two categories have
# similar counts, a slight tweak to the data (e.g. a small shift of the
# study period) can swap their positions, which makes runs hard to compare
# side by side.
#
# Every consumer reads the order from here rather than re-deriving its own,
# so it cannot drift between the models, the plots, and the worksheets. The
# intersect restricts to levels actually present (consumers must tolerate a
# level whose rows all fell outside the observation window or past the stay
# cap) while preserving level order. Non-factor columns fall back to
# alphabetical, by the same stable-convention reasoning.
.stratum_levels_present <- function(column) {
  values <- as.character(column)
  values <- unique(values[!is.na(values)])
  if (is.factor(column)) intersect(levels(column), values) else sort(values)
}

# Total observation-window length in days: the sum of the defined periods'
# durations. The shared denominator for whole-window (non-period) rates,
# e.g. the intake-type / animal-group census and daily-rate rows.
# @param periods The periods data frame (references$periods)
.total_window_days <- function(periods) {
  sum(as.numeric(periods$duration_days))
}

# Margins for every PNG this project writes, in LINES of text, replacing R's
# stock c(5.1, 4.1, 4.1, 2.1) / c(3, 1, 0). Stock leaves the plot box at 54% of
# the canvas; these bring it to 75% without dropping anything from the figure.
#
# The figures are multi-use on purpose: they go into slides, into an internal
# shelter report, into a paper, and they are opened as PNGs on their own. So
# nothing that lets a figure stand alone is given up here. Axis labels and
# titles all stay; what goes is the empty space R reserved around them. A
# journal wants exactly this, and a slide wants it more.
#
# Two things worth knowing before changing these numbers:
#
#   Margins are measured in lines, so png_pointsize_factor scales them. OC runs
#   at 1.5, which silently made every stock margin half again as wide in
#   inches. Setting them here decouples the two: raising the font no longer
#   buys more whitespace along with it.
#
#   mar[4] holds nothing at all while the axes carry R's default 4% padding,
#   because the last tick label then falls inside the box. It is half a line
#   only so that the frame is not the last ink on the canvas. Switching the
#   axes to xaxs/yaxs = "i" WITHOUT padding the limits by hand would put that
#   label astride the right edge and want about 0.7 lines back.
#
# mgp puts the axis title 1.6 lines out and the tick labels 0.25 out, against
# stock 3 and 1; tcl is positive, which turns the ticks inward so they stop
# spending margin. Titles land just above the box, one single-spaced line up,
# which is where mar[3] of 1.5 lines puts them without any per-plot placement.
.PLOT_MAR <- c(2.7, 2.7, 1.5, 0.5)
.PLOT_MGP <- c(1.6, 0.25, 0)
.PLOT_TCL <- 0.35

# Run plotting code in PNG device when filename is provided.
#
# 3:2 rather than the 4:3 these were drawn at until now. A figure is judged by
# how much of the space it is GIVEN it manages to use, and the spaces it is
# given are wide: a slide slot beneath a table, a text column beside a caption.
# A 4:3 figure dropped into any of them is letterboxed, losing on the slide
# what it never had a chance to spend. 3:2 fills the common slide slot outright
# and is an unremarkable ratio for a journal.
#
# The margins below are in lines and do not shrink with the canvas, so the plot
# box gives back a little of its share of a shorter canvas. That trade is worth
# taking: the share is of a canvas better matched to where the figure lands.
#
# Every plot gets the same margins. There is no per-plot adjustment, and none
# is wanted: the one figure that ever asked for extra bottom margin did so to
# annotate below its x-axis label, and that annotation is gone.
#
# The par() call is here rather than in the caller's code block so that it is
# applied only when a device actually opens: the code block runs on the
# interactive device too, where a par() inside it would stick for every later
# plot.
.with_png <- function(filename, code, width = 3200, height = 2133, res = 300) {
  if (!is.null(filename)) {
    .record_emitted_output(filename)
    pointsize_factor <- getOption("mlos.png.pointsize_factor", 1)
    png(filename,
        width = width,
        height = height,
        res = res,
        pointsize = 12 * pointsize_factor)
    on.exit(dev.off(), add = TRUE)
    # Set AFTER the device opens, since par is per device. Nothing is set when
    # no file was asked for, so an interactive session keeps its own settings.
    par(mar = .PLOT_MAR, mgp = .PLOT_MGP, tcl = .PLOT_TCL)
  }
  force(code)
}

# Scale line widths for PNG plots using a global factor
.png_lwd <- function(lwd) {
  lwd * getOption("mlos.png.line_width_factor", 1)
}

# The grid every plot draws, in one place so the seven of them cannot drift.
#
# Darker than R's "lightgray" default, which survives a 3200px PNG viewed at
# full size and all but disappears once the same figure is shrunk onto a slide.
# Still dotted, and still lighter than any series: a solid gray line at this
# weight starts to read as data rather than as a reference.
#
# Width goes through .png_lwd like every other line, so the grid keeps its
# weight relative to the curves rather than being fixed while they scale.
.plot_grid <- function() {
  grid(col = "gray70", lty = "dotted", lwd = .png_lwd(1))
}

# Get n colors cycling through a palette
.get_series_colors <- function(n, palette = .STRATIFIED_COLORS) {
  palette[(seq_len(n) - 1) %% length(palette) + 1]
}


# Create a counting-process Surv object from period_data columns
# @param df  Data frame with time_start, time_end, and an event column
# @param event  Optional event-indicator override (default: df$event)
.make_surv_obj <- function(df, event = NULL) {
  if (is.null(event)) event <- df$event
  survival::Surv(time  = df$time_start,
                 time2 = df$time_end,
                 event = event,
                 type  = "counting")
}

# Forward-fill a right-continuous step series onto a day grid: for each day,
# the value at the last time <= day, or `fill` for days before the first time.
# `times` must be sorted ascending (survfit time vectors are).
.forward_fill <- function(times, values, days, fill) {
  unname(c(fill, values))[findInterval(days, times) + 1]
}

# =======================================================================
# Probability-mass binning
# =======================================================================

# Right-closed bin edges for a probability-mass histogram, returned as
# c(0, width, 2 * width, ..., last_regular, analysis_cap).
#
# Bins run at the requested width until one of them contains plot_cap, and that
# bin is kept whole rather than cut at the cap. A cut bin spans less time than
# its neighbours and so collects less mass, which the eye reads as a fall in
# the exit rate rather than as a narrower interval.
#
# The single bin from there to analysis_cap carries everything past the plotted
# range, so the bars account for every stay the analysis window resolves. It is
# far wider than the others in days while being drawn the same width, which is
# why the plot labels it as an interval rather than leaving it to be read as a
# rate. A regular edge closer to analysis_cap than one full width is dropped
# into it, since the alternative is a sliver bin at the right-hand end.
#
# Width 0 returns NULL, which is how the whole feature stays off.
.mass_bin_edges <- function(width, plot_cap, analysis_cap) {
  if (length(width) != 1 || is.na(width) || width <= 0) return(NULL)
  width <- as.integer(width)
  analysis_cap <- as.integer(analysis_cap)
  if (is.na(analysis_cap) || analysis_cap <= 0) return(NULL)

  plot_cap <- min(as.integer(plot_cap), analysis_cap)
  last_regular <- min(ceiling(plot_cap / width) * width, analysis_cap)
  regular <- seq(0L, last_regular, by = width)
  # Edge 0 always survives: with a width wider than the cap it is the only
  # regular edge there is, and the result is the single bin (0, analysis_cap].
  regular <- regular[regular == 0L | (analysis_cap - regular) >= width]

  edges <- unique(c(regular, analysis_cap))
  if (length(edges) < 2) return(NULL)
  as.integer(edges)
}

# Interval labels for those edges, in the notation the bins actually use.
.mass_bin_labels <- function(edges) {
  sprintf("(%d,%d]", edges[-length(edges)], edges[-1])
}

# The mass each bin takes out of one or more cumulative series, as a matrix
# with a row per bin and a column per series.
#
# `cumulative` holds non-decreasing series on the `days` grid, read at the bin
# edges as the step functions they are: the value at an edge is the value at
# the last day at or before it, so an edge past the end of the grid takes the
# last fitted value. Holding a series flat past its last observation is what
# the estimators themselves do, and it is why an edge at the analysis cap needs
# no grid running that far.
#
# Nothing here is specific to an estimator: any cumulative grid differences the
# same way, whether it is a CIF, a distribution function, or 1 - S.
.cumulative_bin_masses <- function(days, cumulative, edges) {
  cumulative <- as.matrix(cumulative)
  at_edge <- vapply(seq_len(ncol(cumulative)),
                    function(j) .forward_fill(days, cumulative[, j], edges, 0),
                    numeric(length(edges)))
  masses <- at_edge[-1, , drop = FALSE] - at_edge[-nrow(at_edge), , drop = FALSE]
  rownames(masses) <- .mass_bin_labels(edges)
  colnames(masses) <- colnames(cumulative)
  masses
}


# One value off a curve tabulated by whole day, at an x that need not be one.
# The step covering x is the day below it, so floor() rather than rounding:
# that is the step a vertical line drawn at x crosses on the plot, and it is
# what makes a reported number and the picture beside it agree.
#
# `values` is indexed from day 0. NA for an x outside the grid or not finite,
# which is what a tenure statistic that was never reached gives.
.grid_value_at <- function(values, x) {
  if (!isTRUE(is.finite(x))) return(NA_real_)
  idx <- floor(x) + 1L
  if (idx < 1L || idx > length(values)) return(NA_real_)
  values[[idx]]
}


# 1-based start/end positions of one stratum's block within a survfit object's
# time-ordered vectors ($time, $surv, $lower, ...). A fit with no strata
# (e.g. survfit(surv_obj ~ 1)) is treated as a single stratum spanning the
# whole time vector.
.stratum_range <- function(km_fit, stratum_idx) {
  if (is.null(km_fit$strata)) {
    return(list(start = 1L, end = length(km_fit$time)))
  }
  end <- sum(km_fit$strata[seq_len(stratum_idx)])
  list(start = unname(end - km_fit$strata[stratum_idx] + 1L), end = unname(end))
}

# Extract a KM value series day-by-day from a KM fit (forward-fill)
# @param km_fit  A survfit object (unstratified)
# @param days    Integer vector of days (e.g. 0:max_time)
# @param values  Numeric vector parallel to km_fit$time (default: km_fit$surv)
# @return Numeric vector, length(days)
.extract_km_survival <- function(km_fit, days, values = km_fit$surv) {
  .forward_fill(km_fit$time, values, days, 1.0)
}

# Extract survival probabilities for one stratum from a stratified KM fit (forward-fill)
# @param km_fit_stratified  A (possibly unstratified) survfit object
# @param stratum_idx        1-based index of the stratum
# @param days               Integer vector of days
# @param values             Numeric vector parallel to the fit's $time, sliced to
#                           this stratum here rather than by the caller (default:
#                           $surv; pass $lower or $upper for the CI bounds)
# @return Numeric vector of survival probabilities, length(days)
.extract_stratum_survival <- function(km_fit_stratified, stratum_idx, days,
                                      values = km_fit_stratified$surv) {
  rng <- .stratum_range(km_fit_stratified, stratum_idx)
  idx <- rng$start:rng$end
  .forward_fill(km_fit_stratified$time[idx], values[idx], days, 1.0)
}

# Register of the plot and CSV files this run emitted, so the results manifest
# can describe exactly what was written rather than whatever happens to be
# sitting in the output directory. That distinction is not academic: an earlier
# run's files linger (results/ is not cleared between runs), and a settings
# change or a stratifier the data no longer supports leaves them behind, so
# reading the directory would attribute another run's outputs to this one.
#
# Recorded at the two choke points every output goes through, .with_png and
# .write_plot_csv. reset_emitted_outputs() must be called at the start of a run;
# the test suite calls it per fixture, since one process runs them all.
.emitted_outputs_env <- new.env(parent = emptyenv())
.emitted_outputs_env$files <- character(0)

reset_emitted_outputs <- function() {
  .emitted_outputs_env$files <- character(0)
  invisible(NULL)
}

.record_emitted_output <- function(filename) {
  .emitted_outputs_env$files <- c(.emitted_outputs_env$files, filename)
  invisible(NULL)
}

# Base names of everything written since the last reset, in emission order.
emitted_outputs <- function() unique(basename(.emitted_outputs_env$files))

# Derive the CSV filename that accompanies a saved PNG plot (same path, .csv extension)
.plot_csv_filename <- function(plot_filename) {
  paste0(tools::file_path_sans_ext(plot_filename), ".csv")
}

# The two confidence-interval column headings that belong to a plot companion
# CSV's series column. The bounds sit in their own block to the right of the
# whole estimate grid, paired per series, rather than each beside the column it
# bounds: most readers want the curves alone, and that layout lets them read
# the left of the file and stop.
#
# "_ci_lower"/"_ci_upper" rather than "_lower"/"_upper" because a series heading
# is a data value. A stratum named "LARGE_lower" would collide with the bound
# column of one named "LARGE"; nothing is named "LARGE_ci_lower".
.ci_bound_names <- function(series_name) {
  c(lower = paste0(series_name, "_ci_lower"),
    upper = paste0(series_name, "_ci_upper"))
}

# Write a plot companion CSV and report it on the console
.write_plot_csv <- function(df, filename, label = "Plot data") {
  .record_emitted_output(filename)
  utils::write.csv(df, filename, row.names = FALSE)
  cat(label, "exported to:", filename, "\n")
  invisible(NULL)
}

# Look up a per-stratified-output emission flag (see references$output_flags,
# built in extract_references from the km_survival_by_stratifier / aj_cif_by_stratifier /
# ... settings). Returns a named logical c(png=, csv=): png controls the PNG,
# csv the companion CSV. Defaults to both TRUE when references carries no
# output_flags (e.g. an interactive fit built before this setting existed) or
# the key is absent, so every existing caller keeps producing both files.
.output_flag <- function(references, key) {
  of <- references$output_flags
  if (is.null(of) || is.null(of[[key]])) return(c(png = TRUE, csv = TRUE))
  of[[key]]
}

# Exact 95% CI helpers for count-based estimates, shared by the unified KM
# summary and the workbook's confidence-interval section. Both return
# c(lower, upper), NA when the count or denominator is missing or
# non-positive. .poisson_rate_ci is the exact Poisson (Garwood) interval for
# a count over an exposure, on the per-unit-of-exposure rate scale;
# .binom_prop_ci is the exact binomial (Clopper-Pearson) interval for x
# successes in n trials. The distributional assumptions these add
# (independent occurrences at a constant rate within the window; independent
# Bernoulli trials) are stated in math methods 8.2.
.poisson_rate_ci <- function(count, exposure) {
  if (is.na(count) || is.na(exposure) || exposure <= 0) return(c(NA_real_, NA_real_))
  as.numeric(stats::poisson.test(round(count), exposure)$conf.int)
}
.binom_prop_ci <- function(x, n) {
  if (is.na(x) || is.na(n) || n <= 0) return(c(NA_real_, NA_real_))
  as.numeric(stats::binom.test(round(x), round(n))$conf.int)
}

# Extract the raw (un-resampled) jump times and CI bounds for one stratum from a
# stratified survfit object. Unlike .extract_stratum_survival, this does not forward-fill
# onto a day grid: it returns the exact points at which the step function jumps, which is
# what's needed to draw a true stair-shaped CI ribbon (see .ci_ribbon_stair_xy below).
# @param km_fit_stratified  A (possibly unstratified) survfit object (with conf.int, i.e. $lower/$upper)
# @param stratum_idx        1-based index of the stratum
# @return List with time, lower, upper (numeric vectors, all the same length)
.stratum_ci_steps <- function(km_fit_stratified, stratum_idx) {
  rng <- .stratum_range(km_fit_stratified, stratum_idx)
  idx <- rng$start:rng$end
  list(
    time  = km_fit_stratified$time[idx],
    lower = km_fit_stratified$lower[idx],
    upper = km_fit_stratified$upper[idx]
  )
}

# Build (x, y) coordinates tracing a right-continuous step function as an explicit
# staircase (horizontal run then vertical jump at each point in `times`), suitable for
# polygon() or lines(). `y0` is the value that holds before the first jump (e.g. 1.0 for
# a survival curve at day 0). The staircase is held flat out to `x_max`.
# `values` must be NA-free, which its one caller guarantees: .ci_ribbon_stair_xy
# truncates at the first NA in either CI bound, so both bounds stop together.
.stair_step_xy <- function(times, values, y0, x_max) {
  in_range <- times <= x_max
  times    <- times[in_range]
  values   <- values[in_range]

  x <- 0
  y <- y0
  prev_y <- y0
  for (i in seq_along(times)) {
    x <- c(x, times[i], times[i])
    y <- c(y, prev_y,   values[i])
    prev_y <- values[i]
  }
  x <- c(x, x_max)
  y <- c(y, prev_y)
  list(x = x, y = y)
}

# Build a closed polygon (x, y) tracing a stair-shaped confidence-interval ribbon:
# the lower bound stair from 0 to x_max, then the upper bound stair back from x_max to 0.
# `times`/`lower`/`upper` are raw step points for one stratum, e.g. from .stratum_ci_steps,
# or a daily-tabulated CIF series. `y0` is the value both bounds hold before the first
# step point: 1 for survival curves, 0 for CIFs.
# Returns a polygon with zero-length x/y if no valid (non-NA) CI points remain.
.ci_ribbon_stair_xy <- function(times, lower, upper, x_max, y0 = 1) {
  bad <- is.na(lower) | is.na(upper)
  first_bad <- which(bad)[1]
  if (!is.na(first_bad)) {
    keep  <- seq_len(first_bad - 1)
    times <- times[keep]
    lower <- lower[keep]
    upper <- upper[keep]
  }
  lo <- .stair_step_xy(times, lower, y0, x_max)
  hi <- .stair_step_xy(times, upper, y0, x_max)
  list(x = c(lo$x, rev(hi$x)), y = c(lo$y, rev(hi$y)))
}

# Normalized restricted mean time-to-outcome from a daily CIF series:
# sum_t (CIF(tau) - CIF(t)) / CIF(tau), i.e. the mean days to outcome among
# those who have the outcome by tau. NA if the series is all-NA/empty or
# CIF(tau) is 0 (no such outcomes).
.cif_normalized_rmean <- function(cif_vals) {
  cif_vals <- cif_vals[!is.na(cif_vals)]
  if (length(cif_vals) == 0) return(NA_real_)
  cif_tau <- tail(cif_vals, 1)
  if (isTRUE(all.equal(cif_tau, 0))) return(NA_real_)
  sum(cif_tau - cif_vals, na.rm = TRUE) / cif_tau
}

# Prepend a summary row to a plot-CSV data frame whose first column is Days:
# all columns NA except days = `label` (default "restricted_mean") and any
# entries supplied in `values` (a named list keyed by column name).
.prepend_restricted_mean_row <- function(df, values = list(), label = "restricted_mean") {
  row <- as.data.frame(
    as.list(rep(NA_real_, ncol(df))),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  names(row) <- names(df)
  row$days <- label
  for (nm in names(values)) {
    row[[nm]] <- values[[nm]]
  }
  rbind(row, df)
}

# Find all observation gaps in a set of (time_start, time_end] intervals:
# maximal stretches of days below `cap` covered by no interval, i.e. with no
# animal at risk. Possible with left truncation when everyone at risk
# resolves before a later entrant arrives. This must be computed from the
# intervals themselves: survfit only reports rows AT event/censoring times,
# where n.risk >= 1 by construction, so scanning a fit's n.risk for zeros
# can never find a gap. Returns a data frame with columns gap_start,
# gap_end (0 rows when there are no gaps).
.find_observation_gaps <- function(time_start, time_end, cap) {
  ord    <- order(time_start, time_end)
  starts <- time_start[ord]
  ends   <- time_end[ord]
  gap_starts <- numeric(0)
  gap_ends   <- numeric(0)
  cover_end  <- 0
  for (i in seq_along(starts)) {
    if (starts[i] > cover_end) {
      gap_starts <- c(gap_starts, cover_end)
      gap_ends   <- c(gap_ends, starts[i])
    }
    cover_end <- max(cover_end, ends[i])
  }
  keep <- gap_starts < cap
  data.frame(gap_start = gap_starts[keep], gap_end = gap_ends[keep])
}

# Observation gaps within each level of one stratifier, as a data frame with
# columns stratifier (the display label), stratum, gap_start, gap_end (0 rows
# when there are none). Strata are visited in sorted order, so the row order
# is stable regardless of how the data happens to be arranged.
#
# A small stratum can have a gap even when the pooled data does not, which is
# why this is checked per stratum rather than only on the whole. The gaps are
# a property of the (time_start, time_end] intervals alone: they involve no
# events, outcome types, or fitted model, and the KM and AJ risk sets at any
# time t are the same rows (time_start < t <= time_end). So one scan serves
# both analyses, and both are unreliable from a stratum's first gap onward.
# This returns the gaps without reporting them; each caller words its own
# warning, since the consequence differs by analysis.
.stratum_gaps <- function(period_data, stratifier, cap) {
  empty <- data.frame(stratifier = character(0), stratum = character(0),
                      gap_start = numeric(0), gap_end = numeric(0),
                      stringsAsFactors = FALSE)
  col_values <- as.character(period_data[[stratifier$col]])
  found <- list()
  for (stratum in .stratum_levels_present(period_data[[stratifier$col]])) {
    in_stratum <- !is.na(col_values) & col_values == stratum
    stratum_gaps <- .find_observation_gaps(period_data$time_start[in_stratum],
                                           period_data$time_end[in_stratum],
                                           cap)
    if (nrow(stratum_gaps) == 0) next
    found[[length(found) + 1]] <- data.frame(
      stratifier = stratifier$label,
      stratum    = stratum,
      gap_start  = stratum_gaps$gap_start,
      gap_end    = stratum_gaps$gap_end,
      stringsAsFactors = FALSE
    )
  }
  if (length(found) == 0) return(empty)
  do.call(rbind, found)
}

# Apply callback over the subsets of period_data defined by one stratifying
# column, one call per level. Defaults to period_label, which
# break_down_by_period always provides.
#
# Note the two kinds of subset this produces. Splitting on period_label
# partitions ROWS: break_down_by_period already emits one left-truncated row
# per animal per period, so a period subset asks "what happened during this
# window" and censors each animal at the period boundary. Splitting on any
# other column (intake_type, animal_group) instead keeps ALL of an animal's
# rows across every period; because those intervals are contiguous on the
# days-since-intake axis, the counting-process data reassembles into the
# full stay, so such a subset spans the whole study. Both are correct, they
# just answer different questions.
.map_period_subsets <- function(period_data, callback, col = "period_label") {
  column <- period_data[[col]]
  values <- as.character(column)
  # Iterate in canonical level order via .stratum_levels_present (which also
  # states the ordering rationale), so the AJ per-stratum results, plots,
  # and legends share the models' ordering. That helper covers the
  # non-factor case too (alphabetical), so a genuinely non-factor stratum
  # column a caller might pass gets the same stable order as everywhere
  # else.
  levels_present <- .stratum_levels_present(column)
  results <- vector("list", length(levels_present))
  names(results) <- levels_present
  for (level_name in levels_present) {
    subset_df <- period_data[!is.na(values) & values == level_name, , drop = FALSE]
    results[[level_name]] <- callback(subset_df, level_name)
  }
  results
}
