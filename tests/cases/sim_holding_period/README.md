# sim_holding_period — in-care tenure and remaining LOS against known truth

This fixture holds a shelter where **no animal leaves during its first 5
days** (a stray hold), after which each animal leaves with a constant 10%
chance per day, however long it has stayed. Intakes are steady at 10 a
day across two identical six-month periods.

The hold gives every tenure-based output two regimes, so each one has a
distinctive closed form to check against:

| Output | Through the hold (x < 5) | After the hold |
|---|---|---|
| KM survival | 1 | 0.9^(x−5) |
| Remaining LOS | 15 − x | 10, flat |
| In-care tenure G(x) | (14 − x)/15 | (2/3)·0.9^(x−4) |

and the summaries follow: restricted mean 15 days, mean tenure of the
animals in care 10 days, 11 days still owed per resident, census 150.

## Why this fixture exists

The suite already checks the tenure outputs for internal consistency:
the in-care tenure column sums to the mean tenure, and remaining LOS at
day 0 equals the restricted mean. Those identities hold for *any* curve,
so a formula that computed the wrong quantity consistently would pass
them. This fixture compares the outputs with a generating truth instead,
through the new `expected_tenure` check in `tests/run_tests.R`, for the
whole sample and for each period.

Remaining LOS shows the hold most plainly: an animal on its intake day
expects 15 more days, and each day of the hold takes one off, until the
hold is over and the expectation stops changing at 10. That flat stretch
is what "memoryless" looks like on this plot.

## What is pinned

- `expected_tenure`: the KM, in-care tenure and remaining-LOS curves at
  chosen days on both sides of the hold's end; the restricted mean; the
  mean tenure and the days still owed per resident; the tenure median and
  90th percentile; and remaining LOS read at each tenure statistic.
- `expected_period_stats`: the same truths counted from the stays rather
  than read off a curve — the inventory census (150) and the accumulated
  in-care days of the nights held (1,500).
- `expected_census`: the census-by-tenure route to the same census.
- `expected_km`: the committed sample's counts.

Tolerances are about 4.5 standard deviations, from a 120-seed scan; the
committed seed (76) is the scan's most typical draw.

## A design note: the cap

The cap is 120 days, where the true curve is effectively zero. A cap far
past the data (365) was tried first and made the mean tenure unstable on
some seeds: when a period's last long stay is censored, the curve is held
flat out to the cap, and the mean tenure weights those far days most. The
guides describe this sensitivity under "Choosing your
`restricted_stay_cap`"; this fixture keeps the cap short so that it tests
the curves rather than the cap.
