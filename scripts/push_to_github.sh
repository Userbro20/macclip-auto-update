#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ $# -lt 1 ]]; then
  echo "Use it like this: ./scripts/push_to_github.sh \"say what changed\""
  exit 1
fi

MESSAGE="$1"

cd "$ROOT"

GIT_NAME="$(git config user.name || true)"
GIT_EMAIL="$(git config user.email || true)"

if [[ -z "$GIT_NAME" ]]; then
  echo "Git name is missing. Run: git config user.name \"Your Name\""
  exit 1
fi

if [[ -z "$GIT_EMAIL" ]]; then
  echo "Git email is missing. Run: git config user.email \"your@email.com\""
  exit 1
fi

if command -v gh >/dev/null 2>&1; then
  if ! gh auth status >/dev/null 2>&1; then
    echo "GitHub login is missing. Run: gh auth login"
    exit 1
  fi
fi

git add .

if git diff --cached --quiet; then
  echo "Nothing changed. Nothing to push."
  exit 0
fi

git commit -m "$MESSAGE"
git push -u origin main

echo "Done. Your changes are on GitHub."