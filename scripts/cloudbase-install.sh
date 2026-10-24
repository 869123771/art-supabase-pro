#!/usr/bin/env sh
set -eu

# CloudBase's command field accepts one command; keep setup failures fatal here.
git -c http.version=HTTP/1.1 submodule update --init --recursive
npx --yes pnpm@11.28.2 install --frozen-lockfile
