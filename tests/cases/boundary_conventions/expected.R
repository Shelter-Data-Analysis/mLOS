# Expected results for boundary_conventions.
# Hand-derived (see settings.yaml comment): same-day intake/outcome gives
# LOS 1; an outcome exactly on a period boundary is censored in the
# earlier period and counted as an event in the later one; an intake
# exactly on a boundary joins the later period only.

expected_km <- list(
  n_total         = 7,    # 5 animals, two of them split across the boundary
  n_events        = 5,    # one event per animal
  n_censored      = 2,    # the two boundary-censored P1 rows (animals 2, 3)
  n_capped        = 0,
  median_los      = 5,
  percentile_90   = 7,
  restricted_mean = 4.6,  # 1 + 3*(4/5) + 3/5 + 2/5 + 1/5
  max_time        = 7
)

# Stratified by period. Period_2's S(4) = 0.5 exactly, so its median is
# the midpoint of the flat stretch [4, 6): 5 (the same exact-tie midpoint
# convention documented in stratified_km_animal_group).
#
# Stratified by animal_group (n counts stratum ROWS, survfit's "records"):
# SMALL (uncut rows (0,1], (0,4], (0,5], all events): risk sets 3, 2, 1 at
#   days 1, 4, 5 -> S = 2/3, 1/3, 0 -> median = 4 (S(1) = 0.667 > 0.5,
#   S(4) = 0.333 <= 0.5, no tie).
# LARGE (animal 2: (0,5] censored + (5,6] event; animal 3: (0,1] censored
#   + (1,7] event): at day 6 both continuation rows are at risk, 1 event
#   -> S = 1/2 EXACTLY; at day 7 one at risk, 1 event -> S = 0. The exact
#   tie makes the median the midpoint of the flat stretch [6, 7): 6.5.
expected_stratified_km <- list(
  period.Period_1.n      = 4,
  period.Period_1.events = 2,
  period.Period_1.median = 5,
  period.Period_2.n      = 3,
  period.Period_2.events = 3,
  period.Period_2.median = 5,
  group.SMALL.n          = 3,
  group.SMALL.events     = 3,
  group.SMALL.median     = 4,
  group.LARGE.n          = 4,
  group.LARGE.events     = 2,
  group.LARGE.median     = 6.5
)

# 2 periods -> Cox runs with the period predictor; only the fit's shape is
# asserted (the HR itself is not hand-derivable in a useful way here).
expected_cox <- list(
  has_analysis = 1,
  n            = 7,
  n_events     = 5,
  # Definitional reference rows: Period_1 (OLDEST default) and SMALL
  # (animal_group_reference in settings.yaml), each with HR exactly 1.
  HR_periodPeriod_1    = 1,
  HR_animal_groupSMALL = 1
)

# Per-period metrics from the three shared functions in mlos_data.R (the
# single source feeding both the console summary and the Excel By_Period
# sheet). Hand-derived from the period rows in settings.yaml:
#   P1 rows (t_start, t_end]: (0,1] (0,5] (0,1] (0,5]  -> animal-days 12
#   P2 rows:                  (5,6] (1,7] (0,4]        -> animal-days 11
# In-care days per row = (t_end - t_start - 1) * (t_end + t_start) / 2:
#   P1: 0 + 10 + 0 + 10 = 20. The same-day animal (0,1] contributes 0 --
#       an intraday stay has LOS 1 but no overnight presence.
#   P2: 0 + 20 + 6 = 26. Animal 2's (5,6] also contributes 0: one day at
#       risk but no full in-care day inside the period.
# Flow counts use the animal's own intake/outcome dates against the
# period window: P1 has 4 intakes (Jan 2, 5, 10, 14) and 2 outcomes
# (Jan 2, Jan 9); P2 has 1 intake (Jan 15) and 3 outcomes (Jan 15, 18, 20)
# -- the boundary outcome counts in P2, consistent with its event row.
expected_period_stats <- list(
  Period_1.duration_days                   = 14,
  Period_1.total_observations            = 4,
  Period_1.events                        = 2,
  Period_1.censored                      = 2,
  Period_1.left_truncated                = 0,
  Period_1.right_censored                = 2,
  Period_1.capped_at_restricted_stay_cap               = 0,
  Period_1.mean_days_at_risk             = 3,       # (1 + 5 + 1 + 5) / 4
  Period_1.total_animal_days             = 12,
  Period_1.mean_census_inventory                   = 12 / 14,
  Period_1.total_in_care_days_sum        = 20,
  Period_1.daily_mean_total_in_care_days = 20 / 14,
  Period_1.total_intakes                 = 4,
  Period_1.total_outcomes                = 2,
  Period_1.mean_daily_intakes            = 4 / 14,
  Period_1.mean_daily_outcomes           = 2 / 14,

  Period_2.duration_days                   = 17,
  Period_2.total_observations            = 3,
  Period_2.events                        = 3,
  Period_2.censored                      = 0,
  Period_2.left_truncated                = 2,       # animals 2 and 3; animal 4's intake is ON the boundary
  Period_2.right_censored                = 0,
  Period_2.capped_at_restricted_stay_cap               = 0,
  Period_2.mean_days_at_risk             = 11 / 3,  # (1 + 6 + 4) / 3
  Period_2.total_animal_days             = 11,
  Period_2.mean_census_inventory                   = 11 / 17,
  Period_2.total_in_care_days_sum        = 32,      # animal 2 row (5,6]: {5};
                                                    # animal 3 row (1,7]: 1..6 = 21
                                                    # (left-truncated rows keep the
                                                    # boundary night at t_start);
                                                    # animal 4 row (0,4]: 1..3 = 6.
                                                    # P1 20 + P2 32 = 52, the
                                                    # single-period value (see
                                                    # in_care_days_boundary_neutrality)
  Period_2.daily_mean_total_in_care_days = 32 / 17,
  Period_2.total_intakes                 = 1,
  Period_2.total_outcomes                = 3,
  Period_2.mean_daily_intakes            = 1 / 17,
  Period_2.mean_daily_outcomes           = 3 / 17
)

