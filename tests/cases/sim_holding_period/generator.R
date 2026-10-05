# Data generator for the sim_holding_period fixture
# =======================================================================
# Draws a randomized sample whose length of stay has a HOLDING PERIOD:
# no animal leaves during its first 5 counted days, and from its 6th day
# on it leaves with probability q = 0.1 on each day, independently of
# how long it has stayed. The survival curve is therefore flat, then
# geometric:
#   S(x) = P(LOS > x) = 1            for x = 0..5,
#   S(x) = 0.9^(x - 5)               for x >= 5.
# That shape gives the in-care tenure profile and the remaining-LOS
# curve closed forms with two regimes each (linear through the hold,
# geometric or constant after it), which is what the fixture exists to
# check; see settings.yaml for the derivations.
#
# Generating model
#   - Daily intakes: independent Poisson(10) counts for every calendar
#     day from 2023-10-01. The study's first period starts 2024-01-01,
#     so the three months before it bring the population from empty to
#     steady state (the mean stay is 15 days) and supply the
#     left-truncated residents observed from 2024-01-01.
#   - Length of stay (both endpoint days counted, so a same-day stay is
#     LOS = 1): LOS = 6 + G, with G ~ Geometric(0.1) on 0, 1, 2, ...
#     (R's rgeom), so P(LOS > x) = 0.9^(x - 5) for x >= 5.
#   - Outcome code: L/T/N with probabilities 0.6/0.3/0.1, independent of
#     everything else.
#
# Animals still in care on 2025-01-01 (the export date and study end)
# have a blank outcome and are right-censored.
#
# The generated data.csv is committed, so the suite is deterministic;
# re-running this script reproduces it byte-for-byte. The tolerances in
# expected.R are sized (~4 standard deviations, from a seed scan at
# authoring time) so a fresh sample from a new seed should pass; the committed
# seed was picked from a 120-seed scan as the most TYPICAL draw (every
# continuous estimate within 0.83 standard deviations of its truth), because
# the case doubles as a worked example.
#
# Reproducibility: written under R 4.4 with the default RNG; R >= 3.6
# reproduces the sample exactly.
#
# Run from anywhere:
#   Rscript tests/cases/sim_holding_period/generator.R
# It writes data.csv next to itself.

set.seed(76)

# Resolve this script's own directory, then load the shared finalize/write
# helper (finalize_and_write) from the parent cases/ directory.
sim_dir <- dirname(sub("^--file=", "",
             grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)))
source(file.path(sim_dir, "..", "sim_common.R"))

intake_start <- as.Date("2023-10-01")   # population builds before period 1
export_date  <- as.Date("2025-01-01")   # study end / export date

hold_days     <- 5      # no outcome during the first 5 counted days
q             <- 0.1    # daily outcome probability from day 6 on
intake_rate   <- 10
outcome_codes <- c("L", "T", "N")
outcome_probs <- c(0.6, 0.3, 0.1)

intake_days <- seq(intake_start, export_date - 1, by = "day")
n_per_day   <- rpois(length(intake_days), intake_rate)
intake_date <- rep(intake_days, n_per_day)
n           <- length(intake_date)

los <- hold_days + 1L + rgeom(n, q)

data <- data.frame(
  intake_date  = intake_date,
  outcome_date = intake_date + los - 1,
  outcome_type = sample(outcome_codes, n, replace = TRUE, prob = outcome_probs),
  stringsAsFactors = FALSE
)

finalize_and_write(data, export_date, "HLD", sim_dir)
