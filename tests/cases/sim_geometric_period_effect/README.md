# sim_geometric_period_effect — a true period effect, and why the census lags it

This fixture simulates the situation the period analysis exists for: on a
known date, the rate at which animals in care have outcomes **doubles** —
for every animal in care, including residents admitted earlier. Its
central lesson is the contrast between two ways of seeing that change:

- The **Cox period hazard ratio** sees it immediately. Periods 2 and 3
  get the *same* true hazard ratio (exactly 2 vs period 1), because the
  rate shift sits exactly on the period 1→2 boundary.
- The **census** — the number most shelters actually watch — lags.
  Period 1 sits at its steady state (~83 animals), period 3 at the new
  one (~43), but period 2 inherits period 1's population and spends
  weeks working it off. Little's law (mean census = daily intakes ×
  mean LOS) holds in periods 1 and 3 and **fails in period 2**, which
  is why period 2's census is deliberately not checked. Meanwhile
  period 2's outflow temporarily *exceeds* its inflow (~5.44 vs 5 per
  day) as the excess ~40 animals leave.

## The model

- **What "the rate doubles" means.** Following the outcome-window model
  of Mavrovouniotis, *Animals* 2026, 16(8):1158, Section 2.5: outcomes
  occur at a constant rate λ within a window of duration T each day,
  while the stay itself is counted in whole days (arrival and departure
  days both count, so a same-day intake and outcome is LOS = 1). The
  daily probability of *no* outcome is then Q = e^(−λT), and LOS is
  geometric. Doubling λ **squares** Q: before the boundary Q = 0.94
  (daily outcome probability 0.06), after it Q = 0.94² = 0.8836
  (probability 0.1164). This is exactly the whole-day (grouped) form of
  proportional hazards, so the Cox hazard ratio — fitted with the Efron
  tie handling, see the math document Section 6.2 — has true value
  exactly 2: the within-day rate ratio.
- **A neat consequence**: squaring Q compresses the survival curve
  two-fold in time, S₂(m) = S₁(2m). Period 2/3's day-6 values equal
  period 1's day-12 values exactly — median 6 vs 12 days, and identical
  AJ cumulative incidences (0.52408) at those days.
- **Memorylessness is what makes the shift clean**: the chance of an
  outcome today never depends on time already served, so the boundary
  changes every resident's prospects without re-drawing anyone's
  remaining stay.
- Study periods: three calendar quarters starting 2024-04-01. Intakes
  (Poisson, 5/day) begin 2023-12-01 — a notional **period 0** in which
  the population builds from an empty shelter to steady state before
  observation starts, and which supplies the left-truncated residents
  observed from day one of period 1. Truncation then recurs at every
  boundary: each period inherits the previous one's residents.
- Outcome codes L/T/N are assigned 0.7/0.2/0.1, independent of stay
  length, so each cause's CIF is that fixed share of the all-cause CIF.

`generator.R` reproduces `data.csv` byte-for-byte (fixed seed, R >= 3.6);
the full derivation of every expected value is in `settings.yaml`.

## What to look at

- `expected.R` — per-period KM medians (12/6/6 days) and restricted
  means (= mean LOS = 1/q), the twin Cox hazard ratios checked against
  exactly 2, Little's law in periods 1 and 3, the period-2 outflow
  surplus, and per-period AJ fractions exhibiting the two-fold
  compression.
- The run also demonstrates mLOS's **observation-gap warning** on
  organic data: in the fast-discharge periods, hardly anyone reaches
  extreme tenures, so past tenure ~67 (period 2) and ~43 (period 3) the
  risk set is a single inherited long-term resident, with empty
  stretches before its exit. The flagged gaps sit where survival is
  already below 0.001, so none of the checked statistics are affected —
  but it is exactly the situation the warning exists for.
- Run `Rscript tests/run_tests.R --prefix sim` for just the simulation
  cases; add `--generate-outputs` and open
  `tests/results/sim_geometric_period_effect/` for the plots — the
  by-period KM overlay and the by-period AJ lines show the period 1
  curve clearly separated from the (statistically identical) period 2
  and 3 curves. Plots are windowed to 30 days (`plot_stay_cap`); the
  analyses run to the 120-day cap, chosen high enough that capping
  never distorts the census or the restricted means.
