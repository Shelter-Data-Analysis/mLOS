# Expected values for sim_weibull_truncation (statistical case; see
# settings.yaml for the generating truth and generator.R for the model).
#
# Unlike the exact fixtures, the expected values here are the KNOWN
# PARAMETERS of the generating model, not hand-derived properties of this
# particular sample, so each statistical field carries a c(value, tol)
# tolerance sized at ~4 standard errors of its estimator (from the fitted
# models at authoring time), widened where the day-rounding bias
# documented in settings.yaml applies. A fresh sample from generator.R
# with a new seed is expected to pass. Counts (n, events, capped) are
# properties of the committed sample and use the case-wide tolerance,
# which makes integer comparisons exact.

# Case-wide tolerance: sized for the AJ probability checks (~4 standard
# errors of a CIF at n ~ 1100 events); every non-count field with a
# different scale overrides it per-field below.
tolerance <- 0.05

expected_km <- list(
  median_los      = c(11, 1),        # smallest m with S(m) <= 0.5; S(10)=0.517, S(11)=0.477
  restricted_mean = c(14.3509, 1.5), # sum of S(m), m = 0..89; 4*se(rmean) = 1.5
  percentile_90   = c(30, 3),        # smallest m with S(m) <= 0.10
  n_total  = 1180,                   # committed-sample counts (exact)
  n_events = 1086,
  n_capped = 2,
  gap_detected = 0
)

expected_cox <- list(
  has_analysis = 1,
  n            = 1180,
  n_events     = 1086,
  # True hazard ratio 2^(-1.3); tol = 4 robust SE on the log scale.
  HR_intake_typeOWNER = c(0.406127, 0.12)
)

expected_weibull <- list(
  has_analysis = 1,
  n            = 1180,
  n_events     = 1086,
  # Day rounding biases the fitted shape up by ~0.08 and the LOS ratio
  # down by ~0.04 (see settings.yaml); tolerances cover bias + 4 SE.
  shape                = c(1.3, 0.21),
  TR_intake_typeOWNER  = c(2.0, 0.4),
  HRw_intake_typeOWNER = c(0.406127, 0.11)
)

expected_stratified_km <- list(
  intake.STRAY.n      = 582,
  intake.STRAY.events = 553,
  intake.STRAY.median = c(8, 1),        # smallest m with exp(-(m/10)^1.3) <= 0.5
  intake.STRAY.rmean  = c(9.7380, 1.3), # sum of S_STRAY(m), m = 0..89
  intake.OWNER.n      = 598,
  intake.OWNER.events = 533,
  intake.OWNER.median = c(16, 1.5),     # S_OWNER(15) = 0.503 is borderline, so 15 also passes
  intake.OWNER.rmean  = c(18.9639, 2.5),
  # .pos pins the KM output order (legend/CSV column order): intake_type is
  # canonically ALPHABETICAL, so OWNER before STRAY. These positions are the
  # deterministic factor-level order and carry no statistical tolerance, unlike
  # the sampled counts above. Counterpart to the chronological period order
  # pinned in custom_period_labels.
  intake.OWNER.pos    = 1,
  intake.STRAY.pos    = 2,
  n_strata_gaps       = 0
)

# Cause is independent of stay length, so CIF_cause(m) = p_cause * F(m)
# and CondRem_cause(m) = p_cause flat in m. All use the case tolerance.
expected_aj <- list(
  has_analysis     = 1,
  n_outcome_states = 3,
  cif_Any_day10 = 0.48295,   # 1 - S(10)
  cif_L_day10   = 0.33807,   # 0.7 * (1 - S(10))
  cif_Any_day30 = 0.90039,   # 1 - S(30)
  cif_L_day30   = 0.63028,
  cif_T_day30   = 0.18008,
  cif_N_day30   = 0.09004,
  condrem_L_day30 = 0.7,
  condrem_T_day30 = 0.2,
  condrem_N_day30 = 0.1
)
