# Expected results for stratified_km_animal_group.
# Hand-derived (see settings.yaml comment), then verified directly against
# survfit()/summary() before being written down here.
#
# Two rows have a BLANK animal_group, which .fill_missing_level turns into
# the explicit "_UNKNOWN_" level; the pins below run that level through
# the stratified KM, the by-group AJ, and Cox as a real, analyzable
# stratum (the integration counterpart of the unit checks in
# run_tests.R's validation section).

# Unified/pooled curve: 10 distinct LOS values 1..10, no censoring, so
# survival right after the k-th smallest event = (10-k)/10. Two exact
# threshold ties, both reported as the midpoint of the touching step (as
# in aj_competing_risks_mixed): S(5) = 0.5 exactly -> median 5.5, and
# S(9) = 0.1 exactly -> percentile_90 = 9.5 (the midpoint rule at the
# 0.10 threshold, which no other case exercises). The restricted mean,
# computed directly as the area under S(t), is (10+9+...+1)/10 = 5.5.
expected_km <- list(
  n_total         = 10,
  n_events        = 10,
  n_censored      = 0,
  n_capped        = 0,
  median_los      = 5.5,
  percentile_90   = 9.5,
  restricted_mean = 5.5,
  max_time        = 10
)

# Stratified by animal_group: each stratum has distinct event days with no
# censoring, so survival right after its own k-th smallest event = (n-k)/n.
# SMALL (n=3, days 1,2,3): S = 2/3, 1/3, 0 -> median = 2 (S(1)=0.667 > 0.5,
#   S(2)=0.333 <= 0.5; no exact tie).
# LARGE (n=5, days 4,5,6,7,8): S = 0.8,0.6,0.4,0.2,0 -> median = 6
#   (S(5)=0.6 > 0.5, S(6)=0.4 <= 0.5; no exact tie).
# _UNKNOWN_ (n=2, days 9,10): S = 0.5, 0 -> S(9) = 0.5 is an exact tie,
#   so the median is the midpoint of that step: 9.5.
# .pos pins the KM output order (legend/CSV column order): animal_group is
# canonically in byte order, so LARGE, SMALL, then _UNKNOWN_. The fill lands
# last because these labels are upper case and the underscore's byte sits
# above them; against lower-case labels the same rule puts it first. Byte
# order is the C locale's, held there by the LC_COLLATE pin at the top of
# mlos_common.R, without which a UTF-8 locale collates the underscore ahead
# of every letter and this order reverses. This is the counterpart to the
# chronological period order pinned in custom_period_labels; both come from
# the factor levels set at data construction and read back through
# .stratum_levels_present.
expected_stratified_km <- list(
  group.SMALL.n          = 3,
  group.SMALL.events     = 3,
  group.SMALL.median     = 2,
  group.LARGE.n          = 5,
  group.LARGE.events     = 5,
  group.LARGE.median     = 6,
  group._UNKNOWN_.n      = 2,
  group._UNKNOWN_.events = 2,
  group._UNKNOWN_.median = 9.5,
  group.LARGE.pos        = 1,
  group.SMALL.pos        = 2,
  group._UNKNOWN_.pos    = 3
)

