# Expected results for stratum_gap.
# Hand-derived (see settings.yaml comment): pooled coverage is continuous
# (no unified gap) but the SLOW animal group has nobody at risk in
# (15, 20] -- a gap only the per-stratum check can see.

expected_km <- list(
  n_total         = 4,
  n_events        = 4,
  n_censored      = 0,
  n_capped        = 0,

  # The pooled data has NO gap -- that is the point of this fixture.
  gap_detected    = 0,

  median_los      = 15,
  percentile_90   = 30,
  restricted_mean = 95 / 6,  # 15.8333..., cap 40
  max_time        = 30
)

# Stratified by animal_group. FAST's S(5) = 0.5 exactly, so its median is
# the midpoint of the flat stretch [5, 25): 15 (documented exact-tie
# convention). SLOW's curve zeroes at day 15 -- before its own gap -- so
# animal 4's 30-day stay contributes nothing, and the gap fields flag it.
expected_stratified_km <- list(
  group.FAST.n      = 2,
  group.FAST.events = 2,
  group.FAST.median = 15,
  group.SLOW.n      = 2,
  group.SLOW.events = 2,
  group.SLOW.median = 15,

  n_strata_gaps = 1
)
expected_stratified_km[["gap.Animal Group.SLOW.start"]] <- 15
expected_stratified_km[["gap.Animal Group.SLOW.end"]]   <- 20

# animal_group has 2 levels -> Cox runs; only the fit's shape is asserted.
expected_cox <- list(
  has_analysis = 1,
  n            = 4,
  n_events     = 4
)
