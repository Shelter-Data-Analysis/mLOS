# Re-derives the two math-methods figures that no run produces
# =======================================================================
# Most numbers the documents quote come out of a standard run, and
# tests/show_guide_examples.py checks those against one. Two do not, and
# this recomputes them on whatever dataset it is pointed at:
#
#   SCAN A, the starting-value grid of section 6.6. Whether flexsurv's own
#     start carries each fit of the Weibull block, and where our grid lands
#     when it does not. Section 6.6 says that on OC2 no fit fails from
#     flexsurv's start while two of the six a run makes stop short of the
#     grid, by 54 and 75 log-likelihood units, both of them carrying shape()
#     terms.
#
#     This scan fits BOTH shape parameterizations whatever the settings say,
#     and it leaves out the crude companion, so its list is not a run's set of
#     fits. The summary lines reconcile the two, which is the arithmetic
#     behind the count section 6.6 quotes.
#
#   SCAN B, the count floor of section 6.7. Fits a Weibull per cell of the
#     intake type x animal group grid and reads off the standard error's
#     constant, the spread of shape between well-populated cells (those
#     holding at least 100 outcomes), and where the two meet. Section 6.7
#     says 0.72/sqrt(n) against a theoretical 0.78, a spread near 19% with
#     k from 0.61 to 1.22, and a meeting point of n = 14 to 16.
#
# Both scans fit through .fit_weibull, so a cell whose default start fails
# is retried exactly as it would be in a run rather than dropped.
#
#   Rscript tests/scan_shape_floor.R data/OC2_data.csv data/OC2_settings.yaml
#
# A settings file with the large dogs cut (other_filter_column_name:
# animal_size, other_filter_cut: LARGE) is what reproduces 6.6's failing
# case; any settings file reproduces 6.7's floor for its own data.

suppressMessages({
  source("mlos_common.R"); source("mlos_setup.R"); source("mlos_data.R")
  source("mlos_km.R");     source("mlos_cox.R")
})

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) stop("usage: Rscript tests/scan_shape_floor.R <data.csv> <settings.yaml>")
data_file <- args[[1]]
settings_file <- args[[2]]

# The floor this scan is checking, and the population threshold section 6.7
# reads "well-populated" as. Both are stated in the document; if either moves,
# the document and this file move together.
WELL_POPULATED <- 100L

invisible(capture.output({
  settings   <- read_settings(settings_file)
  references <- extract_references(settings, define_periods(settings))
  raw        <- read_and_prepare_data(data_file, references)
  references <- detect_optional_columns(raw, references)
  period_data <- break_down_by_period(raw, references)
}))
cat(sprintf("\n%s with %s\n%d rows, %d outcomes\n",
            data_file, settings_file, nrow(period_data), sum(period_data$event)))

# ------------------------------------------------------- SCAN A ------------
# The fits a run makes, in the same releveling, each tried from flexsurv's own
# start before the grid is allowed to help.
cat("\n=== A. starting values (section 6.6) ===\n")
period_data$period <- factor(period_data$period_label,
                             levels = unique(period_data$period_label[order(period_data$period_num)]))
for (col in c("intake_type", "animal_group")) {
  if (!col %in% names(period_data)) next
  period_data[[col]] <- factor(period_data[[col]])
  ref <- references[[paste0(col, "_reference")]]
  if (!is.null(ref) && ref %in% levels(period_data[[col]]))
    period_data[[col]] <- relevel(period_data[[col]], ref = ref)
}
surv_obj <- .make_surv_obj(period_data)

present <- intersect(c("period", "intake_type", "animal_group"), names(period_data))
present <- present[vapply(present, function(p) nlevels(factor(period_data[[p]])) > 1, logical(1))]
scale_side <- paste(c("surv_obj ~ 1", present), collapse = " + ")
formulas <- c(scale_side, "surv_obj ~ 1")
for (term in present) {
  others <- setdiff(present, term)
  if (!length(others)) next
  formulas <- c(formulas, paste(c(scale_side, paste0("shape(", others, ")")), collapse = " + "))
  if (length(others) > 1)
    formulas <- c(formulas, paste(c(scale_side,
      paste0("shape(", paste(others, collapse = " * "), ")")), collapse = " + "))
}
formulas <- unique(formulas)

