#!/bin/bash
# Usage: scripts/release.sh [--tag]
# The local equivalent of the "Release" workflow. No version argument, ever: the next version
# comes from the latest vYYYY.M.n tag and today's date in Europe/Madrid
# (scripts/release/version.py). Without --tag it only computes and previews; with --tag it
# creates the annotated tag on main's HEAD and prints the push command. Pushing the tag starts
# the tag pipeline (.github/workflows/release.yml): build, Graphink.dmg, approval, publish.
# Needs git, python3 and git-cliff (or release-notes/<version>.md for the notes).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

create_tag=0
case "${1:-}" in
  '') ;;
  --tag) create_tag=1 ;;
  *) echo "usage: scripts/release.sh [--tag]" >&2; exit 2 ;;
esac

git fetch --quiet --tags origin 2>/dev/null || echo "warning: could not fetch tags from origin; using local tags" >&2
latest=$(python3 scripts/release/version.py latest-tag)
version=$(python3 scripts/release/version.py next)
tag="v$version"
echo "Latest release tag: ${latest:-none}"
echo "Next release:       $tag (today in Europe/Madrid)"

status=0
python3 scripts/release/notes.py check-release --version "$version" || status=$?
if [[ $status == 3 ]]; then
  echo "Nothing to release: no feat/fix/perf commits since ${latest:-the start} and no release-notes/$version.md."
  exit 0
elif [[ $status != 0 ]]; then
  exit "$status"
fi
echo
echo "----- Release notes for $version -----"
python3 scripts/release/notes.py version-notes --version "$version"
echo "--------------------------------------"

if [[ $create_tag == 0 ]]; then
  echo
  echo "Preview only. To release from main: scripts/release.sh --tag"
  exit 0
fi
[[ $(git rev-parse --abbrev-ref HEAD) == main ]] || { echo "error: check out main first" >&2; exit 1; }
[[ -z $(git status --porcelain --untracked-files=no) ]] || { echo "error: commit or discard local changes first" >&2; exit 1; }
if git rev-parse --verify --quiet "refs/remotes/origin/main" > /dev/null && [[ $(git rev-parse HEAD) != $(git rev-parse origin/main) ]]; then
  echo "error: main is not at origin/main; pull or push first so the tag marks a published commit" >&2; exit 1
fi
git tag --annotate "$tag" --message "Graphink $version"
echo
echo "Created $tag on $(git rev-parse --short HEAD). Next:"
echo "  git push origin $tag"
echo "That starts the Release build workflow (build, Graphink.dmg, approval in the 'release'"
echo "environment, then publish as the latest GitHub Release). To undo before pushing:"
echo "  git tag --delete $tag"
