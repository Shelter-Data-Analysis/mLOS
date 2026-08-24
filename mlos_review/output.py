"""Where reports go, and what happens to the one that was already there.

Reports land in `reports/` by default, which git ignores like every other
generated directory. Writing a report never overwrites one: the file already at
that path is renamed out of the way first, so the plain name always holds the
most recent deck and older ones stay beside it.

The archive name copies the convention `archive_previous_outputs` uses in
mlos_results.R, `<stem>_<YYYYMMDD>_<NNN>`, with the ordinal counting within the
date and zero-padded to three. Copying it is the point: someone reading
`reports/` and `results/` side by side should not have to work out why two
archive schemes that do the same job look different. As there, the date is the
day the file is archived rather than the day it was written, since that is what
the R version records and matching a convention beats improving half of it.
"""

from __future__ import annotations

import re
from datetime import date
from pathlib import Path


def archive_existing(path: str | Path, today: date | None = None) -> Path | None:
    """Move any file already at `path` aside. Returns where it went, or None.

    Nothing is deleted, here or anywhere else in this package. A report that
    took a run to produce is not ours to discard because a new one has the same
    name.
    """
    path = Path(path)
    if not path.exists():
        return None

    today = today or date.today()
    stem, suffix = path.stem, path.suffix
    prefix = f"{stem}_{today:%Y%m%d}_"

    used = []
    for sibling in path.parent.glob(f"{prefix}*{suffix}"):
        match = re.fullmatch(rf"{re.escape(prefix)}(\d+)", sibling.stem)
        if match:
            used.append(int(match.group(1)))
    # Width 3 is a display choice, not a limit: the format widens past 999
    # rather than truncating, so a counter can never block a run.
    ordinal = max(used) + 1 if used else 1

    destination = path.with_name(f"{prefix}{ordinal:03d}{suffix}")
    path.rename(destination)
    return destination


def prepare_output(path: str | Path, today: date | None = None) -> tuple[Path, Path | None]:
    """Make the report directory and clear the target name.

    Returns the path to write and where the previous file was archived, so a
    caller can say what it did rather than leaving the user to notice.
    """
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    return path, archive_existing(path, today=today)
