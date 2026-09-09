# Changelog

What changed between releases, and whether the change moves a number.

Two rules govern entries here.

**Say whether output moved.** A release either changes what a run computes or
it does not, and a reader deciding whether to rerun needs that in the first
line of the section, not inferred from the bullets. A documentation-only
release says so and says that output is byte-identical to the release before.

**The section heading moves when the version is closed out, before the tag.**
It moves with `MLOS_VERSION`, `version:` in `CITATION.cff` and `version` in
`pyproject.toml`, in the commit the tag will point at. Zenodo archives that
tree, so a heading still reading `Unreleased` there archives a release unable
to name itself. `PUBLISHING.md` step 2 is where the four are moved together.

---

## Unreleased

**No number changed**: only the entry point moved, and every CSV, every plot
and `results.json` are byte-identical to 0.2.1.

- `Rscript mlos_run_complete.R --help` (or `-h`) prints the options, the
  environment variables, and the default each one falls back to, then exits
  without running the analysis. It is answered before the required-package
  check, so it prints on a machine where `survival` and `yaml` are not
  installed yet, which is the machine most likely to be asking.
- The six run defaults are constants that both the help text and the
  environment-variable fallback chain read, so a default cannot move in one and
  not the other. The help text derives its package list from
  `MLOS_PACKAGES_REQUIRED` and `MLOS_PACKAGES` for the same reason.
- The unrecognized-argument error gains a line pointing at `--help`.
- `tests/run_tests.R` gains six entry-point checks: that `--help` and `-h`
  print usage, that the version appears, that the analysis does not run, and
  that the help text names the real default settings file.
- `README.md` and the user guide's "Running the Tool" section describe the
  option.

## 0.2.1 (2026-09-08)

The DOIs the 0.2.0 release minted, caught. **No number changed**:
`tools/make_deposit.py` is the only source that moved, no run reads it, and
every CSV and every plot is byte-identical to 0.2.0.

- `CITATION.cff`, `README.md` and `presentation_guide.md` name results version
  2, `10.5281/zenodo.22652165`, and deck version 3, `10.5281/zenodo.22652329`.
  Neither existed when 0.2.0 was archived, which is why a second release
  carries them.
- `PUBLISHING.md`'s identifier table gains mLOS 0.1.2, which it had never
  recorded, mLOS 0.2.0, and the two new deposit versions. Its ancestry diagram
  names the deposits a reader would fetch today.
- Step 7 gives the deck deposit's type as Presentation, which is what the
  records carry, and warns that Zenodo's New Version brings the previous
  version's *is derived from* forward. That field then names a results version
  the deck does not come from, and resolves, so only a reading of the
  published record catches it.
- The deposit README names `flexsurv` and `digest` among the packages a
  rebuild needs. Following it without them gives no Weibull companion and no
  digests, which are two of the fields the deposit exists to carry.
- The README says which plots have no companion CSV. A stacked bar plot bins a
  curve rather than redrawing one, so a day grid beside it would be another
  figure's numbers.
- The staging script counts the upload set rather than naming it. The deck
  bundle carries its settings file beside the zip, so the instruction to
  upload three named four files.
- The changelog's own second rule now says the section heading moves at
  close-out rather than at the tag, which is the order `PUBLISHING.md` step 2
  has always given. The tagged tree is what Zenodo archives, so the heading has
  to name the version by then.

---

## 0.2.0 (2026-09-08)

Variant decks, deck templates, an educational section, two interval figures,
and a run that records its environment and the digests of what it read. **No
computed value moved**: every CSV is byte-identical to 0.1.2, and every value
`results.json` already held is unchanged. The output set grew, so a bundle
deposited under 0.1.2 is incomplete rather than wrong. Thirty plots are
redrawn, on axis scaling and axis labels, and carry the same numbers.

Both suites run on every push, and a run stamps the digest of what it read.
Nothing in this part computes or draws anything.

- A run records the SHA-256 of its data file and of its settings file, in the
  console log, in the `run` block of `results.json`, and on the workbook's
  cover sheet. The algorithm and the label shape are the ones ShelterDataPrep
  writes for the file it prepared, so the preparation log and this one compare
  without a converter. Bundles written before this carry neither field and
  render "(not recorded)".
