#!/usr/bin/env bash
# Initialize GitLab-managed remote state for this project.
# Prerequisites: brew install glab opentofu
# One-time: glab auth login --hostname gitlab.com  (PAT with "api" scope, Maintainer+)
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v glab >/dev/null 2>&1; then
  echo "glab not found. Install: brew install glab" >&2
  exit 1
fi
if ! command -v tofu >/dev/null 2>&1; then
  echo "tofu not found. Install: brew install opentofu" >&2
  exit 1
fi

glab opentofu init default -R gin852423/GIN207 -b tofu "$@"

echo ""
echo "Remote state ready. Use: tofu plan | tofu apply"
