#!/usr/bin/env bash

cp /scripts/patches.d/multipass.patch /domjudge-src
cd /domjudge-src
cd */.
git apply ../multipass.patch




