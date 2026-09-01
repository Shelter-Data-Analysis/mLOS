<!--
Writing math that survives GitHub. GitHub runs its markdown pass over the
contents of inline and display math before the renderer sees them, so three
things that are correct LaTeX break there, and each was verified by eye on a
rendered page:
  \{ and \}   arrive as bare braces, so \left\{ becomes \left{ and the
              formula dies. Use a cases environment, or \lbrace and \rbrace.
  \_          arrives as a bare underscore, an error inside \text{} or
              \texttt{}. Keep real column and field names out of the formula
              and write them in code spans in the prose instead.
  *           is eaten as an emphasis marker. Write \ast (this file uses
              \tau^{\ast} throughout).
  }_          a subscript underscore right after a closing brace can open
              markdown emphasis, and a second one anywhere in the same
              paragraph (even in a different formula) closes it, so both
              underscores vanish and the formula dies. An underscore after a
              letter or digit is always safe. So write \widehat F_{k}, not
              {\widehat{F}}_{k}, and \mathrm{RMTL_{k}}, not \text{RMTL}_{k}.
              One such underscore survives at section 9 in
              {\widehat{se}}_{\text{RMST}}: it is safe only because nothing
              else in that paragraph can close it, so do not add a subscript
              there.
Safe, and used freely below: \, and \; spacing, the \\ row separator,
\mspace, subscripts, \left( ... \right). Putting the display delimiters on
their own line makes no difference either way. Pandoc is happy with all of the
above, so the Word export is not what constrains this.

Keep a long or tall expression (a summation with limits, a stacked fraction)
on its own display line rather than inside a text line, because GitHub wraps
tall inline math into two inset lines mid-sentence. Short ones stay inline;
this is a balancing act, not a rule to apply everywhere, and inside a table
cell or a dense list it is not an option at all.

House conventions for the documents, including this one, are in
documentation_rules.md at the repository root. Read it before editing. What
stays here is the LaTeX above: it is about how GitHub's markdown pass treats
math, which is this document's problem and no other's.
-->

# mLOS — Length-of-Stay Analysis Tool: Math Methods

*Note: This Markdown file is the documentation of record for mLOS math methods, version 20260901_001. Read it in any markdown reader that renders LaTeX math, Obsidian among them. The companion `mlos_math_methods.docx` is tracked here, but it is rebuilt only for a release, so it carries the version it was built from: where the two differ, this file is the current one and the Word copy lags it.*

*© 2026 Michael Loizos Mavrovouniotis. This document is licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). It is part of the mLOS project, whose code is released under the MIT License.*

# 1. Introduction and Scope

This document is the authoritative reference for all mathematical and statistical processing performed by mLOS (`mlos_setup.R`, `mlos_data.R`, `mlos_km.R`, `mlos_cox.R`, `mlos_aj.R`, `mlos_excel_export.R`, with shared helpers in `mlos_common.R`, orchestrated by `mlos_run_complete.R`). It states the conventions, estimators, and derived metrics precisely enough that results can be interpreted and reproduced without reading the code.

mLOS takes shelter intake/outcome records that distinguish three types of outcome (community live, other live, and non-live). The records may also carry two categorical covariates, intake type and a flexibly defined animal group. Those two, together with the analysis periods of §2.4, are the three axes the analysis partitions on: time period, intake type, and animal group. The analysis produces:

- Kaplan–Meier (KM) analysis of length of stay (LOS), unified (the whole sample) and stratified on the three axes.
- KM-based curves for expected remaining LOS conditional on elapsed days in care.
- Cox proportional-hazards regressions on the three axes.
- Weibull regressions on the three axes.
- Aalen–Johansen (AJ) competing-risks cumulative incidence functions (CIF) of the three outcome types, unified or stratified on the three axes.
- Outcome-mix curves from AJ conditional on elapsed days in care.
- Descriptive and fitted (expected) metrics of occupancy and flow, unified or stratified on the three axes.
- For every plot, a companion CSV of the plotted data.
- A consolidated Excel workbook.
- An experimental PowerPoint slide deck with its own workbook of results.

The statistical techniques come from the field of **survival analysis**. Accordingly, **“survival”** in this document means only that an animal is still in care and has no outcome yet. It says nothing about which outcome eventually follows, live or non-live. That distinction is handled by the competing-risks analysis of §7.

This document aims to balance mathematical rigor with ease of reading. Where a verbal description is unequivocal, no equation is given. Equations appear where the precise formula matters and cannot be easily conveyed in text.

# 2. Data Conventions and Preparation

**The examples used are marked OC1 or OC2.** The mark names the Orange County Animal Care run the figure was read from. OC2 is the default example and OC1 the earlier definition of the same shelter's records, both tracked under `data/` with provenance sidecars. The two do not always spell a level alike (large dogs are `LARGE` on OC2 and `LRG` on OC1), so a figure quoted without its mark would not be checkable against a run. A figure that holds on both names both, "on OC1 and OC2", rather than saying "on either run": that form quantifies over a set that can grow, and an OC3 would inherit a claim nobody checked against it. The Presentation Guide's "Worked examples, and which run they come from" gives the commands that reproduce either.

## 2.1 Input fields and canonical outcome codes

Each CSV row describes one shelter stay (each intake is a separate record, even for the same animal) and carries:

- `intake_date` (mandatory) — the calendar date the animal entered care.
- `outcome_date` (mandatory column; value may be blank) — the date the animal left care; blank means **still in care** at data extraction.
- `outcome_type` (mandatory) — blank for animals still in care (or, when `outcome_date` is recorded, for an unclassified exit; §2.3 and §3.2, source 4); otherwise a code that must resolve to one of the three canonical outcomes:
  - **L** — community live outcome (return-to-owner, adoption)
  - **T** — other live outcome (transfer, foster, return-to-field)
  - **N** — non-live outcome (euthanasia, died in care, lost in care)
- optional `intake_type` and `animal_group` (categorical covariates) and `animal_id` (used only for clustered standard errors in the Cox model, never to link successive stays of the same animal analytically). When the `animal_id` column is absent, or blank on some rows, ids are auto-generated at data-reading time, one per stay record, so each stay carries an id. A generated id treats each stay as a distinct animal.

`animal_group` may alternatively be **synthesized** (`animal_group_columns`): the listed CSV columns are concatenated in order with `_` as separator (e.g., gender `F` + size `LARGE` → `F_LARGE`), replacing any existing `animal_group` column.

The values of `intake_type` and `animal_group` may be **rewritten** (`intake_type_map`, `animal_group_map`): each setting lists value pairs, and every occurrence of a listed value is replaced by its target before the column is turned into levels, so a value mapped away is absent from every count, stratum, and model that follows. Replacement is simultaneous, so the pairs do not chain, and it happens after synthesis and after the missing-value fill below, meaning the keys are whole composite values and may include the `_UNKNOWN_` placeholder.

**Missing-value convention** for `intake_type` and `animal_group`: these columns never carry missing values into the analysis. Blank or absent entries are filled with the explicit placeholder level `_UNKNOWN_`, padded with an additional underscore on each side (`__UNKNOWN__`, …) until it matches no value already present in that column. Such rows therefore form their own level in the stratified KM curves and the Cox model, rather than being silently excluded by the fitting routines' missing-data handling. For a synthesized `animal_group`, the fill is applied to each source column **before** concatenation (gender `F` with a missing size yields `F__UNKNOWN_`), so a composite name never embeds an unnoticed missing piece.

Extra columns are ignored unless named in the settings to synthesize `animal_group` on the fly (`animal_group_columns`, above) or to apply an optional value filter (`other_filter_column_name`). Column order is irrelevant.

## 2.2 Outcome-label transformations (applied in this order)

1.  **Deletion** (`outcome_type_delete`): rows whose raw `outcome_type` matches any listed label are removed before any other processing.
2.  **In-care recoding** (`outcome_type_in_care`): rows whose raw `outcome_type` matches any listed label have `outcome_type` set to missing. **The `outcome_date` is retained**, so such a row is treated as *censored at its recorded departure date*. The animal contributes at-risk time up to that date but no classified outcome (see §3.2, censoring source 4).
3.  **Mapping** (`outcome_type_L` / `_T` / `_N`, all-or-none): remaining non-blank raw labels are mapped to the canonical L/T/N codes. If the three keys are absent, the CSV must already use L/T/N as the outcome type. Whitespace is trimmed before all comparisons, and no raw label may appear under more than one `outcome_type_*` setting (checked; violation is an error).

## 2.3 Row-level validation

Every row must satisfy: (a) `intake_date` parses as a `YYYY-MM-DD` date; (b) `outcome_date`, when present, parses and satisfies `outcome_date` $\geq$ `intake_date` (same-day intake and outcome is allowed); (c) `outcome_type` is blank or belongs to the recognized label set: the deletion list, the in-care list, and either the mapping labels (when the `outcome_type_L/T/N` keys are given) or the literal codes L/T/N (when they are not). The two modes are exclusive: with a mapping in place, a literal L/T/N in the CSV is recognized only if it is itself one of the listed raw labels.

Note that a recorded `outcome_date` with a blank `outcome_type` is valid, under either `discard_bad_rows` setting. The row is an unclassified exit, censored at its departure date (§3.2, source 4). Whether that censoring is appropriate is a data question the tool cannot check; see the warning in the User Guide's data file section. Under the default `discard_bad_rows: false`, any violation stops the run with a description of the offending rows; under `true`, offending rows are dropped. Rows with all three required fields missing are always dropped before these checks are applied, under either setting. A completely blank row is not an error.

**Duplicate-stay removal.** After `animal_id` is filled (§2.1), rows sharing the same triple of `animal_id`, `intake_date`, and `outcome_date` are reduced to their **last** occurrence. An identical triple is theoretically real only when `intake_date` equals `outcome_date` (an animal completing two full round trips within one day). But, even in this narrow case, it is far more likely to reflect a re-classification or an accidental duplication, so the last row, the presumed correction, is the one kept. Blank outcome dates compare equal, so two still-in-care rows for the same animal and intake date also collapse. With auto-generated ids (§2.1) every row is its own animal and the check removes nothing.

**Overlapping-stay handling** (`discard_overlapping_rows`). After duplicate removal, the stays of each `animal_id` are checked pairwise for physically impossible overlap. Two stays with intake dates $a_{1}, a_{2}$ and outcome dates $u_{1}, u_{2}$ (a blank outcome date counting as unbounded) **overlap** if and only if

$$a_{1} < u_{2}\quad\text{and}\quad a_{2} < u_{1}.$$

Equivalently, two stays do *not* overlap exactly when one ends on or before the other begins. A stay beginning on the day another ends (a same-day departure and return) is legitimate and never flagged; a same-day stay strictly inside another stay is flagged; and two still-in-care rows for one animal always conflict. Under the default `discard_overlapping_rows: false`, any overlap stops the run with a listing of the offending pairs; under `true`, within each animal the rows are ranked from longest to shortest (a blank outcome ranks longest; for equal lengths the later file row is ranked longest) and a row is dropped when it overlaps an already-kept row. In effect, the shorter stay of each overlapping pair is discarded. Of two equally long stays, the one earlier in the file is discarded. The check runs **before** the study-window filtering (§2.5), so overlaps are judged on the complete file. With auto-generated ids the check removes nothing.

**Optional value filters.** The settings may additionally restrict the analysis to a user-chosen subset of stays, keeping or dropping whole rows by matching `intake_type`, `animal_group`, or one other named column against a list of values. These filters are applied after the duplicate and overlapping-stay checks above, so those still judge the complete file, and before the study-window filtering of §2.5. Every downstream quantity is then computed on the retained subset. The setting syntax is documented in the User Guide.

**Row order.** Every cleaning step in this section, including the optional value filters, and the study-window filtering of §2.5, only removes rows: the surviving records keep their original file order until the period decomposition of §3 (the overlapping-stay tie-break relies on this).

## 2.4 Analysis periods

The settings supply an ordered vector of $m + 1$ boundary dates $b_{1} < b_{2} < \ldots < b_{m + 1}$, defining $m$ periods. By convention, **each period is left-closed and right-open**:

$$P_{j} = \lbrack\, b_{j},\mspace{6mu} b_{j + 1}\,),\quad\quad j = 1,\ldots,m,$$

A period’s end date, then, is the first calendar day **not** in the period, and period duration is $D_{j} = b_{j + 1} - b_{j}$ days. There is no limit on the number of periods for the analyses themselves. Only *plots* are skipped when a stratifier exceeds the plot-strata limit (§5.4). The **unified study window** is $\lbrack\, b_{1},\mspace{6mu} b_{m + 1}\,)$.

## 2.5 Study-window filtering and the record-inclusion requirement

After the transformations described in earlier sections, records are discarded if `outcome_date` $< b_{1}$ (the animal left before the window opened) or `intake_date` $\geq b_{m + 1}$ (the animal entered after the window closed). Blank outcome dates are not subjected to the first rule. Because this trimming comes last, out-of-window records still participate in the duplicate and overlapping-stay cleaning of §2.3 and can determine its outcome. **The cleaning result is thus a property of the data file alone**, independent of the chosen window.

The analysis is valid only if the input contains **every stay that overlaps the study window**, not merely stays that started or ended inside it. Animals already in care at a period start are handled by left truncation (§3.1). Omitting them would bias LOS estimates downward, because long-stay animals are exactly the ones most likely to span boundaries. Animals still in care at period end are handled by right censoring (§3.2).

## 2.6 Time scale and the day-counting convention

All survival times are in **days since intake**: for each animal, $t = 0$ at its own intake date.

**Day-counting convention.** Both the intake day and the outcome day count as days of stay:

- An animal arriving and leaving the same day has LOS $= 1$. **The minimum LOS is 1** and there is no LOS $= 0$.
- For an observed outcome, LOS = (`outcome_date` − `intake_date`) + 1.
- The $+ 1$ also guarantees strictly positive observation intervals (§3).

No $+ 1$ is applied in the above LOS formula when censoring at a period boundary, because the boundary date is already exclusive (the first day outside the period) and so inherently carries the extra day.

## 2.7 Which day counts, and who is in the census: end-of-day conventions

This subsection collects, in one place, which calendar day counts and which animals are counted for the length-of-stay, tenure, remaining-time, census, and flow quantities the tool reports. It extends the inclusive day-counting rule of §2.6 and is the reference for reading the "days already in care" axis of the plots (§§5.6–5.8) and the census figures (§4, §8.4). Nothing here changes a computation. It fixes the language for all of them.

**Two anchors.**

*Anchor 1: both endpoints count (the LOS clock).* Restating §2.6: for an observed stay with intake date $a$ and departure date $u$, $\text{LOS} = (u - a) + 1$, so both the arrival day and the departure day count as days in care. The minimum LOS is 1 and there is no $\text{LOS} = 0$. On the survival clock, the departure event lands at $t = \text{LOS}$, so $S(t) = P(\text{LOS} > t)$ satisfies $S(0) = 1$: no stay can end at $t = 0$.

*Anchor 2: everything is read at the end of the day.* The counts, tenures, remaining times, and census values are evaluated as of the end of the day, after that day's arrivals and departures have both occurred. This reference unambiguously settles whether an animal that arrives or departs on a given day is in or out of each quantity. Nights are the one exception, and carry their own label, given with the overnight census below. "End of the day" is a *reading* convention, not a claim about when during the day events actually happen. It is the vantage point from which the rules below are stated, and it is why an animal that came in today is already in care today, while one that left today is not.

**Two tenure clocks (they differ by one).** An animal in care today, with intake day $a$, has two tenures, and the tool uses both:

- **Days in care so far (inclusive count):** $(\text{today} - a) + 1$. Today itself counts, and on the intake day this is 1. This is the LOS-consistent count of §2.6, that is, the animal's current LOS if it were to leave today.
- **Days already in care (elapsed count):** $\text{today} - a$. Today is not yet counted as completed, and on the intake day this is 0. This is the $x$-axis of the "days already in care" plots and their companion CSVs (remaining-LOS §5.8, census-by-tenure §5.6, in-care tenure §5.7), and it is the argument $x$ of $S(x)$.

The two differ by exactly 1: elapsed $=$ inclusive $- 1$. The plots and CSVs are indexed by the **elapsed** count ($x = 0$ is the intake day). The LOS figure and the "current LOS if it left today" reading use the **inclusive** count (intake day $= 1$). An animal plotted at "0 days already in care" has, inclusively, been in care 1 day.

