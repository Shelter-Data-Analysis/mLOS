# sim_crossed_shape — a discharge shape that lives in the cell

This fixture holds a shelter where the *shape* of the discharge process
belongs to the **combination** of intake type and animal group, and to
neither of them on its own. Two intake types, two animal groups, one
common Weibull scale of 20 days, and a checkerboard of shapes:

|        | G1   | G2   |
|--------|------|------|
| OWNER  | 0.70 | 1.30 |
| STRAY  | 1.30 | 0.70 |

Owner-surrendered G1 animals and stray G2 animals face a falling
discharge hazard; the other two diagonal cells face a rising one. Half
the shelter accelerates with tenure and half decelerates, and the two
halves are defined by a pairing rather than by either column.

## Why the checkerboard

Its row means and its column means are equal. On the log scale both main
effects are therefore exactly zero, so an **additive** shape formula,
`shape(intake_type) + shape(animal_group)`, can do no better than one
shape for everyone, while the **crossed** formula,
`shape(intake_type * animal_group)`, recovers the pattern.

That is the property the suite was missing. Every other fixture that
enables `parametric_regression` has at most two qualifying predictors, so
each shape variant has a single "other" term, its crossed and additive
formulas are the same string, and the choice between them is never
exercised. Crossing needs a third predictor to exist at all, which is why
period is here: two periods with no true difference between them, giving
a third qualifying predictor and a true-null calibration check at once.

## What the three variants show

| variant | shape formula | crossing LR (1 df) | reading |
|---|---|---|---|
| scale = period | intake_type × animal_group | ≈ 288 | the real interaction |
| scale = intake_type | period × animal_group | ≈ 0.9 | no such term in the truth |
| scale = animal_group | period × intake_type | ≈ 1.6 | no such term in the truth |

One variant where crossing is decisive and two where it buys nothing, all
from the same sample. A fixture that varied shape along a single
dimension would be fitted equally well either way and would pin nothing.

## The invariant this case guards

The additive shape model is nested inside the crossed one, so the crossed
fit cannot be the worse of the two and the crossing statistic cannot be
negative. The harness asserts that wherever a crossing happened, not only
here — a negative value means one of the two fits missed its own optimum,
which is a fitting fault rather than anything the data did. That failure
mode is reachable on real three-predictor data and was invisible to the
suite before this fixture existed.

## Fitted against generating truth

Whole-day discretization (`ceiling` of a continuous Weibull draw, so
arrival and departure days both count and the minimum stay is 1) biases
fitted shapes slightly upward at this scale. The reference cell's fitted
k is about 0.75 against a generating 0.70, and the two shape ratios come
out near 1.80 and 1.74 against a generating 1.857. `expected.R` pins the
fitted values with tolerances rather than adjusting the generating
constants.

Regenerate the sample with:

```bash
Rscript tests/cases/sim_crossed_shape/generator.R
```
