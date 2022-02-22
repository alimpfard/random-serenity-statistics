#!/bin/bash

set -xeu

here="$(realpath .)"
jq '.[]' < data/loc.json > loc.sj
last_indexed_commit="$(cat misc/last_commit)"

pushd serenity || exit 1

git log --oneline | head -n5
echo

allcommits=$(git log "$last_indexed_commit"..HEAD --oneline | cut -f1 -d' ')

for hash in $allcommits; do
    git checkout "$hash" >/dev/null 2>&1 || continue
    scc -cd --no-cocomo --no-min --format json --exclude-dir .git,Build,Toolchain,Ports 2>/dev/null | \
        jq -c 'map({Name, Lines, Code})' >> "$here/loc.sj"
done
popd || exit 1

jq -sc . < loc.sj > data/loc.json

jq ".[] | reduce .[] as \$item (0; . + \$item.Code)" < data/loc.json > raw.loc.dat
# echo >> raw.loc.dat
# jq '.[] | .["C++"].Code' < data/loc.json > raw.loc.dat

gnuplot <<<$(echo '
    set terminal pngcairo size 1280,720
    set output "view/loc.png"
    set border linewidth 1.5
    set style \
        line 1 \
        linecolor rgb "#0060af" \
        linetype 1 \
        linewidth 2 \
        pointtype 7 \
        pointsize 1.5
    plot "raw.loc.dat" with linespoints linestyle 1
')

git add view/loc.png
