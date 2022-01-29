#!/bin/bash

set -eu

cd serenity

for arch in i686 x86_64; do
    Meta/serenity.sh build $arch
done
