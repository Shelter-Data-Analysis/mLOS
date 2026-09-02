"""Presentation settings: what the deck should contain, as opposed to what the
data says.

YAML, in the same syntax and with the same `.yaml` extension as the analysis
settings the R side reads, so there is one file format to learn rather than
two. Comments matter more here than anywhere else in the package, because most
of these values are enumerations and a reader needs to see the alternatives
without opening the source; that rules out JSON.

Everything has a default, so a missing file is a valid configuration and a
missing key is never an error. What IS an error is a key that is not
recognized, or a value outside its enumeration: a silently ignored typo in a
settings file is a setting the user believes is in force.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass, field, replace
from pathlib import Path

DEFAULT_SETTINGS_FILE = Path("data") / "OC_deck_settings.yaml"

# How the highest and lowest values in a table are marked.
FLAG_STYLES = ("MARK", "COLOR")

# How much of the competing-risks analysis the deck carries. TEASER is one or
# two slides that show what the method can do without presenting its results in
# full, for an audience that has not asked for them.
AJ_COVERAGE = ("FULL", "TEASER", "NONE")

# Emphasis keywords. A list of level names may be given instead of any of
# these, which forces the stratifier salient AND pins those levels into its
# tables whether or not the usual selectors would have chosen them.
EMPHASIS_KEYWORDS = ("AUTO", "ALWAYS", "NEVER")

# Settings-file stratifier names, which are the words a reader knows, mapped to
# the bundle's internal ids.
STRATIFIER_KEYS = {
    "period": "period",
    "intake_type": "intake",
    "animal_group": "group",
}


class SettingsError(ValueError):
    """A settings file that cannot be honoured as written."""


@dataclass(frozen=True)
class Emphasis:
    """What a stratifier is entitled to, before the data gets a say.

    `mode` is AUTO (let salience decide), ALWAYS (force it in), or NEVER (keep
    it out). `levels` is non-empty only when the file named specific levels,
    which implies ALWAYS: naming the levels you want shown and then leaving it
    to chance would not be a coherent request.
    """

    mode: str = "AUTO"
    levels: tuple[str, ...] = ()

    @property
    def forced(self) -> bool:
        return self.mode == "ALWAYS"

    @property
    def suppressed(self) -> bool:
        return self.mode == "NEVER"


@dataclass(frozen=True)
class Settings:
    """Everything the deck reads that does not come from the results bundle."""

    output_directory: Path = Path("reports")
    output_filename: str = "mlos_deck.pptx"
    high_low_flag: str = "MARK"
    aj_coverage: str = "TEASER"
    # Whether the two ratio figures use a log x axis. False is the audience's
    # axis and the default: a ratio is multiplicative, so only a log scale
    # draws 2 and 0.5 as the same size of effect, but it is a thing to be
    # explained from the podium before anything on it can be read. A reader
    # who wants the symmetry asks for it.
    ratio_log_scale: bool = False
    # A one-slide .pptx whose artwork is stamped onto the slides with room for
    # it, and whose theme the whole deck is set in. None builds on pptx's own
    # template, which is what a deck built before this setting existed used.
    template: Path | None = None
    emphasis: dict[str, Emphasis] = field(default_factory=dict)
    # What a stratifier the file says nothing about is entitled to. A field
    # rather than a constant because one dataset changes the answer: see
    # `for_dataset`.
    default_emphasis: Emphasis = Emphasis()

    def emphasis_for(self, stratifier_id: str) -> Emphasis:
        """Emphasis for a bundle stratifier id, or the default for this run."""
        return self.emphasis.get(stratifier_id, self.default_emphasis)

    def for_dataset(self, stratifiers: Sequence[str]) -> "Settings":
        """These settings, read against the stratifiers a run actually has.

        One dataset changes what an unstated stratifier should get. AUTO means
        "let the findings decide", and deciding is a comparison: rank the
        dimensions of the analysis and spend the deck on the ones that separate
        the data. With a single dimension there is nothing to rank it against
        and nothing to lose the comparison to, so the default becomes ALWAYS.
        A dataset with one stratifier and an AUTO default would otherwise leave
        the planner, once it exists, choosing between that stratifier and
        nothing.

        Only the DEFAULT moves. A file that says AUTO said so about this
        stratifier, and a file that says NEVER means it whatever else the
        dataset holds; both are left exactly as written.

        The stratifiers are passed in rather than read from a bundle so that
        this module stays free of the results format, and are the analysis
        dimensions only: the whole sample is not one of them, being the
        baseline every dimension is read against rather than a choice among
        them.
        """
        if len(stratifiers) != 1:
            return self
        return replace(self, default_emphasis=Emphasis(mode="ALWAYS"))

    @property
    def output_path(self) -> Path:
        return self.output_directory / self.output_filename


def _parse_emphasis(key: str, value) -> Emphasis:
    """One emphasis entry: a keyword, or a list of levels to pin."""
    if isinstance(value, str):
        word = value.strip().upper()
        if word not in EMPHASIS_KEYWORDS:
            raise SettingsError(
                f"emphasis.{key}: {value!r} is not one of "
                f"{', '.join(EMPHASIS_KEYWORDS)}, nor a list of level names."
            )
        return Emphasis(mode=word)

    if isinstance(value, (list, tuple)):
        levels = [str(v) for v in value]
        if not levels:
            raise SettingsError(
                f"emphasis.{key}: an empty list says nothing. Use NEVER to "
                f"exclude the stratifier, or AUTO to leave it to the data."
            )
        # Naming levels implies wanting the stratifier shown.
        return Emphasis(mode="ALWAYS", levels=tuple(levels))

    if isinstance(value, bool):
        # YAML turns `true`/`false` into booleans. They are accepted as the
        # obvious synonyms rather than rejected on a technicality, but the
        # keywords are what the template uses, because a boolean cannot spell
        # the third state and AUTO is the common case.
        return Emphasis(mode="ALWAYS" if value else "NEVER")

    raise SettingsError(
        f"emphasis.{key}: expected one of {', '.join(EMPHASIS_KEYWORDS)} or a "
        f"list of level names, got {type(value).__name__}."
    )


def _require_choice(name: str, value, allowed: tuple[str, ...]) -> str:
    word = str(value).strip().upper()
    if word not in allowed:
        raise SettingsError(f"{name}: {value!r} is not one of {', '.join(allowed)}.")
    return word


def _require_flag(name: str, value) -> bool:
    """A yes/no setting, refusing anything that is not one.

    YAML already turns `true`/`false`/`yes`/`no` into booleans, so what arrives
    here as a string is a value the user believed was a flag and was not, which
    is worth an error rather than a silent truthiness test: `ratio_log_scale:
    "off"` is a non-empty string and would switch the axis ON.
    """
    if isinstance(value, bool):
        return value
    raise SettingsError(f"{name}: {value!r} is not true or false.")


def _parse_template(value) -> Path | None:
    """The template path, checked for existence where it is written.

    Refused here rather than at render time, because the render is the end of a
    run that has already read the results and built every slide, and a typo in
    a path is worth hearing about before that.
    """
    if value is None:
        return None
    path = Path(str(value))
    if not path.exists():
        raise SettingsError(f"template: no file at '{path}'.")
    return path


def from_mapping(data: dict) -> Settings:
    """Build settings from an already-parsed mapping.

    Split out from `load` so the validation can be tested without a file, and
    so a caller that has settings from somewhere else can reuse the rules.
    """
    if data is None:
        return Settings()
    if not isinstance(data, dict):
        raise SettingsError("The settings file must be a mapping of keys to values.")

    known = {"output", "tables", "emphasis", "aj_coverage", "figures",
             "template"}
    unknown = sorted(set(data) - known)
    if unknown:
        raise SettingsError(
            f"Unrecognized setting(s): {', '.join(unknown)}. "
            f"Known settings are: {', '.join(sorted(known))}."
        )

    output = data.get("output") or {}
    tables = data.get("tables") or {}
    figures = data.get("figures") or {}
    emphasis_in = data.get("emphasis") or {}

    # Refused by type before the keys are judged, or a scalar here would be
    # iterated as its characters and refused as unrecognized single-letter
    # keys, which points the user at entirely the wrong mistake.
    for name, section in (("output", output), ("tables", tables),
                          ("figures", figures), ("emphasis", emphasis_in)):
        if not isinstance(section, dict):
            raise SettingsError(
                f"{name}: expected a mapping of keys to values, got "
                f"{type(section).__name__}."
            )

    unknown_output = sorted(set(output) - {"directory", "filename"})
    if unknown_output:
        raise SettingsError(f"Unrecognized output setting(s): {', '.join(unknown_output)}.")
    unknown_tables = sorted(set(tables) - {"high_low_flag"})
    if unknown_tables:
        raise SettingsError(f"Unrecognized tables setting(s): {', '.join(unknown_tables)}.")
    unknown_figures = sorted(set(figures) - {"ratio_log_scale"})
    if unknown_figures:
        raise SettingsError(f"Unrecognized figures setting(s): {', '.join(unknown_figures)}.")

    unknown_strata = sorted(set(emphasis_in) - set(STRATIFIER_KEYS))
    if unknown_strata:
        raise SettingsError(
            f"Unrecognized emphasis stratifier(s): {', '.join(unknown_strata)}. "
            f"Known stratifiers are: {', '.join(sorted(STRATIFIER_KEYS))}."
        )

    emphasis = {
        STRATIFIER_KEYS[key]: _parse_emphasis(key, value)
        for key, value in emphasis_in.items()
    }

    defaults = Settings()
    return Settings(
        output_directory=Path(output.get("directory", defaults.output_directory)),
        output_filename=str(output.get("filename", defaults.output_filename)),
        high_low_flag=_require_choice(
            "tables.high_low_flag",
            tables.get("high_low_flag", defaults.high_low_flag), FLAG_STYLES),
        aj_coverage=_require_choice(
            "aj_coverage", data.get("aj_coverage", defaults.aj_coverage), AJ_COVERAGE),
        ratio_log_scale=_require_flag(
            "figures.ratio_log_scale",
            figures.get("ratio_log_scale", defaults.ratio_log_scale)),
        template=_parse_template(data.get("template")),
        emphasis=emphasis,
    )


def load(path: str | Path | None = None) -> Settings:
    """Read a settings file, or return defaults when there is none.

    An explicitly named file that does not exist is an error; the default path
    being absent is not, because running with no settings at all is a supported
    way to work.
    """
    explicit = path is not None
    path = Path(path) if explicit else DEFAULT_SETTINGS_FILE
    if not path.exists():
        if explicit:
            raise SettingsError(f"No settings file at '{path}'.")
        return Settings()

    try:
        import yaml
    except ImportError as exc:  # pragma: no cover - environment dependent
        raise SettingsError(
            "Reading a deck settings file needs PyYAML: pip3 install --user pyyaml. "
            "Without it, delete or rename the settings file to run on defaults."
        ) from exc

    try:
        data = yaml.safe_load(path.read_text())
    except yaml.YAMLError as exc:
        raise SettingsError(f"Could not parse '{path}': {exc}") from exc

    try:
        return from_mapping(data)
    except SettingsError as exc:
        raise SettingsError(f"{path}: {exc}") from exc
