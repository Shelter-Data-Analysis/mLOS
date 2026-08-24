"""Reading `results.json` without re-deriving anything from it.

The bundle encodes an R matrix as `{"type": "matrix", "rows": [...],
"columns": [...], "values": [[...]]}`, which is a DataFrame with the axes
swapped: rows are measure names, columns are stratum levels. Every block wants
it the other way round, one row per level, so `matrix` transposes on the way
out and blocks can then say `df["km_median_los"]`.

Nothing here computes a reported number. If a block finds itself deriving a
statistic rather than selecting and arranging one, that is a sign the value
belongs in the R bundle instead; see the completeness contract at the top of
mlos_results.R.
"""

from __future__ import annotations

import json
import sys
from dataclasses import dataclass
from pathlib import Path

import pandas as pd

# The bundle format this package was written against, and the one thing here
# that has to be kept in step with the analysis by hand: it must equal
# MLOS_RESULTS_SCHEMA_VERSION in mlos_results.R, where the numbered history of
# what each version changed is also kept. The test suite compares the two, so
# bumping one without the other fails rather than drifts.
#
# A mismatch warns and carries on, the same way mlos_render.R does. Refusing
# would make an archived run's deck unbuildable for a schema change that may not
# touch anything the deck reads, and the point of the check is that a deck built
# from a bundle this code does not know is never built silently.
EXPECTED_SCHEMA_VERSION = 5

# The whole sample leads, as the baseline everything else is read against. It
# is the one ordering decision made here rather than taken from the bundle,
# because it is a presentation choice and not a property of the analysis: `all`
# is a genuine stratifier in the bundle with a single level, not a special case,
# which is what lets a pooled row come from the same code path as the
# stratified ones. Everything after it follows the bundle's own order.
BASELINE_STRATIFIER = "all"


def _check_schema_version(found, path: Path) -> None:
    """Warn when a bundle was written by a version this package does not know.

    Absence is reported too: every bundle mlos_results.R has ever written
    carries the field, so a file without one is either older than the versioning
    or not an mLOS bundle at all, and both are worth saying out loud before the
    reader starts pulling names out of it.
    """
    if found == EXPECTED_SCHEMA_VERSION:
        return
    seen = "none" if found is None else repr(found)
    print(
        f"*** WARNING: {path} has schema version {seen}; mlos_review expects "
        f"{EXPECTED_SCHEMA_VERSION}. Anything built from it may be wrong. ***",
        file=sys.stderr,
    )


