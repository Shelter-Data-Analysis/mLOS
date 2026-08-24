# Data generator for the sim_size_mixture fixture
# =======================================================================
# Draws a randomized sample with STATIC HETEROGENEITY and nothing else:
# two dog sizes, each with a perfectly memoryless (geometric) stay, and
# NO change of any kind over calendar time.
#
#   SMALL: 70% of intakes, daily outcome probability q = 0.12
#          (mean stay 8.33 days)
#   LARGE: 30% of intakes, daily outcome probability q = 0.03
#          (mean stay 33.3 days)
#
# The point of the case is what this mixture does to POOLED (unadjusted)
# analyses: the pooled hazard declines with tenure -- not because any
# dog's prospects change (no individual's ever do), but because the
# fast-leaving small dogs drain out of the risk set first, leaving the
# long-staying large dogs behind. This is the classic frailty /
# unobserved-heterogeneity artifact of the survival literature, in its
# simplest possible form: a two-point mixture of constant hazards.
# A field-known corollary: although large dogs are only 30% of intakes,
# at steady state they are ~63% of the animals in residence (census
# share of a group scales as intake share / departure rate).
#
# Two study periods are defined with NO true difference between them
# (nothing changes on the boundary), giving the suite a true-null
# calibration check: the Cox period hazard ratio must come out 1.
#
# Generating model
#   - Daily intakes per size: independent Poisson counts (7/day SMALL,
#     3/day LARGE) for every calendar day from 2023-09-01. The study's
#     first period starts 2024-05-01, ~7 time constants of the SLOW
#     group (1/q = 33 days) later, so the population builds from empty
#     to steady state before observation begins and the animals still
#     in care on 2024-05-01 enter left-truncated.
#   - Stay of each animal: geometric within its size (floor definition:
#     arrival and departure days both count, same-day intake and outcome
#     is LOS = 1): P(LOS = m) = q (1-q)^(m-1), P(LOS > m) = (1-q)^m,
#     exact at whole days.
#   - Outcome code: L/T/N with probabilities 0.7/0.2/0.1, independent of
#     everything else (the cause dimension is not this fixture's story;
#     see sim_cause_rate_shift for that).
#
# Animals still in care on 2024-11-01 (the export date and study end)
# have a blank outcome and are right-censored.
#
# The generated data.csv is committed, so the suite is deterministic;
# re-running this script reproduces it byte-for-byte. The tolerances in
# expected.R are sized (~4 standard deviations of each estimator across
# a 20-seed scan at authoring time) so a fresh sample from a new seed
# should pass; the committed seed was picked from that scan as a TYPICAL
# draw, because the case doubles as a worked example.
#
# Reproducibility: written under R 4.x with the default RNG; R >= 3.6
# reproduces the sample exactly.
#
# Run from anywhere:
#   Rscript tests/cases/sim_size_mixture/generator.R
# It writes data.csv next to itself.

set.seed(8)

# Resolve this script's own directory, then load the shared finalize/write
# helper (finalize_and_write) from the parent cases/ directory.
sim_dir <- dirname(sub("^--file=", "",
             grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)))
source(file.path(sim_dir, "..", "sim_common.R"))

intake_start <- as.Date("2023-09-01")   # ~8 months before period 1: steady state
export_date  <- as.Date("2024-11-01")   # study end / export date

groups <- list(
  SMALL = list(rate = 7, q = 0.12),
  LARGE = list(rate = 3, q = 0.03)
)
outcome_codes  <- c("L", "T", "N")
outcome_shares <- c(0.7, 0.2, 0.1)

intake_days <- seq(intake_start, export_date - 1, by = "day")

per_group <- lapply(names(groups), function(g) {
  spec        <- groups[[g]]
  n_per_day   <- rpois(length(intake_days), spec$rate)
  intake_date <- rep(intake_days, n_per_day)
  n           <- length(intake_date)
  los         <- rgeom(n, spec$q) + 1L
  data.frame(
    intake_date  = intake_date,
    outcome_date = intake_date + los - 1,
    outcome_type = sample(outcome_codes, n, replace = TRUE, prob = outcome_shares),
    animal_group = g,
    stringsAsFactors = FALSE
  )
})
data <- do.call(rbind, per_group)
data <- data[order(data$intake_date), ]   # file order = intake order (stable)

finalize_and_write(data, export_date, "SIZ", sim_dir)
