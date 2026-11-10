#!/usr/bin/env bash
# Collect .deb assets from watched repositories' GitHub releases into the flat
# APT pool, prune old versions, then regenerate the Packages/Release indexes.
#
# Usage: collect.sh <path-to-gh-pages-checkout>
#   WATCHED       env var, one "owner/repo" per line
#   KEEP_VERSIONS env var, per-package versions to keep (default 3)
#
# Imports are tracked by release asset id in deb/manifest.json:
#   {"assets": {"<id>": "<filename>"}}
# so rebuilt releases re-import (new id) and pruned files drop their
# bookkeeping (reverse lookup by filename).
set -euo pipefail

KEEP_VERSIONS="${KEEP_VERSIONS:-3}"
POOL="${1:?usage: collect.sh <gh-pages-checkout>}"
cd "$POOL"

mkdir -p deb
[ -f deb/manifest.json ] || echo '{"assets": {}}' > deb/manifest.json

NEW_ASSETS=()
while IFS=$'\t' read -r ASSET_ID ASSET_NAME ASSET_URL REPO TAG; do
  if jq -e --arg id "$ASSET_ID" '.assets | has($id)' deb/manifest.json >/dev/null; then
    continue
  fi
  echo "importing ${REPO}@${TAG}: ${ASSET_NAME}"
  curl -fsSL -o "deb/${ASSET_NAME}" "$ASSET_URL"
  NEW_ASSETS+=("${ASSET_NAME}")
  jq --arg id "$ASSET_ID" --arg name "$ASSET_NAME" \
    '.assets[$id] = $name' deb/manifest.json > manifest.tmp
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

# Prune: per package name keep only the newest KEEP_VERSIONS versions.
# Filenames are nfpm-style <name>_<version>_<arch>.deb with numeric
# dot-separated versions, so `sort -V` is adequate ordering.
PRUNED=()
for name in $(ls deb/*.deb | xargs -n1 basename | cut -d_ -f1 | sort -u); do
  keep="$(
    ls "deb/${name}_"*.deb 2>/dev/null \
      | sed "s|.*/||; s|^${name}_||; s|_[^_]*\.deb$||" \
      | sort -uV | tail -n "${KEEP_VERSIONS}"
  )"
  for f in "deb/${name}_"*.deb; do
    ver="$(basename "$f" .deb | sed "s|^${name}_||; s|_[^_]*$||")"
    if ! grep -qx "$ver" <<< "$keep"; then
      echo "pruning old version: $(basename "$f")"
      rm "$f"
      PRUNED+=("$(basename "$f")")
    fi
  done
done

# Drop bookkeeping for pruned files (reverse lookup by filename).
for fname in ${PRUNED[@]+"${PRUNED[@]}"}; do
  id="$(jq -r --arg n "$fname" '.assets | to_entries[] | select(.value == $n) | .key' deb/manifest.json | head -n1)"
  if [ -n "${id:-}" ] && [ "$id" != "null" ]; then
    jq --arg id "$id" 'del(.assets[$id])' deb/manifest.json > manifest.tmp
    mv manifest.tmp deb/manifest.json
  fi
done

if [ "${#NEW_ASSETS[@]}" -eq 0 ] && [ "${#PRUNED[@]}" -eq 0 ]; then
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

SUMMARY="+${NEW_ASSETS[*]:-none} -${PRUNED[*]:-none}"
git add -A
git -c user.name="github-actions[bot]" \
    -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
    commit -m "Collect: ${SUMMARY}"
git push
echo "imported ${#NEW_ASSETS[@]}, pruned ${#PRUNED[@]}"
