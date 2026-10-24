#!/usr/bin/env sh
set -eu

# CloudBase's command field accepts one command; keep setup failures fatal here.
if [ -n "${CLOUDBASE_SOURCE_COMMIT:-}" ]; then
  case "$CLOUDBASE_SOURCE_COMMIT" in
    *[!0-9a-f]*) echo 'Invalid CloudBase source commit' >&2; exit 1 ;;
  esac
  if [ "${#CLOUDBASE_SOURCE_COMMIT}" -ne 40 ]; then
    echo 'Invalid CloudBase source commit length' >&2
    exit 1
  fi
  git fetch --depth=1 origin "$CLOUDBASE_SOURCE_COMMIT"
  git checkout --detach "$CLOUDBASE_SOURCE_COMMIT"
fi

node scripts/cloudbase-modules.mjs install
npx --yes pnpm@11.28.2 install --frozen-lockfile