The elapsed axis starts at 0 by design: it places the curve's guaranteed value $S(0) = 1$ at the left edge, and pushes the first possible event to $x = 1$, where $S(1) = 1 - P(\text{LOS} = 1)$ is one minus the fraction of same-day (intraday) stays. This is what lets the survival curve begin at exactly 1 while keeping the minimum LOS at 1, with no zero-length stays. The two clocks are a deliberate pairing, not a discrepancy: the elapsed clock is the natural argument of $S$, and the inclusive clock is the natural way to state a stay's length.

**Membership rules, per computation.** For each quantity, this table shows whether today counts. It also shows whether an animal is counted today if today is its intake day, its outcome day, or both (an intraday round trip).

| Quantity | Does today count? | Intake today | Outcome today | Intraday (in and out today) | Per-stay total |
|---|---|---|---|---|---|
| **LOS** (per stay) | both endpoints count | arrival day counts | departure day counts | LOS $= 1$ | $(u-a)+1$ |
| **Current tenure**, inclusive (days in care so far) | yes, today counts | tenure $= 1$ | counted; tenure $= \text{LOS}$ | tenure $= 1$ | n/a (per day) |
| **Days already in care** (plot axis $x$) | no, today not yet completed | $x = 0$ | $x = \text{LOS}-1$ | $x = 0$ | n/a (per day) |
| **Remaining days** (Remaining LOS, §5.8) | no, today excluded; tomorrow included with certainty | remaining from arrival $=$ RMST | **excluded** from the "still in care" set (it left) | excluded | $\ge 1$ where defined |
| **Inventory census** (`mean_census`, `expected_census`, census-by-tenure) | present any part of today counts | **included** | **included** | **included** | $\text{LOS}$ animal-days |
| **Overnight census** (`= inventory − mean daily intakes`) | last night's held count | **excluded** (no night before it) | **included** (held last night) | **excluded** | $\text{LOS} - 1$ nights |
| **Intake count** (flow, §4) | counted today | counted | n/a | counted | 1 |
| **Outcome count** (flow, classified only, §4) | counted today | n/a | counted if classified | counted if classified | 1 |

**Current tenure (days in care so far) includes today.** Computed at the end of the day, an animal that is present has been in care for its arrival day through today, inclusive, so today counts. An animal that came in today therefore has a tenure of 1, the smallest value this clock takes, and an animal on its departure day has a tenure equal to its full LOS. The plots and CSVs carry the *elapsed* version of this axis, "days already in care," which is one less: 0 on the intake day.

**Remaining days do not include today but automatically include tomorrow.** Remaining LOS (§5.8) is defined for an animal still in care at the end of day $x$ (it has not left today, i.e. its length of stay $T$ exceeds $x$; §5.1). Today is already spent and is not part of what remains. Tomorrow, day $x + 1$, is counted with certainty, since an animal in care at the end of today will still be in care for at least one more counted day even if it leaves tomorrow. This is the leading $1$ in the formula, and it is why Remaining LOS $\ge 1$ wherever it is defined. An animal whose outcome is today is not in the conditioning set at all (it has already left), so it contributes nothing to remaining-time quantities for day $x$.

**The census exists in two conventions, and they differ precisely on the arrival day.** This is the subtlest point, and the two must not be conflated.

The **inventory census** is the headline census: `mean_census` / `mean_census_inventory` (§4), the Little's-law `expected_census` (§5.6, §8.4), and the height of the census-by-tenure profile (§5.6). It counts an animal on every day it is present for any part of the day, both its arrival day and its departure day inclusive, and it therefore includes intraday round trips. On a given day it counts both that day's intakes and that day's outcomes. Each stay contributes a number of animal-days equal to its $\text{LOS}$.

The inventory census on a day is **not** an instantaneous headcount taken at any moment of that day. Two intraday animals whose stays do not overlap (one leaves in the morning, another arrives in the afternoon) are never both physically present at once, yet the inventory census counts both. The convention that makes this the correct count is a resource, not a moment: picture animals housed individually, kennels that must be cleaned before re-use, and full cleaning that can only be completed at the end of the day. Then a kennel used by an animal is unavailable for the rest of that day even after the animal leaves, so the two non-overlapping intraday animals tie up two kennels, and the inventory census is the number of kennels used that day. Counting both endpoint days, and counting intraday animals, is exactly this kennel-occupancy count: every animal present during the day holds a kennel for the whole day. The Little's-law `expected_census` predicts this same kennels-used quantity.

The **overnight census** counts nights held rather than days present. A night is labeled by the morning that ends it, so each day of a stay carries the night before it, except the arrival day: the animal was not there for that night. A stay is therefore present for $\text{LOS}$ days and held for $\text{LOS} - 1$ nights, and an intraday stay is held for none. The count attached to a day is the morning-rounds headcount before that day's intakes. (It is equal to the previous night's headcount.) An animal is excluded on its intake day and included on its departure day. This is consistent with a shelter reviewing its overnight census during morning rounds. Summed over a period, one night is dropped per intake, which is what makes a period's overnight census equal to the inventory census minus that period's mean daily intakes (§4). The first night a period counts began in the period before it, and the night following its last day belongs to the period after it.

So the headcount a reader is likely to picture for "census", the animals physically in the building at the end of the day, is a night count rather than a day count. It excludes animals that left today and includes those that arrived today, which makes it an overnight census, attached by the label above to tomorrow. It is **not** the inventory census, which counts today's departures and today's intraday animals as well. When the text says "census" without qualification it means the inventory census. The overnight census is always named as such.

**Flow counts land on the day the event happens.** An intake is counted in the period containing its intake date. A classified outcome is counted in the period containing its outcome date (§4). These are event counts, not resident counts, so the intraday and endpoint questions do not arise: the intake and the outcome of an intraday animal are each counted once, on that day.

**Why the inventory census predicts what it predicts.** The census-by-tenure profile $N(d) = \bar{I}\,\widehat{S}(d)$ over $d = 0,\ldots,\tau - 1$ (§5.6, with $\tau$ the restricted stay cap of §3.3) uses the elapsed-tenure clock: at $d = 0$ (intake day) $\widehat{S}(0) = 1$, so all of a day's intakes appear at tenure 0, and the last tenure at which a stay of length $\text{LOS}$ is counted is $d = \text{LOS} - 1$ (its departure day). Summed, it gives the inventory census $L = \bar{I}\,\widetilde{\text{RMST}}$ (present on both endpoint days, matching `mean_census`), and the overnight prediction is $L - \bar{I}$. This is why predicted and observed censuses are compared on the inventory convention, with the overnight prediction obtained by subtracting the mean daily intakes, mirroring the observed-side identity of §4.

# 3. Period Decomposition: Truncation, Censoring, and Capping

Each stay record is converted into one row per period it participates in. With intake date $a$, outcome date $u$ (possibly missing), and period $P_{j} = \lbrack s_{j},e_{j})$, the animal **participates** in $P_{j}$ if

$$a < e_{j}\quad\text{and}\quad\left( u\text{ is blank}\mspace{6mu}\text{or}\mspace{6mu} u \geq s_{j} \right).$$

Each participating animal-period pair yields an observation interval $(t_{\text{start}},t_{\text{end}}\rbrack$ on the days-since-intake scale, and an event indicator $\delta$:

$$t_{\text{start}} = max\left( s_{j} - a,\mspace{6mu} 0 \right),$$

$$t_{\text{end}} = \begin{cases}
e_{j} - a, & \text{if }u\text{ is blank}, \\
\min\left( (u - a) + 1,\mspace{6mu} e_{j} - a \right), & \text{if }u\text{ is recorded},
\end{cases}$$

$$\delta = \begin{cases}
1, & \text{if outcome type is non-missing, }u\text{ is recorded, and }u < e_{j}, \\
0, & \text{otherwise (censored)}.
\end{cases}$$

Note that $\delta = 1$ requires a **classified** outcome: a retained departure date whose outcome type was recoded to missing (§2.2, in-care recoding) yields $\delta = 0$.

## 3.1 Left truncation (delayed entry)

If the animal was already in care at the period start ($a < s_{j}$), then $t_{\text{start}} > 0$: the animal enters the risk set at $t_{\text{start}}$, not at 0. This is standard left truncation. Within a period, animals whose stays began earlier are observed only conditionally on still being in care at $s_{j}$. Treating them as observed from intake would distort the estimates (length-biased sampling). Left truncation is handled identically in KM, Cox, and AJ via the counting-process representation (§3.5).

## 3.2 Right censoring — four sources

An observation is censored ($\delta = 0$) when no classified outcome occurs within its interval. Four mechanisms produce this:

1.  **Still in care** at data extraction (blank `outcome_date`), censored at the period end.
2.  **Administrative censoring at a period boundary**: the outcome occurred on or after $e_{j}$, so within $P_{j}$ the stay is censored at $e_{j} - a$. The same animal typically reappears, left-truncated, in the next period’s rows.
3.  **Capping** at the restricted stay cap (§3.3).
4.  **Unclassified exit**: the animal left care on a recorded date but has no classified outcome, either because its raw code was recoded by `outcome_type_in_care` or because the CSV supplied a date with a blank type. Such a row is censored at its departure time $\min\left( (u - a) + 1,\mspace{6mu} e_{j} - a \right)$ and does not participate in periods after its departure.

All four are treated as noninformative (independent) censoring. Sources 2 and 3 are administrative and satisfy this by construction. Sources 1 and 4 are assumptions: animals censored these ways are assumed to have the same residual-stay prospects as comparable animals remaining under observation.

## 3.3 Restricted stay cap

The configurable cap $\tau$ (`restricted_stay_cap`, a positive integer in days) bounds the analysis horizon: any row with $t_{\text{end}} > \tau$ is flagged as capped, has $t_{\text{end}}$ set to $\tau$, and is censored ($\delta = 0$). Capping makes all restricted-mean quantities well defined and prevents a few extreme stays from dominating means. The proportion of rows capped, $n_{\text{capped}}/n_{\text{rows}}$, is reported. A separate `plot_stay_cap` $\leq \tau$ limits only plot x-axes and affects no statistic.

Because $\tau$ sets the horizon for the KM restricted mean (§5.3) and Remaining LOS (§5.8), the tool's primary point estimates, it is one of the most consequential settings. It should be chosen deliberately from the observed stay-length distribution, more conservatively the sparser the data, since with few observations a single implausible or mis-recorded stay near or beyond $\tau$ can dominate the restricted mean. See the User Guide's "Choosing your `restricted_stay_cap`" section.

### Where the cap has its worst consequences

Every stay counts in full up to $\tau$, including the stays capped there. A row capped at $\tau$ is censored, not discarded: it stays in the risk set for all of days $0$ through $\tau - 1$ and never triggers a drop in $\widehat{S}$, so $\widehat{S}(d)$ for $d < \tau$ is exactly what it would have been with no cap, and the capped stay contributes the maximum any single stay can contribute to every sum over that grid. Concretely, the capped stays supply $\tau\,\widehat{S}(\tau)$ of the restricted mean $\sum_{d < \tau}\widehat{S}(d)$. On **OC1**’s animal groups that is about a tenth of the LRG figure, from under one percent of that group's arrivals. Nothing in the formulas treats a capped animal as absent.

What the cap does exclude is those stays' existence *beyond* $\tau$, and that exclusion is not spread evenly over the outputs. The single diagnostic is the curve's terminal value $\widehat{S}(\tau)$, reported as `km_still_in_care_at_cap` per stratum and as `still_in_care_at_cap` for the unified curve: it is the fraction of an arriving cohort that outlives the cap. **A value as small as 0.5% is not negligible**, because the standing population weights those stays by their duration (§5.6): a stay present for hundreds of days is present on hundreds of census days, so a remnant that is a rounding error among arrivals can be several percent of the residents. Ordered from most to least exposed:

1. **Resident tenure quantiles** (`per_resident_past_days_restricted_p90`, then `..._restricted_median`, §5.7). Worst affected, and the only quantities here that give no signal when they fail. They are read off a tenure profile that ends at $\tau$, so they behave as though every capped stay departed on day $\tau$. Since the profile is nearly flat far out in its tail, a small change in the excluded mass buys many days. On **OC1**, if the LRG stays at the cap were to continue for a further 200 days on average, that group's resident P90 would move from 190 days to about 254. At a further 380 days the true value would lie beyond $\tau$ and be unidentifiable, yet a definite integer would still be reported, since $G(\tau - 1) = 0$ makes "not reached" impossible by construction (§5.7).
2. **Resident tenure and workload means** (`per_resident_past_days`, `expected_past_animal_days`, `expected_future_animal_days`, `expected_census`, §5.6). These are lower bounds, and they are understated by more than $\widehat{S}(\tau)$ suggests, for the same length-bias reason. A mean spreads the missing mass over the whole range instead of concentrating it at one crossing point, so these move less than the quantiles.
3. **Restricted mean LOS** (§5.3). A lower bound on the unrestricted mean by exactly $\int_{\tau}^{\infty}S$, which is the point of the estimand rather than a defect: `restricted` in the name is the disclosure, and the horizon is reported beside the value.
4. **Cumulative incidences at the cap** (§7.2). $\widehat F_{k}(\tau)$ is a lower bound on each outcome's eventual share. The conditional and normalized quantities built on it (§§7.4, 7.5) are explicitly conditional on an outcome by $\tau$ and are unchanged by a larger horizon.
5. **Kaplan-Meier median and 90th percentile** (§5.2). Essentially unexposed, and honest when they are: they are read off $\widehat{S}$ itself, which the cap does not distort below $\tau$, and a quantile the curve never reaches is reported as "not reached" rather than as a value pinned near the cap.
6. **Cox and Weibull regressions** (§6). Capping enters as ordinary administrative censoring, so a capped stay contributes its full exposure to $\tau$ without its unknown end date being imputed.

The practical rule is that a cap chosen to exclude implausible records also sets a ceiling on the tenure and census figures, and the two purposes pull in opposite directions. Read $\widehat{S}(\tau)$ before quoting anything from groups 1 and 2, and re-run at a second cap when it is not near zero. The sensitivity of a number to $\tau$ is measurable, and measuring it only costs one more run.

## 3.4 Invalid intervals

The survival machinery requires $t_{\text{end}} > t_{\text{start}}$ strictly. The inclusive day-counting convention (§2.6) is what makes this strict inequality (rather than $\geq$) satisfiable by every genuine stay, because both the intake and outcome days count. A same-day intake and outcome yields $t_{\text{start}} = 0$ and $t_{\text{end}} = 1$, not a degenerate zero-length interval. If capping produces $t_{\text{start}} \geq t_{\text{end}}$ (e.g., an animal whose entire within-period exposure lies beyond the cap), the row is dropped from that period and the count is reported. Observed times are never altered to force validity.

## 3.5 Counting-process representation; multi-period animals

Each row enters the analyses as a counting-process triple, `Surv(time_start, time_end, event, type = "counting")`. At any duration $t$, the **risk set** consists of the rows with $t_{\text{start}} < t \leq t_{\text{end}}$.

An animal spanning $k$ periods contributes $k$ rows, contiguous on the days-since-intake scale. (Each period row’s censoring time equals the next row’s truncation time.) Pooled, these rows reconstruct exactly the risk-set contributions of the uncut stay. Rows are treated as separate at-risk intervals, not chained into per-animal trajectories. For KM and AJ the splitting is therefore fully neutral, for point estimates *and* confidence intervals alike, because the estimators and their variances depend on the data only through the aggregate event counts $d_{i}$ and risk-set sizes $n_{i}$, which the splitting leaves unchanged. What remains an assumption is independence across *distinct stays* (separate intakes, including successive stays of the same animal, §9). The Cox model corrects its standard errors for this via clustering (§6.3). If `animal_id` is provided, the correction applies across distinct stays. If it is not, one id is generated per stay, which still allows Cox to correct for the splitting of stays across periods.

# 4. Occupancy and Flow Metrics (per period)

For each period $P_{j}$ of length $D_{j}$ days, using the capped intervals of §3:

**Days at risk** per row: $r = t_{\text{end}} - t_{\text{start}}$. No further $+ 1$: the inclusive day counting is already embedded in $t_{\text{end}}$, so an intraday animal has $r = 1$.

**Total animal-days**: $A_{j} = \sum_{\text{rows in }P_{j}}^{}r$. Counts both arrival and departure days, and includes intraday animals.

**Mean census (inventory)**: $A_{j}/D_{j}$, the average daily in-care count under a convention that counts an animal as present on both its arrival and its departure day. It is therefore slightly inflated relative to an overnight census. The **mean overnight census**, the average number of animals held per night (§2.7), equals the mean census minus the mean daily intakes, or $\left( A_{j} - I_{j} \right)/D_{j}$, with $I_{j}$ the period's total intakes (defined below). Under the night rule of §2.7, a stay's nights in a period are its days present there minus its arrival day (when the arrival falls in this period). Accordingly, intraday animals contribute no overnight presence.

**Daily mean of total in-care days** — a cumulative-load metric, not a headcount. On each night an animal is in care, it contributes its days in care as of that night, on the inclusive count of §2.7, which is also the number of nights it has been held since intake, including that night. Equivalently, this is the elapsed count on the next morning. The metric is the period’s nightly totals averaged over its $D_{j}$ days. Nights are credited to the period containing the following morning (§2.7), the same convention as the overnight census above, so the two metrics count exactly the same nights. For a row $(t_{\text{start}},t_{\text{end}}\rbrack$ the nightly contributions are the integers $m,\ldots,t_{\text{end}} - 1$ with $m = \max\left( t_{\text{start}},\, 1 \right)$: an intraday animal contributes none, and a left-truncated row’s first contribution, at value $t_{\text{start}}$, is the night straddling the period boundary. They sum to

$$\frac{\left( t_{\text{end}} - m \right)\,\left( m + t_{\text{end}} - 1 \right)}{2}.$$

The metric is this quantity summed over the period’s rows, divided by $D_{j}$. A stay spanning several periods contributes exactly $\text{LOS} - 1$ nights across them: the period splitting is neutral for this metric, as for the others. Dividing the metric by the mean overnight census $\left( A_{j} - I_{j} \right)/D_{j}$ converts it exactly into the **mean days already in care per animal present**: how long the current population has been in care, on average.

**Intake and outcome flow.** Total intakes in $P_{j}$ = rows with $s_{j} \leq$ `intake_date` $< e_{j}$; total outcomes = rows with a **classified** outcome (non-missing `outcome_type`) whose `outcome_date` lies in $\lbrack s_{j},e_{j})$. Unclassified exits are not counted as outcomes. Mean daily intakes/outcomes divide by $D_{j}$.

# 5. Kaplan–Meier Analysis

## 5.1 Estimator

Let $T$ be length of stay and $S(t) = P(T > t)$ the probability of still being in care $t$ days after intake. With distinct event times $t_{1} < t_{2} < \ldots$, $d_{i}$ classified outcomes at $t_{i}$, and risk-set size $n_{i}$ at $t_{i}$ computed from the counting-process intervals (so truncation and all censoring sources are respected), the product-limit estimator is

$$\widehat{S}(t) = \prod_{i:\, t_{i} \leq t}^{}\left( 1 - \frac{d_{i}}{n_{i}} \right).$$

The **unified** analysis fits this to all pooled period rows. If no animal is at risk over some stretch of durations before $\tau$ while animals are at risk after it, the curve cannot be identified across that gap in observation, and a warning is printed. (Such a gap is possible under left truncation.) The check is made on the intervals themselves, because fitted times by construction have $n_{i} \geq 1$.

## 5.2 Median, 90th percentile, and confidence intervals

The median LOS is the smallest $t$ with $\widehat{S}(t) \leq 0.5$. The 90th percentile is the smallest $t$ with $\widehat{S}(t) \leq 0.10$ (90% of animals have had an outcome by then). Either may be “not reached.” **Exact-tie exception:** if $\widehat{S}(t)$ equals the target level exactly over a flat stretch (a run of consecutive durations with no event), the `survival` package's convention is to report the midpoint of that stretch rather than its left edge: e.g. $\widehat{S}(t) = 0.10$ for $t \in \lbrack 15,20)$ yields a reported 90th percentile of $17.5$, not $15$. Pointwise 95% confidence bounds for $\widehat{S}(t)$, and the confidence intervals (CIs) of the median and the 90th percentile, use the `survival` package defaults (Greenwood variance on the log-survival scale). A quantile's CI is obtained by inverting the curve's pointwise bounds, so a bound is reported as NA when the corresponding bound of the curve never crosses the target level within the cap. The median is reported with the caveat (see the User Guide) that it is typically a small integer and insensitive to changes in the long-stay population. The full curve is the primary output.

## 5.3 Restricted mean LOS

Because the largest observations are often censored, the unrestricted mean is not identified. mLOS reports the **restricted mean survival time (RMST)** at horizon $\tau$:

$$\text{RMST}(\tau) = \int_{0}^{\tau}\widehat{S}(t)\, dt,$$

the area under the KM curve up to the cap: the expected LOS within the first $\tau$ days. For the unified curve this is computed exactly from the step function (`survival`’s `rmean`), and that exact value populates the `restricted_mean` row of the unified curve’s CSV. For **stratified** curves, the CSV `restricted_mean` row is instead the daily step sum

$$\widetilde{\text{RMST}} = \sum_{d = 0}^{d_{\max}}\widehat{S}(d)$$

over the daily-tabulated curve (§5.5), the unit-width Riemann sum of the same area. Because every observation time is an integer number of days (§2.6), $\widehat{S}$ can jump only at integer times and is constant on each interval $\lbrack d,\, d + 1)$, so the step sum equals the integral *exactly*.

