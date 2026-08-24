# Expected results for median_not_reached.
# Hand-derived (see settings.yaml comment): one event at day 5 among five
# animals, the other four capped and censored at day 30, so S holds at
# 0.8 and neither the median nor the 90th percentile is ever reached.

expected_km <- list(
  n_total         = 5,
  n_events        = 1,
  n_censored      = 4,
  n_capped        = 4,
  fraction_capped = 0.8,
  median_los      = NA,   # S(t) = 0.8 forever, never <= 0.5
  percentile_90   = NA,   # never <= 0.10 either
  restricted_mean = 25,   # 5*1.0 + 25*0.8
  max_time        = 30,
  # S never falls below 0.8, so the curve's terminal value at the cap is 0.8:
  # the fitted counterpart of fraction_capped, which is 4/5 here by a different
  # route (a count of rows that reached the cap, not a survival estimate).
  still_in_care_at_cap = 0.8
)

# Single period, no intake_type/animal_group columns -> no Cox predictor.
expected_cox <- list(
  has_analysis = 0
)

# Single cause: cif_L = 0.2 from day 5 through the cap.
expected_aj <- list(
  has_analysis     = 1,
  max_time         = 30,
  n_outcome_states = 1,

  cif_L_day0     = 0,
  cif_L_day4     = 0,
  cif_L_day5     = 0.2,
  cif_Any_day5   = 0.2,
  cif_L_day30    = 0.2,

  condrem_L_day0 = 0.2,
  condrem_L_day5 = 0
)
