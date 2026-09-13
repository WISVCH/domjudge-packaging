#!/usr/bin/python3

import pathlib
import re

dj_source = next(pathlib.Path("/domjudge-src").glob("domjudge*"))
language_fixture_php = dj_source / "webapp/src/DataFixtures/DefaultData/LanguageFixture.php"

with open(language_fixture_php, "r") as f:
     lines = f.readlines()

for i in range(len(lines)):
    line = lines[i]
    if line.startswith("            [") and "kotlin" in line:
        lines[i] = line.replace("false", "true")
        print("Patching Kotlin line to:")
        print(lines[i].rstrip())
        break
else:
    print(f"Couldn't find kotlin line in {language_fixture_php}")
    exit(1)

with open(language_fixture_php, "w") as f:
    f.writelines(lines)
