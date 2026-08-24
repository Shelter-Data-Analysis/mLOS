# Data generator for the sim_cause_rate_shift fixture
# =======================================================================
# Draws a randomized sample with a CAUSE-SPECIFIC rate shift: at the
# period 1 -> 2 boundary (2024-07-01), the within-day rates of the three
# outcome causes change by DIFFERENT factors, for every animal in care:
#
#   L (live release):  rate TRIPLES        (x 3)
#   T (transfer):      rate drops 3-fold   (x 1/3)
#   N (non-live):      rate UNCHANGED      (x 1)
#
# "Rate" is meant in the outcome-window sense of Mavrovouniotis, Animals
# 2026, 16(8):1158, Section 2.5: within each day's outcome window the
# causes compete as constant rates lambda_L, lambda_T, lambda_N, while
# the stay is counted in whole days. Writing Lambda for their sum, the
# daily probability of NO outcome is Q = exp(-Lambda T), and an outcome
# day's cause is j with probability lambda_j / Lambda, independent of
# the day (the competing-exponentials race inside the window).
#
# The baseline cause shares are 0.6 / 0.3 / 0.1 for L / T / N, chosen so
# the all-cause rate multiplier at the boundary is
#   0.6 * 3  +  0.3 * (1/3)  +  0.1 * 1  =  2   EXACTLY.
# The all-cause process is therefore numerically identical to the
# sim_geometric_period_effect fixture: Q goes 0.94 -> 0.94^2 = 0.8836
# (daily outcome probabilities q1 = 0.06, q2 = 0.1164), the grouped form
# of proportional hazards with true Cox hazard ratio exactly 2. What
# changes is the cause mix: the post-shift shares are
#   (0.6*3, 0.3/3, 0.1*1) / 2  =  0.9 / 0.05 / 0.05.
# KM, Cox, and the census cannot distinguish this fixture's world from
# the uniform doubling of sim_geometric_period_effect; only the AJ
# cause-level analysis can (see README.md).
#
# Generating model
#   - Daily intakes: independent Poisson(10) counts for every calendar
#     day from 2023-12-01 on. The study's first period starts 2024-04-01,
#     so the four months before it act as a notional "period 0" (~7 time
#     constants of 1/q1 ~ 17 days): the population builds from empty to
#     steady state, and the animals still in care on 2024-04-01 enter
#     left-truncated. The rate is 10/day, double the geometric case's,
#     because the delicate checks here are the 0.05 post-shift cause
#     shares: at ~1000 events per period their standard error is ~0.007,
#     so a 4-SE tolerance cleanly separates 0.05 from the 0.1 that a
#     naive "N unchanged" reading would predict.
#   - Departure: on each calendar day of its stay (including the arrival
#     day), an animal leaves with probability q1 = 0.06 before 2024-07-01
#     and q2 = 1 - 0.94^2 = 0.1164 from that day on. Within a constant-q
#     stretch the LOS (floor definition: arrival and departure days both
#     count, same-day intake and outcome is LOS = 1) is geometric:
#       P(LOS = m) = q (1-q)^(m-1),   P(LOS > m) = (1-q)^m,
#     exact at whole days, with none of the day-rounding bias documented
#     in sim_weibull_truncation. The day-by-day process is simulated by
#     the same two-geometric-draw construction as in
#     sim_geometric_period_effect (g1 at the old rate; if the animal
#     survives its s old-rate days, memorylessness lets the remainder be
#     a fresh g2 at the new rate).
#   - Outcome code: drawn from the shares of the rate regime IN FORCE ON
#     THE OUTCOME DAY: 0.6/0.3/0.1 for outcomes through 2024-06-30,
#     0.9/0.05/0.05 for outcomes from 2024-07-01. This is exact, not an
#     approximation: in the within-day race the cause is independent of
#     the stay length given the regime, and an animal in care at the
#     boundary draws both its remaining stay and its eventual cause
#     entirely under the new rates (memorylessness).
#
# Animals still in care on 2024-10-01 (the export date and study end)
# have a blank outcome and are right-censored.
#
# The generated data.csv is committed, so the suite is deterministic;
# re-running this script reproduces it byte-for-byte. The tolerances in
# expected.R are sized (~4 standard deviations of each estimator across
# a 25-seed scan at authoring time) so a fresh sample from a new seed
# should pass; the committed seed was picked from that scan as a TYPICAL
# draw (all statistics within ~1.2 SD of the truth), because the case
# doubles as a worked example.
#
# Reproducibility: written under R 4.x with the default RNG; R >= 3.6
# reproduces the sample exactly.
#
# Run from anywhere:
#   Rscript tests/cases/sim_cause_rate_shift/generator.R
# It writes data.csv next to itself.

set.seed(3)

# Resolve this script's own directory, then load the shared finalize/write
# helper (finalize_and_write) from the parent cases/ directory.
sim_dir <- dirname(sub("^--file=", "",
             grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)))
source(file.path(sim_dir, "..", "sim_common.R"))

intake_start <- as.Date("2023-12-01")   # notional period 0 begins
shift_date   <- as.Date("2024-07-01")   # period 1 -> 2 boundary: cause rates diverge
export_date  <- as.Date("2024-10-01")   # study end / export date

q_before <- 0.06
q_after  <- 1 - (1 - q_before)^2   # all-cause rate doubles: 0.1164
intake_rate <- 10
outcome_codes <- c("L", "T", "N")
shares_before <- c(0.6, 0.3, 0.1)      # baseline within-day rate shares
shares_after  <- c(0.9, 0.05, 0.05)    # after x3, x1/3, x1: (1.8, 0.1, 0.1)/2

intake_days <- seq(intake_start, export_date - 1, by = "day")
n_per_day   <- rpois(length(intake_days), intake_rate)
intake_date <- rep(intake_days, n_per_day)
n           <- length(intake_date)

g1 <- rgeom(n, q_before) + 1L
g2 <- rgeom(n, q_after)  + 1L
s  <- pmax(as.numeric(shift_date - intake_date), 0)  # old-rate departure chances
los <- ifelse(s == 0, g2,                 # admitted at the new rates
       ifelse(g1 <= s, g1, s + g2))       # left before / survived the shift
outcome_date <- intake_date + los - 1

# Cause from the regime in force on the outcome day (exact; see header).
post <- outcome_date >= shift_date
outcome_type <- character(n)
outcome_type[!post] <- sample(outcome_codes, sum(!post), replace = TRUE, prob = shares_before)
outcome_type[post]  <- sample(outcome_codes, sum(post),  replace = TRUE, prob = shares_after)

data <- data.frame(
  intake_date  = intake_date,
  outcome_date = outcome_date,
  outcome_type = outcome_type,
  stringsAsFactors = FALSE
)

finalize_and_write(data, export_date, "CRS", sim_dir)
