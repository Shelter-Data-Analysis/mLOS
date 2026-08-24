# Expected results for in_care_days_boundary_neutrality.
# Same data as boundary_conventions with the interior boundary removed;
# each value below must equal the sum of that fixture's two per-period
# values (see settings.yaml for the derivation). Only the shared
# per-period metric functions are checked here.

expected_period_stats <- list(
  Period_1.duration_days                   = 31,
  Period_1.total_observations            = 5,
  Period_1.events                        = 5,
  Period_1.censored                      = 0,
  Period_1.left_truncated                = 0,
  Period_1.capped_at_restricted_stay_cap               = 0,
  Period_1.total_animal_days             = 23,      # = 12 + 11 in boundary_conventions
  Period_1.mean_census_inventory                   = 23 / 31,
  Period_1.total_in_care_days_sum        = 52,      # = 20 + 32 in boundary_conventions
  Period_1.daily_mean_total_in_care_days = 52 / 31,
  Period_1.total_intakes                 = 5,       # =  4 +  1 in boundary_conventions
  Period_1.total_outcomes                = 5
)
