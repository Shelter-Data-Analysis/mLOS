# Expected results for custom_period_labels.
# Identical numbers to boundary_conventions (same data, periods, cap; see
# that fixture's settings.yaml for the full hand derivation). What this
# fixture pins is the *keys*: with period_labels set, every per-period
# result must be keyed by the custom labels ("Old policy", "New policy" --
# spaces included), and no Period_1/Period_2 keys may appear anywhere.

expected_km <- list(
  n_total         = 7,
  n_events        = 5,
  n_censored      = 2,
  n_capped        = 0,
  median_los      = 5,
  percentile_90   = 7,
  restricted_mean = 4.6,
  max_time        = 7
)

# stratum names come from period_label, so the custom labels must show up
# verbatim (after .strip_stratum_prefix removes the "period_label=" prefix).
# The NA entries assert the default labels are NOT also present.
expected_stratified_km <- list(
  n_strata_gaps = 0
)
expected_stratified_km[["period.Old policy.n"]]      <- 4
expected_stratified_km[["period.Old policy.events"]] <- 2
expected_stratified_km[["period.Old policy.median"]] <- 5
expected_stratified_km[["period.New policy.n"]]      <- 3
expected_stratified_km[["period.New policy.events"]] <- 3
expected_stratified_km[["period.New policy.median"]] <- 5
expected_stratified_km[["period.Period_1.n"]]        <- NA
expected_stratified_km[["period.Period_2.n"]]        <- NA

# Period strata must come out in CHRONOLOGICAL order (the KM output order the
# plot legend and CSV columns use), not alphabetical. Here that distinction
# bites: "New policy" sorts before "Old policy" alphabetically, but "Old
# policy" is period 1 and must appear first. .pos is the 1-based KM output
# position; pinning it guards against survfit's alphabetical default sneaking
# back in (see break_down_by_period, which makes period_label a chronological
# factor).
expected_stratified_km[["period.Old policy.pos"]]    <- 1
expected_stratified_km[["period.New policy.pos"]]    <- 2

# Cox regresses on period_num, not the label, so relabeling must leave the
# fit untouched.
expected_cox <- list(
  has_analysis = 1,
  n            = 7,
  n_events     = 5
)

# By-period AJ: per_period is keyed by period_label. Single outcome type,
# so cif_L = 1 - per-period KM survival (see settings.yaml).
expected_aj_period <- list(
  has_analysis = 1,
  n_periods    = 2
)
expected_aj_period[["Old policy.cif_L_day0"]]   <- 0
expected_aj_period[["Old policy.cif_L_day1"]]   <- 1 / 4
expected_aj_period[["Old policy.cif_L_day5"]]   <- 5 / 8
expected_aj_period[["Old policy.cif_Any_day5"]] <- 5 / 8
expected_aj_period[["Old policy.cif_L_day6"]]   <- NA  # grid ends at day 5,
                                                       # Old policy's own
                                                       # largest fitted time
expected_aj_period[["New policy.cif_L_day4"]]   <- 1 / 2
expected_aj_period[["New policy.cif_L_day6"]]   <- 3 / 4
expected_aj_period[["New policy.cif_L_day7"]]   <- 1
expected_aj_period[["New policy.cif_Any_day7"]] <- 1
expected_aj_period[["Period_1.cif_L_day5"]]     <- NA  # default label must not appear

# Per-period counts/census/flow metrics, keyed by the custom labels.
# Values match boundary_conventions Period_1/Period_2 one for one.
expected_period_stats <- list()
expected_period_stats[["Old policy.duration_days"]]                   <- 14
expected_period_stats[["Old policy.total_observations"]]            <- 4
expected_period_stats[["Old policy.events"]]                        <- 2
expected_period_stats[["Old policy.censored"]]                      <- 2
expected_period_stats[["Old policy.left_truncated"]]                <- 0
expected_period_stats[["Old policy.right_censored"]]                <- 2
expected_period_stats[["Old policy.capped_at_restricted_stay_cap"]]               <- 0
expected_period_stats[["Old policy.mean_days_at_risk"]]             <- 3
expected_period_stats[["Old policy.total_animal_days"]]             <- 12
expected_period_stats[["Old policy.mean_census_inventory"]]                   <- 12 / 14
expected_period_stats[["Old policy.total_in_care_days_sum"]]        <- 20
expected_period_stats[["Old policy.daily_mean_total_in_care_days"]] <- 20 / 14
expected_period_stats[["Old policy.total_intakes"]]                 <- 4
expected_period_stats[["Old policy.total_outcomes"]]                <- 2
expected_period_stats[["Old policy.mean_daily_intakes"]]            <- 4 / 14
expected_period_stats[["Old policy.mean_daily_outcomes"]]           <- 2 / 14

expected_period_stats[["New policy.duration_days"]]                   <- 17
expected_period_stats[["New policy.total_observations"]]            <- 3
expected_period_stats[["New policy.events"]]                        <- 3
expected_period_stats[["New policy.censored"]]                      <- 0
expected_period_stats[["New policy.left_truncated"]]                <- 2
expected_period_stats[["New policy.right_censored"]]                <- 0
expected_period_stats[["New policy.capped_at_restricted_stay_cap"]]               <- 0
expected_period_stats[["New policy.mean_days_at_risk"]]             <- 11 / 3
expected_period_stats[["New policy.total_animal_days"]]             <- 11
expected_period_stats[["New policy.mean_census_inventory"]]                   <- 11 / 17
expected_period_stats[["New policy.total_in_care_days_sum"]]        <- 32
expected_period_stats[["New policy.daily_mean_total_in_care_days"]] <- 32 / 17
expected_period_stats[["New policy.total_intakes"]]                 <- 1
expected_period_stats[["New policy.total_outcomes"]]                <- 3
expected_period_stats[["New policy.mean_daily_intakes"]]            <- 1 / 17
expected_period_stats[["New policy.mean_daily_outcomes"]]           <- 3 / 17
