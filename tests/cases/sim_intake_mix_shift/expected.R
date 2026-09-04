# Expected values for sim_intake_mix_shift (statistical case; see
# settings.yaml for the generating truth and generator.R for the model).
#
# As in the other sim_* fixtures, expected values are the KNOWN
# PARAMETERS of the generating model; statistical fields carry
# c(value, tol) tolerances of ~4 standard deviations of each estimator
# (from a 30-seed scan of the generator at authoring time), and counts
# are properties of the committed sample, pinned exactly through the
# case-wide tolerance.
#
# The story this case pins: at the period 1 -> 2 boundary every dog's
# within-day rate improves x1.5 while the intake mix flips 70/30 ->
# 30/70 SMALL/LARGE, at constant 10 dogs/day. Because large dogs stay
# far longer, the two changes fight, and the CRUDE view loses:
#
#   crude (per-period pooled KM):   median 8 -> 10 days   (worse)
#                                   census 155.7 -> 173.3 (fuller)
#   adjusted (Cox with period+size): HR 1.5 in periods 2 AND 3
#                                   (every dog 50% faster)
#
# Both describe the same data correctly. Period 2 is the transition and
# its pooled statistics are deliberately unchecked.

# Case-wide tolerance: makes the committed-sample integer counts exact
# (any deviation of 1 or more fails); every statistical field carries
# its own c(value, tol).
tolerance <- 0.5

expected_km <- list(
  # The unified KM pools both regimes AND both mixes, so its median and
  # restricted mean have no clean closed form; only the committed-sample
  # counts are pinned here.
  n_total  = 3229,
  n_events = 2750,
  n_capped = 10,     # LARGE tail past the 120-day cap
  gap_detected = 0
)

expected_cox <- list(
  has_analysis = 1,
  n            = 3229,
  n_events     = 2750,
  # THE ADJUSTED VIEW, and the point of the case. All three true
  # coefficients are exact: both sizes' rates scale by the same 1.5, so
  # there is no period-by-size interaction and this two-predictor model
  # is correctly specified.
  #
  # Period: the within-day rate improves x1.5, and Q -> Q^1.5 is the
  # grouped form of proportional hazards with ratio 1.5. Periods 2 and
  # 3 share the same true hazard, so these two fields check the SAME
  # truth twice. An HR ABOVE 1 means dogs leave FASTER (shorter stays);
  # that the crude medians move the opposite way is the paradox.
  # Committed sample fits 1.533 / 1.485; scan mean 1.49 (SD 0.094).
  HR_periodPeriod_2 = c(1.5, 0.38),
  HR_periodPeriod_3 = c(1.5, 0.38),
  # Size: ln(0.97)/ln(0.88) = 0.238273, unchanged by the boundary
  # (both rates scale together). The same truth sim_size_mixture pins,
  # here recovered from an independent sample under a moving mix.
  HR_animal_groupLARGE = c(0.238273, 0.05)
)

# Per-stratifier stratified Cox variants (.cox_stratified_variants): the model
# of expected_cox with one predictor moved inside strata(), so its levels get
# their own baseline hazards instead of a shared one. This case is the sharper
# test of the two sim fixtures that pin these, because the composition moves:
# the intake mix flips across the boundary, so if the stratification were
# miswired the period contrast would pick up the mix shift and land nowhere
# near 1.5. It does not, because the SIZE dimension is what gets its own
# baseline here, exactly as adjusting for it does in expected_cox.
expected_cox_stratified_period <- list(
  has_analysis = 1,
  n            = 3229,
  n_events     = 2750,
  # strata(animal_group): one baseline per size.
  n_strata             = 2,
  n_strata_with_events = 2,
  lr_df                = 2,  # three periods, two contrasts
  # Period_3 carries the true hazard ratio of 1.5, as in expected_cox, now
  # under a free per-size baseline.
  HR_periodPeriod_3 = c(1.5, 0.38),
  # Both periods share that truth, which frees Period_2 to pin the variant
  # fit's tie rule, as sim_geometric_period_effect pins the pooled fit's.
  # The variant is a separate coxph call, so it needs its own pin: Breslow
  # returns 1.4955 here, twelve tolerances out. Committed-sample value,
  # moving with a fresh seed.
  HR_periodPeriod_2 = c(1.531008, 0.003)
)

