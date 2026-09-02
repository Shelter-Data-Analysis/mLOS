"""Variant decks: a presentation written as an outline, drawing on the deck.

A variant is mostly plain text slides written by hand, plus a selection of the
slides the deck already builds, reused as they are. It is what a room asks for
that the deck does not: a teaching section, a fifteen-minute version, a talk
that opens with one finding and explains the method behind it.

This is the first piece of the deck plan the Presentation Guide describes, in
its simplest honest form: a plan written out rather than solved against a
budget. The rest of that design, ranking rules and trimming to fit, is not here
and is not approximated.

    python3 -m mlos_review.variant OUTLINE.md [results_dir] [out.pptx]
                                   [--settings=FILE] [--template=FILE]
    python3 -m mlos_review.variant --list [results_dir] [--settings=FILE]

The slides an `@insert` borrows are BUILT again, from the same bundle, not
copied out of the deck file. A slide in a .pptx has its numbers formatted into
strings and its geometry fixed at the page it was laid out for, so a borrowed
one could not be set into a template's band, rendered at another size, or read
by any renderer written later. What the deck emits instead is a sidecar listing
what it holds, and this module checks its own assembly against that: a variant
that no longer matches the deck on disk is refused rather than quietly built.

Slides are addressed by title, which is the stand-in for the rule ids the guide
promises. Titles carry vocabulary labels, so an outline written against one
dataset can fail against another. That failure is loud, and `--list` says what
the titles are.
"""

from __future__ import annotations

import difflib
import json
import re
import sys
import tempfile
from copy import deepcopy
from dataclasses import dataclass, field, replace
from pathlib import Path

from mlos_review.bundle import Bundle
from mlos_review.deck import (MANIFEST_SUFFIX, assemble, figure_directory,
                              manifest_path, resolved_settings)
from mlos_review.figures import FigureSet
from mlos_review.names import Vocabulary
from mlos_review.output import prepare_output
from mlos_review.render_pptx import (Bullet, Slide, bullet_pages, lead_height,
                                     render, template_band, text_budget,
                                     title_lines)
from mlos_review.settings import (Settings, SettingsError,
                                  load as load_settings, parse_template)

# How a continuation page is named, read backwards. `_gathered_section` in
# deck.py writes it; a variant has to recognize it, because a run of findings
# pages is addressed as one thing and there is no telling which sentence lands
# on which page.
CONTINUATION = ", continued"

# The properties a heading may carry, in braces at the end of its line. A word
# outside this set is refused rather than ignored, for the settings file's
# reason: a property silently not in force is a property the writer believes is
# in force.
PROPERTIES = {"divider": ("layout", "TITLE")}

# The directives, each of which yields slides. Nothing modifies the slide it
# sits inside, so a reader never has to track which slide a line belongs to.
DIRECTIVES = ("@insert", "@stub")

# What a stub says on the slide it makes. Loud on purpose: it is a gap held
# open for a slide nobody has written, and a gap that reads as finished work is
# worse than no gap at all. The prefix is why a stub wants a SHORT title: it is
# set at the divider's size, and a sentence there wraps onto the body beneath.
# What the slide is to be about goes in its body, like any other slide's.
STUB_PREFIX = "TO WRITE"
STUB_EMPTY = "Nothing here yet."

# Deepest indent a sub-bullet may carry. With two levels there is nothing to
# count, so any indent is level 1 and this is only a guard: past one tab a
# markdown reader stops seeing a list and starts seeing a code block, and the
# writer meant a third level the renderer does not draw.
MAX_INDENT = 4

BULLET_LINE = re.compile(r"^(\s*)-\s+(.*\S)\s*$")
HEADING_LINE = re.compile(r"^(#{1,2})\s+(.*\S)\s*$")
PROPERTY_TAIL = re.compile(r"^(.*\S)\s*\{([^{}]*)\}$")


class OutlineError(ValueError):
    """An outline that cannot be honoured as written.

    Carries every problem found, not the first. Someone fixing an outline wants
    the list, and a parser that stops at line 3 hides the mistake on line 30.
    """

    def __init__(self, source: str, problems: list[tuple[int, str]]):
        self.source = source
        self.problems = problems
        super().__init__("\n".join(f"{source}:{line}: {text}"
                                   for line, text in problems))


