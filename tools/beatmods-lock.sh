#!/usr/bin/env bash
set -euo pipefail
v=${1:?usage: tools/beatmods-lock.sh GAME_VERSION}
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl -fsS -o "$tmp/mods.json" "https://beatmods.com/api/mods?gameName=BeatSaber&gameVersion=$v&status=verified&platform=steampc"

jq -r '.mods[].latest.zipHash' "$tmp/mods.json" |
  xargs -P 8 -I '{}' sh -c '
    set -e
    curl -fsS -o "$1/$2.zip" "https://beatmods.com/cdn/mod/$2.zip"
    echo "$2  $1/$2.zip" | md5sum -c --quiet
    nix hash file --sri --type sha256 "$1/$2.zip" > "$1/$2.sri"
  ' _ "$tmp" '{}'

for f in "$tmp"/*.sri; do
  h=${f##*/}
  jq -n --arg k "${h%.sri}" --rawfile v "$f" '{($k): ($v | rtrimstr("\n"))}'
done | jq -s add > "$tmp/sri.json"

mkdir -p "$repo/beat-saber"
jq -S --arg v "$v" --slurpfile sri "$tmp/sri.json" '
  if (.mods | length) == 0 then error("BeatMods has no verified mods for \($v)") else . end
  | (.mods | map({ key: (.latest.id | tostring), value: .mod.name }) | from_entries) as $names
  | {
      gameVersion: $v,
      mods: (.mods | map({
        key: .mod.name,
        value: {
          version: .latest.modVersion,
          url: "https://beatmods.com/cdn/mod/\(.latest.zipHash).zip",
          hash: $sri[0][.latest.zipHash],
          depends: [.latest.dependencies[] | $names[tostring] // error("\(.) is not a verified \($v) mod")] | sort
        }
      }) | from_entries)
    }
' "$tmp/mods.json" > "$repo/beat-saber/beatmods.json"