@dataclass(frozen=True)
class Bundle:
    """One results.json, with the accessors blocks are allowed to use."""

    data: dict
    root: Path

    @classmethod
    def load(cls, path: str | Path) -> "Bundle":
        path = Path(path)
        if path.is_dir():
            path = path / "results.json"
        data = json.loads(path.read_text())
        _check_schema_version(data.get("schema_version"), path)
        return cls(data=data, root=path.parent)

    # -- presence -----------------------------------------------------------

    def has(self, *path: str) -> bool:
        """Whether a dotted path exists and is not None.

        This is what a block's `requires` is built from: absence is an ordinary
        answer, so a rule can ask before building rather than catching a
        KeyError and hoping it meant what it seemed to mean.
        """
        node = self.data
        for key in path:
            if not isinstance(node, dict) or key not in node:
                return False
            node = node[key]
        return node is not None

    def value(self, *path: str, default=None):
        """A scalar at a dotted path, or `default` where there is none.

        The read for the bundle's loose facts: settings, run metadata, the
        unified node's scalars. `has` then a chain of `.get({})` says the same
        thing twice and gets longer every time a fact moves one level deeper.
        """
        node = self.data
        for key in path:
            if not isinstance(node, dict) or key not in node:
                return default
            node = node[key]
        return default if node is None else node

    def stratifiers(self) -> list[str]:
        """Stratifier ids actually present, in presentation order.

        The order of the analysis dimensions is READ FROM THE BUNDLE rather
        than listed here. `strata` is a JSON object whose keys arrive in the
        order R wrote them, which is the order of the stratifier registry in
        mlos_common.R, so reordering that registry reaches the deck without a
        matching edit on this side. Two things follow from it that a hardcoded
        list did not give us: a stratifier added to the registry appears in the
        deck instead of being silently invisible here, and a name this package
        has no display label for still renders, because the vocabulary
        tokenizes what it does not recognize and records it for curation.

        Only the baseline is positioned by this package (see
        BASELINE_STRATIFIER); R happens to write it second, after `period`,
        which is an artifact of how the strata list is assembled and not a
        statement about presentation.
        """
        present = list(self.data.get("strata", {}))
        lead = [BASELINE_STRATIFIER] if BASELINE_STRATIFIER in present else []
        return lead + [s for s in present if s != BASELINE_STRATIFIER]

    # -- tables -------------------------------------------------------------

    def matrix(self, *path: str) -> pd.DataFrame:
        """A bundle matrix as a DataFrame indexed by level, columns by measure.

        Raises KeyError if absent; callers that can proceed without it should
        ask `has` first rather than catching.
        """
        node = self.data
        for key in path:
            node = node[key]
        if node.get("type") != "matrix":
            raise TypeError(f"{'.'.join(path)} is not a matrix")
        columns = node["columns"]
        # A single-level stratifier serializes its labels as a bare string.
        if isinstance(columns, str):
            columns = [columns]
        frame = pd.DataFrame(node["values"], index=node["rows"], columns=columns)
        return frame.transpose()

    def table(self, *path: str) -> pd.DataFrame:
        """A bundle `table` node as a DataFrame, one row per record.

        The other serialized shape, and the one the record-like nodes use: the
        period definitions, the attrition steps, the unified stay counts. It
        arrives column-major and needs no transposition, which is the whole
        difference from `matrix`.

        A single-record table may serialize its columns as bare scalars rather
        than one-element lists, the same way a single-level stratifier
        serializes its labels, so scalars are wrapped rather than left to
        become a frame of characters.
        """
        node = self.data
        for key in path:
            node = node[key]
        if node.get("type") != "table":
            raise TypeError(f"{'.'.join(path)} is not a table")
        return pd.DataFrame({
            name: values if isinstance(values, list) else [values]
            for name, values in node["columns"].items()
        })

    def stratum(self, stratifier: str, block: str) -> pd.DataFrame:
        return self.matrix("strata", stratifier, block)

    def levels(self, stratifier: str) -> list[str]:
        labels = self.data["strata"][stratifier]["labels"]
        return [labels] if isinstance(labels, str) else list(labels)

    # -- figures ------------------------------------------------------------

    def figure(self, kind: str, stratifier: str,
               outcome: str | None = None, variant: str = "lines") -> Path | None:
        """The PNG for one manifest entry, or None if the run did not emit it.

        Selection is by (kind, stratifier, outcome, variant) rather than by
        filename, so a rule names what it wants and the manifest resolves it.
        Output flags can switch any figure off, which is why None is a normal
        answer.

        `stratifier` is required and never None: every manifest entry names one,
        a whole-sample file naming "all". It carried no default because the
        pooled entries once had no stratifier at all, and a default of None
        would now silently match nothing instead of failing.

        `variant` separates two drawings of the same numbers: "lines" is the
        default everywhere, and "stack" picks the stacked rendering where one
        exists. Without it the unified CIF and conditional plots each have two
        manifest entries with the same key, and a caller gets whichever comes
        first rather than the one it asked for.
        """
        for entry in self.data.get("outputs", []):
            if (entry.get("kind") == kind
                    and entry.get("stratifier") == stratifier
                    and entry.get("outcome") == outcome
                    and entry.get("variant", "lines") == variant):
                plot = entry.get("plot")
                if not plot:
                    return None
                path = self.root / plot
                return path if path.exists() else None
        return None
