# Expected results for identical_periods.
# Two periods with identical (time-shifted) data: the unified KM curve
# and restricted mean must equal each period's own. All three fits share
# the hand-derived curve S = 2/3, 1/3, 0 at days 2, 4, 9 (see
# settings.yaml), so the unified values below and the per-period values in
# expected_stratified_km are the SAME numbers -- that equality is the
# point of the fixture.

expected_km <- list(
  n_total         = 6,   # 3 animals per period, none split across a boundary
  n_events        = 6,
  n_censored      = 0,
  n_capped        = 0,
  median_los      = 4,   # S(2) = 2/3 > 0.5, S(4) = 1/3 < 0.5, no tie
  percentile_90   = 9,   # S(4) = 1/3 > 0.1, S(9) = 0 <= 0.1, no tie
  restricted_mean = 5,   # 2 + 2*(2/3) + 5*(1/3) = mean(2, 4, 9)
  max_time        = 9
)

# Each period alone must reproduce the unified median and restricted
# mean (same LOS multiset {2, 4, 9}, no censoring).
expected_stratified_km <- list(
  period.Period_1.n      = 3,
  period.Period_1.events = 3,
  period.Period_1.median = 4,
  period.Period_1.rmean  = 5,
  period.Period_2.n      = 3,
  period.Period_2.events = 3,
  period.Period_2.median = 4,
  period.Period_2.rmean  = 5,
  n_strata_gaps          = 0
)

# The two periods are exchangeable at every event time, so the period
# effect's partial-likelihood score at beta = 0 vanishes and the fitted
# HR is exactly 1 (see settings.yaml).
expected_cox <- list(
  has_analysis      = 1,
  n                 = 6,
  n_events          = 6,
  HR_periodPeriod_2 = 1
)

# Extensive per-animal metrics are identical across the two periods; only
# the per-day rates differ, through the month lengths (Jan 31, Feb 28).
expected_period_stats <- list(
  Period_1.duration_days                   = 31,
  Period_1.total_observations            = 3,
  Period_1.events                        = 3,
  Period_1.censored                      = 0,
  Period_1.left_truncated                = 0,
  Period_1.right_censored                = 0,
  Period_1.capped_at_restricted_stay_cap               = 0,
  Period_1.mean_days_at_risk             = 5,       # (2 + 4 + 9) / 3
  Period_1.total_animal_days             = 15,
  Period_1.mean_census_inventory                   = 15 / 31,
  Period_1.total_in_care_days_sum        = 43,      # 1 + 6 + 36
  Period_1.daily_mean_total_in_care_days = 43 / 31,
  Period_1.total_intakes                 = 3,
  Period_1.total_outcomes                = 3,
  Period_1.mean_daily_intakes            = 3 / 31,
  Period_1.mean_daily_outcomes           = 3 / 31,

  Period_2.duration_days                   = 28,
  Period_2.total_observations            = 3,
  Period_2.events                        = 3,
  Period_2.censored                      = 0,
  Period_2.left_truncated                = 0,
  Period_2.right_censored                = 0,
  Period_2.capped_at_restricted_stay_cap               = 0,
  Period_2.mean_days_at_risk             = 5,
  Period_2.total_animal_days             = 15,
  Period_2.mean_census_inventory                   = 15 / 28,
  Period_2.total_in_care_days_sum        = 43,
  Period_2.daily_mean_total_in_care_days = 43 / 28,
  Period_2.total_intakes                 = 3,
  Period_2.total_outcomes                = 3,
  Period_2.mean_daily_intakes            = 3 / 28,
  Period_2.mean_daily_outcomes           = 3 / 28
)
