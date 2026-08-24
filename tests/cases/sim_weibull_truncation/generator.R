# Data generator for the sim_weibull_truncation fixture
# =======================================================================
# Draws a randomized sample of KNOWN behavior: two intake types whose
# lengths of stay follow Weibull distributions with a common shape and a
# 2x scale (LOS) ratio. Intakes arrive from 2024-01-01 (tA), but the
# fixture's settings.yaml defines the study window as 2024-03-01 (tB) to
# 2024-09-01 (tC), so the sample exhibits, with no hand construction:
#   - left truncation:   animals already in care at tB enter the risk set
#                        at time tB - intake_date;
#   - window filtering:  animals that left before tB never appear;
#   - right censoring:   animals still in care at tC (the export date)
#                        have a blank outcome and are censored at tC.
#
# Generating model
#   - Daily intakes per group: independent Poisson(3) counts for every
#     calendar day in [tA, tC).
#   - Stay of each animal: a continuous duration W ~ Weibull(shape
#     k = 1.3, scale 10) for STRAY, Weibull(k = 1.3, scale 20) for OWNER,
#     recorded as an LOS of floor(W) + 1 calendar days. That is the mLOS
#     day-counting convention itself: the arrival and departure days both
#     count, so an animal in and out the same day (any W < 1) has
#     LOS = 1, a W between 1 and 2 spans two calendar days, and so on.
#     Since a continuous draw is never a whole number, floor(W) + 1
#     equals ceiling(W). Thus outcome_date = intake_date + LOS - 1, the
#     event time (outcome_date - intake_date + 1) is exactly ceiling(W),
#     and the discrete survival matches the continuous one at whole
#     days: P(event time > m) = P(W > m) = exp(-(m/scale)^k).
#   - Outcome code: L/T/N with probabilities 0.7/0.2/0.1, independent of
#     group and stay length, so each cause-specific CIF is that fraction
#     of the all-cause CIF.
#
# The generated data.csv is committed alongside this script, so the test
# suite is fully deterministic; re-running this script reproduces it
# byte-for-byte, and changing the seed draws a fresh sample with the same
# statistical properties. The tolerances in expected.R are sized (~4
# standard errors around the truth, plus the documented day-rounding
# bias) so a fresh sample of this size should still pass; the committed
# seed was picked from a short scan of seeds as a TYPICAL draw, because
# the case doubles as a worked example -- a sample whose estimates sit
# 2-3 standard errors from the truth, while statistically unremarkable,
# would make a confusing showcase.
#
# Reproducibility: written under R 4.x with the default RNG
# (Mersenne-Twister / Inversion / Rejection); R >= 3.6 reproduces the
# sample exactly.
#
# Run from anywhere:
#   Rscript tests/cases/sim_weibull_truncation/generator.R
# It writes data.csv next to itself.

set.seed(1)

# Resolve this script's own directory, then load the shared finalize/write
# helper (finalize_and_write) from the parent cases/ directory.
sim_dir <- dirname(sub("^--file=", "",
             grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)))
source(file.path(sim_dir, "..", "sim_common.R"))

intake_start <- as.Date("2024-01-01")   # tA: first intake day
study_start  <- as.Date("2024-03-01")   # tB: study window start (settings.yaml)
study_end    <- as.Date("2024-09-01")   # tC: study window end / export date

groups <- list(
  STRAY = list(rate = 3, shape = 1.3, scale = 10),
  OWNER = list(rate = 3, shape = 1.3, scale = 20)
)
outcome_codes <- c("L", "T", "N")
outcome_probs <- c(0.7, 0.2, 0.1)

intake_days <- seq(intake_start, study_end - 1, by = "day")

per_group <- lapply(names(groups), function(g) {
  spec        <- groups[[g]]
  n_per_day   <- rpois(length(intake_days), spec$rate)
  intake_date <- rep(intake_days, n_per_day)
  n           <- length(intake_date)
  w           <- rweibull(n, shape = spec$shape, scale = spec$scale)
  stay_days   <- floor(w) + 1   # = ceiling(w); same-day intake and outcome is LOS 1
  data.frame(
    intake_date  = intake_date,
    outcome_date = intake_date + stay_days - 1,
    outcome_type = sample(outcome_codes, n, replace = TRUE, prob = outcome_probs),
    intake_type  = g,
    stringsAsFactors = FALSE
  )
})
data <- do.call(rbind, per_group)
data <- data[order(data$intake_date), ]   # file order = intake order (stable)

finalize_and_write(data, study_end, "SIM", sim_dir)