The RMST is reported with a 95% CI, $\text{RMST}(\tau) \pm 1.96\,\widehat{se}$, using the standard error the `survival` package computes alongside `rmean`. Both the unified interval and the per-stratum ones appear in the workbook's confidence-interval section (§8.4), the unified one in the single column of **By_All**.

## 5.4 Stratified KM and the plot-strata limit

Separate KM curves are fit for each level of, in turn, `period_label`, `intake_type`, and `animal_group`, but a stratifier with fewer than two observed levels is skipped. Estimation within a stratum applies §5.1 on the stratum's rows. Stratum names have the `column=` prefix stripped for display and CSV headers, and the stratified CSVs carry the confidence intervals alongside the survival estimates. Per-stratum 95% confidence ribbons are an optional plot overlay (`show_km_ci_ribbons`, off by default). When a stratifier has more levels than the plot-strata limit (`max_plot_strata`), the **plot** is skipped but the companion CSV is still written. The fits and statistics run on the full data regardless of the number of strata, so the limit is a legibility preference, not a statistical choice. See the User Guide's plot strata limit section for the setting itself.

## 5.5 Daily tabulation (forward fill)

To tabulate a fitted survival curve on the daily grid $d = 0,1,\ldots$, the value at day $d$ is the estimate at the largest fitted time $\leq d$. It is $1.0$ before the first fitted time. Confidence bounds are forward-filled the same way. The KM CSV files contain the daily estimates with their lower and upper 95% bounds (for each stratum, in the case of stratified CSVs).

For KM curves, both unified and stratified, the grid runs through day $\tau - 1$, matching the horizon used for the restricted mean (§5.3) and for Remaining LOS (§5.8). When no observation extends that far, the curve is simply held flat via the same forward-fill rule.

## 5.6 Steady-state census by tenure

Each KM fit, combined with the observed intake rate, implies a standing population: how many animals are in care, and how long each has been there. Let $\bar{I}$ be the **mean daily intakes** of the fitted stratum: for a period stratum, $I_{j}/D_{j}$ (§4); for an intake-type or animal-group stratum, its total intakes divided by the whole study window $\sum_{j}D_{j}$, the same denominator convention as the stratum sheets (§8.3).

Suppose the population is at **steady state**: intakes arrive at the constant rate $\bar{I}$ per day and every stay follows the fitted LOS distribution. On any given day, consider the animals whose intake was $d$ days earlier. Under the inventory convention of §4 (present on both arrival and departure day), such an animal is still present exactly when its LOS exceeds $d$ counted days, i.e. $T > d$, which has probability $\widehat{S}(d)$. The expected number in care at tenure $d$ is therefore

$$N(d)\mspace{6mu} = \mspace{6mu}\bar{I}\,\widehat{S}(d),\qquad d = 0,1,\ldots,\tau - 1:$$

The KM curve, rescaled by the intake rate, is the **census-by-tenure profile**. Summing over the daily grid gives the predicted total,

$$L\mspace{6mu} = \mspace{6mu}\sum_{d = 0}^{\tau - 1}N(d)\mspace{6mu} = \mspace{6mu}\bar{I}\,\widetilde{\text{RMST}},$$

which is **Little's law**: average population = arrival rate $\times$ average time in system. $L$ predicts the **mean census (inventory)** of §4, not the overnight census: the present-at-tenure-$d$ indicator $\lbrace T > d\rbrace$ counts arrival and departure days exactly as $A_{j}$ does. The overnight prediction is $L - \bar{I}$, matching the identity of §4. The comparison is also cap-consistent on both sides: the observed census counts a stay's animal-days only up to $\tau$ (the capped $t_{\text{end}}$ of §3.3), and $L$ truncates the same tail, so predicted and observed remain directly comparable even when the cap binds. Both understate the true building census by the animal-days beyond $\tau$.

Everything in this section and in §5.7 is therefore **restricted to the cap on both readings**, and these are the outputs most sensitive to the choice of $\tau$. The reason is that the resident view weights each stay by its duration, so the cap's excluded tail carries more weight here than it does in any arriving-cohort figure: a remnant of a fraction of a percent of arrivals can be several percent of the residents. The curve's terminal value $\widehat{S}(\tau)$, reported as `km_still_in_care_at_cap`, is the diagnostic, and §3.3 ranks which quantities move and by how much. Where $\widehat{S}(\tau)$ is not near zero, read every figure below as a lower bound and check it by repeating the run with a different cap.

Dividing by the total turns the profile into the **tenure distribution of the in-care population**,

$$p(d)\mspace{6mu} = \mspace{6mu}\frac{\widehat{S}(d)}{\widetilde{\text{RMST}}},$$

This distribution is length-biased. Because a long stay is present on more days than a short one, the animals seen in care on any given day overrepresent long stays relative to the intake cohort the KM curve models.

**The workload the census carries.** The same profile carries two animal-day totals, both summed over the daily grid. The **elapsed** workload $\bar{I}\sum_{d}d\,\widehat{S}(d)$ is the care the standing population has already received, and it predicts the **daily mean of total in-care days** of §4: a stay of length $T$ is held on $T - 1$ nights, carrying tenures $1$ through $T - 1$, which sum to $T(T - 1)/2$. The **future** workload $\bar{I}\sum_{t}(t + 1)\,\widehat{S}(t)$ is the care it is still owed within the cap. The two differ by exactly the census:

$$\bar{I}\sum_{t = 0}^{\tau - 1}(t + 1)\,\widehat{S}(t)\; - \;\bar{I}\sum_{d = 0}^{\tau - 1}d\,\widehat{S}(d)\; = \;\bar{I}\sum_{t = 0}^{\tau - 1}\widehat{S}(t)\; = \;L,$$

Each resident contributes one day to the gap, so the two per-resident readings (dividing each workload by $L$) differ by exactly one day. §5.8 shows that the future workload is also the census profile multiplied by the remaining days each of its animals expects.

mLOS plots $N(d)$ for the unified fit and once per stratifier, a curve per stratum (“Expected Number in Care” against “Days Already in Care”), each plot with a companion CSV (§8.2), and gathers these aggregates in a **census aggregates** block on the aligned workbook sheets (§8.4): $L$ as `expected_census` beside the observed `mean_census_inventory`, the elapsed and future workloads as `expected_past_animal_days` and `expected_future_animal_days` beside the observed `daily_mean_total_in_care_days`, and the three per-resident readings. The same block, row-for-row identical, appears for the whole unstratified sample on the By_All sheet (§8.3). Agreement is consistent with a population near steady state. A gap flags a population still in transition (§9, item 10).

## 5.7 In-care tenure profile

The tenure distribution $p(d)$ of §5.6 also stands on its own as a survival-style curve: the fraction of the steady-state in-care population whose current tenure exceeds $x$,

$$G(x)\mspace{6mu} = \mspace{6mu}\sum_{d > x}p(d)\mspace{6mu} = \mspace{6mu}\frac{\sum_{d = x + 1}^{\tau - 1}\widehat{S}(d)}{\sum_{d = 0}^{\tau - 1}\widehat{S}(d)},\qquad x = 0,\ldots,\tau - 1.$$

The intake rate $\bar{I}$ cancels, so $G$ is a pure normalized transform of the stratum's KM curve — no arrival-rate assumption enters. It describes (in survival-function form) the distribution of the time already elapsed for the stays in progress — at a random instant in steady state. It is a distribution over **tenures**, not over lengths of stay, even though the LOS curve is what generates it. (Renewal theory calls it the equilibrium, or age, distribution.) Its mean is

$$\sum_{x}G(x) = \frac{\sum_{d}d\,\widehat{S}(d)}{\sum_{d}\widehat{S}(d)},$$

the `per_resident_past_days` of §5.6, the same name the CSV header row uses.

mLOS plots $G$ for the unified fit and once per stratifier on the same day axis as the KM curve (§8.2), so the intake cohort and the standing population can be read side by side. The unified plot is marked at its median and 90th percentile, the two quantile rows of §8.4, where the marks cross $G$ at $0.5$ and $0.1$ by the reading convention those rows use. It is also marked at its mean, $\sum_{x}G(x)$. The same three values are where the unified Remaining LOS curve is marked (§5.8). Unlike the Kaplan-Meier median and 90th percentile marked on the survival plot, these are always reached and always restricted, as explained at the end of this section.

The two curves describe different populations, and the comparison is informative rather than tautological even though $G$ is derived from $\widehat{S}$. **If the discharge hazard is constant** (memoryless / exponential LOS), then $G(x) = \widehat{S}(x + 1)$: with $\widehat{S}(d) = q^{d}$, $\widetilde{\text{RMST}} = \sum_{d \geq 0}q^{d} = 1/(1 - q)$ and $p(d) = (1-q)q^{d}$, so $G(x) = \sum_{d > x}p(d) = q^{x + 1} = \widehat{S}(x+1)$ exactly. Equivalently, the in-care tenure is memoryless too, and equals $T - 1$ in distribution (elapsed tenure starts at $0$, while LOS $T$ never reaches $0$). So $G$ decays at the same rate as $\widehat{S}$ but reads one grid step ahead of it — a fixed one-day offset, rather than an exact coincidence at matching $x$.

But **if the hazard is decreasing** (long-stay-heavy, the typical shelter case, e.g. Weibull shape $k < 1$ of §6.6), $G$ lies **above** $\widehat{S}$ by more than that one-day baseline offset: the animals in care overrepresent long stays, because a long stay is present on more days than a short one (length bias). An **increasing hazard** puts $G$ below $\widehat{S}$ instead.

So the vertical gap between the two curves, net of the one-day baseline offset of the constant-hazard case, shows how much the tenure of the animals housed at steady state skews away from the length of stay of the animals taken in, and its sign indicates the hazard's direction.

$G$ also does not start at $1$ the way $\widehat{S}$ does: $G(0) = 1 - p(0) = 1 - \widehat{S}(0)/\widetilde{\text{RMST}} = 1 - 1/\widetilde{\text{RMST}}$, since $\widehat{S}(0) = 1$. The excluded mass $p(0) = 1/\widetilde{\text{RMST}}$ is the fraction of the steady-state in-care population at tenure exactly $0$ (admitted today), which the strict "$> 0$" in $G(0)$'s definition excludes. It shrinks toward $0$ as $\widetilde{\text{RMST}}$ grows, so long-stay strata start close to $1$ and short-stay strata start well below it — the same day-$0$ mass that §5.6 uses as the scale factor $\bar{I}$ recoverable from $N(0)$, here normalized instead of rescaled.

**Cap sensitivity, and what the normalization assumes.** The denominator $\sum_{d < \tau}\widehat{S}(d)$ is the restricted mean, so $p$ is a proper distribution on $0,\ldots,\tau - 1$ and $G$ is the tenure distribution generated by the *capped* stay $\min(T,\tau)$ rather than by $T$. Truncating the grid at $\tau$ and renormalizing is algebraically identical to assuming every stay still in care at the cap departs on day $\tau$. That assumption is unavoidable and self-declaring for the restricted mean of §5.3, whose name states it. Here it is neither, which makes $G$ and especially its quantiles (§8.4) the outputs most exposed to the cap. Note what the assumption does **not** do: a capped stay is fully present in the numerator for every $d < \tau$ (§3.3), so it is weighted at its maximum within the cap, and only its days beyond $\tau$ are missing. The mean $\sum_x G(x)$ inherits the same restriction as a lower bound. See §3.3 for the ranking and for worked magnitudes on OC.

