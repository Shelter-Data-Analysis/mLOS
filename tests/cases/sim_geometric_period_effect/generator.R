# Data generator for the sim_geometric_period_effect fixture
# =======================================================================
# Draws a randomized sample with a TRUE PERIOD EFFECT: the rate at which
# animals in care have outcomes DOUBLES at the period 1 -> 2 boundary
# (2024-07-01), for every animal in care, including residents admitted
# earlier. Geometric (memoryless) stays make that shift clean: the
# chance of leaving today never depends on how long the animal has
# already stayed, so "the rate changes at the boundary" is well defined
# without re-drawing anyone's remaining stay.
#
# "The rate doubles" is meant in the outcome-window sense of
# Mavrovouniotis, Animals 2026, 16(8):1158, Section 2.5: outcomes occur
# at a constant rate lambda within a window of duration T each day,
# while the stay itself is counted in whole days. The daily probability
# of NO outcome is then Q = exp(-lambda T), and doubling lambda squares
# it: Q2 = Q1^2. This is exactly the grouped (whole-day) form of
# proportional hazards, so the Cox period hazard ratio estimates the
# within-day rate ratio: its true value here is 2.
#
# Generating model
#   - Daily intakes: independent Poisson(5) counts for every calendar day
#     from 2023-12-01 on. The study's first period starts 2024-04-01, so
#     the four months before it act as a notional "period 0": the shelter
#     population builds from empty to its steady state (time constant
#     1/q1 ~ 17 days, so ~7 time constants) before observation begins,
#     and the animals still in care on 2024-04-01 enter left-truncated.
#   - Departure: on each calendar day of its stay (including the arrival
#     day), an animal leaves with probability q = 0.06 before 2024-07-01
#     and q = 1 - 0.94^2 = 0.1164 from that day on (the within-day
#     outcome rate doubles, so the daily no-outcome probability squares:
#     0.8836 = 0.94^2). Within a constant-q stretch the LOS
#     (floor definition: arrival and departure days both count, same-day
#     intake and outcome is LOS = 1) is geometric:
#       P(LOS = m) = q (1-q)^(m-1),   P(LOS > m) = (1-q)^m,
#     exact at whole days -- being a discrete model, it has NONE of the
#     day-rounding bias documented in sim_weibull_truncation.
#   - Outcome code: L/T/N with probabilities 0.7/0.2/0.1, independent of
#     everything else.
#
# The day-by-day departure process is simulated by two geometric draws
# per animal (vectorized, but exactly equivalent to walking the days):
#   g1 ~ Geometric(q1) + 1  is the LOS if the old rate lasted forever;
#   s  = days from the intake day through 2024-06-30 (chances to leave
#        at the old rate);
#   if g1 <= s the animal left before the shift (LOS = g1); otherwise it
#   was still in care when the rate changed -- P(g1 > s) = (1-q1)^s, the
#   correct survival -- and by memorylessness its remaining stay is a
#   fresh g2 ~ Geometric(q2) + 1, giving LOS = s + g2. Animals admitted
#   on or after the shift use g2 alone.
#
# Animals still in care on 2025-01-01 (the export date and study end)
# have a blank outcome and are right-censored.
#
# The generated data.csv is committed, so the suite is deterministic;
# re-running this script reproduces it byte-for-byte. The tolerances in
# expected.R are sized (~4 standard errors around the closed-form truth)
# so a fresh sample from a new seed should pass; the committed seed was
# picked from a short scan as a TYPICAL draw, because the case doubles
# as a worked example.
#
# Reproducibility: written under R 4.x with the default RNG; R >= 3.6
# reproduces the sample exactly.
#
# Run from anywhere:
#   Rscript tests/cases/sim_geometric_period_effect/generator.R
# It writes data.csv next to itself.

set.seed(10)

# Resolve this script's own directory, then load the shared finalize/write
# helper (finalize_and_write) from the parent cases/ directory.
sim_dir <- dirname(sub("^--file=", "",
             grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)))
source(file.path(sim_dir, "..", "sim_common.R"))

intake_start <- as.Date("2023-12-01")   # notional period 0 begins
shift_date   <- as.Date("2024-07-01")   # period 1 -> 2 boundary: q doubles
export_date  <- as.Date("2025-01-01")   # study end / export date

q_before <- 0.06
q_after  <- 1 - (1 - q_before)^2   # rate doubles within the outcome window: 0.1164
intake_rate <- 5
outcome_codes <- c("L", "T", "N")
outcome_probs <- c(0.7, 0.2, 0.1)

intake_days <- seq(intake_start, export_date - 1, by = "day")
n_per_day   <- rpois(length(intake_days), intake_rate)
intake_date <- rep(intake_days, n_per_day)
n           <- length(intake_date)

g1 <- rgeom(n, q_before) + 1L
g2 <- rgeom(n, q_after)  + 1L
s  <- pmax(as.numeric(shift_date - intake_date), 0)  # old-rate departure chances
los <- ifelse(s == 0, g2,                 # admitted at the new rate
       ifelse(g1 <= s, g1, s + g2))       # left before / survived the shift

data <- data.frame(
  intake_date  = intake_date,
  outcome_date = intake_date + los - 1,
  outcome_type = sample(outcome_codes, n, replace = TRUE, prob = outcome_probs),
  stringsAsFactors = FALSE
)

finalize_and_write(data, export_date, "GEO", sim_dir)
