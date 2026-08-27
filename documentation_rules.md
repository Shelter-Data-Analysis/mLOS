# Documentation rules

Gathered from the August 2026 review of the mLOS guides. Everything here was
settled by making the mistake first, so each rule names the failure it prevents.

This file is the authority for all four markdown documents in the repository.
The HTML comment at the top of `mlos_math_methods.md` keeps the rules that are
about LaTeX rather than prose: which constructs GitHub's markdown pass breaks
before the math renderer sees them, and how to spell a subscript so it survives
both GitHub and pandoc. Read that comment before editing math; read this before
editing anything.

---

## 1. What the document is for

**A reader who never opens the source is the audience.** The test for any
paragraph: does someone who will not read the code need this? If the answer is
no and a docstring already carries it, delete it from the document. The
docstring is usually better, because it sits beside what it describes and
cannot drift as far.

**Move rationale, do not delete it.** When an explanation belongs somewhere,
it belongs in the section that owns the decision. A walkthrough should say what
happens; the reference section says why. Deleting load-bearing reasoning to hit
a word count trades one problem for a worse one.

**Excess text causes more confusion than brevity.** This is the governing
rule. Where the two conflict, cut.

## 2. Register

**Plain statements.** No figurative asides, no editorial flourishes.

**No first person.** Not "we compute", not "our workbook".

**No contractions.**

**No all-caps for emphasis.** Bold or italics only. All-caps belongs to field
values, level names, settings values, and acronyms, and using it for emphasis
too makes those unreadable.

**Never narrate a past state of the code.** The reader has never seen the
earlier design, so "an earlier draft did X" spends their attention on a thing
that does not exist. State what the design is. Where the reasoning matters,
say what the alternative *would* cost, in the present tense:

> Setting headers smaller needs an exemption for headers short enough not to,
> and the exemption is the tell: a table headed `From`, `To`, `Days` **would
> get** three at one size and two at another.

**Say what happens, not what does not.** Describing the method that was not
used, to explain the one that was, doubles the length and halves the clarity.

## 3. Absolutes

**Avoid "the only", "always", "never", "nowhere" in matters of design.** They
are true when written and falsified by a change made somewhere else, and nobody
goes back to the sentence. The package-wide ones are the worst, because the
change that breaks them can be in a different file.

**Keep them where they cannot quietly go bad:**