@dataclass
class Page:
    """One entry in an outline, before it becomes slides.

    `kind` is SLIDE (written here), INSERT (borrowed from the deck) or STUB (a
    gap held open). A Page is not a Slide: an INSERT becomes as many slides as
    its run has pages, and a long SLIDE breaks across several.
    """

    kind: str
    title: str
    line: int
    layout: str = "STACKED"
    lead: str = ""
    lead_line: int = 0
    bullets: list[Bullet] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)


def parse_outline(text: str, source: str = "outline") -> list[Page]:
    """Read an outline into pages. Raises OutlineError listing every problem.

    The format, one line at a time:

        # Title            a slide
        # Title {divider}  a slide, set as a section opener
        ## Subheading      that slide's lead
        a paragraph        also that slide's lead
        - a bullet         level 0
          - a bullet       level 1, at any indent up to one tab
        > a note           a paragraph of speaker notes
        @insert <title>    the deck's slide of that title, and its run
        @stub <title>      a gap, held open and warned about

    A `@stub` takes the same body a `#` slide takes, which is where the note
    saying what the missing slide is about belongs; its own title is set at the
    divider's size and wants to stay short.
    """
    pages: list[Page] = []
    problems: list[tuple[int, str]] = []
    current: Page | None = None

    def opened(number: int, what: str) -> bool:
        if current is None:
            problems.append((number, f"{what} before the first heading."))
            return False
        if current.kind == "INSERT":
            problems.append((number, f"{what} after '@insert "
                                     f"{current.title}', which borrows a slide "
                                     f"whole and has nowhere to put it."))
            return False
        return True

    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.rstrip()
        if not line.strip():
            continue

        heading = HEADING_LINE.match(line)
        if heading:
            depth, title = len(heading.group(1)), heading.group(2)
            if depth == 1:
                current = _open_page(title, number, problems)
                pages.append(current)
            elif opened(number, "a subheading"):
                _set_lead(current, title, number, problems)
            continue

        if line.startswith("#"):
            problems.append((number, "only # and ## are headings; a deeper one "
                                     "is reserved."))
            continue

        if line.startswith("@"):
            word, _, rest = line.partition(" ")
            rest = rest.strip()
            if word not in DIRECTIVES:
                problems.append((number, f"unknown directive {word!r}. The "
                                         f"directives are {', '.join(DIRECTIVES)}."))
            elif not rest:
                problems.append((number, f"{word} needs "
                                         + ("a slide title." if word == "@insert"
                                            else "something to say.")))
            else:
                current = Page(kind=word[1:].upper(), title=rest, line=number)
                pages.append(current)
            continue

        if line.startswith(">"):
            if opened(number, "a note"):
                current.notes.append(line[1:].strip())
            continue

        bullet = BULLET_LINE.match(line)
        if bullet:
            indent, body = bullet.group(1), bullet.group(2)
            if not opened(number, "a bullet"):
                continue
            if len(indent.expandtabs(MAX_INDENT)) > MAX_INDENT:
                problems.append((number, "bullets go two levels deep at most."))
                continue
            current.bullets.append(Bullet(body, 1 if indent else 0))
            continue

        if not opened(number, "text"):
            continue
        if current.bullets:
            problems.append((number, "a paragraph after a bullet. Start it with "
                                     "'- ' to make it a bullet, or '> ' to make "
                                     "it a speaker note."))
        else:
            _set_lead(current, line.strip(), number, problems)

    for page in pages:
        if page.kind == "SLIDE" and not page.bullets and not page.lead:
            problems.append((page.line, f"{page.title!r} has no content."))
    if problems:
        raise OutlineError(source, problems)
    return pages


def _open_page(title: str, number: int,
               problems: list[tuple[int, str]]) -> Page:
    """A heading, with any properties in braces taken off its end."""
    page = Page(kind="SLIDE", title=title, line=number)
    tail = PROPERTY_TAIL.match(title)
    if not tail:
        return page
    page.title = tail.group(1)
    for word in (w.strip() for w in tail.group(2).split(",")):
        if word in PROPERTIES:
            setattr(page, *PROPERTIES[word])
        elif word:
            problems.append((number, f"unknown property {word!r}. The "
                                     f"properties are "
                                     f"{', '.join(sorted(PROPERTIES))}."))
    return page


