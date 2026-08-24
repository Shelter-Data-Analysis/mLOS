# Expected results for aj_competing_risks_mixed.
# Hand-derived (see settings.yaml comment): 7 animals resolve L at day 10,
# 2 resolve T at day 15, 1 resolves N at day 20, no censoring.

expected_km <- list(
  n_total         = 10,
  n_events        = 10,
  n_censored      = 0,
  n_capped        = 0,
  median_los      = 10,
  # S(t) = 0.1 exactly for t in [15, 20) -- an exact tie with the 0.10
  # threshold. survival::quantile.survfit() reports the midpoint of that
  # flat stretch (17.5), not its left edge (15); see mlos_math_methods.md
  # Sec 5.2's "exact-tie exception". Confirmed directly: fit$time = 10,15,20,
  # fit$surv = 0.3,0.1,0, quantile(fit, 0.9)$quantile = 17.5 (its "lower" CI
  # bound for that same quantile is 15, the naive smallest-t value).
  percentile_90   = 17.5,
  restricted_mean = 12,
  max_time        = 20
)

# Single period, no intake_type/animal_group columns -> no Cox predictor.
expected_cox <- list(
  has_analysis = 0
)

# AJ competing-risk CIF, hand-derived in settings.yaml: cif_L jumps to 0.7 at
# day 10, cif_T jumps to 0.2 at day 15, cif_N jumps to 0.1 at day 20, and
# cif_Any = 1 - S(t) throughout since there is no censoring. condrem_<cause>
# is P(eventual outcome = cause | still unresolved at this day): at day 0
# (everyone still at risk) it equals the final CIF proportions; at day 10,
# right after the L cohort resolves, L's remaining share is used up (0) and
# the remaining 0.3 probability mass splits 1/3 N, 2/3 T among what's left
# at risk -- the three condrem_*_day10 values sum to 1.
expected_aj <- list(
  has_analysis     = 1,
  max_time         = 20,
  n_outcome_states = 3,

  cif_L_day0    = 0,
  cif_T_day0    = 0,
  cif_N_day0    = 0,
  cif_Any_day0  = 0,
  cif_L_day9    = 0,

  cif_L_day10   = 0.7,
  cif_T_day10   = 0,
  cif_N_day10   = 0,
  cif_Any_day10 = 0.7,
  cif_L_day14   = 0.7,

  cif_L_day15   = 0.7,
  cif_T_day15   = 0.2,
  cif_N_day15   = 0,
  cif_Any_day15 = 0.9,
  cif_T_day19   = 0.2,

  cif_L_day20   = 0.7,
  cif_T_day20   = 0.2,
  cif_N_day20   = 0.1,
  cif_Any_day20 = 1,

  condrem_L_day0  = 0.7,
  condrem_T_day0  = 0.2,
  condrem_N_day0  = 0.1,
  condrem_L_day10 = 0,
  condrem_N_day10 = 1 / 3,
  condrem_T_day10 = 2 / 3
)