# AJ within each animal_group. Every animal here has outcome L and none is
# censored, so L is the only competing state and cif_L = 1 - S(t) exactly,
# stepping by 1/n at each stratum's own event days: SMALL by 1/3 at days
# 1,2,3, LARGE by 1/5 at days 4..8, and _UNKNOWN_ by 1/2 at days 9,10.
# The same (n-k)/n reasoning as expected_stratified_km above, read as
# incidence rather than survival.
#
# Each stratum's grid ends at its OWN last event, so SMALL is tabulated only
# through day 3 and has no day-4 cell at all (asserted as NA below, an
# absence assertion). That raggedness costs nothing: a CIF is flat past its
# last event, so extending SMALL's grid to day 8 would only add terms of
# CIF(tau) - CIF(t) = 1 - 1 = 0, leaving every CondRem value and the
# restricted mean unchanged.
#
# The companion CSV's restricted_mean row (.cif_normalized_rmean, the mean
# days to outcome among those who reach it by tau) is 2 for SMALL, 6 for
# LARGE, and 9.5 for _UNKNOWN_, which with no censoring is just the plain
# mean of each stratum's LOS: (1+2+3)/3, (4+..+8)/5, (9+10)/2.
expected_aj_group <- list(
  has_analysis    = 1,
  n_animal_groups = 3,

  SMALL.cif_L_day0   = 0,
  SMALL.cif_L_day1   = 1 / 3,
  SMALL.cif_L_day2   = 2 / 3,
  SMALL.cif_L_day3   = 1,
  SMALL.cif_Any_day3 = 1,
  # SMALL's last event is day 3; nothing is tabulated past it.
  SMALL.cif_L_day4   = NA,

  # P(L after day 0 | in care at day 0) = 1: everyone leaves L eventually.
  SMALL.condrem_L_day0 = 1,
  # By day 3 nobody is left at risk, so the conditional is undefined (0/0),
  # not 0 -- see the at_risk_x guard in compute_aj_cif_results.
  SMALL.condrem_L_day3 = NA,

  LARGE.cif_L_day3   = 0,
  LARGE.cif_L_day4   = 0.2,
  LARGE.cif_L_day5   = 0.4,
  LARGE.cif_L_day6   = 0.6,
  LARGE.cif_L_day7   = 0.8,
  LARGE.cif_L_day8   = 1,
  LARGE.cif_Any_day8 = 1,
  LARGE.condrem_L_day0 = 1,

  # The filled level is a real stratum with its own AJ tabulation.
  `_UNKNOWN_.cif_L_day8`    = 0,
  `_UNKNOWN_.cif_L_day9`    = 0.5,
  `_UNKNOWN_.cif_L_day10`   = 1,
  `_UNKNOWN_.cif_Any_day10` = 1,
  `_UNKNOWN_.condrem_L_day0` = 1
)

# One period (see settings.yaml), so the by-period AJ has a single stratum. It
# still runs: having only one level means there is nothing to COMPARE, which
# suppresses the plot and its CSV, but the numbers are needed for the workbook
# column all the same. The single stratum is the whole sample, so its CIF is
# the unified one: the ten animals have LOS 0 to 9 and every outcome is L, and
# a stay of LOS k departs at day k+1, so cif_L(d) = d/10 across the grid.
expected_aj_period <- list(
  has_analysis = 1,
  n_periods    = 1,
  Period_1.cif_L_day1    = 0.1,
  Period_1.cif_L_day5    = 0.5,
  Period_1.cif_L_day10   = 1,
  Period_1.cif_Any_day10 = 1
)

# No intake_type column at all, which is a different case: nothing to compute,
# not merely nothing to compare. This one still declines.
expected_aj_intake <- list(has_analysis = 0)

