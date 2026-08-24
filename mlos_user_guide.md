# mLOS — Length-of-Stay Analysis Tool: User Guide

*Note: This Markdown file is the documentation of record for the mLOS User Guide, version 20260823_001. Read it in any markdown reader, Obsidian among them. The companion `mlos_user_guide.docx` is tracked here, but it is rebuilt only for a release, so it carries the version it was built from: where the two differ, this file is the current one and the Word copy lags it.*

*© 2026 Michael Loizos Mavrovouniotis. This document is licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). It is part of the mLOS project, whose code is released under the MIT License.*

## Contents

- [What mLOS Does: For Practitioners](#what-mlos-does-for-practitioners)
    - [The core idea](#the-core-idea)
    - [Why full curves matter, and why averages mislead](#why-full-curves-matter-and-why-averages-mislead)
    - [Why it's harder than just tabulating and averaging](#why-its-harder-than-just-tabulating-and-averaging)
    - [What "steady state" means](#what-steady-state-means)
    - [What you feed it](#what-you-feed-it)
    - [What you get back](#what-you-get-back)
    - [Choosing your period boundaries](#choosing-your-period-boundaries)
    - [Choosing your `restricted_stay_cap`](#choosing-your-restricted_stay_cap)
    - [Getting more out of the tool](#getting-more-out-of-the-tool)
- [Technical Reference](#technical-reference)
    - [Overview](#overview)
    - [Plots](#plots)
        - [Kaplan-Meier (KM) plots](#kaplan-meier-km-plots)
        - [Remaining LOS plots](#remaining-los-plots)
        - [Census by tenure plots](#census-by-tenure-plots)
        - [In-care tenure plots](#in-care-tenure-plots)
        - [Aalen-Johansen (AJ) plots](#aalen-johansen-aj-plots)
        - [Plot strata limit](#plot-strata-limit)
    - [Numerical output](#numerical-output)
        - [The console log](#the-console-log)
        - [Each run archives the one before it](#each-run-archives-the-one-before-it)
        - [The results JSON](#the-results-json)
        - [Where the rows went](#where-the-rows-went)
        - [How to read the JSON](#how-to-read-the-json)
        - [Rebuilding the workbook from the JSON](#rebuilding-the-workbook-from-the-json)
        - [The Excel workbook](#the-excel-workbook)
        - [The General sheet](#the-general-sheet)
        - [The stratum sheets](#the-stratum-sheets)
        - [The Cox_Regression sheet](#the-cox_regression-sheet)
        - [The Weibull_Regression sheet](#the-weibull_regression-sheet)
        - [The per-predictor Weibull sheets](#the-per-predictor-weibull-sheets)
        - [Shapes per combination on those sheets](#shapes-per-combination-on-those-sheets)
- [Running the Tool](#running-the-tool)
- [Data File (CSV)](#data-file-csv)
    - [Mandatory columns](#mandatory-columns)
    - [Optional columns](#optional-columns)
    - [Outcome type codes](#outcome-type-codes)
    - [Fine print on dates and LOS](#fine-print-on-dates-and-los)
    - [Records that must be in the file](#records-that-must-be-in-the-file)
    - [Study window trimming](#study-window-trimming)
    - [The screening stages, in order](#the-screening-stages-in-order)
- [Settings File (YAML)](#settings-file-yaml)
    - [Study design](#study-design)
        - [`period_dates` (required)](#period_dates-required)
        - [`restricted_stay_cap` (required)](#restricted_stay_cap-required)
        - [`period_labels`](#period_labels)
    - [Outcome classification](#outcome-classification)
        - [`outcome_type_L`, `outcome_type_T`, `outcome_type_N` (all-or-none)](#outcome_type_l-outcome_type_t-outcome_type_n-all-or-none)
        - [`outcome_type_delete`](#outcome_type_delete)
        - [`outcome_type_in_care`](#outcome_type_in_care)
    - [Defining the comparison groups](#defining-the-comparison-groups)
        - [`animal_group_columns`](#animal_group_columns)
        - [Value maps](#value-maps)
        - [Value filters](#value-filters)
    - [Data screening](#data-screening)
        - [`discard_bad_rows`](#discard_bad_rows)
        - [`discard_overlapping_rows`](#discard_overlapping_rows)
    - [Regression options](#regression-options)
        - [`period_reference`](#period_reference)
        - [`intake_type_reference`](#intake_type_reference)
        - [`animal_group_reference`](#animal_group_reference)
        - [`parametric_regression`](#parametric_regression)
        - [`weibull_shape_crossing`](#weibull_shape_crossing)
    - [Plots and output selection](#plots-and-output-selection)
        - [`plot_stay_cap`](#plot_stay_cap)
        - [`max_plot_strata`](#max_plot_strata)
        - [`show_km_ci_ribbons`](#show_km_ci_ribbons)
        - [`show_aj_cif_ci_ribbons`](#show_aj_cif_ci_ribbons)
        - [`png_pointsize_factor`](#png_pointsize_factor)
        - [`png_line_width_factor`](#png_line_width_factor)
        - [Stratified-output selection](#stratified-output-selection)
- [Capabilities and Conventions](#capabilities-and-conventions)
    - [Survival analysis framework](#survival-analysis-framework)
    - [Observation gaps](#observation-gaps)
    - [Competing risks](#competing-risks)
    - [Census and animal-day metrics](#census-and-animal-day-metrics)
    - [Which day counts? Who is in the census?](#which-day-counts-who-is-in-the-census)
    - [Statistical testing](#statistical-testing)
    - [ExitLOS vs AnimLOS](#exitlos-vs-animlos)
- [Limitations](#limitations)
- [References](#references)

## What mLOS Does: For Practitioners

mLOS is a tool that helps animal shelters answer some deceptively tricky questions. A sampling, in everyday terms:

**Length of stay, over time and across groups**

- Which categories of animals stay longer or shorter?
- Are animals staying longer or shorter in our shelter than they used to?
- Even if the typical (median) stay is holding steady, is the long-stay tail growing or shrinking?
- Did length of stay change after we shifted a policy? By how much? Could the difference be just noise?

**How an animal's prospects change during its stay**

- Do the animal's prospects shift as its stay lengthens?
- If an animal has already been here two weeks, how many more days should we expect it to stay?
- Does the likely outcome change the longer an animal stays? Among the animals still with us at two weeks, what outcome mix should we expect from here on?

**Outcomes and how they compete**

- Do community outcomes (adoption, return-to-owner) occur faster or slower than transfers?
- What fraction of animals reach a live outcome within their first week, or their first month?
- How has the split between adoption, transfer, and euthanasia shifted from one period to the next?
- Are non-live outcomes concentrated early in the stay or late, and has that timing moved?

**The population in care**

- How is the mix of animals in care different from the mix as they arrive at intake?
- How do the animals in our kennels skew toward long stays compared with the animals we take in?
- What is our average daily census, and does it match what our intake rate and stay lengths imply?
- Is our census in steady state, or are we working off (or building up) a backlog?
- How much future care (animal-days of work) does our current population still represent before it clears?
- Which group would free up the most kennel-days if we could speed up its outcomes?

**Cutting the question finer**

- Do any of these patterns differ by intake type (stray, owner-surrender, transfer-in)?
- Do they differ by animal size or gender, by shelter facility, or by any grouping we care to define?
- What do we see if we zero in on a single intake stream, one location, one age band, or one calendar window?

We usually plot complete distributions rather than just averages.  We compute confidence intervals that tell you whether you can rely on a given metric or curve.  The sections below explain why these distinctions matter and how to read what the tool gives back.

### The core idea

You give it records of every animal that passed through (or was sitting in) your shelter during the study window, and you tell it which time periods you want to compare, say, the last three calendar quarters. You define what subset of the data you want to look at, and how to group them.  The tool then computes, with proper statistics behind it, whether length-of-stay (LOS) actually changed, and how it varies by outcome (adoption vs. euthanasia), by intake, or by animal group.

### Why full curves matter, and why averages mislead

The most important thing mLOS shows you is the **full curve**: at each day since intake, what fraction of animals are still in care? A single number (a mean or median) cannot tell you what a curve can.

Curves might **cross**. You might see that animals in one period fall behind those in another in the first two weeks, but then catch up and eventually overtake them. The two periods can produce similar overall averages while having very different dynamics. This is a useful insight that averages hide.

The **median** is particularly deceptive. It is usually a small integer, and it can stay the same even as large changes occur in the LOS curve. The hardest-to-place animals consume the most shelter resources and have stays above the median. Changes in this sub-population can impact the shelter without moving the median. The 90th percentile of LOS is one way of looking at this effect.  The full curve is better, because it shows all percentiles in one place.

The **mean** is better, but it still blends short-stay, medium-stay, and long-stay effects into one number. If shorter stays got better while longer stays got worse, those effects dilute or cancel each other in the mean. The full curves show them separately.

### Why it's harder than just tabulating and averaging

Two statistical problems make it misleading to simply tabulate each animal's stay and then average. mLOS is built to handle both:

- **Animals still in the shelter haven't finished their stay yet.** If you exclude them, you bias your numbers downward: the animals with the longest stays are exactly the ones most likely to still be there. mLOS treats them correctly as "still counting" (statisticians call this right-censoring).
- **Animals already in the shelter when a study period begins shouldn't have their whole stay counted**, only the part that falls inside the period. Skip this and your estimates get distorted.  mLOS treats them as "counting" only from the start of the period (statisticians call this left-truncation).

That's why the tool requires every animal whose stay **overlaps** with the study window, not just animals that arrived or left during it.

### What "steady state" means

A few of the population numbers mLOS reports, like the expected census by tenure and the in-care tenure profile, talk about the animals sitting in your shelter. But mLOS isn't measuring the exact animals in your shelter on a particular date. The tool only works with two kinds of numbers. The first is straightforward averages and rates computed from your data over the period you chose (how many animals you actually took in, how many days of care you actually delivered, and what the average census was during that period). The second is what the intake and length-of-stay patterns would produce if they simply kept going, unchanged, indefinitely; that hypothetical, settled-down population is what's meant by **steady state**.

Comparing the two tells you something real. If your observed census and the steady-state prediction roughly agree, your population is behaving the way its current intake and outcome patterns imply it should, and there's nothing unusual building up or draining away. If they disagree, your shelter is still working through a transition, perhaps recovering from a surge of intakes, or gradually clearing a backlog, and the steady-state number shows where the population is heading, not where it is today.

So when a plot or a metric refers to the "expected" or "predicted" population, read it as a projection from your fitted patterns, not a headcount. A true point-in-time snapshot, literally which animals are in the building right now, is not something mLOS computes. That could be added as a future feature, but today every population figure it reports is either a period average or a steady-state projection.

### What you feed it

- A CSV (spreadsheet-style text file) of animal records: when each arrived, when it left (if it has left), and what happened to it.
- A settings file (in YAML, a simple plain-text format) defining your comparison periods and a few options, such as how outcome codes in your data map to the three categories the tool understands: live release to the community (adoption, return-to-owner), other live outcomes (transfer, foster), and non-live outcomes (euthanasia, death, loss).

The settings file offers additional capabilities.  You can filter your data on the fly (e.g., study only large dogs), map values (e.g., convert one animal size to another), or control details of the plots.  But for a standard run on a simple CSV data file, you can ignore the advanced settings.

If your shelter houses multiple species, run **one species at a time** (e.g., dogs only): species differ so much in their length-of-stay dynamics that mixing them blurs every curve and average. Use the animal-group feature for distinctions *within* a species, such as by size or gender.

### What you get back

- **The in-care stay curves** showing the probability an animal is still in care over time, for each period, so you can visually see whether and how the curves shifted, and whether they cross.  (Statisticians call these "survival" curves, but here they describe whether an animal is still in the shelter.)
- **Remaining-stay curves**: if an animal has already been there X days, how many more days should you expect?
- **Competing-risk breakdown** of animal outcomes (adoption vs. transfer vs. euthanasia) and how the outcome mix changes the longer an animal stays.
- **Population-load numbers**, including observed and expected daily census.
- **Stratified results**: The above calculations and curves but **separated out** by period, by intake type, or by animal group (defined flexibly from your data).  A **stratifier** is any of the axes that we use (period, intake type, animal group), whose discrete **levels** (or **strata**) split the data into categories.   In these plots, each stratification is done separately.
- **Cox regression** (and optional **Weibull regression**): Tests of whether the differences between periods, intake types, and animal groups are real or just noise, and how large they are, all in a single regression that includes every stratification at once. Cox reports **hazard ratios** (how much faster or slower animals leave: 1.2 means a 20% higher discharge rate, so shorter stays). The optional Weibull reports a similar comparison directly as **LOS ratios** ("stays run 30% longer than the reference"), which is usually the more intuitive number.
- **Per-predictor Weibull regressions** *(optional)* — one LOS ratio per stratifier (period, intake type, animal group), each adjusted for the other two exactly as the general Weibull above, but additionally letting the *other* predictors' groups differ not just in how long they stay but in *how their chances of leaving change over time* — a distinction the single-shape Cox and general Weibull models don't make.
- **Per-predictor stratified Cox regressions** — the same idea applied to Cox, and always run whenever two of the three stratifiers are usable. One fit per stratifier reports that stratifier's hazard ratios while giving every combination of the other two its own separate baseline, instead of assuming, as the main Cox regression does, that a single baseline shape fits them all. Compare a hazard ratio here against the main Cox table's: agreement says that assumption was not costing you anything, and a real gap says it was. These fits are in `results.json` but on no worksheet. The slide deck builder also draws on them.
- **A record of what was screened out** — a `Data_Preparation` worksheet, and a `data_preparation_stats.csv` beside it, tracing how the rows of your file became the rows the analysis ran on: every stage in the order it ran, what each one cut or rewrote, and how many of the values your settings name were actually found.  It is worth reading on a first run, and essential when you use the optional settings that screen and transform the data before the main statistical analysis.

### Choosing your period boundaries

The most consequential decision is where to draw the period boundaries. Useful dividing points are dates when something actually changed: a new program launched, a policy shift took effect, a staffing reorganization happened, a community initiative began. Aligning boundaries to real events makes the comparison meaningful: you're asking "did things change after our policy change?" rather than dividing time arbitrarily.

Practical tips: align boundaries to a fixed day of the week (e.g., Monday) to avoid day-of-week noise in intakes and outcomes. Aim for at least 100 outcomes per period; start with longer periods and shorten only if data are sufficient (i.e., if the confidence intervals in numerical values and plots are narrow).

### Choosing your `restricted_stay_cap`

This setting deserves the same care as your period boundaries. It tells the tool how long a stay can plausibly be before it should be treated as an outlier or a possible data discrepancy (a data-entry error, or an outcome that was simply never recorded) rather than a genuine long stay. Set it too low and you remove the long-stay portion of real animals, biasing the restricted mean downward. (We talk about **restricted mean** rather than a plain mean, precisely because of this cap.) Set it too high, especially with sparse data, and a few implausible or mis-recorded stays can dominate the restricted mean. Do a test run with a somewhat long cap (e.g., 365 days), check the in-care stay curves (labeled as KM for Kaplan-Meier curves), and adjust the cap down to where the curve has flattened near zero (very few stays last that long).  Be more conservative the sparser your data.

**One number tells you whether the cap is shaping your answers.** It is `km_still_in_care_at_cap` on each stratum sheet, the height of the KM curve at the cap. That's the fraction of an arriving cohort still in care when the cap arrives, hence the fraction whose stay isn't fully modeled (though their stays still count up to the cap). Read it before quoting any tenure or census figure. **Half a percent is already worth attention, and one percent deserves a second run at a different cap.** That sounds like an over-reaction to a tiny number, but it's not. The census and tenure figures describe the animals in care at a moment, and an animal that stays a very long time is in care on very many days. A remnant that rounds to nothing among arrivals can be several percent of your residents. On **OC1** and **OC2**, the large dogs still in care at the 365-day cap are under one percent of that group's intakes but their stays **up to the cap** already supply about a tenth of the group's whole restricted mean. If they're not data errors and they have additional long stays past the cap, there's a risk of underestimating the LOS and census.

The cap does **not** drop the animals that reach it. A stay that hits the cap is treated as still in care on every day up to the cap, counted at full weight in every curve and every animal-day total, exactly like an animal whose outcome you are still waiting for. The KM curve below the cap is identical to what you would get with no cap at all. The only thing missing is what those animals would have gone on to do *after* the cap.

Where the missing tail shows up, worst first:

- **The resident tenure quantiles** (`per_resident_past_days_restricted_median` and `per_resident_past_days_restricted_p90`) are the most cap-sensitive numbers the tool produces, and the only ones that never warn you. They describe the tenure (past days in care) of the resident population. They are read off a tenure profile that stops at the cap, which amounts to assuming every animal stops being a resident if it hits the cap, and they always return a number: there is no "not reached" for these the way there is for the median length of stay. On the large dogs of **OC1** and **OC2**, if the animals at the cap were in fact to stay another 200 days on average, the reported 90th percentile of resident tenure would move from 190 days to roughly 254. Treat these quantiles as lower bounds.
- **The census and animal-day figures** (`expected_census`, `expected_past_animal_days`, `expected_future_animal_days`, `per_resident_past_days`) are lower bounds, and understated by proportionally more than the at-cap fraction, for the length-of-stay weighting reason above. They move less than the quantiles do.
- **The restricted mean length of stay** is a lower bound on the true mean, by design. This is the case where the cap is doing its intended job and saying so: the word `restricted` in the name is the disclosure.
- **The median and 90th percentile of length of stay** are usually not affected, and flag themselves when they are. They come straight off the KM curve, which the cap does not distort below the cap. If the curve never falls to the level a quantile needs, the tool reports no value rather than a number pinned near the cap.

The two jobs you are asking the cap to do therefore pull against each other: a low cap protects the restricted mean from bad records, but it also puts a ceiling on every tenure and census figure. There is no setting that escapes the tension, but there is a cheap way to measure it. Runs take seconds, so when `km_still_in_care_at_cap` is not near zero, run the analysis again at a noticeably different cap and compare. If a number you plan to quote moves materially, quote it as a range, say which cap produced it, and revisit your data. With more reliable data, you can afford to use a higher cap.

### Getting more out of the tool

The standard run produces a comprehensive set of results, but it is also a starting point. When a curve or a hazard ratio raises a question, the settings file gives you six levers for exploring it, none of which requires regenerating your shelter data file:

- **Period definition**: redraw the boundaries around the event you care about, or specify a single period to zero in on one window. The stratified plots by intake type and animal group are produced for the **aggregate across all periods**.  With only one period specified, the aggregate equals the period, so you get the plots for a single window.
- **Group generation** (`animal_group_columns`): build `animal_group` from any column or combination of columns in your file (gender plus size, a facility column to compare locations, facility plus size), so the grouping follows your question rather than whatever a pre-existing `animal_group` column happens to hold.
- **Intake type filtering** (`intake_filter_pass` / `intake_filter_cut`): restrict the analysis to one or more intake streams.
- **Group filtering** (`animal_group_filter_pass` / `animal_group_filter_cut`): restrict it to the groups of interest, including composite groups built by `animal_group_columns`.
- **Filtering by any other column** (`other_filter_column_name` with `other_filter_pass` / `other_filter_cut`): subset on something the analysis does not otherwise use, such as an **intake subtype** or an age band.
- **Relabeling** (`intake_type_map` / `animal_group_map`): rename or merge values before anything counts them, so a handful of rare labels can be folded into a category they approximately match instead of standing as strata of their own.

Syntax and fine print for the filters are in the [value-filters section](#value-filters) of the [settings reference](#settings-file-yaml); relabeling is under [value maps](#value-maps), and group generation under [`animal_group_columns`](#animal_group_columns).

When you re-run on a subset, it helps to know what moves and what stays put:

- **Each curve on a stratified plot is computed from its own stratum's rows alone.** Filtering out categories of a dimension therefore leaves that dimension's surviving curves exactly as they were: cut TRANSFER intakes, and on the intake-type (stratified) plot the STRAY and OWNER curves are unchanged. The TRANSFER curve simply disappears. This invariance is deliberate (and tested), so you can compare a filtered run against the full run curve by curve.
- **Everything that aggregates across the filtered dimension does change.** When you stratify by one dimension you are aggregating across the others: the plot by animal group pools all intake types, so removing one intake type re-estimates every animal group's curve from a different mix, and the same goes for the period plots and all unified results (the unified curves and the `By_All` sheet). Refining a category has the mirror-image effect: splitting the animal groups by size redraws the animal-group plot with finer curves but leaves the intake-type and period plots untouched, because their strata still contain exactly the same rows.
- **The Cox and Weibull regressions change under all of these edits, in every row of their tables.** They are joint, adjusted models: each ratio is estimated holding the other predictors fixed, so eliminating a category, refining one, or narrowing the window changes the adjustment behind every coefficient, not only the edited predictor's rows. A hazard ratio can therefore move after you filter a different column, which reflects the changed adjustment rather than an error. It is also why the marginal curves and the adjusted ratios can legitimately tell different stories. The Weibull sheet's crude-versus-adjusted shape comparison is the built-in illustration of the same phenomenon.
- **Zeroing in on a single sub-period changes everything, even with the same categories**: stays are truncated and censored at the new window's edges, so every curve and every regression now describes that window alone.

Two notes of caution. Filters shrink the sample, so watch the confidence intervals and keep the 50-outcomes-per-period guideline in mind. And if you filter away the level you named as a Cox reference (`intake_type_reference`, `animal_group_reference`), the ratios for that predictor come out blank. Choose reference levels from among the values you plan to retain.

---

## Technical Reference

### Overview

mLOS is an R-based tool for analyzing animal shelter length-of-stay (LOS) distributions using statistical methods. It compares LOS across multiple user-defined time periods and, optionally, across intake types and animal groups. It also compares competing outcome types.

It relies on techniques from "survival statistics", but here "survival" just means an animal is still in care, i.e., has no outcome.  The differentiation between outcome types (including live vs. non-live outcomes) is done separately.

**Required R packages:** `survival` and `yaml`; `jsonlite` is additionally required to write the results JSON and `openxlsx` to produce the Excel results workbook (without either, the run still completes and the corresponding export is skipped with a warning). Optional: `flexsurv` (only if `parametric_regression` is enabled). Running the tool locally requires R itself installed on your computer as well as these packages; see https://cran.r-project.org/ for installing R and its packages.

**Required data: all animal stays that have any overlap with the study periods**.  Not just outcomes during the study periods. Not just intakes during the study periods.

### Plots

The plots are the heart of the methodology.  Each line plot is saved as a PNG file with a companion CSV containing the plotted data (and restricted mean values, where applicable). **Stack plots are the exception: they carry no CSV**, because each draws the same numbers as its line counterpart, whose CSV sits beside it under the same name without the `_stack` suffix. Stack plots also carry no confidence-interval ribbons, since bands stacked on one another leave no place for ribbons.

**Why every plot ships with its data.** The plots this tool draws are one reasonable set of choices, and they will not be everyone's. You may want points rather than lines, two strata combined in a single panel, the unified curve drawn over the stratified ones for comparison, a different axis range, a house color scheme, or a figure formatted for a particular journal. Rather than add a setting for each of these, the tool gives you the numbers: every plot's companion CSV holds exactly what was drawn, in a shape you can paste straight into Excel, R, Python, or a graphing tool. Columns can be cut and pasted across CSV files, so combining curves from separate plots is a spreadsheet operation rather than a code change.

The CSVs are a supported output on the same footing as the plots themselves, not a debugging by-product, and they are deliberately kept in a plain, readable form: a `days` column, one column per stratum, and (where it applies) a single summary row between the header and the day grid. The manifest in `results.json` describes each file, its columns, and its units, so a script can find and read them without knowing the naming conventions.

**Confidence-interval columns.** Where a curve has a pointwise confidence interval, the file carries its bounds as a block of extra columns to the right of the whole grid of estimates, rather than a pair beside each column they bound. Most readers want the curves and nothing else, and this layout lets them read the left of the file and stop. In the stratified files the bound columns are named for the column they bound, `<stratum>_ci_lower` and `<stratum>_ci_upper`, paired per stratum and in the same order as the estimates; the two unified files name theirs for the single curve or for the outcome instead (`lower_ci` and `upper_ci` in `km_survival_unified.csv`, `ci_lower_L` and its counterparts in `aj_cif_unified.csv`). The summary row above the day grid leaves the bound columns empty, because aggregating a pointwise bound down its column would not give the bound of the aggregate; the intervals around the summary statistics themselves are in the workbook and in `results.json`. Bound cells can also be empty in the tail of a stratum whose curve has already reached zero, where every remaining animal has left and the estimator reports no interval; the ribbon on the matching plot stops at the same day for the same reason.

Four families carry bounds: the pooled `km_survival_unified` and `aj_cif_unified`, and the stratified `km_survival_by_*` and `aj_cif_by_*_outcome_*`. They are written whether or not the plot draws its ribbon, since [`show_km_ci_ribbons`](#show_km_ci_ribbons) and [`show_aj_cif_ci_ribbons`](#show_aj_cif_ci_ribbons) decide whether overlapping bands stay legible on a panel, which has nothing to do with whether you want the numbers. The other files have no bounds to carry: the remaining LOS, census, and in-care tenure curves are transforms of a KM curve rather than estimates with intervals of their own, and the conditional outcome probabilities are a ratio of cumulative-incidence differences that the fit gives no interval for.

**Strata (level) ordering**. Everywhere strata appear (plot legends, CSV columns, worksheet columns, and the regression tables) they follow one fixed canonical order: chronological for periods, alphabetical for intake types and animal groups. Periods are intervals of dates, so any other order would read as wrong. Intake types and animal groups have no natural order, so alphabetical is used purely as a stable convention: on a fixed set of categories it never changes from run to run. We rejected ordering by frequency because, when two categories have similar counts, a slight change to the data (for example, a small shift of the study period) can swap the categories' positions, which makes runs hard to compare side by side.

**When are stratified results produced?** Stratification is meaningful only when the stratifier exists (recalling that `intake_type` and `animal_group` are optional) **and** has two or more levels (strata) to compare. A stratified plot or worksheet is meaningless if a stratifier has only one level, because it would only replicate information in the unified (unstratified) plots and statistics which are always produced.  This applies to all KM plots, AJ plots, their CSVs, and worksheets in the Excel workbook that are described by stratifier: by period, by intake type, or by animal group.

#### Kaplan-Meier (KM) plots

| File | Description |
|---|---|
| `km_survival_unified` | Single KM curve pooled across all periods and all animals. Always shown with a shaded confidence-interval ribbon. |
| `km_survival_by_period` | KM curves overlaid for each period, the primary comparison plot. |
| `km_survival_by_intake_type` | KM curves by intake type, pooled across all periods. |
| `km_survival_by_animal_group` | KM curves by animal group, pooled across all periods. |

The three `km_survival_by_*` plots can optionally show the same style of shaded confidence-interval ribbon per stratum (drawn as a true stair shape matching the curve). The ribbon is off by default (unlike the unified plot above, where it's always on). Enable it with `show_km_ci_ribbons: true` in the settings file. The setting governs the picture only: the bounds are in `km_survival_by_*.csv` regardless.  CI ribbons are not available on the rest of the KM-derived plots described below.

**The three marks.** `km_survival_unified` carries a dashed vertical line at each of its median, its 90th percentile, and its restricted mean, in red, orange, and green, with the value spelled out in the legend. The two unified companion plots described below, `km_remaining_los_unified` and `km_in_care_tenure_unified`, are marked the same way in the same three colors, so the marks read alike across all three unified figures. A statistic the curve never reaches (a median beyond the cap, say) has neither a line nor a legend row; one that falls beyond the plotted x range, which is set by [`plot_stay_cap`](#plot_stay_cap), keeps its legend row and its value, noted "off scale". The stratified plots are not marked: with several curves on a panel, it would be confusing. These per-stratum statistics can be found in the workbook.

#### Remaining LOS plots

For the pooled KM curve and for each stratified KM plot, a companion remaining-LOS plot shows the expected number of days still in care for an animal that has already spent X days in the shelter, as a function of X. This is an end-of-day quantity: "X days in the shelter" means the animal is still in care at the end of day X, so the remaining LOS value is never below 1: even an animal leaving tomorrow accrues one more counted day. At X = 0 the value equals the restricted mean, providing a consistency check. The computation uses the conditional survival formula: Remaining LOS(X) = 1 + (1/S(X)) × Σ S(t) for t = X+1 to τ−1, where S(t) is the KM survival probability and τ is `restricted_stay_cap`.  This cap is an upper bound for the stay, beyond which we stop tracking outcomes for statistical purposes.

The "Days Already in Care" axis on this and the next two plot families (census by tenure, in-care tenure) is the **elapsed** count: X = 0 is the intake day, one less than the animal's inclusive days in care (which is 1 on the intake day). See "Which day counts? Who is in the census?" for the full convention.

| File | Description |
|---|---|
| `km_remaining_los_unified` | Remaining LOS pooled across all periods and all animals, the companion of `km_survival_unified`. Its single column is headed `All`, matching the workbook's By_All sheet. Titled "tied to in-care tenure statistics" for the reason below. |
| `km_remaining_los_by_period` | Remaining LOS by period. |
| `km_remaining_los_by_intake_type` | Remaining LOS by intake type. |
| `km_remaining_los_by_animal_group` | Remaining LOS by animal group. |

**Why the pooled plot is marked at someone else's statistics.** This curve has no median or 90th percentile of its own to mark, and computing one would be a mistake. Remaining LOS is a *function of tenure*, not a distribution over animals: its column holds one value per day of the tenure grid, so a median of those values would be a median over days on a chart, weighting the one day at tenure 200 exactly like the one day at tenure 3, and it would be useless. What is meaningful is the remaining LOS *at* a tenure that itself means something. So `km_remaining_los_unified` is marked at the median, 90th percentile, and mean tenure of the in-care population, the three statistics of the [in-care tenure plot](#in-care-tenure-plots) below, and its legend reports the remaining LOS the curve reads at each of them: "the animal in the middle of the standing population has been here 21 days and can expect 55 more". The values are read at the day step the mark falls in, which is the step the drawn line crosses, so the legend and the picture agree.

One reading to avoid: the value at the mean tenure is not the average remaining stay across residents. That average is `per_resident_future_days` in the workbook, and it equals the mean tenure plus exactly one day; the curve read at the mean tenure sits well above it on a heavy-tailed shelter, because averaging a curve is not the same as reading it at the average. The legend says "At mean tenure" rather than "Mean" for exactly this reason. Both numbers are correct answers to different questions: this mark answers "what does a resident of typical tenure still owe us", `per_resident_future_days` answers "what does the standing population owe us, per head".

All three marked values are reported as well as drawn, as `remaining_days_at_mean_tenure`, `remaining_days_at_median_tenure`, and `remaining_days_at_p90_tenure` in the census-aggregates section of every stratum sheet and in `results.json`, so the per-stratum readings exist even though only the unified curve is marked. The first of them is also this family's CSV summary row. The restricted mean is not used here: it belongs to the KM curve, whose own CSV beside this one reports it, and it is in any case the value this curve shows at X = 0.

#### Census by tenure plots

**Steady state**, the assumption behind this plot and the one that follows it, means the hypothetical population produced by holding the fitted intake rate and length-of-stay curve constant indefinitely: a projection from your fitted patterns, not a measurement of any actual day's headcount. See [What "steady state" means](#what-steady-state-means) earlier in this guide for the full picture.

For each stratified KM plot, the census-by-tenure plot turns the same curve into a steady-state population profile: how many animals you should expect in care at each number of days already in care, if intakes keep arriving at the observed daily rate and stays keep following the fitted curve. The value at day X is the stratum's mean daily intakes times its KM survival at X, so the curve is the KM curve rescaled from a probability to a headcount.

The area under each curve, or the sum of the corresponding CSV column over all days, gives the **predicted average census** for that stratum (Little's law: average population = intake rate × average stay). Dividing the column by that total gives the tenure mix of the in-care population, i.e., what fraction of the animals present have been in care X days. (See below for a survival-curve representation of the same information, in the in-care tenure plots.)  The area under the curves can also be read over intervals in X: it visualizes how many animals of each stratum are expected to be resident with tenure in the chosen X interval.

On the other hand, reading across the strata at a fixed X shows how the tenure-X in-care population splits among the strata. Summing curve values over all strata, i.e., a row in the CSV file, gives the total census at tenure X. That row-sum reading is exact for the intake-type and animal-group plots, whose strata partition the population; the by-period columns are instead separate per-period steady states, so summing across periods does not correspond to a single real census.

These plots complement the remaining-LOS plots above: one says how many animals sit at each tenure, the other how many more days each of them expects; together they describe the standing population and its future workload.

The companion CSV carries a single header row above the day grid, `expected_census` (the column total; the same name the workbook's census-aggregates section uses for this quantity), matching the one-header convention of the other plot CSVs. The other aggregates are recoverable from the grid: the scale factor is the day-0 row (mean daily intakes = the expected number in care at zero days), and the future care demand is the summed product of the census profile and the remaining LOS. The workbook's census-aggregates section reports all of them directly.

| File | Description |
|---|---|
| `km_census_by_tenure_unified` | Expected animals in care by tenure, pooled across all periods and all animals. Its single column is headed `All`, and its summary row is `expected_census`. |
| `km_census_by_tenure_by_period` | Expected animals in care by tenure, per period. |
| `km_census_by_tenure_by_intake_type` | Expected animals in care by tenure, per intake type. |
| `km_census_by_tenure_by_animal_group` | Expected animals in care by tenure, per animal group. |

There is also a pooled `_unified` file of the same type, but it is less informative. It is simply the unified KM curve multiplied by a single number, the overall intake rate: the same shape with a different y-axis. The expected census is the unified curve's second header row.  It is also reported as the `expected_census` row of the workbook's By_All sheet and in `results.json`.

The value of this family lies entirely in the **relative** heights of its curves. Each stratum is scaled by its own intake rate, which is what puts the levels on a common footing in numbers of animals and makes the cross-stratum readings above possible: how the tenure-X population divides among the strata, and which strata contribute most of the animals at each tenure. A stratum with a long average stay but few intakes and one with a short average stay but many can end up contributing comparable numbers, and only the rescaling shows that.

#### In-care tenure plots


For the pooled KM curve and for each stratified KM plot, a companion plot shows, for each X, the fraction of the steady-state in-care population whose tenure (days already in care) exceeds X. Do not conflate this with the previous plot, census by tenure, which is a **count** at each exact tenure value X. The in-care tenure plot is a **fraction**, for tenures **strictly exceeding** X, not equal to it.

This plot answers a question the KM curve does not: not "how long do the animals we take in stay?" but "how long have the animals we house already been here?" Read it beside the KM plot on the same day axis. The two describe different populations: the KM is the intake flow, while the in-care tenure plot is the standing population, which is weighted toward long-stayers because a long stay is present on more days than a short one. So this curve normally sits **higher than** the KM for the heavy-tailed stays (decreasing-hazard in statistical terminology) typical of shelters. The gap is how much the animals you are housing skew longer than the animals you take in. When the length of stay is memoryless (a constant discharge rate regardless of time already in care) the two curves nearly line up, but not exactly: the in-care tenure curve at X reads like the KM curve one day later, at X+1, not like the KM curve at X itself (the strict "exceeds X" convention, needed so the curve's column total correctly gives the mean in-care tenure, sets it one day ahead of an exact overlay).

This curve doesn't start at 1.0 the way the KM curve does. At X = 0 it reads `1 − 1/restricted mean LOS`, not 1, because that fraction of the standing population was admitted today (tenure exactly 0) and the strict "exceeds 0" excludes them. Short-stay strata therefore start noticeably below 1; long-stay strata start close to it. The starting point X = 0 here is the **elapsed** "days already in care," not the tool's usual, inclusive LOS clock. An animal admitted today reads X = 0 on this axis, even though its length of stay so far, on the inclusive clock used everywhere else in the tool, already stands at 1 day (a same-day arrival-and-departure stay has LOS = 1, never LOS = 0; see "Which day counts? Who is in the census?" for the full convention).

Each curve is a transformation of that stratum's KM curve alone (the intake rate cancels out), so it needs no assumption about arrival rates. The companion CSV carries a single header row, `per_resident_past_days` (the same name the workbook uses for this quantity) which is the mean tenure of the in-care population and equals the column total.

The pooled plot is marked at three statistics of this same tenure distribution: its median, its 90th percentile, and its mean. The first two are `per_resident_past_days_restricted_median` and `..._restricted_p90` in the workbook, where the red and orange lines cross the curve at 0.5 and 0.1; the mean is `per_resident_past_days`, the column total. Unlike the KM median these are always reached, because the profile is built on the capped day grid (i.e., assumes no animals remain in care past `restricted_stay_cap`).

**This curve, and the median and 90th percentile read off it, are the tool's most cap-sensitive outputs.** The profile runs from day 0 to the stay cap and is scaled to sum to one over that range, which amounts to reading the tenure of a population in which every animal at the cap left on that day. The animals at the cap are fully counted up to it; what is missing is their tenure beyond it, and this is the view that feels that absence most, because a very long stay is present on very many days. Check `km_still_in_care_at_cap` on the stratum sheet before quoting anything from this curve, and see "Choosing your `restricted_stay_cap`" for how far the numbers can move.

| File | Description |
|---|---|
| `km_in_care_tenure_unified` | In-care tenure profile pooled across all periods and all animals, the companion of `km_survival_unified`. Its single column is headed `All`, matching the workbook's By_All sheet. |
| `km_in_care_tenure_by_period` | In-care tenure profile, per period. |
| `km_in_care_tenure_by_intake_type` | In-care tenure profile, per intake type. |
| `km_in_care_tenure_by_animal_group` | In-care tenure profile, per animal group. |

#### Aalen-Johansen (AJ) plots

AJ analyses model L (community live outcome), T (other live outcome), and N (non-live outcome) as competing risks. Each outcome type gets its own plot, if that outcome is observed.

The central quantity is the **cumulative incidence function (CIF)**. The CIF of an outcome type is the probability, as a function of day X, that an animal has left care by that specific outcome type on or before day X. Each CIF starts at 0 and can only rise; for example, a value of 0.55 at day 30 on the L curve means that an estimated 55% of incoming animals reach a community live outcome within their first 30 days in care. At any day, the three CIFs add up to the probability of having left care for any classified reason by then, and the remainder up to 1 is the probability of still being in care.

Both the CIFs and the conditional probabilities below are tabulated over the **AJ analysis window**: from intake out to the last observed time (the last day any stay was still under observation, whether it ended in an outcome or was censored). That last day is at most the `restricted_stay_cap`, but is often well short of it, because the AJ curves stop where the data run out rather than being carried flat to the cap. (The Kaplan-Meier analysis instead always runs to the cap; the Limitations section explains why holding a cumulative-incidence curve flat past its last event would misrepresent the data.) Each stratum gets its own analysis window, so on a stratified AJ plot different strata's lines can legitimately end at different days.

From AJ analysis, we also compute the conditional outcome probability: given that an animal is still in care at day X, the probability the animal leaves by each outcome type before the end of the AJ analysis window.

Both quantities are computed pooled, and again separately within each level of every available stratifier: period, `intake_type`, and `animal_group`. The stratified files are named after the stratifier, so `<stratifier>` below stands for `by_period`, `by_intake_type`, or `by_animal_group`. Each set appears only when its stratifier exists (recall that `intake_type` and `animal_group` are optional) and has two or more levels to compare. A single-period run does not stratify by period.

| File | Description |
|---|---|
| `aj_cif_unified` | Cumulative incidence functions (CIF) for all three outcome types pooled; shows the probability of each outcome over time. Always shown with shaded confidence-interval ribbons. |
| `aj_cif_<stratifier>_outcome_L` | CIF for community live outcomes (L), with one line per stratum. |
| `aj_cif_<stratifier>_outcome_T` | CIF for other live outcomes (T), with one line per stratum. |
| `aj_cif_<stratifier>_outcome_N` | CIF for non-live outcomes (N), with one line per stratum. |

The `aj_cif_<stratifier>_outcome_*` plots can optionally show the same style of confidence-interval ribbon, one per stratum. Off by default (unlike the unified plot above, where it's always on); enable with `show_aj_cif_ci_ribbons: true` in the settings file. The setting governs the picture only: the bounds are in `aj_cif_<stratifier>_outcome_*.csv` either way. Not available on the conditional outcome-probability plots below, for which the fit does not produce an interval.

| File | Description |
|---|---|
| `aj_conditional_unified` | Conditional outcome probability, pooled across all strata: given that an animal is still in care at day X, the probability the animal leaves by each outcome type before the end of the AJ analysis window. All three outcome types as separate lines, one per outcome. |
| `aj_conditional_unified_stack` | The same pooled conditional outcome probability as `aj_conditional_unified`, drawn instead as a stacked area so the three outcome types visibly sum to the total probability of having left by the end of the window at each day. Same underlying numbers, different picture. PNG only, no CSV. |
| `aj_cif_unified_stack` | The same cumulative incidence as `aj_cif_unified`, drawn as a stacked area. The bands sum to the overall CIF, so the top of the stack reads as the probability of having departed by that day and the white space above it as the probability of still being in care. PNG only, and without the confidence-interval ribbons the line version carries. |
| `aj_conditional_<stratifier>_outcome_L` | Conditional outcome probability for L (community live outcome), with one line per stratum. |
| `aj_conditional_<stratifier>_outcome_T` | Conditional outcome probability for T (other live outcome), with one line per stratum. |
| `aj_conditional_<stratifier>_outcome_N` | Conditional outcome probability for N (non-live outcome), with one line per stratum. |

Each `_stack` plot draws the same numbers as the plot it is named after, so only the line version carries the companion CSV: `aj_cif_unified.csv` serves `aj_cif_unified_stack.png`, and `aj_conditional_unified.csv` serves `aj_conditional_unified_stack.png`. Read the stacks for composition and the lines for individual curves and their confidence intervals.

Line plots are drawn in staircase form, changing only on integer days, which is how the underlying estimates actually behave; stacked area plots interpolate between days instead, purely for improved visual presentation.

A note on what a stratum means, because it differs by stratifier. Periods slice each animal's stay at the period boundaries, so an animal that spans two periods is counted in both, and each period's curves describe only what happened inside that window. Intake type and animal group do not slice: an animal keeps its whole stay in whichever level it belongs to, so those curves describe the full study. Both are correct, they simply answer different questions, and it is worth keeping the distinction in mind when reading a by-period curve next to a by-animal-group one.

#### Plot strata limit

Stratified plots (KM curves and AJ lines, each by period, intake type, or animal group) are produced only when the stratifier has **10 or fewer levels** by default, adjustable up or down with the `max_plot_strata` setting (with a hard maximum of 13, the size of the plot color palette; see the [settings reference](#settings-file-yaml)). When the limit is exceeded the plot is skipped with a console message, but the companion CSV file is still written (unless you have separately turned that CSV off; see [Stratified-output selection](#stratified-output-selection)). All numerical analyses (KM fits, Cox regression, AJ) run on the full data regardless of how many strata there are.

This limit exists purely for **visual legibility**. How many curves stay readable on one panel depends on how well they happen to separate, on whether confidence-interval ribbons are drawn (ribbons overlap and muddy a panel and can be controlled with `show_km_ci_ribbons` and `show_aj_cif_ci_ribbons`), and on your own preference. Ten curves that separate cleanly may read better than four that tangle. Since nothing but the rendering is affected, and the CSV of every stratum is written either way, setting the limit is a matter of taste rather than a statistical decision. See `max_plot_strata` in the [settings reference](#settings-file-yaml) for how to change it, including how to turn stratified plots off entirely while keeping their data.

The plot limit is applied slightly differently by the two analyses: the KM plots count the stratifier's **levels**, while the AJ plots count the strata that actually produced a usable fit. The two agree unless some stratum contains no analyzable outcome at all. Such a stratum gets no AJ line, so an AJ panel can show fewer lines than the KM panel for the same stratifier, and because AJ counts it as one fewer, AJ can stay within the limit and draw its plots where KM exceeds it and skips. This is not common, but if you see KM and AJ differ in the number of lines they show or in which stratified plots they construct, this is the reason.

### Numerical output

#### The console log

Console (terminal) output is captured in an "analysis_log.txt" file. It prints progress reports as the run proceeds, diagnostics such as warnings, and a few summary statistics. The results themselves are in the workbook and in `results.json`.

#### Each run archives the one before it

Before anything is written, the previous run's output is moved into a dated subdirectory of the results folder, named `mLOS_<YYYYMMDD>_<nnn>` with the number counting runs on that date. The results folder therefore always holds exactly one complete run, which means a file left over from an earlier run cannot be mistaken for a current one, and a result you wanted is not silently overwritten. However, only files this tool generates are moved, namely the workbook, the log, the JSON, and the plots and CSVs. If you keep your own notes or spreadsheets in the same folder they're left untouched. The archived runs are not deleted; they accumulate until you remove them yourself. They sit inside the results folder so they stay in view.

If a run fails early, for example because a settings file was misnamed, the archiving has already happened: it runs before the settings file is even read. Nothing is lost, but the results folder will look emptier than you expect, because the previous run's files now sit inside the newest `mLOS_<YYYYMMDD>_<nnn>` subdirectory and the failed run wrote little or nothing to replace them.

#### The results JSON

Results are written to `results.json` first, and the Excel workbook is a rendering of that file. Everything the workbook shows is in the JSON, in full precision and under stable names, and the JSON carries more besides: it is meant to be complete enough to build a report or a slide deck from, so a value is left out of it only when the tool stops computing that value altogether, never because one particular consumer had no room for it. Dropping a section from the workbook therefore doesn't remove it from the JSON.

The one class of result that lives outside the file is the per-day curve grids, which stay in the companion CSVs and are reached through the `outputs` manifest described below. The JSON is the file to read from a script, a notebook, or another program; the workbook is the file to read yourself. Its `schema_version` field marks the layout, and changes when a field changes meaning or disappears.

**Not all results are written to the Excel workbook.** The per-predictor Cox regressions are an illustration of this. They are computed on every qualifying run and written to `cox.stratified_variants` (keyed `period`, `intake`, `group`), and copied to `strata.<stratifier>.cox_stratified` beside that stratifier's other measures. Each such entry carries the fit's formula, its row and event counts, how many baseline strata it used and how many of those held events, its hazard-ratio table in the same shape as the main Cox table's, its four global tests, and its concordance. Of all that, the workbook shows only the hazard ratios, in the Hazard ratios block of that stratifier's own sheet. The tests and the concordance stay in the JSON because they are computed against a stratified baseline, so they answer a different question from the main Cox regression's and should not be compared with them, whereas the hazard ratios should.  These per-stratifier Cox regressions can be used in slides by the deck builder.

The JSON takes every computed value regardless of whether any report shows it, and the workbook is a reading of it, chosen for a person to scan.

#### Where the rows went

`data_preparation` records how the rows of your CSV became the rows the analysis ran on, which no other output states. `rows_read` is the file's row count and `rows_prepared` the number of stays left after cleaning; the `attrition` table between them has one row per step that ran, giving the count before it, after it, and the difference, in the order the steps were applied. (`attrition` is the row-removing part of the fuller `ledger` described below, projected out of it rather than recorded separately, so the two can never disagree.) A step that had no occasion to run, a filter you did not configure, or a bad-row discard that found nothing to drop, is absent. The checks that always run (blank records, duplicate stays, overlapping stays, the study window) are listed even when they removed nothing. The counts chain from `rows_read` to `rows_prepared` without gaps.

Beside the table are the figures that are not removals:

- How many outcomes were recoded as still in care.
- One record per value-map transformation configured in `mapped_intake_type` or `mapped_animal_group`, each record giving `from`, `to`, and `rows_mapped`. The table is present but empty when no map is configured.
- Whether your file supplied `animal_id` values or the tool generated them.
- The number of distinct animals.
- The count of stays still in care, censored early, or with a recorded outcome.
- The intake and outcome date ranges.

Finally, `rows_analyzed` is the number of animal-period rows, together with the count of rows the period split could not keep because capping or truncation removed them from the risk pool of that period. Note that `rows_analyzed` is not comparable with `rows_prepared`: a stay spanning two periods is one stay but two rows, which is why the two are reported separately. Everything above `rows_analyzed` counts stays.

**The screening ledger.** The same story is also told as one table, in a format shared with ShelterDataPrep ([10.5281/zenodo.22051338](https://doi.org/10.5281/zenodo.22051338)), the separate tool that prepares a raw shelter extract into the CSV that mLOS reads. It appears three ways: as the `ledger` and `ledger_detail` tables inside `data_preparation`, as the `Data_Preparation` worksheet, and as `data_preparation_stats.csv` in your results folder. All three are renderings of one table, so they cannot state different numbers.

The CSV is the one that matters for the shared format. It has the same columns, in the same order, as the `<name>_stats.csv` that ShelterDataPrep writes, so you can read both files with one reader and stack them into a single flow from the raw extract to the rows the models ran on: that tool's last stage hands off a row count and an animal count, and mLOS's first stage picks up exactly those. The format is documented in ShelterDataPrep in two places: the [README](https://github.com/Shelter-Data-Analysis/ShelterDataPrep#the-statistics-table) summarizes it in a paragraph, and [docs/statistics-table.md](https://github.com/Shelter-Data-Analysis/ShelterDataPrep/blob/main/docs/statistics-table.md) is the specification, under "The statistics table" and "The by-value breakdown". A `section` column selects between the two halves: a `stage` row is one screening step with the counts on either side of it, and a `detail` row is one value your settings name, counted within the rows that step touched. Each half leaves the other's columns empty, which is what keeps this one file rather than two.

Three things are specific to mLOS and worth knowing if you are reading the two files together.

- The `split` action is mLOS's own, and it is the one stage whose row count *rises*: it turns each stay into one row per period it is observed in. Rows are stays before it and animal-period rows after it, which is the same distinction `rows_prepared` and `rows_analyzed` draw above. A preparation ledger never needs this verb, because preparation only ever removes rows.
- The `pass` role, with a scope of `rows kept`, is how a keep-only filter reports itself. A `pass` filter names the values it keeps, so those are what its counts are over. A `cut` filter names what it removes, and its counts are over the rows it removed, exactly as upstream.
- The `animal_id` columns are empty throughout when your file supplied no `animal_id` column. The tool then generates one per row, so counting them would only restate the row counts under a name that promises animals.

A value shown with a count of `0` matched nothing in your file. That zero is the point of the by-value half: it is the only signal you get that a key is misspelled, differently cased, or was flattened by YAML, and a value your data simply no longer carries looks the same, so checking it is your job. The `Data_Preparation` worksheet shows the same two halves as two separate tables, dropping the columns that belong to the other one, since in a spreadsheet a blank column reads as a fault rather than as a section marker.

Three further counts say why `rows_analyzed` and `rows_prepared` differ. Two of them count animals and one counts stays, so they do not add up or nest into one another:

- `animals_with_multiple_rows` is how many animals appear on more than one row. Two quite different things put an animal there, and this count does not distinguish them, which is why the other two exist. Do not read it as a period-splitting measure.
- `stays_split_across_periods` counts stays cut by a period boundary. This one is keyed on the stay, not the animal: one animal whose two stays are both split contributes two here and one above.
- `animals_with_repeat_stays` counts animals that came back for a genuinely separate later visit, which can happen entirely inside one period and has nothing to do with how you set your period dates.

Which cause dominates depends on your period boundaries. Periods that are long relative to a typical stay leave most multiple-row animals to repeat visits; periods shorter than a typical stay cut nearly every long stay, and boundary splits become the larger share. Read the two counts against each other rather than assuming either.

These three are reported in `results.json` only. The `Data_Preparation` worksheet carries the ledger's two halves and not the counts around them.

#### How to read the JSON

**How the run drew things.** `settings.presentation` holds the settings that change no result: the plot day cap, the maximum number of strata plotted, the confidence-ribbon toggles, the PNG sizing factors, and the per-output emission flags. These are carried so a figure you build downstream can be made to match the tool's own, using the same x-axis truncation and the same stratum limit. The settings that do affect results sit outside this group, in `settings` itself.

**One name per measure.** Every quantity has a single name, in lower case with underscores, and it is the same name in the workbook, in `results.json`, and in the CSV files: `total_animal_days` is `total_animal_days` wherever you meet it. The canonical outcome codes keep their upper case inside those names (`outcome_mix_L`, `aj_rmtl_N`, `cif_Any`), because they are values rather than words. These names are chosen to be unambiguous and easy for a program to match, not to be pretty; turning `km_median_los` into "Median length of stay" belongs in a report or slide deck built on these outputs, where the wording is being chosen anyway.

The JSON describes its own shapes, so a reader needs no knowledge of the analysis code: a measure table is tagged `"type": "matrix"` and carries its `rows`, `columns`, and `values`; a data table is tagged `"type": "table"` and carries its columns by name; a set of labeled values, such as the outcome-type mapping, is tagged `"type": "named_vector"`. Missing values are `null`.

The JSON carries the plot palette, under `palette`, so a chart you build downstream can match the tool's own figures. Colors are given as `#RRGGBB` hex rather than by name, because color names are not portable. `stratum_colors` is the stratified-curve palette, applied to strata in the order each sheet or CSV lists them, never recycled. `outcome_colors` and `outcome_labels` are keyed by outcome code instead, so an outcome keeps its color and its wording even in a chart that shows only some of them, and `outcome_order` is the canonical L, T, N order used everywhere in the tool (best outcome first, worst outcome last, deliberately not alphabetical).

The JSON also carries an `outputs` manifest: one entry per plot and companion CSV the run actually wrote, giving the file name, what it contains, which stratifier and outcome it belongs to (a whole-data file names `all` as its stratifier, the same name the `strata` block and the `By_All` sheet use for the whole sample, so one lookup key serves both halves of the JSON), what the `days` column and the value columns mean, their units, and what the summary row above the day grid is, including how that row follows from the grid beneath it (a column sum for the survival, census, and tenure files; remaining LOS at mean tenure for the remaining LOS files; the normalized form of restricted mean time to outcome for AJ cumulative incidence). Which files a run produces depends on your settings and on what the data supports (see [Stratified-output selection](#stratified-output-selection)), so this is how a downstream script discovers what is there rather than guessing from file names. The per-day grids themselves stay in the CSVs, which are easier than JSON for reading and replotting.

#### Rebuilding the workbook from the JSON

`Rscript mlos_render.R [JSON_FILE] [EXCEL_FILE]` rebuilds the workbook from a saved `results.json` without repeating the analysis, which is useful for re-examining an earlier run. It is also how the test suite proves the JSON is complete: a workbook rebuilt from the file must match the one the run produced, cell for cell.

#### The Excel workbook

Many (but not all) statistical results and descriptive statistics are exported to a consolidated Excel workbook (`analysis_results.xlsx`). Four sheets are always present: `General` (the workbook's first sheet, a cover sheet), `Data_Preparation` (the screening ledger described above), `Cox_Regression`, and `By_All` (the whole-dataset version of the stratum-sheet layout: a single unified column carrying the full unified analysis, counts, KM, census aggregates, outcome mix, incidence, and AJ, so it lines up row-for-row with the stratified sheets). Further sheets are conditional:

- A `By_Period` sheet when two or more periods are defined. Period is treated as a stratifier like any other, so a single-period run has nothing to compare and the sheet is omitted. `By_All` carries the same numbers in that case, and the period's dates and duration are on the `General` worksheet.
- `By_Intake_Type` and/or `By_Animal_Group` sheets when the respective column is present with two or more levels.
- When `parametric_regression: WEIBULL` is set, a `Weibull_Regression` sheet as well as separate `Weibull_By_Period` / `Weibull_By_Intake_Type` / `Weibull_By_Animal_Group` sheets for qualifying predictors (see Per-predictor Weibull regressions, below).

Every sheet is laid out in vertical sections with a blank row as the separator.  A section has a heading followed by a row of column labels, then data rows, and sometimes a text footnote. A section heading has a short bold phrase in the first cell and sometimes a plain-text clarification in the cell to its right; it never carries data of its own. What follows a blank row is always a heading; nothing else sits in that position. Where a quantity comes with a confidence interval, the estimate and its lower and upper bounds are always three separate cells, never one cell of formatted text, so you can chart or sort them directly.

#### The General sheet

`General` is a cover sheet rather than a per-column table. It opens with the run metadata: the data, settings, output, and log file paths, and the generation time. Below that come these blocks, in order:

- **Period metadata** — the start date, exclusive end date, and duration of each period. This is the same table that leads `By_Period`.
- **Observation gaps** — placed high, right after the period metadata, so that it is not overlooked. It is shaded green when no risk-set gaps were found and red when any were. See the Observation gaps section.
- **Analysis settings** — the settings that shape the numbers or their interpretation: the restricted stay cap, the Cox reference levels for period, intake type, and animal group, the columns that compose the animal-group dimension, whether a Weibull fit was run alongside Cox, the two row-discard flags, the intake, animal-group, and other value filters, and the outcome labels deleted outright or reclassified as still-in-care.
- **Unified KM detail** — the overall study window, the restricted stay cap and the fraction of stays it bound, and the unified median, 90th percentile, still-in-care-at-cap, and restricted mean. These are the same four KM Length of Stay figures the `By_All` sheet carries per column.
- The stratification coverage, and the raw-label to L/T/N mapping actually applied.

Plot-only settings are deliberately left out of the analysis settings: the axis caps, the point and line sizing, the maximum plotted strata, the confidence-ribbon toggles, and the flags that only select which stratified plots and CSVs are written.

One pair on the Unified KM detail block is easy to misread. "Fraction capped" and "Still in care at cap (fitted)" are the observed and fitted readings of the same event, listed apart so that neither is mistaken for the other.

---

#### The stratum sheets

The `By_Intake_Type` and `By_Animal_Group` sheets replicate the `By_All` layout, one column per intake type or animal group, with every measure on exactly the same worksheet line as on `By_All` and `By_Period`, so columns can be cut and pasted across the sheets for comparisons across stratifiers. To keep the numbers compatible, the measure sections deliberately keep the `By_Period` counting conventions rather than re-unifying stays across period boundaries: the counted rows are animal-period segments, truncated and censored at period boundaries, so a stay spanning several periods contributes one row per period it touches to its column (exactly as it contributes one row to each of those periods' columns on `By_Period`). In particular, `total_observations` counts these rows rather than animals, `left_truncated` counts rows already in care when their period starts (that is, presences at period left boundaries), and `right_censored` includes censoring at period boundaries, not only at the end of the entire study window. Denominators for census and daily rates are the total days across all periods. A cell is NA or blank when the measure is not computable for that column.

The one exception is the top section of each stratum sheet, in the slot the period-metadata table occupies on `By_Period`: **counts unified across periods**, where each stay counts exactly once. `unified_total_stays` is the number of distinct stays, `unified_left_truncated` counts stays whose intake precedes the start of their first observed period (in care before observation begins), and `unified_right_censored` counts stays with no observed outcome.  This last category consists of animals still in care at the end of observation, capped at the restricted stay cap, or ending in an unclassified exit (a departure date with no classified outcome type, whether recoded by `outcome_type_in_care` or blank in the data; see the [data file section](#data-file-csv)). These are the three numbers whose row-level versions carry period-boundary effects, shown here with those effects removed. A short reminder of all these conventions sits beside the unified counts on the same rows, on a light pink panel — but only when more than one period actually contains data (a defined-but-empty period does not count). When there's only one period, there is no period boundary for a stay to cross, so the unified and row-level counts are identical column for column; the pink panel would be misleading and is replaced with a green note pointing out that identity instead.

Below the top section come the measure sections, identical in shape and order on `By_Period` and on every stratum sheet. From top to bottom:

##### Observations

This section starts with `duration_days`, the column's denominator in days behind its census and daily-rate figures. On `By_Period` it is each period's own length. On `By_All`, `By_Intake_Type`, and `By_Animal_Group` it is the whole study window, identical across columns.

Next come the counted animal-period rows and how they resolve: `total_observations` (rows, not distinct animals), `events` (rows ending in a classified outcome), the `left_truncated`, `right_censored`, and `capped_at_restricted_stay_cap` counts, `mean_days_at_risk`, `total_animal_days`, and the intake and outcome flow (`total_intakes`, `total_outcomes`, `mean_daily_intakes`, `mean_daily_outcomes`).

The mean census and the accumulated in-care days are not here. They are reported in the census-aggregates section below, beside their expected counterparts.

##### Outcome events

This section holds `completed_outcomes_total`, the count of classified outcomes overall, and the count of each classified outcome type (L, T, N), which add up to that total. These raw counts are what the outcome mix and the incidence rates further down are built from, and `completed_outcomes_total` is the outcome-mix denominator.

##### Outcome mix among completed outcomes

Among the stays that ended with a classified outcome, this section gives the share going to each outcome type (L, T, N). It is a composition, not a rate, so the shares sum to 1. It is undefined when the column recorded no completed outcomes.

##### Incidence rates per 100 animal-days

These report classified outcomes per 100 days of care delivered, overall and per outcome type. The figure reads like a daily percentage of the in-care population: a rate of 3.5 means that on an average day about 3.5% of the animals in care left with a classified outcome.

Unlike the outcome mix, which is a share of departures, this is measured against exposure. It reflects how fast outcomes occur, not just their proportions.

##### KM Length of Stay

Four numbers summarize the Kaplan-Meier fit for that stratum, or for the whole population on `By_All`: the median, the 90th percentile, still in care at cap, and the restricted mean.

The **median** and **90th percentile** are the days by which half, and 90%, of stays have ended. Either is labeled "not reached" if it would fall beyond the cap.

**`km_still_in_care_at_cap`** is the curve's terminal value, the fitted probability that a stay is still in care once it has reached the cap. It is the fitted counterpart of the observed `fraction_capped` in the observations section. See the [census and animal-day metrics section](#census-and-animal-day-metrics) for how to read the pair.

The **restricted mean LOS** is the mean stay capped at `restricted_stay_cap`. It is more stable than the ordinary mean when long stays or heavy censoring are present. It always reflects the full cap: when no stay reaches that far, the survival curve is held flat out to the cap, since "still in care" is a valid, stable state indefinitely.

##### Census aggregates (observed and expected)

This section sits right after the KM block. It sets the observed standing population beside the one implied at steady state by the fitted KM curve and the observed intake rate. The rows come in a fixed order:

- The observed mean census (`mean_census_inventory`), paired with the Little's-law prediction (`expected_census`, mean daily intakes times the KM restricted mean).
- The observed accumulated in-care days (`daily_mean_total_in_care_days`), paired with the animal-days the KM curve says the steady-state census has already accrued (`expected_past_animal_days`) and still owes (`expected_future_animal_days`).
- Three days-per-resident figures. `per_resident_in_care_days` is the observed accumulated tenure per resident, a direct data count. `per_resident_past_days` is the same quantity as implied at steady state by KM. `per_resident_future_days` is the expected remaining stay, again from KM.
- `per_resident_past_days_restricted_median` and `per_resident_past_days_restricted_p90`, the median and 90th percentile of the tenure distribution whose mean is `per_resident_past_days`.
- `remaining_days_at_mean_tenure`, `remaining_days_at_median_tenure`, and `remaining_days_at_p90_tenure`, the remaining-LOS curve read at each of those three tenures.

See the [census and animal-day metrics section](#census-and-animal-day-metrics) for how to read agreement and disagreement among the observed and expected versions of each metric.

##### AJ Final CIF

From the competing-risks (Aalen-Johansen) fit, this section reports the final cumulative incidence of each outcome type and of `Any`: the probability that an animal reaches that outcome within the AJ analysis window. `Any` is the probability of having left for any classified reason by the end of that window, so 1 minus `Any` is the probability of still being in care then.

This is related to the outcome mix section above, but it answers a different question. The outcome mix is a share among outcomes observed in the data, so it sums to 1. The final CIF is an absolute probability over all animals, computed by the Aalen-Johansen estimator, which takes truncation and censoring into account. Its shortfall below 1 is the still-in-care fraction at the end of the AJ analysis window.

##### AJ restricted mean

This is the mean number of days to each outcome, computed only among the animals that experience that outcome within the AJ analysis window. It is a normalized restricted mean of the cumulative-incidence curve.

Because it is normalized by the final CIF, it does not depend on where the window ends. Extending the curve flat past the last observed event only appends zero terms, so the value does not change.

The metric is analogous to a simple calculation shelters do by averaging the LOS of the animals in each outcome type. The AJ version, however, takes truncation and censoring into account, and so avoids the perverse effects the naive average suffers when long-stay residents accumulate in one period and leave in another.

These rows carry no confidence interval.

##### Restricted mean days by state (RMST and RMTL)

This is a companion decomposition. Of the first `restricted_stay_cap` days after intake, it reports how many an animal spends still in care (`aj_rmst_stay`) and how many it spends already departed via each outcome type (`aj_rmtl_L`, `aj_rmtl_T`, `aj_rmtl_N`, and `aj_rmtl_Any` for all outcomes together).

These use the **same flat-to-cap convention as the KM restricted mean**. Each curve is held flat from its last observed event out to the cap, then integrated over the full cap. Two things follow. `aj_rmst_stay` is identical to the KM restricted mean above, and the in-care and departed rows add up to the cap exactly. The departed rows therefore sum to the cap **minus** the restricted mean.

"RMTL" is the name used in the competing-risks statistical literature, restricted mean time lost. Here the "lost" days are days out of care, so for live outcomes it would read more naturally as time gained. Each value comes with a 95% confidence interval in the confidence-interval section.

Comparing `aj_rmtl_` rows across columns shows where those days go. A large `aj_rmtl_L` says animals of that column spend most of those first `restricted_stay_cap` days already placed in the community.

The flat extension to the cap in these restricted means differs from the daily CIF and conditional-outcome *curves*, which stop at the last observed event day and are not carried to the cap. That is a plotting and tabulation choice, described under Plots and Limitations, and it does not affect the restricted means here.

##### 95% confidence intervals

A closing section on `By_All`, `By_Period`, `By_Intake_Type`, and `By_Animal_Group` gathers the intervals, in the same order as the sections above it: the fraction of stays capped, the mean daily intake and outcome rates, the outcome-mix shares, the incidence rates, the KM median, 90th percentile, and restricted mean, the fitted still-in-care-at-cap probability (the curve's pointwise bounds at the cap), the final cumulative incidence of each outcome type (`Any` included), and the restricted mean days by state, both in care and departed via each outcome type.

Rows come in estimate/lower/upper triplets, with the estimate re-displayed above its bounds so each triplet reads on its own. The intervals sit in one bottom section rather than as extra columns beside the estimates, which keeps sheets with many levels readable. A bound is NA when the data cannot estimate it, for example a median whose upper confidence bound is never reached within the stay cap.

Each family of intervals is computed differently:

- **KM and AJ intervals** come directly from the fitted curves.
- **Rate intervals** (daily intakes and outcomes, incidence) are exact Poisson intervals. They assume events occur independently at a steady rate within the window. Group arrivals, such as a litter surrendered together or a bulk transfer, and strong seasonality, make them somewhat too narrow.
- **Proportion intervals** (fraction capped, outcome mix) are exact binomial intervals. They treat the counted rows as independent, including repeat stays of one animal. (The Cox regression, on the other hand, clusters its robust standard errors on `animal_id`, which keeps one animal's period-split rows in a single cluster.) Because these intervals are computed over rows, redrawing your period boundaries changes their width even when the point estimate is unmoved: a stay split in two contributes two rows.
- **The expected census** gets an **indicative interval only**. It is the product of the intake rate and the restricted mean, and its interval treats those two estimates as independent, which is only a rough approximation. The estimates are likely positively correlated, so the true interval is wider than the one shown. A proper joint treatment is an advanced topic left for future versions. Until then, read the reported interval as a lower bound on the real uncertainty.

The mathematical methods document states these assumptions in full, in section 8.4.

Some quantities carry no interval at all: the other census aggregates, the remaining-LOS curves, the tenure profiles, and the AJ restricted means (the mean-days-to-outcome rows). The restricted mean days by state, above, does get them.

##### Hazard ratios and LOS ratios

*Two blocks, closing the sheet after the confidence intervals.*

A compact companion to the regressions described below. Each block puts this column's own predictor's ratios side by side, each with its 95% confidence interval and no p-value, which keeps them small.

**Hazard ratios:**

- `cox_pooled_hazard_ratio`, from the Cox regression;
- `cox_stratified_hazard_ratio`, from the per-predictor Cox regression, which gives the other predictors' combinations their own baselines;
- `weibull_pooled_hazard_ratio`, from the general Weibull regression.

**LOS ratios:**

- `km_restricted_mean_ratio`, each level's restricted mean stay as a multiple of the reference level's, straight from the KM curves;
- `weibull_freed_shape_los_ratio`, from the per-predictor Weibull regression, which lets the other predictors' combinations each carry their own curve shape;
- `weibull_pooled_los_ratio`, the same predictor from the general Weibull regression.

Two blocks and not one because within each block the values are comparable with one another, and the fits that produce comparable values differ between the two. The per-predictor Weibull regression has a hazard ratio too, and it is left out of the first block because it belongs to one covariate combination rather than to the data. `pooled` means the fully adjusted fit, and is not the crude Weibull on the **Weibull_Regression** sheet, which drops the intake-type and animal-group terms altogether.

The KM ratio leads the second block as the least assuming of the three, and it differs from the two below it in two ways rather than one. It adjusts for nothing: each level's own curve against the reference level's, mix and all. And it is a ratio of *restricted* means, capped at the restricted stay cap, where a Weibull LOS ratio describes the whole fitted distribution. Where a real share of stays reaches the cap, the KM ratio is pulled toward 1 by the cap alone, so compare it with the two below it only when very few stays reach the cap. It is also the one row that adjusts for nothing yet still needs the Cox regression, which is where its reference level comes from; with no Cox fit the row is empty.

The Weibull rows sit at the bottom of both blocks and appear only when `parametric_regression: WEIBULL` is set. Without it each block still carries its other ratios, with a footnote saying the Weibull fit was off. A requested fit that declined or failed leaves its rows present and empty.

Every row is transposed into the same one-column-per-level layout as every section above.

Unlike everything else on the sheet, these two blocks do not sit on the same worksheet lines as `By_All`'s copies of them. `By_All` has no single stratifying predictor for them to report on, so both its slots read "not applicable". They are placed last specifically so that difference cannot shift anything else on the sheet out of alignment.

See the per-predictor Weibull sheets below for the fuller report that lives on its own worksheet: every level's p-value, and the shape-ratio table for the other predictors. The per-predictor Cox regression has no worksheet of its own; its hazard ratio here is all of it the workbook shows, and the rest of that fit is in `results.json`.

#### The Cox_Regression sheet

The Cox regression tests whether LOS distributions differ significantly across periods, intake types, and animal groups when these stratifiers act simultaneously. It quantifies the differences as hazard ratios.

The hazard-ratio table lists every level of every predictor. The reference level appears as a definitional row: hazard ratio exactly 1, with a blank confidence interval and p-value, because the reference is the denominator of the ratios rather than an estimate of its own.

Levels appear in a fixed canonical order, chronological for periods and alphabetical for intake types and animal groups. The table's rows therefore line up with the `By_Period`, `By_Intake_Type`, and `By_Animal_Group` columns, and they stay in the same positions across repeated runs on the same shelter. The Weibull sheets follow the same convention.

#### The Weibull_Regression sheet

*Optional, written only when `parametric_regression: WEIBULL` is set.*

This is a parametric companion to Cox on the same predictors. Its main output is **LOS ratios**. "LOS ratio 1.30" means stays run about 30% longer than the reference group, which is usually the number a practitioner actually wants, with no conversion from hazard ratios needed.

The sheet also reports:

- Hazard ratios implied by the fit, for direct comparison with the Cox sheet, to check if the two models tell the same story.
- A shape parameter `k` with a plain-language legend: `k < 1` means discharge slows down the longer an animal has stayed, so there are more long residents. `k > 1` means discharge speeds up the longer an animal has stayed, so there are fewer long residents.
- A crude fit that drops the intake-type and animal-group terms and keeps only period, so the LOS ratio may still vary by period while a single shape covers the whole dataset. Comparing that shape against the main fit's is the heterogeneity diagnostic: a mixture of fast-leaving and slow-leaving groups produces a declining hazard on its own, so a pooled shape below 1 may reflect composition rather than any change in an individual animal's prospects. Period is kept because it cannot produce that effect. A stay crossing a boundary is split into one row per period, so period describes when care was delivered rather than a group an animal belongs to, and there is no persistent membership for the population to sort on. When only one period holds data, this fit has no predictors at all.

What the Weibull adds over Cox is the LOS ratio without conversion, the shape `k` as a number in its own right, and estimates that extend past the last stay in the data. What it costs is the assumption that stay lengths follow a Weibull distribution, which the implied hazard ratios are the check on. It is not the model to reach for on thin data: Cox handles a sparse dataset more comfortably, not less, because its baseline is estimated out of the way rather than fitted alongside the coefficients.

A "Fit stability" row near the top says whether the fit reached a maximum the confidence intervals can be computed from exactly, or whether they are approximations. The estimates are reported either way.

#### The per-predictor Weibull sheets

*Optional, written only when `parametric_regression: WEIBULL` is set. There is one `Weibull_By_Period`, `Weibull_By_Intake_Type`, or `Weibull_By_Animal_Group` sheet per qualifying predictor.*

A sheet whose stratifier does not qualify at all shows a note instead of the tables, and the compact companion table on the corresponding `By_...` sheet shows the same note.

Stratifying by period alone conflates two things: whatever period itself does to how long animals stay, and any shift in the *mix* of intake types and animal groups from one period to the next, such as more owner surrenders or a rising share of one animal group among intakes.

The general Cox and Weibull regressions above already correct for that, placing intake type and animal group as covariates alongside period. But both still assume that every intake type and every animal group shares the *exact same shape* of discharge process over time. Cox's flexible, data-driven baseline is nonetheless one baseline applied to everyone, and the general Weibull's shape `k` is likewise a single number for the whole dataset. Neither model can tell you whether, say, stray large dogs leave care at a fundamentally different *pace over time* than owner-surrendered large dogs or stray small dogs, only whether they leave at a different *average rate*.

This is what the per-predictor sheets add. `Weibull_By_Period` fits period's LOS ratio like the general Weibull does, with the same adjustment, the same reference period, and directly comparable numbers. What it adds is that intake types may have their **own shape of discharge over time**, and animal groups theirs, instead of all being forced to share one. `Weibull_By_Intake_Type` and `Weibull_By_Animal_Group` do the same for their respective predictor's LOS ratio while letting the *other* predictors vary in shape.

Beside the LOS ratios, which mean exactly what they do on the `Weibull_Regression` sheet, each sheet reports a **shape ratio** for every other predictor's levels. A shape ratio near 1 means that predictor's levels genuinely share one discharge shape, so the general Weibull's assumption holds up for it. A shape ratio far from 1 means they do not: one group's chances of leaving change with tenure in a way another group's do not, a distinction the pooled models are structurally unable to see or report.

A sheet's LOS ratio tells you how much longer or shorter stays run for the corresponding predictor's levels, once the other predictors' shapes are allowed to differ. That is the same practical reading as the general Weibull's, but with a narrower assumption.

**Model tests.** This block carries a likelihood ratio against a Weibull with no predictors at all, which on any reasonably-sized dataset is statistically significant but not very useful.

A "Shape crossing" row in the overview says which shape formula produced the numbers and why it was that one, and the model formula at the top names the fit itself. On a default run it reports the by-dimension shape described here.

**Baseline shape.** Above the shape ratios sits a baseline shape with its confidence interval, and it is easily misread. It is the shape of one particular combination, the one where every other predictor sits at its reference level. It is not an average across your animals.

A group's own shape is that baseline multiplied by the group's shape ratio. The sheet prints it for you in the `own_shape_k` column beside the ratio, with its own confidence interval. That interval is computed separately: it is not the ratio's interval rescaled, because a group's own shape combines two estimated numbers and carries the uncertainty of both. The reference level's own shape is the baseline itself, so its row is filled in too.

That multiplication gives the group's shape in the combinations where the *other* shape predictor also sits at its reference level, so the `own_shape_k` column describes one cell rather than the group across the board. Elsewhere the group's ratio still applies, multiplied by the other predictor's ratio: on **OC2**, LARGE's own shape reads 0.67 in the reference intake type and works out to 0.52 in RET and 0.69 in OWNER.

A baseline close to 1 sitting above a column of ratios below 1 still means most of your population has a discharge rate that falls the longer an animal stays.

A mixture of fast-leaving and slow-leaving groups genuinely can itself produce a shape below 1, through a sorting effect: the initial mixture gradually sheds the fast-leaving group and drifts toward the slow-leaving one. The resemblance to a Weibull is only approximate. A mixture's hazard falls toward the slowest group's rate and then flattens, whereas a Weibull with `k < 1` has a hazard that keeps falling, so the two agree over the range you observe and part company beyond it. That is one more reason to quote the restricted mean rather than an extrapolated one. But showing that a mixture *could* explain it does not show that it *did*.  Within an initially homogeneous cohort, the stay itself, along with related shelter policies, may impact each animal's prospects as a function of its stay.     These two effects can co-exist. Convert to per-group shapes before deciding if one is the better explanation.

#### Shapes per combination on those sheets

*Advanced, and a work in progress. Skip this if `weibull_shape_crossing` is false (its default).*

By default each shape *dimension* carries its own effect, so an intake type shifts the shape by the same factor in every animal group. Setting `weibull_shape_crossing: true` instead gives every intake-type and animal-group **combination** its own shape. Leave it off unless the shape structure itself is what you are studying: a run in which any sheet crosses its shapes gets no shape recommendation in the findings deck at all.

It needs all three stratifiers to have two or more levels, since with two stratifiers there is only one other predictor and nothing to cross. It also spends a parameter on every combination, so a combination holding fewer than 5 outcomes (animals that actually left, not animals still in care at the end of the window) blocks it, and a combination your data never produced counts as zero and blocks it the same way. One short combination is enough, so a single rare pairing costs the whole sheet its per-combination shapes and it falls back to the by-dimension version, with the reason on the "Shape crossing" row. If that happens and you want the crossing, the fix is to merge or filter that pairing away, either as a combination or by acting on the individual levels it consists of. Avoiding sparse levels or combinations is a good idea generally.

A crossed sheet's **Model tests** block carries a second likelihood ratio, against the same fit without the interaction terms, and that test is the interesting one: it asks whether the interaction terms earned their extra parameters.

A crossed sheet also carries a further term for each combination itself, listed below the shape ratios under "Shape interaction terms". A combination's own shape is then the baseline times *both* main-effect ratios times its interaction term. An interaction term is that correction, not a shape on its own, although the number looks like one. The block is there for readers who want the whole fitted model, and a sheet whose shapes were not crossed leaves it out, having estimated no such terms.

## Running the Tool

The main entry point is `mlos_run_complete.R`. Run it from the command line:

```
Rscript mlos_run_complete.R [--settings FILE] [--data FILE] [--results DIR]
```

Defaults (if arguments are omitted):

- Settings: `data/OC2_settings.yaml`
- Data: `data/OC2_data.csv`
- Results directory: `results/`

These defaults can also be overridden with environment variables `MLOS_SETTINGS_FILE`, `MLOS_DATA_FILE`, and `MLOS_OUTPUT_DIR`. The names of the three output files created inside the results directory can be overridden too: `MLOS_LOG_FILE` (default `analysis_log.txt`), `MLOS_EXCEL_FILE` (default `analysis_results.xlsx`), and `MLOS_JSON_FILE` (default `results.json`).

An unrecognized command-line argument (or an option missing its value) stops the run with a usage message rather than silently falling back to the defaults.

A full console log is written to `results/analysis_log.txt`.

**No local R installation?** The repository includes `colab_mlos.ipynb`, a Google Colab notebook that runs the same analysis in the browser: it installs the required packages and sets up the folders for you; you upload the `mlos_*.R` source files along with your data and settings files (the notebook's instructions show the exact layout).

---

## Data File (CSV)

**Columns may appear in any order. Extra columns are ignored by default**, but any extra column may be named in the settings file to construct an animal grouping on the fly (`animal_group_columns`) or to apply a one-off filter (`other_filter_column_name`); see the [settings reference](#settings-file-yaml).

### Mandatory columns

| Column | Description |
|---|---|
| `intake_date` | Date the animal entered care. Format: `YYYY-MM-DD`. |
| `outcome_date` | Date the animal left care. Blank or empty for animals currently in care. Format: `YYYY-MM-DD`. A date paired with a blank `outcome_type` is an "unclassified exit"; see the warning below. Blank alongside a non-blank `outcome_type`, it is a data error; see [`discard_bad_rows`](#discard_bad_rows). |
| `outcome_type` | Outcome code. See below for canonical values and how to map other values to the canonical ones. Blank for animals currently in care.  But a blank `outcome_type` with a recorded `outcome_date` is an unclassified exit; see warning below. An outcome code that a shelter uses to mean the animal is still resident belongs in [`outcome_type_in_care`](#outcome_type_in_care); otherwise it stops the run when its `outcome_date` is blank. |

**Warning: an `outcome_date` with a blank `outcome_type` is accepted silently, as an "unclassified exit."** Such a row passes validation without any error or warning, even under the strict default `discard_bad_rows: false`. The animal is treated as leaving observation on its departure date: it contributes at-risk time through that date and is censored there, counting as an outcome nowhere. It is not an event in the KM curves or the Cox regression, does not count as an outcome in any AJ cumulative incidence, and is excluded from the `total_outcomes` flow counts. This is exactly the treatment the `outcome_type_in_care` setting produces on purpose (see below), and rows recoded by that setting are the intended source of the pattern. If date-with-blank-type rows exist in your raw data, make sure that is what you mean: if the animal truly left care and only its outcome code went unrecorded, the analysis treats the animal as having an unknown departure date later than its actual one, and this inflates LOS estimates. The count of such rows (recoded and raw together) is printed in the console Data Summary as "Animals censored (unclassified exit)"; check that it matches what you expect, and consider `outcome_type_delete` for rows that are simply bad records.

### Optional columns

| Column | Description |
|---|---|
| `intake_type` | How the animal came into care (e.g., `STRAY`, `OWNER`). Enables stratified KM curves and Cox regression by intake type. Use a small fixed set of string values. Blank values are filled with `_UNKNOWN_` and analyzed as their own category (see below). |
| `animal_group` | A user-defined category (species, size, age group, facility, or any combination). Enables stratified analysis by group. Use a small fixed set of string values. Blank values are filled with `_UNKNOWN_` (see below). Can also be constructed automatically from other columns via `animal_group_columns` in the settings file; see below. |
| `animal_id` | Animal identifier. Rows belonging to the same animal, such as repeat intakes, share one value. When the column is missing, or an id is blank, an id is generated automatically, one per row. Real animal ids change the behavior in three ways; see below. |

**Blanks in `intake_type` and `animal_group` become `_UNKNOWN_`.** Blank entries in these two columns are neither dropped nor left missing: they are filled with the placeholder value `_UNKNOWN_`, so those animals appear as their own category in the stratified KM curves and the Cox regression rather than being silently excluded from them. If your data already uses the literal value `_UNKNOWN_`, the placeholder grows an extra underscore on each side (`__UNKNOWN__`, and so on) until it collides with nothing. Every fill is reported on the console. Note that a column holding one real value plus some blanks therefore has **two** categories, enough to switch on the stratified analysis for that column.

**Recommendation: use UPPERCASE (or Capitalized) values in `intake_type` and `animal_group`.** These values appear verbatim in plot legends, Excel sheets, and regression coefficient names, where they are glued directly to the column name: `intake_typeOWNER` reads much more clearly than `intake_typeowner`. Values are case-sensitive throughout, including in `intake_type_reference` and `animal_group_reference`, so pick one convention and use it consistently in the data and the settings file.

**What real `animal_id` values enable.** Three parts of the analysis behave differently when the column holds genuine identifiers rather than generated ones.

- **Clustered standard errors in Cox regression.** The fit always clusters on `animal_id` (see [The Cox_Regression sheet](#the-cox_regression-sheet)). Generated ids are assigned one per stay, before the period split, so the segments of a single stay share a cluster whether or not you supply the column. What real ids add is the link between an animal's *separate* stays: with generated ids a repeat visitor counts as two unrelated animals, and the interval widths do not account for the correlation between its visits.
- **Duplicate-stay removal.** Rows sharing `animal_id`, `intake_date`, and `outcome_date` are reduced to the last one, and the count is printed. If `outcome_date` > `intake_date`, one row in the pair cannot be real. If `outcome_date` = `intake_date`, it is theoretically possible that these are two real round trips within one day, but they are far more likely a correction, re-classification, or accidental copy.
- **The overlapping-stay check.** Two stays of one animal that overlap in time are physically impossible, so the run either stops or drops the shorter stay. See [`discard_overlapping_rows`](#discard_overlapping_rows).

### Outcome type codes

The tool uses three canonical codes internally. The shelter data CSV can either use these codes directly, or use site-specific labels that are mapped in the settings file (see `outcome_type_L/T/N` below).

| Code | Meaning |
|---|---|
| `L` | Community live outcome: return-to-owner, adoption. |
| `T` | Other live outcome: transfer, foster, return-to-field. |
| `N` | Non-live outcome: euthanasia (any type), died in care, lost in care. |

Animals still in care have a blank `outcome_type` and a blank `outcome_date`. But a blank `outcome_type` with a recorded `outcome_date` is instead an unclassified exit (see the warning in the [mandatory-columns section](#mandatory-columns) above). Other `outcome_type` values in the data can also be converted to the in care status (see the `outcome_type_in_care` setting below).

### Fine print on dates and LOS

- Dates must be in `YYYY-MM-DD` format (hyphen-separated).
- The tool validates date fields and outcome type codes (see `discard_bad_rows` for how errors are handled) and checks for physically impossible overlapping stays of the same animal (see `discard_overlapping_rows`).
- LOS is calculated inclusively: an animal that arrives and leaves on the same calendar day has LOS = 1. There is no LOS = 0.
- Animals still in care are treated as right-censored at the end of each period they participate in.
- Every count is read at the end of the day, and the "census" without qualification is the inventory census, which counts an animal on both its intake and its outcome day (the overnight census counts nights, so it excludes the intake day). More details are in [Which day counts? Who is in the census?](#which-day-counts-who-is-in-the-census) below, and in the math methods document (§2.7).

### Records that must be in the file

The analysis is valid only if the data include **all animal stays that overlap with the study periods**, not just animals with outcomes during those periods. Animals already in care at the start of a period are left-truncated (their time at risk begins at the period start, not their intake date). Including their full stay would bias LOS estimates upward, while omitting them altogether would bias them downward.

### Study window trimming

The study window spans from the first `period_dates` entry to the last. After the row-level cleaning steps, the tool automatically discards records that lie entirely outside it: rows whose `outcome_date` falls before the window opens (the animal left before the study began), and rows whose `intake_date` falls on or after the date the window closes (the animal entered after it ended). A blank `outcome_date` (animal still in care) never triggers the first rule. The number of records discarded is printed in the "Data Filtering Results" console section. Stays that merely straddle a window edge are kept in full; the parts outside the window are handled by left truncation and right censoring during the period breakdown.

Trimming is the last data-preparation step: it happens after the duplicate and overlapping-stay cleaning (see `discard_overlapping_rows`). Records outside the study window therefore still participate in that cleaning and can decide its outcome; for example, a stay lying outside the window can be the longer member of an overlapping pair and eliminate a shorter stay inside it. This is deliberate: whether two records physically conflict is a property of the data, not of the analysis window, so the cleaning gives the same result whatever `period_dates` says, and a conflict is never hidden just because one of its records falls outside the window.

Except for the overlapping-stay cleaning, including out-of-window records in the data file is harmless, and supplying a wider export than the study window is the safer practice: it guarantees the inclusion requirement above is met even if the window is later widened.

**Row order is preserved.** None of the cleaning or filtering steps reorder the data: rows are only ever removed, so the records that survive keep the order they had in the CSV file, up to the point where the data is sliced into periods. (The `discard_overlapping_rows` tie-break, "earlier in the file", relies on this.)

---

### The screening stages, in order

Data preparation runs these stages in this order. Each stage driven by a setting is documented with that setting in the [settings reference](#settings-file-yaml); the two that need no setting, the mandatory-column check and the study-window trimming, are described above.

| # | Stage | What it does |
|---|---|---|
| 1 | `outcome_type_delete` | Drop rows whose raw `outcome_type` is in the delete list |
| 2 | Mandatory-column check | Stop if `intake_date` / `outcome_date` / `outcome_type` are missing |
| 3 | Build `animal_group` | Concatenate `animal_group_columns` (if set) |
| 4 | Row validation | Bad/short dates, `outcome_type_in_care` recode, factor variable conversion (`discard_bad_rows`) |
| 5 | Value maps | Rewrite `intake_type` / `animal_group` values (`intake_type_map`, `animal_group_map`) |
| 6 | **Duplicate-stay removal** | Collapse rows sharing `animal_id` + `intake_date` + `outcome_date` |
| 7 | **Overlapping-stay screen** | Detect/stop-or-drop physically impossible overlapping stays (`discard_overlapping_rows`) |
| 8 | **Value filters** | `intake_type`, then `animal_group`, then the `other` column |
| 9 | Study-window trimming | Drop stays entirely outside every period |

The order is not arbitrary. The two integrity checks at stages 6 and 7 judge the **complete** file, so they run before any filter can remove one row of a conflicting pair, and the trimming that closes the sequence runs last so that a stay is discarded only once every other step has had its say. This guarantees that altering the study window does not make animals enter or leave the study set for any reason other than their stay's overlap with the study window.

## Settings File (YAML)

The settings file uses YAML syntax. All string values are case-sensitive. **Use blank spaces for indentation, but no tabs.**  Values that could be misread by YAML (e.g., `Yes`, `No`, `True`) must be quoted.  **It's safer to quote all string values.**

An unrecognized setting name stops the run: a misspelled key (e.g., `plot_stay_capp`, or `outcome_type_l` in the wrong case) would otherwise be silently ignored, making the tool behave as if the setting were never given. Comments (lines starting with `#`) are always fine.

### Study design

#### `period_dates` *(required)*

```yaml
period_dates:
  - 2024-01-01
  - 2024-04-01
  - 2024-07-01
  - 2024-10-01
```

Defines the boundaries of the time periods to compare. N dates define N−1 periods. Minimum of 2 dates (one period). Dates must be strictly increasing; an out-of-order or duplicate date stops the run. There is no hard limit on the number of periods; all periods are used in every analysis (KM, Cox regression, AJ). However, period is a stratifier, and stratified plots are skipped when the number of strata exceeds a limit; see the section [Plot strata limit](#plot-strata-limit) above.

Each period is **left-closed, right-open**: the first date of a period is included in it; the last date is the first date of the next period. For example, `2024-01-01` to `2024-04-01` includes January 1 but not April 1.

**Recommendation:** align period boundaries to a fixed day of the week (e.g., Monday) to avoid noise from day-of-week variation in intakes and outcomes. Aim for at least 100 outcomes per period; start with longer periods and shorten only if data are sufficient.

#### `restricted_stay_cap` *(required)*

```yaml
restricted_stay_cap: 365
```

Positive integer. Stays exceeding this number of days are capped: their time in the analysis ends at the cap and they are treated as right-censored there. The cap is the analysis horizon for **every** method, not just the restricted mean: the KM curve ends at the cap (so the median or 90th percentile is reported as "not reached" if it would fall beyond it), outcomes occurring past the cap are censored in the Cox regression. The AJ analysis uses no information beyond the cap. Below the cap, the curves are unaffected. The fraction of stays capped is reported as "Fraction capped at limit". To shorten the plots without shortening the analysis, set [`plot_stay_cap`](#plot_stay_cap) instead; it truncates the x-axis and changes no computed value.

**This is one of the most consequential settings in the tool, not just a technical default.** It effectively defines (crucially, for the KM restricted mean) the boundary between a "long but real" stay and one that should be treated as an outlier or a potential data discrepancy. Choose it deliberately by inspecting your actual stay-length distribution rather than reusing a default from another dataset. Be more conservative the sparser your data: with few observations, a single implausible or erroneous stay recorded near or beyond the cap can dominate the restricted mean.

When the tool detects a gap in observations (no animals at risk for a contiguous range of days before the cap is reached), it prints a warning giving the gap's day range. Because the KM curve is not identified across that stretch, consider expanding or combining periods. Gaps do not change `restricted_stay_cap` or affect the restricted mean calculation.

#### `period_labels`

```yaml
period_labels:
  - "Pre-COVID"
  - "COVID"
  - "Post-COVID"
```

Custom names for the periods, used everywhere the periods appear: console output, plot legends, CSV columns, and the Excel workbook. If omitted, periods are named `Period_1`, `Period_2`, ... in chronological order.

The list must contain exactly one label per period (that is, one fewer than the number of `period_dates` entries), in the same chronological order as the periods they name. Labels must be unique, non-blank, and must not contain commas or equals signs (those characters would break the column headers of the stratified CSV outputs). Quote all values so YAML doesn't misread labels like `Yes` or `2020`.

Labels only rename the periods; they do not affect any calculation, the ordering of periods, or the `period_reference` setting (which still selects the oldest or newest period by date).

### Outcome classification

#### `outcome_type_L`, `outcome_type_T`, `outcome_type_N` *(all-or-none)*

```yaml
outcome_type_L:
  - "Adopted"
  - "RTO"
outcome_type_T:
  - "Transferred"
  - "Foster"
outcome_type_N:
  - "Euthanized"
  - "Died"
  - "Lost"
```

Maps site-specific raw labels from the CSV `outcome_type` column to the canonical L/T/N codes. If the data file already uses `L`, `T`, and `N` directly, omit all three keys. Otherwise, provide all three; each must list at least one value. No raw label may appear under more than one code. If none of the three keys are present, the CSV is assumed to already contain `L`, `T`, or `N` directly. The two modes are exclusive: when the mappings are given, only the listed labels are recognized, so a literal `L`, `T`, or `N` in the data is then an error unless it appears in one of the lists.

Quote all values because YAML may otherwise interpret certain strings as booleans.

#### `outcome_type_delete`

```yaml
outcome_type_delete:
  - "Duplicate"
  - "DataError"
```

Raw CSV labels in the `outcome_type` field whose rows should be **dropped entirely** before analysis. Applied before any outcome type mapping. Useful because some shelters use the `outcome_type` field to mark duplicate or cancelled rows.

#### `outcome_type_in_care`

```yaml
outcome_type_in_care:
  - "InCare"
  - "OnHold"
```

Raw CSV labels that indicate an animal is **still in care** despite having a non-blank outcome code. Rows matching these labels are recoded to blank outcome type, while `outcome_date` is retained (used as the right-censoring date). Applied before outcome type mapping. A common use is for shelter management systems that export a placeholder outcome code for animals not yet discharged.

A code listed here is also exempt from the check that stops the run on an outcome code with a blank `outcome_date` (see [`discard_bad_rows`](#discard_bad_rows)): the recode runs first, and a placeholder code with no departure date is precisely what the setting exists to absorb.

Another use is the treatment of reversible outcomes (such as "FOSTER") as inconclusive. For such outcome type entries, the animal is no longer residing in the shelter, but its eventual outcome (type or date) is undetermined. In fact, many shelters code FOSTER not as an outcome but as a change of location (like a move from one kennel to another).

### Defining the comparison groups

#### `animal_group_columns`

```yaml
animal_group_columns:
  - gender
  - size
```

A list of CSV column names to combine into a single `animal_group` value for each row. The columns are concatenated in order, separated by `_`. For example, if `gender` is `F` and `size` is `LARGE`, the resulting group is `F_LARGE`. A single column also works, but specify it in the list form as in the example above.

The group need not describe the animal itself. The same mechanism can be used for other information, provided that it remains the same during the animal's stay.  For a multi-facility organization, for instance, list a facility column alone to compare locations, or combine it with an animal feature:

```yaml
animal_group_columns:
  - facility
  - size
```

yielding groups like `FacilityA_LARGE` and `FacilityB_SMALL`.

Combining columns multiplies the number of distinct groups, so don't overuse this feature. For smaller datasets, ideally no more than about 6 groups for interpretable Cox regression results. Larger datasets can support more.

If this setting is omitted, the tool looks for a CSV column literally named `animal_group`. If neither `animal_group_columns` is set nor an `animal_group` column is present, stratified analysis by animal group is skipped.

When `animal_group_columns` is set, any CSV column named `animal_group` is ignored (unless included itself in the list) and the synthesized value takes its place. The source columns listed in `animal_group_columns` are used only to construct `animal_group` and are otherwise ignored, like any other extra column. All columns listed must exist in the CSV; the run stops with an error if any are missing.

If a source column is blank for some row, that part is filled with `_UNKNOWN_` **before** concatenation: a female of unknown size (`gender` = `F`, blank `size`) yields `F__UNKNOWN_`, so a composite group is explicit when it contains a missing piece. The same collision rule applies as for direct columns (see the [optional-columns section](#optional-columns) above).

#### Value maps

**`animal_group_map` and `intake_type_map`** are two optional settings that rewrite the values of a stratification column before anything else looks at it. Each is a list of pairs, one per list item, giving a value as it appears in the data and the value it becomes:

```yaml
animal_group_map:
  - "XL": "LRG"
  - "TOY": "SMALL"

intake_type_map:
  - "OWNER SUR": "SURRENDER"
  - "SEIZED": "OTHER"
```

`animal_group_map` rewrites `animal_group`, `intake_type_map` rewrites `intake_type`. Everything downstream sees only the rewritten values.  This includes the levels of the column, the stratified plots and worksheets, the Cox and Weibull tables, the value filters, and the period split. A value mapped away leaves **no empty level behind**, which is the difference between this and a filter: mapping `XL` to `LRG` produces exactly the analysis you would have got had the file said `LRG` all along.

**What it is for.** Merging categories that are too thin to stand alone (a handful of `XL` animals folded into `LRG`), and normalizing labels that a data export spells more than one way. It is also the way to handle labels that appear only sometimes: mapping is by value, and a **key that matches nothing in the data is not an error**, so a map written for a rare intake type can sit in the settings file across runs whether or not that extract happens to contain one.

**Rules.** Keys must be unique. The same value cannot be mapped twice, and the run stops if it is. Both sides are case-sensitive and must match the data exactly. Quote both sides. An unquoted `Y`, `N`, `Yes`, `No`, `True`, or `False` is turned into a boolean by YAML before the tool sees it. On the **key** side that happens too early to be caught, leaving a key that quietly matches nothing.

**Nothing is checked against the data, so check the report.** Because an absent key is legitimate, the tool cannot tell a deliberate one from a typo. What it does instead is count: each map prints one console line listing **every pair with the number of values it transformed**, including the pairs that transformed none.

```
animal_group_map: transformed 143 value(s) [XL -> LRG: 143, TOY -> SMALL: 0]
```

A pair you expected to fire showing `0` is the signal that its key is misspelled, differently cased, or was flattened by YAML (and should have been quoted). The same counts are in `results.json` under `data_preparation` (`mapped_intake_type`, `mapped_animal_group`), one record per pair. The by-value half of the screening ledger described under "Numerical output" counts every other setting that names values the same way: the two outcome-type settings, the outcome type mapping, and all three value filters. Verifying them is your job; the tool will not stop for it.

**The pairs do not chain.** All replacements are made at once against the original values, so with `XL` → `LRG` and `LRG` → `MED` in one map, an `XL` becomes `LRG` and stays there. The result never depends on the order the pairs are listed in.

**Where the maps run.** (See also [The screening stages, in order](#the-screening-stages-in-order) above.) After `animal_group` is built (so for a composite group the keys are whole composite values such as `F_LARGE`, not the pieces) and after blanks are filled, but before the column becomes a set of levels. Two things follow. A blank `intake_type` or `animal_group` is by then its `_UNKNOWN_` placeholder. This means `"_UNKNOWN_"` is a usable key, and can be converted to a real category by mapping. And because the maps run **before** the value filters, a filter list must name the values as they are **after** mapping. A map configured for a column the data does not have (`animal_group_map` with no `animal_group`) stops the run, as the corresponding filter would.

#### Value filters

Three optional filters restrict the analysis to a subset of rows by matching a column against a list of values. Each filter is a **whole-row** selection; every step that produces a statistic, plot, or CSV sees only the retained rows, and the filters keep no statistics of their own — a filtered-out row is simply absent, as if it were never in the file. Each filter reports, in the console, how many rows it kept and dropped.

Each of the three targets takes **at most one** of a `*_pass` list (keep only rows whose value is in the list) or a `*_cut` list (drop rows whose value is in the list). Supplying both for one target stops the run. Values are matched against the CSV labels, case-sensitive, so quote them and write them exactly as they appear in the data (the same convention as the `outcome_type_*` settings). One nuance: a blank `intake_type` or `animal_group` has by this point been relabeled to its `_UNKNOWN_` placeholder (see the [optional-columns section](#optional-columns)), so to keep or cut those rows list `"_UNKNOWN_"`, not the empty string; and if a value map is in force, the values to list are the ones it produces, not the ones it replaced. The `other` column is matched on its raw value. A present-but-empty list, or a filter that removes every row, stops the run with an explanatory message.

**`intake_filter_pass` / `intake_filter_cut`** — filter on the `intake_type` column.

```yaml
intake_filter_pass:
  - "STRAY"
  - "OWNER SUR"
```

The data must have an `intake_type` column; if it does not, these settings cannot be present (the run stops).

**`animal_group_filter_pass` / `animal_group_filter_cut`** — filter on `animal_group`.

```yaml
animal_group_filter_cut:
  - "SML"
```

Applied **after** `animal_group` is constructed (from `animal_group_columns`, or from an `animal_group` column already in the data), so the values you list are the composite group labels. If no `animal_group` exists, these settings cannot be present.

**`other_filter_column_name` + `other_filter_pass` / `other_filter_cut`** — filter on one further column, named explicitly.

```yaml
other_filter_column_name: coat_color
other_filter_pass:
  - "black"
  - "brown"
```

`other_filter_column_name` names a single column (not a list) that must exist in the data file; it pairs with one of `other_filter_pass` / `other_filter_cut`, and the name and the list are all-or-none together. The column need not be a stratifier and is not otherwise used or reported — it is read only to apply this filter, then dropped like any other extra column. This is the way to subset on something the analysis does not otherwise know about. It is a good way to analyze only dogs, or only cats, when your data file contains both.

**Do not filter on outcome information.** An outcome is forward information, settled only when the animal leaves, so a stay still in care has none and a filter on an outcome column selects stays by their future. A `pass` list keeps only stays that have already ended, and only those that ended a chosen way, which reinstates the flaw in traditional LOS calculations that this tool was created to remedy (see [Why it's harder than just tabulating and averaging](#why-its-harder-than-just-tabulating-and-averaging)). A `cut` list removes those animals outright, which is again a selection made on forward information. If the intent is censoring, use [`outcome_type_in_care`](#outcome_type_in_care). To ask about particular outcomes, use the competing-risks output, which separates the outcome types while keeping every animal in the analysis (see [Aalen-Johansen (AJ) plots](#aalen-johansen-aj-plots)). The case where outcome information is a legitimate filter is when it conveys data curation: when a shelter uses the outcome field to flag a duplicate or a data error, [`outcome_type_delete`](#outcome_type_delete) drops those rows, and such a code was never a real (non-duplicate) outcome to begin with.

**Where the filters run.** All three are applied **late** in data preparation — deliberately *after* the duplicate-stay removal and the overlapping-stay screen, and just before the study-window trimming (with which they do not interact). This ordering matters: those two integrity checks judge the **complete** file, so a filter can never hide a duplicate or an overlap by removing one row of the conflicting pair before it is checked. The full sequence is in [The screening stages, in order](#the-screening-stages-in-order).

Because a `pass`/`cut` selection is a plain subset, the order among the three filters never changes the surviving set.

**What happens to a filtered-out level.** Emptying an `intake_type` or `animal_group` value does not remove it from the analysis's list of levels — exactly as when a level's rows all fall outside the study window or past the stay cap. The stratified outputs (KM, AJ, the by-stratum worksheets) skip any level with no rows, so an emptied level simply does not appear there. The **Cox table keeps it as a phantom row** with a blank hazard ratio, so a filtered run and the unfiltered run produce the **same Cox layout** and line up row-for-row when you compare them. (A predictor filtered all the way down to a single remaining level is the exception: a one-level factor cannot be a Cox predictor at all, so it drops out of the model entirely rather than leaving phantom rows.)

One caveat follows from levels being retained: if you cut the `animal_group` or `intake_type` value you set as an explicit Cox reference level, that level survives as an empty level and passes the reference check, but with no rows behind it the baseline is degenerate and every hazard ratio for that predictor comes out blank. Keep any reference level among the values you retain.

### Data screening

#### `discard_bad_rows`

```yaml
discard_bad_rows: false
```

Controls how row-level data quality errors are handled. Default is `false`.

The following checks are applied to every row:

| Check | Condition flagged as bad |
|---|---|
| `intake_date` | Cannot be parsed as a `YYYY-MM-DD` date. |
| `outcome_date` | Present but cannot be parsed, or is earlier than `intake_date`. (But same-day intake and outcome is allowed.) |
| `outcome_type` | Non-blank value that is not in `outcome_type_delete`, `outcome_type_in_care`, or among the recognized outcome labels: the mapped raw labels when the `outcome_type_L/T/N` settings are given, or the literal codes `L`/`T`/`N` when they are not. |
| `outcome_type` with `outcome_date` | An outcome code paired with a blank `outcome_date`: the stay claims to have ended without saying when, and no analysis can tell it apart from an animal still in care. Applied after the `outcome_type_in_care` recode, so a code meaning the animal has not left belongs in that setting and is not flagged here. |

- **`discard_bad_rows: false`** (default) — the run stops immediately with an error message describing the problem. Use this when data quality must be verified before any results are produced.
- **`discard_bad_rows: true`** — bad rows are dropped, with only a printed count. The run continues on the remaining rows.

Completely blank rows (no intake date, outcome date, or outcome type; e.g., a stray `,,` line) are not treated as errors: they are always dropped with a printed count, under either setting, before these checks run.

#### `discard_overlapping_rows`

```yaml
discard_overlapping_rows: false
```

Controls how **overlapping stays** are handled. Default is `false`. Meaningful only when the CSV supplies real `animal_id` values; with auto-generated ids every row is its own animal and no overlap can exist.

Two stays of the same `animal_id` overlap when each begins strictly before the other ends. Both directions must hold at once; one direction alone proves nothing, since for any two stays whatsoever the earlier one begins before the later one ends. Overlap in this sense is physically impossible: an animal cannot be in care twice at once. Same-day traffic is not overlap, because an animal can leave and return within one calendar day: a stay beginning on the day another stay ends is legitimate and never flagged. A blank `outcome_date` (still in care) counts as a stay with no end, so it conflicts with any later stay of the same animal; in particular, two still-in-care rows for one animal always conflict.

- **`discard_overlapping_rows: false`** (default) — the run stops with an error listing the overlapping pairs.
- **`discard_overlapping_rows: true`** — the shorter stay of each overlapping pair is dropped, with a printed count. A blank outcome date counts as the longest possible stay. If the two stays are equally long, the one appearing earlier in the file is dropped. The surviving rows keep their original file order.

The check runs after duplicate-stay removal and **before** the study window trimming (see the [data file section](#data-file-csv)), so overlaps are judged on the complete file, including stays outside the study window. This makes runs that share other settings, but test different study periods, more compatible.

### Regression options

#### `period_reference`

```yaml
period_reference: OLDEST
```

Which period serves as the reference in Cox regression. Choices: `OLDEST` (default) or `NEWEST`; any other value stops the run. This is a policy, not a period number: the reference is the oldest (or newest) period **that contains data**. Normally that is simply the first (or last) period, but if a boundary period turns out to be empty (the tool prints a warning when a defined period has no observations), the reference moves inward to the nearest period with data rather than failing. Other periods are reported as hazard ratios relative to the reference period. Does not change the underlying statistical model, only the parametrization.

Unlike `animal_group_reference` and `intake_type_reference`, the reference-choice pitfalls above rarely bite here: periods are the same shelter's population observed over different time windows, so one period isn't normally expected to be radically faster, slower, or sparser than another the way a deliberately distinct animal group or intake type might be.

#### `animal_group_reference`

```yaml
animal_group_reference: MED
```

The value of `animal_group` used as the reference (baseline) level in Cox regression. Optional; defaults to the most frequent level if omitted. An `_UNKNOWN_` filled level counts like any other, because some datasets use blank to mean "normal". If the specified value is **not found in the data, the run stops with an error**: a misspelled reference would otherwise silently reparametrize the model around a different baseline. When `animal_group` is constructed via `animal_group_columns`, the reference must be a full composite value (e.g., `F_LARGE`, not `F`). Other groups are reported as hazard ratios relative to this reference. Does not affect KM curves or AJ analyses.

**Choosing the reference is a reporting decision, not a modeling one.** It does not change the underlying model or its fit. The choice is purely a parametrization. Every hazard ratio in the output is a contrast against the reference, so a poor choice can make the whole table hard to read.

**Prefer a large group, with many outcomes, whose stays overlap well with the other groups.** Every reported hazard ratio and confidence interval inherits the precision of the reference. A small reference, or one whose animals are at risk over only a narrow stretch of the LOS range, widens the intervals of every row in the table, even for groups that are individually well estimated; a well-populated, well-overlapping reference confines any poor behavior to the problematic group's own row.

Also keep in mind what the estimate can and cannot say: a hazard ratio between two groups draws its direct information from the stretch of stay time over which both groups still have animals at risk. With several groups, information also flows indirectly, because all coefficients are estimated jointly: comparing each of two groups against a third bridges them even where they never overlap. But every such bridge relies on the proportional-hazards assumption, which the tool does not test (see the assumptions section of the methods document). If one group empties out early, its reported ratios rest mostly on the early part of the stay.

There is no easy rule of thumb that guarantees well-behaved output. Whether trouble occurs depends on how the groups actually overlap in your data. If the results show badly behaved values (hazard ratios near zero or absurdly large, enormous confidence intervals or standard errors), try a different reference category and rerun. Switching the reference rescales all hazard ratios by a common factor (each new ratio is the old one divided by the new reference's old ratio). The change to watch more closely is the reported uncertainty: the standard errors, confidence intervals, and p-values of each contrast. The stratified KM plots are the practical tool for picking the new reference: they show each group's curve, so look for a group whose curve steps down steadily across the plotted range and overlaps the others', rather than one that plunges to zero immediately or barely moves.

#### `intake_type_reference`

```yaml
intake_type_reference: STRAY
```

Same role as `animal_group_reference`, but for the `intake_type` column. Optional; defaults to the most frequent level, and a specified value not found in the data stops the run. The reference-choice guidance under `animal_group_reference` applies here unchanged.

#### `parametric_regression`

```yaml
parametric_regression: WEIBULL
```

Adds a **Weibull regression** alongside the Cox regression, with the same predictors and reference levels, reported on its own `Weibull_Regression` worksheet laid out like the Cox sheet. Accepted values: `false` (default, no parametric fit) or `WEIBULL`; any other value stops the run. Requires the `flexsurv` package (`install.packages("flexsurv")`); if the package is missing, or the fit fails to converge (e.g. every stay has nearly the same length), the parametric step is skipped with a note and the rest of the run is unaffected.

Why turn it on: the Weibull fit reports **LOS ratios** directly ("stays run 30% longer than the reference group"), with confidence intervals, rather than leaving readers to interpret hazard ratios, and it estimates the shape `k` as a number in its own right. The trade-off is that it assumes stay lengths follow a Weibull distribution; the worksheet's implied-hazard-ratio column (compare against the Cox sheet) is the built-in check on that assumption. It is not a way to get more out of a small dataset: the Cox fit copes with sparse data more comfortably, since it estimates its baseline out of the way rather than alongside the coefficients. The Weibull fit is the one that struggles when a cell is thin.

The worksheet also reports the Weibull shape `k`. Values below 1 mean discharge slows down the longer an animal has been in care, which means that there are more long residents, and group differences in LOS are larger than the hazard ratios suggest. Values above 1 mean discharge speeds up the longer an animal has been in care (fewer long residents; group differences in LOS are smaller than the hazard ratios suggest).

The worksheet closes with a **crude Weibull**: the same fit with the intake-type and animal-group terms dropped (intercept plus the period factor, when there is one), so its shape describes the shelter's pooled discharge process. Comparing the two shapes is a quick heterogeneity diagnostic. A pooled `k` below 1 next to an adjusted `k` near 1 means the apparent slowdown comes from mixing fast-moving and slow-moving groups (the fast ones leave the population first), not from individual animals getting harder to place the longer they stay. When the main model has no group terms, it already is the crude fit and the worksheet says so instead of repeating the numbers.

#### `weibull_shape_crossing`

```yaml
weibull_shape_crossing: true
```

Read only when `parametric_regression: WEIBULL` is set. Controls how the per-predictor Weibull sheets (`Weibull_By_Period` and the rest) let the shape vary. The default, `false`, gives each of the other predictors its own shape effect, so an intake type shifts the shape by the same factor in every animal group. Setting it to `true` gives every **combination** of the other predictors its own shape instead.

This is an advanced setting and a work in progress. Leave it off unless the shape structure itself is what you are studying. Turning it on costs a parameter per combination, so a run that meets a thin combination drops that one sheet back to the by-dimension shape and reports a different model there than on its neighbors. The findings deck makes no shape recommendation at all from a run in which any sheet crossed, so a run made this way has less to say about shape than the default one. What it buys, where the data can carry it, is a shape that belongs to the pairing rather than to either dimension, and a likelihood-ratio test saying whether the pairing earned its parameters.


### Plots and output selection

#### `plot_stay_cap`

```yaml
plot_stay_cap: 60
```

Positive integer, must be ≤ `restricted_stay_cap`. If provided, KM and AJ plots are truncated at this day on the x-axis. Does not affect any computed statistics. Defaults to `restricted_stay_cap` if omitted. Useful when the distribution is visually informative in the first few weeks but computation of the restricted mean must extend further for accuracy.

#### `max_plot_strata`

```yaml
max_plot_strata: 5
```

Positive integer, at most 13. The largest number of strata for which a stratified plot is drawn. A stratifier (period, intake type, animal group) with more levels than this has its plots skipped with a console message, while its companion CSV is still written. Default is 10. The upper limit of 13 is the number of distinct stratum colors in the tool's palette: a plot with more curves than colors would have to reuse them, making curves indistinguishable, so a larger value stops the run.

This setting affects **plots only**. Every numerical analysis runs on every stratum no matter the value of `max_plot_strata`, and the CSV behind each skipped plot is written unchanged, so nothing is lost but the picture. It's a matter of preference rather than a statistical choice. How many curves stay legible on one panel depends on how well they separate and on whether confidence-interval ribbons are drawn, which crowd a panel much faster than bare lines. See the section [Plot strata limit](#plot-strata-limit) above for some nuances on how this limit is applied for KM and AJ.

If the curves separate cleanly and you want to see all the plots, keep the limit at 13 so that the run produces as many plots as its palette allows.

If you use a high limit and end up with plots that are too cluttered to be useful, lower the limit to stop producing those plots.  This will allow your run to complete faster, but some of your results won't be plotted.  If you want those plotted, you're left with two choices: Reformulate to fewer strata (which changes the results), or take the CSV files and build your own plots, perhaps partitioning the levels for an offending stratifier and doing multiple plots instead of one.

Set `max_plot_strata` to `1` to turn stratified plots off entirely while still producing all their CSVs. Every stratifier has at least two levels by definition (a single-level column is not a stratifier at all and is skipped earlier), so a limit of 1 suppresses all of them. `0` is rejected: it would mean the same thing, and allowing two spellings of "off" invites ambiguity or typos.

#### `show_km_ci_ribbons`

```yaml
show_km_ci_ribbons: true
```

`true` or `false`. When `true`, the three stratified KM plots (`km_survival_by_*`) show a shaded confidence-interval ribbon per stratum, drawn as a true stair shape matching the curve. Default is `false`. The unified `km_survival_unified` plot always shows its ribbon regardless of this setting, and the `km_remaining_los_*` plots never do. The setting affects the plots only: the companion CSVs carry the bounds at either setting, in their own columns to the right of the estimates. See the [Kaplan-Meier plots section](#kaplan-meier-km-plots) above.

#### `show_aj_cif_ci_ribbons`

```yaml
show_aj_cif_ci_ribbons: true
```

`true` or `false`. When `true`, the stratified AJ CIF plots (`aj_cif_by_period_outcome_*`, and likewise for intake type and animal group) show a shaded confidence-interval ribbon per stratum. Default is `false`. The unified `aj_cif_unified` plot always shows its ribbons regardless of this setting, and the conditional outcome-probability (`aj_conditional_by_*`) plots never do. The setting affects the plots only: the companion CSVs carry the bounds at either setting, in their own columns to the right of the estimates. See the [Aalen-Johansen plots section](#aalen-johansen-aj-plots) above.

#### `png_pointsize_factor`

```yaml
png_pointsize_factor: 1.5
```

Positive number. Scales font sizes in PNG output. Default is 1.0. Values above 1 make text larger; useful on high-DPI displays or when plots will be used in presentations.

#### `png_line_width_factor`

```yaml
png_line_width_factor: 2.0
```

Positive number. Scales line widths in PNG output. Default is 1.0.

#### Stratified-output selection

```yaml
km_survival_by_stratifier: TRUE
km_remaining_los_by_stratifier: CSV
km_census_by_tenure_by_stratifier: PNG
km_in_care_tenure_by_stratifier: FALSE
aj_cif_by_stratifier: TRUE
aj_conditional_by_stratifier: TRUE
```

Six independent settings, one per family of stratified output, controlling which files that family produces. Each stratified plot is drawn once per stratifier (by period, by intake type, and by animal group), and each such plot has a companion CSV holding the plotted values. These settings choose, per family, whether to write the plot, the CSV, both, or neither:

| Value | Effect |
|---|---|
| `TRUE` *(default)* | write both the PNG plot and its companion CSV |
| `FALSE` | write neither |
| `PNG` | write only the PNG plot |
| `CSV` | write only the companion CSV |

The values are case-sensitive (all upper case, like every other setting value). Any setting you omit defaults to `TRUE`, so a settings file that predates these keys behaves exactly as before.

The six families are: `km_survival_by_stratifier` (the Kaplan-Meier survival curves by stratum), `km_remaining_los_by_stratifier` (expected remaining LOS), `km_census_by_tenure_by_stratifier` (steady-state census by current tenure), `km_in_care_tenure_by_stratifier` (in-care tenure profile), `aj_cif_by_stratifier` (Aalen-Johansen cumulative incidence), and `aj_conditional_by_stratifier` (conditional outcome probability).

These settings affect **only the stratified outputs**. The unified (whole-data) plots and CSVs, including `km_survival_unified`, `km_remaining_los_unified`, `km_census_by_tenure_unified`, `km_in_care_tenure_unified`, `aj_cif_unified`, `aj_conditional_unified`, and the AJ unified stack plots, are always produced. In particular, setting `km_remaining_los_by_stratifier` or `km_in_care_tenure_by_stratifier` to `FALSE` suppresses only that family's per-stratifier files; its `_unified` file is still written. The settings are also independent of [`max_plot_strata`](#max_plot_strata): a family whose stratum count exceeds that limit still has its plot skipped and only its CSV written, and even that CSV is suppressed if you set the family to `PNG` or `FALSE` here.

---

## Capabilities and Conventions

### Survival analysis framework

mLOS uses the **counting-process** formulation of survival analysis (`Surv(time_start, time_end, event)`), which correctly handles:

- **Left truncation**: animals already in care when a period begins are observed only from the period start, not from their intake date. This prevents length-biased sampling.
- **Right censoring**: animals still in care at the end of a period, or whose stays are capped at `restricted_stay_cap`, are treated as censored rather than excluded.

Animals participate in multiple periods if they were in care across period boundaries.

### Observation gaps

With left truncation it is possible, especially with a low number of animals, for some stretch of days to have **no animals at risk at all**. This happens when everyone at risk resolved before a later, left-truncated entrant arrived. The Kaplan-Meier estimator cannot recover from such a gap. If the last animal at risk before the gap leaves with an outcome, the curve drops to zero, and every outcome after the gap multiplies an already-zero curve: the post-gap stays contribute nothing to the median, percentiles, or restricted mean, which silently understates length of stay.

mLOS checks for gaps in the pooled (unified) KM data and, separately, within every stratum of the stratified KM analyses (by period, intake type, and animal group). A small stratum can have a gap even when the pooled data does not, and small strata are far more gap-prone. Gaps are reported in three places:

- Console warnings (which also appear in `analysis_log.txt`).
- The **Observation gaps** section of the Excel `General` sheet, listing every gap with its analysis, stratum, and day range.  It's shown **green** when no gaps were found and **red** when any were.
- The speaker notes of the two opening slides of the example deck, if you build one. The periods on the title slide, as well as the pooled data and the fields on the descriptive slide that follows it, indicate whether gaps occurred or not (see the Presentation Guide).

mLOS does **not** adjust any statistic for a gap: all numbers are reported exactly as computed, so a red gap section means the affected curves and restricted means should not be trusted from the first gap onward. If gaps are flagged, consider:

- **lengthening the periods** (fewer, longer periods keep more animals under observation on every day);
- **making `intake_type` or `animal_group` coarser** (fewer categories mean larger strata, for example by listing fewer columns in `animal_group_columns`);
- **reducing `restricted_stay_cap`**, so the analysis stops before the sparse right tail where gaps typically occur.

### Competing risks

The AJ analysis models L, T, and N as competing risks. Its central quantity is the cumulative incidence function (CIF, also defined in the [plots section](#plots) above): the CIF of an outcome type at day X is the probability that an animal has left care by that specific outcome type on or before day X, accounting for the fact that animals that experience one outcome type are no longer at risk for the others. This is conceptually different from (and more appropriate than) treating each outcome type as a separate KM analysis.

The conditional AJ distribution answers a complementary question: given that an animal is still in care at the end of day X (it did not leave that day), what is the probability it will leave with a specific outcome type before the end of the AJ analysis window? This is computed both unified and stratified, allowing comparison of how the expected outcome mix shifts with time already spent in care.

### Census and animal-day metrics

Three metrics summarize shelter population load per stratum:

- **total_animal_days** — total days of care provided.  It equals the sum of `days_at_risk` across all animals in the period. Counts both the arrival and departure days of each stay. Includes same-day (intraday) animals.
- **mean_census_inventory** — average number of animals in care.  It equals `total_animal_days` divided by the period length in days. It is a mean daily census, but it counts both arrival and departure days (and intraday animals). The mean overnight census (a morning-rounds headcount) equals the `mean_census_inventory` minus the `mean_daily_intakes`.
- **daily_mean_total_in_care_days** — the total in-care days accumulated by the animals in care overnight, averaged across the period. Excludes same-day arrivals/departures, since intraday animals contribute nothing to an overnight count. This is a cumulative-load metric (how much accumulated care the in-care population represents), not a headcount. It counts exactly the same nights as the overnight census (boundary nights are credited to the period containing the following morning), so dividing it by the mean overnight census gives exactly the average tenure so far of the animals in the shelter.

The KM block reports the curve's terminal value as `km_still_in_care_at_cap`, the fitted probability that an animal has reached the stay cap without an outcome. The block also reports the 95% confidence interval. Read this value beside `fraction_capped` in the observation block, which counts the rows that actually reached the cap. One is a tally and the other is an estimate from the fitted curve, so they answer the same question by different routes and are worth comparing. A wide gap says the curve is being pulled by censoring the tally cannot see. The bounds are blank where the curve has reached zero, which is `survfit` declining to bracket a boundary value, rather than a missing number.

These observed metrics have model-based counterparts, gathered with them in a **census aggregates** section on `By_All`, `By_Period`, `By_Intake_Type`, and `By_Animal_Group` (just after the KM block). `expected_census` is the Little's-law prediction, mean daily intakes times the KM restricted mean (see the [census by tenure plots section](#census-by-tenure-plots)), computed on the same conventions as `mean_census_inventory` (arrival and departure days both counted, animal-days counted only up to the restricted stay cap) and so directly comparable to it. Agreement means the population is near steady state: the census you have is the census your intake rate and stay pattern produce. A gap means the population is in transition, still working off (or building up) a backlog from an earlier regime. The prediction then shows the census the current rates are heading toward, which is often the more useful planning number.

The **care days of the census** are presented in two terms. Care that has already accrued is `expected_past_animal_days` and care still owed (within the stay cap) is `expected_future_animal_days`. The two differ by exactly `expected_census`, as each resident contributes one day to the difference.

Three **per-resident figures** follow: `per_resident_in_care_days` (observed, `daily_mean_total_in_care_days` ÷ `mean_census_inventory`), `per_resident_past_days` (the same accumulated-tenure quantity as the KM steady state implies, `expected_past_animal_days` ÷ `expected_census`), and `per_resident_future_days` (expected remaining stay per resident, `expected_future_animal_days` ÷ `expected_census`). The sequence is observed-past, inferred-past, inferred-future so the KM-inferred past sits between the two measures it is naturally compared with: observed vs inferred past is the backward-looking version of the census comparison, while inferred past and future differ by exactly one day. Note that `per_resident_in_care_days` divides by the inventory census, not by the overnight census of the exact conversion above: the inventory denominator matches `expected_census`, the denominator of the two inferred figures, so all three per-resident figures sit on the same convention, at the cost of reading slightly below the exact overnight-based tenure per animal present.

Two **quantiles of the tenure distribution** follow: `per_resident_past_days_restricted_median` and `per_resident_past_days_restricted_p90`. Read them as descriptions of the animals in care, not the animals arriving: the median resident has been here that long already, and one resident in ten has been here longer than the 90th percentile. On a stratum with a long tail these sit far above the KM median length of stay, and that gap is expected rather than a discrepancy, since long stays accumulate in the population while short ones pass through. Both are restricted to the stay cap: they are read off the tenure profile on days 0 to the cap, so a cap that binds pulls the 90th percentile down toward it without any missing-value marker to warn you. When many stays exceed the cap, the census numbers understate the true population by the animal-days beyond the cap.

Three rows close the section: `remaining_days_at_mean_tenure`, `remaining_days_at_median_tenure`, and `remaining_days_at_p90_tenure`, the remaining-LOS curve read at each of the three tenures just described. Read one as referring to one hypothetical animal: the resident in the middle of the population has already been here `per_resident_past_days_restricted_median` days and can expect `remaining_days_at_median_tenure` more. **`remaining_days_at_mean_tenure` is not the average remaining stay of the animals in care.** That average is `per_resident_future_days`, which sits a few rows above it and is always exactly one day more than `per_resident_past_days`. The reading at the mean tenure is usually much longer, because the curve climbs steeply over the early tenures and then flattens. (Reading a curve at an average is not the same as averaging it.) Both are worth having and they answer different questions: what a resident of typical tenure still owes, and what the whole standing population owes per head. All three inherit the cap sensitivity of the tenure numbers they are read at.

**Cap sensitivity of this whole section.** Every number here is restricted to the stay cap, and this is the section where that restriction bites hardest, the two quantiles hardest of all. The diagnostic sits a few rows above, in the KM block: `km_still_in_care_at_cap`. At half a percent the tenure figures already deserve a caveat when you quote them, and at one percent they deserve a second run at a different cap. The reason the threshold is so low is that this section counts residents rather than arrivals, and a long stay is a resident on many days, so the arriving-cohort fraction understates how much of the standing population the cap is silent about. See also "Choosing your `restricted_stay_cap`". Note what is not at issue: the animals that reach the cap are counted at full weight on every day up to it, so nothing here treats them as absent.

### Which day counts? Who is in the census?

Two conventions run through every count, and pinning them down removes most day-boundary confusion. The math methods document treats this in full (§2.7). Here are the essentials:

**Everything is read at the end of the day.** Each count is taken after that day's arrivals and departures have happened. That single vantage point fixes who is in and who is out: an animal that came in today is in care today, and one that left today is not. Nights carry their own label, described with the census flavors below.

**A stay counts both endpoints, so there are two tenure clocks.** A stay's length counts both its arrival and departure day, so a same-day arrival-and-departure has LOS = 1. There is no LOS = 0. On any given day an animal's **days in care so far** (its current LOS if it left today) includes today: every animal taken in today has been in care 1 day today. The plots and their CSVs instead use the **elapsed** count, "days already in care," which is one less, so it reads 0 on the intake day. The elapsed axis starts at 0 by design: it is where the survival curve is guaranteed to equal 1, and the first drop is at day 1 (one minus the fraction of same-day stays), which keeps the curve starting at exactly 1 with no zero-length stays.

**Remaining days exclude today but include tomorrow for free.** The remaining-LOS curves apply to an animal still in care at the end of today (it did not leave today). Today is already spent, so it is not counted in what remains; tomorrow is counted with certainty, because an animal here at the end of today will be here at least one more counted day even if it leaves tomorrow. This is why remaining LOS is never below 1.

**The census comes in two flavors that differ only on the arrival day.** The **inventory census** (`mean_census_inventory`, the predicted `expected_census`, and the census-by-tenure plots) counts an animal on every day it is present for any part of the day. It includes both today's intakes and today's outcomes (and same-day animals). It is not a snapshot at any instant. Picture kennels that can only be fully cleaned at day's end, so an animal ties up a kennel for the whole day even after it leaves, and two same-day animals that never overlap still use two kennels. The inventory census is that kennels-used count. The **overnight census** (the morning-rounds headcount, equal to the inventory census minus the mean daily intakes) instead counts only the nights actually held. A night is labeled by the morning that ends it, so each day of a stay carries the night before it, except its arrival day, which the animal was not there for. A stay is therefore held one night fewer than its LOS, a same-day animal is held none, and the count excludes an animal on its intake day and includes it on its outcome day. (Informally, morning rounds count the animals who were in the building the evening before: the same night, labeled by the morning that ends it rather than the evening that starts it. Either way it is a count of nights, not the inventory census.) Unqualified, "census" means the inventory census.

### Statistical testing

Cox regression tests whether the hazard of discharge differs across periods, intake types, and animal groups simultaneously in a single model. The proportional hazards assumption implies that the ratio of hazard rates between any two categories is constant over time. Robust (sandwich) standard errors clustered on `animal_id` are always used to account for the within-animal correlation across periods. If the CSV supplies no `animal_id`, ids are generated automatically (one per stay), which still ties a period-split stay into one cluster, but it cannot link repeat intakes of the same animal.

### ExitLOS vs AnimLOS

The L/T/N outcome types this tool reports on by default correspond to ExitLOS, as defined in [1]: length of stay measured up to the animal's exit from this organization, whatever form that exit takes.

You can instead have the tool compute AnimLOS (discussed in [2, 3]), which attempts to model an animal's length of stay across organizations rather than stopping at this one. For AnimLOS, animals transferred out to another organization need to be treated as censored rather than as a classified outcome, since their stay continues elsewhere and this tool has no visibility into it. To recode transfers as censoring, identify the raw outcome codes in your data that denote transfer to another organization, and list them under `outcome_type_in_care` (see the [settings reference](#settings-file-yaml) above).

---

## Limitations

- **Partial typographical checking.** Date fields and outcome type codes are validated (see `discard_bad_rows`). Errors in group labels or intake types are not caught and create unexpected factor levels in the output (blank values, by contrast, are handled: they are filled with `_UNKNOWN_`, as described in the [optional columns section](#optional-columns)). Validate your CSV before running.
- **Unclassified exits are accepted without a warning.** A row with an `outcome_date` but a blank `outcome_type` passes validation and is censored at its departure date (see the warning in the [data file section](#data-file-csv)). When such rows are data errors rather than deliberate, the censoring inflates the LOS estimates. The signal to check for this is the "Animals censored (unclassified exit)" count in the console Data Summary.
- **Proportional hazards.** Cox regression assumes that hazard ratios are constant over the entire LOS range. Violations can occur when, for example, long-stay animals have a fundamentally different discharge profile. The per-predictor stratified Cox fits in `results.json` are a partial screen on this: they re-estimate each stratifier's hazard ratios without assuming proportional hazards for the *other* two. A large gap between one of these and the unified Cox is a sign the assumption is straining for the remaining stratifiers, but says nothing about whether the assumption holds for the axis being estimated.
- **Minimum sample size.** Results become unstable with fewer than ~100 outcomes per period. With very few events, confidence intervals are wide and tests underpowered. When in doubt, use longer periods. The same goes for intake types or animal groups, and the remedy there is to condense values to a smaller set.
- **No interaction terms.** The Cox model includes period, intake type, and animal group as main effects only. Interactions (e.g., whether the period effect differs by animal group) are not estimated.
- **Single-intake assumption.** Each row in the CSV is treated as an independent intake event. If an animal has multiple intakes, each is a separate record. The `animal_id` column is used only for clustering standard errors, not to link successive stays analytically.
- **AJ conditional probabilities do not sum to 1.** The conditional AJ probabilities at each day X give the probability of each outcome type occurring between day X and the end of the AJ analysis window (see the next point for what sets that window, which is at most `restricted_stay_cap`). Their sum across outcome types is less than 1 whenever some animals are still in care at the end of that window: the remainder represents animals expected to still be in care then.
- **AJ conditional probabilities go to zero after the last observed event.** The AJ estimator is purely empirical. Its curves stop stepping at the last day any outcome was actually observed, which is often well before `restricted_stay_cap`. Once no more events are observed (even if animals are still at risk), the CIF stops stepping up, and the conditional probability of any future outcome drops to zero beyond that point. This does not mean those animals will have no outcome. It simply reflects the limit of the observed data. This is unlike the KM restricted mean (see the KM restricted mean above), which always extends all the way to `restricted_stay_cap` by holding the survival curve flat past its last observed value, a reasonable convention there because "still in care" is a stable, ongoing state, whereas holding a cumulative-incidence curve flat would wrongly imply that no further outcomes can occur.


---

## References

[1] Mavrovouniotis ML. Use of Kaplan-Meier and Cox regressions in the distribution of length of stay in animal shelters for pre-specified calendar periods: Definition, computation, and examples of dog length of stay in Orange County California. PLOS ONE. 2026;21(1):e0342102. doi:10.1371/journal.pone.0342102

[2] Mavrovouniotis ML. Distribution of Length of Stay and Its Variation by Calendar Period in Animal Shelters. In: Veterinary Information Network; 2026:456-459. [researchgate.net](https://www.researchgate.net/publication/403852994_Distribution_of_Length_of_Stay_and_Its_Variation_by_Calendar_Period_in_Animal_Shelters)

[3] Mavrovouniotis ML. Distribution of length of stay and its variation by calendar period in animal shelters: Cumulative incidence of outcome types by calendar period in Orange County California.  (Forthcoming in the JSMCAH special issue on the ABVP 2026 Symposium, to appear in www.jsmcah.org)

