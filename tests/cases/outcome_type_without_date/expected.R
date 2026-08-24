# Expected results for outcome_type_without_date.
# Hand-derived in settings.yaml. n_total is the assertion that carries the
# fixture: ten rows in, two dropped for carrying an outcome_type with no
# outcome_date, and the HOLD row kept because outcome_type_in_care claimed
# it first.

expected_km <- list(
  n_total         = 8,
  n_events        = 6,
  n_censored      = 2,
  n_capped        = 1,
  median_los      = 10,
  percentile_90   = NA,
  restricted_mean = 13.125,
  max_time        = 30
)

# Single period, no intake_type or animal_group column: no predictor to fit.
expected_cox <- list(
  has_analysis = 0
)

expected_aj <- list(
  has_analysis     = 1,
  n_outcome_states = 3,
  cif_L_day4       = 0,
  cif_L_day5       = 0.375,
  cif_L_day10      = 0.5,
  cif_N_day10      = 0.125,
  cif_T_day10      = 0.125,
  cif_Any_day10    = 0.75,
  cif_Any_day30    = 0.75
)