- `digest` is optional the way the three packages that write output are, with
  one difference worth knowing before a run matters: an absent one costs the
  two fields rather than the run, but it also costs the deposit, since
  `tools/make_deposit.py` refuses a run whose digests read "(digest package not
  installed)". `mlos_user_guide.md` lists it and `colab_mlos.ipynb` installs
  it, and the Python suite holds that notebook to every package the R files
  call, which is how it came to be missing from both.
- The goldens carry the two digests, which pins each fixture's input bytes:
  editing a fixture's `data.csv` now shows up in its golden diff.
- `tools/make_deposit.py` is tracked, and is the enforcement behind
  `PUBLISHING.md`. It checks a run's recorded digests against the files it is
  about to stage, refuses a run that recorded none, and for the deck bundle
  reads the run timestamp each deck prints on its opening slide, so a deck
  built from an earlier run cannot be uploaded. The deposited decks are
  `mlos_deck.pptx` and the educational variant, both unbranded, and the deck
  travels with the `<name>_slides.json` written beside it: that file is what an
  outline is written against, so a deposit without it ships a deck that can be
  shown and not extended.

- `.github/workflows/tests.yml` runs `tests/run_tests.R` and
  `tests/run_review_tests.py`. The R suite runs under a UTF-8 locale and under
  `LC_ALL=C`; the Python suite on 3.9 with pandas 2, and on 3.13 with each of
  pandas 2 and 3. `pyproject.toml` sets no ceiling on pandas, so both majors
  are in use in the wild and both are tested; pandas 3 requires Python 3.11,
  which leaves the floor leg on pandas 2. Each Python leg prints the versions
  the resolver chose.
- The UTF-8 leg is the one that tests the collation pin. `LC_ALL=C` satisfies
  the pin in `mlos_common.R` from outside, so the suite's collation check
  reports itself skipped rather than passing; a locale that collates
  differently is what gives it teeth.
- `check_figures_are_drawn` asserts that a build still draws every figure kind.
  The per-case manifest check compares the manifest against the PNG directory,
  and those agree when a build draws nothing at all, so a regression that
  silenced every figure passed every fixture. The kinds are read from the
  manifest rather than from instrumenting `figures`, and bundles are built only
  until each kind has been seen, which is four of them.
- The goldens are not compared on a runner. `tests/golden/environment.txt`
  records the versions they were written against and a runner installs what
  CRAN holds today, so the byte comparison would fail on a package that moved
  without a number having changed. `--generate-outputs` stays local.

A run records the versions it ran under, and the goldens record theirs.
**No analysis number changed**: every CSV is byte-identical to the release
before.

- The `run` block of `results.json` gains `r_version` and one field per package
  in `MLOS_PACKAGES`. `survival` sets the last digits of every curve and fit,
  `flexsurv` those of the Weibull companion, `yaml` how a settings value parses,
  `jsonlite` the layout of the file, and `openxlsx` the workbook, so an archived
  run says what produced its numbers rather than leaving a reader to guess.
  A machine missing an optional package writes `not installed` rather than a
  shorter block, which keeps two runs comparable field for field. The schema
  version stays 5, here and for the two digests above: it moves when a field
  changes meaning or disappears, and an addition does neither.
- That policy holds only while a reader tolerates an absent field, and four
  consumers do that in four different ways, so no one of them shows the
  promise. A suite check strips every field the run block has gained since 5
  from a real bundle and requires the workbook to build, and to build the same
  sheets.
- The console log header carries the same versions on one line under the tool
  version, so a log read on its own says what produced the numbers below it.
  `mlos_environment_versions` in `mlos_common.R` is what the header, the run
  block, and the goldens' record are all built from, so the three name the same
  things in the same order.
- `mlos_render.R` echoes the versions its bundle recorded, which are the ones
  that computed the numbers it is about to lay out rather than the ones on the
  machine laying them out. A bundle without them renders as before.
