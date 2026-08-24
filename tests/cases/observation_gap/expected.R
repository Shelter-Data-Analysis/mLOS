# Expected results for observation_gap.
# Hand-derived (see settings.yaml comment): three animals resolve at days
# 5/10/15 from the period start; a fourth, left-truncated 20 days into
# its stay, resolves at day 30. Nobody is at risk in (15, 20].

expected_km <- list(
  n_total         = 4,
  n_events        = 4,
  n_censored      = 0,
  n_capped        = 0,

  # The gap itself -- the point of this fixture. The old n.risk-based
  # check could never fire; the interval-coverage sweep must.
  gap_detected    = 1,
  gap_start       = 15,
  gap_end         = 20,

  # Degenerate estimator behavior through the gap, documented on purpose:
  # S hits 0 at day 15 (risk set empties via an event), so animal 4's
  # 30-day stay contributes nothing to any statistic below.
  median_los      = 10,
  percentile_90   = 15,
  restricted_mean = 10,   # area up to the gap only: 5 + 5*(2/3) + 5*(1/3)
  max_time        = 30
)

# Single period, no intake_type/animal_group columns -> no Cox predictor.
expected_cox <- list(
  has_analysis = 0
)
