# Expected values for weibull_small (see settings.yaml for the derivation
# and the survreg cross-check of the Weibull pins).

expected_cox <- list(
  has_analysis = 1,
  n            = 14,
  n_events     = 13,
  concordance  = 0.594444,
  HR_intake_typeowner = 0.432698,
  # The reference level appears as a definitional row: HR exactly 1.
  HR_intake_typestray = 1
)

expected_weibull <- list(
  has_analysis = 1,
  n            = 14,
  n_events     = 13,
  shape        = 1.289723,
  TR_intake_typeowner  = 2.325576,
  HRw_intake_typeowner = 0.336726,
  # Definitional reference rows, mirroring the Cox table.
  TR_intake_typestray  = 1,
  HRw_intake_typestray = 1
)
