# Expected values for sim_cause_rate_shift (statistical case; see
# settings.yaml for the generating truth and generator.R for the model).
#
# As in the other sim_* fixtures, expected values are the KNOWN
# PARAMETERS of the generating model; statistical fields carry
# c(value, tol) tolerances of ~4 standard deviations of each estimator
# (from a 25-seed scan of the generator at authoring time), and counts
# are properties of the committed sample, pinned exactly through the
# case-wide tolerance.
#
# The story this case pins: at the period 1 -> 2 boundary the
# cause-specific within-day rates change by DIFFERENT factors (L x3,
# T x1/3, N x1) whose share-weighted sum is exactly 2, so every
# all-cause statistic below is numerically identical in truth to
# sim_geometric_period_effect's, and only the by-period AJ block can
# tell the two fixtures' worlds apart: the cause shares shift from
# 0.6/0.3/0.1 to 0.9/0.05/0.05 (L's plateau rises, T's collapses
# 6-fold, and N's halves even though N's own rate never changed).

# Case-wide tolerance: sized for the small-share AJ probability checks
# (~4 SD of a 0.05-share CIF/CondRem at each period's ~1000 events),
# tight enough to separate the post-shift N share (0.05) from the 0.1
# that a naive "N unchanged" reading would predict. Larger-variance
# fields override it per-field below.
tolerance <- 0.04

expected_km <- list(
  # The unified KM pools rows from the two regimes, so its median and
  # restricted mean are composition-weighted mixtures with no clean
  # closed form; only the committed-sample counts are pinned here.
  n_total  = 2217,
  n_events = 1967,
  n_capped = 0,     # the 120-day cap never binds (see settings.yaml)
  gap_detected = 0
)

expected_cox <- list(
  has_analysis = 1,
  n            = 2217,
  n_events     = 1967,
  # True all-cause hazard ratio EXACTLY 2: the share-weighted rate
  # multiplier is 0.6*3 + 0.3/3 + 0.1 = 2, and 1 - q2 = (1 - q1)^2 is
  # the grouped form of proportional hazards with ratio 2, which the
  # Efron tie handling targets (math document Section 6.2; the 25-seed
  # authoring scan averaged 2.021 with SE 0.022, and the committed
  # sample fits 1.970). tol = ~4 SD across the scan. The Cox model
  # cannot see the cause-level divergence: this one number is all it
  # reports, identical in truth to the geometric case's.
  HR_periodPeriod_2 = c(2.0, 0.45)
)

expected_stratified_km <- list(
  # Within each period the all-cause hazard is constant, so each
  # period's KM curve is exactly geometric: S_p(m) = Q_p^m, median =
  # smallest m with S_p(m) <= 0.5, restricted mean (cap 120, never
  # binding) = 1/q_p. Identical truth to sim_geometric_period_effect.
  period.Period_1.n      = 1089,
  period.Period_1.events = 924,
  period.Period_1.median = c(12, 2),        # 0.94^11 = 0.506 is borderline
  period.Period_1.rmean  = c(16.6567, 2.5),
  period.Period_2.n      = 1128,
  period.Period_2.events = 1043,
  period.Period_2.median = c(6, 1.5),
  period.Period_2.rmean  = c(8.5911, 1),
  # Observation gap in the sparse extreme-tenure tail of the fast-hazard
  # period: past tenure ~72 the period-2 risk set thins to a lone
  # inherited long-term resident, and mLOS flags the empty stretch
  # before its exit. Survival there is already ~1e-3, so every statistic
  # above is unaffected; these pins are committed-sample facts (they
  # move with a fresh seed) that exercise the gap reporting.
  n_strata_gaps          = 1,
  gap.Period.Period_2.start = 72,
  gap.Period.Period_2.end   = 96
)

# Per-period AJ: THE analysis this fixture exists for. Within a regime
# the outcome day and the cause are independent, so cif_Any(m) =
# 1 - Q_p^m and CIF_cause = share_cause * cif_Any; CondRem_cause =
# share_cause up to a < 0.005 tail correction (see settings.yaml).
# Checked near each period's median day: the two-fold compression puts
# Period 2's day 6 and Period 1's day 12 on the SAME all-cause value
# (cif_Any = 1 - 0.94^12 = 0.52408, the geometric case's number), while
# the cause split differs, which is exactly what separates this fixture
# from a uniform doubling:
#   L: 0.31445 -> 0.47167 (rate x3: plateau up, reached 2x faster)
#   T: 0.15722 -> 0.02620 (rate x1/3: plateau down 6-fold, yet reached
#                          2x faster; the time scale belongs to the
#                          all-cause hazard, not to T)
#   N: 0.05241 -> 0.02620 (rate UNCHANGED: the faster L claims animals
#                          first, so N's share halves anyway)
expected_aj_period <- list(
  has_analysis = 1,
  n_periods    = 2,
  Period_1.cif_Any_day12   = c(0.52408, 0.07),
  Period_1.cif_L_day12     = c(0.31445, 0.07),
  Period_1.cif_T_day12     = c(0.15722, 0.05),
  Period_1.cif_N_day12     = 0.05241,
  Period_1.condrem_L_day12 = c(0.6, 0.08),
  Period_1.condrem_T_day12 = c(0.3, 0.09),
  Period_1.condrem_N_day12 = c(0.1, 0.06),
  Period_2.cif_Any_day6    = c(0.52408, 0.09),
  Period_2.cif_L_day6      = c(0.47167, 0.09),
  Period_2.cif_T_day6      = 0.02620,
  Period_2.cif_N_day6      = 0.02620,
  Period_2.condrem_L_day6  = c(0.9, 0.05),
  Period_2.condrem_T_day6  = c(0.05, 0.045),
  Period_2.condrem_N_day6  = 0.05
)
