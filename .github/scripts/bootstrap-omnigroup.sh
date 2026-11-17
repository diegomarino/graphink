#!/bin/bash
# Fetch the pinned OmniGroup gitlink shallowly, then run the reviewed bootstrap
# block from Patches/OmniGroup/README.md verbatim (single source of truth, the
# same extraction Checks/Analyzer/dependencies/check-packaging.py tests).
. "$(dirname "$0")/common.sh"

pin=$(git rev-parse HEAD:OmniGroup)
if [[ "$pin" != "$OMNIGROUP_PIN" ]]; then
  echo "::error::OmniGroup gitlink $pin differs from OMNIGROUP_PIN in .github/ci.env" >&2
  exit 1
fi

# A shallow fetch of exactly the pinned commit; the README block's own
# `git submodule update --init` then finds it checked out and changes nothing.
if [[ ! -e OmniGroup/.git ]]; then
  git submodule update --init --depth 1 OmniGroup
fi

block=$(python3 -c 'import pathlib, sys
text = pathlib.Path("Patches/OmniGroup/README.md").read_text()
print(text.split("bash <<'"'"'BOOTSTRAP'"'"'\n", 1)[1].split("\nBOOTSTRAP", 1)[0])')
bash -c "$block"

echo "OmniGroup at $(git -C OmniGroup rev-parse HEAD) with the reviewed patch series applied"
