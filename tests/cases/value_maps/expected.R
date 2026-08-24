# Expected results for value_maps.
#
# The point of this case is that the two optional value maps rewrite
# intake_type and animal_group before anything reads them, so every number
# below is the number the analysis would produce from a file that had been
# written with the mapped labels in the first place. What the pins are
# guarding is therefore mostly WHICH rows ended up in which stratum, plus the
# absence assertions: no raw label may survive anywhere as a level, a stratum,
# or a Cox row.
#
# The register records what each map did, including the two keys that occur
# nowhere in the data (GIANT, SEIZED). Their zero counts are the contract: a
# configured map reports EVERY pair, so a key that matched nothing is present
# with a count of 0 rather than silently missing, which is the only signal a
# user gets that a key is misspelled (nothing else checks a map against the
# data, by design -- see the User Guide, Value maps). n_pairs pins that no
# pair is dropped from the report.
expected_preparation <- list(
  rows_read       = 10,
  rows_prepared   = 10,
  recoded_in_care = 0,

  # animal_size: TOY on 3 rows, XL on 3, GIANT on none.
  mapped_animal_group.n_pairs = 3,
  mapped_animal_group.XL      = 3,
  mapped_animal_group.TOY     = 3,
  mapped_animal_group.GIANT   = 0,

  # Two spellings merge into one target. "OWNER SUR" is a strict prefix of
  # "OWNER SURRENDER", so these two counts coming out 3 and 3 (rather than
  # 6 and 0) is what pins whole-value matching.
  mapped_intake_type.n_pairs             = 3,
  `mapped_intake_type.OWNER SUR`         = 3,
  `mapped_intake_type.OWNER SURRENDER`   = 3,
  mapped_intake_type.SEIZED              = 0
)

# Unified/pooled curve, unaffected by the maps (they move rows between strata,
# never in or out of the sample): 10 distinct LOS values with no censoring, so
# survival right after the k-th smallest event = (10-k)/10, over event days
# 1..10. S(5) = 0.5 and S(9) = 0.1 are exact threshold ties, each reported as
# the midpoint of the touching step (the rule pinned in
# aj_competing_risks_mixed), giving median 5.5 and percentile_90 9.5. The
# restricted mean is the area under S(t), (10+9+...+1)/10 = 5.5.
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

# The strata AFTER mapping, each with distinct event days and no censoring, so
# survival right after its own k-th smallest event is (n-k)/n and (nothing
# being censored) its restricted mean is the plain mean of its event days.
#
#   SML (n=5): days 1,3,5,7,9    -> S = .8,.6,.4,.2,0; S(3)=.6 > .5 and
#     S(5)=.4 <= .5, so median 5, with no tie. rmean = 25/5 = 5.
#   LRG (n=5): days 2,4,6,8,10   -> median 6 by the same reading. rmean = 6.
#   STRAY (n=4): days 1,4,5,9    -> S = .75,.5,.25,0; S(4) = 0.5 EXACTLY, so
#     the median is the midpoint of that step, (4+5)/2 = 4.5. rmean = 19/4.
#   SURRENDER (n=6): days 2,3,6,7,8,10 -> S(6) = 0.5 exactly likewise, so
#     median (6+7)/2 = 6.5. rmean = 36/6 = 6.
#
# The four strata are what the maps produced: SML and LRG each drew 3 of their
# 5 rows through a map (TOY and XL), and every SURRENDER row came through one
# of the two intake spellings. Getting a single row's mapping wrong would move
# the medians and the means, which is what makes these the pins.
#
# .pos pins output order (legend and CSV column order), which is alphabetical
# per stratifier: LRG before SML, STRAY before SURRENDER. Note the maps do not
# get a say in it -- the order follows the mapped labels, not the raw ones,
# which under the raw spelling would have run TOY before XL.
expected_stratified_km <- list(
  group.SML.n      = 5,
  group.SML.events = 5,
  group.SML.median = 5,
  group.SML.rmean  = 5,
  group.LRG.n      = 5,
  group.LRG.events = 5,
  group.LRG.median = 6,
  group.LRG.rmean  = 6,
  group.LRG.pos    = 1,
  group.SML.pos    = 2,

  intake.STRAY.n          = 4,
  intake.STRAY.events     = 4,
  intake.STRAY.median     = 4.5,
  intake.STRAY.rmean      = 4.75,
  intake.SURRENDER.n      = 6,
  intake.SURRENDER.events = 6,
  intake.SURRENDER.median = 6.5,
  intake.SURRENDER.rmean  = 6,
  intake.STRAY.pos        = 1,
  intake.SURRENDER.pos    = 2,

  # No raw label may survive as a stratum. This is the difference between a
  # map and a filter: a filter empties a level but keeps it (see
  # value_filters), a map leaves nothing behind at all.
  group.XL.n           = NA,
  group.TOY.n          = NA,
  group.GIANT.n        = NA,
  `intake.OWNER SUR.n` = NA,
  intake.SEIZED.n      = NA
)

