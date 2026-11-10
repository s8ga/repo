#!/usr/bin/env bash
# Rebuild APT indexes over the whole gh-pages pool (no imports).
# Use after manual pool edits, e.g. purging old package versions.
set -euo pipefail

POOL="${1:?usage: reindex.sh <gh-pages-checkout>}"
cd "$POOL/deb"

dpkg-scanpackages --multiversion . > Packages
gzip -k -f Packages
apt-ftparchive \
  -o APT::FTPArchive::Release::Origin="s8ga-repo" \
  -o APT::FTPArchive::Release::Label="s8ga-repo" \
  -o APT::FTPArchive::Release::Suite="stable" \
  -o APT::FTPArchive::Release::Codename="stable" \
  -o APT::FTPArchive::Release::Architectures="amd64 arm64" \
  release . > Release

cd "$POOL"
if git diff --quiet; then
  echo "indexes already up to date"
  exit 0
fi
git add -A
git -c user.name="github-actions[bot]" \
    -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
    commit -m "Reindex APT pool"
git push
