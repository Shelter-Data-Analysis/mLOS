# Expected results for auto_animal_id.
# Same data and periods as truncation_censoring_split, but with no animal_id
# column in the CSV. read_and_prepare_data auto-generates one id per row, so
# the boundary-straddling animal's two period-split rows stay in one Cox
# cluster and every result must match its explicit-id twin field-for-field.

expected_km <- list(
  n_total         = 6,   # 4 unsplit animals + row 5's 2 period-rows
  n_events        = 5,   # one event per logical animal
  n_censored      = 1,   # row 5's Period_1 (administratively censored) row
  n_capped        = 0,
  median_los      = 10,
  percentile_90   = 10,
  restricted_mean = 10,
  max_time        = 10
)

# Cox runs (2 periods). Period_1 has zero events, so the period
# coefficient is complete-separation: HR is NA, not a crash. Clustering is on
# the auto-generated animal_id; the fit matches truncation_censoring_split.
expected_cox <- list(
  has_analysis      = 1,
  n                 = 6,
  n_events          = 5,
  HR_periodPeriod_2 = NA
)