expected_cox_stratified_group <- list(
  has_analysis = 1,
  n            = 3229,
  n_events     = 2750,
  # strata(period): one baseline per period, and the reason this variant is
  # worth pinning -- the period effect is now absorbed into three separate
  # baselines rather than assumed proportional, and the size contrast has to
  # come out at the same closed-form truth either way.
  n_strata             = 3,
  n_strata_with_events = 3,
  lr_df                = 1,
  HR_animal_groupLARGE = c(0.238273, 0.05)
)

expected_stratified_km <- list(
  # THE CRUDE VIEW: within a STEADY period the pooled curve is the
  # intake-share mixture of the two sizes' geometrics, and its median
  # RISES from 8 to 10 across the boundary although every dog improved.
  # Period 1: S(m) = 0.7*0.88^m + 0.3*0.97^m
  # Period 3: S(m) = 0.3*0.825513^m + 0.7*0.955339^m
  period.Period_1.n      = 1098,
  period.Period_1.events = 931,
  period.Period_1.median = c(8, 2),        # S(7)=0.52847, S(8)=0.48687
  period.Period_1.rmean  = c(15.5747, 3),  # = sim_size_mixture's period truth
  period.Period_3.n      = 1050,
  period.Period_3.events = 900,
  period.Period_3.median = c(10, 2),       # S(9)=0.51741, S(10)=0.48737
  period.Period_3.rmean  = c(17.3279, 2.6),
  # Period 2 is the TRANSITION: the standing population is still working
  # off its old composition, so its pooled median and restricted mean
  # have no clean closed form and are deliberately not checked. Only its
  # counts are pinned. (The committed sample shows median 9, neatly
  # between the two steady-state truths, but that is not a truth to
  # pin -- the scan spread its median over 8..12.)
  period.Period_2.n      = 1081,
  period.Period_2.events = 919,
  # The group-stratified KM pools BOTH regimes for each size, so its
  # curves are pre/post hazard mixtures with no clean closed form --
  # the very pooling trap this case is about, one level down. Counts
  # only; see settings.yaml.
  group.LARGE.n      = 1910,
  group.LARGE.events = 1509,
  group.SMALL.n      = 1319,
  group.SMALL.events = 1241,
  n_strata_gaps      = 0
)

expected_period_stats <- list(
  # Capped Little's law at steady state (the census statistic counts
  # animal-days only up to restricted_stay_cap, so the truth is
  # intakes/day x E[min(LOS, 120)]): the shelter gets FULLER while every
  # dog gets faster. Period 2 is NOT checked (transition). Period 3's
  # tolerance also absorbs its ~3.3 settling bias: its start is 4.11
  # time constants past the boundary, so it is ~98.4% relaxed, not 100%
  # (measured in the authoring scan; see settings.yaml).
  Period_1.mean_census_inventory = c(155.747, 31),
  Period_3.mean_census_inventory = c(173.279, 31),
  # Volume never changed, only the mix -- load-bearing for the story, so
  # pinned in all three periods including the transition.
  Period_1.mean_daily_intakes = c(10, 1.1),
  Period_2.mean_daily_intakes = c(10, 1.4),
  Period_3.mean_daily_intakes = c(10, 1.0),
  # Outflow matches inflow in the steady periods. Period 2's outflow
  # runs ~0.25/day below inflow as the population accumulates its extra
  # ~24 animals, but that is far inside sampling noise here, so it is
  # not pinned (see settings.yaml and README.md).
  Period_1.mean_daily_outcomes = c(10, 1.0),
  Period_3.mean_daily_outcomes = c(10, 1.1),
  # Left truncation happens in every period (committed-sample counts):
  # period 0 residents enter period 1 truncated, and each later period
  # inherits the previous one's residents the same way.
  Period_1.left_truncated = 152,
  Period_2.left_truncated = 160,
  Period_3.left_truncated = 160
)

# Census-by-tenure companion (math methods 5.7): predicted_census = mean
# daily intakes x KM restricted mean, per steady period -- the KM route
# to the same capped Little's-law truths as mean_census above, showing
# the shelter getting FULLER while every dog gets faster. Period 2 (the
# transition) and the group strata (pre/post hazard mixtures) have no
# clean closed form and are not checked.
expected_census <- list(
  period.Period_1.lambda = c(10, 1.1),
  period.Period_3.lambda = c(10, 1.0),
  period.Period_1.predicted_census = c(155.747, 33),
  period.Period_3.predicted_census = c(173.279, 33)
)
