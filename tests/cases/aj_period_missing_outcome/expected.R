# Expected results for aj_period_missing_outcome.
# Hand-derived (see settings.yaml comment). The point of this fixture is
# expected_aj_period: Period_2 has no N outcome (its cif_df has no cif_N
# column -- asserted via NA below, since the flattener only emits
# populated cells and check_fields treats an absent actual as NA), and
# Period_3 has no events at all, so it is skipped and excluded from
# per_period (n_periods = 2, not 3).

expected_km <- list(
  n_total         = 8,    # P1: 3 rows, P2: 3 rows, P3: 2 rows
  n_events        = 5,
  n_censored      = 3,    # animal 6 twice (P2, P3) + animal 7
  n_capped        = 0,
  median_los      = 8,
  percentile_90   = NA,   # S holds at 2/7, never reaches 0.10
  restricted_mean = 156 / 7,  # 22.2857..., cap 60, flat extension
  max_time        = 59,
  gap_detected    = 0     # pooled coverage is continuous; see the
                          # Period_3 stratum gap under expected_stratified_km
)

# 3 periods -> Cox runs with period as the predictor. Period_3 has
# zero events (complete separation for its coefficient), which must not
# crash the fit; only the fit's basic shape is asserted here.
expected_cox <- list(
  has_analysis = 1,
  n            = 8,
  n_events     = 5
)

# Discovered by the per-stratum gap check after this fixture was written:
# within Period_3 (in analysis time, days since each animal's own intake),
# animal 7 is censored at day 27 while animal 6 enters left-truncated at
# day 28 -- nobody is at risk in (27, 28]. The pooled data has no gap
# (gap_detected = 0 above); this one-day hole exists only inside the
# Period_3 stratum, a genuine example of the stratum-only gap case.
expected_stratified_km <- list(
  n_strata_gaps = 1
)
expected_stratified_km[["gap.Period.Period_3.start"]] <- 27
expected_stratified_km[["gap.Period.Period_3.end"]]   <- 28

expected_aj_period <- list(
  has_analysis = 1,
  n_periods    = 2,   # Period_3 skipped: no analyzable outcomes

  # Period_1: L jumps to 2/3 at day 5, N to 1/3 at day 10; cif_Any hits 1
  # at day 10, so CondRem is NA (nobody at risk) from there on.
  Period_1.cif_L_day0      = 0,
  Period_1.cif_L_day5      = 2 / 3,
  Period_1.cif_N_day5      = 0,
  Period_1.cif_Any_day5    = 2 / 3,
  Period_1.cif_L_day10     = 2 / 3,
  Period_1.cif_N_day10     = 1 / 3,
  Period_1.cif_Any_day10   = 1,
  Period_1.cif_L_day11     = NA,   # grid ends at P1's own largest fitted
                                   # time (day 10), not the unified max 59
  Period_1.condrem_L_day0  = 2 / 3,
  Period_1.condrem_N_day0  = 1 / 3,
  Period_1.condrem_L_day5  = 0,
  Period_1.condrem_N_day5  = 1,
  Period_1.condrem_L_day10 = NA,   # at-risk mass is 0 from day 10

  # Period_2: L jumps to 2/3 at day 8; no N outcome ever observed, so the
  # cif_N column does not exist for this period.
  Period_2.cif_L_day0     = 0,
  Period_2.cif_L_day8     = 2 / 3,
  Period_2.cif_Any_day8   = 2 / 3,
  Period_2.cif_L_day28    = 2 / 3, # flat through animal 6's boundary
                                   # censoring at day 28, P2's grid end
  Period_2.cif_L_day29    = NA,    # grid ends at day 28, not the unified 59
  Period_2.cif_N_day8     = NA,    # column absent by design
  Period_2.condrem_L_day0 = 2 / 3,
  Period_2.condrem_L_day8 = 0
)
