#!/usr/bin/env python3
"""Parse "Depends-on:" lines of a pull request description.

    Depends-on: https://github.com/<owner>/<repo>/pull/<n>

Only repositories of the given owner are accepted, so the canary never fetches
from other accounts. Used by the canary (bot/canary-targets.sh) and tested in
test_depends_on.py. Only the standard library.

Commands:
    depends_on.py --owner OWNER < body    (JSON list on stdout)
"""

import argparse
import json
import re
import sys

LINE = re.compile(r"^\s*Depends-on:\s*(\S+)\s*$", re.IGNORECASE | re.MULTILINE)
URL = re.compile(r"^https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/pull/([0-9]+)/?$")


class DependsError(Exception):
    pass


def parse(body, owner):
    """Return [{"repo": name, "number": n}] in order of appearance, without duplicates."""
    result = []
    for url in LINE.findall(body or ""):
        m = URL.match(url)
        if not m:
            raise DependsError(f"not a pull request URL: {url}")
        if m.group(1).lower() != owner.lower():
            raise DependsError(f"only repositories of {owner} can be depended on: {url}")
        dep = {"repo": m.group(2), "number": int(m.group(3))}
        if dep not in result:
            result.append(dep)
    return result


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--owner", required=True)
    args = ap.parse_args(argv)
    try:
        print(json.dumps(parse(sys.stdin.read(), args.owner)))
    except DependsError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