This curve uses the **elapsed tenure** of the steady-state in-care population. A different, forward-looking reading — the distribution of the *total eventual* length of stay of the animals in that population — is the length-biased LOS distribution, with survival $\sum_{d > x}d\,f(d)/\sum_{d}d\,f(d)$ where $f(d) = \widehat{S}(d^{-}) - \widehat{S}(d)$; for exponential LOS that one is Gamma$(2,\lambda)$ (Erlang-2) rather than exponential. It is not currently produced, because the remaining LOS, in the next section, is more meaningful in practice.

## 5.8 Expected remaining LOS

For each KM fit, mLOS also computes, for every $x = 0,1,\ldots,\tau - 1$, the **expected remaining LOS** for an animal still in care at the **end of day** $x$ (it has accrued $x$ counted days and did not leave that day, i.e. $T > x$):

$$\text{Remaining LOS}(x)\mspace{6mu} = \mspace{6mu} 1\mspace{6mu} + \mspace{6mu}\frac{1}{\widehat{S}(x)}\sum_{t = x + 1}^{\tau - 1}\widehat{S}(t),$$

This uses the daily-tabulated $\widehat{S}$ of §5.5 and is undefined (missing) where $\widehat{S}(x) = 0$. It is the discrete, cap-restricted mean residual stay, viewed as an end-of-day quantity. Since

$$\frac{\widehat{S}(t)}{\widehat{S}(x)} = \widehat{P}(T > t \mid T > x)$$

is the probability of still being in care at the end of day $t$, each sum term is the probability that day $t + 1$ counts. The leading $1$ is day $x + 1$ itself: an animal still in care at the end of day $x$ accrues tomorrow as a counted day with certainty, even if it leaves tomorrow. Hence $\text{Remaining LOS}(x) \geq 1$ wherever it is defined. **Consistency check:** at $x = 0$, because $\widehat{S}(0) = 1$ (the minimum LOS is 1, so no outcome can occur at $t = 0$),

$$\text{Remaining LOS}(0) = \sum_{t = 0}^{\tau - 1}\widehat{S}(t),$$

which is the daily step-sum restricted mean of §5.3. These curves are plotted for the unified fit and once per stratifier (“Expected Remaining Days in Care” against “Days Already in Care”), each plot with a companion CSV.

**Complementarity with §5.6.** The census profile $N(d)$ of §5.6 says how many animals sit at each tenure. Remaining LOS says how many more days an animal at that tenure expects. Their product, summed over the grid, is the future workload of §5.6, the animal-days the current census is still owed within the cap:

$$\sum_{d = 0}^{\tau - 1}N(d)\,\text{Remaining LOS}(d)\mspace{6mu} = \mspace{6mu}\bar{I}\sum_{t = 0}^{\tau - 1}(t + 1)\,\widehat{S}(t),$$

where terms with $N(d) = 0$ are read as $0$ (Remaining LOS is undefined there, but no animals are at stake). The closed form follows from

$$N(d)\,\text{Remaining LOS}(d) = \bar{I}\,\left( \widehat{S}(d) + \sum_{t > d}\widehat{S}(t) \right)$$

and reordering the double sum. The two analyses are two readings of the same partial sums of $\widehat{S}$, tied together by the identity $\text{Remaining LOS}(0) = \widetilde{\text{RMST}}$ above.

**Where the unified curve is marked, and why not at its own quantiles.** Remaining LOS is a function of tenure, not a distribution over animals. Its column holds one value per day of the grid, so a median of those values would be a median over days, weighting the single day at tenure 200 exactly as it weights the single day at tenure 3. This would not say anything interesting about the shelter. What is meaningful is the value the curve takes **at** a tenure that is itself a statistic of the standing population. The unified plot is therefore marked at the median, the 90th percentile and the mean of the in-care tenure distribution $p$ of §§5.6 and 5.7, and its legend reports the Remaining LOS the curve takes at each: the animal in the middle of the standing population has been in care so long, and expects this many days more.

Reading the curve at the mean tenure is **not the mean of the curve over residents**. The latter average has a closed form:

$$\sum_{d = 0}^{\tau - 1}p(d)\,\text{Remaining LOS}(d)\mspace{6mu} = \mspace{6mu}1 + \frac{\sum_{d}d\,\widehat{S}(d)}{\sum_{d}\widehat{S}(d)},$$

with terms set to $0$ whenever $\widehat{S}(d) = 0$, exactly as in §5.6. This is 1 plus `per_resident_past_days`, and equals `per_resident_future_days`, the future workload per resident reported in §5.6. The remaining LOS metrics are distinct from this, and reported beside it, as `remaining_days_at_mean_tenure`, `remaining_days_at_median_tenure`, and `remaining_days_at_p90_tenure` (§8.4). Each is computed from its own stratum's fit at that stratum's own tenure statistic, so they are available per stratum even though only the unified curve is marked in the plot. The two readings differ by a Jensen gap whose sign follows the curvature of Remaining LOS over the bulk of $p$. Where the curve is concave, the usual shape when the discharge hazard falls steeply early and then flattens, the mark sits above the resident average. On **OC1** the gap is wide, 74.9 days at the mean tenure against 53.7 days averaged over residents. The mark answers what a resident of typical tenure still owes. `per_resident_future_days` answers what the standing population owes per head.

# 6. Regressions on the Three Factors

Two regression families are fitted on the same counting-process rows and the
same three factors: Cox, which leaves the baseline hazard unspecified, and an
optional Weibull, which gives it a parametric form and so reports a
length-of-stay ratio directly. In their pooled form both hand every covariate
pattern a single baseline shape.

The order below is Cox first (§6.1 to §6.5), then the Weibull and its shape
variants (§6.6 and §6.7), then the stratified Cox (§6.8). The last two allow the
covariate pattern to affect the shape of the LOS distribution or the hazard
function. §6.7 relaxes the LOS distribution parametrically, by freeing the
Weibull shape. §6.8 relaxes the hazard function nonparametrically, by giving
each combination of the other factors its own baseline. §6.8 closes by comparing
what the two approaches to relaxation say on the same data.

## 6.1 Model and predictors

The Cox model for the hazard of *any classified outcome* (all outcome types pooled) is

$$h(t \mid x) = h_{0}(t)\,\exp\left( \beta^{\top}x \right),$$

with $h_{0}(t)$ an unspecified baseline hazard and $x$ dummy indicators for whichever of the following have at least two observed levels: **period**, **intake type**, and **animal group**. Here, only main effects are used, with no interaction terms estimated. A filled `_UNKNOWN_` level (§2.1) counts as an observed level, so rows with a missing covariate value participate in the fit as their own group. If none qualify (a single period, and no intake type or animal group column), there is no predictor left to fit (the global tests of §6.4 would have nothing to test against), so Cox regression is skipped entirely for that dataset.

**Reference levels.** The reference level for each factor is chosen by `period_reference` (a policy, `OLDEST` or `NEWEST`, resolving to the oldest or newest period *with data*), `intake_type_reference`, and `animal_group_reference` (each a named level). When a level is not named, the **most frequent level**, counted over animal-period rows with a filled `_UNKNOWN_` level (§2.1) eligible like any other, is used. Reference choice affects only the parametrization (which contrasts are reported), not the fit. The User Guide's settings reference gives the selection syntax and its validation.

**Reference choice and reporting quality.** Although the fit is invariant to the reference, every reported contrast is against it, so the choice governs how readable the output is. A reference level with few events, or one whose risk set occupies only a narrow stretch of the LOS range, inflates the standard errors of *all* reported contrasts. A large, well-overlapping reference confines poor behavior to the genuinely problematic level's own row.

When a level's outcome timing barely overlaps the reference's, the partial likelihood for that contrast can be monotone (separation) and the estimate diverges. The parametrization sets only the reported direction, toward $\infty$ against a slow (long-LOS) reference and toward 0 against a fast one, the latter being the numerically safer failure mode. No rule of thumb prevents this in general. Beyond the data's overlap structure, the ratio is extrapolation under the proportional-hazards assumption (§9, item 2). When the output shows degenerate hazard ratios or extreme standard errors, change the reference level and refit, using the stratified KM plots of §5.4 to choose one (the User Guide gives the same guidance for practitioners).

## 6.2 Estimation with truncation and censoring

The model maximizes the Cox partial likelihood over the counting-process rows, so the risk set at each event time contains exactly the rows whose interval covers that time: left truncation and all four censoring sources of §3.2 are handled automatically. The proportional-hazards assumption states that each covariate multiplies the hazard by a constant factor across all durations $t$ (see §9).

**Tied event days.** Event times are whole days (§2.6), so ties are massive: every day on which more than one animal has an outcome is a tie. The fit uses the **Efron approximation** to the tied partial likelihood (the `survival::coxph` default). The choice determines what the reported hazard ratio estimates. Picture each day as containing an outcome window within which discharges occur at a constant rate. A covariate that multiplies that within-day rate by $c$ turns the daily probability $q$ of an outcome into $1 - (1 - q)^{c}$ (equivalently, survival through a day is raised to the power $c$: the grouped form of proportional hazards). Under day-counted data from such a process, the Efron-approximated HR targets the **within-day rate ratio** $c$. It does not target the ratio of daily probabilities, nor the daily odds ratio, which is what the exact discrete likelihood (`ties = "exact"`, a conditional-logistic model) would estimate. When daily probabilities are small, all three nearly coincide. This behavior is verified against a simulation fixture `tests/cases/sim_geometric_period_effect`, whose within-day outcome rate doubles at a period boundary and whose fitted period HRs are checked against 2.

**Interpretation.** A hazard ratio $\text{HR} = e^{\beta} > 1$ means an increased discharge hazard, i.e. shorter stays. An $\text{HR} < 1$ means longer stays. For each coefficient the tool reports $\text{HR}$, the 95% confidence interval $\exp\left( \widehat{\beta} \pm 1.96\,\widehat{se}\left( \widehat{\beta} \right) \right)$, and a Wald p-value.

## 6.3 Clustered robust standard errors

The model is always fit with `cluster(animal_id)` and robust variance: the sandwich (grouped-jackknife) estimator treats each **animal**, not each row, as the independent unit, correcting the standard errors for the correlation among an animal’s multiple period rows. `animal_id` is guaranteed to exist: when the CSV omits it (§2.1), ids are generated one per stay record *before* the period decomposition of §3, so a generated id still gathers one stay’s period rows into a single cluster. What it cannot do is link separate stays of the same animal, which only a supplied id can. The likelihood-ratio and score tests still assume within-cluster independence. The Wald and robust score tests do not, so those are the ones to rely on under clustering.

## 6.4 Global tests and concordance

The fit reports the likelihood-ratio, Wald, and score (log-rank) tests of the global null $\beta = 0$. It reports the robust score test when the fit yields one; some degenerate fits do not. It also reports the concordance (C-index) with standard error: the probability that, of two comparable animals, the one with the higher fitted hazard has the shorter stay.

## 6.5 Reading hazard ratios on the time scale

Hazard ratios live on the hazard scale, not the LOS scale: $\text{HR} = 2$ does **not** mean stays half as long. Because the model of §6.1 is unstratified, all covariate patterns share the single baseline, and proportional hazards ties their survival curves to it by a power law,

$$S(t \mid x) = S_{0}(t)^{\text{HR}(x)}.$$

Expected LOS is the area under the survival curve, so each HR does correspond to a definite LOS ratio. The correspondence runs through the *shape* of $S_{0}$, however, and equals $1/\text{HR}$ only when the baseline hazard is constant over the stay. mLOS reports hazard ratios only and performs no such conversion. The stratified variants of §6.8 have no single $S_{0}$ to read against; they have one per stratum instead, so this whole conversion is unavailable for them. Their hazard ratios can nevertheless be compared to the ones here.

**Weibull rule of thumb.** If the baseline is approximately Weibull, $S_{0}(t) = \exp\left( - (t/\lambda)^{k} \right)$, then $S_{0}(t)^{\text{HR}}$ is again Weibull with the same shape $k$ and the time axis rescaled: every quantile of stay, and the mean, change by the factor $\text{HR}^{- 1/k}$. The shape $k$ can be read off a plot of $\log\left( - \log\widehat{S}(t) \right)$ against $\log t$ (near-Weibull ⇔ near-straight line of slope $k$). With $k = 1$ (constant hazard) this recovers $1/\text{HR}$. With $k < 1$ the discharge hazard declines over the stay, so animals already long in care tend to stay longer still (a common shelter pattern) and the hazard ratios *understate* the LOS differences. With $k > 1$ they overstate them. The rescaling inherits the proportional-hazards assumption (§9). It is exact for uncapped Weibull means and quantiles, but only approximate for the restricted means mLOS reports (§5.3), the approximation being workable when the cap $\tau$ sits well past the bulk of the stay distribution.

**All-cause only.** This time-scale reading is available precisely because the Cox model pools all outcome types (§6.1). The outcome-specific curves of §7 have shapes that are harder to characterize and certainly differ by outcome type, driven by mechanistic constraints early in the stay, such as a hold period during which return-to-owner outcomes concentrate while adoption of stray intakes cannot yet occur. Those distortions largely offset in the all-cause curve, which is why it is the smoother, better-behaved object. Fitting Cox models per outcome type (censoring competing outcomes) would compound this with the deeper problem that such fits address a hypothetical world where the competing outcomes do not occur. Regression on the outcome-specific cumulative incidences themselves (Fine–Gray/Gray) is not currently included in mLOS but may be added in a future version.

## 6.6 Optional Weibull regression (`parametric_regression: WEIBULL`)

When enabled, a Weibull regression is fitted **in addition to** Cox on the same counting-process rows, the same predictors, and the same reference levels. The model makes the §6.5 rule of thumb exact: the baseline is $S_{0}(t) = \exp\left( - (t/\lambda)^{k} \right)$ and each covariate rescales the time axis, so $e^{\beta}$ is directly the **LOS ratio** (with $\beta$ the coefficient on log time). The parametric form buys the shape $k$ as an estimate in its own right, quantities that extend past the last observed event, and the LOS ratio without conversion, at the price of the Weibull assumption itself, which the implied hazard ratios below are the check on. Data thin enough to trouble a Cox fit troubles this one more rather than less: Cox profiles its baseline out of the partial likelihood as a nuisance function, while a Weibull fit estimates $(k,\lambda)$ alongside the coefficients through a nonlinear optimization that a thin cell can send to a boundary or to a singular Hessian (§6.7).

**Estimation.** The fit uses `flexsurv::flexsurvreg` rather than `survreg`, because the animal-period rows carry left truncation (§3.1), which `survreg` does not accept. The truncated-segment likelihood makes within-stay period splitting *exactly* neutral: contiguous segments of one stay multiply back to the full-stay contribution,

$$\frac{S(t_{1})}{S(t_{0})} \cdot \frac{f(T)}{S(t_{1})} = \frac{f(T)}{S(t_{0})},$$

so the log-likelihood, and with it the maximum-likelihood estimate (MLE) and the Hessian-based standard errors, is identical whether a stay is split or not, for any covariate holding one value over the whole stay. Where period changes at a boundary the same product is the likelihood of a covariate that changes on that date, which is the intended model rather than an approximation of an unsplit one. Either way the segments enter as a single product and not as separate units, which is why no clustering correction is owed for the splitting. A degenerate or non-convergent fit (e.g. all stays the same length) is skipped with a console note and a "not available" note on its worksheet, and the run continues. A fit that returns but that the optimizer left short of a maximum, or whose Hessian is not positive definite, is reported rather than skipped: the estimates stand and the intervals around them are approximations, and a "Fit stability" row on the worksheet says which of the two the reader has.

**Starting values** (for the Weibull regressions of this section and §6.7). `flexsurvreg` derives its own, and they go wrong in two ways. On some datasets they place the initial log-likelihood at $-\infty$, so the optimizer stops before it has started ("initial value in `vmmin` is not finite") on a fit that is not ill-posed at all. On others they converge early and report success from a point short of the maximum, which is the worse case, since nothing about the returned fit signals it. Every fit is therefore made from `flexsurvreg`'s own start and from each point of a fixed grid of nine explicit starts, with the covariate coefficients started at zero: shape 0.6 or 1.0 at scale 5; shape 0.6 or 1.2 at scale 10; shape 0.6, 0.8, or 1.0 at scale 20; and shape 0.8 or 1.2 at scale 40. The scales reach down to 5 days rather than up past 40 because a shelter at capacity turns over fast by necessity, and a mean stay of a few days is a real operating regime rather than an edge case. The best log-likelihood wins but, in order to beat `flexsurvreg`'s own start, a grid start has to win by $10^{-6}$ of its own magnitude, far above the optimizer's own convergence tolerance. This means that a run for which the grid is either unhelpful or only trivially helpful stays with `flexsurvreg`'s fit and reproduces exactly.

