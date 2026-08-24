# Expected results for max_plot_strata_off.
#
# max_plot_strata is a plot-only setting, so the point of this case is not
# in the numbers here: it is in the golden png_manifest.txt (no stratified
# PNGs) sitting next to the golden CSVs (all still written). Those are
# checked by --generate-outputs; see settings.yaml for the reasoning.
#
# The numbers are still worth asserting, because the one thing that would
# make the setting dangerous is if it quietly changed an ANALYSIS rather
# than only its rendering. These are the same values as
# stratified_km_animal_group, whose data this reuses, and they must stay
# identical with the limit set to 1.

expected_km <- list(
  n_total         = 8,
  n_events        = 8,
  n_censored      = 0,
  median_los      = 4.5,
  restricted_mean = 4.5,
  max_time        = 8
)

# Unchanged by the plot limit: the KM fits still run on every stratum.
expected_stratified_km <- list(
  group.SMALL.n      = 3,
  group.SMALL.median = 2,
  group.LARGE.n      = 5,
  group.LARGE.median = 6
)

# Unchanged by the plot limit: AJ still fits every stratum, and its CIFs
# are the ones hand-derived in stratified_km_animal_group's expected.R.
expected_aj_group <- list(
  has_analysis      = 1,
  n_animal_groups   = 2,
  SMALL.cif_L_day1  = 1 / 3,
  SMALL.cif_L_day3  = 1,
  LARGE.cif_L_day4  = 0.2,
  LARGE.cif_L_day8  = 1
)
