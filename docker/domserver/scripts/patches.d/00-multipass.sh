#!/usr/bin/env bash

cp ../multipass.patch /domjudge-src
cd /domjudge-src
cd */.
git apply multipass.patch




