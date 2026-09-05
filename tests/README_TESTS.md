# mLOS Test Suite

Validation tests for the production `mlos_*.R` files. Two kinds of fixtures
are run through the real analysis functions and checked against known
expected values: small hand-derived datasets compared exactly, and `sim_*`
simulation cases — randomized samples from a fully known model, compared
against the generating parameters with statistical tolerances (see below).
The suite never modifies production code, data, or settings.

## Running the suite

From the project root:

```
Rscript tests/run_tests.R                      # fixtures + validation checks, writes no files
Rscript tests/run_tests.R --generate-outputs   # + plots/CSVs/Excel per fixture, golden comparison
Rscript tests/run_tests.R --update-golden      # + regenerate the golden files (see below)
Rscript tests/run_tests.R --prefix sim         # only fixtures whose name starts with "sim"
Rscript tests/run_tests.R --only km            # only checks whose label contains "km"
```

`--prefix <value>` restricts the run to the fixture cases whose directory
name starts with `<value>`; a prefixed run is fixtures-only (the
settings-validation and entry-point sections belong to the full suite and
are skipped). It combines with the other flags, so
`--prefix sim_weibull_truncation --update-golden` regenerates one case's
golden files without touching the others.

`--only <value>` narrows what is reported to the checks whose label contains
`<value>`, which is how you re-run one section after a failure without
reading past everything else. The two flags select different things and
combine. In the R suite `--only` does not shorten the run: the analyses are
shared between checks, so there is nothing to skip that would not also skip
checks that were asked for. In the Python suite it selects check functions by
name and does skip their work, except where one check's result feeds another,
in which case the producing check still runs with its own output muted.

### One failing check costs one check

Both runners contain the errors their checks raise. A check that stops is
reported as `[ERROR]`, counted as a failure, and the run continues; the
summary line says how many of the failures stopped rather than compared
badly. This matters more here than the wording suggests, because a suite
whose whole design is to run every check against every fixture is exactly the
suite that has the most to lose from one `KeyError` in the third case
aborting every case after it and printing a traceback where the summary
belongs.

The granularity differs between the two, and it follows their structure. The
Python checks are named functions taking a bundle, so each is isolated
individually, with a second guard around the whole fixture for the
scaffolding between them. The R fixture checks are inline code sharing one
set of fitted results, so the unit there is the case: a fixture that stops
costs that fixture, and every other fixture and the suite-wide checks still
run. Finer guards inside an R case would mostly report the same failure
again as a cascade of "object not found".

### The presentation builder

The Python package under `mlos_review/` has its own suite, in the same shape
and with no test-framework dependency:

```
python3 tests/run_review_tests.py             # synthetic checks + every golden bundle
python3 tests/run_review_tests.py --quiet     # failures only
python3 tests/run_review_tests.py --prefix sim
python3 tests/run_review_tests.py --only care_days
```

It reads the committed golden bundles rather than re-running R, so it needs
`tests/golden/` to be populated (`Rscript tests/run_tests.R --update-golden`)
but does not need R itself. It imports the deck builder, so it needs the same
packages `mlos_review` does, the ones `pyproject.toml` declares.

Checks come in two kinds. Fixture checks assert invariants over every golden
bundle, dispatching on what each contains, which is where the awkward shapes
live: eleven levels, an unreached median, a single constant-LOS period, an
eleven-way tie on intake rate, selectively disabled outputs. Synthetic checks
build a small frame by hand for behavior no fixture pins down at the
boundary. Both are needed, and the split is not cosmetic: the rule that
highlight flags are inherited from the full table rather than recomputed on
the shown rows CANNOT be tested from fixtures, because the levels a
superlative picks usually are the extremes, so a recomputation agrees by
accident. It takes a hand-built case with a mid-range row to fail.

There are no golden files for the deck yet. The content spec is still moving,
and a golden of a table that is about to change shape would produce churn
rather than catch bugs.

### The documents themselves

`run_review_tests.py` also checks the three guides as markdown, in a
`documents` section that runs before the fixtures and needs neither R nor a
golden bundle. It exists because the guides break in ways that are invisible
from whichever side you happen to be looking at: they are read on GitHub, they
are exported to Word by `make_docx.sh`, and the two renderers do not agree
about everything.

