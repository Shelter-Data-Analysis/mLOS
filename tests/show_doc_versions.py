#!/usr/bin/env python3
"""Whether each Word export is built from the Markdown beside it, and whether
the stamp it is built against was kept honest.

Each guide carries a version stamp, `YYYYMMDD_NNN`, in the note under its
title. The stamp is prose, so pandoc copies it into the .docx, and comparing
the two answers the question a tracked Word export raises: is this copy
current, or was it built from an earlier draft?

Each .docx carries a second marker the .md does not: the commit of the source
it was built from, written in by make_docx.sh. The two answer the same
question from opposite ends. The stamp is what a person can compare holding
nothing but the two files, which is the case when a Word copy has been emailed
to someone; the commit is exact and needs nobody to remember anything, but only
means something beside a clone. Either one disagreeing calls the export
behind, and them disagreeing with each other is worth seeing too: a stamp that
matches while the commit does not is an edit that skipped its bump.

    python3 tests/show_doc_versions.py
    python3 tests/show_doc_versions.py --history

Modification times cannot answer it. Git does not carry them, so a fresh clone
gives every file the same checkout time, and the .docx would look current
whatever it holds.

TWO CHECKS, and only one of them can fail.

**Staleness reports.** The Word exports are rebuilt for a release rather than
on every edit, so a stale one is the ordinary state between releases, and a
status that went red on it is a status people learn to ignore. PUBLISHING.md
is where rebuilding them is a step.

**An unbumped edit fails**, and is the exit status. The stamp is bumped by
hand (documentation_rules.md), which on its own would make it a claim nobody
checks: edit a guide without bumping and every stale export downstream reads
as current. So the working tree is compared with HEAD, with the stamp itself
normalized out so that a bump alone does not count as a change. A guide whose
text moved while its stamp stood still is named, before the commit that would
bury it. Wire it to a pre-commit hook if you want it unmissable.

`--history` runs the same comparison over every pair of successive commits
that touched a guide, which says whether the rule has ever been broken.
It reports rather than fails: a violation already in history stays there, and
a check that could only be satisfied by rewriting history is one that gets
switched off.
"""

import re
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

#  The same three make_docx.sh declares. Other markdown in the repository gets
#  no Word export and carries no stamp, so there is nothing here to compare.
DOCS = ["mlos_user_guide.md", "mlos_math_methods.md", "presentation_guide.md"]

STAMP = re.compile(r"version (\d{8}_\d{3})")

#  The second marker, written into the .docx by make_docx.sh and deliberately
#  not into the .md: which commit of the source it was built from. The two
#  answer the same question from opposite ends. The stamp is what a person can
#  compare holding nothing but the two files; the commit is exact and needs
#  nobody to remember anything, but only means something beside a clone.
BUILT = re.compile(r"at commit ([0-9a-f]{7,40})(, plus uncommitted changes)?")


def markdown_stamp(path=None, after_text=None):
    text = after_text if after_text is not None else path.read_text(encoding="utf-8")
    found = STAMP.search(text)
    return found.group(1) if found else None


def docx_text(path):
    """The document body as plain text, tags stripped.

    Pandoc puts each marker in one text run today, but a formatting change
    could split one across several, and a marker broken over two `<w:t>`
    elements would read as absent and report a false mismatch.
    """
    try:
        with zipfile.ZipFile(str(path)) as archive:
            xml = archive.read("word/document.xml").decode("utf-8")
    except (zipfile.BadZipFile, KeyError):
        return None
    return re.sub(r"<[^>]*>", "", xml)


def docx_stamp(path):
    text = docx_text(path)
    if text is None:
        return None
    found = STAMP.search(text)
    return found.group(1) if found else None


def docx_built(path):
    """(commit, dirty) the .docx says it was built from, or (None, False)."""
    text = docx_text(path)
    if text is None:
        return None, False
    found = BUILT.search(text)
    if not found:
        return None, False
    return found.group(1), bool(found.group(2))


