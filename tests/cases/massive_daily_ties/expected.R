# Expected results for massive_daily_ties.
# Hand-derived from the exact counts (see settings.yaml). Every risk set
# is halved (LARGE) or quartered (SMALL) each day, so every survival
# value below is a dyadic rational, exact rather than approximate.

expected_km <- list(
  # Pooled, both groups: at risk 512, 192, 80, 36, 17, 9, 5, 3, with
  # events 320, 112, 44, 19, 8, 4, 2, 1 on days 1 to 8. S runs 0.375,
  # 0.15625, 0.0703125, 0.033203125, 0.017578125, 0.009765625,
  # 0.005859375, 0.00390625, and one animal of each group is censored
  # at day 8.
  n_total    = 512,
  n_events   = 510,
  n_censored = 2,
  n_capped   = 0,     # cap 30, last observation at day 8

  # Everyone arrives together and the risk set is never empty, so the
  # pooled timeline has no hole.
  gap_detected = 0,

  median_los    = 1,   # S(1) = 0.375, already under half, no exact tie
  percentile_90 = 3,   # S(2) = 0.15625 > 0.1 >= S(3) = 0.0703125
  max_time      = 8
)

expected_cox <- list(
  has_analysis = 1,
  n            = 512,
  n_events     = 510,
  # WHAT THE TIE RULE ESTIMATES. SMALL's within-day outcome rate is
  # exactly twice LARGE's, so the true within-day rate ratio is 2, the
  # daily probability ratio is 0.75/0.50 = 1.5 and the daily odds ratio
  # is 3. At q = 0.5 these three are far apart, and the tie rule decides
  # which one the fit goes after: Efron reaches 1.835779 and Breslow
  # 1.470990, landing near the probability ratio instead.
  #
  # Efron is an approximation, so 1.835779 is not 2 and no tolerance
  # should pretend otherwise: at q this large the large-sample Efron
  # value for these two rates is 1.891, and this finite construction
  # sits a little below it. The pin is therefore the fitted value. It
  # holds to the last digit on rerun, because the data are built rather
  # than sampled, and it sits 3600 tolerances from Breslow.
  HR_animal_groupSMALL = c(1.835779, 1e-4)
)

# Per group, with the same exactness. LARGE halves from 256 and SMALL
# quarters from 256, each stopping one animal short of a fractional day.
expected_stratified_km <- list(
  group.LARGE.n      = 256,
  group.LARGE.events = 255,
  # S(1) = 0.5 EXACTLY, so the median is the midpoint of the flat
  # stretch [1, 2) under the documented exact-tie convention.
  group.LARGE.median = 1.5,
  group.SMALL.n      = 256,
  group.SMALL.events = 255,
  group.SMALL.median = 1,   # S(1) = 0.25, under half on the first day

  # Both groups are at risk from day 0 without a break.
  n_strata_gaps = 0
)
