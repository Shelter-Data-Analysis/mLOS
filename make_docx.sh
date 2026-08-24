#!/usr/bin/env bash
#
# make_docx.sh - rebuild the Word exports of the guides, but only the stale ones.
#
# Each .docx here is pandoc output whose content comes entirely from the .md
# beside it. Both are tracked, and the .docx is rebuilt for a release rather
# than on every edit, so a stale one is the ordinary state in between. A .docx
# is stale when it is missing, or when its version stamp differs from the one
# in the .md.
#
# The stamp is YYYYMMDD_NNN, in the note under each document's title, bumped by
# hand with each set of edits (documentation_rules.md). It is prose, so pandoc
# copies it into the .docx, which is what makes the comparison possible.
# Modification times cannot do this job now that the .docx are tracked: git
# does not carry them, so a fresh clone gives every file the same time.
#
# A second line goes into the .docx and not into the .md: which commit of the
# .md it was built from, taken from git at build time. The two answer the same
# question from opposite ends. The stamp is what a person can read and compare
# when they hold nothing but the two files, which is the case when a Word copy
# has been emailed to someone; the commit is exact and needs nobody to
# remember anything, but only means something beside the repository. A build
# from a .md with uncommitted changes says so rather than naming a commit that
# does not contain what was built.
#
#   ./make_docx.sh                    rebuild every stale export
#   ./make_docx.sh -n                 say what is stale, build nothing
#   ./make_docx.sh -f                 rebuild all of them, stale or not
#   ./make_docx.sh mlos_user_guide.md rebuild just this one, if stale
#
# Add a new guide by putting its .md name in DOCS below.
#
# pandoc: PANDOC=/path/to/pandoc ./make_docx.sh overrides the search.

set -euo pipefail

# The three reader-facing guides, and only those. Other markdown in the
# repository stays markdown: documentation_rules.md is maintainer-facing, and
# reads perfectly well as plain text, so a Word copy of it has no audience.
#
# This list is the declaration of which documents get a Word export, and
# tests/run_review_tests.py checks that it covers every one of them. Adding a
# guide here fails there until the guide is covered, which is the right
# direction.
DOCS=(
  mlos_math_methods.md
  mlos_user_guide.md
  presentation_guide.md
)

force=0
dry_run=0

usage() {
  sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    -f|--force)   force=1; shift ;;
    -n|--dry-run) dry_run=1; shift ;;
    -h|--help)    usage 0 ;;
    --)           shift; break ;;
    -*)           echo "make_docx.sh: unknown option $1" >&2; usage 1 >&2 ;;
    *)            break ;;
  esac
done

