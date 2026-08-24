# Expected results for value_filters.
#
# The point of this case is that the three optional filters select exactly
# the right rows before any analysis runs. The intake_type (cut TRANSFER),
# animal_group (pass LARGE), and coat (pass black) filters compose in that
# order to leave animals 3, 5, 8 -- community-live stays of length 4, 6, 7.
# These numbers pin that selection; if any filter matched the wrong rows,
# n_total or the median would move. The golden CSVs/PNGs check that the rest
# of the pipeline then runs cleanly on the filtered data.
#
# The golden cox_hazard_ratios.csv deliberately keeps a phantom
# "intake_typeTRANSFER" row with a blank hazard ratio: filtering does not drop
# an emptied factor level, so the Cox layout matches an unfiltered run (see the
# User Guide, Value filters). Do not "fix" that NA row away.

expected_km <- list(
  n_total         = 3,
  n_events        = 3,
  n_censored      = 0,
  median_los      = 6,
  restricted_mean = 5.666667,
  max_time        = 7
)
