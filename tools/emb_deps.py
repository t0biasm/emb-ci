#!/usr/bin/env python3
"""Read and check emb-project.toml (which submodules a project branch follows).

Used by the propagation bot, the canary and developers on Windows/Linux/macOS.
Only the standard library (Python >= 3.11, tomllib).

emb-project.toml:

    project = "prj-sumobot"

    [ci]
    target = "//applications/sumobot:app"
    config = "atmega32u4"

    [follow."toolchain/emb-toolchain"]
    track = "main"          # branch name, or "tag:<glob>" e.g. "tag:v1.*"
    mode  = "auto"          # auto: push after green CI, pr: open a PR, off
    group = "core"          # optional: members of a group are bumped together

Submodules that are not listed are frozen.

Commands:
    emb_deps.py check   [--root DIR] [--branch NAME]
    emb_deps.py status  [--root DIR]
    emb_deps.py match   --repo NAME --ref REF [--root DIR]   (JSON on stdout)
"""

import argparse
import configparser
import fnmatch
import json
import subprocess
import sys
import tomllib
from pathlib import Path

CONFIG_NAME = "emb-project.toml"
MODES = ("auto", "pr", "off")


class ConfigError(Exception):
    pass


def load_config(root):
    path = Path(root) / CONFIG_NAME
    if not path.is_file():
        raise ConfigError(f"{path} not found")
    try:
        with open(path, "rb") as f:
            data = tomllib.load(f)
    except tomllib.TOMLDecodeError as e:
        raise ConfigError(f"{path}: {e}") from e
    return data


def follow_rules(config):
    """Return {submodule path: {track, mode, group}} with defaults and validation."""
    rules = {}
    follow = config.get("follow", {})
    if not isinstance(follow, dict):
        raise ConfigError("[follow] must be a table of submodule paths")
    for path, rule in follow.items():
        if not isinstance(rule, dict):
            raise ConfigError(f"follow.{path} must be a table")
        unknown = set(rule) - {"track", "mode", "group"}
        if unknown:
            raise ConfigError(f"follow.{path}: unknown keys {sorted(unknown)}")
        mode = rule.get("mode", "auto")
        if mode not in MODES:
            raise ConfigError(f"follow.{path}: mode must be one of {MODES}, got {mode!r}")
        track = rule.get("track")
        if not isinstance(track, str) or not track:
            raise ConfigError(f"follow.{path}: track is required (branch or tag:<glob>)")
        if track.startswith("tag:") and len(track) == 4:
            raise ConfigError(f"follow.{path}: empty tag pattern")
        rules[path] = {"track": track, "mode": mode, "group": rule.get("group")}
    return rules


def submodule_urls(root):
    """Return {path: url} from .gitmodules."""
    gm = Path(root) / ".gitmodules"
    if not gm.is_file():
        return {}
    cp = configparser.ConfigParser(strict=False)
    # .gitmodules is git-config syntax; tabs are indentation
    cp.read_string("\n".join(line.strip() for line in gm.read_text().splitlines()))
    return {cp[s]["path"]: cp[s].get("url", "") for s in cp.sections() if "path" in cp[s]}


def repo_name(url):
    name = url.rstrip("/").rsplit("/", 1)[-1]
    if name.endswith(".git"):
        name = name[:-4]
    return name


def ref_matches(track, ref):
    """ref is 'main', 'release/1.x' or 'refs/heads/..' / 'refs/tags/..'."""
    if ref.startswith("refs/heads/"):
        ref = ref[len("refs/heads/"):]
        kind = "branch"
    elif ref.startswith("refs/tags/"):
        ref = ref[len("refs/tags/"):]
        kind = "tag"
    else:
        kind = "branch"
    if track.startswith("tag:"):
        return kind == "tag" and fnmatch.fnmatchcase(ref, track[4:])
    return kind == "branch" and ref == track


def match(root, repo, ref):
    """Follow rules of this project branch that apply to a push of `ref` in `repo`."""
    config = load_config(root)
    rules = follow_rules(config)
    urls = submodule_urls(root)
    result = []
    for path, rule in rules.items():
        if rule["mode"] == "off":
            continue
        if repo_name(urls.get(path, "")) != repo:
            continue
        if ref_matches(rule["track"], ref):
            result.append({"path": path, **rule})
    return result


def check(root, branch=None):
    """Return a list of problems (empty = ok)."""
    problems = []
    try:
        config = load_config(root)
        rules = follow_rules(config)
    except ConfigError as e:
        return [str(e)]
    urls = submodule_urls(root)
    for path, rule in rules.items():
        if path not in urls:
            problems.append(f"follow.{path}: not a submodule in .gitmodules")
        if branch and branch.startswith("release/") and rule["mode"] != "off" \
                and rule["track"] == "main":
            problems.append(
                f"follow.{path}: release branch {branch} must not track main "
                "(follow a maintained line such as release/1.x, or set mode = \"off\")")
    groups = {}
    for path, rule in rules.items():
        if rule["group"]:
            groups.setdefault(rule["group"], set()).add(rule["mode"])
    for name, settings in groups.items():
        if len(settings) > 1:
            problems.append(f"group {name!r}: members need the same mode (the tracked refs may differ per repository)")
    ci = config.get("ci", {})
    if not isinstance(ci, dict):
        problems.append("[ci] must be a table")
    return problems


def pinned_commits(root):
    out = subprocess.run(["git", "-C", str(root), "submodule", "status"],
                         capture_output=True, text=True, check=False).stdout
    pins = {}
    for line in out.splitlines():
        parts = line.strip().split()
        if len(parts) >= 2:
            pins[parts[1]] = parts[0].lstrip("+-U")
    return pins


def status(root):
    config = load_config(root)
    rules = follow_rules(config)
    urls = submodule_urls(root)
    pins = pinned_commits(root)
    rows = []
    for path in sorted(set(urls) | set(rules)):
        rule = rules.get(path)
        rows.append((path, pins.get(path, "?")[:10],
                     f"{rule['mode']} <- {rule['track']}" if rule else "frozen"))
    width = max((len(r[0]) for r in rows), default=0)
    return "\n".join(f"{p:<{width}}  {sha:<10}  {desc}" for p, sha, desc in rows)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("check", "status", "match"):
        p = sub.add_parser(name)
        p.add_argument("--root", default=".")
        if name == "check":
            p.add_argument("--branch")
        if name == "match":
            p.add_argument("--repo", required=True)
            p.add_argument("--ref", required=True)
    args = ap.parse_args(argv)
    try:
        if args.cmd == "check":
            problems = check(args.root, args.branch)
            for p in problems:
                print(f"error: {p}", file=sys.stderr)
            return 1 if problems else 0
        if args.cmd == "status":
            print(status(args.root))
            return 0
        print(json.dumps(match(args.root, args.repo, args.ref)))
        return 0
    except ConfigError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
