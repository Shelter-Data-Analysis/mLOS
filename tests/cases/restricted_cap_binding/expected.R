# Expected results for restricted_cap_binding.
# Hand-derived (see settings.yaml comment): 4 events at day 5, one stay
# capped and censored at the 20-day cap, and one left-truncated row
# (time_start = 31 >= capped time_end = 20) dropped as invalid.

expected_km <- list(
  n_total         = 5,    # 6 animals minus the dropped invalid-interval row
  n_events        = 4,
  n_censored      = 1,    # animal 5, censored at the cap
  n_capped        = 1,    # animal 5 only; animal 6 never reaches period_data
  fraction_capped = 0.2,  # 1 / 5
  median_los      = 5,
  percentile_90   = NA,   # S(t) holds at 0.2, never reaches 0.10
  restricted_mean = 8,    # 5*1.0 + 15*0.2
  max_time        = 20
)

# Single period, no intake_type/animal_group columns -> no Cox predictor.
expected_cox <- list(
  has_analysis = 0
)

# Single cause: cif_L = 1 - S(t) up to the censoring, jumping to 0.8 at
# day 5 and holding through the cap. condrem_L (P(resolve L by tau=20 |
# still in care at day x)) is 0.8 at day 0 and 0 at day 5: the 0.2 still
# at risk after day 5 never resolves within the horizon.
expected_aj <- list(
  has_analysis     = 1,
  max_time         = 20,
  n_outcome_states = 1,

  cif_L_day0     = 0,
  cif_L_day4     = 0,
  cif_L_day5     = 0.8,
  cif_Any_day5   = 0.8,
  cif_L_day20    = 0.8,

  condrem_L_day0 = 0.8,
  condrem_L_day5 = 0
)
