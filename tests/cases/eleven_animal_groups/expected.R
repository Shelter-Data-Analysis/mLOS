# Expected results for eleven_animal_groups.
# Hand-derived (see settings.yaml comment): group G<k>'s single animal has
# LOS = k, so every stratum is a one-step curve with median k. 11 strata
# exceeds the 10-strata plot limit, but the analysis must be unaffected.

expected_km <- list(
  n_total         = 11,
  n_events        = 11,
  n_censored      = 0,
  n_capped        = 0,
  median_los      = 6,
  percentile_90   = 10,
  restricted_mean = 6,   # (1 + 2 + ... + 11) / 11, cap 20 never binds
  max_time        = 11
)

# All 11 strata must be fitted even though the plot is skipped: for each
# group G<k>, n = 1, events = 1, median = k.
expected_stratified_km <- local({
  flat <- list()
  for (k in 1:11) {
    g <- sprintf("G%02d", k)
    flat[[paste0("group.", g, ".n")]]      <- 1
    flat[[paste0("group.", g, ".events")]] <- 1
    flat[[paste0("group.", g, ".median")]] <- k
  }
  flat
})

# Cox on animal_group: 11 one-observation levels, heavy separation --
# the fit must complete without crashing; only its shape is asserted.
expected_cox <- list(
  has_analysis = 1,
  n            = 11,
  n_events     = 11
)