On **OC2** every fit succeeds from `flexsurvreg`'s own start, and two of the six a run makes stop short of what a grid start reaches, by 54 and 75 log-likelihood units. Both carry the `shape()` terms of §6.7, which is where the shortfall concentrates. The consequence to accept is that a Weibull number can move on any dataset, an archived run included, wherever a non-trivially better optimum exists to move to: a fit that is not in the immediate vicinity of the maximum is wrong whether or not it reported an error, and reproducing a wrong number is not worth the fits it saves. A dataset whose scale suits none of the starts can still fail outright, in which case the block reports itself unavailable. `tests/scan_shape_floor.R` recomputes the per-formula comparison for any dataset it is pointed at (including the shape parameterizations of §6.7), not just the fits an ordinary non-test run on that dataset makes.

**Reported.** For each coefficient, the LOS ratio $e^{\beta}$ with 95% CI and Wald p-value. This is the practitioner-facing quantity, read as "1.30 = stays about 30% longer than the reference level". Alongside it, the **implied hazard ratio** $\text{HR} = \left( e^{\beta} \right)^{- k} = e^{- k\beta}$, with a delta-method CI over the estimation-scale parameters $(\log k,\ \beta)$, printed and exported side by side with the Cox hazard ratios: their agreement is a direct, assumption-light check that the Weibull description of the discharge process holds (§6.5). A likelihood-ratio test against the covariate-free Weibull is also reported, which is the parametric analogue of Cox's global tests (the other Cox tests having no counterpart). Finally, the shape $k$ with CI and a plain-language legend:

- $k < 1$: the discharge hazard falls with tenure, so there are **more long residents** and LOS differences between groups are larger than the hazard ratios suggest.
- $k = 1$: constant hazard; the LOS ratio is $1/\text{HR}$.
- $k > 1$: the discharge hazard rises with tenure, so there are **fewer long residents** and LOS differences are smaller than the hazard ratios suggest.

The LOS ratios describe full stays under the fitted model. Restricted means (§5.3), which stop at the cap, differ slightly (§6.5).

**Crude companion fit.** The worksheet closes with a second Weibull fitted on the same rows with the group terms dropped: intercept plus the period factor when at least two periods have data, intercept only otherwise. (When the main model already has no group terms, the fit is not repeated and the worksheet says so.) Its shape describes the *marginal* discharge process, and the pair of shapes is a diagnostic for unobserved-mixture effects: with heterogeneous groups, the marginal hazard falls with tenure as the fast-leaving group drains out of the risk set, even when every group's own hazard is constant. A crude $k < 1$ alongside an adjusted $k \approx 1$ therefore signals composition, not stays that stall with tenure. The `sim_size_mixture` test fixture is a worked example: a 70/30 mixture of two constant-hazard groups whose adjusted shape sits near 1 while the crude shape sits near 0.87.

**Standard errors.** The reported SEs are model-based (inverse Hessian). Within-stay splitting cannot affect them (see above), but the invariance holds *only* for likelihood-based variances: any future sandwich or bootstrap variance must cluster split rows by stay. Correlation among **repeat stays** of one animal is **not corrected**. Unlike `coxph`, which offers `cluster()`, no ready clustered-variance option exists for `flexsurvreg`, so treating stays as independent is a software-availability choice. A by-animal cluster bootstrap is the upgrade path if animals with repeat stays dominate a dataset. (This differs in kind from KM/AJ, whose *point estimates* need no such correction by construction. The independence assumption their confidence intervals carry is stated in §9.)

## 6.7 Per-predictor Weibull shape regression (`parametric_regression: WEIBULL`)

A stratified KM curve by period (§5.4) mixes two things: whatever period itself does to length of stay, and any shift in the *mix* of intake types and animal groups across periods — a composition effect of exactly the kind the crude-companion comparison of §6.6 exposes for the marginal curve. Cox (§6.1) and the pooled Weibull of §6.6 both adjust for this, holding intake type and animal group fixed as covariates alongside period, so their period coefficient describes period's own effect. But both still force **one baseline shape onto every covariate pattern**: Cox's baseline hazard is nonparametric but *shared*, so proportional hazards ties every intake type and animal group to the same baseline shape. The pooled Weibull's baseline is parametric but likewise a single $(k,\lambda)$ pair extended to every pattern by a scale-only formula. Neither lets the *shape* of the discharge process — how the hazard evolves over the stay, not just its level — differ between, say, owner-surrendered strays and transferred-in large dogs.

When enabled, mLOS fits one additional Weibull regression per predictor $X$ that already qualifies for the pooled model of §6.1 (period, intake type, or animal group; qualification is at least two observed levels, as in §6.1). A second pre-condition is that at least one *other* qualifying predictor exists to place on shape; with only one qualifying predictor overall there is nothing to vary shape by, and the step is skipped. Each such "shape variant" keeps the identical location (scale) formula of §6.6 — every qualifying predictor, the same reference levels, the same re-leveled rows — so $X$'s LOS ratio is read under the same adjustment as the pooled Weibull and is directly comparable to it cell for cell. What changes is that the **other** qualifying predictors are additionally placed on the shape parameter, through `flexsurv::flexsurvreg`'s ancillary-parameter (`shape(...)`) formula terms:

$$\log\lambda(x) = \beta_{0} + \sum_{p}\beta_{p}^{\top}x_{p},$$

$$\log k\left( x_{- X} \right) = \gamma_{0} + \sum_{p \neq X}\gamma_{p}^{\top}x_{p}.$$

The scale sum runs over every qualifying predictor, exactly as in §6.6. The shape sum runs over every qualifying predictor **except** $X$, one term per level.

So the "period" variant lets the shape differ by intake type and by animal group while period's own coefficient is read exactly as in the pooled model. The "intake type" variant instead frees period's and animal group's shapes while reporting intake type's LOS ratio, and symmetrically for "animal group".

**Reported**, per variant: the LOS ratio $e^{\beta_{p}}$ for every qualifying predictor, with CI and Wald p-value, as in §6.6 (the general-Weibull number and this one agree up to sampling noise whenever a single shared shape genuinely fits the data); the **shape ratio** for **other** predictors' levels, the multiplicative effect on $k$ of that level relative to its reference, with CI and Wald p-value; the baseline shape $k\left( x_{- X} = \text{reference} \right)$, the shape at the reference combination of every non-$X$ predictor, with its CI; and a likelihood-ratio test against the covariate-free Weibull, the same recipe as §6.6.

**Reading a shape ratio.** A shape ratio near 1 (CI spanning it) says that predictor's levels share one discharge-hazard shape, so the single-shape assumption behind the pooled Weibull (and, via §6.5, the Cox proportional-hazards assumption) is not contradicted for that predictor here. A shape ratio far from 1 says the levels' hazards evolve differently over the stay, a distinction the pooled models cannot see and do not report, since they fit one $k$ for everyone. The ratio holds across the board, since additivity is the assumption that a level multiplies $k$ by the same factor in every cell. Freeing the shape formula changes only how $k$ is modeled, not the location formula, so $X$'s own LOS ratio remains an estimate under the same scale model as §6.6. It can differ from the general-Weibull number only insofar as the fit no longer forces a shared shape onto covariate patterns.

**Reading the baseline shape.** The reported $k\left( x_{- X} = \text{reference} \right)$ is the shape of **one covariate combination**, the cell in which every non-$X$ predictor sits at its reference level. It is not an average over the data, and it does not summarize the dataset's shape. A level's own shape is that baseline times its shape ratio, so a baseline near 1 above a column of ratios below 1 still describes a population whose discharge hazard mostly falls with tenure. That product is the level's shape in the cells holding the reference level of every *other* shape predictor, so a published own $k$ belongs to a cell: away from those cells the level's own ratio still applies, multiplied by the other predictors' ratios. On **OC2** the scale = period variant puts LARGE at 0.67, which is LARGE among strays, and the same fit puts LARGE at 0.52 in RET and 0.69 in OWNER. This matters because it is the step at which the composition reading of §6.6 is easily overextended: showing that a mixture of groups *can* manufacture a pooled $k$ below 1 does not establish that it *did*, and the two mechanisms can coexist. On **OC2** they do. The pooled crude shape is 0.71 and the adjusted shape 0.82, so composition is contributing. But in the scale = period variant, whose reference combination sits at $k = 0.99$, the large-dog shape ratio of 0.68 puts that group's own shape at 0.67, genuine tenure dependence within the group and not a mixture artifact, while the puppy ratio of 1.08 puts puppies at 1.07, a discharge hazard that *rises* with tenure. Read the baseline and the ratio column together, or convert to per-level shapes, before attributing a sub-1 shape to either mechanism alone.

**Estimation, standard errors, and failure modes** follow §6.6 exactly: the same `flexsurvreg` counting-process fit, the same model-based (Hessian) standard errors with the same no-repeat-animal-clustering caveat, the same graceful skip on non-convergence, a console note and a "not available" note on its worksheet without stopping the run, and the same "Fit stability" row when a fit returns but its intervals are approximations. The `sim_size_mixture` test fixture, already the worked example for §6.6's crude-companion comparison (a 70/30 mixture of two constant-hazard groups whose pooled shape sits near 0.87 from composition alone), also exercises this section: its "period" and "animal group" variants each estimate a reference-combination shape near 1 and a shape ratio for the other predictor near 1 too, correctly reporting that neither predictor's levels actually need their own shape in that simulated dataset — the composition effect there being period-neutral by construction.

### Crossing the shape terms (`weibull_shape_crossing`)

The additive formula above gives each shape *dimension* its multipliers separately, and it places the cells on an additive grid in $\log k$. Setting `weibull_shape_crossing: true` replaces the shape sum with one term per combination $c$ of the levels of every predictor except $X$,

$$\log k\left( x_{- X} \right) = \gamma_{0} + \sum_{c}\gamma_{c}\,\mathbb{1}\left\lbrack x_{- X} = c \right\rbrack,$$

so that $\log k$ becomes a free function of the non-$X$ cell. For the by-period Weibull with **OC2**'s four intake types and five animal groups, that makes $4 \times 5 - 1 = 19$ free shape parameters under crossing, against $(4 - 1) + (5 - 1) = 7$ for the additive shape terms. That makes this fit parallel to the stratified Cox of §6.8, whose crossed `strata()` term gives each combination its own nonparametric baseline, and the additive grid is a constraint the data need not satisfy: because the additive shape model is nested inside the crossed one, the two are compared by a likelihood ratio on the difference in shape parameters, reported per variant, and on an **OC2** run with crossing enabled that comparison rejects the grid wherever it is made, at 98.2 on 8 degrees of freedom for the intake-type variant and 50.2 on 6 for the animal-group one. The scale formula stays additive either way, which is what keeps $X$'s own LOS ratio a single acceleration factor common to every cell (§6.5) and comparable cell for cell with §6.6.

This is an **advanced setting**, and it is off by default. Treat it as **work in progress**. A shape per cell is a parameter per cell, a thin cell cannot pay for one, and the guards listed below then drop that variant back to the additive formula, so one worksheet in a run may report a different model than the next. Selective merging of thin cells, which would address this complication, is not implemented. The reading a crossed fit supports is also narrower: a crossed shape ratio holds only at the reference level of the other shape predictors, where an additive one holds across the board, and a run in which any variant crossed gets no shape recommendation on a slide (see the recommendation section of the Presentation Guide). Enabling crossing is a choice to study the shape structure on a worksheet, not a way to get better numbers out of the rest of the tool.

**Only with three or more qualifying predictors.** With exactly two, $x_{- X}$ has a single dimension: its combinations *are* that one predictor's levels, the crossed formula and the additive one are the same model written two ways, and the setting changes nothing. Only a third qualifying predictor makes the crossed form, its guards, and its fallback reachable at all.

**When crossing cannot be afforded.** Two guards apply, in order, and both fall back to the additive shape formula, recording the reason. The reported model formula names which of the two produced the numbers, and a "Shape crossing" row on the worksheet gives the state in words.

The first guard is a **count**, applied before anything is fitted: every combination of the non-$X$ predictors must hold at least 5 **outcomes**. Outcomes and not stays, because a Weibull shape is identified by observed exit times — a censored row contributes only a survival term and a left-truncated one only conditions the risk set, so left truncation is tolerable here but heavy censoring is not. A combination absent from the data counts as zero, so an empty cell is refused by name here rather than reaching the optimizer as a singular matrix. One combination under the floor vetoes the crossing for that whole variant. Pooling thin cells into one or more remainders instead could keep it, at the price of a synthesized level, and is the natural upgrade if this section is developed further.

Five is low on purpose, since crossing is reached only when asked for and the precision of a cell's shape is then the requestor's judgment. What the floor still owes is the cell no judgment can rescue: with the guard lifted, **OC2**'s one-outcome cell takes an implied $k$ of 1.78 whose interval runs from 0.35 to 8.94, where a well-populated cell such as RET $\times$ LARGE gets 0.49 to 0.54. A floor set for precision would instead land near 15. The standard error of a fitted Weibull shape falls as roughly $0.78/\sqrt{n}$ on the log scale, and the **OC2** cells match that closely at $0.72/\sqrt{n}$, while the real spread of shape *between* well-populated cells there, meaning the 15 of its 20 cells that hold at least 100 outcomes, is about 19%, with $k$ running 0.61 to 1.22 at a standard deviation of 0.17. Putting the floor where those meet, so a cell's shape is known about as precisely as the variation the crossing exists to model, gives $n$ between 14 and 16. That is the number to restore if crossing ever stops being a deliberate choice. The per-cell fits behind this paragraph are recomputed by `tests/scan_shape_floor.R`.

The second guard is the **fit**, which catches what a count cannot: cells individually adequate but jointly awkward, showing up as an outright failure or as a non-positive-definite Hessian. Since a crossed fit has somewhere to fall back to, that case is treated as a refusal here rather than reported with approximate intervals as §6.6 describes.

On an **OC2** run with `weibull_shape_crossing: true`, the count guard fires once, on the scale = period variant, where 1 of the 20 intake-type $\times$ animal-group combinations falls short (RET $\times$ `_UNKNOWN_`, at one outcome). That variant reports the additive shape formula; the other two the crossed formula. A default run reports the additive formula on all three. Crossing adds no variant: there is one per qualifying predictor either way, and each of **OC2**'s three would cross on the shape of its data alone. What crossing adds is a second fit to every variant that actually crosses, the additive formula being the denominator of that variant's crossing test. With one of the three refused above, two carry that second fit, so the run makes eight Weibull fits against a default run's six: the pooled model, the covariate-free null, the crude companion, and one variant apiece. The crossed scale = animal-group fit is the one that gains most from the starting-value grid of §6.6, at 260 log-likelihood units against 54 and 75 for the two additive fits a default run already covers.

**Reported additionally**, on a variant that crossed: the crossing test above, against the additive shape formula it replaced; and the cell-specific terms. A crossed shape ratio is read at the reference level of the other shape predictors rather than across the board, which is the footing the baseline $k$ stands on either way, and a level's own $k$ away from that cell carries the cell's own untabulated term as well as the ratios.

The cell-specific terms $\gamma_{c}$ are reported in a **table of their own**, beside the main-effect shape ratios rather than among them, and an additive fit leaves that table empty because it estimates no such terms. Two reasons for the separation. A product term has no level of any single predictor to file it under, so no canonical level order fits it and it is written in the fit's own row order without a reference row. And the deck recovers a level from the end of a term name, which an interaction row would satisfy by accident, so the main table has to stay free of products. Nothing downstream consumes the interaction table — it is there so that the workbook and `results.json` carry the whole fitted shape model rather than the part that tabulates neatly.

Read a cell-specific term as a **correction, not a shape**: with treatment contrasts, a combination's own shape is
$$k(i,j) = k\left( x_{-X} = \text{reference} \right)\times e^{\gamma_{i}}\times e^{\gamma_{j}}\times e^{\gamma_{ij}},$$
the baseline times both main-effect ratios times the interaction term, and $e^{\gamma_{ij}}$ is 1 by construction wherever either predictor sits at its reference level. That is the same "baseline times ratio" reading §6.6 has always asked of the main effects, one factor longer. What this does *not* give is an interval on $k(i,j)$: that is a linear combination of coefficients and needs the delta method over their joint covariance, which multiplying the three published intervals does not deliver. A per-cell shape table with its own intervals is the natural upgrade if those are wanted.