def _set_lead(page: Page, text: str, number: int,
              problems: list[tuple[int, str]]) -> None:
    """The slide's standing line, from a subheading or an opening paragraph.

    One of them, not both and not two paragraphs. `Slide.lead` is a single
    string that the renderer sizes and takes out of the body; running two of
    them together makes a slide that overflows rather than one that says more.
    """
    if page.lead:
        problems.append((number, f"a second lead for {page.title!r}, which "
                                 f"already has one from line {page.lead_line}."))
        return
    page.lead, page.lead_line = text, number


def runs(slides: list[Slide]) -> dict[str, list[Slide]]:
    """The deck's slides, grouped into the runs an outline can address.

    A slide titled `<head>, continued` extends the run its head opened; every
    other slide opens a run of its own. That is `_gathered_section`'s naming
    rule read backwards, and it is why a findings section is borrowed whole:
    the sentences are paginated by height, so which one lands on which page is
    not something an outline can know.

    A title used twice is refused. The deck's own test holds titles unique, so
    reaching this means a rule broke that, and inserting the first match would
    silently borrow the wrong slide.
    """
    grouped: dict[str, list[Slide]] = {}
    order: list[str] = []
    head = ""
    for slide in slides:
        if head and slide.title == f"{head}{CONTINUATION}":
            grouped[head].append(slide)
            continue
        head = slide.title
        if head in grouped:
            raise ValueError(
                f"This deck has two slides titled {head!r}, so an outline "
                f"cannot name either one. Slide titles are the only way a "
                f"variant addresses a slide.")
        grouped[head] = [slide]
        order.append(head)
    return {head: grouped[head] for head in order}


def compose(pages: list[Page], base: list[Slide], source: str = "outline",
            budget: int | None = None) -> list[Slide]:
    """Turn parsed pages into slides, borrowing from `base` where asked.

    Borrowed slides are copied, not referenced. `Slide` is mutable and several
    rules edit one after building it, so a variant holding the deck's own
    objects could change the deck's.
    """
    available = runs(base)
    problems: list[tuple[int, str]] = []
    slides: list[Slide] = []

    for page in pages:
        if page.kind == "INSERT":
            run = available.get(page.title)
            if run is None:
                problems.append((page.line, _no_such_slide(page.title, available)))
                continue
            slides.extend(deepcopy(slide) for slide in run)
        elif page.kind == "STUB":
            slides.append(Slide(
                title=f"{STUB_PREFIX}: {page.title}",
                lead=page.lead,
                bullets=list(page.bullets) or ([] if page.lead
                                               else [Bullet(STUB_EMPTY)]),
                notes=page.notes or ["A gap held open by the outline. The "
                                     "slide that belongs here has not been "
                                     "written."],
                layout="TITLE"))
        else:
            slides.extend(_written_slides(page, budget))

    if problems:
        raise OutlineError(source, problems)
    return slides


def _no_such_slide(title: str, available: dict[str, list[Slide]]) -> str:
    # Naming a continuation page is the likely slip, and the generic answer
    # would send someone looking for a title that is right there in the deck.
    head = title[:-len(CONTINUATION)] if title.endswith(CONTINUATION) else ""
    if head in available:
        return (f"{title!r} is a continuation page, which is not addressed on "
                f"its own. Insert {head!r} and its pages come with it.")
    near = difflib.get_close_matches(title, list(available), n=2, cutoff=0.6)
    suggestion = (" Did you mean " + " or ".join(repr(t) for t in near) + "?"
                  if near else "")
    return (f"no slide titled {title!r} in this deck.{suggestion} "
            f"Run --list for the titles.")


