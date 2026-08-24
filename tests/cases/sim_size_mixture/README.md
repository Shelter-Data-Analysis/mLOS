# sim_size_mixture — the declining-hazard illusion (heterogeneity, not memory)

This fixture holds a shelter where **nothing ever changes and nobody's
prospects depend on how long they've stayed**: 70% SMALL dogs leaving at
a constant 12% per day (mean stay 8.3 days), 30% LARGE dogs at a
constant 3% per day (mean stay 33.3 days). Every dog is memoryless.
And yet the pooled analyses "show" that dogs get harder to move the
longer they stay.

That is the classic frailty (unobserved heterogeneity) artifact of the
survival literature, in its simplest possible form: the fast-leaving
small dogs drain out of the risk set first, so the surviving population
is increasingly made of long-stayers, and the *pooled* hazard declines
with tenure even though no *individual* hazard does.

## The illusion, quantified (the blind view)

A memoryless process must obey fixed ratios between its summaries:
mean ≈ 1.44 × median, 90th percentile ≈ 3.32 × median. The pooled
mixture breaks both, and `expected_km` pins the numbers:

| Pooled statistic | Value | Memoryless benchmark |
|---|---|---|
| median | 8 days | — |
| mean (restricted, cap 120) | 15.57 | ~11.5 (1.44 × median) |
| 90th percentile | 38 days | ~27 (3.32 × median) |

The fitted Weibull says it directly: **without** the size term the shape
comes out ≈ 0.87 (a "declining hazard"; authoring scan mean 0.869, this
sample 0.886). mLOS reports exactly this fit as the **unified Weibull**
(intercept + period only) at the bottom of the Weibull worksheet, next
to the adjusted fit — and `expected.R` pins its shape at the 0.87
pseudo-truth (`shape_unified`), so the illusion is checked by the
suite, not just described.

## The resolution (the sighted view, same data)

Record size, and the artifact dissolves — all pinned in `expected.R`:

- Stratified KM: each size is flat-geometric (SMALL median 6, rmean
  8.33; LARGE median 23, rmean 32.47).
- Cox with the size term: LARGE hazard ratio at its grouped-hazards
  truth ln(0.97)/ln(0.88) = 0.238.
- Weibull **with** the size term: shape ≈ 1.12, i.e. constant hazard up
  to the documented whole-day discretization bias; LOS ratio 4.

The practical lesson is an action, not a caveat: **record size and
stratify by it.** The unified KM here is not wrong — it correctly
describes the shelter's aggregate flow — but reading tenure-dependence
into it is.

## Two more things this fixture pins

1. **A true null.** The two study periods are identical by
   construction, so the Cox period hazard ratio must be exactly 1 and
   both periods' KM statistics equal the same mixture truths. No other
   sim case checks that the machinery reports *no effect* when there
   is none.
2. **The census composition fact.** Although LARGE dogs are 30% of
   intakes, at steady state they are **63% of the resident population**
   (census share = intake share ÷ departure rate, normalized). The
   per-period census is pinned at its capped Little's law value
   (10/day × E[min(LOS, 120)] = 155.7); the LARGE tail past the
   120-day cap also makes this the first sim where `n_capped` is
   materially nonzero (13 stays).

## The model

Poisson intakes (7/day SMALL, 3/day LARGE) from 2023-09-01, about seven
time constants of the slow group before the first period (2024-05-01),
so observation opens at steady state with organically left-truncated
residents. Two quarterly periods; animals still in care on 2024-11-01
are right-censored. Stays are geometric per size (whole-day counting,
no rounding bias in the KM/Cox layer); outcome codes L/T/N at fixed
0.7/0.2/0.1 shares — the cause dimension deliberately stays inert (see
sim_cause_rate_shift for that story).

`generator.R` reproduces `data.csv` byte-for-byte (fixed seed,
R >= 3.6); the full derivation of every expected value is in
`settings.yaml`.

## What to look at

- `expected.R` — the pooled ratio violations, the null period HR, the
  stratified geometric truths, the adjusted Weibull shape, and the
  capped Little's law census.
- Run `Rscript tests/run_tests.R --prefix sim` for the simulation
  cases; add `--generate-outputs` and open
  `tests/results/sim_size_mixture/` for the plots. The by-group KM
  overlay is the payoff: two clean exponential-looking curves far
  apart, while the unified KM curve bends — steep early (small dogs
  leaving), shallow late (large dogs remaining).
- Plots are windowed to 60 days (`plot_stay_cap`), wide enough to show
  the LARGE median at day 23; the analyses run to the 120-day cap.