n_failed_default <- 0L
for (ft in formulas) {
  default <- suppressWarnings(tryCatch(
    flexsurv::flexsurvreg(as.formula(ft), data = period_data, dist = "weibull"),
    error = function(e) e))
  failed <- inherits(default, "error")
  n_failed_default <- n_failed_default + failed
  retried <- .fit_weibull(ft, period_data, environment())
  cat(sprintf("  %-58s default %s | grid %s\n", substr(ft, 1, 58),
              if (failed) "FAILS " else "ok    ",
              if (inherits(retried$fit, "error")) "FAILS TOO"
              else sprintf("k = %.4f%s", retried$fit$res["shape", "est"],
                           if (isTRUE(retried$retried)) " (rescued)" else "")))
}
cat(sprintf("  -> %d of %d fits fail from flexsurv's own start\n",
            n_failed_default, length(formulas)))
cat(sprintf("  -> %d of those %d formulas are additive, which is what a default run fits;\n",
            sum(!grepl("*", formulas, fixed = TRUE)), length(formulas)))
cat("     the run also fits the crude companion of 6.6, which this scan does not list\n")

# ------------------------------------------------------- SCAN B ------------
cat("\n=== B. the count floor (section 6.7) ===\n")
if (!all(c("intake_type", "animal_group") %in% names(period_data))) {
  cat("  needs both intake_type and animal_group; skipped for this dataset\n")
} else {
  grid <- expand.grid(intake = sort(unique(as.character(period_data$intake_type))),
                      group  = sort(unique(as.character(period_data$animal_group))),
                      stringsAsFactors = FALSE)
  rows <- lapply(seq_len(nrow(grid)), function(i) {
    cell <- period_data[as.character(period_data$intake_type) == grid$intake[i] &
                        as.character(period_data$animal_group) == grid$group[i], ]
    out <- data.frame(intake = grid$intake[i], group = grid$group[i],
                      n_outcomes = sum(cell$event), k = NA_real_, se_log_k = NA_real_)
    if (out$n_outcomes < 1 || nrow(cell) < 2) return(out)
    env <- new.env(); assign("surv_obj", .make_surv_obj(cell), envir = env)
    fitted <- .fit_weibull("surv_obj ~ 1", cell, env)
    if (inherits(fitted$fit, "error")) return(out)
    out$k        <- unname(fitted$fit$res["shape", "est"])
    out$se_log_k <- unname(sqrt(diag(fitted$fit$cov))[1])
    out
  })
  cells <- do.call(rbind, rows)
  cells <- cells[order(cells$n_outcomes), ]
  print(cells, row.names = FALSE, digits = 4)

  fitted_cells <- cells[!is.na(cells$k), ]
  well <- fitted_cells[fitted_cells$n_outcomes >= WELL_POPULATED, ]
  constant <- mean(fitted_cells$se_log_k * sqrt(fitted_cells$n_outcomes))
  spread   <- sd(log(well$k))
  cat(sprintf("\n  SE constant: %.3f observed against sqrt(6)/pi = %.4f in theory\n",
              constant, sqrt(6) / pi))
  cat(sprintf("  well-populated (>= %d outcomes): %d of %d cells, k %.2f to %.2f, sd %.3f, spread %.0f%%\n",
              WELL_POPULATED, nrow(well), nrow(cells), min(well$k), max(well$k),
              sd(well$k), 100 * spread))
  cat(sprintf("  floor where they meet: n = %.1f observed, %.1f on the theoretical constant\n",
              (constant / spread)^2, ((sqrt(6) / pi) / spread)^2))
  # The two numbers on the last two lines are not meant to agree. The precision
  # floor above is where a cell's shape becomes as well known as the variation
  # crossing exists to model; the guard sits below it because crossing is only
  # reached when weibull_shape_crossing asks for it, which leaves precision to
  # the caller and leaves the guard the cells that cannot be fitted at all.
  cat(sprintf("  the guard is set at %d, below the precision floor above: crossing is\n",
              .WEIBULL_CROSSING_MIN_EVENTS))
  cat("  opt-in, so the guard refuses only what cannot be fitted (see mlos_cox.R)\n")
}
cat("\n")
