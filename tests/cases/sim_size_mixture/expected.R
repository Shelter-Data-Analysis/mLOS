# Expected values for sim_size_mixture (statistical case; see
# settings.yaml for the generating truth and generator.R for the model).
#
# As in the other sim_* fixtures, expected values are the KNOWN
# PARAMETERS of the generating model; statistical fields carry
# c(value, tol) tolerances of ~4 standard deviations of each estimator
# (from a 20-seed scan of the generator at authoring time), widened
# where the documented Weibull discretization bias applies. Counts are
# properties of the committed sample, pinned exactly through the
# case-wide tolerance.
#
# The story this case pins: a 70/30 mixture of SMALL (q = 0.12) and
# LARGE (q = 0.03) dogs, each memoryless, nothing changing over
# calendar time. The pooled statistics violate the memoryless ratio
# benchmarks (mean ~ 1.44 x median, p90 ~ 3.32 x median) because the
# pooled hazard declines with tenure -- pure composition, no dog's
# prospects ever change -- while the stratified KM shows each size
# flat-geometric and the Cox/Weibull fits, which include the size term,
# dissolve the artifact. The two periods are identical by construction,
# so the period hazard ratio is a true-null calibration check.

# Case-wide tolerance: makes the committed-sample integer counts exact
# (any deviation of 1 or more fails); every statistical field carries
# its own c(value, tol).
tolerance <- 0.5

expected_km <- list(
  # The pooled (unadjusted) view -- the "blind" analysis this case
  # exists to exhibit. Mixture truths: S(m) = 0.7*0.88^m + 0.3*0.97^m.
  # mean/median = 1.95 and p90/median = 4.75 vs the memoryless 1.44 and
  # 3.32: the tail belongs to the large dogs.
  median_los      = c(8, 1.5),        # S(7)=0.5275, S(8)=0.4859
  restricted_mean = c(15.5746, 2.1),  # 0.7*(1-.88^120)/.12 + 0.3*(1-.97^120)/.03
  percentile_90   = c(38, 4.5),       # S(38)=0.0997, extremely borderline
  n_total  = 2166,                    # committed-sample counts (exact)
  n_events = 1851,
  n_capped = 13,                      # LARGE tail past the 120-day cap
  gap_detected = 0
)

expected_cox <- list(
  has_analysis = 1,
  n            = 2166,
  n_events     = 1851,
  # True-null calibration: the two periods are identical by
  # construction, so the period hazard ratio is EXACTLY 1.
  HR_periodPeriod_2 = c(1.0, 0.18),
  # Grouped proportional hazards between the sizes:
  # theta = ln(0.97)/ln(0.88) = 0.238258 (committed sample fits 0.248).
  HR_animal_groupLARGE = c(0.238258, 0.06)
)

expected_weibull <- list(
  has_analysis = 1,
  n            = 2166,
  n_events     = 1851,
  # WITH the size term the hazard is constant within group, so the true
  # shape is 1; fitting a continuous Weibull to whole-day geometric
  # stays biases it up ~ +0.12 (scan mean 1.115), and the tolerance
  # covers bias + 4 SD.
  shape = c(1.0, 0.22),
  # The unified companion (intercept + period only, reported at the
  # bottom of the Weibull worksheet) drops the size term, and its shape
  # IS the declining-hazard illusion this case is about: pseudo-truth
  # ~0.87 from the authoring scan (mean 0.869, SD 0.018; committed
  # sample 0.886), well below 1 although no dog's hazard ever falls.
  shape_crude        = c(0.87, 0.08),
  crude_same_as_main = 0,   # distinct fit: the main model has the size term
  # True LOS ratio: mean 33.33 / mean 8.33 = 4; discretization biases
  # it down ~ -0.2 in some draws (committed 3.80). Period TR: null, 1.
  TR_animal_groupLARGE = c(4.0, 0.95),
  TR_periodPeriod_2    = c(1.0, 0.2),
  # Implied hr = TR^(-shape); continuous-model truth 1/4 = 0.25.
  HRw_animal_groupLARGE = c(0.25, 0.09)
)

# Per-predictor Weibull shape variants (.weibull_regression_analysis):
# same scale formula as expected_weibull's main fit (period + animal_group,
# both present here since intake_type is absent), but with shape(...) added
# for whichever predictor the variant is NOT named for. With exactly one such
# predictor there is nothing to cross it with, so this case exercises the
# additive shape formula and the crossing branch reports crossed = FALSE with
# no reason; the three-predictor case is an inline test in run_tests.R.
# Committed-sample
# values only (no independent multi-seed scan was run for these -- the
# tolerances below are carried over from the closely analogous fields in
# expected_weibull, which WAS scanned, since both fields describe the same
# underlying quantities under a slightly more flexible shape).
expected_stratifier_weibull_period <- list(
  has_analysis = 1,
  n            = 2166,
  n_events     = 1851,
  # scale = period + animal_group (adjusted, like expected_weibull), shape =
  # animal_group. Reference-combination shape (animal_group = SMALL): within-
  # group hazard is exactly constant by construction, so the true value is 1,
  # same reasoning as expected_weibull$shape.
  shape                 = c(1.0, 0.25),
  SR_periodPeriod_2     = c(1.0, 0.25),  # true null, as in expected_weibull
  SR_animal_groupLARGE  = c(4.0, 1.0),   # true 33.33/8.33 = 4, as in expected_weibull
  # Shape ratio LARGE/SMALL: both groups are individually constant-hazard, so
  # the true ratio is 1 (scale already carries the group LOS difference).
  SHAPE_animal_groupLARGE = c(1.0, 0.2)
)

