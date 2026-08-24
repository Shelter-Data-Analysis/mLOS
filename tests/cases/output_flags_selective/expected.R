# Expected results for output_flags_selective.
#
# The six output-emission flags are rendering-only settings, so the point of
# this case is not the numbers here: it is in the golden png_manifest.txt and
# the golden CSV set, checked by --generate-outputs, which together prove each
# of PNG/CSV/FALSE/TRUE produces exactly the right file(s). See settings.yaml.
#
# The numbers are asserted anyway, to guarantee the flags only change which
# files are written, never the analysis. These are the same values as
# stratified_km_animal_group / max_plot_strata_off, whose data this reuses.

expected_km <- list(
  n_total         = 8,
  n_events        = 8,
  n_censored      = 0,
  median_los      = 4.5,
  restricted_mean = 4.5,
  max_time        = 8
)

# Unchanged by the emission flags: the KM fits still run on every stratum.
expected_stratified_km <- list(
  group.SMALL.n      = 3,
  group.SMALL.median = 2,
  group.LARGE.n      = 5,
  group.LARGE.median = 6
)

# Unchanged by the emission flags: AJ still fits every stratum.
expected_aj_group <- list(
  has_analysis      = 1,
  n_animal_groups   = 2,
  SMALL.cif_L_day1  = 1 / 3,
  SMALL.cif_L_day3  = 1,
  LARGE.cif_L_day4  = 0.2,
  LARGE.cif_L_day8  = 1
)
