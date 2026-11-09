#!/usr/bin/env bash
# Collect .deb assets from watched repositories' GitHub releases into the flat
# APT pool, then regenerate the Packages/Release indexes.
#
# Usage: collect.sh <path-to-gh-pages-checkout>
# Watched repos are listed in the WATCHED env var (one "owner/repo" per line).
#
# Imports are tracked by release asset id in deb/manifest.json, so a rebuilt
# release (same tag, re-uploaded assets) is picked up again.
set -euo pipefail

POOL="${1:?usage: collect.sh <gh-pages-checkout>}"
cd "$POOL"

mkdir -p deb
[ -f deb/manifest.json ] || echo '{"assets": []}' > deb/manifest.json

NEW_ASSETS=()
while IFS=$'\t' read -r ASSET_ID ASSET_NAME ASSET_URL REPO TAG; do
  if jq -e --argjson id "$ASSET_ID" '.assets | index($id)' deb/manifest.json >/dev/null; then
    continue
  fi
  echo "importing ${REPO}@${TAG}: ${ASSET_NAME}"
  curl -fsSL -o "deb/${ASSET_NAME}" "$ASSET_URL"
  NEW_ASSETS+=("${ASSET_NAME}")
  jq --argjson id "$ASSET_ID" '.assets += [$id]' deb/manifest.json > manifest.tmp
  mv manifest.tmp deb/manifest.json
done < <(
  for R in $WATCHED; do
    gh api "repos/${R}/releases?per_page=30" \
      | jq -r --arg repo "$R" '
          .[]
          | .tag_name as $tag
          | .assets[]
          | select(.name | endswith(".deb"))
          | [(.id | tostring), .name, .browser_download_url, $repo, $tag]
          | @tsv'
  done
)

if [ "${#NEW_ASSETS[@]}" -eq 0 ]; then
  echo "no changes"
  exit 0
fi

( # regenerate APT indexes for the flat pool
  cd deb
  dpkg-scanpackages --multiversion . > Packages
  gzip -k -f Packages
  apt-ftparchive \
    -o APT::FTPArchive::Release::Origin="s8ga-repo" \
    -o APT::FTPArchive::Release::Label="s8ga-repo" \
    -o APT::FTPArchive::Release::Suite="stable" \
    -o APT::FTPArchive::Release::Codename="stable" \
    -o APT::FTPArchive::Release::Architectures="amd64 arm64" \
    release . > Release
)

git add -A
git -c user.name="github-actions[bot]" \
    -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
    commit -m "Collect: ${NEW_ASSETS[*]}"
git push
echo "imported ${#NEW_ASSETS[@]} asset(s)"
