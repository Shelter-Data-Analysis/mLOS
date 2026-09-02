# mLOS Presentation Guide

*Note: This Markdown file is the documentation of record for the mLOS
presentation guide, version 20260902_001. Read it in any markdown reader,
Obsidian among them. The companion `presentation_guide.docx` is tracked here,
but it is rebuilt only for a release, so it carries the version it was built
from: where the two differ, this file is the current one and the Word copy
lags it.*

How the `mlos_review/` package turns a finished analysis into audience-facing
documents, and how to extend it.

This is a tentative document for a package that is part built. The design is
settled; roughly half of it exists. Sections describing code that does not
exist yet say so explicitly.

The package is experimental and may remain experimental. Read [What a deck is
worth](#what-a-deck-is-worth) before showing anyone one.

The four middle sections are written for four different readers. [Producing a
deck](#producing-a-deck) is for whoever runs the builder, [The deck, slide by
slide](#the-deck-slide-by-slide) for whoever receives one, [What the deck
decides](#what-the-deck-decides) for whoever has to defend a line on a slide,
and [Extending the package](#extending-the-package) for whoever changes the
code. Nothing in the last one is needed to read a deck or to build one.

## Table of contents

- [What this is](#what-this-is)
- [What a deck is worth](#what-a-deck-is-worth)
- [Producing a deck](#producing-a-deck)
  - [Running it, and what it writes](#running-it-and-what-it-writes)
  - [Settings](#settings)
  - [Checking a deck before it is shown](#checking-a-deck-before-it-is-shown)
  - [Checking that the wording is complete](#checking-that-the-wording-is-complete)
  - [Worked examples, and which run they come from](#worked-examples-and-which-run-they-come-from)
  - [What you cannot do yet](#what-you-cannot-do-yet)
- [The deck, slide by slide](#the-deck-slide-by-slide)
  - [The two opening slides](#the-two-opening-slides)
  - [Length of stay, per stratifier](#length-of-stay-per-stratifier)
  - [What the residents still owe](#what-the-residents-still-owe)
  - [The three workload slides](#the-three-workload-slides)
  - [Hazard ratios, then length-of-stay ratios](#hazard-ratios-then-length-of-stay-ratios)
  - [The competing-risks run](#the-competing-risks-run)
  - [Closing sections](#closing-sections)
  - [Educational](#educational)
  - [Speaker notes](#speaker-notes)
  - [The file you get](#the-file-you-get)
- [What the deck decides](#what-the-deck-decides)
  - [The opening summary](#the-opening-summary)
  - [Observation gaps](#observation-gaps)
  - [The measures a slide leads with](#the-measures-a-slide-leads-with)
  - [High, low, and flat](#high-low-and-flat)
  - [Which levels a table shows](#which-levels-a-table-shows)
  - [The competing-risk tables](#the-competing-risk-tables)
  - [Caveats the data triggers](#caveats-the-data-triggers)
  - [When the deck says nothing](#when-the-deck-says-nothing)
  - [Findings](#findings)
  - [Recommendations](#recommendations)
  - [Salience](#salience)
  - [The salience threshold](#the-salience-threshold)
  - [Every threshold in one place](#every-threshold-in-one-place)
- [Extending the package](#extending-the-package)
  - [Where it sits](#where-it-sits)
  - [Reading the bundle](#reading-the-bundle)
  - [The regression frames](#the-regression-frames)
  - [Display names](#display-names)
  - [Content blocks](#content-blocks)
  - [Slide rules](#slide-rules)
  - [The deck plan](#the-deck-plan)
  - [Figures this package draws](#figures-this-package-draws)
  - [Renderers](#renderers)
  - [Everything a build writes](#everything-a-build-writes)
  - [Invariants](#invariants)
  - [Running the pieces](#running-the-pieces)
- [Design decisions and why](#design-decisions-and-why)
- [Known gaps](#known-gaps)

---

## What this is

The R analysis, upstream from this package, does length-of-stay (LOS)
computations on shelter data and writes `results/results.json`, a complete
record of every reported number, with plots and companion CSVs beside it. The
presentation builder reads the JSON and the plots it names, and nothing else.
It does not import R, it does not open the R-produced workbook, and it does
not recompute a statistic. Everything it shows has already been computed once,
cross-checked by the test suite, and written out.

The intended outputs, in the order they are being built:

| Output | Status |
|---|---|
| Slide deck (`.pptx`) | example deck working |
| Workbook of every table the slide deck build made | working |
| Text report with inset figures and tables | designed, not built |
| Audience-tailored spreadsheets | designed, not built |

All of them read the same content blocks. That is the reason for the
architecture: a table built once can be drawn on a slide, written into a
report, or written into a worksheet, and only the last step differs. The
workbook is the first proof of it, containing the same blocks the deck uses
with a different last step and needing no additional information.

Throughout this document, **workbook** means the one generated here, not
`analysis_results.xlsx`, the results workbook R writes upstream. Where that one
is meant it is named.

**This package does not do any sophisticated statistics.** It only does simple
spreadsheet computations that use the statistical results at hand. The package
uses KM and AJ derived time-axis plots produced by the R code. It does not
draw its own plots of those types. It draws only the kinds of ordinary
comparison figures a casual spreadsheet user could draw. Model fitting and
survival curves are R's, on the other side of `results.json`. The two
[invariants](#invariants) say where that line falls and why.

---

## What a deck is worth

The package is experimental, and it may stay experimental. A document that
decides what to say is harder to get right than a document that reports what
it was given. This package uses rules and thresholds, and that approach may
not be enough. If you pass a deck along, pass the warnings in this section
along with it.

**Correctness is the part being tested, and it is the easy part.** The test
suite checks that every figure on a slide is the number the analysis wrote for
it, that the surrounding wording matches the number it sits beside, that a
comparison declines rather than guesses when the bundle cannot support it, and
that nothing runs off the page. All of that is worth having, but it is not
enough to make a deck a good briefing. A deck can be arithmetically faultless
and aesthetically pleasing, and still be the wrong set of slides.

**The findings may not be consistently interesting.** Which findings reach a
slide is decided by hardcoded rules against fixed thresholds. Nothing weighs a
result against the question a reader actually has, and nothing recognizes that
a run was uneventful: slides are produced either way. A difference that clears
a threshold is shown, but it may or may not matter. Where the selection is
closest to reasoned is documented under [What the deck
decides](#what-the-deck-decides) and in the findings blocks generated along
with the slides. Read those as the current
state of an argument, not as a settled method.

**Findings that matter may be omitted, and the omissions are not visible.** A
deck is a selection and is never a summary. A stratifier no rule looks for, or
a measure no slide has room for, is dropped without a trace. An effect the
analysis found and the plots show can simply fail to appear in the deck. The
workbook the build writes beside the deck holds the tables made along the way,
including the rows the slides had no room for, which recovers some of this but
not all of it. **A finding's absence from a deck is not evidence that it is
absent from the data.** The JSON file and the plots remain the complete
record. The Excel workbook R writes holds more than the deck's workbook does,
and still less than the JSON.

The practical reading: a generated deck is **raw material for a briefing**
somebody writes, and is not itself the briefing. Check it against the JSON and
`analysis_results.xlsx` before it reaches an audience, and expect to add what
it left out.

---

## Producing a deck

*For whoever runs the builder. What a build writes, what the settings
change, and what to check before a deck reaches anybody.*

**This is not yet ready for routine use.** A handful of slide types exist, the
settings file covers output, flag style, emphasis, and competing-risk coverage,
and the sequence they appear in is hardcoded rather than planned. What follows
is enough to look at what it produces.

### Running it, and what it writes

A deck built from the shipped OC2 settings is deposited at
[10.5281/zenodo.22135419](https://doi.org/10.5281/zenodo.22135419), with its
table workbook, its figures, and the settings file it was built under, so the
output described below can be read without running anything. That deposit is
derived from the results deposit rather than standing on its own, and the
caveats above apply to it exactly as they apply to a deck built here.

After a normal analysis run, from the repository root:

```bash
python3 -m mlos_review.deck
```

That reads `results/`, takes its settings from `data/OC_deck_settings.yaml`,
and writes four things into `reports/`, which is created if needed and is not
tracked by git:

- `mlos_deck.pptx`, the deck;
- `mlos_deck_tables.xlsx`, every table the build made, including the rows the
  slides had no room for;
- `mlos_deck_figures/*.png`, every figure this package drew;
- `mlos_deck_figures/manifest.json`, saying what those PNGs are.

The companions are named after the deck file rather than after the directory
holding it, so a second deck built beside the first keeps its own workbook and
its own figures. Building `mlos_deck_OC1.pptx` next to `mlos_deck.pptx` gives
you `mlos_deck_OC1_tables.xlsx` and `mlos_deck_OC1_figures/`.

**A deck is never overwritten, and neither is the workbook.** One already at
either name is renamed to `<stem>_<YYYYMMDD>_<NNN>` first, the same scheme
`results/` uses to archive an earlier run, so the plain name always holds the
most recent and older ones stay beside it. Nothing is deleted. The figures are
the exception and are simply redrawn, because the deck embeds its images, so
an archived deck keeps the ones it was built with.

### Settings

The settings file uses the same YAML syntax and the same extension as the
analysis settings beside it; `data/OC_deck_settings.yaml` is the example.
Every key has a default, so anything you delete falls back; an unrecognized
key or an out-of-range value is refused rather than ignored, to avoid
typo-induced errors. The command line holds itself to the same rule: an
unrecognized `--flag`, or `--settings` without its `=FILE`, is refused rather
than silently run past.

| Setting | Values | Effect today |
|---|---|---|
| `output.directory`, `output.filename` | paths | yes |
| `tables.high_low_flag` | `MARK`, `COLOR` | yes |
| `emphasis.<stratifier>` | `AUTO`, `ALWAYS`, `NEVER`, or a list of levels | all four, for the one decision salience currently drives |
| `aj_coverage` | `FULL`, `TEASER`, `NONE` | yes; `TEASER` carries the whole-sample slide and one stratifier's, `FULL` carries every stratifier's |
| `figures.ratio_log_scale` | yes, no | yes; the log x axis on the two ratio figures |
| `template` | path to a one-slide `.pptx` | yes, on the slides that have room for it |

A template is branding, not a layout: its slide carries artwork and nothing
else, and the renderer copies that artwork onto the slides it fits. The band
left free is measured from where the artwork sits, so a header, a footer strip
of logos or both are read as what they are. A slide carrying a figure is left
plain, the figures being opaque and sized to whatever the body leaves them, and
so is a slide whose content is taller than the band at any bullet size. On the
OC2 deck twenty-one of the fifty-two slides are branded: the closing findings,
the recommendations, the section openers, three of the four table slides, and
the educational slide that carries the observation-window diagram.

A slide that does not fit at eighteen point is measured again at sixteen and at
fourteen, and takes the artwork at the largest size that fits. The alternative
is a slide that loses the branding its neighbours have over a quarter of an
inch. On OC2 one slide steps down.

`Slide.schematic` is how the diagram slide qualifies at all. It says the
figures are drawn to be recognized rather than measured, so room taken from
them costs nothing; the rule that builds the slide sets it, since what a figure
is showing is the rule's to say. It applies where the figure sits beside the
text rather than under it, which on the TITLE layout it does: what the figure
gives up is width it can spare, and under a list it would be giving up the
height it is read in. On OC2 the diagram goes from 6.17 by 4.16 inches to 6.11
by 4.12.

The template sets the page's color scheme and has to be the same page size,
13.333 by 7.5 inches. Type stays Calibri, which is what the column widths and
the page breaks are measured in; a wider face wraps a table header mid-word.

`--template=FILE` overrides whatever the settings file says, and is how a
template that lives outside the repository is used without writing a machine's
own paths into a tracked file. It is the setting most worth a flag: a template
belongs to the occasion rather than to the dataset, so the same analysis goes
branded to one audience and plain to another. Give the branded build its own
output name, `reports/mlos_deck_with_template.pptx` say, and its workbook and
figures follow that name rather than displacing the plain deck's.

`emphasis` is one map keyed by stratifier rather than one key per stratifier.
To wire a fourth stratifier, add it to `STRATIFIER_KEYS` in `settings.py`,
which maps the words a settings file uses onto the bundle's internal ids. A
stratifier the analysis grows reaches the deck on its own, but naming it in
`emphasis` before that map knows it is refused as an unrecognized stratifier.
Its values are words rather than booleans because there are three states:
`AUTO` is the common case, and booleans are accepted as synonyms for `ALWAYS`
and `NEVER`.

What a stratifier being salient buys today is a second slide: the
resident-outlook slide, what its levels' animals already in care still owe,
immediately after its LOS slide. Every stratifier gets the
LOS slide, since a deck that splits by a dimension has to show it;
the outlook question is asked only of the dimensions deemed salient.

`ALWAYS` and `NEVER` answer that outright. Under `AUTO` the data answers: a
stratifier is salient when its levels' average stays are more than a day, plus
15% of the shelter's average stay, apart, after the part of that spread which
is sampling noise has been taken out. Every LOS slide reports the number in
its speaker notes, with the threshold and the verdict, whichever way it came
out and whether or not a setting overrode it. The arithmetic, and what the
noise correction is doing, is under [Salience](#salience).

**On a dataset with one stratifier, an unstated stratifier defaults to
`ALWAYS`.** `AUTO` means "let the findings decide", and deciding is a
comparison: rank the analysis dimensions and spend the deck on the ones that
separate the data. With a single dimension there is nothing to rank it against,
so it is treated as salient rather than left waiting for a comparison it cannot
lose. What moves is the default. A file that writes `AUTO`
against that stratifier has said what it wants, and `NEVER` means it whatever
else the dataset holds; both are honoured exactly as written.

Naming levels implies `ALWAYS`, since asking for particular levels and then
leaving their appearance to chance is not a coherent request. Pinned levels
**join** the selectors rather than replacing them, so pinning what you care
about cannot hide what the data says is remarkable. A pinned level this dataset
lacks is warned about and skipped, not fatal: one settings file gets reused
across runs, and a filtered dataset explains an absent level as readily as a
typo does.

### Checking a deck before it is shown

A build that succeeds is not a deck that is ready. [What a deck is
worth](#what-a-deck-is-worth) says why. Four checks, in order:

1. **Read "Where to look next".** It names the settings this run's own numbers
   suggest changing, and a run that produced one is usually worth doing again
   before the deck is shown rather than after.
2. **Read the speaker notes.** Every data-conditional caveat is there and
   nowhere else: the observation-gap scan, whether the stay cap is shaping the
   tenure figures, whether the three marks rank the levels alike, and each
   stratifier's salience number against the threshold.
3. **Look for what is missing.** A deck is a selection, and a selection leaves
   no trace of what it dropped. `mlos_deck_tables.xlsx` holds the rows the
   slides had no room for, `analysis_results.xlsx` holds more than that, and
   `results.json` holds everything. A finding's absence from a deck is not
   evidence that it is absent from the data.
4. **Check the wording and the numbers**, with the two commands in the
   sections below.

### Checking that the wording is complete

Every machine name the deck might print has to be translated into words. To
see whether any name is falling through to the automatic fallback:

```bash
python3 -m mlos_review
```

It prints how many names were covered by the curated table and lists any that
were not. An empty list is the healthy state. A name appearing there means the
deck will print a mechanically de-underscored version of the machine name
until someone writes a better phrase for it.

### Worked examples, and which run they come from

Numbers quoted below to show a rule working are marked **OC1** or **OC2**,
naming the Orange County dataset they were read off. OC2 is the default since
2026-08-01; OC1 is the dataset most of this document was written against, and
its examples are kept as they are rather than half-converted, so that every
figure here belongs to a run that actually produced it.

**A figure that holds on both names both** — "on OC1 and OC2" — rather than
saying "on either run" or "on the Orange County data". The wording matters
because those two forms quantify over the set of Orange County runs, and that
set can grow: an OC3 would silently inherit a claim nobody checked against it,
where naming OC1 and OC2 stays true whatever arrives later. 

Both runs are reproducible from tracked inputs, which is what makes a marked
number checkable rather than merely dated:

```bash
Rscript mlos_run_complete.R --data data/OC1_data.csv \
    --settings data/OC1_settings.yaml --results results/OC1
python3 -m mlos_review.deck results/OC1 reports/mlos_deck_OC1.pptx
```

Drop the three arguments for OC2, which is what the defaults name. Neither
`results/` nor `reports/` is tracked, and a deck's workbook and figures are
named after the deck file, so an OC1 run and its deck can sit beside the
current ones indefinitely without a mix-up in the companion files.

To check the marks rather than take them on trust:

```bash
python3 tests/show_guide_examples.py results/OC1
```

It reads the dataset out of the run's own provenance, prints every example
this document marks with that tag beside what the run now says, and names the
ones that have parted. These numbers are expected to move when a dataset or a
threshold does. When it reports a difference, fix this document and the
expected value in that file together.

A number not marked to an example is fixed by the code (a slide dimension, a
threshold, a column count) or read off the test fixtures, and does not move
when a dataset does.

### What you cannot do yet

Detail level, figures-versus-bullets balance, mathematical sophistication, and
the slide budget are designed and unimplemented. The slide sequence is fixed
in code rather than planned against a budget. There is no text-centered
report. The workbook is not an independent product; it just holds the tables
the slide deck build made.

---

## The deck, slide by slide

*For whoever receives a deck, or presents one. What each slide shows and
how to read it. Why a slide says what it says is under [What the deck
decides](#what-the-deck-decides).*

The deck often talks about **an average day or an average resident, not a
specific date or animal.** Every resident figure in the deck (census, tenure
profile, days still owed) is a steady-state average implied by the observed
arrival rate and LOS, not a count taken on any particular date. The
study window has usually closed by the time anyone reads the deck, so
"today's" numbers are not in the data at all, and even for a date inside it
the figure is a fitted average rather than a snapshot.

### The two opening slides

The deck opens on a **title slide** carrying the study window and its periods,
a diagram of what a study window sees of a stay, and one footnote giving two
timestamps: when the statistics were computed, and when the deck was built
from them. The diagram is the four cases the analysis has to handle: a stay
observed whole, one already in care when the window opened (left-truncated),
one still in care when it closed (right-censored), and one that is both. It is
not a finding, it is the methodology every later number relies on. A slide of
**descriptive summary** follows: the size of the sample, how its stays were
recorded as ending, and how they fall across the fields the analysis splits
by, in up to three small tables side by side.

**Both opening slides close their notes with the [observation-gap
scan](#observation-gaps)**, the
periods on the first and the pooled data and the fields on the second. A gap
is a stretch of days no stay was under observation for, and the curve is not
estimable across one. A clean run says so, which is the one caveat in the deck
that speaks either way. A gap inside the plotted range is named with its level
and its days, and one past the plot cap is mentioned in a line, since no
figure in the deck reaches it and what it still costs is the restricted means.

### Length of stay, per stratifier

Then comes an LOS slide for the whole sample, then per usable
stratifier: the Kaplan-Meier curves on the left, the in-care tenure profile on
the right, and a highlights table underneath. The whole sample has only a
single row of numbers, being the baseline every later slide splits. Which
levels the table carries is under [Which levels a table
shows](#which-levels-a-table-shows).

**Where the three marks rank two levels differently**, one ahead on the median
and behind on the P90, say, the speaker notes name the pairs and work one of
them through with its numbers. It is the caution against saying "this group
stays longer" without specifying the metric. A level with the higher median
and the lower P90 has a middle section sitting at higher LOS but a lighter
tail. Specify the metric, unless they all point in the same direction.
Differences under a day count as ties, so a pair is named only where the
reversal is real.

### What the residents still owe

The whole sample has a second slide, and so does any stratifier the settings
mark salient. This second slide is built to the same shape as the slide before
it, with two figures side by side: the **census by tenure** and the
**remaining-LOS** curve. The first tells you the expected number of animals in
care at exactly that tenure; the second what an animal still owes as a
function of that tenure.

The two figures are the two factors in a multiplication: future care demand is
the residents at each tenure times the days each still owes, summed. The
in-care tenure profile is that curve integrated, and a cumulative form is not
what multiplies the one beside it. The census figure also starts at the daily
intake rate and encloses the expected census, neither of which a probability
axis can show.

**The stratified version carries no marks**, and its notes say so: each level
has its own three tenure statistics, and a full set per curve would be
unreadable on one panel. The numbers are read off the table instead, a row per
level listing that level's median, mean, and P90 tenure with what its own
remaining-LOS curve reads at each.

Its rows are the rows of the slide before it, chosen by the same selectors, so
the pair reads as one statement about the same levels. Stratified, the census
curves are in animals rather than in each level's own fraction, so at each
tenure their heights divide that day's residents between the levels, and the
area under one is that level's expected census.

The tables of the two slides in each pair are **views of one table**, sliced
rather than built separately, so they cannot disagree. The entire table (each
metric in one column) goes into the workbook, where a single sheet holds the
whole sample and then the levels of each stratifier, stacked.

### The three workload slides

The LOS section then turns the durations into a quantity, over
three slides that build on each other. Each slide treats the stratifiers side
by side, because comparison is useful across axes.

The first asks who is in care: each level's share of the arrivals, then the
animals it has in care on an average day, counted and fitted, with the counted
share beside it. (The by-period table skips the share percentages, because
periods don't coexist.) The second asks how long the average resident has been
in care, counted and fitted, and how many days that resident still has to
come. The third slide multiplies the two: animal-days on an average day,
counted and fitted, and the forward days owed beside them.

Each of the three slides carries a subtitle above its tables: the broad
insight the slide exists to support. Longer-staying categories are
over-represented in the census against intake; future and past per-resident
stays are related at steady state; longer-staying categories dominate the
animal-days the current residents are committed to.

**The animal-days tables footnote the level holding most of the days owed**,
since there is no room for a share column: "LARGE holds 93% of the days owed".
A period table says instead that each period's figure is its own commitment,
since periods don't coexist to share a population.

**A table showing more than ten levels does not fit under a subtitle**, so
the slide keeps the ten largest by its counted column and footnotes how many
it left out. The footnote says the shares stay *shares of the whole* and so no
longer add to 100%.

**The multiplication is exact.** Residents times tenure per resident is
animal-days, on the counted side and the fitted side alike, by construction in
`.census_aggregate_matrix`. So the third slide is the first two multiplied,
and a gap between counted and fitted there is the two earlier gaps compounded
rather than a third piece of evidence. The test suite checks the identity on
every fixture, to catch a slide reading the wrong column.

**Every one of the three pairs a counted column with a fitted one**, holding
the model against the data, by which point the audience has taken four slides
of KM-implied figures on trust. Where they agree, which they mostly do, the
agreement gets a finding of its own: the survival curves reproduce the
population the data actually held. Where they part, the fitted side is the one
assuming the intake rate and the LOS pattern have been stable long
enough to settle. A level counted above its fitted figure was carrying more
than its own steady state would hold, the long stays of a busier past still in
the building; counted below, it was still filling up behind a rise. It is a
dynamic reading in a deck that usually looks at steady state, and it is
clearest by period where the regimes actually differ. The fitted side is
capped at the stay cap and the counted side is not. On OC2 the gaps are
uneven: the two censuses agree within 4%, the tenures part by 14% on Early-C,
and the animal-days by 13% on Late-C.

**Two exact identities carry a bullet each.** On the second slide's last two
columns: what a resident still has to come is what it has already served plus
exactly one day, on every level, always. In a population at steady state, time
served and time still to come have the same distribution, and the extra day is
the day the animal is having. On the third slide, days owed minus animal-days
elapsed is the census, which is the same fact multiplied out.

**The first slide's own reading is between the levels**, not between the
columns. A level's share of the residents over its share of the arrivals is
its mean stay over the shelter's, so a level that is 38% of the arrivals and
70% of the residents has stays about twice the shelter's average. That is
heterogeneity *between* levels. The whole-sample slide sees this from the other
side: two groups each perfectly memoryless but at different rates pool into a
heavy-tailed distribution, because early on the fast group is leaving and what
is left later is increasingly the slow one. Mixing populations produces a
falling hazard on its own. The same arithmetic appears again on the third
slide, where a level's share of the days owed over its share of the residents
is its mean tenure over the shelter's.

**Periods carry days owed but no shares.** A day of care falls in exactly one
period, so the elapsed days divide cleanly, but days owed belongs to the
population standing in the building at one moment, and periods divide the
calendar rather than that population. Each period's figure is its own
commitment, worth comparing across the periods but not part of any total.

The study-window animal-day total goes to the workbook rather than to a slide.
It is the counted census times the length of the window, so beside the census
it would put a second scale of the same quantity, and read against the days
owed it would invite "we are nearly done".

### Hazard ratios, then length-of-stay ratios

The LOS section closes with two runs of slides, all of the
stratifiers' hazard ratios and then all of their LOS ratios. Hazard ratios
compare rates, LOS ratios compare durations.

**The order is the argument.** The hazard-ratio run settles the model choice:
two genuinely different estimators sit beside a parametric one, and the
question is whether the Weibull's form is making the answer. Only then are the
LOS slides worth reading, their leading column being that same Weibull
expressed in days. Ending on length of stay also ends in the audience's own
vocabulary rather than the estimator's.

Each slide holds three estimates
per level, dots with 95% intervals on the left and the estimates alone in a
table
on the right.

**Whether the bridge holds is a generated finding**.
Each hazard-ratio slide reports how far its Weibull column sits from its Cox
one, in proportion, and whether the two intervals overlap. On OC2 it holds for
period, where the Weibull tracks the Cox within 4%, and fails for animal
group, where LARGE parts by 24% and the intervals do not meet: that level's
time ratio on the slide that follows is partly a statement about the assumed
shape, and the Kaplan-Meier column beside it is the check, assuming nothing
and reading straight off the curves the presentation leads with. Intake type
sits between, parting by 10% on RET with the intervals still overlapping.

The hazard-ratio slide carries the pooled Cox, the stratified Cox, and the
pooled Weibull. The first two differ in what they assume about everything
else, one shared baseline hazard against a baseline per combination of the
other splits; the third imposes a shared Weibull baseline, so where
it parts company the parametric shape is not fitting the shelter data.

The LOS slide carries the pooled Weibull time ratio, the freed-shape
Weibull's, and the ratio of Kaplan-Meier restricted means. The last adjusts
for nothing: it is built from the Kaplan-Meier restricted means the earlier
slides showed. The gap between it and the two beside it shows how much of what
those slides showed was the mix of the other dimensions, since the splits are
not independent and a level can look long simply because it is full of animals
that are long for another reason. On OC2 the Late-C period is 53% longer
unadjusted and 31% adjusted, and Early-C crosses over from level with Pre-C to
9% shorter.

**Two things the notes can say and the figures cannot.** The Weibull
hazard ratio and the Weibull time ratio are *one* estimate in two forms,
related by the fitted shape; they are the bridge between the two runs. And the
reference level affects every interval on both figures: one with few stays
widens every whisker at once, and one at an end of the stay distribution puts
every other level on the same side of 1. The reference is a setting, and left
unset it is the most frequent level, which handles the first and more
important of these. Among levels with enough stays behind them, a mid-range
one keeps the comparison two-sided as well.

Each estimate is a dot with its 95% interval. The reference level sits exactly
on the dashed line at 1 and carries no whiskers, which is what marks it as the
denominator rather than an estimate. [Figures this package
draws](#figures-this-package-draws) says why dots are used. The axis is linear
by default; `figures.ratio_log_scale` turns on the log axis that would draw 2
and 0.5 as the same size of effect.

A robustness check these two slides replaced, `cox_comparison_by_stratifier`,
is still built, and is kept after the closing sections, behind a page
separating it from the presentation. Nothing there is gathered into the
closing sections.

### The competing-risks run

The competing-risks section is controlled by `aj_coverage`: two whole-sample
slides, then a run of slides for one stratifier or for every one, and then a
closing section gathering what each found. `TEASER` is the default.

The whole-sample slide is a teaser and is built to answer the two questions the
method exists for, as two stacked figures over a table. On the left, cumulative
incidence: the probability a stay has ended each way by day X, stacked, so the
top of the bands is the chance of having left at all and the space above it the
chance of still being here. On the right, the same analysis read forward, the
outcome mix among the stays still in care on day X. Stacks rather than lines
because both questions are about shares of a whole, which is what bands show
and lines only imply. It carries no per-stratum breakdown and no confidence
bounds, which is what makes it a teaser rather than the treatment. The line
versions of both figures are in the stratified slides.

**The second whole-sample slide turns the question on the animals in the
building.** Where the teaser is about stays from intake, this one is about
residents: how much longer an animal of a given tenure has to go, and which
way it is going to leave. Its figures are the two curves it is read off,
remaining stay and the conditional outcome mix, both against tenure. Its table
is a row per resident tenure, median, mean and P90, each with the remaining
stay and the outcome mix at that tenure. Every outcome column is conditional on
having reached the tenure, and `at cap` closes the row with the share still in
care when the analysis window ends. The mix comes from the bundle rather than
off the figure's grid, so a number and the line a reader would draw at that
tenure name the same day.

A stratifier's run, `aj_by_stratifier`, is a flip-book: one slide per outcome,
each holding that one outcome's cumulative incidence by level, against a table
that does not change as the panels do. Levels are compared *within* a panel,
which is the comparison the analysis supports; a plot holding outcomes and
levels at once supports neither. The notes say what the panels cannot: a high
final incidence is good for a live outcome and bad for a non-live one, so a
level sitting high on one panel is not doing better overall, and where two
levels finish level the one that got there sooner spent less time in care to do
it. The table beside them is the end state of the curves, where each level's
stays ended up and how long the ones that ended that way took.

Geometry, table, and footnote are identical across the run, and the figures are
identical in size because R draws them on one canvas with margins fixed in
lines rather than to content. So what changes when the presenter clicks is the
curves inside the frame, the outcome named after the colon in the title, and
which column the table's header points an arrow at. The frame does not move,
which emulates animation with three ordinary slides that behave identically in
PowerPoint, Keynote, Slides, and PDF.

The same finding about the stratifier rides on each slide in the animation.
The closing section de-dupes findings. If no AJ figures are emitted, the
section degrades to a single stacked slide carrying just the table, in the
same spirit as an LOS slide with its figures switched off.

`aj_coverage: TEASER` carries one stratified slide, chosen by
`aj_teaser_stratifier`. **Fewest levels wins**, since its figures are easier
to read. A stratifier the run drew no AJ figures for is not a candidate; a
stratifier with salience set to `NEVER` is not either. Ties go to the bundle's
stratifier order. `FULL` carries every stratifier's slide instead.

Either way the teaser slide is **built last and inserted first**, so the note
promising a breakdown is only written when there are slides to follow it.

### Closing sections

**The deck ends on two collected sections**, not one. **Findings** is what
the data said. **Where to look next** is what to do about it: one line per
recommendation the run's own numbers triggered, each naming the setting to
change or the data to fix. They are separate because they are different speech
acts, and an audience reading a single list cannot tell a finding from a
suggestion without a tag on every line. Most recommendation rules stay silent
on a healthy dataset, which is the point: on the twenty-eight test fixtures,
ten produce none at all. What each rule looks for is under
[Findings](#findings) and [Recommendations](#recommendations).

### Educational

**One section sits behind everything else**, including the robustness check,
and teaches a way of reading rather than reporting a result.

**An educational slide carries no findings and no recommendations.** The
section drops both from every slide it builds rather than asking each rule to
remember, so a rule added later cannot leak a sentence about method into a
summary of sentences about the shelter.

Two slides today, in this order.

**Looking at Length of Stay (LOS)** is an alternate opening. It asks how a
period's length of stay is computed at all, and carries the title slide's own
truncation diagram, because the answer is that a period sees whole stays and
also parts of stays that began before it or end after it. It cites the method
paper and the software release, and it is left deliberately unfilled: a figure
drawn from the data can take the space later. Always built.

**Working with Probabilities in Time Intervals** puts the two interval stacks
side by side over the two whole-sample tables, narrowed to what the picture can
be checked against. Its figures need `probability_mass_width` set in the
analysis settings; without it the slide is absent and the section is the opener
alone.

A bullet may sit one level in, which is what the opener's sub-lists use. Deeper
than one level is a document rather than a slide.

### Speaker notes

**Every slide carries speaker notes** explaining what its figures are, how to
read them, and what the numbers below them are restricted to. The notes end
with that slide's own findings and recommendations that are passed along to
the corresponding closing sections. A presenter talking through a slide can
see what it contributes, with numbers included from the slide's table. A run
of slides sharing one set of findings, which the competing-risk panels do,
hangs the set on every one of them; the closing sections de-duplicate.

### The file you get

The `.pptx` opens in PowerPoint, Keynote, LibreOffice Impress, and Google
Slides, and is fully editable. Nothing in it is a picture of a table; the
tables are real tables you can retype a number into.

**Tables do not break words.** A table that cannot be made
to fit is drawn wider than its box and hangs off the slide, where the eye can
see it; if there is still a problem, the fix is to reduce the number of
columns. The mechanics are under [Renderers](#renderers).

---

## What the deck decides

*For whoever has to defend a line on a slide. Which rows appear, which
numbers are marked, when the deck stays silent, and what every threshold
is set to.*

### The opening summary

Four tables and a pair of notes describing what was analyzed, i.e., the input
as the run narrowed it (not raw file statistics, which belong to data
preparation).  Also indicates whether a gap existed in the risk set.

| Block | What it holds | Where it lands |
|---|---|---|
| `study_window_table` | the window and its periods, with dates and day counts | the title slide |
| `sample_table` | stays, distinct animals, intakes, the cap, and the stays that ran past it, then the outcome tallies | the summary slide |
| `level_counts_table` | one field's levels, with their stays | the summary slide |
| `field_summary_table` | one row per field: level count, and the levels with the fewest and most stays | nowhere yet |
| `workload_table` | one stratifier's rows for one of the three workload questions: who is in care, how long they have been here, the animal-days that implies | each of the three workload slides |
| `window_gap_notes` | what the observation-gap scan found among the periods | the title slide's notes |
| `sample_gap_notes` | the same for the pooled data and each field | the summary slide's notes |

**Counts here are per stay, from the unified counts**, each stay counted once
however many periods it touches. The period-level counts elsewhere count a stay
once per period, which is what a per-period rate needs.

**The sample and its outcomes are one table**, because
the outcome tallies are counts over the same sample and a reader checking that
they add up should not have to look across tables. `Any` leads them,
carrying the analysis's own `completed_outcomes_total`. It is the one cell on
the slide with no share: its share is one by construction.

Its rows carry an outer index level, `Sample` over `Outcomes`. **The footnote
governs the second group only.** Three totals in the count column disagree:
intakes fall short of stays by the left-truncated ones, outcomes by the
right-censored. The footnote explains that second gap, so it governs the
outcome rows alone. The renderer writes a repeated outer label once, so the
grouping costs one narrow column.

**A field is enumerated only if it fits.** `level_counts_table` is built for
fields with no more levels than the run's own `max_plot_strata`, which is
already the user's judgment about how many levels fit on a picture. Past
that, the field is left off the slide.

`field_summary_table` is the block for the dataset where that starts costing
something: one row per field whatever its size, naming the levels with the
fewest and most stays. **No rule builds it today**, and it is kept the way
`QUADRANTS` is, with a fixture test calling it directly.

**The window drops its pooled row when there is one period**. What is kept is
the period, since its label is what the reader meets on every other slide.
Periods defined but never reached by a stay are left out throughout the deck.

### Observation gaps

An observation gap is a stretch of days below the stay cap with no stay under
observation at all, which left truncation makes possible: every stay at risk
resolved before the next entrant's tenure reached it. R scans for them, records
what it found in `unified.gaps`, and adjusts nothing, so a report is what makes
the finding reach anybody. `observation_gaps` reads that table;
`window_gap_notes` and `sample_gap_notes` are what the two opening slides call.

**The scan is reported on the slides that describe the data**, not with the
findings: a gap is a property of the window's coverage rather than of any
statistic computed inside it. The periods go on the title slide, which lists
them, and the pooled data and each field on the summary slide. The split is
taken as a complement, the periods being what the summary does not tally (see
`summary_fields`), so the two account for every analysis R scanned whatever
stratifiers a future bundle carries.

**This caveat speaks when it has nothing to report**, which is the one
departure from the rule below. A gap does not qualify a curve, it invalidates
it from that day onward, so "there are none" is a finding a presenter is
entitled to have been told rather than an absence they are left to infer.

**It will not claim a check that did not happen.** R scans a stratifier only
where it fitted one, so a single-period run leaves the title slide silent
rather than reporting a clean bill it has no scan behind. Nothing is lost: the
pooled scan always runs, and with one period it is that period's scan over the
same rows, reported on the slide that follows.

**Detail is spent where it can be acted on.** A gap starting below
`plot_stay_cap` is a hole in a curve the audience is looking at, so it is named
with its stratum and its days. A gap past that cap is in no figure in the deck,
so it is reported briefly: which levels, and where the first one starts, since
what it still costs is the restricted means, which run to the stay cap. Gaps
are recorded up to the stay cap and detailed up to the plot cap, so on **OC1**
the brief form covers days 60 to 365, which is exactly where a real gap is
likely to land: a small stratum's risk set thins far out in the tail, long
after the figures have stopped.

The join is by analysis *name*: R writes `Unified KM` and `KM by <label>`, and
the label is the key the bundle carries. The two R-side lists it comes from
agree on the words and not always on their case, so the match ignores case. An
analysis this package cannot place falls to the summary slide rather than being
dropped.

### The measures a slide leads with

`full_table` holds every level of one stratifier on the measures the deck leads
with: mean daily intakes, then three trios in one shape, median then mean then P90, then one
column that is none of them.

The trios are the LOS an arriving animal faces, the tenure an animal already
in care has served, and the further stay that animal expects, the last being
the remaining-LOS curve read at each tenure in the trio before it. Three
readings of one survival curve, in one order, so a reader who has learned to
scan one has learned to scan the others. Fraction still in care at the stay
cap and expected census sit between the first two trios.

The odd column is `per_resident_future_days`, the average remaining stay
*across* residents, and it goes last because it is what the trio before it is
most likely to be mistaken for. It is `per_resident_past_days` plus exactly
one day, while the reading at the mean tenure is a different and usually much
larger number. The whole-sample slide that shows both heads this one
"Remaining, resident mean", overriding the vocabulary, which is the one place
in the deck where a column name is written by the rule rather than looked up.

Thirteen columns is a sheet rather than a slide, so every slide takes a
`sub_table` of it: a column view carrying the same numbers, flags, and formats.
Flags are inherited rather than recomputed, for the reason `flag_extremes`
gives, and `LOS_SLIDE_MEASURES` and `OUTLOOK_SLIDE_MEASURES` name the two
halves.

Two columns are the fitted quantity rather than the observed tally beside it.
The at-cap column is `km_still_in_care_at_cap`, the fitted curve's terminal
value, not `fraction_capped`; the census column is `expected_census`, the
Little's-law figure the fitted curve implies, not `mean_census_inventory`.
With both in place the table is a single consistent view: everything on it
comes off the KM curve except the daily intakes, which are a count over the
observation window, and that is what the speaker note is able to say without
exceptions. Expected elapsed animal-days was dropped from this table; it is a
total-tenure quantity and belongs on a slide built around that.

The measures come from four different bundle matrices, so the block declares
which matrix each is drawn from and joins them. Flags are suppressed when there
is only one level, where "highest of one" would be noise.

### High, low, and flat

`flag_extremes` marks each column's highest and lowest values with `H` and `L`,
and marks every level `F` for flat when they all tie. Three properties matter.

**Judging is over every level, always.** A highlights table subsets the
result; it never recomputes flags on the rows it shows. Otherwise "H" would
quietly mean "highest of the four I happened to pick", which is both wrong and
invisible.

**Ties below the all-tied case are shared.** If three levels hold the maximum,
all three carry `H`. `extreme_levels` is the prose counterpart, so a sentence
under such a table names the same levels the marks do rather than one of them.

**`F` removes the need for a combined flag.** Because the all-tied case has
its own mark, no level is ever simultaneously highest and lowest, so there is
no `HL`. This matters more than it sounds: an all-tied median is common, and
without `F` a column of identical numbers would carry an arbitrary `H` and `L`
implying a difference that is not there.

### Which levels a table shows

`selected_levels` is the shared mechanism: up to a show-all limit every level
appears, and beyond it the levels holding the given selectors' superlatives are
taken as a union, in canonical order, with pinned levels joining rather than
replacing. The LOS and competing-risk tables both go through it, because
choosing rows is one decision rather than two; what differs between them is
which columns select and how many rows are worth showing, and those are
arguments. `_shown` then cuts a table down to those rows, carrying everything
that describes it (formats, headers, flags, row formats, the highlight column),
and writing the "n of m levels shown" footnote.

`highlights_table` is that applied to LOS: two to four levels are all shown,
and beyond that it selects the union of four superlatives, most intakes per
day, most residents on average, shortest restricted mean LOS, longest
restricted mean LOS.

**The union routinely yields fewer than four rows, and that is intended.** The
superlatives collide, because a group that fills the kennels is usually also
the one that stays longest. The highlights table is bait to send the reader to
the full table, not a complete picture. Fewer rows are not backfilled.

**Which superlative won a row is deliberately not shown.** It was proposed and
rejected as clutter.

**Rows appear in the stratifier's canonical level order**, never in the order
the selectors fired. The reader is comparing rows against each other and
against the same stratifier elsewhere in the deck, so an order that encoded the
selection criteria would read as a ranking it is not.

**A selector that cannot tell the levels apart does not pick a row.** If every
level has the same intake rate, "most intakes per day" is meaningless, and
`idxmax` would silently return whichever level sorts first, putting a row on
the slide and implying a superlative the data does not support. The test is
`separates`, one predicate used everywhere the question arises: a flag answers
it with `F`, a selector by picking nothing, a finding by saying nothing.

### The competing-risk tables

Every competing-risk table reports the same two measures per outcome: the share
at the stay cap, and the mean days to it. That mean is **conditional on the
outcome**, the average among the stays that end that way, which is why the
footnote says so; read as an unconditional mean it is badly wrong.

"Any" is left out of all of them. The shares already sum to it, and a mean time
to "any outcome" is better covered by the KM-based LOS tables.

`aj_levels_table` is the **master table**, in two senses. It is where the flags
are judged, because every column there holds one measure and an extreme
compares shares with shares and days with days; everything downstream
extracts and reshapes. It is the shape the **companion Excel
sheets are built from**; the slide arrangements are
subsets and transpositions of exactly that.

Its arrangement is **one row per level**, every share and then every mean-days
metric, each column headed by its outcome code and the vocabulary's short name
for the measure: `L share`, `L days`. Columns keep their real bundle names,
`aj_final_cif_L` and so on, and only the printed header is composed, through
`Table.headers`; a renderer that wants the full wording still has the measure
key.

Flags are the usual ones, judged across every level and suppressed for a single
level, exactly as in `full_table`.

`aj_teaser_table` is the block for `all`, the whole-sample (one level)
stratifier.

`aj_highlights_table` selects **by time rather than share**. Six
levels or fewer are all shown; above that, the levels holding the longest and
the shortest mean time to each outcome join a union, in canonical order. The
figures above the table are cumulative incidence curves, so a level with a
remarkable share is already the line the eye goes to; how long that share takes
to accumulate is what the reader cannot get off the plot at a glance. Six
rather than the LOS tables' four because these rows are shorter to read.

`aj_outcome_table` is the upright arrangement of the same numbers, one row per
outcome over the whole sample. No slide uses it. It is kept because it is the
shape a reader wants wherever outcomes rather than levels are the focus.

**No table carries confidence bounds.** A slide table of six
columns has no room for eighteen, and a reader who needs the interval is
better served by the bundle or by `analysis_results.xlsx`.

The AJ window in `aj_window_notes` is the
last fitted time, capped at the stay cap, a property of a level's own
data: on **OC2**, MED's curve ends at day 132 where LARGE's runs to 365. The
note names those levels, and says that this is **not** a distortion. Past its
window a level has nobody left under observation, so its shares are final
rather than cut short and they compare with a longer-running level's on the
same terms. It would matter for a window-sensitive quantity such as RMTL,
which the deck does not report.

### Caveats the data triggers

Some caveats belong on a slide only where the numbers put them there, and the
block that holds the numbers is what decides.

**A data-conditional caveat belongs in the block layer, not in the slide
rule.** The cap
sensitivity note (`cap_sensitivity_notes`) sets the
pattern. Whether a level's tenure figures are trustworthy is a fact about that
level's KM curve, so the function that knows the numbers decides. It returns
an empty list when the cap does not bind. Two further rules it establishes:
judge across every level rather than the rows the highlights table chose, and
name the worst offender first.

`order_shift_notes` follows the pattern exactly. It
compares every pair of levels on the three marks one figure carries, the
median, the mean, and the P90, and speaks only about the pairs whose ranks
vary by mark, suggesting a change in shape. A note per figure, if any are
found.

**A difference under a day is no difference.** `ORDER_SHIFT_TOLERANCE` is 1.0
and is applied to each difference before any sign is read. One number covers
two cases that want the same treatment: the median and the P90 are read off a
step function on a grid of whole days, so anything under a day there is
already a tie. The restricted mean is an integral over that grid and is not a
whole number, so the same threshold treats a fraction of a day as no
difference.

**A mark one level has no value for is dropped from that pair**, not the pair
from the comparison. An unreached P90 is common and leaves the median and the
mean perfectly comparable; what it cannot do is produce a shift on its own,
since a shift needs two marks pointing opposite ways.

**The leading pair is the deepest reversal, measured by its smaller side.** A
pair three days ahead on one mark and forty behind on another is treated as
crossing by three. The leading pair is the one the note spells out with
numbers, so it should be the one where the crossing is starkest.

The observation-gap notes are the deliberate exception to the silence rule. A
cap caveat qualifies a number the audience can still read; a gap means there
is no number to read past that day, so the scan reports either way and a
presenter never has to wonder whether it ran. It only stays silent for a scan
that did not happen: see [Observation gaps](#observation-gaps).

### When the deck says nothing

Silence is a result. A statement reaches a slide only where the data can tell
the levels apart, and `separates` is the one predicate that decides it: a flag
answers by marking every level `F`, a selector by picking no row, a finding by
saying nothing. Naming one of two identical levels as the highest would be
false, and `idxmax` would do it silently.

Where that lands:

- **Flags.** All levels tied is its own mark, so no column carries an arbitrary
  `H` and `L` over identical numbers. See [High, low, and
  flat](#high-low-and-flat).
- **Selectors.** A superlative no level holds alone puts no row on a slide. See
  [Which levels a table shows](#which-levels-a-table-shows).
- **Findings.** Nothing is said for a stratifier with one level, or where LOS
  is flat across levels. Past `MAX_TIED_LEVELS` an extreme is not named at all,
  and the two ends abstain independently.
- **Numbers too small to state.** The committed-workload sentence abstains
  below what it can carry, since a fitted census of 0.4 animals owing 1.2 days
  reads as nonsense rather than as a small number.
- **Recommendations.** Silent by default: one that fires on every deck stops
  being read. On the twenty-eight test fixtures, ten produce none at all.
- **Shape.** One crossed Weibull variant silences the shape recommendation for
  the whole run, rather than leaving it resting on whichever variants stayed
  additive. See [Recommendations](#recommendations).

**The observation-gap scan is the deliberate exception.** A cap caveat
qualifies a number the audience can still read, where a gap means there is no
number to read past that day, so the scan reports either way and a presenter
never has to wonder whether it ran. See [Observation gaps](#observation-gaps).

### Findings

Each slide carries a list of finished sentences that **do not appear on it**.
The deck collects them into a closing section, so the summary is assembled from
what the sections found rather than written separately and left to drift. A
section rather than one slide: the bullets are paginated against the slide
height and continue onto "Findings, continued" rather than running off the
bottom. Nothing gathered is ever dropped, reordered, or split mid-sentence.

A slide footnote and a speaker note are not the same length of sentence. The
footnote says what would be misread without it and stops; the careful version
goes to the notes. The competing-risk pair is the example: the footnote says
mean days is the average duration of stays with that outcome, and the note adds
that it is conditional on the outcome and badly wrong read any other way.

Findings carry their numbers: "Among animal group levels, LRG has the
longest average stay at 31 days, and the largest share of residents at 67%."
(**OC1**.)
Usually there is one per slide, sometimes two, sometimes none. Nothing is said
when a stratifier has one level, or when LOS is flat across levels,
since "the longest of several identical values" is not a finding.

Which slide contributes what, in the order they reach the closing section:

| Slide | Finding |
|---|---|
| Title | a curve the deck plots is not estimable, where an observation gap starts inside the plot cap |
| Whole-sample LOS | the arrival and resident medians read against each other, then which stratifier separates stays furthest |
| Whole-sample outlook | how long the middle resident has been here and how much longer it expects |
| LOS by stratifier | the longest average stay and the largest census share, then whether the three marks rank the levels alike |
| Outlook by stratifier | which levels' residents are furthest from leaving and which nearest |
| Workload | the shelter's committed animal-days, and the level carrying them where one does |
| Hazard ratios by stratifier | whether the Weibull column tracks the Cox one, and whether the hazard ratios survive a freer baseline |
| Competing risks | the sweep, then time to outcome per outcome type, then the widest timing gap between levels and the widest inside one |

Three of those are conditional on more than the numbers being present.

**The gap finding fires only inside the plot cap.** Past it no figure crosses
the gap and the opening notes already report it. Inside it, the sentence is
made whatever else the deck found: a curve the audience looked at cannot be
read past a day. It rides the title slide, the one slide that always exists,
and leads the closing section, which is where a sentence qualifying everything
after it belongs.

**The burden-carrier finding** (`burden_carrier`) **fires only where a level
carries the load**:
more than half the days owed, and a larger share of them than of the residents
who owe them. Both, because either alone says nothing. A majority on its own is
usually the biggest level being biggest, which is on the slide already; a
disproportion on its own can be 3% of the residents holding 5% of the days. On
**OC2**, animal group qualifies (LARGE at 93% of the days owed against 70% of
the residents) and intake type does not (STRAY at 60% against a 64% census
share).

**The outcome timings are read along both axes**, as two findings, one per
stratifier each. `findings_for_outcome_spread` reads *down* a column, comparing
the levels against each other on one outcome, and names the outcome that
separates them most. `findings_for_outcome_contrast` reads *across* a row,
comparing one level's outcomes against each other, and names the level whose
own outcomes differ most: on OC2, OTH's other-live outcomes take 4.5 times as
long as its community-live ones, which no comparison between levels would
show and which an average over OTH's stays hides completely. Both read the
same frame, `_outcome_timings`, so a cell too thin to average is too thin
either way.

One per stratifier rather than one per outcome or level, since the closing
section takes a bullet per contribution. The sentence beside it already gives
the slowest and fastest level of every outcome; what this adds is the multiple
and which outcome carries it. `OUTCOME_SPREAD_MULTIPLE` is 2.0 for both, the
point at which "somewhat longer" stops describing a gap.

**It ignores levels with fewer than `OUTCOME_SPREAD_MINIMUM_EVENTS` of that
outcome.** Without the floor the widest ratio is almost always the smallest
level's: on OC2 it is `_UNKNOWN_`'s time to a non-live outcome, over twenty of
them. With the floor the animal-group finding is LARGE against PUPPY, a
nineteenfold gap over hundreds of events each.

**The committed-workload sentence abstains below what it can state.** Both its
numbers are fitted, so a small enough dataset produces a real census of 0.4
animals owing 1.2 days, and rounded into a sentence that is a claim about a
shelter, that reads as nonsense rather than as a small number. The
animal-years clause goes the same way on its own account: it exists to make a
large number graspable and is dropped rather than printing "some 0
animal-years".

### Recommendations

`recommend.py`, gathered like findings and displayed after them as "Where to
look next". **A recommendation is not a finding.** A finding reports what
the data said. A recommendation suggests new runs to learn more, and it names
the knob, the analysis setting to alter or the data to fix.

**The kind is a field, not a tag in the text.** `Slide.recommendations` sits
beside `Slide.findings`. Two fields rather than one list of typed
findings, which is worth revisiting if a third kind arrives.

Both closing sections are built by one paginator, `_gathered_section`,
parameterized by an accessor rather than a field name. Both gather over the
opening slides as well as the sections, because the observation-gap finding
and its remedy ride the title slide.

**Silent by default.** A recommendation that fires on every deck stops being
read. Several of these are expected never to fire on a healthy dataset; see
[When the deck says nothing](#when-the-deck-says-nothing) for how often that
comes out silent across the fixtures.

**Every threshold is set higher than the caveat covering the same ground.** A
caveat is worth making when something is worth knowing, a recommendation when
something is worth doing. `CAP_RECOMMENDATION_THRESHOLD` is 5%, ten times the
`CAP_SENSITIVITY_THRESHOLD` at which the deck starts saying the cap shapes an
answer.

| Rule | Fires when | Names |
|---|---|---|
| `narrowing` | a level carries the workload (`burden_carrier`) and holds at least `NARROWING_MINIMUM_STAYS` | `other_filter_column_name`, `animal_group_columns`, `intake_filter` |
| `dimension_not_separating` | a stratifier falls below the salience threshold | `period_dates` |
| `unestimable_levels` | a level's agreement margin is at or past `WIDE_MARGIN` | merging, or the source data |
| `cap_binding` | a level is over `CAP_RECOMMENDATION_THRESHOLD` still in care at the cap | `restricted_stay_cap` |
| `tail_spread` | a level's P90-over-median is `TAIL_SPREAD_MULTIPLE` times the shelter's own | splitting the level |
| `falling_hazard` | a level's whole *own*-shape interval is under both `SHAPE_CEILING` and the pooled shape times `SHAPE_POOLED_CEILING`, in every *uncrossed* variant that fitted it, and it holds at least `RECOMMENDATION_MINIMUM_SHARE` of stays | a tenure threshold |
| `gap_remedy` | an observation gap starts inside the plot cap | `period_dates`, `animal_group_columns`, `restricted_stay_cap` |

Three of them are worth their reasoning.

**`narrowing` uses the burden-carrier test**, the same one behind the finding
above, so the deck cannot suggest re-analyzing a level it did not name.

**`narrowing` names the filter that keeps the dimension alive.** The obvious
way to narrow to LARGE is `animal_group_filter`, and it is the poor one: it
narrows the rows and flattens animal group to a single level at the same time,
so the rerun has one fewer split than the run that asked for it. The
recommendation names the other way instead. `other_filter_column_name` exists
to filter a column the analysis does not otherwise use, so setting it to the
column animal group is composed from, with `other_filter_pass`, narrows the
same rows and leaves `animal_group_columns` free to be pointed at another
attribute of the same animals, an age band for instance. The mirror run is
named too: the same column as `other_filter_cut` keeps everything EXCEPT the
carrier, and the levels it was swamping finally state their own behavior on
the other splits and in both regressions. A stratifier the tool does not
compose, `intake` being the case, has nothing to repoint and gets the plain
filter.

**`tail_spread` is relative to the shelter, not absolute.** A level is flagged
for being more dispersed than the data it came from, so a shelter whose stays
are heavy-tailed throughout is not flagged on each level. On
OC2 that is intake type RET, whose 90th percentile is 37 days against a median
of 3, 2.1 times the pooled ratio; LARGE at 1.5 times does not clear it.

**`falling_hazard` reads the shape *variants*, and one crossed variant
silences the run.** R fits the Weibull shape in variants, each holding one
stratifier's scale and letting the shape vary by the others. Under the default
additive shape formula a level's shape ratio is that level against its
reference, the same factor in every cell, and the rule reads it. Under
`weibull_shape_crossing` (an experimental feature), the tabulated ratio is
that contrast taken *inside the reference level of the other dimension* —
LARGE against MED among STRAY intakes, not LARGE against MED. Nothing
guarantees the reference cell is the large or the interesting one, and a
recommendation may not rest on a number with undetermined scope.

Setting that variant aside on its own would leave the agreement test running on
whichever variants stayed additive, so a level could reach a slide off one fit
because the fit that would have checked it was the one set aside. The rule
therefore says nothing about shape for the whole run as soon as any variant
crossed, which is also what the setting is for: an experimental reading of the
shape structure, made on a worksheet. The ratios stay on the `Weibull_By_...`
sheets, where an analyst reads them beside the model that produced them.

The test is on the fits the run made, not on the setting, so a run that asked
for crossing and got none of it, every variant having fallen back, is read like
any other.

**What the own shape is, and is not.** With two other predictors on the shape,
even an additive fit publishes a level's own k at the reference levels of the
others: on **OC2** LARGE reads 0.67, which is LARGE among strays, where the
same fit gives 0.52 in RET and 0.69 in OWNER. What carries the sentence past
that is the requirement above that every variant estimating the level agree.
The variants hold different things fixed, so LARGE also comes back at 0.65 from
the intake-type variant, where intake type is not on the shape at all and the
estimate is pooled across intake types. A level owing its shape to one
reference cell does not survive two fits that condition differently, and the
least extreme of them is the number quoted.

**`falling hazard` reads the level's *own* shape, not its shape ratio.** A
ratio is a comparison against whichever level the settings named as the
reference. The recommendation is about a level's own shape parameter k being
under 1. The two come apart whenever the reference cell's shape is high, so a
ratio of 0.80 against a baseline of 1.3 describes a level whose hazard *rises*
with tenure. R already publishes each level's own k with its own interval.

**Two ceilings, and the tighter one binds.** `SHAPE_CEILING` is absolute: the
hazard has to be genuinely falling. `SHAPE_POOLED_CEILING` is a fraction of the
shelter's own pooled adjusted shape: the level has to stand out from it, since
a shelter whose hazard falls throughout is a fact the deck states once. The
pooled *adjusted* shape is the comparator rather than the crude one, the crude
shape being low partly because the levels differ. The two thresholds cross at
a pooled k of 0.895: below that a level must stand out from a shelter that
already falls, above it falling at all is the harder test. On OC2 the pooled
shape is 0.82, so the binding ceiling is 0.78.

**The whole confidence interval has to clear the ceiling**,
not merely the estimate. And a level
holding less than
`RECOMMENDATION_MINIMUM_SHARE` of stays is never named, because a shape
estimated off a handful of stays is a poor choice for a follow-up run. That
floor is also what (in **OC2**) keeps the `_UNKNOWN_` fill off the
recommendations without a special rule for it: `_UNKNOWN_` is 1.0% of OC2's
stays and drops out on its size, while on a shelter where unknowns ran to a
fifth of intake it would be a real population and would qualify.

Since the bundle publishes levels but not model-term column names, the level is
recovered from a term like `animal_groupLARGE` as a suffix. A term two levels
could both claim is refused rather than assigned to the first match.

**Ties are named, not broken.** `extreme_levels` returns every level holding a
column's extreme, so a sentence reads "LRG and XL have the longest average
stay", with the verb agreeing. 

Past `MAX_TIED_LEVELS`, which is two, the extreme is not named at all. Two
levels read as a result; five lead to silence. The two ends abstain
**independently**, so a column with a clear fastest level and a four-way tie
for slowest reports the fastest and stops.

> **`selected_levels` may break ties arbitrarily**, because it only decides
> which rows fit: the loser keeps its row in the workbook. The selectors abstain
> instead, since naming one of two tied levels in a sentence would be false.

The competing-risks slides draw conclusions about **time**, one clause per
outcome gathered into a single bullet: "Time to outcome by animal group: for
community live outcomes, LARGE is slowest (20.7 days) and PUPPY fastest (5.7).
For other live outcomes, LARGE is slowest (65.7 days) and PUPPY fastest (4.8).
..." (**OC2**.) One bullet rather than three because the closing slide takes a
bullet per contribution and three about one stratifier would be too many. The
levels it names are the same ones the table flags H and L on those columns,
judged across every level and not only the rows the highlights table showed.

Ahead of it comes the **sweep**: "By animal group, PUPPY is
the fastest in every outcome type." It leads because it is the finding no
single panel shows. The section puts one outcome in front of the audience at a
time, on purpose, and a reader stepping through those panels cannot see that
onr level consistently sits at the same end. Either clause can appear
without the other. On **OC1** the
animal groups extremes split across LRG, XL, TOY, PUPPY, and
`_UNKNOWN_`, while on **OC2** the fastest clause fires alone.

**The test for it is the strict one**: every outcome must have a *sole* holder
of the extreme, and it must be the same level throughout. This differs from
the per-outcome sentences which name every level that shares an extreme and
print the number beside them. The sweep has no numbers anywhere in it, and is
entirely blocked by an outcome tie (separately at each end). A stratifier with
one outcome gets no sweep.

> **A share of residents is only meaningful when the levels partition the
> population at a moment in time.** Animal group and intake type do: every
> resident has exactly one size and one intake type. **Periods do not.** They
> partition the calendar, so their mean censuses are averages over disjoint
> stretches. On **OC2** they sum to 571 against a true census of 191, and a
> "share of residents by period" is not meaningful. Rather than hardcode which
> stratifiers are safe, the block checks whether the level censuses actually
> add up to the pooled census, and stays silent when they do not.

The recommendations are plain strings today. They will want structure once the
planner has to rank or drop them.

### Salience

**Built**, in `salience.py`, for the one decision that needs it today: whether
`emphasis: AUTO` gives a stratifier the resident-outlook slide. Nothing ranks
stratifiers against each other yet, because nothing has a slide budget to spend.

`stay_days_deviation` is how far apart a stratifier's levels are in average
stay, in days, after taking out the part that is sampling noise. Keeping it in
days makes it readable directly: levels of this stratifier differ by about plus
or minus eleven days of average stay. Normalization is a separate step at
ranking time, dividing by the pooled restricted mean, because comparing
stratifiers needs a unitless number but interpreting one does not.

It is built in three steps.

**1. The observed spread** is the intake-weighted standard deviation of the
levels' `km_restricted_mean`.

**2. The noise floor** is what that same spread would have been if every level
had the same true average stay and only sampling error had separated them. Each
level's restricted mean is an estimate and R publishes its standard error as
`km_restricted_mean_se`; estimates scatter even when what they estimate is
identical, so part of any observed spread is the width of the estimates rather
than a finding. The floor is the expectation of the observed weighted variance
under that null:

```
noise^2  =  sum_i  w_i * SE_i^2 * (1 - w_i / W)  /  W          W = sum_i w_i
```

**3. The deviation** takes one out of the other in quadrature, floored at
zero:

```
stay_days_deviation  =  sqrt( max(0, observed^2 - noise^2) )
```

This is the split ANOVA makes, with the within-group part arriving already
computed as each level's standard error, so subtracting gives a direct
method-of-moments estimate of the between-level variance. That estimator is
DerSimonian and Laird's, the standard way meta-analysis separates real
heterogeneity between studies from the imprecision of each study.

It is a size-aware effect estimate, not a test: no p-value and no
distributional claim. At sixteen thousand stays a test rejects everything, and
the question a deck asks is whether levels differ enough to be worth a slide.

The `(1 - w_i / W)` factor corrects for each level helping to set the mean it
is then measured against. Without it the floor is overstated, by a factor of
two exactly when there are two levels, which is the common case.

**Flooring at zero is the honest reading of a negative result.** A spread
smaller than its own noise floor means the levels are no further apart than
sampling error alone would have put them, which is reported as no spread rather
than as a negative variance.

**Where the correction earns its place.** On **OC2** it changes almost
nothing: 15,597 arrivals give a floor of half a day against spreads of 3 to 11
days, so the deviation moves by three hundredths of a day. It matters at the
other end, where `weibull_small` has fourteen arrivals, a raw spread of 5.5
days, and a floor of 4.1. Without the subtraction a rare intake type or a small
animal group could be, paradoxically, called salient because it contains
very few animals.

### The salience threshold

A stratifier is salient when `stay_days_deviation` exceeds

```
STAY_DAYS_DEVIATION_FLOOR + STAY_DAYS_DEVIATION_SHARE * pooled mean LOS
    =   1 day  +  15% of the pooled restricted mean
```

A floor *plus* a share, not the larger of the two, so the threshold is smooth
in mean LOS. Each term answers an objection to the other: without the floor a
short-stay shelter would be salient on a spread of hours, and without the share
a long-stay shelter would be salient on anything at all. They cross at 6.7 days
of mean LOS, so on any shelter but a very fast one the share decides.

The share is taken on the pooled restricted mean, the whole-sample figure, not
on the intake-weighted mean of the levels that the spread was computed around.
The two are within a fraction of a day of each other, and the pooled one is on
a slide the reader has already seen, so the threshold is a number they can
check.

**How it lands on OC1**, the shelter this was calibrated against and so the
only real calibration evidence:

| Stratifier | levels | observed spread | noise floor | `stay_days_deviation` | threshold | salient |
|---|---|---|---|---|---|---|
| Period | 3 | 3.46 | 0.44 | 3.43 | 3.53 | no, by 0.1 days |
| Intake type | 3 | 4.49 | 0.55 | 4.46 | 3.53 | yes, 1.3x |
| Animal group | 7 | 11.09 | 0.64 | 11.07 | 3.53 | yes, 3.1x |

So the rule selects, and it selects the two dimensions of the shelter's own
making over the one the calendar made: how an animal arrived and what size it
is separate its stays further than which period it arrived in. It selects the
same two on **OC2**, on a dataset with a fourth intake type and two fewer
animal groups, which is the only evidence so far that the threshold is not
tuned to one run's level counts.

**Period fails by a tenth of a day**, which is worth knowing when reading this
table rather than being alarmed by. Nothing about a threshold makes 3.43 and
3.53 meaningfully different, and a shelter that wants its periods shown says
so in the settings, which is what the OC deck settings do. A near miss is the
expected condition near any threshold; what the note on the LOS slide gives a
reader is the number, so a near miss is visible as one.

Both constants are named at the top of `salience.py`. The share is what makes
this a filter rather than a floor: at 8% all three stratifiers pass, at 15%
they do not, and that is the kind of adjustment this is expected to need as it
meets more shelters.

Weighted by intake share rather than census share, because for LOS the
arriving-cohort view is the natural one.

> **Weight by `total_intakes`, not `mean_daily_intakes`.** Counts partition
> across every stratifier, since each arrival belongs to exactly one period,
> one intake type and one group. Per-day rates do not: each period carries its
> own denominator, so per-period rates sum to roughly one rate per period
> rather than to the overall rate. Weighting by the rate would make the period
> weights shares of *rate* instead of shares of *arrivals*, overweighting a
> short busy period. For intake type and animal group the two agree, because
> the denominator is common, which is what makes this the kind of error that
> looks correct everywhere it is first tried.

The general rule this is an instance of: before combining a measure across the
levels of a stratifier, ask whether the levels partition the thing being
measured. Periods partition the calendar; they do not partition the standing
population, and they do not share a denominator with each other.

The Cox test is a gate, not a ranker. At sixteen thousand stays everything is
significant, so p-values cannot order slides.

**Salience is computed here, never in R.** It is a presentation heuristic, not
a finding; in `results.json` it would sit beside estimates that survived a test
suite and would read as a claim about the shelter rather than a claim about the
deck. It is also expected to be tuned, and tuning it in R would cost a re-run
and twenty-eight regenerated golden files per adjustment. Move it into R only if
it ever becomes a reported quantity.

### Every threshold in one place

These decide what a deck says. Each is a presentation judgment rather than a
statistical one: none of them is a level at which a result becomes true, only
one past which a sentence is worth printing. They are named at the top of the
module that uses them, with the reasoning beside them, and are expected to move
as the tool meets more shelters.

| Constant | Value | Gates |
|---|---|---|
| `STAY_DAYS_DEVIATION_FLOOR` | 1 day | with the share below, whether a stratifier is salient under `AUTO` |
| `STAY_DAYS_DEVIATION_SHARE` | 15% of the pooled restricted mean | the same; the two are added, and cross at 6.7 days of mean LOS |
| `HIGHLIGHT_SHOW_ALL_MAX` | 4 levels | above this an LOS highlights table selects rather than shows all |
| `AJ_SHOW_ALL_MAX` | 6 levels | the same for a competing-risk highlights table |
| `MAX_LISTED_LEVELS` | 10 levels | how many levels the summary slide enumerates, where the run's own `max_plot_strata` is absent |
| `WORKLOAD_MAX_ROWS` | 10 levels | how many rows a workload table keeps, largest by its counted column |
| `MAX_TIED_LEVELS` | 2 levels | how many levels may share an extreme before a finding names none of them |
| `ORDER_SHIFT_TOLERANCE` | 1 day | the difference below which two levels tie on a mark, so no order shift is read |
| `CAP_SENSITIVITY_THRESHOLD` | 0.5% still in care at the cap | when a slide starts saying the cap shapes its tenure figures |
| `CAP_RECOMMENDATION_THRESHOLD` | 5% still in care at the cap | when changing `restricted_stay_cap` is worth recommending |
| `OUTCOME_SPREAD_MULTIPLE` | 2.0x | how far apart two outcome timings have to be before the gap is a finding |
| `OUTCOME_SPREAD_MINIMUM_EVENTS` | 30 events | how many of an outcome a level needs before its timing enters that comparison |
| `WIDE_MARGIN` | 20% | the agreement margin past which a level counts as unestimable |
| `TAIL_SPREAD_MULTIPLE` | 2.0x the pooled ratio | how dispersed a level's stays have to be, relative to the shelter, before splitting it is worth recommending |
| `SHAPE_CEILING` | k = 0.85 | how far below 1 a level's whole own-shape interval must sit |
| `SHAPE_POOLED_CEILING` | 95% of the pooled adjusted k | and how far below the shelter's own shape; the two cross at a pooled k of 0.895 |
| `NARROWING_MINIMUM_STAYS` | 1,000 stays | how large a level must be before a rerun narrowed to it is worth suggesting |
| `RECOMMENDATION_MINIMUM_SHARE` | 2% of stays | the share below which no recommendation names a level |

The cap pair is the one place two of these cover the same ground, and
[Recommendations](#recommendations) says why the recommending one is set ten
times higher. The burden-carrier test, which two rules share, has no constant
of its own: a level qualifies on holding more than half the days owed and a
larger share of them than of the residents who owe them, and
[Findings](#findings) says why either condition alone says nothing.

---

## Extending the package

*For whoever changes the code. Nothing here is needed to read a deck or to
build one.*

### Where it sits

```
  R analysis
      |
      v
  results/results.json  +  results/*.png, *.csv
      |
      v
  Bundle            reading, no computation        bundle.py
      |
      +--> Regression frames  the two Cox fits      regression.py
      |                       side by side
      v
  Content blocks    Table, Bullets, Figure, Note   blocks.py
      |
      v
  Slide rules       conditions -> slides           (deck.py, provisional)
      |
      v
  Deck plan         budget, ordering, trimming     (not built)
      |
      +---> pptx renderer                          render_pptx.py
      |         ^
      |         +-- figures this package draws     figures.py
      +---> xlsx writer (every table, every run)   workbook.py
      +---> markdown -> pandoc (report)            (not built)
```

Files that exist today: `names.py`, `bundle.py`, `regression.py`, `blocks.py`,
`figures.py`, `workbook.py`, `settings.py`, `output.py`, `render_pptx.py`,
`deck.py`.

### Reading the bundle

`Bundle` (in `bundle.py`) is the only thing that touches the JSON.

An R matrix arrives as
`{"type": "matrix", "rows": [...], "columns": [...], "values": [[...]]}`
where rows are measure names and columns are stratum levels.
`Bundle.matrix()` transposes it, so blocks work with one row per level and one
column per measure, and can say `df["km_median_los"]`.

The other serialized shape is `{"type": "table", "columns": {...}}`, which the
record-like nodes use: the period definitions, the attrition steps, the unified
stay counts. `Bundle.table()` returns it as a frame directly, since it is
already column-major and needs no transposition.

Two of its accessors carry a design decision rather than a signature.

**`has`** answers whether a dotted path exists and is not null, and a block's
`requires` is built from it. Absence has to be an ordinary answer rather than
an exception, because plenty of absences are legitimate: `cox` has no analysis
when there is a single period and no other predictor, the Weibull shape
variants exist only for some stratifiers, and any figure can be switched off by
an output flag. Catching a `KeyError` instead would make a genuine bug look
like a legitimately absent section.

**`figure`** resolves a figure through the bundle's `outputs` manifest rather
than by filename, and returns `None` when the run did not emit it. A rule asks
for a kind and a stratifier and gets a path or nothing. This is why the
manifest exists: filenames are an implementation detail of the R plotting code,
and a slide should not know them.

`BASELINE_STRATIFIER` puts `all` first, an ordering decided here rather than
taken from the bundle; everything after it follows the bundle's own key
order. The
whole sample is not a special case in the bundle; it is a genuine stratifier
with a single level named `"All"` and exactly the same measure rows as the
others, so a pooled row comes from the same code path as a stratified one and
cannot drift from it.

### The regression frames

`regression.py` turns the bundle's two Cox regressions into frames, and is the
one place in the package that derives a number.

`pooled(bundle)` is the pooled Cox regression of the methods document's §6.1:
every stratifier in one linear predictor, all of them sharing one baseline
hazard. `stratified(bundle)` is the per-predictor fits of §6.8: one model per
stratifier, carrying that stratifier alone while the others move inside
`strata()`, so each combination of their levels gets its own baseline. Both
are indexed by `(stratifier, level)` with columns `hr`, `hr_ci_lower`,
`hr_ci_upper`, `p_value`, and the reference level present as the definitional
row R writes for it with hazard ratio exactly 1 and no interval.

**The two frames have the same index.** The pooled table carries one row per
level of every qualifying predictor; each variant carries one row per level of
its own and none for the others, which are inside `strata()` and have no
coefficients. The union of the variants is therefore exactly the pooled row
set. Nothing has to align them.

Rows come out in the order the bundle's `hr_table` gives, **not** the order of
`cox.xlevels`. The two differ: `xlevels` is the releveled order with the
reference first, while R writes the table back in the canonical order every
worksheet, plot, and stratum table uses. Reading `xlevels` instead would list
a deck's animal groups two different ways on consecutive slides.

#### Two comparisons, kept apart

`comparison(pooled, stratified)` puts the two fits side by side and adds two
derived columns, which ask different questions.

`p_difference` is the ordinary two-sided test of whether the two fits disagree.
A small value is its finding. It is the familiar question readers look
for.

`agreement_margin` is the achieved equivalence margin. A margin of 0.08 says
the data establish, at 95% confidence, that the two models agree within 8%,
the ratio of their hazard ratios lying inside [1/1.08, 1.08].

**Why both.** A large p-value cannot separate real agreement from a level too
thin to establish anything, because thin data
earns a large p for free. A margin cannot be earned that way: thin data widens
the interval, the margin grows, and the number reports honestly that little
was settled. Genuine agreement has a large p beside a tight margin,
while a large p beside a wide margin means nothing was established either way.
On **OC2** the p-values run 0.40 to 0.98 across every level while the margins
distinguish the well-populated levels, at 7% to 11%, from the one uncommon
animal group, `_UNKNOWN_` at 24%. The p column alone would have called those
nine levels the same thing.

The two are two readings of one z statistic at one confidence level, so they
cannot disagree: `p_difference < 0.05` exactly when the ratio's interval
excludes 1. The fixtures pin that.

**The margin is set by whichever end of the interval sits further from 1**,
whether or not the interval contains 1. On **OC2**, PUPPY's runs
[0.904, 1.067], so the lower end sets the margin at 10.7% and the upper end's
6.7% is not the answer. `check_margin_takes_the_further_bound` pins it.

**Both columns share one variance, and it treats the two fits as independent,
which is only an approximation.** They come from the same rows and their
correlation is almost certainly positive, so the true variance of their
difference, `Var_p + Var_s - 2*Cov`, is smaller than the sum used here. The
approximation makes both columns conservative, each in the direction it can
afford. Too large a variance shrinks every z statistic, so a p-value comes out
larger and under-reports a real difference; and the interval widens, so a
margin comes out larger than the data require. Neither column can flatter its
own finding on account of it. The p column loses power, which is reason to
report it beside the margin.

The correlation-aware alternative, Hausman's `Var_s - Var_p`, is unavailable
here regardless: these are clustered robust standard errors rather than
model-based ones. The efficiency result the method rests on does not hold for
them, and on **OC2** it returns a negative variance on three of the nine
estimated rows.

Standard errors are recovered from the reported intervals, since that
inversion is exact and keeps the interval a reader sees as the one source of
the uncertainty.

#### Why this one file derives

Invariant 1 below says nothing is recomputed, and this is an exception. The
quantity is a comparison *between* two bundle entries, used for presentation
rather than reported as a new result, and it lives in one function so that the
exception is visible. If it ever needs to appear in `analysis_results.xlsx`,
or to be cited as a separate finding, then it should move into R.

### Display names

`names.py` is the single place where `km_median_los` becomes "median LOS". It
lives here, downstream of the structures that are better off with machine
names: the bundle, `analysis_results.xlsx` and the CSVs.

#### Conventions

**Labels begin lowercase.** "mean daily intakes", not "Mean daily intakes",
because a label can land mid-sentence in a bullet. Renderers that need a
capital call `capitalize_first`.

**Known acronyms stay unexpanded**: CI, KM, AJ, Cox, LOS. Spelling out
acronyms increases table width unnecessarily.

**Unknown acronyms carry a plain alternative.** RMST is the motivating case: a
shelter director will not know it, unlike LOS. An entry's `plain` field gives
the low-mathematics wording, which a mathematical-sophistication setting could
select.

**Vocabulary rule, inherited from the analysis**: "in care" and "in-care"
belong to the residents present at a moment, and a total number of days is a
stay or an LOS. `per_resident_past_days` is resident-view of days already in
care; `km_restricted_mean` is a duration of the whole stay. The deck reports
both views side by side and they diverge hard.

#### Entry shape

An entry carries the full phrase, a `short` form for narrow table columns, the
`unit`, and the `plain` low-mathematics register. The unit is kept out of the
label so a renderer can print it once per header instead of in every cell.

A `short` must stand on its own: a table spanning the arriving-cohort and
resident views cannot lend context it does not have, and would otherwise head
two different medians "Median".

#### Three namespaces

| Namespace | Contents | Maps to |
|---|---|---|
| `METRICS` | measure names from stratum matrices, unified scalars, regression table columns | a phrase |
| `KINDS` | the `kind` field of the outputs manifest | a figure title, and the filename stem |
| `STRATIFIERS` | `period`, `intake`, `group`, `all` | a phrase used inside titles |

#### Three structural rules

**Confidence bounds and standard errors are parsed, not named.**
`km_median_los_ci_lower` resolves to `(base="km_median_los",
role="ci_lower")`. Naming every `_ci_lower`, `_ci_upper`, and `_se` spelling
instead would roughly double the curated table.  A renderer wants one header
over three numeric columns, which is the estimate-lower-upper discipline R's
workbook already follows.

`python3 -m mlos_review` counts the two sides against a real bundle, and an
empty awaiting-curation list is the healthy state.

**The competing-risk outcome slot is filled from the bundle.**
`outcome_mix_L`, `incidence_L_per_100_animal_days`, `aj_final_cif_L`, and their
siblings are templates with a code slot, resolved against
`palette.outcome_labels`. Those labels are configuration, which is why they
legitimately live in the JSON. The
configured label repeats its code as a prefix ("L community live") so the
legend in R's workbook ties to the plot colors; prose strips the prefix and
short forms keep the bare code.

**`Any` is a pseudo-outcome.** It appears in `aj_final_cif_Any` and friends
but not in the configured labels, because it is not a state the data can
record. The vocabulary supplies "any outcome" for it.

#### The fallback

Anything unmatched is rendered by splitting on underscores and expanding known
acronyms. This is a safety net, not a strategy. Its job is to keep raw
`snake_case` off a slide when a name is added to the bundle before anyone
curates its wording. Every fallback is recorded, and `report_fallbacks` lists
them, so the un-curated set is visible.

The sweep feeding that report admits the per-outcome spellings too, such as
`aj_final_cif_L`: a machine name is lowercase snake_case except for its
outcome-code segments, which are user configuration and uppercase-initial.

### Content blocks

A block is a pure function of the bundle that selects and arranges values. If a
block finds itself deriving a statistic, that is a signal the value belongs in
the R bundle instead. That is how the resident-tenure quantiles got there: the
median resident tenure was initially reachable only by reading the
`km_in_care_tenure` CSV grid and finding where the profile crosses 0.5, so it
was added to the bundle rather than recomputed here.

#### `Table`

The field-by-field contract is on the `Table` and `Format` dataclasses in
`blocks.py`. What belongs here is the four decisions behind them, each of which
is about content rather than rendering.

**Tables carry numbers, never formatted strings**, and flags travel as a
parallel overlay rather than being pasted into the number. The spreadsheet
renderer is a named future consumer: pptx can draw "9 H" in one cell, while
xlsx writes `9` as a number and expresses the flag as conditional formatting.
A string cell cannot be sorted, charted, or read by whatever consumes this
next. A column may still hold text where the value is genuinely textual, a
date or a level name, which is not a number written into a string.

**Decimal places are a content decision, not a styling one.** A median in
whole days and a fraction of stays capped are different kinds of numbers, and
rounding a fraction to zero places would destroy it.

**Percent is a display choice, and the frame keeps the fraction.**
`fraction_capped` is stored as `0.008` and rendered as `0.8%`, the scaling
happening in the renderer, so a spreadsheet renderer can write the fraction
into the cell and set a percent number format and a reader can change the
display without changing the data.

**Units are footnoted, not repeated per column.** Most measures are in days or
counts, familiar enough to the audience not to be worth a table row of their
own. The footnote is there for the reader who needs it.

### Slide rules

**Designed, provisionally implemented.** `deck.py` contains a handful of
hardcoded rules called in a fixed order, standing in for the registry:
`title_slide`, `summary_slide`, `los_overall`, `resident_outlook`,
`los_by_stratifier`, `resident_outlook_by_stratifier`, `workload_slide`,
`aj_teaser`, `aj_by_stratifier`, `findings_section`, and
`recommendations_section`. The order they are called in is `build`'s, not a
property of the rules.

`workload_slide` reads across every stratifier at once, which fixes its
position: it can only follow all of them. It is called once per workload
question, so the three slides are three calls rather than three rules.

`resident_outlook_by_stratifier` is the first rule whose condition is the
settings rather than the bundle: it declines unless the stratifier is salient,
which today means `emphasis` said `ALWAYS` or pinned levels, or the dataset has
a single stratifier and the default moved (see `Settings.for_dataset`). When
`AUTO` is computed from the findings, this is the rule that will read it.

`build` resolves the settings against the dataset once, before any rule is
called, so two rules cannot disagree about the same stratifier on the same run.

The first two are the opening, gathered by `opening_slides`. The title slide is
the one rule with no condition: a deck always has a title. The study window and
the truncation and censoring diagram ride there because both are about the
window rather than about anything computed inside it. `summary_slide` follows
the ordinary absence rule, so a bundle with none of the descriptive numbers
gets no summary slide.

That diagram is the one figure in a deck not drawn from the run. It is
`OPENING_DIAGRAM`, a PNG committed inside the package, dropped rather than
raising if the file is not beside the code. `kaplan_meier_diagram.svg` is the
source, since pptx has no SVG; the command that rasterizes it is in `deck.py`,
next to the constant. `OPENING_DIAGRAM_NOTES` leads the slide's notes when it
is present.

`provenance` writes the title slide's footnote: the mLOS version that computed
the numbers, taken from the bundle's `run` node, then two stamps at second
resolution, when the statistics were computed and when the deck was built. A
deck rebuilt today from a bundle computed in March is a deck showing March's
shelter, and a deck that gets deposited is citable only as a version beside a
DOI.

The registry these stand in for gives a rule an id, a condition, a salience,
and a build. A rule also reports its own cost at each detail level, so one rule
can render at one, two, or four slides, which is what lets the planner degrade
a section instead of deleting it.

Rules are plain Python in a registry, not a YAML rule language. The conditions
are computations rather than configuration: "if intake type turns out to
matter" is a statistic, not a flag. A configuration language would also make it
impossible to run every rule against every fixture in a loop, which is how this
is tested.

The one existing rule shows the fallback discipline worth keeping: both figures
are optional, since output flags can switch either off. With one missing the
survivor runs full width; with both missing the table still carries the slide.

### The deck plan

**Designed, not built.**

Two passes. Rules *propose*, each reporting an id, a priority tier, a salience,
and a cost at each detail level. A planner then solves a small knapsack against
`max_slides`, honouring fixed tiers (title, methods, caveats are not
negotiable) and spending the remainder in salience order.

Two passes rather than sequential rule application, because sequential
application makes the last rule pay for everything the earlier ones spent.

### Figures this package draws

Every figure in the deck is a PNG the R run produced, resolved through the
bundle's `outputs` manifest by `Bundle.figure`. That stays the rule: a figure
of reported numbers belongs beside the numbers, drawn by the code that computed
them.

`figures.py` is the exception, for figures the R side does not have. There are
two: the paired hazard-ratio bars of the reserve section (`hr_comparison`),
where the comparison between the two Cox fits exists only here, and the
three-estimate dots of the hazard-ratio and LOS ratio slides (`hazard_ratios`,
`los_ratios`), which put estimates from different models on one axis.

Both copy R's base-graphics look rather than matplotlib's, since they land on
the same slides as R's own: bold title inside the figure, large type, dashed
light-gray gridlines, boxed legend, and the same 3200 x 2133 pixels at 3:2.
Colors come from the run's `palette.stratum_colors`, with one caveat the legend
has to carry: on these figures a color is a *model*, where on every KM and AJ
figure a color is a stratum. They are written to the deck's own figures
directory, `mlos_deck.pptx` giving `mlos_deck_figures/`.

**Bars run from zero, which is why the ratio slides are not bars.** A bar's
length has to mean the value, so the `hr_comparison` bars start at zero and a
dashed line at 1 carries the above/below reading. That is also what rules bars
out for the ratio slides: three per level, over a range of 0.7 to 3.8, spends
most of the ink below 1. Those slides use dots, the reference level's drawn at
full strength on the line at 1 and carrying no whiskers.

The ratio slide titles carry "hazard ratios (HR)" so the figure below can say
"HR", the figure having less width to spare.

### Renderers

A renderer knows how to put a title, figures, a table, and notes onto a page.
It knows nothing about what any of them mean.

`render_pptx.py` computes geometry from the slide size rather than hardcoding
it, because the figure count varies. Figures preserve their 4:3 aspect ratio
for consistency.

A slide names one of five **layouts**, which is the presentational vocabulary
a rule has. How many figures a slide carries and whether they are peers is
something only the rule knows; the geometry is the renderer's.

`STACKED` is the default: figures in a row, table across the full width beneath
them, which is right whenever the figures are two readings of one thing.

`SPLIT` puts the figures left and the table right, both vertically centered,
for one figure held against a table the reader keeps in view while the figure
changes. The table takes its natural width but never more than half, so a
narrow table hands the surplus to the figure.

`QUADRANTS` fills a two-column grid in reading order with the table last. **No
rule uses it today**: the competing-risk slide it would suit uses `SPLIT`,
since a 4:3-ish figure does not fit well on a quarter of a 16:9
slide. It is kept for a future rule wanting four figures of equal standing, and
a synthetic test calls it.

`TABLES` puts several tables in a row, each headed by its own title, for a
slide whose subject is several small tables that answer one question between
them. Each takes its **natural** width rather than an equal share, since a
one-column tally could sit beside a five-column summary. The row adapts to
one, two, or three tables without branching on the count, and a single table
arrives centered. Their tops are shared so the titles line up.

A table's own title is drawn only where the slide's title does not name it;
for example on a slide of several tables, or the opening slide. A title is
also allowed to **set** the width that table occupies, because a title is
given one line and must not wrap. The table then centers inside the width it
was given.

`TITLE` is the opening slide: bullets, then any tables beneath them, the whole
block centered vertically in the body and set flush left, with the slide title
larger. The vertical centering is the whole difference from `STACKED` carrying
the same pieces, and a title slide hung flush under its title looks like one
that lost its figure. A figure moves that column into the left half and takes
the right.

Separately from a table's own footnotes, a slide may carry **one footnote of
its own**, drawn at the foot of the page whatever the layout, for what is true
of the page rather than one of its components; the title slide's provenance
line is the case. It is set like a table footnote.

Figures are never stretched: each is drawn at its own aspect ratio, read from
the PNG header, since the ratio is R's decision and R has
changed it once already.

A table is sized to its content and **centered when it does not need the full
width**. Each column is sized to **its own** longest cell, capped at
`MAX_COLUMN_WIDTH`, from a per-character estimate, pptx offering no text
metrics. Each string
is charged at the point size it is actually set in, and a flag mark only
when one will be drawn.

**Capitals are charged half again as much**, level names being the one thing in
these tables written in capitals. The
rates are measured against Arial, whose capitals are wider than the Calibri a
deck asks for, erring on the side of caution.

**One type size inside a table**, for the row labels, the column headers, the
numbers, and a table's own title. The nine-measure
LOS table wants about half an inch more than the slide has and is
squeezed to fit.

**Tables never break a word.** A column is sized to its own longest cell, and
a row that does not fit is squeezed proportionally out of the columns with
slack to give. What a column is never squeezed below is its longest *word*:
PowerPoint wraps at spaces, but when that is insufficient it breaks mid-word
instead. Where even those floors do not fit, the table is drawn wider than its
box and hangs off the slide, where the geometry check and the eye can both see
it.

A table's *height* is counted the same way, wrapped headers included, because
pptx grows a row to fit its text whatever height the shape claims, and could
result in overwriting of footnotes. The suite checks both on every rendered
fixture: no header narrower than its longest word; and no text box starting
inside the space a table will actually occupy.

How many columns fit is measured rather than chosen. On the three workload
slides, whose tables sit side by side and each pay for their own column of
level names, the row has about 12.5 inches: the census slide uses 12.1, the
tenure slide 11.9, the animal-days slide 11.7. The animal-days slide has no
room for a fourth, and the reason is the numbers rather than the headings,
since five and six digits with a thousands separator need about an inch a
column; a share of the days owed would ask for 13.9
inches. It goes to the workbook and the slide's findings instead. That is the
rule whenever a column will not fit.

Column headings on those slides carry no commas and no phrases: Counted,
Fitted, Future, Owed, Pct, Intake Pct. Longer phrases belong to table titles,
which carry enough to let the column and row headings stay short.

Tables are drawn in **"No Style, No Grid"** with **every other data row washed
gray**, rather than ruled. The pptx default is a blue-banded style, and blue
is saved for painting a high value. A ruled table pulls attention away from
figures.

Cell insets are tightened from pptx's tenth of an inch a side, which can add
up across seven columns.

**The high and low marks are arrows, not letters.** Outcome codes come from
the user's data, so any letter can collide with one: on the OC data an `L`
beside a number would mean lowest while the `L` above it means community live.
The tokens in the flag frame are still `H`, `L`, and `F`, which are data a
spreadsheet renderer may express as a conditional format; only the pptx
renderer turns them into `↑`, `↓` and `=`, and the setting is `MARK` rather
than `LETTER` for the same reason.

Flags are drawn as a separate grayed run beside their number, so the cell still
reads as a number with a mark on it. Values are set larger than headers.

**Speaker notes are a list**, not one string, because they accumulate from
several places: what the rule says about the figures, caveats a block attaches,
and standing facts such as the stay cap. The renderer writes one paragraph per
entry.

### Everything a build writes

One call to `deck.build` writes four things into `reports/`, from one bundle
and one set of blocks, so they cannot come from different runs.

| File | What | Overwritten? |
|---|---|---|
| `mlos_deck.pptx` | the deck | archived first |
| `mlos_deck_tables.xlsx` | every table the build made | archived first |
| `mlos_deck_figures/*.png` | every figure this package drew | yes |
| `mlos_deck_figures/manifest.json` | what those PNGs are | yes |

The deck and the workbook are deliverables, so an existing one is renamed aside
rather than replaced, by the same `<stem>_<YYYYMMDD>_<NNN>` scheme `results/`
uses. The figures are inputs to the deck and are embedded in it, so an archived
deck keeps the ones it was built with and nothing is lost by redrawing them.

#### The figure manifest

`mlos_deck_figures/manifest.json` lists one entry per PNG with `plot`, `kind`,
`stratifier`, and `description`, the same field names the bundle's `outputs`
entries use, so a consumer that already reads R's manifest reads this one
without learning a second vocabulary. A consumer asks for a kind and a
stratifier instead of guessing a filename, which is the same reason R's
manifest exists.

#### What gets a sheet

`workbook.py` writes every table a build actually creates, one per sheet, with
three exclusions:

- a table that never reaches a reader, existing only as a step between frames;
- a table that is merely a *view* of another already written, being a row
  selection, a column subset, or a transposition: `highlights_table` picks four
  rows out of `full_table`, and the slide's four-column Cox comparison is the
  same case against the full one;
- a table that is another one under a different name, such as the
  competing-risk teaser, which *is* the whole-sample stratum's table.

A table that *combines* information from different places gets a sheet even
when its parts appear elsewhere. The three Cox sheets are the case: the
comparison holds a ratio, an interval, a p-value, and a margin that appear in
neither fit.

**One sheet per table, unless the columns are identical.** The grouping used
is a family of tables that is the same table computed once per stratifier,
where the headings match by construction. Those are stacked on one sheet, each
under its own heading row, separated by a blank line. Anything less certain
gets its own sheet, which is safe to split further and hard to get wrong.

On **OC1** and **OC2** that is eleven sheets: `Study_Window`, `Sample`,
`Stays_By_Stratum`, `LOS_By_Stratum`, `Workload_By_Stratum`,
`Outcomes_By_Stratum`, `Cox_Pooled`, `Cox_Stratified`, `Cox_Comparison`,
`HR_Panel`, `LOS_Ratio_Panel`. The four middle ones stack one table per
stratifier; the last two are the regression panels the hazard-ratio and
LOS slides are drawn from.

`Workload_By_Stratum` is the one sheet that holds more than its slides do. The
three workload slides take a slice each and leave out the study-window
animal-day total entirely, because on a slide it put a second scale of the
census beside the census; here every column sits together, and a stratifier
whose levels do not divide the standing population carries its share columns
empty rather than dropping them, so the family still stacks under one row of
headings.

Each share column follows the column it divides, and its header names that
quantity: `Intakes, pct` after `Intakes/day`, `Census counted, pct` after
`Census, counted`. The slides can head a share `Pct` because the column beside
it says what of; a sheet is read a column at a time and its order is not fixed,
so a header that leans on its neighbor is one column move away from being
wrong.

Two things differ from the slide rendering, both because a sheet is where a
reader goes to check a number rather than to take an impression of it. Headers
use the vocabulary's full label rather than its short form, since a short form
leans on its neighbors and the comparison sheet has three estimates each with
an interval: short forms head it "Lower, Upper" three times with nothing saying
which estimate each pair bounds. And a cell whose format would display a
nonzero value as zero falls back to General, so a Cox p-value of 3.7e-06 shows
as `3.67183E-06` rather than as `0.0000`, which reads as an exact zero.

Numbers stay numbers: the cell holds full precision and carries an Excel number
format saying how to show it, and a percentage is stored as the fraction the
bundle holds with a percent format over it. A reader can change the decimals,
sort the column, or chart it, none of which a pre-rounded string allows.

### Invariants

These hold across the package, and a change that breaks one is a design change
rather than a bug fix.

1. **The statistics are R's.** This package does simple computations only:
   arithmetic over numbers the analysis has already computed and published, of
   the kind a reader could redo in a spreadsheet from the same cells. It does
   not fit models, estimate survival, resample, or impute. Where a value needs
   any of that, the fix is to add it to the R bundle, not to derive it here.
   The dividing line is not what a quantity is about but what producing it
   takes: `regression.comparison` is arithmetic on numbers already in the file
   and stays; anything needing a risk set, a likelihood, or a grid does not.
2. **The survival figures are R's too.** This package draws spreadsheet-style
   figures: bars, columns, dots, and lines over the rows of a table it holds.
   Kaplan-Meier curves, Aalen-Johansen cumulative incidence, conditional
   outcome mixes, and in-care tenure profiles are drawn beside the estimators
   that produced them and arrive here through the bundle's `outputs` manifest.
   The line is the kind of picture, not the subject: the hazard-ratio figure is
   a bar chart of Cox output and belongs here because it is a bar chart. A
   curve over a time grid would not, since reproducing one means reproducing
   the estimator's grid, risk sets, step conventions, and intervals.
3. **Tables carry numbers.** Formatting happens at render time.
4. **Absence is an answer.** Blocks declare what they need; rules ask before
   building. Exceptions are for bugs.
5. **Machine names survive to the renderer.** Translation happens in one place,
   at the last moment. A table may override its own column headers, but that
   override is read at render time too and never written into the frame.
6. **Every table a build makes is written out.** A table shown on a slide is
   shown in the rows that fit; the workbook has all of them. See
   [Everything a build writes](#everything-a-build-writes) for what qualifies.
7. **Every rule runs against every fixture.** Twenty-eight bundles in
   `tests/golden/` cover eleven animal groups, an unreached median, a single
   constant-LOS period, observation gaps both pooled and per stratum, and
   selectively disabled outputs.

### Running the pieces

```bash
python3 -m mlos_review                          # display-name coverage report
python3 -m mlos_review.deck                     # the deck, into reports/
python3 -m mlos_review.deck results out.pptx    # explicit input and output
python3 -m mlos_review.deck --settings=x.yaml   # a different settings file
python3 -m mlos_review.deck --template=b.pptx   # branded, whatever the file says
python3 tests/run_review_tests.py               # the test suite
python3 tests/show_guide_examples.py results/OC1  # the marked numbers
```

In Colab the runtime stays on R and Cell 3 shells out to Python, since the
deck reads only `results/` and touches no R. See `colab_mlos.ipynb`.

To inspect a deck without opening it:

```bash
/Applications/LibreOffice.app/Contents/MacOS/soffice --headless --convert-to
pdf --outdir . out.pptx ```

Dependencies are declared in `pyproject.toml` at the repository root, which is
the one place they are stated: `pandas`, `python-pptx`, `PyYAML`, `matplotlib`,
and `openpyxl`, on Python 3.9 or newer. All five are needed by an ordinary
build: matplotlib draws the hazard-ratio figure and is imported the moment
`deck` is, and openpyxl writes the companion workbook every run produces. To
install them, from the repository root:

```bash
pip install -e .
```

Installing is optional: `python3 -m mlos_review.deck` run from the repository
root works without it, and the install is what makes `import mlos_review` work
from anywhere, which a scheduled build or a notebook wants. On the Mac's system
Python 3.9 most of these are already present and only `PyYAML` is usually
missing (`pip3 install --user pyyaml`).

Without PyYAML the package still runs on defaults, but a settings file present
at the default path is an error rather than something silently skipped.

The test suite reaches for two things the package does not, and they are absent
from `pyproject.toml` deliberately: `markdown-it-py` and a pandoc, which its
`documents` section uses to render the three guides both ways and compare what
each renderer made of them. They check the documents rather than the package,
and a Colab session building a deck should not be made to install them.
Missing, that section reports `[SKIP]` with the reason and the summary counts
it, so a machine without them does not read as a machine that passed.

The Colab notebook keeps its own explicit `pip install` line rather than
installing the package, because a session holds only the files uploaded into it
and a cell that failed for want of `pyproject.toml` would be worse than one
naming its packages. That the session holds only what was uploaded also makes
the notebook's file listing part of the install rather than documentation of
it. Both lists are a second copy of something, so the test suite compares each
against its original.

---

## Design decisions and why

**Markdown is not the intermediate.** Generating markdown and running pandoc
to produce both slides and reports was the first proposal, and it was rejected
for two reasons. It cannot reach the spreadsheet: once a table is a pipe table
its numbers are strings, so the xlsx path would have to bypass markdown and
re-derive from JSON. And pandoc's pptx writer cannot lay out the slide that
matters most here, two figures side by side above a table, because the fenced
`::: columns` div works for Beamer and reveal.js and is ignored for pptx.

Markdown remains the right renderer for the eventual text report, reusing the
pandoc path already used for the methods documents. It is one renderer among
several rather than the thing everything funnels through.

**python-pptx rather than Quarto or reveal.js**, because co-authors and
shelter staff need to edit the deck. Quarto's pptx inherits the same pandoc
layout limits, and since the slide count is computed rather than authored,
using it would mean generating `.qmd` from Python anyway: it would buy the
rendering and not the logic.

**The Block IR is the intermediate**, which is what the original three-part
proposal already described. Tables and bullet lists with titles and footnotes
attached *are* a document model. Keeping them and putting thin renderers behind
them makes the renderer choice swappable rather than foundational.

---

## Known gaps

Ordered roughly by how much they block the next step.

- **No planner, no profiles, no budget.** Parts 2 and 3 of the design. Salience
  now exists (`salience.py`) and decides one thing, whether a stratifier earns
  its resident-outlook slide, but nothing ranks stratifiers against each other
  or trades slides off against a budget, and there is still no notion of detail
  level. The threshold is calibrated against one shelter; see
  [Salience](#salience) for what it does there and what tightening it would
  take.
- **The highlights union can collapse further than expected.** On the **OC1**
  animal groups it selects two rows out of seven, because three of the four
  superlatives land on LRG; **OC2** collapses the same way, to two rows out of
  five. `emphasis` with a level list is the workaround and it does work
  (on **OC1**, pinning LRG, XL, and TOY gives four rows), but needing it to get
  a readable
  table suggests the selectors themselves want revisiting.
- **Nine measures is dense for a slide table.** It fits, but the full table may
  belong in the report and an appendix rather than under two figures.
- **No bullet-list block.** The design calls for one; the findings slide and
  the title slide render bullets directly rather than through a block.
- **`field_summary_table` is built and unused.** It is the shape for a dataset
  whose fields have more levels than a slide can list; the current analysis has
  at most two fields with six levels between them, which `level_counts_table`
  simply tallies. Wire it in when a dataset needs it.
- **The opening summary has no methods slide behind it.** It says what was
  analyzed and not how, so a caveat about left truncation or the stay cap
  reaches the audience only through the speaker notes. The fixed tiers in the
  deck plan name a methods tier; it is not built.
- **No golden files for the deck.** The structural suite exists
  (`tests/run_review_tests.py`), but nothing pins the exact content of a
  rendered table. That is deliberate while the block set is still moving; add
  goldens once it settles.
- **Golden bundles ship no PNGs**, which is right (images are large, and the R
  suite already checks that every plot named in the manifest was written) but
  means `bundle.figure` finds nothing during a fixture test. Every layout would
  therefore go untested against a real bundle, so `check_deck_with_figures`
  stages a copy of the fixture with a 3:2 placeholder at every path the
  manifest names. The images carry no data; the geometry computed around them
  is what is under test.
- **The report and spreadsheet renderers do not exist.**
