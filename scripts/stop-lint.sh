#!/usr/bin/env bash
set -u
REPO="$(git rev-parse --show-toplevel)"
cd "$REPO" || exit 0

# Skip when no Swift files were touched in the working tree.
if ! git status --porcelain -- '*.swift' | grep -q .; then
  exit 0
fi

# Use the existing CI gate. just check = swiftlint --strict + swiftformat --lint.
if ! out=$(just check 2>&1); then
  printf '%s\n' "$out" >&2
  echo "" >&2
  echo "Lint/format violations above. Run 'just format' then fix swiftlint warnings before stopping." >&2
  exit 2
fi
exit 0