expected_stratifier_weibull_group <- list(
  has_analysis = 1,
  n            = 2166,
  n_events     = 1851,
  # scale = period + animal_group, shape = period. Reference-combination
  # shape (period = Period_1): same constant-hazard reasoning, true value 1.
  shape                = c(1.0, 0.25),
  SR_periodPeriod_2    = c(1.0, 0.25),
  SR_animal_groupLARGE = c(4.0, 1.0),
  # Shape ratio Period_2/Period_1: the two periods are identical by
  # construction, so the true ratio is 1.
  SHAPE_periodPeriod_2 = c(1.0, 0.2)
)

# Per-stratifier stratified Cox variants (.cox_stratified_variants): the same
# two predictors as expected_cox, but with the OTHER one moved inside strata(),
# so each of its levels carries its own baseline hazard instead of being tied
# to a shared one by proportional hazards. The truths are exactly the ones
# expected_cox already pins, and the point of pinning them again here is that
# they must SURVIVE the move: this generator makes each size's hazard exactly
# constant, so proportional hazards holds and freeing the baseline can cost
# precision but must not shift the estimate. A future change that broke the
# stratification (crossing the wrong terms, say, or losing the releveling)
# would show up as these two drifting away from expected_cox's values while
# expected_cox itself still passed.
expected_cox_stratified_period <- list(
  has_analysis = 1,
  n            = 2166,
  n_events     = 1851,
  # strata(animal_group): one baseline per size, both with events.
  n_strata             = 2,
  n_strata_with_events = 2,
  lr_df                = 1,  # period supplies the model's only coefficient
  # True null, as in expected_cox: the two periods are identical.
  HR_periodPeriod_2 = c(1.0, 0.2)
)

expected_cox_stratified_group <- list(
  has_analysis = 1,
  n            = 2166,
  n_events     = 1851,
  # strata(period): one baseline per period.
  n_strata             = 2,
  n_strata_with_events = 2,
  lr_df                = 1,
  # theta = ln(0.97)/ln(0.88) = 0.238258, the same truth expected_cox recovers
  # under the shared baseline, at the same tolerance.
  HR_animal_groupLARGE = c(0.238258, 0.06)
)

expected_stratified_km <- list(
  # The sighted view: within each size the curve is exactly geometric.
  group.LARGE.n      = 753,
  group.LARGE.events = 549,
  group.LARGE.median = c(23, 5.5),      # 0.97^22=0.5117, ^23=0.4963 borderline
  group.LARGE.rmean  = c(32.4709, 5.5), # (1-0.97^120)/0.03
  group.SMALL.n      = 1413,
  group.SMALL.events = 1302,
  group.SMALL.median = c(6, 1.6),       # 0.88^5=0.5277, ^6=0.4644
  group.SMALL.rmean  = c(8.3333, 1.1),  # (1-0.88^120)/0.12
  # Both periods sample the SAME mixture truths (the null, seen at the
  # KM level): identical medians and restricted means.
  period.Period_1.n      = 1078,
  period.Period_1.events = 910,
  period.Period_1.median = c(8, 2),
  period.Period_1.rmean  = c(15.5746, 2.75),
  period.Period_2.n      = 1088,
  period.Period_2.events = 941,
  period.Period_2.median = c(8, 2),
  period.Period_2.rmean  = c(15.5746, 2.75),
  n_strata_gaps          = 0
)

expected_period_stats <- list(
  # Capped Little's law at steady state, in BOTH periods: mean census =
  # intakes/day x E[min(LOS, cap)] = 10 x 15.5746 = 155.75 (the census
  # statistic counts animal-days only up to restricted_stay_cap; see
  # settings.yaml). Of that census, ~63% is LARGE dogs from 30% of
  # intakes -- the composition fact is derived in settings.yaml, though
  # the per-group split is not a reported statistic.
  Period_1.mean_census_inventory = c(155.746, 27),
  Period_2.mean_census_inventory = c(155.746, 30),
  # Flow: steady state, so outcomes match intakes (10/day) throughout.
  Period_1.mean_daily_intakes  = c(10, 1.2),
  Period_2.mean_daily_intakes  = c(10, 1.2),
  Period_1.mean_daily_outcomes = c(10, 1.2),
  Period_2.mean_daily_outcomes = c(10, 1.2),
  # Left truncation happens in both periods (committed-sample counts):
  # period 0 residents enter period 1 truncated, period 1's residents
  # enter period 2 the same way.
  Period_1.left_truncated = 142,
  Period_2.left_truncated = 159
)

# Census-by-tenure companion (math methods 5.7): predicted_census = mean
# daily intakes x KM restricted mean. The per-period values re-pin the
# mean_census truths above through the KM route; the per-group values pin
# the composition fact the mean_census comment could only assert: LARGE
# dogs hold 97.4 / 155.7 = 63% of the census from 30% of intakes.
# Tolerances combine the intake-rate and rmean pins in quadrature.
expected_census <- list(
  group.LARGE.lambda = c(3, 0.7),
  group.SMALL.lambda = c(7, 1.0),
  group.LARGE.predicted_census = c(97.413, 28),   # 3 x 32.4709
  group.SMALL.predicted_census = c(58.333, 12),   # 7 x 8.3333
  # One day-grid pin: N(5) for SMALL = 7 x 0.88^5 = 3.694 -- the census
  # profile is the intake rate times the geometric survival curve.
  group.SMALL.day5 = c(3.694, 0.8),
  period.Period_1.predicted_census = c(155.746, 33),
  period.Period_2.predicted_census = c(155.746, 33)
)