So the check runs both and diffs what each made of the file: the set of
headings, and how many bullet lists, tables and code blocks each saw. Anything
one sees and the other does not is where the two copies come apart. On top of
that it checks, without either renderer, the three things pandoc needs a blank
line above and GitHub does not, a list, a heading, and a `---` rule.

That last one is why this exists. A `---` directly under a line of text is a
setext underline to pandoc and a thematic break to CommonMark, so the line
above becomes a heading, takes the anchor the real section wanted, and pushes
the real one to `<slug>-1`. The presentation guide's contents list shipped
that way in August 2026: perfect on GitHub, and every link to the last section
landing on the contents list in Word.

`make_docx.sh` decides which documents this covers. Its `DOCS` list is the
declaration and the check compares its own against it, so adding a fourth
guide there fails here until it is covered too.

The renderer comparison needs `markdown-it-py`, which is CommonMark and the
closest local stand-in for GitHub, and a pandoc:

```
pip3 install markdown-it-py
```

Neither is a dependency of `mlos_review`, which is why neither is in
`pyproject.toml`: they check the documents, not the package, and a Colab
session should not install them to build a deck. When either is missing the
comparison reports `[SKIP]` with the reason and the summary line counts it, so
a machine without the tools cannot look like a machine that passed. The
blank-line rules run either way.

### The section numbers

A `section references` section, right after the one above, checks the numbering
that a paper cites. Two documents number their sections, the math methods and
`documentation_rules.md`, and both are read for sequence: a subsection that
skips a number, repeats one, sits under the wrong section, or carries no number
at all. Which heading level holds the sections is read from the document, since
the math methods number `#` and the rules number `##`.

It then sweeps every `.md`, `.R`, `.py`, `.yaml`, `.sh`, `.toml` and `.ipynb`
in the repository for `§` and checks each one names a real section of the math
methods. Ranges (`§§7.1–7.5`) are checked at their endpoints, which is enough
because the sequence check has already established the interior. A `§` is
written without a document name, so the sweep reads every one as pointing at
the math methods; that the rules are numbered and never cited this way is
itself checked, and a third numbered document fails here until the ambiguity is
settled.

What this catches is a citation of a section that is not there, which is what a
renumbering leaves behind everywhere below the insertion. What it does not
catch is a citation of the wrong real section. This file cited math methods
§5.7 for `expected_census` from the initial public release until August 2026;
§5.6 was meant, §5.7 is a real section about the in-care tenure profile, and no
check can tell those apart.

### The numbers the documents quote

Neither of the above touches the worked examples in the guides and the math
methods document, which are marked OC1 or OC2 and read off real runs:

```
python3 tests/show_guide_examples.py                 # the default results/
python3 tests/show_guide_examples.py results/OC1
Rscript tests/scan_shape_floor.R data/OC2_data.csv data/OC2_settings.yaml
Rscript tests/scan_shape_floor.R data/OC2_data.csv data/OC2_largecut_settings.yaml
python3 tests/show_doc_versions.py
```

`show_guide_examples.py` reports every quoted figure a standard run produces
beside what the run says. `scan_shape_floor.R` recomputes the two derivations
no run performs, the count floor behind the shape guard and the behavior of
the starting-value grid; the large-dog cut is the case where flexsurv's own
starts fail. `show_doc_versions.py` compares each guide against the two markers its tracked
Word export carries, the version stamp and the commit it was built from, which
together say whether that export was built from what the guide now says.

The first two report and never fail: the quoted numbers are meant to move when
a dataset does, and a suite that broke on a shelter's real data changing is
one people learn to ignore. They report, and you decide whether the document
or the run is the thing to change.

`show_doc_versions.py` does both, and the split is the point. Which exports
are behind is a report, because a stale export is the ordinary state between
releases. A guide whose text has moved since HEAD while its stamp stood still
is a failure, and is the exit status: the stamp is bumped by hand, so without
this it is a claim nobody checks, and an unbumped edit makes every stale
export downstream read as current. Run it before committing a documentation
change. `--history` asks the same question of every pair of commits and only
reports, since a violation already in history stays there.

## Requirements

