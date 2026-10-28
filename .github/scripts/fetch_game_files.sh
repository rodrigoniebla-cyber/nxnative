#!/bin/bash
# The game files for build-ipa.yml and build-mush8.yml: usage fetch_game_files.sh <folder> <release tag> [links...]
# Downloads the .nsp / .xci / .nsz / .xcz assets (and their numbered parts) of a release of this repository, and each link: a direct download link, or a Google Drive share link of a file
# or a folder (gdown, which gets past Drive's large-file page). Then brings a Drive folder's files up into <folder> and joins numbered parts (name.nsp.000 / .001, …) into the file
# they were split from. Needs GH_TOKEN for the release, and python for gdown.
set -eo pipefail
dir=$1 tag=$2; shift 2
mkdir -p "$dir"
cd "$dir"
if [ -n "$tag" ]; then
  gh release download "$tag" --repo "$GITHUB_REPOSITORY" \
    --pattern '*.nsp' --pattern '*.xci' --pattern '*.nsz' --pattern '*.xcz' \
    --pattern '*.nsp.[0-9]*' --pattern '*.xci.[0-9]*' --pattern '*.nsz.[0-9]*' --pattern '*.xcz.[0-9]*' \
    || { [ $# -gt 0 ] || exit 1; echo "::warning::no game files from release '$tag'; using the links only"; }
fi
for u in "$@"; do
  echo "downloading ${u%%\?*}"
  case "$u" in
    *drive.google.com/*|*drive.usercontent.google.com/*|*docs.google.com/*)
      command -v gdown >/dev/null || python -m pip install -q gdown==5.2.0
      case "$u" in */folders/*) kind=--folder ;; *) kind=--fuzzy ;; esac
      ok=
      for attempt in 1 2 3; do   # --continue: a retry resumes the file and skips a folder's finished ones
        if gdown "$kind" --continue --quiet "$u"; then ok=1; break; fi
        sleep 15
      done
      if [ -z "$ok" ]; then
        echo "::error::Google Drive download failed: is the file or folder shared as 'Anyone with the link'? A file many people downloaded recently is refused for a day"
        exit 1
      fi ;;
    *) curl -fL --retry 3 --retry-delay 5 -sS -OJ "$u" ;;
  esac
done
# a Drive folder lands in a subfolder of its own: its game files and parts come up to the game folder
find . -mindepth 2 -type f \( -iname '*.nsp' -o -iname '*.xci' -o -iname '*.nsz' -o -iname '*.xcz' -o -iname '*.nsp.[0-9]*' -o -iname '*.xci.[0-9]*' -o -iname '*.nsz.[0-9]*' -o -iname '*.xcz.[0-9]*' \) -exec mv -n {} . \;
# numbered parts → the file they were split from, deleting each part once copied (the disk holds the game about three times over during a build)
for first in *.000 *.001; do
  [ -e "$first" ] || continue
  base="${first%.*}"
  [ -e "$base" ] && { echo "::error::both $base and its parts are present"; exit 1; }
  echo "joining $base"
  ls -1 -- "$base".[0-9]* | sort | while IFS= read -r part; do cat -- "$part" >> "$base" && rm -- "$part"; done
done
shopt -s nullglob nocaseglob
files=(*.nsp *.xci *.nsz *.xcz)
if [ ${#files[@]} = 0 ]; then
  echo "::error::no .nsp, .xci, .nsz or .xcz file in release '$tag' or the links"
  exit 1
fi
ls -l
df -h .