# Per-stratum observation/census/flow stats, as the Excel By_Animal_Group
# sheet computes them: the shared metric functions grouped by animal_group
# with the whole-window day denominator. One period of 31 days (2021-01-01
# to 2021-02-01, end excluded), all 10 intakes and outcomes inside it, no
# truncation, censoring, or capping anywhere, so every value is exact:
#
# - total_observations: one animal-period row per animal (single period,
#   so rows = animals here): 3 / 5 / 2.
# - days_at_risk per row = its LOS, so total_animal_days are the LOS sums
#   1+2+3 = 6, 4+..+8 = 30, 9+10 = 19 (together 55, the pooled total), and
#   mean_census = that sum over the 31-day window.
# - total_in_care_days_sum: per row (time_start = 0, so m = 1) the formula
#   (time_end - m)(time_end + m - 1)/2 collapses to LOS(LOS-1)/2, i.e. the
#   0+1+..+(LOS-1) in-care day-count sum: SMALL 0+1+3 = 4, LARGE
#   6+10+15+21+28 = 80, _UNKNOWN_ 36+45 = 81 (together 165, the pooled
#   sum), each divided by the 31-day window for the daily mean.
# - flows: every intake and outcome date lies inside the single period, so
#   each stay is counted once and the daily means divide by 31.
#
# The filled _UNKNOWN_ level is pinned as an ordinary stratum here too. No
# intake_type column exists, so the intake absence assertion closes the
# block.
expected_stratum_stats <- list(
  group.SMALL.total_observations = 3,
  group.SMALL.events             = 3,
  group.SMALL.left_truncated     = 0,
  group.SMALL.right_censored     = 0,
  group.SMALL.capped_at_restricted_stay_cap    = 0,
  group.SMALL.duration_days        = 31,
  group.SMALL.mean_days_at_risk  = 2,
  group.SMALL.total_animal_days  = 6,
  group.SMALL.mean_census_inventory        = 6 / 31,
  group.SMALL.total_in_care_days_sum        = 4,
  group.SMALL.daily_mean_total_in_care_days = 4 / 31,
  group.SMALL.total_intakes      = 3,
  group.SMALL.total_outcomes     = 3,
  group.SMALL.mean_daily_intakes = 3 / 31,

  group.LARGE.total_observations = 5,
  group.LARGE.events             = 5,
  group.LARGE.left_truncated     = 0,
  group.LARGE.right_censored     = 0,
  group.LARGE.mean_days_at_risk  = 6,
  group.LARGE.total_animal_days  = 30,
  group.LARGE.mean_census_inventory        = 30 / 31,
  group.LARGE.total_in_care_days_sum        = 80,
  group.LARGE.daily_mean_total_in_care_days = 80 / 31,
  group.LARGE.total_intakes      = 5,
  group.LARGE.total_outcomes     = 5,

  `group._UNKNOWN_.total_observations` = 2,
  `group._UNKNOWN_.events`             = 2,
  `group._UNKNOWN_.left_truncated`     = 0,
  `group._UNKNOWN_.right_censored`     = 0,
  `group._UNKNOWN_.mean_days_at_risk`  = 9.5,
  `group._UNKNOWN_.total_animal_days`  = 19,
  `group._UNKNOWN_.mean_census_inventory`        = 19 / 31,
  `group._UNKNOWN_.total_in_care_days_sum`        = 81,
  `group._UNKNOWN_.daily_mean_total_in_care_days` = 81 / 31,
  `group._UNKNOWN_.total_intakes`      = 2,
  `group._UNKNOWN_.mean_daily_outcomes` = 2 / 31,

  # Unified-across-periods stay counts (calculate_unified_stay_counts).
  # One period, one stay per animal, no truncation or censoring anywhere,
  # so each group's total_stays equals its row count and both unified
  # truncation/censoring counts are zero -- which is exactly the pin: with
  # nothing to unify, the stay-level counts must collapse to the row-level
  # ones above.
  group.SMALL.total_stays          = 3,
  group.SMALL.left_truncated_stays = 0,
  group.SMALL.right_censored_stays = 0,
  group.LARGE.total_stays          = 5,
  group.LARGE.left_truncated_stays = 0,
  group.LARGE.right_censored_stays = 0,
  `group._UNKNOWN_.total_stays`          = 2,
  `group._UNKNOWN_.left_truncated_stays` = 0,
  `group._UNKNOWN_.right_censored_stays` = 0,

  # No intake_type column in this fixture: no intake.* entries may exist.
  intake.STRAY.total_observations = NA
)

# SMALL (days 1-3), LARGE (days 4-8), and _UNKNOWN_ (days 9-10) never
# overlap, so animal_group is genuine complete separation for Cox -- both
# coefficients diverge. With animal_group_reference: SMALL (see
# settings.yaml), each divergence direction is HR -> 0 (verified directly:
# both well under the 1e-6 tolerance, with no Inf/overflow), not
# HR -> +Inf as it would be with a slower reference. The filled
# _UNKNOWN_ level appears in the model as an ordinary factor level with
# its own coefficient.
expected_cox <- list(
  has_analysis             = 1,
  n                        = 10,
  n_events                 = 10,
  HR_animal_groupLARGE     = 0,
  HR_animal_group_UNKNOWN_ = 0,
  # The reference level appears as a definitional row: HR exactly 1.
  HR_animal_groupSMALL     = 1
)