- The Excel cover sheet lists the same fields under Run metadata. Every cell
  falls back to `(not recorded)`, so a bundle written before this renders with
  its two columns balanced instead of only the tool version being covered.
- `tests/golden/environment.txt` records those versions beside the goldens,
  written by a full `--update-golden` and printed by every `--generate-outputs`
  run. A difference is reported rather than failed: a newer `survival` that
  shifts no number would fail a version assertion while every golden passed,
  and would fail on Colab every run, which compiles the newest CRAN `survival`.
  What already fails when the numbers move is the golden itself; the record
  says whether the environment is why. A prefixed `--update-golden` leaves the
  record alone and warns, since regenerating one case there would build the
  tree half on each environment.
- The golden comparison blanks the new `results.json` fields for that same
  reason, and `check_json_round_trip` asserts them against the live versions
  instead, so a field that stopped being written fails rather than normalizing
  to nothing.

The Cox fits name their tie handling, and a fixture built for it holds them
there. **No analysis number changed**: `ties = "efron"` is the `coxph` default.

- `ties = "efron"` is passed at both `coxph` call sites in `mlos_cox.R`. Event
  times are whole days, so every event day is a tie, and the tie rule decides
  what the hazard ratio estimates.
- `tests/cases/massive_daily_ties` puts the candidate answers far enough apart
  to be told apart. 256 of 512 large dogs leave the same day, then 128 of 256
  and 64 of 128, against 384 of 512 small dogs and 96 of 128: the within-day
  rate ratio is exactly 2, the daily probability ratio 1.5, the odds ratio 3.
  Efron returns 1.889 and Breslow 1.500, the probability ratio to within 2e-14.
  The window shuts after four days, where the small dogs run out of whole
  animals, so every count is an exact fraction of its risk set, every day
  carries exits from both groups, and the pin is built rather than sampled.
- The case pins both `coxph` calls. A null two-level `intake_type` splits each
  group into identical halves, which gives the stratified variants a second
  stratifier to run on and a hazard ratio of exactly 1 to return. The variant's
  Efron value differs from the pooled one in the third decimal, because
  duplicating a dataset changes how many events are tied and Efron's correction
  reads that count while Breslow's does not, so the pair also catches the two
  calls disagreeing about the rule.
- Math methods 6.2 now says how far the Efron approximation carries: within a
  quarter of a percent of the within-day rate ratio while the daily probability
  stays under about 0.12, and 5% short of it at 0.5. Breslow returns the daily
  probability ratio exactly instead.

A worked template ships with the repository, and table rows are one line tall
unless their text needs more. **No analysis
number changed**: this is the deck's geometry and nothing it computes.

- `data/deck_example_template.pptx` is a template that works, so the guide's
  example is a file rather than a description. Bars of 0.8 and 0.7 inches leave
  a 4.90 inch body against a plain slide's 5.90, and brand 18 of the OC2 deck's
  48 slides. A check holds it to a band deep enough to be worth showing, since
  deepening a bar quietly stops the branding reaching the table slides.
- `data/educational.md` and `data/extended_variant_features.md` are tracked as
  the two worked outlines: one written to be presented, one written to be read
  beside the guide.
- `data/extended_variant_features.md` exercises every part of the outline
  format, including the parts a presentation would not want: a stub, an insert
  that borrows a whole run of continuation pages, and a written page long
  enough to break in two. `data/educational.md` stays the one written to be
  shown.
- The educational section gains **Working with Metrics: Just numbers, no
  plots**, which carries the two whole-sample tables under an identity a room
  can check by hand and over a line saying where to look next. The slide after
  it keeps the two interval figures and gives up the tables it used to carry
  under them, so neither page asks for the numbers and the picture at once. A
  COLUMN layout draws the tables down the page instead of across, for tables
  wide enough that a row would squeeze both to half a slide.
- `Slide.close` is a line at the foot of the body, the lead read from the other
  end: what a slide concludes, or what it hands to the next one. In an outline
  it is a paragraph written under the bullets, where one was refused before. It
  sits above a footnote, and costs nothing on a slide that has none.