## 6.8 Per-predictor stratified Cox regression

The pooled model of §6.1 adjusts for every qualifying predictor at once, but it hands them all a single baseline: $h(t \mid x) = h_{0}(t)\exp\left( \beta^{\top}x \right)$ has one $h_{0}$, so proportional hazards is assumed to hold *across* period, intake type, and animal group simultaneously, and every covariate pattern in the data is tied to the same curve shape by a power law (§6.5). §6.7 raises exactly this objection on the parametric side and answers it by freeing the Weibull shape. The nonparametric answer is stratification, and that is what this section adds.

For each predictor $X$ that qualifies for §6.1, and provided at least one *other* predictor also qualifies, mLOS fits one additional Cox model that carries $X$ alone in the linear predictor while every other qualifying predictor moves into a `strata()` term:

$$h\left( t \mid X = j,\ z \right) = h_{0z}(t)\,e^{\beta_{j}},$$

where $z$ indexes the combinations of the other predictors' levels and each combination carries its own entirely unrestricted baseline $h_{0z}$. With all three predictors qualifying, the "period" variant is `surv_obj ~ period + strata(intake_type, animal_group)`, and symmetrically for the other two. A single crossed `strata()` term is what makes each *combination* a baseline rather than each dimension separately: with **OC2**'s four intake types and five animal groups the period variant has 20 baselines, not 9. The optional crossed shape formula of §6.7 is the parametric counterpart of exactly this choice. Estimation, tied-day handling, and the clustered robust variance follow §6.2 and §6.3 unchanged. What changes is that the partial likelihood compares each event only with the rows at risk **in its own stratum**, so nothing about the shape of one combination's discharge process constrains another's. With only one qualifying predictor overall there is nothing to stratify on and the step is skipped entirely. The fits are otherwise unconditional, needing no setting to enable them.

**What the comparison buys.** Under the pooled model and the stratified variant, $X$'s coefficient estimates the same $\beta$ whenever proportional hazards genuinely holds for the *other* predictors, the stratified fit merely giving up some efficiency for the freedom it did not need. When it does not hold, the two models separate, and the stratified estimate is the one that does not depend on the failed assumption. The pair is therefore a usable proportional-hazards screen on the nuisance dimensions, and given that mLOS runs no Schoenfeld-residual test (§9, item 2), it is the closest thing available. It is a screen and not a test: agreement is evidence that the shared baseline was not costing anything, not proof, and the two fits can agree while proportional hazards fails for $X$ itself, which neither of them relaxes.

**What a variant deliberately does not report.** Three consequences of the free baseline, none of them defects:

- Its likelihood-ratio test (and its Wald, score, and robust score tests) compares the fit against the **stratified** null, the baseline-only model with the same strata, on $X$'s degrees of freedom alone. The statistic is not comparable with §6.4's, which tests every predictor jointly against a common baseline on more degrees of freedom. Reading one against the other is a category error, not a finding.
- Its concordance is likewise computed within strata, so it is not comparable with §6.4's either.
- The stratified predictors get no coefficients at all. A variant stratified on period is silent about period by construction: the entire period effect is absorbed into the baselines. That is the point (period is adjusted for without assuming proportional hazards for it), but it means the intake-type and animal-group variants say nothing about the period contrast that motivates much of this tool. Read the pooled model of §6.1, or the period variant, for that.

**Sparsity is the failure mode.** A stratum with no events contributes nothing to the partial likelihood, and a stratum with few events contributes little, so the cost of stratification is paid in the number of cells rather than in bias. The count of baseline strata and the count of those holding at least one event are both reported so this is visible rather than inferred. A fit that fails outright (a degenerate stratum structure, say) is skipped with a console note and a recorded reason, and the run continues, exactly as §6.6 handles a failed Weibull.

**On OC2** the stratification is comfortable and the screen comes back clean: the period variant has 20 baseline strata, the intake-type variant 15 and the animal-group variant 12, every one of them holding events, over 15,521 events in total, and no hazard ratio moves by as much as 3% from its pooled value (the largest shifts are the OTH intake type at 0.738 against 0.760 pooled and the Early-C period at 1.125 against 1.098). On that dataset the single shared baseline of §6.1 is costing essentially nothing.

Worth reading beside §6.7, which can free the same combinations parametrically and reaches the opposite verdict: on an **OC2** run with `weibull_shape_crossing` enabled the crossed *shape* is decisively better than the additive one, while the free *baseline* barely moves a hazard ratio here. The two are not in conflict. Stratification asks whether the pooled baseline biased $X$'s coefficient, and on this dataset it did not. The shape crossing asks whether one shape describes all the cells, and it does not. A model can be a poor description of the nuisance dimensions without that misdescription leaking into the contrast of interest.

**Reported**, per variant: the formula, $n$ and the event count, the number of baseline strata and how many of them hold events, the hazard ratio for each level of $X$ with its 95% confidence interval and Wald p-value in the same form and the same canonical level order as §6.1's table (reference level included as a definitional row with $\text{HR} = 1$), the four global tests of §6.4 evaluated against the stratified null, and the within-strata concordance.

**Where they go.** Into `results.json` at `cox.stratified_variants.<stratifier>` and, copied, at `strata.<stratifier>.cox_stratified`, with the whole per-variant report above. Of that report the workbook takes one line: each stratifier's own hazard ratios, in the Hazard ratios block of its own sheet (§8), beside the pooled hazard ratio they are the check on. The tests and the concordance stay in the JSON, since they are evaluated against a stratified null and answer a different question from §6.1's. The `sim_size_mixture` and `sim_intake_mix_shift` test fixtures pin them against generating truth: both have closed-form true coefficients, and both check that those coefficients survive the move into a stratified baseline, the latter under a composition that shifts across the period boundary.

# 7. Aalen–Johansen Competing-Risks Analysis

## 7.1 Multistate setup

The outcome types are **competing risks**: each stay ends in at most one of the observed states among L, T, N. The event variable is a factor whose first level is the censoring state (`Censor`, assigned to the rows with $\delta = 0$), followed by the outcome states actually observed in the data at hand (sorted). The multistate model `Surv(time_start, time_end, event_factor) ~ 1` is fit on the counting-process rows with a distinct `id` per row, so each row enters as an independent at-risk interval (§3.5), not as part of a per-animal trajectory. (A factor status makes `Surv` construct the multistate object. The older approach of specifying `type = "mstate"` is deprecated in the `survival` package.)

## 7.2 Cumulative incidence functions

For outcome type $k$, the **cumulative incidence function (CIF)** is

$$F_{k}(t) = P\left( T \leq t,\ \text{outcome} = k \right),$$

the probability of having left care by day $t$ **due to cause** $k$ **specifically**. Its Aalen–Johansen estimator is

$$\widehat F_{k}(t) = \sum_{i:\, t_{i} \leq t}^{}\widehat{S}\left( t_{i}^{-} \right)\,\frac{d_{ik}}{n_{i}},$$

where $\widehat{S}\left( t^{-} \right)$ is the all-cause probability of still being in care just before $t_{i}$, $d_{ik}$ the type-$k$ outcomes at $t_{i}$, and $n_{i}$ the risk set. Unlike running “1 − KM” separately per cause, the AJ estimator accounts for the removal of animals by competing causes, and the estimates satisfy

$$\widehat F_{\text{Any}}(t)\mspace{6mu} = \mspace{6mu}\sum_{k}^{}\widehat F_{k}(t)\mspace{6mu} = \mspace{6mu} 1 - \widehat{S}(t),$$

reported as `cif_Any`: the probability of having left care for any classified reason by day $t$.

## 7.3 Daily CIF table and confidence intervals

The fitted state-occupancy probabilities, with their pointwise 95% confidence bounds, are tabulated on the daily grid $d = 0,\ldots,\tau^{\ast}$ by forward fill (0 before the first fitted time). The horizon $\tau^{\ast}$ is the largest fitted time in the standard run, and it is less than or equal to the cap $\tau$, since all intervals are capped there. The User Guide calls the interval $\lbrack 0,\, \tau^{\ast} \rbrack$ the **AJ analysis window**.

A cumulative incidence is filled with $0$ before the first fitted time rather than the $1.0$ of a survival curve, and its grid stops at $\tau^{\ast}$ rather than running to the cap as the KM grids do (§5.5), since holding it flat past the last event would misrepresent unresolved cases as resolved (§9). `cif_Any` is the row sum of the cause-specific CIF columns. Its own pointwise bounds come ready-made from the same fit, since $\mathrm{CIF_{\text{Any}}} = 1 - P(\text{in care})$ means its lower and upper bounds are the complements of the in-care state's upper and lower bounds. The unified CIF plot shows each $\widehat F_{k}$ with a shaded confidence ribbon. The companion CSV carries the CIF, lower, and upper columns for each state and for `cif_Any`. The same unified curves are also drawn as a stacked area (`aj_cif_unified_stack`): the bands sum to the overall CIF, so the top of the stack is `cif_Any` (the probability of having departed by that day) and the space above it the probability of still being in care (the KM survival function). As a stack it carries neither confidence ribbons nor a companion CSV of its own (§8.2).

Where the `probability_mass_width` setting asks for them, two further figures bin the same $\widehat F_{k}$ instead of plotting it: the mass in an interval $(a, b]$ is $\widehat F_{k}(b) - \widehat F_{k}(a)$, read at the interval ends from the grid above, and the bar left over is $1 - \mathrm{CIF_{\text{Any}}}$ at the cap. No estimator, risk set, or interval construction enters that a curve in this section does not already use, and no confidence bounds are offered for a difference of two bounded quantities. The curves stay the reading these summarize.

## 7.4 Conditional remaining-outcome distribution

For an animal **still in care at the end of day** $x$ (the same end-of-day conditioning as §5.8: $T > x$, so an animal that leaves on day $x$ itself is excluded), the probability that it will leave with outcome $k$ after day $x$ (on day $x + 1$ or later) but by the horizon $\tau^{\ast}$ is

$$\mathrm{CondRem_{k}}(x)\mspace{6mu} = \mspace{6mu}\frac{\widehat F_{k}\left( \tau^{\ast} \right) - \widehat F_{k}(x)}{1 - \widehat F_{\text{Any}}(x)},$$

defined only where the denominator (the probability of still being in care at the end of day $x$) exceeds $10^{-9}$, and reported as missing otherwise. The threshold is a floating-point guard: an estimated in-care probability below $10^{-9}$ cannot arise from data (it would take on the order of a billion animals), only from accumulated rounding in the CIF sums, and treating such a denominator as positive would admit spurious trailing days whose values are ratios of rounding error. The threshold also keeps the set of defined days stable across `survival` package versions, which may differ on whether the final $\widehat F_{\text{Any}}$ lands exactly on 1 or a few $10^{-13}$ short of it. **Convention:** the denominator is $1 - \widehat F_{\text{Any}}(x)$, *not* the sum of the numerators, so the values across $k$ may sum to **less than 1**. The shortfall is the probability that the animal’s outcome is still undetermined at $\tau^{\ast}$ (still in care then). These are plotted for the unified fit two ways, as separate lines and as stacked areas (“Outcome Type Stack After Day x”), and, for each stratifier of §7.6, as line plots overlaying the strata. These plots show how the expected outcome mix shifts with time already spent in care.

## 7.5 Normalized restricted mean of a CIF

Every exported CIF column (including `cif_Any`) carries a `restricted_mean` value computed as

$$\mathrm{RM_{k}}\mspace{6mu} = \mspace{6mu}\frac{\sum_{d = 0}^{\tau^{\ast}}\left( \widehat F_{k}\left( \tau^{\ast} \right) - \widehat F_{k}(d) \right)}{\widehat F_{k}\left( \tau^{\ast} \right)}\mspace{6mu} = \mspace{6mu}\sum_{d = 0}^{\tau^{\ast}}\left( 1 - \frac{\widehat F_{k}(d)}{\widehat F_{k}\left( \tau^{\ast} \right)} \right),$$

left blank when $\widehat F_{k}\left( \tau^{\ast} \right) = 0$. Since $\widehat F_{k}(d)/\widehat F_{k}\left( \tau^{\ast} \right)$ is the distribution function of the outcome time *conditional on a type-*$k$ *outcome by* $\tau^{\ast}$, and the outcome time is integer-valued, this is exactly the **mean days to outcome** $k$ **among animals that experience outcome** $k$ **within the horizon**. Applied to `cif_Any`, it is the mean days to any classified outcome occurring by $\tau^{\ast}$.

**Why this differs from the KM restricted mean.** Applied to `cif_Any` this averages over the animals that left, while the KM restricted mean of §5.3 averages over all of them, counting those still in care at the cap at $\tau$ days. The two are related exactly:

$$\text{RMST}(\tau)\; = \;\left( 1 - \widehat{S}(\tau) \right)\mathrm{RM_{\text{Any}}}\; + \;\widehat{S}(\tau)\,\tau,$$

the days of those that left, weighted by the fraction that left, plus the whole horizon for the fraction that did not. Rearranged, $\mathrm{RM_{\text{Any}}} = \left( \text{RMST}(\tau) - \tau\,\widehat{S}(\tau) \right)/\left( 1 - \widehat{S}(\tau) \right)$. The two agree exactly when nothing is still in care at the cap, and separate as that remnant grows. On **OC2**'s animal groups, MED and SMALL reach $\widehat{S}(\tau) = 0$ and report the same number twice, while LARGE, with 0.9% still in care, reports a restricted mean of 30.6 days against 27.7 days to outcome.

The ratio

$$\frac{\widehat{\mathbf F_{k}}(d)}{\widehat{\mathbf F_{k}}\left( \tau^{\ast} \right)}$$

is by definition $1$ at $d = \tau^{\ast}$, so extending the sum past $\tau^{\ast}$ under the same forward-fill convention used for KM curves (§5.5) would only append zero-valued terms, leaving $\mathrm{RM_{k}}$ unaffected by that choice of horizon. The daily $\widehat{\mathbf F_{k}}$ and $\mathrm{CondRem_{k}}$ values are not: extending them flat past $\tau^{\ast}$ would misrepresent the horizon’s true information limit (§9), which is why the tabulation itself stops at $\tau^{\ast}$ rather than $\tau$.

## 7.6 Stratified AJ: by period, intake type, and animal group

The full computation of §§7.1–7.5 is repeated within each level of the available stratifiers: period, `intake_type`, and `animal_group`. As in §5.4, a stratifier with fewer than two observed levels is skipped; a stratum whose rows yield no analyzable outcome is skipped with a note. Each stratum is fit independently on its own rows, with its own truncation and censoring per §3 and its own horizon $\tau^{\ast}$, the largest fitted time among that stratum's rows. The horizons are therefore ragged across strata, which is harmless: a CIF is flat past its last event, so $\widehat F_{k}\left( \tau^{\ast} \right)$, every $\mathrm{CondRem_{k}}$ value, and the normalized restricted mean (§7.5) are unchanged by any larger horizon.

A period stratum consists of that period's animal-period rows, censored at the period boundary, so its curves describe outcome incidence within that calendar window. An `intake_type` or `animal_group` stratum keeps all of an animal's rows, so its curves span the whole study window. Both are correct. They answer different questions.

Gaps in a stratum's risk set (§5.1) are checked per stratum here as well, on the same rows as the stratified KM check, because the consequence for AJ is its own: a stratum accrues no events across a gap, so its CIFs stall and its conditional probabilities understate everything that follows, from the first gap onward.

Per-outcome plots overlay the strata as lines, for both the CIFs and the conditional probabilities, subject to the plot-strata limit (§5.4), with the CSVs still written unless the stratified-output selection settings suppress them (see the User Guide). Per-stratum confidence ribbons on the CIF plots are optional (`show_aj_cif_ci_ribbons`, off by default), and the stratified CIF CSVs include the normalized restricted-mean row per stratum.

## 7.7 Restricted mean days in state: RMST and RMTL

A second restricted-mean decomposition, complementary to §7.5, integrates each state-occupancy probability over the full cap $\tau$ (not the ragged horizon $\tau^{\ast}$):

$$\mathrm{RMTL_{k}}(\tau) = \int_{0}^{\tau}\widehat F_{k}(t)\, dt,\qquad \text{RMST}(\tau) = \int_{0}^{\tau}\widehat{S}(t)\, dt,\qquad \text{RMST}(\tau) + \sum_{k}^{}\mathrm{RMTL_{k}}(\tau) = \tau.$$

