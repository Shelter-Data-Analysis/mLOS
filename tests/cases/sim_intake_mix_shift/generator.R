# Data generator for the sim_intake_mix_shift fixture
# =======================================================================
# Draws a randomized sample in which, at the period 1 -> 2 boundary,
# TWO things change at once and pull the reported numbers in OPPOSITE
# directions:
#
#   1. Every dog in care gets FASTER: the within-day outcome rate
#      improves x1.5, for both sizes and for every animal already in
#      care (Q -> Q^1.5, the grouped form of proportional hazards, so
#      the true Cox period hazard ratio is exactly 1.5).
#   2. The INTAKE MIX flips: SMALL/LARGE goes from 70/30 to 30/70.
#      Total intake stays 10 dogs per day throughout, so nothing about
#      the shelter's volume changes -- only who walks through the door.
#
# Because LARGE dogs stay far longer, the mix flip drags every POOLED
# statistic the wrong way: the crude per-period KM median RISES from 8
# to 10 days and the census RISES from ~156 to ~173, while every
# individual dog's prospects IMPROVED by 50%. That is Simpson's
# paradox in a shelter: the crude comparison says "we got slower and
# fuller", the size-adjusted Cox model says "every dog got 50%
# faster", and both are correct statements about the same data.
#
# "Rate" is meant in the outcome-window sense of Mavrovouniotis,
# Animals 2026, 16(8):1158, Section 2.5: outcomes occur at a constant
# rate lambda within a window of duration T each day, while the stay is
# counted in whole days, so the daily no-outcome probability is
# Q = exp(-lambda T) and multiplying lambda by 1.5 raises Q to the 1.5
# power. Since BOTH sizes' rates scale by the same 1.5, the hazard
# ratio BETWEEN the sizes is unchanged by the boundary -- there is no
# period-by-size interaction, so the Cox model with period + size is
# correctly specified and all three of its true coefficients are known
# in closed form.
#
# Generating model
#   - Daily intakes per size: independent Poisson counts for every
#     calendar day from 2023-09-01. Before 2024-08-01: 7/day SMALL,
#     3/day LARGE. From 2024-08-01: 3/day SMALL, 7/day LARGE.
#   - Daily outcome probabilities (geometric stays, floor definition:
#     arrival and departure days both count, same-day intake and
#     outcome is LOS = 1):
#       SMALL: q = 0.12 before, 1 - 0.88^1.5 = 0.17449 from the shift
#              (mean stay 8.33 -> 7.03 days)
#       LARGE: q = 0.03 before, 1 - 0.97^1.5 = 0.04466 from the shift
#              (mean stay 33.3 -> 22.4 days)
#   - The day-by-day departure process uses the same two-geometric-draw
#     construction as sim_geometric_period_effect, per size:
#       g1 ~ Geometric(q_before) + 1 is the LOS if the old rate lasted
#       forever; s = days from the intake day through 2024-07-31; if
#       g1 <= s the dog left before the shift (LOS = g1); otherwise it
#       was still in care when the rate changed -- P(g1 > s) =
#       (1-q_before)^s, the correct survival -- and by memorylessness
#       its remaining stay is a fresh g2 ~ Geometric(q_after) + 1,
#       giving LOS = s + g2. Dogs admitted on or after the shift use
#       g2 alone.
#   - Outcome code: L/T/N with probabilities 0.7/0.2/0.1, independent
#     of everything else (the cause dimension is not this fixture's
#     story; see sim_cause_rate_shift for that).
#
# The first period starts 2024-05-01, about 7 time constants of the
# SLOW group (1/q = 33 days) after intakes begin, so the population
# builds from empty to steady state during a notional "period 0" and
# the dogs still in care on 2024-05-01 enter left-truncated. Period 2
# is the TRANSITION (the standing population works off its old
# composition), and period 3 is the new steady state, ~98% relaxed by
# its start. Dogs still in care on 2025-02-01 (the export date) have a
# blank outcome and are right-censored.
#
# The generated data.csv is committed, so the suite is deterministic;
# re-running this script reproduces it byte-for-byte. The tolerances in
# expected.R are sized (~4 standard deviations of each estimator across
# a 30-seed scan at authoring time) so a fresh sample from a new seed
# should pass. Because the case doubles as a worked example, the
# committed seed was picked from that scan as the most TYPICAL draw
# (max |z| = 0.57 over the checked statistics) among those that also
# put both pooled medians exactly on their truths (8 and 10) and show
# the census trajectory the truth implies, rising across all three
# periods. That last requirement matters only for the worked example:
# period 2's census is transitional and deliberately unchecked (see
# expected.R), so in an unlucky draw it can land below period 1's
# purely by sampling noise, which would make the example contradict
# the lesson it exists to teach.
#
# Reproducibility: written under R 4.x with the default RNG; R >= 3.6
# reproduces the sample exactly.
#
# Run from anywhere:
#   Rscript tests/cases/sim_intake_mix_shift/generator.R
# It writes data.csv next to itself.

set.seed(8)

# Resolve this script's own directory, then load the shared finalize/write
# helper (finalize_and_write) from the parent cases/ directory.
sim_dir <- dirname(sub("^--file=", "",
             grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)))
source(file.path(sim_dir, "..", "sim_common.R"))

intake_start <- as.Date("2023-09-01")   # notional period 0 begins
shift_date   <- as.Date("2024-08-01")   # period 1 -> 2 boundary
export_date  <- as.Date("2025-02-01")   # study end / export date

improvement <- 1.5   # every dog's within-day rate multiplies by this

groups <- list(
  SMALL = list(rate_before = 7, rate_after = 3, q_before = 0.12),
  LARGE = list(rate_before = 3, rate_after = 7, q_before = 0.03)
)
outcome_codes  <- c("L", "T", "N")
outcome_shares <- c(0.7, 0.2, 0.1)

intake_days <- seq(intake_start, export_date - 1, by = "day")

per_group <- lapply(names(groups), function(g) {
  spec    <- groups[[g]]
  q_after <- 1 - (1 - spec$q_before)^improvement   # rate x1.5 => Q^1.5

  lambda      <- ifelse(intake_days < shift_date, spec$rate_before, spec$rate_after)
  n_per_day   <- rpois(length(intake_days), lambda)
  intake_date <- rep(intake_days, n_per_day)
  n           <- length(intake_date)

  g1 <- rgeom(n, spec$q_before) + 1L
  g2 <- rgeom(n, q_after)       + 1L
  s  <- pmax(as.numeric(shift_date - intake_date), 0)  # old-rate departure chances
  los <- ifelse(s == 0, g2,                 # admitted at the new rate
         ifelse(g1 <= s, g1, s + g2))       # left before / survived the shift

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

finalize_and_write(data, export_date, "MIX", sim_dir)