The plain run needs the `survival` and `yaml` packages. `--generate-outputs`
additionally uses `jsonlite` for the results bundle and `openxlsx` for the
workbook checks (the latter skipped with a note if it isn't installed). Exit
status is nonzero if any check fails.

## What each mode does

**Plain run** — every fixture under `tests/cases/<name>/` is run through the
production pipeline and its `expected_*` values are checked. Afterwards, a
validation section asserts the exact error messages of the settings parsers
and row-level data checks (these `stop()` paths can't be reached through
fixtures, because a fixture that trips one would abort its own run).

**`--generate-outputs`** — additionally runs *every* analysis on *every*
fixture (even ones a fixture wasn't built to test — small edge-case data is
exactly where an unhandled degenerate case hides; every analysis must either
produce a result or report `has_analysis = FALSE`, never crash) and renders
all plots and CSVs to `tests/results/<name>/` for visual inspection. It also:

- builds the results bundle per fixture, writes it to `results.json`, and
  checks its arithmetic invariants (the census identities, the count-based
  confidence intervals recomputed from their counts, the AJ restricted-mean
  relations) directly on the bundle;
- writes the consolidated Excel workbook per fixture and checks what only the
  workbook can be wrong about: which sheets exist, which measure sits on which
  row, the reference column and the notes, plus a spot check per sheet family
  that a cell holds the bundle's value;
- rebuilds the workbook from `results.json` alone (the `mlos_render.R` path)
  and requires it to match the one rendered from the live bundle, cell for
  cell, which is what keeps the JSON sufficient to reproduce every output;
- checks the `outputs` manifest names exactly the files the run wrote, and
  cross-checks each companion CSV's summary row against both its own grid and
  the bundle's value for the same quantity. The two are computed by
  independent routes on purpose (Little's law versus summing the profile, for
  instance), so this asserts they land in the same place rather than removing
  one of them;
- compares every generated CSV **byte-for-byte** against the committed golden
  copy under `tests/golden/<name>/`, does the same for `results.json` (with
  everything that legitimately varies replaced by placeholders: the generation
  timestamp, the tool version, the R and package versions beside it, and the
  project root that prefixes the paths in the run block, so the goldens match
  on any machine rather than only the one that wrote them),
  and checks that every PNG listed in that case's `png_manifest.txt` was produced
  (PNG bytes vary across R/graphics versions, so only their existence is
  checked).

`tests/results/` is regenerable and git-ignored; `tests/golden/` is committed.

The byte-for-byte comparison pins the package versions that generated the
goldens: a different `survival` version can shift last-digit floating-point
values (and the NA-vs-0 representation of degenerate AJ confidence bounds),
which shows up as golden failures with no statistical meaning.
`--update-golden` records R and every package in `MLOS_PACKAGES` in
`tests/golden/environment.txt`, and every `--generate-outputs` run prints the
live versions beside that record. The same versions go into the `run` block of
each run's own `results.json`, where the golden comparison blanks them and
`check_json_round_trip` asserts them instead. A difference is reported rather than failed:
it names the likely reason for a golden diff, while a version that shifts
nothing leaves every golden passing. On a machine that differs, rely on the
plain run's expected-value checks.

A prefixed `--update-golden` regenerates one case, so it leaves the record
alone and warns when the environment differs. The alternative is a golden tree
built half on each.

## Golden files: the important workflow

If a code change is **supposed** to alter outputs:

1. `Rscript tests/run_tests.R --update-golden`
2. Review the `git diff` of `tests/golden/` — it must show exactly the change
   you intended and nothing else.
3. Commit the golden diff together with the code change.

If a `--generate-outputs` run reports golden failures and you did *not* intend
an output change, that's a regression — investigate before touching the
goldens.

## Adding a fixture

Create `tests/cases/<name>/` with three files:

| File | Contents |
|---|---|
| `data.csv` | Small dataset (`intake_date`, `outcome_date`, `outcome_type`, optionally `animal_id`, `intake_type`, `animal_group`) |
| `settings.yaml` | YAML settings, with a comment block deriving the expected values by hand |
| `expected.R` | One or more `expected_*` lists with the derived values |

Which analyses run is driven entirely by which `expected_*` objects
`expected.R` defines (presence-based dispatch — there is no separate flag):

| Object | Checks | Example field names |
|---|---|---|
| `expected_km` | Unified KM (`km_unified_period`) | `median_los`, `restricted_mean`, `n_capped`, `fraction_capped`, `max_time` |
| `expected_stratified_km` | Stratified KM fits + per-stratum gaps | `period.Period_1.median`, `period.Period_1.rmean`, `group.BIG.n`, `n_strata_gaps`, `gap.Animal Group.SLOW.start` |
| `expected_census` | Census-by-tenure companion of the stratified KM (math methods §5.6): per-stratum intake rate, Little's-law predicted census, and the daily census profile | `period.Period_1.lambda`, `period.Period_1.predicted_census`, `group.SMALL.day5` |
| `expected_cox` | Cox regression | `has_analysis`, `n`, `n_events`, `HR_animal_groupBIG` |
| `expected_weibull` | Weibull regression (needs `parametric_regression: WEIBULL` in the case's settings) | `shape`, `TR_intake_typeOWNER` (LOS ratio), `HRw_intake_typeOWNER` (implied HR), `shape_unified` |
| `expected_aj` | Pooled AJ competing-risk CIFs | `CIF_L_day10`, `CIF_Any_day3`, `CondRem_N_day5`, `n_outcome_states` |
| `expected_aj_period` | AJ within each period | `Period_1.CIF_L_day10`, `n_periods` |
| `expected_aj_intake` | AJ within each `intake_type` | `STRAY.CIF_L_day10`, `n_intake_types` |
| `expected_aj_group` | AJ within each `animal_group` | `LARGE.CIF_L_day10`, `n_animal_groups` |
| `expected_period_stats` | Per-period counts/census/flow metrics | `Period_1.total_animal_days`, `Period_2.daily_mean_total_in_care_days` |
| `expected_stratum_stats` | Per-stratum counts/census/flow metrics, as the Excel `By_Intake_Type`/`By_Animal_Group` sheets compute them (grouped by the stratifier column, whole-window day denominator) | `group.SMALL.total_animal_days`, `intake.STRAY.total_intakes` |

See the `flatten_*()` functions in `run_tests.R` for the full field lists. The
per-period and per-stratum ones read the same observation matrix the results
bundle carries, so a fixture pins the value that reaches `results.json` and the
workbook rather than one derived alongside it.
Expecting `NA` for a field also works as an *absence* assertion (e.g. a CIF
column that must not exist for a period).

Expected values are compared with an absolute tolerance of `1e-6` by
default. A case can widen this in its `expected.R`: a top-level
`tolerance <- 0.05` sets the case-wide tolerance, and any individual field
written as `c(value, tol)` overrides it for that field alone.

A new case also moves three things the documentation states rather than
derives: the golden bundles this repository ships, the list of simulation
cases below, and the presentation guide's count of how many fixtures the
recommendation rules stay silent on. `check_fixture_inventory` in
`run_review_tests.py` measures all three against the cases themselves, so a
fixture added without them fails the Python suite with the numbers to write.
Regenerate the goldens first (`Rscript tests/run_tests.R --update-golden`): a
case with no bundle is a fixture the Python suite never runs, which is the
first thing that check reports.

## Simulation fixtures (`sim_*`): statistical tests with known truth

Fixtures whose name starts with `sim_` hold **randomized samples from a
fully known model** instead of small hand-derived datasets, and their
expected values are the *generating parameters* (true hazard ratio, true
Weibull shape, ...) with tolerances of roughly 4 standard errors — sized
so a fresh sample of the same design should also pass. They serve two
purposes: they check that the analyses recover known truth from realistic
data (larger n, natural left truncation and right censoring), and they are
worked examples users can open to see what every output looks like when
the data samples a predetermined form.

Each `sim_*` case carries two extra committed files beyond the usual
three:

| File | Contents |
|---|---|
| `generator.R` | The seeded script that produced `data.csv`; rerunning it reproduces the sample byte-for-byte (R >= 3.6), and a new seed draws a fresh sample with the same properties |
| `README.md` | What the model is and what to look at |

Every generator sources the shared `tests/cases/sim_common.R` for its
finalize-and-write tail (`finalize_and_write()`: snapshot at the export
date, blank the outcomes of still-open stays, format dates, assign
animal ids, write `data.csv`), so a case copied elsewhere needs that
file alongside it.

The committed `data.csv` keeps every run (including the byte-for-byte
golden comparison) fully deterministic. The derivation of the truth values
lives in the case's `settings.yaml` comment block, like any other fixture.
Run `--prefix sim` to execute just these cases, and
`--generate-outputs` to render their full plot/CSV/Excel output under
`tests/results/<name>/`.

Current simulation cases:

- **`sim_weibull_truncation`** — two intake types with Weibull stays
  (common shape 1.3, scale 10 vs 20 days, so LOS ratio 2 and hazard ratio
  2^(-1.3) = 0.406), Poisson daily intakes from 2024-01-01, study window
  2024-03-01 to 2024-09-01, so left truncation and right censoring arise
  naturally. Checks KM, stratified KM, Cox, Weibull, and AJ against the
  generating truth.
- **`sim_geometric_period_effect`** — a true period effect with
  memoryless (geometric) stays: the within-day outcome rate doubles at
  the period 1→2 boundary for every animal in care (daily no-outcome
  probability squares, the grouped form of proportional hazards, so the
  true Cox HR is exactly 2), after a notional "period 0" brings the
  population to steady state. Checks the twin Cox period hazard ratios,
  per-period KM/AJ (exact geometric truth, no day-rounding bias), and
  Little's law for the census in the steady periods — while period 2
  demonstrates the census lagging a rate change the hazard analyses see
  immediately.
- **`sim_cause_rate_shift`** — a cause-specific rate shift: at the period
  boundary the within-day rates of the three causes change by different
  factors (L ×3, T ×1/3, N unchanged) whose share-weighted sum is exactly
  2, so every all-cause statistic has the *same* true value as in
  `sim_geometric_period_effect` and only the by-period AJ analysis can
  tell the two fixtures apart: the cause shares shift from 0.6/0.3/0.1 to
  0.9/0.05/0.05. Checks that the AJ layer recovers the shifted shares
  (including N's share halving although N's own rate never changed) while
  KM and Cox report the identical all-cause truth.
- **`sim_size_mixture`** — the declining-hazard illusion: a 70/30 static
  mixture of SMALL (q = 0.12) and LARGE (q = 0.03) dogs, each memoryless,
  nothing changing over time. The pooled statistics violate the
  memoryless ratio benchmarks (the pooled hazard declines with tenure by
  composition alone) while the stratified KM shows each size
  flat-geometric and the size-adjusted Cox/Weibull fits dissolve the
  artifact (adjusted shape ≈ 1; the unadjusted fit's shape ≈ 0.87 is
  quoted in the README). Also pins a true-null period hazard ratio
  (identical periods, HR exactly 1) and the capped Little's law census.
- **`sim_intake_mix_shift`** — Simpson's paradox: at the period 1→2
  boundary every dog's rate improves ×1.5 while the SMALL/LARGE intake
  mix flips 70/30 → 30/70 at constant 10 dogs/day. The crude pooled
  median rises 8 → 10 days and the census rises 155.7 → 173.3 (the
  shelter looks slower and fuller) while the size-adjusted Cox model
  reports every dog 50% faster — both correct on the same data. The
  first sim to fit two predictors jointly, with all three true
  coefficients known in closed form (period HR 1.5 twice, group HR
  0.238); period 2 is the transition and deliberately unchecked.
- **`sim_crossed_shape`** — a Weibull shape that belongs to a *pairing*
  rather than to either predictor: two intake types, two animal groups, a
  common scale of 20 days, and a checkerboard of shapes (0.70 on the
  OWNER/G1 and STRAY/G2 cells, 1.30 on the other two). The row means and
  the column means are equal, so both main effects are zero on the log
  scale and only the crossed shape formula recovers the pattern. It
  carries a third qualifying predictor, which is what makes a shape
  variant's crossed and additive formulas differ at all; the two
  variants with no true interaction serve as the null calibration.

House conventions, learned the hard way and documented in the existing
fixtures: derive values by hand first, then verify against the code before
writing them down; when a curve touches a quantile threshold *exactly*
(S = 0.5 or 0.10), the reported statistic is the **midpoint** of the flat
stretch, not its left edge; and `summary(fit, rmean = cap)` extends the curve
flat when the cap lies beyond the last observed time.

After adding a fixture, run `--update-golden` once to create its golden
directory, and review that diff like any other.
