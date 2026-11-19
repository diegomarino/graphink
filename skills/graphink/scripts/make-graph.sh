#!/bin/sh
# Build a Graphink document from a spec and render it, in one call:
#   SPEC.json -> OUT.graphink (the editable document), OUT.png (72 DPI, to look at), OUT.pdf (vector)
#
# Usage: make-graph.sh SPEC.json [OUT] [--force]
#   OUT     the output path without extension (default: SPEC.json without .json)
#   --force replace OUT.graphink, OUT.png and OUT.pdf if they exist
#
# Prints the three paths on success. Exit status: 0 written; 1 a bad spec or a failure (graphink's
# one-line message names the place in the spec); 2 invalid arguments; 3 graphink is not installed and
# 4 not a Mac (find-graphink.sh's message says what to do).

here=$(cd "$(dirname "$0")" && pwd)
spec='' out='' force=''
for arg in "$@"; do
  case "$arg" in
    --force) force=--force ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "make-graph.sh: unexpected option $arg" >&2; exit 2 ;;
    *)
      if [ -z "$spec" ]; then spec=$arg
      elif [ -z "$out" ]; then out=$arg
      else echo "make-graph.sh: unexpected argument $arg" >&2; exit 2
      fi ;;
  esac
done
if [ -z "$spec" ]; then
  echo "Usage: make-graph.sh SPEC.json [OUT] [--force]" >&2
  exit 2
fi
[ -f "$spec" ] || { echo "make-graph.sh: no such spec $spec" >&2; exit 2; }
[ -n "$out" ] || out=${spec%.json}

graphink=$("$here/find-graphink.sh") || exit $?

# Without --force, refuse before writing anything if any output exists.
if [ -z "$force" ]; then
  for ext in graphink png pdf; do
    if [ -e "$out.$ext" ]; then
      echo "make-graph.sh: $out.$ext already exists; pass --force to replace it" >&2
      exit 1
    fi
  done
fi

# graphink's own report goes to stderr, so stdout holds only the three paths.
run() {
  if [ -n "$force" ]; then "$graphink" "$@" --force >&2; else "$graphink" "$@" >&2; fi
}
run create "$spec" -o "$out.graphink" || exit $?
run render "$out.graphink" -o "$out.png" || exit $?
run render "$out.graphink" -o "$out.pdf" || exit $?
echo "$out.graphink"
echo "$out.png"
echo "$out.pdf"
