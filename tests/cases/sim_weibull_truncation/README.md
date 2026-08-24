# sim_weibull_truncation — a simulation case with known truth

This fixture is a worked example as much as a test: `data.csv` is a
randomized sample from a **fully known model**, so you can see what every
mLOS analysis reports when the data really does follow a predetermined
form — and how close the estimates land to the truth.

## The model

- Two intake types with equal, Poisson-distributed daily intakes:
  **STRAY** stays follow a Weibull distribution with shape 1.3 and scale
  10 days; **OWNER** stays the same shape with scale 20 days. Owner
  surrenders therefore stay twice as long (LOS ratio 2), with a true
  hazard ratio of 2^(-1.3) = 0.406.
- A drawn duration W becomes a recorded LOS of floor(W) + 1 calendar
  days. This is the familiar mLOS counting rule: the arrival and
  departure days both count, so an animal that comes and goes the same
  day (any W below 1) has LOS = 1, a W between 1 and 2 spans two days,
  and so on. One consequence, documented in `settings.yaml`, is that the
  parametric Weibull fit sees stays rounded up by about half a day on
  average, so its fitted shape and LOS ratio sit slightly off the
  generating values; the expected-value tolerances account for this.
- Outcome codes L/T/N are assigned with probabilities 0.7/0.2/0.1,
  independent of the stay length.
- Intakes begin 2024-01-01, but the study window in `settings.yaml` is
  2024-03-01 to 2024-09-01. Nothing is hand-built: animals already in
  care on March 1 enter **left-truncated**, animals that left before
  March 1 are filtered out, and animals still in care on September 1
  (the export date) are **right-censored**.

`generator.R` is the committed script that produced `data.csv` (fixed
seed, reproducible on R >= 3.6). Change the seed and rerun it to draw a
fresh sample with the same properties.

## What to look at

- `expected.R` — the generating truth (median 11 days, hazard ratio
  0.406, Weibull shape 1.3, LOS ratio 2, ...) with tolerances of about
  4 standard errors, plus the documented day-rounding bias of the
  parametric fit. The full derivation is in `settings.yaml`.
- Run `Rscript tests/run_tests.R --prefix sim` from the project root to
  execute just the simulation cases.
- Run `Rscript tests/run_tests.R --generate-outputs` and open
  `tests/results/sim_weibull_truncation/` for the complete set of plots,
  CSVs, and the Excel workbook this sample produces. The committed CSVs
  under `tests/golden/sim_weibull_truncation/` show the same numbers
  without running anything.
- The plots are windowed to the first 35 days (`plot_stay_cap: 35` in
  `settings.yaml`), where the action is: the pooled curve is down to
  about 7% still in care by day 35. The analyses and the exported CSVs
  still run to the 90-day `restricted_stay_cap`; the plot cap crops the
  picture, never the data.
