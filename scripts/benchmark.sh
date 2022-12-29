#!/bin/bash

set -eu

here="$(realpath .)"

jq '.[]' < data/benchmarks_x86_64.json > benchmarks_x86_64.sj

cd serenity

# Make a simple, normal build and run the tests
for arch in x86_64; do
    rm -f new.results
    touch new.results

    env \
        SERENITY_QEMU_CPU="max,vmx=off" \
        SERENITY_KERNEL_CMDLINE="fbdev=off panic=shutdown system_mode=self-test" \
        SERENITY_RUN="ci" \
        Meta/serenity.sh run $arch \
    2>dbg.log | tee out.log

    oldIFS="$IFS"
    IFS=$'\n'
    for line in $(grep -hoE '^.*(PASS|FAIL|CRASHED).*\(.*\).*$' out.log); do
        line="$(echo "$line" | sed -e 's#^.*\(PASS\|FAIL\|CRASHED\)\s*\S*\s*\([a-zA-Z0-9_/.-]\+\).*\( (\([0-9.]\+m\?s\))\)\?.*$#\2,\4,\1#')"
        echo "Test result: $line"
        path="$(echo "$line" | cut -f1 -d,)"
        time="$(echo "$line" | cut -f2 -d,)"
        res="$(echo "$line" | cut -f3 -d,)"
        case "$time" in
            *ms)
                time="$(echo "$time" | cut -f1 -dm)"
                ;;
            *s)
                time="$(echo "$(echo "$time" | cut -f1 -ds)" \* 1000 | bc)"
                ;;
            "")
                time=0
                ;;
        esac
        jq '{ ($a): { "time": $b, "res": $c } }' --arg a $path --arg b $time --arg c $res -n >> new.results
    done
    IFS="$oldIFS"

    jq -cs 'reduce .[] as $acc ({}; $acc + .)' new.results >> "$here/benchmarks_$arch.sj"
done

rm -f new.results

cd "$here"

rm -fr view/benchmarks
mkdir -p view/benchmarks

for arch in x86_64; do
    mkdir -p view/benchmarks/$arch

    jq -sc . < benchmarks_$arch.sj > data/benchmarks_$arch.json
    jq '[ .[] | reduce (to_entries[]) as $x([]; . + [$x.key]) ] | reduce .[] as $x([]; . + $x | unique)' < data/benchmarks_$arch.json > tests
    jq 'map(. as $dot | $results[] | {($dot): map(.[$dot])}) | reduce .[] as $x({}; . + $x)' tests --slurpfile results data/benchmarks_$arch.json > all.json

    oldIFS="$IFS"
    IFS=$'\n'
    for line in $(jq 'map(debug)|empty' tests 2>&1); do
        name="$(echo "$line" | jq -r '.[1]')"
        fs_name="$(echo "$name" | sed -e 's#/#_#g')"
        echo $line $name $fs_name
        IFS="$oldIFS"
        rm -f "$fs_name.data"
        for output in $(jq '.[$name] | map([.time, if .res == "PASS" then "0" else "1" end] | debug) | empty' all.json --arg name "$name" 2>&1); do
            echo $(echo "$output" | jq '.[1] | .[]' -r) | sed -e 's/ /, /g' >> "$fs_name.data"
        done

        gnuplot <<<$(echo "
            set terminal pngcairo size 1280,720
            set palette model RGB defined ( 0 'green', 1 'red' )
            set output 'view/benchmarks/$arch/$fs_name.png'
            set border linewidth 1
            set style \
                line 1 \
                linecolor rgb '#0060af' \
                linetype 1 \
                linewidth 2 \
                pointtype 7 \
                pointsize 1.3
            set xtics 1
            plot '$fs_name.data' using 0:1:(\$2 == 0 ? 0 : 1) with points pt 7 ps 3 palette title '$name'
        ")

        IFS=$'\n'
    done
done

git add view/benchmarks
