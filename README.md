# s8ga/repo

Package repository serving infrastructure. This repository hosts nothing on
`main` except the collector; the actual package pool lives on the `gh-pages`
branch and is served at <https://s8ga.github.io/repo/>.

- `scripts/collect.sh` + `.github/workflows/collect.yml`: every 10 minutes,
  pull `.deb` assets from watched repositories' GitHub releases (listed in
  `WATCHED` inside the workflow), store them in the `gh-pages` pool, and
  regenerate the APT indexes (`dpkg-scanpackages --multiversion` +
  `apt-ftparchive`).
- Adding a new package: add `owner/repo` to `WATCHED` — the collector handles
  the rest. To serve rpm someday, add a parallel pool directory and a second
  index command (`createrepo_c`); the deb URL never changes.