$\mathrm{RMTL_{k}}$ is the **restricted mean time lost** of the competing-risks literature: the expected number of days, within the first $\tau$ days after intake, that an animal has already spent departed via outcome $k$. In the shelter world, the "lost" days are days out of care, so for live outcomes the quantity reads more naturally as time *gained* outside the shelter. mLOS keeps the standard name and labels the rows "departed via". The additivity identity holds exactly: every day within the horizon is spent either in care or departed via exactly one outcome type. Consequently, $\tau$ partitions into the RMTLs of the outcome types and the in-care restricted mean (the KM RMST of §5.3, since the AJ in-care probability is the KM curve). Equivalently,

$$\sum_{k}\mathrm{RMTL_{k}}(\tau) = \tau - \text{RMST}(\tau).$$

Estimates and standard errors are ready-made: `summary(aj_fit, rmean =` $\tau$`)[["table"]]` reports each state's restricted mean with its standard error, holding every fitted curve flat from its last event to $\tau$, the same extension convention as the KM restricted mean (§5.3). Unlike the daily CIF tabulation of §7.3, which deliberately stops at $\tau^{\ast}$, the integral is a summary over the horizon rather than a claim about post-$\tau^{\ast}$ incidence, exactly as for the KM RMST. CIs are $\pm 1.96\,\widehat{se}$. The reported `Any` row is the sum of the outcome rows ($= \tau - \text{RMST}$), carrying the in-care row's standard error since $\text{Var}\left( \tau - \int\widehat{S} \right) = \text{Var}\left( \int\widehat{S} \right)$.

One caveat on the standard errors: the multistate table computes them by the infinitesimal-jackknife method, while the KM `se(rmean)` of §5.3 is Greenwood-based, so the in-care row's interval can differ slightly from the KM restricted mean's interval even though the two point estimates are identical. Both are valid, and the difference is small in practice. These per-state means appear on the stratum sheets (§8.4), with the unified fit's in the single column of **By_All**.

# 8. Export Conventions and Derived Summary Metrics

## 8.1 The results JSON

Every run writes `results.json`, the complete record of what it computed. The workbook and the (optional) presentation deck are views onto it: `mlos_render.R` rebuilds the workbook from a saved JSON without repeating the analysis, and the presentation tooling reads the same file. The contract is that the JSON is a superset of the workbook, so a number leaves it only when the tool stops computing it. The plot-companion CSVs, however, are kept separate. The JSON points to them through a manifest rather than storing their content, as described below.

The JSON's top level:

| Block | What it holds |
|:---------------------|:------------------------------------------|
| `schema_version` | the version of the layout below |
| `run` | when the run happened, and over which data and settings files |
| `settings` | the settings that shaped the numbers |
| `data_preparation` | the attrition from CSV rows to analyzed rows |
| `unified` | the whole-sample analysis, including any risk-set gaps (§5.1) |
| `strata` | one block per stratifier, keyed `period`, `intake`, `group`, and `all` |
| `cox`, `weibull`, `aj` | the fits of §§6 and 7, each with a `has_analysis` flag |
| `palette` | the plot colors, so a redrawn figure matches |
| `outputs` | the manifest described below |

Three container shapes carry the numbers, each naming itself in a `type` field. A `matrix` has `rows`, `columns`, and `values`, one array per row across the columns, and is the shape the per-column sheets of §8.4 are built from. A `table` holds its `columns` as named arrays of equal length. A `named_vector` is a single row of labeled values. `schema_version` moves when a field changes meaning or leaves, not when one is added.

What the JSON does not carry are the per-day curve grids of §8.2. The KM curves, Remaining LOS, the census and tenure profiles and the AJ curves stay in the CSVs, and the `outputs` manifest is how the JSON points at them. It holds one entry per emitted plot and CSV, naming the file pair, what the curve is, its day axis, the meaning and units of the value columns, and the summary row above the grid together with the rule that derives it (`column_sum` for a restricted mean, `at_mean_tenure` for the Remaining LOS reading of §8.2). This avoids duplication of large tables and makes results more accessible to the casual user.

## 8.2 Plot-companion CSVs

Every saved PNG has a same-named CSV containing exactly the plotted series on the daily grid. The two unified stack plots are the exception: the cumulative-incidence stack (§7.3) and the conditional-outcome stack (§7.4) have no companion CSVs, since each draws the same numbers as its line counterpart, which carries the CSV instead.

CSVs include a header row summarizing each column where one applies: the exact RMST for the unified KM curve (§5.3), the daily step sum per stratum for stratified KM curves, and the normalized CIF restricted mean (§7.5) for AJ CIF exports, all under the row name `restricted_mean`. Conditional-distribution CSVs include only days where the conditional probabilities are defined.

The Remaining LOS companion CSVs (§5.8) are the exception to the header row being a reduction of the column below it. No reduction of that column means anything, so its header row is instead the curve *read* at a tenure: `remaining_days_at_mean_tenure` (reported in the workbook; §8.4), the stratum's own curve at the day step its mean in-care tenure $\sum_{x}G(x)$ falls in. This is the one aggregate in the manifest whose rule (`at_mean_tenure`) needs a value from outside its own file, the `per_resident_past_days` of the same stratum, which is the in-care tenure CSV's own header row.

