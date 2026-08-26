#!/usr/bin/env bash
# Point this clone's hooks at .githooks. Git does not do this on clone, so it
# has to be run once per working copy.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
git config core.hooksPath .githooks
printf 'hooks installed: core.hooksPath = .githooks\n'
