# Expected results for raw_label_cleanup.
# Hand-derived (see settings.yaml comment): of 9 CSV rows, one is deleted
# by outcome_type_delete, two are dropped by the study-window filter, one
# is recoded to in-care-but-censored-at-departure by outcome_type_in_care,
# and the rest map from raw labels to L/T/N.

expected_km <- list(
  n_total         = 6,        # 9 rows - 1 deleted - 2 outside the window
  n_events        = 4,        # 2 L + 1 T + 1 N
  n_censored      = 2,        # Foster recode (day 8) + still-in-care (day 31)
  n_capped        = 0,        # longest time_end is 31 < cap 40
  median_los      = 10,
  percentile_90   = NA,       # S holds at 2/9, never reaches 0.10
  restricted_mean = 145 / 9,  # 16.111..., cap 40, flat extension past day 31
  max_time        = 31
)

# Single period, no intake_type/animal_group columns -> no Cox predictor.
expected_cox <- list(
  has_analysis = 0
)

# Competing-risk CIFs, hand-derived in settings.yaml. The day-0 CondRem
# values are the final CIFs (everyone still at risk) and sum to 7/9 < 1
# because the still-in-care animal is unresolved at tau = 31.
expected_aj <- list(
  has_analysis     = 1,
  max_time         = 31,
  n_outcome_states = 3,

  cif_L_day0     = 0,
  cif_L_day5     = 1 / 3,
  cif_T_day5     = 0,
  cif_N_day5     = 0,
  cif_Any_day5   = 1 / 3,

  cif_T_day10    = 2 / 9,
  cif_Any_day10  = 5 / 9,

  cif_N_day15    = 2 / 9,
  cif_Any_day15  = 7 / 9,

  cif_L_day31    = 1 / 3,
  cif_T_day31    = 2 / 9,
  cif_N_day31    = 2 / 9,

  condrem_L_day0  = 1 / 3,
  condrem_T_day0  = 2 / 9,
  condrem_N_day0  = 2 / 9,
  condrem_L_day15 = 0    # everything that will resolve already has
)