# Per-stratum metrics as the Excel By_Animal_Group sheet computes them:
# the same shared functions grouped by animal_group with the whole-window
# denominator (14 + 17 = 31 days). This is the only hand-derived fixture
# whose strata SPAN a period boundary, so it pins the cross-period
# semantics: row-level counts keep the By_Period conventions (each
# animal-period row counts once, boundary rows included), while the
# unified stay counts re-unite them.
#
# SMALL = animals 1, 4, 5: uncut rows (0,1], (0,4], (0,5], all events.
#   animal-days 1 + 4 + 5 = 10; in-care sums 0 + 6 + 10 = 16 (the
#   per-row 0+1+..+(LOS-1) sums); intakes Jan 2, 15, 5 and outcomes
#   Jan 2, 18, 9 all inside some period -> 3 each. Nothing is split, so
#   the unified stay counts collapse to the row-level ones (3 stays).
# LARGE = animals 2, 3: four rows, (0,5] censored + (5,6] event and
#   (0,1] censored + (1,7] event.
#   Row level: 4 observations, 2 events, 2 left-truncated (both P2
#   continuation rows), 2 right-censored (both P1 boundary rows);
#   animal-days 5 + 1 + 1 + 6 = 13; in-care sums 10 + 5 + 0 + 21 = 36
#   (rows split at the boundary keep the boundary night at t_start, so
#   16 + 36 = 52, the uncut single-period total; see the Period_2
#   comment above and in_care_days_boundary_neutrality).
#   Unified: the 4 rows re-unite into 2 stays, neither left-truncated
#   (both intakes fall inside P1, observed) nor right-censored (both
#   stays end in an event) -- 4/2/2 vs 2/0/0, the exact divergence the
#   sheet's caveat panel describes.
expected_stratum_stats <- list(
  group.SMALL.duration_days        = 31,
  group.SMALL.total_observations = 3,
  group.SMALL.events             = 3,
  group.SMALL.censored           = 0,
  group.SMALL.left_truncated     = 0,
  group.SMALL.right_censored     = 0,
  group.SMALL.capped_at_restricted_stay_cap    = 0,
  group.SMALL.mean_days_at_risk  = 10 / 3,
  group.SMALL.total_animal_days  = 10,
  group.SMALL.mean_census_inventory        = 10 / 31,
  group.SMALL.total_in_care_days_sum        = 16,
  group.SMALL.daily_mean_total_in_care_days = 16 / 31,
  group.SMALL.total_intakes      = 3,
  group.SMALL.total_outcomes     = 3,
  group.SMALL.mean_daily_intakes = 3 / 31,
  group.SMALL.total_stays          = 3,
  group.SMALL.left_truncated_stays = 0,
  group.SMALL.right_censored_stays = 0,

  group.LARGE.duration_days        = 31,
  group.LARGE.total_observations = 4,
  group.LARGE.events             = 2,
  group.LARGE.censored           = 2,
  group.LARGE.left_truncated     = 2,
  group.LARGE.right_censored     = 2,
  group.LARGE.capped_at_restricted_stay_cap    = 0,
  group.LARGE.mean_days_at_risk  = 13 / 4,
  group.LARGE.total_animal_days  = 13,
  group.LARGE.mean_census_inventory        = 13 / 31,
  group.LARGE.total_in_care_days_sum        = 36,
  group.LARGE.daily_mean_total_in_care_days = 36 / 31,
  group.LARGE.total_intakes      = 2,
  group.LARGE.total_outcomes     = 2,
  group.LARGE.mean_daily_outcomes = 2 / 31,
  group.LARGE.total_stays          = 2,
  group.LARGE.left_truncated_stays = 0,
  group.LARGE.right_censored_stays = 0,

  # No intake_type column in this fixture: no intake.* entries may exist.
  intake.STRAY.total_stays = NA
)
