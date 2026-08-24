# Expected values for sim_crossed_shape (statistical case; see
# settings.yaml for the generating truth and generator.R for the model).
#
# The case exists for one thing no other fixture can reach: a variant
# whose crossed and additive shape formulas are DIFFERENT models, which
# needs three qualifying predictors. Everywhere else the two formulas are
# the same string and the crossing path is never exercised.
#
# The generating shape is a checkerboard over intake_type x animal_group,
#
#              G1     G2
#     OWNER   0.70   1.30
#     STRAY   1.30   0.70
#
# whose main effects on the log scale are exactly zero. So the three
# variants split cleanly, and that split is what is pinned here:
#
#   scale = period       shape ~ intake_type x animal_group  -> the real
#                        interaction. Crossing is decisive.
#   scale = intake_type  shape ~ period x animal_group       -> no such
#   scale = animal_group shape ~ period x intake_type           term in
#                        the truth. Crossing buys nothing, and the
#                        statistic sits where a null belongs.
#
# Statistical fields carry c(value, tol) around the committed sample's
# fitted values. Whole-day discretization (ceiling of a continuous
# Weibull) biases fitted shapes upward at this scale, which is why the
# reference-combination k is pinned near 0.75 rather than at the
# generating 0.70, and why the shape ratios sit slightly below the
# generating 1.857.

# Case-wide tolerance: makes the committed-sample integer counts exact.
tolerance <- 0.5

expected_weibull <- list(
  has_analysis = 1,
  n            = 2672,
  n_events     = 2163,
  # One shape for everyone, averaging over a checkerboard that is
  # genuinely there: near 1, and telling you nothing about either cell.
  shape        = c(0.94, 0.08)
)

# The variant that can see the interaction. Its crossed formula fits 288
# log-likelihood units better than the additive one, on the single degree
# of freedom the interaction costs.
expected_stratifier_weibull_period <- list(
  has_analysis     = 1,
  n                = 2672,
  n_events         = 2163,
  shape            = c(0.75, 0.08),
  crossed          = 1,
  crossing_lr_stat = c(288.4, 40),
  crossing_lr_df   = 1,
  # Read at the other shape predictor's reference level, so each is one
  # arm of the checkerboard: 1.30 / 0.70 = 1.857 in the generating truth.
  SHAPE_intake_typeSTRAY = c(1.80, 0.30),
  SHAPE_animal_groupG2   = c(1.74, 0.30),
  # Scale is common to every cell by construction, so period's own LOS
  # ratio is a true null and the other two sit at 1 as well.
  SR_periodPeriod_2      = c(1.00, 0.15)
)

# The two variants whose crossed term is not in the generating model.
# Crossing is still attempted and still reported, and the statistic is
# what a null looks like on one degree of freedom.
expected_stratifier_weibull_intake <- list(
  has_analysis     = 1,
  shape            = c(0.92, 0.08),
  crossed          = 1,
  crossing_lr_stat = c(0.9, 6),
  crossing_lr_df   = 1
)

expected_stratifier_weibull_group <- list(
  has_analysis     = 1,
  shape            = c(0.91, 0.08),
  crossed          = 1,
  crossing_lr_stat = c(1.6, 6),
  crossing_lr_df   = 1
)