- A table's height counts its header as as many lines as the width estimate
  says it wraps to, and pptx divides that height evenly among the rows. The
  room reserved for a second header line was therefore spread over every data
  row as well, so a table under a header thought to wrap stood half again as
  tall as its numbers needed. Every row is now set to one line's height, which
  pptx treats as a minimum, so a header that really wraps still grows and one
  that does not costs nothing. Table positions are unchanged; 18 of the OC2
  deck's 43 tables lose the padding.

Variant decks, deck templates, and two auxiliary figures. **No existing
analysis number changed** by any of them: the deck the R run has always
produced is built slide for slide as it was, and both new features are
inert unless a settings key or a flag turns them on.

- `python3 -m mlos_review.variant OUTLINE.md` writes a second deck from an
  outline: plain text slides written by hand, plus slides the deck already
  builds, borrowed by title. `#` opens a slide, `##` is its standing line,
  `{divider}` sets it as a section opener, `@insert` borrows, `@stub` holds a
  gap open, `<!-- ... -->` is a comment that also switches slides off, and
  `--list` says what may be borrowed. Speaker notes written under an `@insert`
  head the borrowed slide's own, marked with a `*`; nothing else may be added
  to a borrowed slide. Notes follow markdown's blockquote: consecutive lines
  run on, and a blank line, a bare `>`, a `- ` item or a trailing hard break
  starts the next paragraph.
- The deck now writes `<name>_slides.json` beside itself, recording every
  slide's position, title, layout and run. A variant checks its own assembly
  against it and refuses to build against a deck it no longer matches.
- `template:` in the deck settings file, or `--template=FILE`, lends a
  one-slide `.pptx`'s artwork to the slides that have room for it: those
  carrying no figure, plus a schematic that can yield width, and only where
  the content fits the band the artwork leaves. A slide that would not fit at
  eighteen point is measured again at sixteen and fourteen.

Two auxiliary figures and the setting that turns them on. They bin curves the
tool already draws and add no estimator. **No existing analysis number
changed**: `probability_mass_width` defaults to 0, so a run that does not set
it computes and writes exactly what it did before.

- `aj_mass_unified_stack` draws how much of the distribution falls in each
  interval of days, one stacked bar per interval split by outcome type, with a
  gray bar for the stays still in care at the cap. A bar's total is the fall in
  the KM survival curve over the same interval, so the bars and the gray one
  sum to 1.
- The intervals run at the requested width until one of them contains
  `plot_stay_cap`, which is kept whole, and a single interval then covers the
  rest of the way to `restricted_stay_cap`.
- `aj_fraction_unified_stack` draws the same intervals normalized to their own
  totals, so every bar is full height and what varies is the outcome split.
  Each bar carries its share of the distribution as a label, since normalizing
  hides how much of the data a bar speaks for. The bar at the cap is kept as an
  empty slot so the two figures put every bar at the same x.
- The deck gains an **Educational** section at the very back, behind the
  robustness check. An educational slide carries no findings and no
  recommendations, which the section enforces rather than leaving to each rule.
  It opens with "Looking at Length of Stay (LOS)", an alternate title slide
  carrying the truncation diagram, the question of which stays a period may
  count, and the method and software citations. "Working with Probabilities in
  Time Intervals" follows, putting the two interval stacks side by side over
  the whole-sample length-of-stay and outcome tables so the picture can be
  reconciled against numbers the audience has already been given; it is built
  only where the run drew those figures.
- A slide bullet may sit one level in, for a sub-list.
- **The conditional outcome mix at the three resident tenures** joins the
  bundle as `aj_condrem_at_tenure`, nine values read off the analysis window's
  day grid by the same day convention the remaining-LOS readings beside it use.
  A second whole-sample competing-risk slide reports them: a row per tenure,
  with the remaining stay, the mix, and the share still in care at the cap.
  These are conditional on having reached the tenure, so they are not the
  cumulative incidences the teaser before them shows.
- The STACKED layout can hold a row of tables under its figures, which is what
  that slide needs; slides using its single-table field are unchanged.
