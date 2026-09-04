<!-- Every feature of the outline format, on the slides that use it. Built to be
     read beside presentation_guide.md rather than shown to a room:
     educational.md is the one written to be presented.

     python3 -m mlos_review.variant data/extended_variant_features.md
-->

# Everything an outline can do {divider}
## The format, demonstrated on the slides that use it

- Each slide from here on names the feature it is showing

> A divider takes the TITLE layout, which centres its block and sets the
> heading large. `{divider}` is the only property today.

# A written slide
## The subheading is the slide's lead

- An opening paragraph would set that same line, and setting both is refused
- A bullet at the first level
  - A bullet at the second, indented by anything up to one tab
- Two levels is what the renderer draws

A paragraph under the bullets is the line the slide closes on.

> Which side of the bullets a paragraph sits on says whether it is the lead or
> the close. The close lands at the foot of the body, above a footnote where a
> slide has one.

> Speaker notes wrap in the source and arrive whole, because consecutive lines
> run on. A blank line starts the next paragraph, and so does:
> - a list item like this one
> - or two spaces ending a line

@insert Working with Metrics: Just numbers, no plots   <!-- a trailing comment -->

> A note written under an insert goes in front of the slide's own, marked with
> a star, so a presenter can see which paragraphs came from this outline. On a
> borrowed run it heads the first page only.

@insert Findings

> That one insert borrowed a whole run: the head plus every "continued" page
> the deck paginated it into. A run is addressed through its head because
> which sentence lands on which page is decided by height, so there is no
> telling what to ask for otherwise. It is also why slide titles have to be
> unique, which the test suite enforces on every fixture.

# A slide too long for one page

Enough bullets to overflow, which breaks into a continuation page.

- The renderer paginates a written page the way it paginates the findings
- Each page after the first is titled with ", continued"
- The lead heads the first page only
- Speaker notes go with the first page too
- The closing line goes with the last
- A page break is decided by measured height, not by counting bullets
- So a slide of long bullets breaks earlier than a slide of short ones
- And a branded slide breaks earlier still, the band being shorter
- Nothing is dropped and nothing is split mid-sentence
- A single bullet taller than a page gets a page of its own
- The budget comes from the template when there is one
- Which is why an outline need not know whether it will be branded
- The same routine serves both, so the two cannot disagree
- This is the twelfth bullet
- And this the thirteenth, which is where a plain slide runs out
- So this one lands on the second page

The closing line rides the last page.

@stub A slide nobody has written

- A stub holds a gap open for a slide that does not exist
- Its title is set at the divider's size, so it wants to stay short
- What the missing slide is about goes in the body, like any other slide's

> Every stub left in a deck is warned about at build time, naming the line it
> was written on. A gap that reads as finished work is worse than no gap.

<!--
# A slide switched off

- A block comment is how a slide is set aside while a shorter version is tried
- Nothing between the markers is built, and nothing is lost
-->

# What is deliberately absent
## The outline is a plan, not a program

- No glob or pattern insert: a name that matches nothing fails loudly
- No editing a borrowed slide, only annotating it with notes
- No conditions, variables or includes
- No budget and no ranking, which is the planner this stands in for

> The line worth remembering: an outline may say what a deck contains and in
> what order, and may write plain slides of its own. What it may not do is
> change a slide the deck built.
