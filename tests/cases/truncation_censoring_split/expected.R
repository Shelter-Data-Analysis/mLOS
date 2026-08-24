# Expected km_unified_period() results for truncation_censoring_split.
# Hand-derived (see settings.yaml comment): pooling animal 5's censored row
# (0,5], event=0) with its truncated continuation ((5,10], event=1) exactly
# reconstructs the same uncut (0,10], event=1 interval that animals 1-4 each
# contribute directly -- so the unified KM curve should be identical to
# constant_los_single_period's, but with one extra (censored) row.

expected_km <- list(
  n_total         = 6,   # 4 unsplit animals + animal 5's 2 period-rows
  n_events        = 5,   # one event per logical animal
  n_censored      = 1,   # animal 5's Period_1 row
  n_capped        = 0,
  median_los      = 10,
  percentile_90   = 10,
  restricted_mean = 10,
  max_time        = 10
)

# With 2 periods now (n_periods > 1), Cox actually runs here (unlike the
# single-period fixtures, where it's skipped). Period_1 has zero events, so
# the period coefficient is a genuine complete-separation case: HR is
# NA, not a crash. This also regression-tests a real bug this fixture caught:
# coxph's robust score test (summary()$robscore) can be NULL in this exact
# degenerate shape, which used to crash cox_regression_analysis() on
# round(NULL, 1) -- see the robscore NULL check in mlos_cox.R.
expected_cox <- list(
  has_analysis      = 1,
  n                 = 6,
  n_events          = 5,
  HR_periodPeriod_2 = NA,
  # Definitional reference row for Period_1 (OLDEST default): HR exactly
  # 1, even though the non-reference coefficient diverged to NA above.
  HR_periodPeriod_1 = 1
)

# parametric_regression: WEIBULL is set, but the pooled Weibull fit itself
# fails on this degenerate 2-period, single-predictor shape (complete
# separation, singular Hessian -- see cox_results$weibull$message), so no
# shape variant is ever attempted. Exercises the "declines gracefully" path
# of the shape variants via .weibull_shape_variant_for's fallback,
# independent of the "fewer than two predictors" gate.
expected_stratifier_weibull_period <- list(
  has_analysis = 0
)