- rules the test suite enforces ("tables carry numbers, never formatted
  strings");
- mathematical facts ("the only point at which the two routes meet");
- claims already scoped in time ("the only axis that exists **today**").

The last form is the one worth copying: it carries its own expiry.

**This applies to code comments too.** A comment claiming "the only slide that
draws its own figure" goes stale exactly the same way, and is read less often.

## 4. Brevity

**Do not say the same thing twice in a paragraph.** The second sentence that
renames the first is the commonest form.

**Cut the trailing clause that restates the point.** "…which is the comparison
an audience cannot make by turning pages" after a sentence that already said so.

**Cut justifications of the obvious.** Keep the rule.

**Cut unmarked micro-examples inside a rule.** Numbers tied to a named run stay;
illustrative measurements ("0.72in against the 0.92in it needs") go.

**Watch for deliberate parallel construction and keep it.** Two sentences with
the same shape are often a contrast, not repetition: *spread reads down a
column* against *contrast reads across a row*. Cutting one of a pair leaves the
other stranded.

**Fewer clauses per sentence.** A sentence with two subordinate clauses between
the subject and the point will be reread or skipped.

## 5. Terminology

**Mark every quoted number with the run it came from.** "On OC2", never "on
either run" or "on the Orange County data": those quantify over a set that can
grow, and a future run inherits a claim nobody checked.

**One term per concept.** Check a new word against how the document already
says it. Introducing "axis" where the rest says "field" makes a reader wonder
what changed.

**Four reserved words, for the four things that "pooled" used to mean.** Each
already matches an identifier, so prose and code agree without renaming
anything:

| Word | Means | Identifier it matches |
|---|---|---|
| `unified` | the whole sample, no factor split | `km_survival_unified`, `By_All`, `strata.all` |
| `pooled` | the regression carrying every factor at once, fully adjusted | `cox_pooled_hazard_ratio`, `Cox_Pooled` |
| `crude` | the same fit with covariate terms dropped | the crude Weibull keys |
| `all-cause` | every outcome type together, as against per-outcome | — |

Use `marginal` for a curve that is not split by a factor, where `unified` would
overstate it: the crude fit's own shape is marginal over animal group but still
carries period. Do not write "pooled" as a bare adjective for any of these; it
names one fit and nothing else. "Pooled across all periods and all animals",
with the object spelled out, is ordinary English and stays.

**`predictor` is the regression term.** The paper draft uses `factor` for the
same three axes, which is equally correct and reads better in prose aimed at
practitioners. The documents keep `predictor`, because 152 code sites and every
`per-predictor` heading use it, and switching would pull about 110 prose sites
with it. If it is ever switched, switch the bare word in the same pass or the
sentences stop making sense.

**Define an abbreviation at first use, then use it.** Exceptions worth keeping:
a quoted title, and a sentence about the audience's own vocabulary.

**Name the thing when it is ambiguous.** If "workbook" can mean two files, the
document says which, every time it is not the default one.

## 6. Mechanics

**American spellings**, in prose, in code comments, and in user-visible strings
alike.

**Serial comma in lists of three or more.** Not in two-item lists. A regex
sweep will get this wrong: "in a population at steady state, time served and
time still to come" has the same shape and is a clause.

**Few em dashes.** Never in a heading, where GitHub and pandoc disagree about
the anchor and the Word cross-reference dies. Never immediately before a math
expression.

**A blank line above a list, a heading, and a `---` rule.** Pandoc folds a
list or heading into the paragraph above. The rule is worse: directly under
text it is a setext underline, so that line becomes a heading and takes the
anchor the real section wanted, while CommonMark reads a thematic break and
GitHub looks perfect.

**Bump the version stamp with each set of edits.** The three guides carry
`YYYYMMDD_NNN` in the note under the title: today's date, and a counter that
starts at `001` and rises with each further set the same day. It is what says
whether the tracked Word export beside the file was built from what the file
now says, since pandoc copies the stamp into the `.docx` and git does not carry
modification times. Other markdown here gets no export and carries no stamp.

The `.docx` carries a second marker, the commit its source was built from,
which `make_docx.sh` writes in at build time. Nothing to maintain: it is there
so that a Word file beside a clone can be checked exactly, while the stamp is
what answers the same question for someone holding only the two files.

Bump before committing, not after, and run the check first:

```
python3 tests/show_doc_versions.py
```

It exits nonzero when a guide's text has moved since HEAD and its stamp has
not, which is the failure that matters: an unbumped edit makes every stale
Word export downstream read as current. Its report on which exports are
behind is separate and never affects the status, since a stale export is the
ordinary state between releases. `--history` asks the same question of every
pair of commits.

**Renaming a heading breaks every link to it.** Search for the old anchor
first, and regenerate the contents list.

**The contents list maps sections, not paragraphs.** Signpost headings inside a
long section stay out of it.

**Numbers as numbers**, never formatted into prose or into a string.

**Field names in code spans when the sentence is about the field**
(`outcome_type`), and in plain words when it is about the concept ("the outcome
type mapping"). Never bare and underscored outside a code span, which reads as
neither prose nor code.

**Settings headings are not marked "(optional)"**, since optional is the
default. Only "(required)" and "(all-or-none)" are marked.

**List items that run long take sentence case and a full stop**, and so does a
list mixing long and short items. Short or medium items may stay lowercase with
commas or semicolons. A long item should not join two independent clauses with a
semicolon; make them two sentences.

## 7. Editing mechanics

**Do not reflow paragraphs you did not edit.** Rewrapping at a slightly
different width turns a 40-line diff into a 500-line one and buries the real
changes. After any edit pass, restore the original line breaks on every
paragraph whose text is unchanged.

**Diff the source copy against history to find its real base.** A copy taken
before the last commit merges cleanly with a three-way merge and silently
loses work without one.

## 8. Verification

**Check a claim against the artifact, not against another description of it.**
Validating a guide sentence against a code comment proves nothing when the
comment is the thing that went stale. Build the table, read the deck, run the
query.

**Render with two renderers and diff what each made of the file.** GitHub and
pandoc disagree about enough that a break is invisible from whichever side you
are looking at. Compare heading sets and the counts of lists, tables, and code
blocks.

**Keep a checker for quoted numbers.** Every figure the document quotes,
recomputed from a real run and compared. It reports rather than fails, since
these numbers are meant to move when the data does.

**A check that has only ever passed proves nothing.** Break the thing on
purpose and confirm the check fails.