The census-by-tenure CSVs (`km_census_by_tenure_by_*.csv`, §5.6) hold the absolute profile $N(d)$ per stratum and carry a single `expected_census` header row (the column sum, $L = \bar{I}\,\widetilde{\text{RMST}}$; the same name the workbook's census-aggregates block uses for this quantity, §8.4), keeping the convention of the other plot CSVs, where that row is likewise the column sum of the plotted series. The remaining aggregates are recoverable from the grid rather than carried: the scale factor $\bar{I}$ is the day-0 row $N(0)$ (since $\widehat{S}(0) = 1$), and the future workload is $\bar{I}\sum_{t}(t + 1)\widehat{S}(t)$. So too are the derived profiles: dividing a day row by $N(0)$ recovers $\widehat{S}(d)$, and dividing by `expected_census` gives $p(d)$.

The in-care tenure CSVs (`km_in_care_tenure_by_*.csv`, §5.7) hold the survival-style profile $G(x)$ per stratum, with a single `per_resident_past_days` header row (the column sum $\sum_{x}G(x)$, which is the mean tenure of the in-care population, §5.6).

$G(x)$, $\text{Remaining LOS}(x)$ and the census profile $N(d)$ are all transformations of a single survival curve, so each also has a unified file (`km_in_care_tenure_unified.csv`, `km_remaining_los_unified.csv`, `km_census_by_tenure_unified.csv`) computed from the unified fit of §5.1, its one column headed `All` to match the **By_All** sheet.

## 8.3 Workbook sheets and conventions

The consolidated workbook (`analysis_results.xlsx`) gathers some of the numerical results, the JSON of §8.1 holding them all. Which sheets it contains, their tab order, and the layout of the **General** cover sheet and the regression sheets (whose statistical content is §6) are documented in the User Guide's numerical-output section. This section states the conventions the per-column sheets share. §8.4 defines the measures they carry and the assumptions behind their confidence intervals. Every risk-set gap (§5.1) found by the unified and stratified KM checks is recorded on the General sheet. No statistic is adjusted for a gap (§9, item 8), so that record is what flags the affected curves as unreliable from the first gap onward.

Each stratifier present with two or more observed levels gets its own sheet. There is one column per level in the canonical level order (chronological for periods, alphabetical for the others, both fixed at data reading) shared by the models, the plots, and the Cox table rows. Period is treated no differently from the rest: a single-period run has nothing to compare, so **By_Period** is omitted and **By_All** carries those numbers. **By_All** is the same construction over a single stratum covering the whole dataset, carrying the full unified analysis (the unified KM medians and restricted means of §5.2–5.3, the census aggregates of §5.6, and the unified AJ of §7.2/§7.5) in the shared layout. When and why each sheet is present is covered in the User Guide's numerical-output section.

Throughout this section and the next (§8.4), a **column** is one level of that sheet's stratifier, and the subscript $j$ indexes it: a period on **By_Period**, exactly as in §4, the whole sample in **By_All**, and an intake type or an animal group in their respective sheets. Every measure of §8.4 is computed the same way in each case, on that column's rows.

To keep the numbers compatible, the measures deliberately keep the By_Period counting conventions rather than re-unifying stays across period boundaries. The counted units are the animal-period rows of §3: a stay spanning several periods contributes one row per period it touches to its stratum's column, exactly as it contributes one row to each of those periods' columns on By_Period. In particular, `total_observations` counts rows rather than stays, `left_truncated` counts rows already in care at their period's start, and `right_censored` includes censoring at period boundaries, not only at the end of observation. The day denominator for the census and daily-rate measures is the whole study window, $\sum_{j}^{}D_{j}$, since a stratum's rows span all periods; on **By_Period** it is the period's own length. This is the `duration_days` the observation block opens with. A cell is NA or blank when the measure is not computable for that level.

Every measure block of §8.4, from the observation block through the confidence-interval section, sits on the same worksheet line across By_Period and every stratum sheet, and each block's shape is a deterministic function of the full dataset (for example, the outcome-events rows list every outcome type observed anywhere in the data, not only in that stratum), so compatible distributions of the same data can be compared column for column. The sheets differ in content in one place only, their top block, which §8.4 describes. The KM block is a within-stratum fit (§5.4). The AJ blocks come from the stratified AJ of §7.6 (By_All reuses the unified AJ of §7.2 as its single stratum). The exception is the Weibull LOS ratios block (only when `parametric_regression: WEIBULL`): it is deliberately placed after every block above precisely because its availability is not a deterministic function of the whole dataset the way the rest are (§8.4 explains why).

## 8.4 The measure blocks, in sheet order

Each block below is described in the order it appears on a sheet, under the conventions of §8.3. A bold lead-in is the sheet's own section title, and a block is present on every per-column sheet unless its own description says otherwise.

### Counts unified across periods

The top block, the only exception to the row conventions of §8.3, counts each stay exactly once. **By_Period** carries no such block, because unifying across periods is unification across the very axis that sheet splits on: a stay spanning three periods appears in three of its columns and has no single one to be counted once in. That slot in By_Period instead holds the period's start date, end date, and duration, the same three rows the General sheet records, which keeps the block the same height so the rest of the blocks still line across the four sheets. Stays are keyed by a per-stay identifier assigned to each cleaned input row before the period decomposition. `animal_id` cannot key a stay, because the same animal can return for a new stay. The three measures are:

- `unified_total_stays`: the number of distinct stays observed in the level.
- `unified_left_truncated`: stays whose intake precedes the start of the first period in which they are observed (in care before observation begins), read from the stay's earliest row.
- `unified_right_censored`: stays with no classified outcome, which can happen through sources 1, 3, and 4 in §3.2 (still in care at the end of observation, capped at $\tau$, or ending in an unclassified exit).

These are exactly the three measures whose row-level versions below them carry period-boundary effects, shown here with those effects removed.

### Observations of days and events

**Observations** — starts with `duration_days`, the column's denominator in days (§8.3). It includes counts of rows, events, left-truncated rows, right-censored rows, capped rows; mean days at risk; total animal-days; and the intake/outcome flow metrics of §4. The `mean_census_inventory` and `daily_mean_total_in_care_days` are not reported here but rather in the census-aggregates block further down.

**Outcome events** — contains `completed_outcomes_total`, the column's classified outcomes summed across types, $E_{j} = \sum_{k}^{}E_{jk}$; followed by $E_{jk}$, the number for each type (L: community live outcomes, T: other live outcomes, N: non-live outcomes).

**Outcome mix among completed outcomes** — the share of each outcome type among stays that ended (with a classified outcome). It uses the $E_{j}$ total to compute fractions from the counts within each level:

$$\mathrm{mix_{jk}} = E_{jk}/E_{j},$$

It is undefined when $E_{j} = 0$.

**Incidence rates per 100 animal-days** — occurrence–exposure rates, overall and per type:

$$\mathrm{rate_{jk}} = \frac{E_{jk}}{A_{j}} \times 100,$$

where $A_{j}$ is the column's total animal-days (§4). The rate gives classified outcomes per 100 days of care delivered, displayed to two decimals. The per-100 scale reads like a daily percentage of the in-care population: a rate of 3.50 means that on an average day, about 3.5% of the animals in care left with a classified outcome.

### KM metrics including census and remaining LOS

**KM Length of Stay** — four numbers from the column's own KM fit (§5): median, 90th percentile, the curve's terminal value $\widehat{S}(\tau)$ as `km_still_in_care_at_cap`, and the restricted mean $\text{RMST}(\tau)$.

*Still in care at the cap, observed and fitted.* `fraction_capped` (observation block) counts the rows whose stay reached the cap, a direct tally. `km_still_in_care_at_cap` is the Kaplan-Meier curve's terminal value $\widehat{S}(\tau)$, the corresponding quantity estimated from the fitted curve, and carries the curve's pointwise 95% bounds (reported in the confidence-interval section below). The layout pairs observed and fitted, exactly as `mean_census_inventory` sits beside `expected_census` in the next block, and neither replaces the other. Both are evaluated at elapsed day $\tau$ rather than $\tau - 1$ where the reported day grids stop: the elapsed clock and the inclusive LOS clock differ by one (§2.7), so $\widehat{S}(\tau) = \Pr(\text{LOS} > \tau)$, which is the event the tally counts. The same day is where the Aalen-Johansen grid ends, so the identity $\widehat{S}(\tau) = 1 - \mathrm{CIF_{\text{Any}}}(\tau)$ holds exactly and the suite asserts it per stratum. The confidence interval is left undefined once the curve reaches zero, as `survfit` leaves it.

**Census aggregates** — the steady-state readings of §5.6 set beside their observed counterparts. `expected_census` is the Little's-law prediction $L = \bar{I} \times \text{RMST}(\tau)$, directly comparable to the observed `mean_census_inventory`. Next, `expected_past_animal_days` ($\bar{I}\sum_d d\,\widehat{S}(d)$) and `expected_future_animal_days` ($\bar{I}\sum_t(t+1)\widehat{S}(t)$) are the elapsed and future workloads, which differ by exactly `expected_census`. Of these, `expected_past_animal_days` is comparable to the observed `daily_mean_total_in_care_days`.

Three days-per-resident figures follow, ordered so the KM-inferred past sits between the two measures it is compared with: `per_resident_in_care_days` (observed, `daily_mean_total_in_care_days` $/$ `mean_census_inventory`), `per_resident_past_days` (`expected_past_animal_days` $/$ `expected_census`), and `per_resident_future_days` (`expected_future_animal_days` $/$ `expected_census`). The last two differ by exactly one day.

Next come quantiles of the same in-care tenure distribution: `per_resident_past_days_restricted_median` and `per_resident_past_days_restricted_p90`, the median and 90th percentile of $p(d) = \widehat{S}(d) / \sum_d \widehat{S}(d)$, read off its complementary CDF:

$$G(x) = \sum_{d>x}\widehat{S}(d) / \sum_d \widehat{S}(d)$$
by the convention the Kaplan-Meier quantiles use on $\widehat{S}$, the smallest tenure at which the curve has fallen to or below the tail probability. Since $p$ is a proper distribution on $0..\tau-1$, $G(\tau-1)=0$ and both quantiles are always reached, unlike the Kaplan-Meier median. The cost is that they are restricted quantiles, truncated at the cap with no NA to signal it, so a binding cap pulls the 90th percentile toward $\tau$. **These two rows are the most cap-sensitive numbers the tool reports**, and the only ones that give no signal when the cap binds. Check `km_still_in_care_at_cap` in the KM block above before quoting either, and see §§3.3 and 5.8 for the magnitudes involved. They summarize the tenure of the standing population, not of an arriving cohort, and on a heavy-tailed stratum the resident median sits well above the Kaplan-Meier median. The observed ratio uses the inventory census as its denominator, not the overnight census of the exact conversion in §4: the inventory denominator matches `expected_census`, so the observed and KM-inferred figures are compared on one convention, and the ratio therefore sits slightly below §4's exact mean days already in care per animal present. A per-resident figure is NA where its census denominator is zero or not computable.

Three readings off the Remaining LOS curve of §5.8 close the block, one per tenure statistic above it and in the same order, the mean first: `remaining_days_at_mean_tenure`, `remaining_days_at_median_tenure`, and `remaining_days_at_p90_tenure`. Each is $\text{Remaining LOS}$ evaluated at that tenure, truncated to the day step it falls in, and each answers a question about one animal: If an animal has already been in care as long as this statistic says, how much longer does it expect? The curve's own grid supports no such statistic of its own, being a function of tenure rather than a distribution over animals (§5.8). **Do not read `remaining_days_at_mean_tenure` as the average remaining stay of the in-care population**: that average is `per_resident_future_days` (equal to `per_resident_past_days` $+\ 1$), four rows above, and the two differ by a Jensen gap that widens with the curvature of the Remaining LOS curve over the bulk of $p$ (§5.8). On **OC1**'s whole sample they are 74.9 days and 53.7 days. Because they are read off the same capped profile, all three carry the cap sensitivity of the quantiles above them.

### AJ metrics by outcome type

**AJ Final CIF** and **AJ restricted mean** — the final CIF value $\widehat F_{k}\left( \tau^{\ast} \right)$, which is the probability of that outcome within the horizon; and the normalized restricted mean of §7.5. These AJ metrics are reported for `Any` (all classified outcomes combined) and for each outcome type.

**AJ restricted mean days by state** — the RMST/RMTL decomposition of §7.7: `aj_rmst_stay` (expected days of stay within the cap, identical to `km_restricted_mean`), `aj_rmtl_Any`, and `aj_rmtl_`$k$ for each outcome type (expected days spent departed via that outcome). The rows are additive: the stay row plus `Any` equals the cap $\tau$.

### Confidence intervals

**95% confidence intervals** — the intervals for the estimates above, cut at the 2.5% and 97.5% points. The intervals sit in one section, rather than as columns beside the estimates, so a sheet keeps one column per level however many levels a stratifying axis has. They are displayed as triplets estimate/lower/upper (replicating the estimate already displayed), so they can be read on their own. The order is that of the sections they summarize:

- the fraction of rows capped and the mean daily intake and outcome rates (observation block)
- the outcome-mix shares and the incidence rates
- the KM median, 90th percentile, and $\text{RMST}(\tau)$ (§5.2–5.3)
- the at-cap survival $\widehat{S}(\tau)$ with the curve's pointwise bounds
- an indicative interval for the expected census (see below for method)
- the final AJ CIF for `Any` and each outcome type (the pointwise bounds of §7.3 evaluated at the horizon)
- the AJ restricted mean days by state (§7.7)

The AJ restricted means carry no interval: each is a ratio of correlated CIF estimates with no ready-made CI, and mLOS does not construct one by resampling (§6.6).

The KM and AJ intervals in this section carry no assumptions beyond those of the estimators themselves (§5, §7, and the independence conditions of §9). The count-based intervals do add distributional assumptions of their own, stated here because the survival machinery does not imply them. The mean daily intake and outcome rates and the incidence rates rely on exact Poisson (Garwood) intervals for the observed count over its exposure (calendar days of the window, or animal-days), which treat occurrences as independent events arriving at a constant rate within the window. Systematic structure inside the window, such as seasonality across a long window or same-day group arrivals (a litter surrendered together, a bulk transfer, a hoarding-case intake), makes the counts overdispersed relative to Poisson and these intervals too narrow.

The fraction capped and the outcome-mix shares use exact binomial (Clopper-Pearson) intervals, which treat the rows (or the completed outcomes) as independent Bernoulli trials. The outcome-mix intervals are conditional on the completed-outcome total $E_{j}$, so the shares of one column are each tested against their own total rather than jointly as a multinomial. As throughout (§9), successive stays of one animal count as independent units, and no multiple-comparison adjustment is applied across the section's cells.

The expected-census interval is **indicative only**, and is the one interval in the section built on an assumption we consider wrong in a known direction. $L = \bar{I} \times \text{RMST}(\tau)$ is a product of two estimated quantities, and its interval combines the Poisson variance of the intake rate with the RMST standard error by a first-order delta method on the log scale,

$$\widehat{\text{Var}}\left( \log L \right) \approx \frac{1}{N_{\text{intakes}}} + \left( \frac{{\widehat{se}}_{\text{RMST}}}{\text{RMST}(\tau)} \right)^{2},\qquad L \times \exp\left( \pm 1.96\sqrt{\widehat{\text{Var}}\left( \log L \right)} \right),$$

under the **assumption that the two factors are independent**. We do not believe they are: the intake rate and the stay-length estimate are likely positively correlated, which would add a positive covariance term and make the true interval wider than the one reported. Treating that dependence properly is an advanced topic left for future versions. Until then, read the reported interval as a lower bound on the real uncertainty. The other census aggregates (past and future animal-days, the per-resident ratios) carry no interval.

### Hazard ratios and LOS ratios

They are placed last, after the confidence-interval section, rather than beside the KM block, because the rows they occupy depend on the `parametric_regression` setting, and may differ from sheet to sheet within one run. Placing them at the bottom preserves the legibility of the earlier sections across stratification sheets. Those sections are each a deterministic function of the whole dataset and its settings file, so their rows line up across sheets for that run. That is not the case for these two. **By_All** has no predictor for any of these ratios to be about, so each of its two slots carries a "not applicable" note instead. And one by-stratifier sheet's shape variant can succeed or decline independently of another's (§6.7).

Two blocks close the sheet, **Hazard ratios** and then **LOS ratios**. Each row is an estimate/CI triplet for this column's own predictor, transposed into this sheet's own column-per-level layout so it reads alongside every section above (no p-value at this compact scale).

| Block | Row | Fit |
|---|---|---|
| Hazard ratios | `cox_pooled_hazard_ratio` | pooled Cox (§6.1) |
| | `cox_stratified_hazard_ratio` | per-predictor stratified Cox (§6.8) |
| | `weibull_pooled_hazard_ratio` | pooled Weibull, its LOS ratio raised to $-k$ (§6.6) |
| LOS ratios | `km_restricted_mean_ratio` | stratified KM (§5.4), unadjusted |
| | `weibull_freed_shape_los_ratio` | per-predictor shape variant (§6.7) |
| | `weibull_pooled_los_ratio` | pooled Weibull (§6.6) |

Two blocks and not one because within each of them the values are rigorously comparable with one another, and the fits that produce comparable values are not the same on the two sides. The shape variant has an implied hazard ratio too, and it is deliberately absent from the first block, because its $k$ is the reference shape cell's and the number therefore describes one covariate combination rather than the data.

The KM ratio leads the second block as the least assuming of the three, and differs from the two below it in two ways rather than one. It adjusts for nothing, each level's own curve against the reference level's, mix and all. And it is a ratio of means **restricted** at $\tau$, where a Weibull LOS ratio is a time ratio on the whole fitted distribution: under a true accelerated-failure-time model those are not the same functional, the restricted ratio being pulled toward 1 as the cap binds. Read them together only when little mass sits at the cap. Its interval is a first-order delta method on the log ratio, built from the two restricted means' own standard errors and treating the two levels as independent. That is a simplifying approximation: one animal can have stays in both levels, and both curves are restricted at the same cap. See §9 for the independence assumptions the estimators carry throughout. It is also the one row here that is unadjusted yet still takes its reference level from the Cox fit, so with no fit there is no denominator and the row is empty.

`pooled` names the fully adjusted fit, and is not the **crude** Weibull of §6.6, which drops the group terms and is reported on the **Weibull_Regression** sheet instead.

The Weibull rows sit at the bottom of both blocks and are written only when `parametric_regression: WEIBULL`. With the parametric fit off they are absent altogether and a footnote under each block says so. A requested fit that declined or failed leaves its rows present and empty.

The full detail of §6.7 — each qualifying predictor's LOS ratio with a p-value, the shape-ratio table for the *other* predictors, the baseline shape, and the likelihood-ratio test — is on a dedicated worksheet instead: **Weibull_By_Period** / **Weibull_By_Intake_Type** / **Weibull_By_Animal_Group**, one per qualifying predictor, placed after the by-stratifier sheets.

# 9. Assumptions and Caveats

1.  **Noninformative censoring/truncation.** All estimators assume the censoring and truncation mechanisms of §3 are independent of residual stay time. Period-boundary censoring and capping satisfy this by construction. Still-in-care censoring and unclassified exits are assumptions.
2.  **Proportional hazards** (Cox only): covariate effects are constant hazard multipliers over the whole LOS range. mLOS does not test this assumption. Violations can occur when, e.g., long-stay animals have a fundamentally different discharge profile. The per-predictor stratified fits of §6.8 are a partial indicator. It compares a predictor's pooled and stratified hazard ratios and asks whether forcing one baseline onto the *other* predictors' combinations moved the estimate; it is a real check on those dimensions but silent about the predictor being estimated, whose own effect neither fit relaxes. Inspecting whether the stratified KM curves cross is a useful screen but not conclusive: each KM stratification is marginal (one covariate at a time, unadjusted for the others in the model), so a crossing can be induced (or masked) by the other covariates. And, even without this heterogeneity, hazards can cross without the survival curves crossing. The assumption may also carry each estimate beyond the data; when at-risk windows among levels have limited overlap, the reported ratio is identified from narrow stretches of the data and extrapolated everywhere else. Formal diagnostics (e.g. Schoenfeld-residual tests) are a possible future addition.
3.  **Main effects only.** The pooled Cox model has no interaction terms. Whether the period effect differs by animal group, for example, is not estimated.
4.  **Independence across stays.** Splitting one stay into animal-period rows is neutral for the KM and AJ estimates and their confidence intervals (§3.5). The assumption that remains is independence across *stays*: each CSV row is a separate intake, successive stays of one animal are not linked analytically, and KM and AJ confidence intervals treat all separate stays as independent. The Cox model always clusters its standard errors on `animal_id`, and the clustering serves two distinct purposes. First, it makes the robust (sandwich) variance handle the period splitting of §3 correctly: unlike the likelihood-based variances of KM, AJ, and the Weibull fit, the sandwich estimator sums score contributions per independent unit, so a stay's split rows must be gathered into one cluster rather than counted as separate units. An auto-generated id (§2.1, one per stay) fully suffices for this, so the splitting correction holds even when the CSV supplies no ids. Second, `animal_id` corrects for correlation among repeat stays of one animal. This works only when the CSV supplies real ids, since auto-generated ids treat each stay as its own animal. The optional Weibull regression (§6.6) also treats stays as independent: its model-based standard errors are exact under within-stay splitting, but carry no clustering correction for repeat animals (a software-availability choice, documented there).
5.  **Restricted horizons.** All means are restricted (§5.3, §5.8, §7.5): they describe the first $\tau$ (or $\tau^{\ast}$) days and are not unrestricted expectations. The cap is the effective upper limit of the KM and AJ analysis, since the data are censored there and no information beyond it is used.
6.  **AJ estimates are purely empirical.** After the last observed event time, the CIFs stop stepping up even if animals remain at risk, so $\mathrm{CondRem_{k}}(x)$ falls to zero for $x$ beyond the last event: a limit of the observed data within the window, not a prediction that no outcomes will occur.
7.  **Discrete day grid.** Exported curves, step-sum restricted means, and the remaining-LOS curves live on the integer-day grid. Because every observation time is an integer number of days, the fitted step functions can jump only at grid points, so the daily tabulation is lossless and step sums equal the corresponding integrals exactly (§5.3, §7.5): the grid is a representation choice, not an approximation.
8.  **Gaps in the risk set.** If no animal is at risk over some range of durations, the curves are not identified past the gap. The tool warns when a gap occurs before $\tau$.
9.  **Sample size.** Results become unstable below roughly 100 outcomes per KM or AJ stratum (level), resulting in wide confidence intervals and underpowered tests. Prefer longer periods and broader (potentially lumped) intake types and animal groups when in doubt.
10. **Steady state (census by tenure only).** The predictions of §5.6 assume a stationary intake rate and a stationary LOS distribution over the fitted window. A period that inherits another regime's population violates this: its observed census reflects the transition, while the KM prediction gives the steady-state census the period is relaxing toward, so the two legitimately disagree (a diagnostic, not an error). Seasonal or trending intake makes $\bar{I}$ an average of unlike rates, blurring the same comparison. The cap does not break the comparison (both sides truncate at $\tau$, §5.6), but both sides then understate the true standing population by the animal-days beyond the cap.

# Appendix: Symbol Table

| Symbol                                         | Meaning                                                                                                                                                                                                                                |
| :--------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| $a$, $u$                                       | intake date; outcome date (blank if still in care)                                                                                                                                                                                     |
| $b_{j}$; $s_{j}$, $e_{j}$, $D_{j}$             | period boundary dates; period $j$ start (inclusive), end (exclusive), duration in days                                                                                                                                                 |
| $t_{\text{start}}$, $t_{\text{end}}$, $\delta$ | interval start (left-truncation time), interval end, classified-event indicator for one animal-period row                                                                                                                              |
| $\tau$; $\tau^{\ast}$                          | restricted stay cap (days); AJ tabulation horizon, the User Guide's AJ analysis window (largest fitted time, $\leq \tau$)                                                                                                              |
| $r$, $A_{j}$, $I_{j}$                          | days at risk of a row; total animal-days in period $j$; total intakes in period $j$. But on a stratum sheet $j$ indexes the column for other predictors as well (§8.3).                                                                                                  |
| $T$                                            | length of stay (days since intake; minimum 1)                                                                                                                                                                                          |
| $d$, $x$                                       | days already in care (elapsed tenure). It is $d$ where the day grid is summed over, $x$ where a curve is read at one tenure (§2.7). In §6, $x$ is instead the Cox covariate vector, and $X$ there is the focal predictor of §§6.7–6.8. |
| $S(t)$; $\widehat{S}(t)$                       | probability still in care at $t$; its KM estimate                                                                                                                                                                                      |
| $\widetilde{\text{RMST}}$                      | daily step-sum restricted mean, equal to $\sum_{d}\widehat{S}(d)$ over the day grid; equals the integral $\text{RMST}(\tau)$ exactly (§5.3)                                                                                            |
| $d_{i}$, $d_{ik}$, $n_{i}$                     | at time $t_{i}$: all-cause classified outcomes, type $k$ outcomes, risk set                                                                                                                                                            |
| $F_{k}(t)$; $\widehat F_{k}(t)$                | cumulative incidence of outcome $k$ by day $t$; AJ estimate                                                                                                                                                                            |
| $\widehat F_{\text{Any}}(t)$                   | $\sum_{k}^{}\widehat F_{k}(t) = 1 - \widehat{S}(t)$                                                                                                                                                                                    |
| $\mathrm{CondRem_{k}}(x)$                      | P(outcome $k$ after day $x$, by $\tau^{\ast}$ $\mid$ in care at end of day $x$)                                                                                                                                                        |
| $\mathrm{RM_{k}}$                              | normalized restricted mean of CIF $k$: mean days to outcome $k$ among animals with that outcome by $\tau^{\ast}$ (§7.5)                                                                                                                |
| $\text{Remaining LOS}(x)$                      | expected remaining LOS within the cap, given in care at end of day $x$                                                                                                                                                                 |
| $\bar{I}$                                      | mean daily intakes of a stratum (§5.6); this is not $\lambda$, which is the Weibull scale below                                                                                                                                        |
| $N(d)$; $L$; $p(d)$                            | expected number in care at tenure $d$; predicted mean census (inventory), $\bar{I}\,\widetilde{\text{RMST}}$; tenure distribution of the in-care population (§5.6)                                                                     |
| $G(x)$                                         | fraction of the steady-state in-care population with tenure exceeding $x$: survival-function form of the in-care tenure distribution (§5.7)                                                                                            |
| $\widehat{S}(\tau)$                            | fitted probability a stay is still in care once it has reached the cap, `km_still_in_care_at_cap`; equals $1 - \mathrm{CIF_{\text{Any}}}(\tau)$                                                                                        |
| $\text{RMST}(\tau)$; $\mathrm{RMTL_{k}}(\tau)$ | restricted mean days of stay; restricted mean days already departed via outcome $k$. Both within cap $\tau$ and related by $\text{RMST} + \sum_{k}\mathrm{RMTL_{k}} = \tau$ (§7.7).                                                    |
| $h(t \mid x)$, $h_{0}(t)$, $S_{0}(t)$, $\beta$ | Cox hazard, baseline hazard, baseline survival, log-hazard-ratio coefficients. But $z$ indexes the baseline strata of §6.8.                                                                                                           |
| $k$, $\lambda$                                 | Weibull shape and scale (§6.5–6.7), where $e^{\beta}$ is the LOS ratio. In §6.7's shape variants, $k$ becomes a log-linear function of the non-focal predictors, $k(x_{-X})$, with coefficients $\gamma$.                              |
| $E_{jk}$, $E_{j}$                              | classified type-$k$ events and total events in period $j$. But on a stratum sheet $j$ indexes the column for other predictors as well (§8.3).                                                                                          |