# Any remaining arguments replace the default document list.
if [ $# -gt 0 ]; then
  DOCS=("$@")
fi

# The repo root is where this script lives, so the script works from anywhere.
cd "$(dirname "$0")"

find_pandoc() {
  if [ -n "${PANDOC:-}" ]; then
    echo "$PANDOC"
    return
  fi
  # RStudio bundles a pandoc via Quarto; the tools directory is per architecture.
  local candidate
  for candidate in \
    /Applications/RStudio.app/Contents/Resources/app/quarto/bin/tools/aarch64/pandoc \
    /Applications/RStudio.app/Contents/Resources/app/quarto/bin/tools/x86_64/pandoc \
    /Applications/RStudio.app/Contents/Resources/app/quarto/bin/tools/pandoc
  do
    if [ -x "$candidate" ]; then
      echo "$candidate"
      return
    fi
  done
  command -v pandoc || true
}

# The version stamp, or empty when the file carries none. `|| true` because a
# grep that matches nothing exits 1, which pipefail would turn into an abort.
stamp_of_md() {
  { grep -o 'version [0-9]\{8\}_[0-9]\{3\}' "$1" || true; } | head -1 | awk '{print $2}'
}

# The same stamp as it reads in the document body. Tags are stripped first, so
# a stamp pandoc happened to split across two runs still reads as one string.
stamp_of_docx() {
  { unzip -p "$1" word/document.xml 2>/dev/null | sed 's/<[^>]*>//g' \
      | grep -o 'version [0-9]\{8\}_[0-9]\{3\}' || true; } | head -1 | awk '{print $2}'
}

# What this build was made from, as one sentence for the top of the document.
# `%h` and `%cs` are the abbreviated hash and the commit date; the reader gets
# a date without having to resolve a hash, and show_doc_versions.py reads the
# hash.
build_line() {
  local md="$1" commit date dirty=""

  commit="$(git log -1 --format=%h -- "$md" 2>/dev/null || true)"
  if [ -z "$commit" ]; then
    printf '*Built from `%s`, which git does not track or has no commit for. This Word copy cannot say what it was made from.*\n' "$md"
    return
  fi

  date="$(git log -1 --format=%cs -- "$md" 2>/dev/null || true)"
  if [ -n "$(git status --porcelain -- "$md" 2>/dev/null || true)" ]; then
    dirty=", plus uncommitted changes"
  fi

  printf '*Built from `%s` at commit %s%s (%s). Where that is not the newest commit touching the file, this Word copy is behind it.*\n' \
    "$md" "$commit" "$dirty" "$date"
}

# The build line goes in as its own paragraph, right after the note that
# carries the version stamp: the two belong together, and a reader who opens
# the Word file meets both before the contents list. It is inserted into a
# temporary copy rather than into the .md, because it describes the build and
# not the document.
with_build_line() {
  local md="$1" out="$2"
  awk -v line="$(build_line "$md")" '
    !stamped && /version [0-9]+_[0-9]+/ { stamped = 1 }
    stamped && !done && /^$/ { print ""; print line; print ""; done = 1; next }
    { print }
    END { if (!done) { print ""; print line; print "" } }
  ' "$md" > "$out"
}

pandoc_bin="$(find_pandoc)"
if [ -z "$pandoc_bin" ]; then
  echo "make_docx.sh: no pandoc found. Install one, or set PANDOC=/path/to/pandoc." >&2
  exit 1
fi

built=0
skipped=0
status=0

for md in "${DOCS[@]}"; do
  docx="${md%.md}.docx"

  if [ ! -f "$md" ]; then
    echo "missing source, skipping: $md" >&2
    status=1
    continue
  fi

  md_stamp="$(stamp_of_md "$md")"
  if [ -z "$md_stamp" ] && [ "$force" -eq 0 ]; then
    echo "no version stamp in $md, rebuilding anyway" >&2
  fi

  if [ "$force" -eq 0 ] && [ -f "$docx" ] && [ -n "$md_stamp" ] \
     && [ "$md_stamp" = "$(stamp_of_docx "$docx")" ]; then
    echo "up to date: $docx ($md_stamp)"
    skipped=$((skipped + 1))
    continue
  fi

  if [ "$dry_run" -eq 1 ]; then
    echo "would rebuild: $docx"
    built=$((built + 1))
    continue
  fi

  echo "rebuilding:  $docx"
  # Build beside the target, then move, so an interrupted run leaves the old
  # .docx intact rather than a half written one.
  # The temp name keeps the .docx extension: pandoc picks its writer from the
  # output extension, and anything else silently gives you HTML in a .docx.
  tmp="${md%.md}.tmp.$$.docx"
  # Beside the source, so relative paths in the document still resolve.
  src="${md%.md}.tmp.$$.md"
  with_build_line "$md" "$src"
  if "$pandoc_bin" "$src" -o "$tmp"; then
    mv "$tmp" "$docx"
    built=$((built + 1))
  else
    rm -f "$tmp"
    echo "make_docx.sh: pandoc failed on $md" >&2
    status=1
  fi
  rm -f "$src"
done

echo
if [ "$dry_run" -eq 1 ]; then
  echo "$built stale, $skipped up to date (dry run, nothing written)"
else
  echo "$built rebuilt, $skipped up to date"
fi
exit "$status"
