# Expected results for massive_daily_ties.
# Hand-derived from the exact counts (see settings.yaml). Every risk set
# is halved (LARGE) or quartered (SMALL) each day, so every survival
# value below is a dyadic rational, exact rather than approximate.

expected_km <- list(
  # Pooled, all four cells: at risk 1024, 384, 160, 72, with events 640,
  # 224, 88, 38 on days 1 to 4. S runs 0.375, 0.15625, 0.0703125,
  # 0.033203125, and the 34 animals still in care when the window shuts
  # are censored at day 4.
  n_total    = 1024,
  n_events   = 990,
  n_censored = 34,
  n_capped   = 0,     # cap 30, last observation at day 4

  # Everyone arrives together and the risk set is never empty, so the
  # pooled timeline has no hole.
  gap_detected = 0,

  median_los    = 1,   # S(1) = 0.375, already under half, no exact tie
  percentile_90 = 3,   # S(2) = 0.15625 > 0.1 >= S(3) = 0.0703125
  max_time      = 4
)

expected_cox <- list(
  has_analysis = 1,
  n            = 1024,
  n_events     = 990,
  # WHAT THE TIE RULE ESTIMATES. SMALL's within-day outcome rate is
  # exactly twice LARGE's, so the true within-day rate ratio is 2, the
  # daily probability ratio is 0.75/0.50 = 1.5 and the daily odds ratio
  # is 3. At q = 0.5 these three are far apart, and the tie rule decides
  # which one the fit goes after: Efron reaches 1.888622 and Breslow
  # 1.500000, the probability ratio to within 2e-14.
  #
  # Efron is an approximation, so this is not 2 and no tolerance should
  # pretend otherwise: at q this large the value Efron converges on for
  # these two rates is 1.891, and a window of four days sits a tenth of
  # a percent below it. The pin is therefore the fitted value.
  #
  # The tolerance is what the optimizer, not the data, makes it. The
  # data are built rather than sampled, but the fit still moves by
  # 5.7e-10 across starting values from -2 to 2, so a pin at 1e-9 would
  # be pinning the convergence path. At 1e-8 there are seventeen
  # tolerances of margin above that spread, and Breslow still sits 3.9e7
  # tolerances out.
  HR_animal_groupSMALL = c(1.888621828102, 1e-8),
  # OWNER and STRAY are the same 512 animals twice, so this one is not a
  # fitted value at all: the score at zero is zero and the coefficient
  # is exactly 1 under any tie rule.
  HR_intake_typeSTRAY = 1
)

# strata(intake_type): each half goes back on the schedule a single
# group of 256 would have run, which is why this differs from the
# pooled 1.888621828 in the third decimal. Duplicating a dataset
# changes how many events are tied, and Efron's correction reads that
# count. Breslow's does not, and returns 1.500000 for the pooled fit and
# this one alike, so the pair also catches the two coxph calls
# disagreeing about the rule. The two pins stand 224,000 tolerances
# apart, which is what makes them a pair rather than one value written
# twice.
expected_cox_stratified_group <- list(
  has_analysis         = 1,
  n                    = 1024,
  n_events             = 990,
  n_strata             = 2,
  n_strata_with_events = 2,
  lr_df                = 1,
  HR_animal_groupSMALL = c(1.886385845174, 1e-8)
)

# strata(animal_group): the null factor under a free baseline per size,
# still exactly 1.
expected_cox_stratified_intake <- list(
  has_analysis         = 1,
  n                    = 1024,
  n_events             = 990,
  n_strata             = 2,
  n_strata_with_events = 2,
  lr_df                = 1,
  HR_intake_typeSTRAY  = 1
)

# Per stratum, with the same exactness. LARGE halves from 512 and SMALL
# quarters from 512, and the window shuts on the day SMALL runs out of
# whole animals, leaving 32 LARGE and 2 SMALL censored there. The two
# intake_type strata are identical, so both reproduce the pooled curve.
expected_stratified_km <- list(
  group.LARGE.n      = 512,
  group.LARGE.events = 480,
  # S(1) = 0.5 EXACTLY, so the median is the midpoint of the flat
  # stretch [1, 2) under the documented exact-tie convention.
  group.LARGE.median = 1.5,
  group.SMALL.n      = 512,
  group.SMALL.events = 510,
  group.SMALL.median = 1,   # S(1) = 0.25, under half on the first day

  intake.OWNER.n      = 512,
  intake.OWNER.events = 495,
  intake.OWNER.median = 1,  # the pooled curve, S(1) = 0.375
  intake.STRAY.n      = 512,
  intake.STRAY.events = 495,
  intake.STRAY.median = 1,

  # Every stratum is at risk from day 0 without a break.
  n_strata_gaps = 0
)