def git(*args):
    """Git output, or None when git cannot answer (no repository, no blob)."""
    try:
        done = subprocess.run(("git", "-C", str(ROOT)) + args,
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    except OSError:
        return None
    return done.stdout.decode("utf-8", "replace") if done.returncode == 0 else None


def without_stamp(text):
    """The document with its stamp blanked, so a bump alone is not a change."""
    return STAMP.sub("version (stamp)", text)


def edited_without_bump(before, after):
    """True when the text moved and the stamp did not.

    Both directions matter and neither alone is enough: comparing whole text
    would call a bare bump an edit, and comparing stamps would call an edit
    with no bump nothing at all.
    """
    if before is None or after is None:
        return False
    if without_stamp(before) == without_stamp(after):
        return False
    found_before, found_after = STAMP.search(before), STAMP.search(after)
    if not found_before or not found_after:
        return False          # one side predates stamping; nothing to compare
    return found_before.group(1) == found_after.group(1)


def check_working_tree():
    """Guides edited since HEAD without their stamp being bumped."""
    print("Edited since the last commit:")
    unbumped, seen = [], 0
    for name in DOCS:
        before = git("show", "HEAD:{0}".format(name))
        if before is None:
            print("  --  {0}  not in HEAD".format(name))
            continue
        after = (ROOT / name).read_text(encoding="utf-8")
        if without_stamp(before) == without_stamp(after):
            continue
        seen += 1
        if edited_without_bump(before, after):
            print("  X   {0}  text changed, stamp still {1}".format(
                name, markdown_stamp(after_text=after)))
            unbumped.append(name)
        else:
            print("  ok  {0}  {1} -> {2}".format(
                name, markdown_stamp(after_text=before),
                markdown_stamp(after_text=after)))
    if not seen:
        print("  no guide text changed since HEAD")
    print()
    if unbumped:
        print("Bump the stamp in {0} before committing. Until then the Word "
              "export built from the old stamp reads as current."
              .format(", ".join(unbumped)))
    return unbumped


def check_history():
    """Every pair of successive commits that touched a guide."""
    print("History:")
    total = pairs = 0
    for name in DOCS:
        log = git("log", "--format=%H", "--", name)
        if not log:
            print("  --  {0}  no history".format(name))
            continue
        commits = log.split()          # newest first
        broken, comparable = [], 0
        for newer, older in zip(commits, commits[1:]):
            before = git("show", "{0}:{1}".format(older, name))
            after = git("show", "{0}:{1}".format(newer, name))
            if not (before and after
                    and STAMP.search(before) and STAMP.search(after)):
                continue       # one side predates stamping
            comparable += 1
            if edited_without_bump(before, after):
                broken.append(newer[:7])
        total += len(broken)
        pairs += comparable
        print("  {0} {1}  {2} commits, {3} comparable{4}".format(
            "ok " if not broken else "X  ", name, len(commits), comparable,
            "" if not broken else ", unbumped: " + ", ".join(broken)))
    print()
    # The count of comparable pairs is printed rather than assumed, because
    # almost every commit here predates the stamp and a clean report over
    # nothing would read like a clean report over everything.
    if not pairs:
        print("Nothing to compare yet: every pair of commits has at least one "
              "side from before the stamp existed.")
    elif total:
        print("{0} of {1} comparable pairs changed a guide without bumping "
              "its stamp. They are history; the point is knowing."
              .format(total, pairs))
    else:
        print("All {0} comparable pairs bumped the stamp with the edit."
              .format(pairs))
    return 0


def report_exports():
    """Each Word export against the two markers it carries.

    A mismatch on either is enough to call it behind. They can disagree with
    each other, which is worth seeing rather than hiding: a stamp that matches
    while the commit does not means the source moved and nobody bumped, and
    that is the failure check_working_tree exists to stop.
    """
    width = max(len(name) for name in DOCS)
    stale = []
    compared = 0
    print()
    for name in DOCS:
        md = ROOT / name
        docx = md.with_suffix(".docx")
        want = markdown_stamp(md)
        if want is None:
            print("  X   {0:<{1}}  no version stamp in the Markdown".format(
                name, width))
            stale.append(name)
            continue
        if not docx.exists():
            print("  --  {0:<{1}}  {2}  (no .docx built)".format(
                name, width, want))
            continue

        compared += 1
        reasons = []

        have = docx_stamp(docx)
        if have is None:
            reasons.append("no stamp in the Word file")
        elif have != want:
            reasons.append("stamp {0}, Markdown says {1}".format(have, want))

        built, dirty = docx_built(docx)
        newest = (git("log", "-1", "--format=%h", "--", name) or "").strip()
        if built is None:
            reasons.append("does not say what it was built from")
        elif dirty:
            reasons.append("built from uncommitted changes to {0}".format(built))
        elif newest and built != newest:
            reasons.append("built from {0}, newest is {1}".format(built, newest))

        if reasons:
            print("  X   {0:<{1}}  {2}".format(name, width, "; ".join(reasons)))
            stale.append(name)
        else:
            print("  ok  {0:<{1}}  {2}, built from {3}".format(
                name, width, want, built))
    print()
    if stale:
        print("{0} of the {1} Word exports that exist are behind their "
              "Markdown. That is the ordinary state between releases; rebuild "
              "them when one is cut, or when you are about to send someone a "
              "Word copy.".format(len(stale), compared))
    elif compared:
        print("All {0} Word exports that exist are built from the Markdown "
              "beside them, at its newest commit.".format(compared))
    else:
        print("No Word exports are built.")


def main(argv):
    print()
    if "--history" in argv[1:]:
        return check_history()
    report_exports()
    print()
    unbumped = check_working_tree()
    return 1 if unbumped else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
