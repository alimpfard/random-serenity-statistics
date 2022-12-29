#!/bin/bash

set -eu

cd serenity

for arch in x86_64; do
    Meta/serenity.sh build $arch
done
