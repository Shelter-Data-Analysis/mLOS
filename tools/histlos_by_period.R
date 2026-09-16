# HistLOS by period, for teaching only: the naive LOS distribution built from
# the whole stays of animals whose outcome falls in each period, to contrast
# with the left-truncated and right-censored estimate mLOS reports (ExitLOS).
#
# Usage (from the mLOS working copy):
#   Rscript tools/histlos_by_period.R [--settings FILE] [--data FILE] --results DIR

suppressMessages({
  source("mlos_common.R"); source("mlos_setup.R")
  source("mlos_data.R");   source("mlos_km.R")
})

args <- commandArgs(trailingOnly = TRUE)
opt <- list(settings = file.path("data", "OC2_settings.yaml"),
            data     = file.path("data", "OC2_data.csv"),
            results  = NULL)
for (i in seq(1, length(args), by = 2)) opt[[sub("^--", "", args[i])]] <- args[i + 1]
if (is.null(opt$results)) stop("--results DIR is required")
dir.create(opt$results, recursive = TRUE, showWarnings = FALSE)
out <- function(f) file.path(opt$results, f)

settings   <- read_settings(opt$settings)
references <- extract_references(settings, define_periods(settings))
options(mlos.png.pointsize_factor = references$png_pointsize_factor)
options(mlos.png.line_width_factor = references$png_line_width_factor)
invisible(capture.output(data <- read_and_prepare_data(opt$data, references)))
periods <- references$periods
cap     <- references$restricted_stay_cap

# One row per classified exit, assigned to the period holding its outcome date
# (left-closed, as in break_down_by_period), with the whole stay counted.
hist <- data[!is.na(data$outcome_type) & !is.na(data$outcome_date), ]
idx  <- findInterval(as.numeric(hist$outcome_date),
                     as.numeric(c(periods$start_date, utils::tail(periods$end_date, 1))))
keep <- idx >= 1 & idx <= nrow(periods)
hist <- hist[keep, ]
hist$period_label <- droplevels(factor(periods$period_label[idx[keep]],
                                       levels = periods$period_label))
los <- as.numeric(hist$outcome_date - hist$intake_date) + 1
hist$time_start <- 0
hist$time_end   <- pmin(los, cap)
hist$event      <- as.integer(los <= cap)

fit <- survival::survfit(.make_surv_obj(hist) ~ period_label, data = hist)
labels <- .strip_stratum_prefix(names(fit$strata))

q <- quantile(fit, probs = c(0.5, 0.9), conf.int = FALSE)
summary_rows <- data.frame(period          = labels,
                           median          = as.numeric(q[, 1]),
                           restricted_mean = as.numeric(summary(fit, rmean = cap)$table[, "rmean"]),
                           p90             = as.numeric(q[, 2]))
.write_plot_csv(summary_rows, out("histlos_by_period_summary.csv"), "Summary")
print(summary_rows, row.names = FALSE)

# Styled as km_survival_by_period.png.
cols <- .get_series_colors(length(labels))
.with_png(out("histlos_by_period.png"), {
  plot(fit, conf.int = FALSE, col = cols, lty = 1, lwd = .png_lwd(2), mark.time = FALSE,
       xlim = c(0, references$plot_stay_cap), ylim = c(0, 1),
       xlab = "Days Already in Care", ylab = "Probability Still in Care",
       main = "HistLOS by Period")
  .plot_grid()
  lines(fit, conf.int = FALSE, col = cols, lty = 1, lwd = .png_lwd(2), mark.time = FALSE)
  legend("topright", legend = labels, col = cols, lty = 1, lwd = .png_lwd(2), bg = .LEGEND_BG)
})
.export_stratified_km_csv(fit, out("histlos_by_period.csv"), cap)
