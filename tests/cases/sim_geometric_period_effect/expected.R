# Expected values for sim_geometric_period_effect (statistical case; see
# settings.yaml for the generating truth and generator.R for the model).
#
# As in sim_weibull_truncation, expected values are the KNOWN PARAMETERS
# of the generating model; statistical fields carry c(value, tol)
# tolerances of ~4 standard errors (from the fitted models and a seed
# scan at authoring time), and counts are properties of the committed
# sample, pinned exactly through the case-wide tolerance.
#
# The story this case pins: at the period 1 -> 2 boundary, the rate at
# which animals have outcomes within each day's outcome window doubles,
# for everyone in care (daily no-outcome probability squares: 0.94 ->
# 0.8836). The hazard-level analyses (Cox, per-period KM, per-period AJ)
# see the new rate immediately and identically in periods 2 and 3, while
# the census obeys Little's law only in periods 1 and 3 -- period 2
# inherits period 1's population and works it off, so its census is
# deliberately NOT checked and its outflow temporarily exceeds its
# inflow.

# Case-wide tolerance: sized for the per-period AJ probability checks
# (~4 standard errors of a CIF at each period's ~450-540 events).
tolerance <- 0.08

expected_km <- list(
  # The unified KM pools rows from periods with different hazards, so its
  # median and restricted mean are composition-weighted mixtures with no
  # clean closed form; only the committed-sample counts are pinned here.
  n_total  = 1603,
  n_events = 1452,
  n_capped = 0,     # the 120-day cap never binds (see settings.yaml)
  gap_detected = 0
)

expected_cox <- list(
  has_analysis = 1,
  n            = 1603,
  n_events     = 1452,
  # True hazard ratio EXACTLY 2: the within-day outcome rate doubles,
  # and 1 - q2 = (1 - q1)^2 is the grouped form of proportional hazards
  # with ratio 2, which the Efron tie handling targets (math document
  # Section 6.2; pseudo-truth measured 1.994/2.013 at authoring time).
  # Periods 2 and 3 share the same true hazard, so these two fields
  # check the SAME truth twice. tol = ~4 robust SE on the log scale.
  # The tie rule itself is pinned in massive_daily_ties, on data built
  # so Efron and Breslow are a third of a hazard ratio apart; here they
  # differ by 0.06 against a sampling error of 0.13, so no tolerance
  # sized to this sample could tell them apart.
  HR_periodPeriod_2 = c(2.0, 0.7),
  HR_periodPeriod_3 = c(2.0, 0.7)
)

expected_stratified_km <- list(
  # Within each period the hazard is constant, so each period's KM curve
  # is exactly geometric: S_p(m) = Q_p^m, median = smallest m with
  # S_p(m) <= 0.5, restricted mean (cap 120, never binding) = 1/q_p.
  period.Period_1.n      = 534,
  period.Period_1.events = 446,
  period.Period_1.median = c(12, 1.5),      # 0.94^11 = 0.506 is borderline
  period.Period_1.rmean  = c(16.6567, 3),
  period.Period_2.n      = 583,
  period.Period_2.events = 543,
  period.Period_2.median = c(6, 1),
  period.Period_2.rmean  = c(8.5911, 1.5),
  period.Period_3.n      = 486,
  period.Period_3.events = 463,
  period.Period_3.median = c(6, 1),
  period.Period_3.rmean  = c(8.5911, 1.5),
  # Observation gaps in the sparse extreme-tenure tail of the fast-hazard
  # periods: past tenure ~67 (period 2) and ~43 (period 3), the risk set
  # thins to a lone inherited long-term resident, and mLOS flags the
  # empty stretch before that animal's exit. Survival there is already
  # below 1e-3, so every statistic checked above is unaffected -- these
  # pins are committed-sample facts (like the counts, they move with a
  # fresh seed) that exercise the gap reporting on organic data.
  n_strata_gaps          = 2,
  gap.Period.Period_2.start = 67,
  gap.Period.Period_2.end   = 87,
  gap.Period.Period_3.start = 43,
  gap.Period.Period_3.end   = 46
)

expected_period_stats <- list(
  # Little's law: mean census = daily intakes x mean LOS = daily intakes
  # / daily outcome probability, at steady state -- so periods 1 and 3
  # only. Period 2's census is deliberately NOT checked: it starts at
  # period 1's steady state (~83) and relaxes toward period 3's (~43),
  # averaging ~46.5 on the way down (closed-form geometric relaxation;
  # the committed sample shows ~51). That lag, while the Cox HR above
  # shifts instantly, is the educational point of this case.
  Period_1.mean_census_inventory = c(83.333, 17),
  Period_3.mean_census_inventory = c(42.955, 9),
  # Flow: intakes average 5/day everywhere; outcomes match intakes at
  # steady state (periods 1 and 3), but during period 2 the inherited
  # excess population (83.333 - 42.955 = 40.4 animals) leaves on top of
  # the steady flow: 5 + 40.4/92 = 5.439 outcomes/day > intakes/day.
  Period_1.mean_daily_intakes  = c(5, 1),
  Period_2.mean_daily_intakes  = c(5, 1),
  Period_3.mean_daily_intakes  = c(5, 1),
  Period_1.mean_daily_outcomes = c(5, 1),
  Period_2.mean_daily_outcomes = c(5.4389, 1),
  Period_3.mean_daily_outcomes = c(5, 1),
  # Left truncation happens in EVERY period (committed-sample counts):
  # period 0 residents enter period 1 truncated, and each later period
  # inherits the previous one's residents the same way.
  Period_1.left_truncated = 73,
  Period_2.left_truncated = 88,
  Period_3.left_truncated = 40
)

# Census-by-tenure companion (math methods 5.7): the KM route to the same
# Little's-law truths pinned via mean_census above -- predicted_census =
# mean daily intakes x KM restricted mean, per period. Steady-state
# periods only: for period 2 the KM route predicts the steady-state
# census the period is relaxing TOWARD (~43), not the ~51 its inherited
# population actually averages -- exactly the steady-state caveat (math
# methods Section 9) -- so it is deliberately not checked.
expected_census <- list(
  period.Period_1.lambda = c(5, 1),
  period.Period_3.lambda = c(5, 1),
  # N(0) = lambda * S(0) = lambda: the day-0 census bin is the day's intakes.
  period.Period_1.day0   = c(5, 1),
  period.Period_1.predicted_census = c(83.333, 17),
  period.Period_3.predicted_census = c(42.955, 9)
)

# Per-period AJ: within a period, cif_Any(m) = 1 - Q_p^m, each cause
# takes its fixed share (0.7/0.2/0.1), and CondRem_cause = p_cause to
# three decimals at cap 120 (see settings.yaml for the exact estimand).
# Checked near each period's median day. Because Q2 = Q1^2 compresses
# the curve two-fold, the day-6 values of periods 2/3 EQUAL the day-12
# values of period 1. All use the case tolerance.
expected_aj_period <- list(
  has_analysis = 1,
  n_periods    = 3,
  Period_1.cif_Any_day12 = 0.52408,
  Period_1.cif_L_day12   = 0.36686,
  Period_1.condrem_L_day12 = 0.7,
  Period_1.condrem_T_day12 = 0.2,
  Period_1.condrem_N_day12 = 0.1,
  Period_2.cif_Any_day6  = 0.52408,
  Period_2.cif_L_day6    = 0.36686,
  Period_2.condrem_L_day6 = 0.7,
  Period_3.cif_Any_day6  = 0.52408,
  Period_3.cif_L_day6    = 0.36686,
  Period_3.condrem_L_day6 = 0.7
)
