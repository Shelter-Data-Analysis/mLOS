# sim_intake_mix_shift — Simpson's paradox: "did we get slower, or did our intake change?"

At the period 1→2 boundary of this fixture, two things change at once:

1. **Every dog in care gets 50% faster.** The within-day outcome rate
   improves ×1.5, for both sizes and for every animal already in care.
2. **The intake mix flips**, SMALL/LARGE from 70/30 to 30/70. Total
   intake stays 10 dogs a day: the shelter's volume never changes, only
   who walks through the door.

Because large dogs stay far longer, the two changes fight, and the
crude view loses:

| View | Period 1 | Period 3 | Reads as |
|---|---|---|---|
| Crude pooled KM median | 8 days | **10 days** | got slower |
| Census | 155.7 | **173.3** | got fuller |
| Cox HR, adjusted for size | — | **1.5** | every dog 50% faster |

Both are correct statements about the same data. That is Simpson's
paradox in a shelter, and it is precisely the question the period
analysis exists to answer: *did we get slower, or did our intake
change?*

A note on the sign convention, because it is easy to misread: a hazard
ratio **above** 1 means dogs leave **faster**, i.e. shorter stays — the
good direction. The crude medians moving the other way is the paradox,
not a bookkeeping error.

## Why the truth is exactly known

Both sizes' rates scale by the same 1.5, so the hazard ratio *between*
the sizes is unchanged by the boundary. There is no period-by-size
interaction, which means the Cox model with `period + animal_group` is
correctly specified and **all three of its true coefficients are known
in closed form**:

- `HR_periodPeriod_2` = `HR_periodPeriod_3` = 1.5 (the same truth
  checked twice, as in `sim_geometric_period_effect`)
- `HR_animal_groupLARGE` = ln(0.97)/ln(0.88) = 0.238273 — the same truth
  `sim_size_mixture` pins, here recovered from an independent sample
  *while the mix is moving underneath it*

This is the first sim case to fit two predictors jointly, which is
exactly the adjusted-vs-crude capability it teaches.

## The three periods

- **Period 1** — the old steady state. Its pooled truths (median 8,
  restricted mean 15.5747) are the same ones `sim_size_mixture` pins,
  reproduced here from an independent sample.
- **Period 2** — the **transition**. The standing population is working
  off its old composition, so period 2's pooled median, restricted mean,
  and census have no clean closed form and are deliberately unchecked
  (only its counts are pinned). The committed sample happens to show
  median 9, sitting neatly between the two steady states, but that is a
  coincidence of this draw, not a truth: across the authoring scan the
  period-2 median ranged over 8..12.
- **Period 3** — the new steady state, ~98.4% relaxed by its start
  (4.11 time constants of the new LARGE rate past the boundary). The
  residual shows up as the period-3 census running ~3.3 low against the
  fully-settled truth, well inside its tolerance.

## Two details worth noticing

1. **The population accumulates, so outflow dips below inflow.** During
   period 2 the shelter gains ~24 animals, so outcomes run ~0.25/day
   below intakes. That is the mirror image of
   `sim_geometric_period_effect`, where the population was *draining*
   and outflow temporarily *exceeded* inflow. Here the deficit is far
   inside sampling noise (~4 SD = 0.9/day), so it is described rather
   than pinned.
2. **The group-stratified KM is itself a pooling trap.** `km_group`
   stratifies by size but pools *both regimes*, so each size's curve is
   a pre/post hazard mixture with no clean closed form — the same
   mistake the case is about, one level down. Only its counts are
   pinned. The census composition tells the story a third way: LARGE
   dogs are 63% of the period-1 census from 30% of intakes, and 90% of
   the period-3 census from 70% of intakes.

## The model

Poisson intakes from 2023-09-01 (7/day SMALL + 3/day LARGE before the
boundary, 3/day + 7/day after), about seven time constants of the slow
group before the first period, so observation opens at steady state
with organically left-truncated residents. Daily outcome probabilities:
SMALL 0.12 → 0.174487, LARGE 0.03 → 0.044661 (each Q raised to the 1.5
power). Stays are geometric within size and period, exact at whole days;
the boundary uses the same two-geometric-draw construction as
`sim_geometric_period_effect`, and memorylessness is what makes "the
rate changes for everyone in care" well defined. Outcome codes L/T/N sit
at fixed 0.7/0.2/0.1 shares — the cause dimension stays inert here (see
`sim_cause_rate_shift`). Dogs still in care on 2025-02-01 are
right-censored.

`generator.R` reproduces `data.csv` byte-for-byte (fixed seed,
R >= 3.6); the full derivation of every expected value is in
`settings.yaml`.

## What to look at

- `expected.R` — the crude medians (8 → 10) and the adjusted HRs (1.5,
  twice) sitting in the same file, which is the whole lesson in one
  screen.
- Run `Rscript tests/run_tests.R --prefix sim` for the simulation cases;
  add `--generate-outputs` and open `tests/results/sim_intake_mix_shift/`
  for the plots. The by-period KM overlay is the payoff: the curves
  drift *the wrong way* while the Cox table on the same data reports a
  50% improvement.
- Plots are windowed to 45 days (`plot_stay_cap`); the analyses run to
  the 120-day cap.