- The numbers travel in the bundle as `aj$probability_mass` and reach no
  worksheet. The figures ship no companion CSV: their bars are neither a day
  grid nor a redrawing of one, so the bundle is where they live. They stay out
  of the workbook because the intervals are a reading choice made for a
  picture, and a workbook column that moves with a plot setting invites being
  quoted as though it did not.

Contributing, reporting a bug and asking a question each have somewhere to go.
**Documentation only**: no code changed, and every CSV and every plot is
byte-identical to the release before.

- `CONTRIBUTING.md` leads with the contribution the project most wants, a run
  on another shelter's data: what a deposit holds, where to put it, how to cite
  the version that produced it, and what to say afterwards about how the tool
  performed. Where the extract is not the depositor's to release, the settings
  and the results still stand on their own. Reporting a bug, asking a question
  and opening a pull request follow it.
- `.github/ISSUE_TEMPLATE/` carries a form for a bug report and one for an
  analysis report. The bug form asks for the settings file, `analysis_log.txt`
  and `data_preparation_stats.csv`, which usually locate a fault without the
  data that is generally not the reporter's to send. The analysis form asks
  which plots, sheets and tables carried the finding, since a run reports
  nothing about which parts of a large workbook anyone opens, and asks what
  became of the deck, which is the least settled part and the one a report of
  real use moves fastest. Anything fitting neither form goes in a blank issue.
- The README, `mlos_user_guide.md` and `presentation_guide.md` point at the
  issue tracker. There is no private support channel, so answers are public and
  the next person with the question finds one.
- `tests/README_TESTS.md` is now `tests/README.md`, met by anyone opening
  `tests/` rather than reached by knowing its name, and it opens by naming the
  five layers the suite runs in: hand-derived values, simulation recovery,
  arithmetic invariants, golden files, and documentation integrity.

## 0.1.2 (2026-08-28)

Deck workbook correction, and a documentation pass on terminology. **No
analysis number changed**: the R analysis sources are untouched, and every
value a run computes is identical. What moved is the
`Workload_By_Stratum` sheet of the deck builder's workbook, which now carries
three columns it had been dropping and heads its share columns unambiguously,
and the wording of the three guides.

- The workbook's column order was derived from the three workload slides'
  sections, so a column no slide had room for was dropped from the sheet as
  well, against what `workload_full_table` documents. Three went that way:
  `Intakes/day`, the share of the fitted census, and the share of the days
  owed. All three are now present, from a workbook order of its own
  (`WORKLOAD_WORKBOOK_ORDER`).
- Losing `Intakes/day` left the intake share sitting beside `Days given, whole
  window`, headed only `Pct`, where it read as a share of those days. It is not:
  it is the share of intakes, and for the large dogs of **OC2** the two differ
  by nearly a factor of two, 38.4% against 69.7%. The value was always correct;
  the header and its neighbor were not.
- The four share headers now name what they divide (`Intakes, pct`,
  `Census counted, pct`, `Census fitted, pct`, `Days owed, pct`) instead of a
  bare `Pct` or `Share`, so a share does not depend on its neighbor to be read.

Slides are unaffected: they use their own header map and their own column
sections, neither of which changed. Anyone who read a share out of the deposited
deck workbook should recheck it against the corrected column.

Documentation, in the same window:

- **One name for the fit that carries every factor at once.** It had answered to
  "general Weibull", "main Cox" and "unified Cox" depending on the page, while
  `pooled` was separately naming four different things. Four words are now
  reserved, each already matching an identifier so no code was renamed:
  `unified` for the whole sample, `pooled` for the all-factor fully adjusted
  fit, `crude` for that fit with covariate terms dropped, `all-cause` for every
  outcome type together, plus `marginal` for a curve `unified` would overstate.
  27 sites across the four guides. Recorded in `documentation_rules.md` §5.
- **A contradiction fixed.** The user guide said the per-predictor stratified
  Cox fits were "in `results.json` but on no worksheet", and forty lines later
  said the workbook shows their hazard ratios. The second is right, and
  `mlos_excel_export.R` writes them.
- **Section 6 of the math methods document retitled** to "Regressions on the
  Three Factors", which is what it holds, with a roadmap paragraph saying why
  the stratified Cox sits after the Weibull rather than beside the other Cox
  material. No section renumbered.
