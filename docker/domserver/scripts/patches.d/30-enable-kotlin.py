#!/usr/bin/python3

import pathlib
import re

dj_source = next(pathlib.Path("/domjudge-src").glob("domjudge*"))
language_fixture_php = dj_source / "webapp/src/DataFixtures/DefaultData/LanguageFixture.php"

with open(language_fixture_php, "r") as f:
     lines = f.readlines()

for i in range(len(lines)):
    elements = lines[i].split(',')

    if len(elements) >= 10 and elements[5].strip().lower() == 'false':
        if 'kotlin' in elements[0]:
            elements[5] = 'true'

            lines[i] = ','.join(elements)
            break
else:
    print(f"Couldn't find kotlin line in {language_fixture_php}")
    exit(1)

with open(language_fixture_php, "w") as f:
    f.writelines(lines)
