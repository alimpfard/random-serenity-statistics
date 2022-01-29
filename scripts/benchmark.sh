#!/bin/bash

set -eu

here="$(realpath .)"

jq '.[]' < data/benchmarks_x86_64.json > benchmarks_x86_64.sj
jq '.[]' < data/benchmarks_i686.json > benchmarks_i686.sj

cd serenity

# Make a simple, normal build and run the tests
for arch in i686 x86_64; do
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
        line="$(echo "$line" | sed -e 's#^.*\(PASS\|FAIL\|CRASHED\)\s\+.* \([a-zA-Z0-9_/.-]\+\).* (\([0-9.]\+m\?s\)).*$#\2,\3,\1#')"
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
        esac
        jq '{ ($a): { "time": $b, "res": $c } }' --arg a $path --arg b $time --arg c $res -n >> new.results
    done
    IFS="$oldIFS"

    jq -cs 'reduce .[] as $acc ({}; $acc + .)' new.results >> "$here/benchmarks_$arch.sj"
done

rm -f new.results

cd "$here"

for arch in i686 x86_64; do
    jq -sc . < benchmarks_$arch.sj > data/benchmarks_$arch.json
done