- **`PUBLISHING.md` gained "Decisions, deferred"**, listing terminology and
  results-JSON names worth changing later, and saying plainly that nothing in
  it is a commitment.

---

## 0.1.1 (2026-08-24)

Documentation. **No number changed**: the analysis sources are untouched apart
from the version string, and every value a run computes is identical to 0.1.0.
The version moves because what a citation points at has changed.

Output is not byte-identical, because a run records which version made it.
Measured against the deposited 0.1.0 run rather than assumed: all 37 curve
CSVs are identical, and `results.json` is identical except for the
`mlos_version` line. The version string also appears in the console log header
and on the Excel cover sheet. So the deposit stays valid and stays pinned at
0.1.0, and rerunning under 0.1.1 reproduces its numbers exactly.

### Added

- mLOS has a DOI: [10.5281/zenodo.22083814](https://doi.org/10.5281/zenodo.22083814),
  the concept DOI, which resolves to the newest release. It is in
  `CITATION.cff`, so the rendered citation now carries it.
- What the shipped OC2 settings produce is deposited at
  [10.5281/zenodo.22084231](https://doi.org/10.5281/zenodo.22084231), CC BY 4.0,
  and is a `references` entry: cite it instead of the prepared input if you
  used those results as they are rather than recomputing them.
- The slide deck built from that run is deposited at
  [10.5281/zenodo.22085157](https://doi.org/10.5281/zenodo.22085157), CC BY 4.0.
  `README.md` and `presentation_guide.md` name it. `CITATION.cff` does not: the
  deck builder is experimental, the results deposit is the record, and a
  citation file should not point a reader at the rendering instead.

### Changed

- `README.md`'s citing section names the three deposits and says which to cite
  when, rather than saying no DOI exists yet.
- The deposit each record names as its parent is its direct one. The results
  deposit is derived from the prepared input rather than from the raw extract,
  because mLOS never reads the raw extract, and the ancestry stays walkable
  because the prepared deposit points at the raw one itself.

## 0.1.0 (2026-08-24)

The first release. There is no earlier version to compare against, so this
section describes what 0.1.0 is rather than what moved.

### The analysis

Kaplan-Meier survival, restricted mean length of stay, and median stay, overall
and stratified by period, intake type, or animal group. Cox proportional-hazards
regression with a Weibull shape reading. Aalen-Johansen competing-risks
estimates for the three canonical outcomes. In-care tenure and remaining-stay
curves for the residents present at a moment. Every estimate carries a
confidence interval.

### The outputs

A consolidated Excel workbook, a plot set with the numerical values of each
curve in an identically-named CSV beside it, `results.json` holding every
computed number, a console log, and `data_preparation_stats.csv`, which records
how the input rows were transformed, removed, or kept in the same column layout
as the statistics table ShelterDataPrep writes, so the two stack into one flow
from the raw extract to the rows the models ran on.

The workbook can be rebuilt from a saved `results.json` without repeating the
analysis.

### Release metadata

- `MLOS_VERSION` in `mlos_common.R` is the version of the whole repository, R
  side and Python side alike, because one tag produces one archive with one
  DOI. It is reported in the console log header, in `results.json` under `run`,
  and on the Excel cover sheet. The test suite holds it equal to the version in
  `CITATION.cff` and in `pyproject.toml`.
- `CITATION.cff` names the two data deposits and the preparation tool this
  analysis sits downstream of. It carries no `doi:` field yet, because a
  concept DOI does not exist until a release is archived.
- `PUBLISHING.md` is the runbook for the release itself.
- The two data deposits this analysis reads are cited by their version DOIs,
  `10.5281/zenodo.22051091` for the raw extract and `10.5281/zenodo.22051368`
  for the prepared files, rather than by the concept DOIs that follow the
  newest version. A run log pins its source by digest, so only a version
  record is guaranteed to still hold those bytes.

### Experimental

`mlos_review/`, the Python deck builder, ships as experimental and may stay
that way. It reads `results.json` and redoes none of the statistics. Its
caveats are in `README.md` and in full in `presentation_guide.md`.
