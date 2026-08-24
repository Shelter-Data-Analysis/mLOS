# sim_cause_rate_shift — cause-specific rate changes, and why only AJ sees them

This fixture is the mirror image of `sim_geometric_period_effect`. There,
the rate at which animals in care have outcomes doubles at the period
1→2 boundary **uniformly across causes**, and the lesson is which
analyses see the change immediately (Cox, per-period KM/AJ) and which
lag (the census). Here, the **all-cause truth is identical**: the total
rate doubles at the boundary, true Cox HR exactly 2, same per-period
medians (12 → 6) and restricted means. But the doubling is composed of
*divergent cause-specific changes*:

| Cause | Within-day rate at the boundary | CIF plateau (share of outcomes) |
|---|---|---|
| L (live release) | **×3** | 0.6 → 0.9 |
| T (transfer) | **×1/3** | 0.3 → 0.05 |
| N (non-live) | **unchanged** | 0.1 → 0.05 |

The baseline shares 0.6/0.3/0.1 are chosen so the share-weighted
multiplier is 0.6·3 + 0.3/3 + 0.1 = **exactly 2**. KM, Cox, and the
census therefore *cannot distinguish this fixture's world from the
uniform doubling*: every all-cause number they report has the same true
value in both cases. Only the by-period AJ analysis, the cause-level
layer, reveals what actually happened.

## The competing-risks lessons

Each cause has a distinct, instructive fate, all checked in `expected.R`:

1. **N's rate never changed, yet its plateau halves** (0.1 → 0.05). A
   faster competitor (L) claims animals first; a cause-specific rate can
   be perfectly stable while its observed share collapses. The check
   tolerance is sized so the fitted post-shift N share (0.05) is
   cleanly separated from the 0.1 that a naive "N unchanged" reading
   would predict.
2. **T slowed 3-fold, yet its CIF rises to its (6-fold lower) plateau
   twice as fast.** Every cause's CIF has the *all-cause* time scale:
   S₂(m) = S₁(2m), so period 2's day-6 CIFs sit at period 1's day-12
   heights: same CIF_Any (0.52408), different cause split.
3. **The observed stays of a cause say nothing about that cause's
   rate.** Given the regime, stay length and cause are independent, so
   the mean stay of animals leaving by T drops from ~16.7 to ~8.6 days
   across the boundary even though T's own rate *fell* 3-fold. "T
   slowed down" is invisible in the observed T stays; it shows up only
   as T becoming rare.

## The model

Same machinery as `sim_geometric_period_effect` (see that case and
generator.R here): geometric stays via the outcome-window model of
Mavrovouniotis, *Animals* 2026, 16(8):1158, Section 2.5, with the causes
competing as constant rates within each day's window. Daily no-outcome
probability Q = 0.94 before the boundary, 0.94² = 0.8836 from it; an
outcome day's cause follows the regime's rate shares (0.6/0.3/0.1
before, 0.9/0.05/0.05 from the boundary), independent of tenure;
memorylessness makes the boundary clean for residents already in care.
Intakes are Poisson(10)/day from 2023-12-01 (a notional period 0 builds
the population to steady state); the two study periods are the quarters
from 2024-04-01, and animals still in care on 2024-10-01 are
right-censored. The intake rate is double the geometric case's because
the delicate checks are the 0.05 post-shift shares (~1000 events per
period put their SE near 0.007).

`generator.R` reproduces `data.csv` byte-for-byte (fixed seed, R >= 3.6);
the full derivation of every expected value is in `settings.yaml`.

## What to look at

- `expected.R` — the per-period cause table above as AJ CIF/CondRem
  checks at each period's median day, the Cox HR against exactly 2, and
  per-period KM medians/restricted means (identical truth to the
  geometric case, deliberately).
- Run `Rscript tests/run_tests.R --prefix sim` for the simulation cases;
  add `--generate-outputs` and open `tests/results/sim_cause_rate_shift/`
  for the plots. The by-period AJ CIF plots are the payoff: L's curve
  jumps up and steepens, T's collapses, N's halves, while the by-period
  KM overlay is indistinguishable from `sim_geometric_period_effect`'s.
- The run also exercises the observation-gap warning on organic data: in
  the fast period 2, past tenure ~72 the risk set is a single inherited
  long-term resident (survival already ~1e-3), exactly the situation the
  warning exists for.
- Plots are windowed to 30 days (`plot_stay_cap`); the analyses run to
  the 120-day cap, which never binds.