# Per-stratum observation/census/flow stats, as the Excel By_* sheets compute
# them. One period of 31 days with every intake and outcome inside it and no
# truncation, censoring, or capping, so days_at_risk per row is just its event
# day and the totals are the day sums of each stratum listed above: SML 25,
# LRG 30, STRAY 19, SURRENDER 36 (the last two summing to 55, as do the first
# two -- the same ten stays cut two ways).
expected_stratum_stats <- list(
  group.SML.total_observations = 5,
  group.SML.events             = 5,
  group.SML.right_censored     = 0,
  group.SML.mean_days_at_risk  = 5,
  group.SML.total_animal_days  = 25,
  group.SML.total_intakes      = 5,
  group.LRG.total_observations = 5,
  group.LRG.mean_days_at_risk  = 6,
  group.LRG.total_animal_days  = 30,

  intake.STRAY.total_observations     = 4,
  intake.STRAY.mean_days_at_risk      = 4.75,
  intake.STRAY.total_animal_days      = 19,
  intake.SURRENDER.total_observations = 6,
  intake.SURRENDER.mean_days_at_risk  = 6,
  intake.SURRENDER.total_animal_days  = 36,

  # Absence again, on the stats path this time.
  group.XL.total_observations           = NA,
  `intake.OWNER SUR.total_observations` = NA
)

# AJ by animal group. Every animal leaves with outcome L and none is censored,
# so L is the only competing state and cif_L = 1 - S(t) exactly, stepping by
# 1/5 at each stratum's own event days (SML at 1,3,5,7,9; LRG at 2,4,6,8,10).
# Read as incidence, this is the same (n-k)/n reasoning as the stratified KM
# above; what it adds here is that the AJ path sees the mapped strata too.
expected_aj_group <- list(
  has_analysis    = 1,
  n_animal_groups = 2,

  SML.cif_L_day0   = 0,
  SML.cif_L_day1   = 0.2,
  SML.cif_L_day3   = 0.4,
  SML.cif_L_day5   = 0.6,
  SML.cif_L_day7   = 0.8,
  SML.cif_L_day9   = 1,
  SML.cif_Any_day9 = 1,

  LRG.cif_L_day2    = 0.2,
  LRG.cif_L_day10   = 1,
  LRG.cif_Any_day10 = 1
)

# Cox on the mapped columns. The two stratifiers cut the sample differently
# and neither is separated from the other (SML/LRG and STRAY/SURRENDER
# interleave across the whole day range), so the fit is well conditioned --
# unlike stratified_km_animal_group, which is deliberately separated.
#
# The hazard-ratio table must have exactly the four rows the mapped levels
# imply. The two reference rows are definitional 1s; the two fitted ratios are
# not hand-derivable and are pinned by the golden cox_hazard_ratios.csv rather
# than asserted here. What IS asserted is that no raw label appears as a Cox
# row: a filtered-out level would leave a phantom row with a blank ratio (see
# value_filters), a mapped-away one leaves nothing.
expected_cox <- list(
  has_analysis          = 1,
  n                     = 10,
  n_events              = 10,
  HR_animal_groupSML    = 1,
  HR_intake_typeSTRAY   = 1,
  HR_animal_groupXL     = NA,
  HR_animal_groupTOY    = NA,
  `HR_intake_typeOWNER SUR` = NA
)
