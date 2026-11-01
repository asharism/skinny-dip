#!/bin/sh
# Bundles src/editor.js into ../Resources/editor.bundle.js (checked in, so the
# app builds without Node). Run `npm install` once first.
set -eu
cd "$(dirname "$0")"
./node_modules/.bin/esbuild src/editor.js \
  --bundle --minify --format=iife --target=safari26 \
  --legal-comments=none \
  --outfile=../Resources/editor.bundle.js