def _written_slides(page: Page, budget: int | None) -> list[Slide]:
    """One written page, broken across slides if it does not fit on one.

    Paginated by the routine the closing sections use, and named the way they
    name their pages, so a hand-written list too long for a slide behaves like
    a generated one instead of running off the bottom.
    """
    pages = bullet_pages(page.bullets, lead_height(page.lead) if page.lead else 0,
                         budget) or [[]]
    return [Slide(title=page.title if index == 0
                  else f"{page.title}{CONTINUATION}",
                  bullets=list(bullets),
                  lead=page.lead if index == 0 else "",
                  notes=list(page.notes) if index == 0 else [],
                  layout=page.layout)
            for index, bullets in enumerate(pages)]


def read_manifest(deck_path: str | Path) -> list[dict] | None:
    """The deck's sidecar, or None when there is no deck to correspond to."""
    path = manifest_path(deck_path)
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError:
        return None


def correspondence(slides: list[Slide], manifest: list[dict]) -> list[str]:
    """How this assembly differs from the deck the sidecar describes.

    Empty when they agree. Compares the run HEADS in order, which is exactly
    what an outline can address, rather than a fingerprint of the settings and
    the bundle: a check on the inputs can pass while the output moved, and it
    is the output an `@insert` reaches into.

    Heads rather than every page, because how many pages a run takes is decided
    by height at render time. A variant built against a template breaks the
    findings over a shorter band than an unbranded deck did, and gets more
    pages of the same run; that is the pagination working, not the deck having
    changed underneath.
    """
    built = list(runs(slides))
    recorded = list(dict.fromkeys(entry["head"] for entry in manifest))
    if built == recorded:
        return []
    gone = [t for t in recorded if t not in built]
    fresh = [t for t in built if t not in recorded]
    notes = []
    if gone:
        notes.append("no longer built: " + ", ".join(repr(t) for t in gone))
    if fresh:
        notes.append("newly built: " + ", ".join(repr(t) for t in fresh))
    if not notes:
        notes.append(f"the same {len(built)} slides, in a different order")
    return notes


def build_variant(results: str | Path | Bundle, outline_path: str | Path,
                  out_path: str | Path | None = None,
                  settings: Settings | None = None,
                  check: bool = True) -> tuple[Path, Path | None, list[str]]:
    """Write a variant deck. Returns where it went, what it displaced, and any
    warnings worth printing.

    No workbook. `workbook.sheets` reads the bundle rather than the slides, so
    a variant's workbook would be the deck's under another name.
    """
    outline_path = Path(outline_path)
    pages = parse_outline(outline_path.read_text(), outline_path.name)

    bundle = results if isinstance(results, Bundle) else Bundle.load(results)
    settings = resolved_settings(bundle, settings)
    vocab = Vocabulary(bundle.data)
    if out_path is None:
        out_path = settings.output_directory / (outline_path.stem + ".pptx")
    out_path = Path(out_path)

    figures = FigureSet(directory=figure_directory(out_path))
    base = assemble(bundle, vocab, figures, settings)

    warnings = []
    manifest = read_manifest(settings.output_path)
    if manifest is None:
        warnings.append(
            f"no {settings.output_path.stem}{MANIFEST_SUFFIX} beside "
            f"{settings.output_path}, so nothing says what the deck holds. "
            f"Build the deck to check this variant against it.")
    elif check:
        differences = correspondence(base, manifest)
        if differences:
            raise SettingsError(
                f"this run does not build the deck at {settings.output_path}: "
                + "; ".join(differences)
                + ". Rebuild the deck, or pass --no-check to build anyway.")

    slides = compose(pages, base, outline_path.name,
                     text_budget(template_band(settings.template)))
    warnings.extend(
        f"{outline_path.name}:{page.line}: stub slide {page.title!r} left in "
        f"the deck." for page in pages if page.kind == "STUB")
    # A title the outline wrote that will not fit on its line. Said here rather
    # than left to be discovered in the deck, because a title box grows down
    # over the body instead of shrinking its type, and the writer is the only
    # one who can shorten the words.
    written = {page.title for page in pages if page.kind != "INSERT"}
    warnings.extend(
        f"{slide.title!r} is too long for its line and wraps over the body. "
        f"Shorten it; what the slide is about can go in its bullets."
        for slide in slides
        if slide.title in written or slide.title.startswith(f"{STUB_PREFIX}: ")
        if title_lines(slide.title, slide.layout) > 1)

    figures.write_manifest()
    out_path, archived = prepare_output(out_path)
    render(slides, out_path, vocab, flag_style=settings.high_low_flag,
           template=settings.template)
    return out_path, archived, warnings


