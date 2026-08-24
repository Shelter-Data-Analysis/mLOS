# Expected km_unified_period() results for constant_los_single_period.
# Hand-derived (see settings.yaml comment): every animal has LOS = 10 days
# with a classified outcome, so the KM curve is a single step 1.0 -> 0.0
# at day 10.

expected_km <- list(
  n_total         = 5,
  n_events        = 5,
  n_censored      = 0,
  n_capped        = 0,
  median_los      = 10,
  percentile_90   = 10,
  restricted_mean = 10,
  max_time        = 10
)

# This fixture has a single period and no intake_type/animal_group columns,
# so there is no predictor for Cox regression to fit; cox_regression_analysis()
# should skip the fit entirely rather than crash on a degenerate null model.
expected_cox <- list(
  has_analysis = 0
)

# All outcomes are type L, so the AJ competing-risk CIF has a single cause and
# should degenerate to cif_L(t) = 1 - S(t): 0 for t < 10, jumping to 1 at t = 10
# (all 5 animals resolve to L on day 10, no censoring).
expected_aj <- list(
  has_analysis     = 1,
  max_time         = 10,
  n_outcome_states = 1,
  cif_L_day0       = 0,
  cif_L_day9       = 0,
  cif_L_day10      = 1,
  cif_Any_day10    = 1
)
