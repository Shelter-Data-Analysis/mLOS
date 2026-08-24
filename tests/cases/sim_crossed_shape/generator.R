# Data generator for the sim_crossed_shape fixture
# =======================================================================
# Draws a shelter with THREE qualifying predictors, which is what no other
# fixture has, and with a discharge shape that lives in the CELL rather
# than in either dimension that forms it.
#
# Two intake types x two animal groups, and the Weibull shape of the stay
# is a checkerboard across them:
#
#              G1     G2
#     OWNER   0.70   1.30
#     STRAY   1.30   0.70
#
# The checkerboard is the point. Its row means and column means are equal,
# so on the log scale both main effects are exactly zero and an ADDITIVE
# shape formula, shape(intake_type) + shape(animal_group), can do no
# better than one shape for everyone. Only the crossed formula,
# shape(intake_type * animal_group), can see it. A fixture whose shape
# varies along a single dimension would be fitted equally well either
# way and would not exercise the choice at all.
#
# Two study periods are defined with NO true difference between them, so
# period is a qualifying predictor (three are needed before a variant has
# anything to put on shape) and a true-null calibration check at the same
# time.
#
# Generating model
#   - Daily intakes per cell: independent Poisson counts, 3/day in each of
#     the four cells, from 2023-08-15. The first period starts 2024-01-01,
#     about seven mean stays later, so the population builds from empty to
#     steady state before observation opens and the animals still in care
#     on 2024-01-01 enter left-truncated.
#   - Stay: Weibull with the cell's shape k and a common scale of 20 days,
#     discretized to whole days as ceiling(), so arrival and departure days
#     both count and the minimum LOS is 1, matching the tool's convention.
#     The discretization biases the fitted shape slightly upward at these
#     scales, which is why expected.R carries a widened tolerance on k
#     rather than the raw generating value.
#   - Outcome code: L/T/N with probabilities 0.7/0.2/0.1, independent of
#     everything else. The cause dimension is not this fixture's story.
#   - Export date 2024-07-01, the end of the second period, so stays still
#     open then land as right-censored records.
#
# Rerun with:  Rscript tests/cases/sim_crossed_shape/generator.R

args <- commandArgs(trailingOnly = FALSE)
here <- dirname(sub("^--file=", "", args[grepl("^--file=", args)]))
source(file.path(here, "..", "sim_common.R"))

set.seed(20260817)

start_date  <- as.Date("2023-08-15")
export_date <- as.Date("2024-07-01")
scale_days  <- 20
cells <- list(
  list(intake = "OWNER", group = "G1", k = 0.70),
  list(intake = "OWNER", group = "G2", k = 1.30),
  list(intake = "STRAY", group = "G1", k = 1.30),
  list(intake = "STRAY", group = "G2", k = 0.70)
)

days <- seq(start_date, export_date - 1, by = "day")
rows <- list()
for (cell in cells) {
  n_per_day <- rpois(length(days), lambda = 3)
  intakes   <- rep(days, times = n_per_day)
  los       <- pmax(1, ceiling(rweibull(length(intakes), shape = cell$k, scale = scale_days)))
  rows[[length(rows) + 1]] <- data.frame(
    intake_date  = intakes,
    outcome_date = intakes + (los - 1L),
    outcome_type = sample(c("L", "T", "N"), length(intakes),
                          replace = TRUE, prob = c(0.7, 0.2, 0.1)),
    intake_type  = cell$intake,
    animal_group = cell$group,
    stringsAsFactors = FALSE
  )
}

data <- do.call(rbind, rows)
data <- data[order(data$intake_date, data$outcome_date), ]
rownames(data) <- NULL

finalize_and_write(data, export_date, "CROSS", here)