def addressable(slides: list[Slide]) -> list[tuple[str, int]]:
    """Every title an outline may insert, with how many pages it brings."""
    return [(head, len(run)) for head, run in runs(slides).items()]


def list_titles(results: str | Path, settings: Settings) -> list[str]:
    """The lines `--list` prints.

    Read off the sidecar when there is one, which costs no assembly at all.
    Otherwise assembled into a directory that is thrown away, because listing
    what a deck holds should not leave figures in the reports directory.
    """
    manifest = read_manifest(settings.output_path)
    if manifest is not None:
        counts: dict[str, int] = {}
        for entry in manifest:
            counts[entry["head"]] = counts.get(entry["head"], 0) + 1
        pairs = list(counts.items())
    else:
        bundle = Bundle.load(results)
        settings = resolved_settings(bundle, settings)
        # Thrown away afterwards: assembling draws the ratio figures, and
        # asking what a deck holds should not leave PNGs in the reports
        # directory.
        with tempfile.TemporaryDirectory() as scratch:
            pairs = addressable(assemble(bundle, Vocabulary(bundle.data),
                                         FigureSet(directory=Path(scratch)),
                                         settings))
    return [head + (f"    (+{pages - 1} continuation "
                    f"page{'s' if pages > 2 else ''})" if pages > 1 else "")
            for head, pages in pairs]


VALUED_FLAGS = ("--settings", "--template")
SWITCHES = ("--list", "--no-check")
USAGE = ("Usage: python3 -m mlos_review.variant OUTLINE.md "
         "[results_dir] [out.pptx] [--settings=FILE] [--template=FILE]")


def main(argv: list[str]) -> int:
    args = [a for a in argv[1:] if not a.startswith("--")]
    flags = {a.split("=")[0]: a.partition("=")[2]
             for a in argv[1:] if a.startswith("--")}

    # deck.main's rule, extended to cover a flag that takes no value: a
    # silently ignored flag is a flag the user believes is in force, and
    # `--list=yes` is as much a mistake as `--settings` with nothing after it.
    unknown = sorted(set(flags) - set(VALUED_FLAGS) - set(SWITCHES))
    if unknown:
        print(f"error: unrecognized flag(s): {', '.join(unknown)}. The flags "
              f"are {', '.join(f'{f}=FILE' for f in VALUED_FLAGS)}, "
              f"{', '.join(SWITCHES)}.", file=sys.stderr)
        return 1
    for flag in VALUED_FLAGS:
        if flag in flags and not flags[flag]:
            print(f"error: {flag} needs a value, as {flag}=FILE.",
                  file=sys.stderr)
            return 1
    for flag in SWITCHES:
        if flags.get(flag):
            print(f"error: {flag} takes no value.", file=sys.stderr)
            return 1

    try:
        settings = load_settings(flags.get("--settings") or None)
        if "--template" in flags:
            settings = replace(settings,
                               template=parse_template(flags["--template"]))
    except SettingsError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    if "--list" in flags:
        for line in list_titles(args[0] if args else "results", settings):
            print(line)
        return 0

    if not args:
        print(f"error: name an outline file. {USAGE}", file=sys.stderr)
        return 1
    outline_path = Path(args[0])
    if not outline_path.exists():
        print(f"error: no outline file at '{outline_path}'.", file=sys.stderr)
        return 1

    results = args[1] if len(args) > 1 else "results"
    out = args[2] if len(args) > 2 else None

    try:
        path, archived, warnings = build_variant(
            results, outline_path, out, settings,
            check="--no-check" not in flags)
    except OutlineError as exc:
        for line, text in exc.problems:
            print(f"error: {exc.source}:{line}: {text}", file=sys.stderr)
        return 1
    except (SettingsError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    for warning in warnings:
        print(f"warning: {warning}")
    if archived is not None:
        print(f"archived previous deck to {archived}")
    print(f"wrote {path}")
    manifest = figure_directory(path) / "manifest.json"
    if manifest.exists():
        print(f"wrote {manifest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
