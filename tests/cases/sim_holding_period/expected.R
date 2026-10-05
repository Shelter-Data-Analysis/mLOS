# Expected values for sim_holding_period (statistical case; see
# settings.yaml for the generating truth and its derivations, and
# generator.R for the model).
#
# Expected values are the KNOWN TRUTHS of the generating model: a 5-day
# hold (no outcome during a stay's first 5 counted days), then a constant
# daily outcome probability q = 0.1, so S(x) = 1 for x <= 5 and
# S(x) = 0.9^(x - 5) after. Statistical fields carry c(value, tol)
# tolerances of about 4.5 standard deviations, measured by a 120-seed scan
# at authoring time (worst seed within 4.0 SD on every continuous field);
# counts are properties of the committed sample, pinned exactly.
#
# The truths are stated in their infinite-horizon form. At the 120-day cap
# the finite sums differ from them by less than 1e-4 (S(120) = 5.5e-6),
# far inside every tolerance.

expected_km <- list(
  n_total  = 3996,
  n_events = 3718,
  n_capped = 0,
  gap_detected = 0
)

# The two periods are identical by construction and the population is at
# steady state in both, so the whole sample and each period share every
# truth below. The groups differ only in sample size, hence in tolerance.
.holding_truths <- function(group, tol) {
  t <- list(
    # Restricted mean: (hold + 1) + Q/q = 6 + 9 = 15.
    km_restricted_mean       = c(15, tol$rmean),
    # Mean tenure of the in-care population, sum_d d S(d) / sum_d S(d):
    # sum_d d S(d) = H(H+1)/2 + H Q/q + Q/q^2 = 15 + 45 + 90 = 150, so 10;
    # residents' remaining days per head are one more (math methods 5.6).
    per_resident_past_days   = c(10, tol$tenure),
    per_resident_future_days = c(11, tol$tenure),
    # Quantiles on the whole-day grid sit near rounding edges for any
    # geometric tail (0.9^21 = 0.109 against 0.1 for the KM p90), so they
    # carry day tolerances.
    km_median_los = c(12, 1),
    km_p90_los    = c(27, 3),
    per_resident_past_days_restricted_median = c(7, 1),
    per_resident_past_days_restricted_p90    = c(23, 3),
    # Remaining LOS is constant at 1/q = 10 once the hold is over
    # (memoryless), and every tenure statistic lies past the hold.
    remaining_days_at_mean_tenure   = c(10, tol$rem_mean),
    remaining_days_at_median_tenure = c(10, tol$rem_median),
    remaining_days_at_p90_tenure    = c(10, tol$rem_p90),
    # KM: flat through the hold, then 0.9^(x - 5).
    km_day6  = c(0.9,     tol$km6),
    km_day10 = c(0.59049, tol$km10),
    km_day20 = c(0.205891, tol$km20),
    # In-care tenure G(x) = sum_{d > x} S(d) / 15: linear through the hold,
    # (14 - x)/15, then (2/3) 0.9^(x - 4). G(0) = 1 - 1/15.
    in_care_day0  = c(0.933333, tol$g0),
    in_care_day4  = c(0.666667, tol$g4),
    in_care_day5  = c(0.6,      tol$g5),
    in_care_day10 = c(0.354294, tol$g10),
    in_care_day20 = c(0.123535, tol$g20),
    # Remaining LOS: 15 - x through the hold (each day of it is a day that
    # must still be served), then 1/q = 10. Remaining(0) = RMST.
    remaining_day0  = c(15, tol$rmean),
    remaining_day4  = c(11, tol$rmean),
    remaining_day5  = c(10, tol$rmean),
    remaining_day10 = c(10, tol$rem10),
    remaining_day30 = c(10, tol$rem30)
  )
  setNames(t, paste0(group, ".", names(t)))
}

.holding_tol_all <- list(rmean = 0.7, tenure = 0.75, rem_mean = 0.9, rem_median = 0.8,
                         rem_p90 = 1.9, km6 = 0.026, km10 = 0.038, km20 = 0.03,
                         g0 = 0.0032, g4 = 0.016, g5 = 0.019, g10 = 0.026, g20 = 0.023,
                         rem10 = 0.9, rem30 = 2.3)
.holding_tol_period <- list(rmean = 1.1, tenure = 1.2, rem_mean = 1.35, rem_median = 1.2,
                            rem_p90 = 2.9, km6 = 0.036, km10 = 0.055, km20 = 0.045,
                            g0 = 0.005, g4 = 0.024, g5 = 0.029, g10 = 0.04, g20 = 0.035,
                            rem10 = 1.4, rem30 = 3.6)

expected_tenure <- c(.holding_truths("All", .holding_tol_all),
                     .holding_truths("Period_1", .holding_tol_period),
                     .holding_truths("Period_2", .holding_tol_period))

# The observed side of the same truths, counted from the stays rather than
# read off a KM curve: Little's law puts the inventory census at
# 10 intakes/day x 15 = 150, and the accumulated in-care days of the
# nights held (math methods 4) at 10 x sum_d d S(d) = 1500.
expected_period_stats <- list(
  Period_1.mean_daily_intakes            = c(10, 1.2),
  Period_2.mean_daily_intakes            = c(10, 1.2),
  Period_1.mean_census_inventory         = c(150, 21),
  Period_2.mean_census_inventory         = c(150, 21),
  Period_1.daily_mean_total_in_care_days = c(1500, 310),
  Period_2.daily_mean_total_in_care_days = c(1500, 310)
)

# Census by tenure (math methods 5.6): N(d) = 10 S(d), so N(0) = 10 (the
# day's intakes) and the column sums to the predicted census of 150.
expected_census <- list(
  period.Period_1.lambda           = c(10, 1.2),
  period.Period_2.lambda           = c(10, 1.2),
  period.Period_1.day0             = c(10, 1.2),
  period.Period_1.predicted_census = c(150, 21),
  period.Period_2.predicted_census = c(150, 21)
)
