# Expected results for massive_daily_ties.
# Hand-derived from the exact counts (see settings.yaml). Every risk set
# is halved (LARGE) or quartered (SMALL) each day, so every survival
# value below is a dyadic rational, exact rather than approximate.

expected_km <- list(
  # Pooled, all four cells: at risk 1024, 384, 160, 72, 34, 18, 10, 6,
  # with events 640, 224, 88, 38, 16, 8, 4, 2 on days 1 to 8. S runs
  # 0.375, 0.15625, 0.0703125, 0.033203125, 0.017578125, 0.009765625,
  # 0.005859375, 0.00390625, and four animals are censored at day 8.
  n_total    = 1024,
  n_events   = 1020,
  n_censored = 4,
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
  n            = 1024,
  n_events     = 1020,
  # WHAT THE TIE RULE ESTIMATES. SMALL's within-day outcome rate is
  # exactly twice LARGE's, so the true within-day rate ratio is 2, the
  # daily probability ratio is 0.75/0.50 = 1.5 and the daily odds ratio
  # is 3. At q = 0.5 these three are far apart, and the tie rule decides
  # which one the fit goes after: Efron reaches 1.835975 and Breslow
  # 1.470990, landing near the probability ratio instead.
  #
  # Efron is an approximation, so this is not 2 and no tolerance should
  # pretend otherwise: at q this large the large-sample Efron value for
  # these two rates is 1.891, and this finite construction sits a little
  # below it. The pin is therefore the fitted value. The data are built
  # rather than sampled and the fit converges to 1e-11 from starting
  # values anywhere in [-2, 2], so the tolerance below is five orders
  # looser than the arithmetic and still leaves Breslow 365,000 out.
  HR_animal_groupSMALL = c(1.835975452, 1e-6),
  # OWNER and STRAY are the same 512 animals twice, so this one is not a
  # fitted value at all: the score at zero is zero and the coefficient
  # is exactly 1 under any tie rule.
  HR_intake_typeSTRAY = 1
)

# strata(intake_type): each half goes back on the schedule a single
# group of 256 would have run, which is why this differs from the
# pooled 1.835975452 in the fourth decimal. Duplicating a dataset
# changes how many events are tied, and Efron's correction reads that
# count. Breslow's does not, and returns 1.470990 for the pooled fit and
# this one alike, so the pair also catches the two coxph calls
# disagreeing about the rule. The two pins stand 197 tolerances apart,
# which is what makes them a pair rather than one value written twice.
expected_cox_stratified_group <- list(
  has_analysis         = 1,
  n                    = 1024,
  n_events             = 1020,
  n_strata             = 2,
  n_strata_with_events = 2,
  lr_df                = 1,
  HR_animal_groupSMALL = c(1.835778524, 1e-6)
)

# strata(animal_group): the null factor under a free baseline per size,
# still exactly 1.
expected_cox_stratified_intake <- list(
  has_analysis         = 1,
  n                    = 1024,
  n_events             = 1020,
  n_strata             = 2,
  n_strata_with_events = 2,
  lr_df                = 1,
  HR_intake_typeSTRAY  = 1
)

# Per stratum, with the same exactness. LARGE halves from 512 and SMALL
# quarters from 512, each stopping two animals short of a fractional
# day. The two intake_type strata are identical, so both reproduce the
# pooled curve.
expected_stratified_km <- list(
  group.LARGE.n      = 512,
  group.LARGE.events = 510,
  # S(1) = 0.5 EXACTLY, so the median is the midpoint of the flat
  # stretch [1, 2) under the documented exact-tie convention.
  group.LARGE.median = 1.5,
  group.SMALL.n      = 512,
  group.SMALL.events = 510,
  group.SMALL.median = 1,   # S(1) = 0.25, under half on the first day

  intake.OWNER.n      = 512,
  intake.OWNER.events = 510,
  intake.OWNER.median = 1,  # the pooled curve, S(1) = 0.375
  intake.STRAY.n      = 512,
  intake.STRAY.events = 510,
  intake.STRAY.median = 1,

  # Every stratum is at risk from day 0 without a break.
  n_strata_gaps = 0
)
