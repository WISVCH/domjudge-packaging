#!/usr/bin/env bash

cp /scripts/multipass.patch /domjudge-src
cd /domjudge-src/domjudge*
git apply ../multipass.patch




