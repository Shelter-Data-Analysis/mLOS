"""mLOS review: audience-facing documents built from a results bundle.

EXPERIMENTAL, and possibly permanently so. What the tests establish is that the
documents are correct: every figure on a slide is the number the analysis wrote
for it. What no test can establish, and what is not currently true, is that they
are a good briefing. Two things follow, and both should be said to anyone handed
a deck.

The findings may not be consistently interesting. Selection is by hardcoded
rules against fixed thresholds, so a run in which nothing much happened fills
its slides anyway, and "the largest of several unremarkable differences" reaches
a slide looking exactly like a finding.

Findings that matter are omitted. These documents are a selection and never a
summary. Results a reader would want, including ones plainly visible in the
workbook and the plots, do not appear, and their absence is not evidence of
their unimportance. The analysis output remains the complete record.

Reads `results/results.json` and the figures beside it, and nothing else. No R
internals, no re-computation: every number here has already been computed,
cross-checked, and written out by the analysis.

The package is the display-name vocabulary (`names`), the bundle reader
(`bundle`), the content blocks (`blocks`), a set of example slide rules
(`deck`), and one renderer (`render_pptx`). The planner that would choose among
the rules, and the report and spreadsheet renderers, come later and will share
everything below them.
"""

from mlos_review.names import Name, Vocabulary, capitalize_first

__all__ = ["Name", "Vocabulary", "capitalize_first"]
