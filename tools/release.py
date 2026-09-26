"""Builds a Soapstone release: version checks, installable zip, release notes.

    py tools/release.py check                 # .toc version has a CHANGELOG entry
    py tools/release.py build                 # zip + notes for HEAD, into dist/
    py tools/release.py build --ref v0.1.0    # ...for any tag or commit
    py tools/release.py build --tag v0.2.0    # also require the tag to match

The version lives in one place: `## Version:` in Soapstone/Soapstone.toc at
the chosen ref. The zip holds just the `Soapstone/` folder as committed
(`git archive`), ready to unzip into `Interface\\AddOns`. Release notes are
that version's section of CHANGELOG.md in the working tree, so older
releases can be rebuilt with today's wording.

The GitHub workflow (.github/workflows/release.yml) runs `build --tag` on
every pushed `v*` tag and publishes the result as a GitHub Release.
"""

import argparse
import re
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDON = "Soapstone"
TOC = f"{ADDON}/{ADDON}.toc"
CHANGELOG = ROOT / "CHANGELOG.md"
DIST = ROOT / "dist"

SEMVER = re.compile(r"^\d+\.\d+\.\d+$")


def fail(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def git(*args):
    result = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)
    if result.returncode != 0:
        fail(f"git {' '.join(args)}: {result.stderr.strip()}")
    return result.stdout


def toc_version(ref):
    toc = git("show", f"{ref}:{TOC}")
    match = re.search(r"^## Version:\s*(\S+)", toc, re.MULTILINE)
    if not match:
        fail(f"no '## Version:' line in {TOC} at {ref}")
    version = match.group(1)
    if not SEMVER.match(version):
        fail(f"version '{version}' in {TOC} isn't MAJOR.MINOR.PATCH")
    return version


def changelog_notes(version):
    """The body of the `## [version]` section, without its heading."""
    text = CHANGELOG.read_text(encoding="utf-8")
    heading = re.search(rf"^## \[{re.escape(version)}\][^\n]*\n", text, re.MULTILINE)
    if not heading:
        fail(f"CHANGELOG.md has no '## [{version}]' section")
    rest = text[heading.end():]
    end = re.search(r"^## \[|^\[[^\]]+\]: ", rest, re.MULTILINE)
    notes = (rest[:end.start()] if end else rest).strip()
    if not notes:
        fail(f"CHANGELOG.md section for {version} is empty")
    return notes


def check(ref, tag):
    version = toc_version(ref)
    if tag is not None and tag != f"v{version}":
        fail(f"tag {tag} doesn't match the .toc version {version} (expected v{version})")
    notes = changelog_notes(version)
    return version, notes


def add_build_info(zip_path, ref, label):
    """Adds Soapstone/BuildInfo.lua naming the release, for /soap version.

    In a dev checkout the git hooks write this file (tools/buildinfo.sh);
    it's git-ignored, so git archive never includes it.
    """
    commit = git("rev-parse", "--short", ref).strip()
    date = git("log", "-1", "--format=%cd", "--date=format:%Y-%m-%d %H:%M", ref).strip()
    lua = (
        "-- Written by tools/release.py for this release. Shown by /soap version.\n"
        "local _, ns = ...\n"
        f'ns.BUILD = {{ branch = "{label}", commit = "{commit}", date = "{date}", release = true }}\n'
    )
    with zipfile.ZipFile(zip_path, "a") as archive:
        archive.writestr(f"{ADDON}/BuildInfo.lua", lua)


def build(ref, tag):
    version, notes = check(ref, tag)
    DIST.mkdir(exist_ok=True)
    zip_path = DIST / f"{ADDON}-v{version}.zip"
    git("archive", "--format=zip", "-o", str(zip_path), ref, f"{ADDON}/")
    add_build_info(zip_path, ref, tag or f"v{version}")
    notes_path = DIST / "release-notes.md"
    install = (
        "\n\n---\n\n"
        f"**Install:** download `{zip_path.name}` and unzip it into "
        "`World of Warcraft\\<client>\\Interface\\AddOns`, so you get "
        f"`AddOns\\{ADDON}\\{ADDON}.toc`. Then restart the game."
    )
    notes_path.write_text(notes + install + "\n", encoding="utf-8")
    print(f"version  {version}")
    print(f"zip      {zip_path.relative_to(ROOT)}")
    print(f"notes    {notes_path.relative_to(ROOT)}")
    return version


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["check", "build"])
    parser.add_argument("--ref", default="HEAD", help="tag or commit to release (default HEAD)")
    parser.add_argument("--tag", help="require this tag name to equal v<.toc version>")
    args = parser.parse_args()
    if args.command == "check":
        version, _ = check(args.ref, args.tag)
        print(f"ok: {version} has a changelog entry")
    else:
        build(args.ref, args.tag)


if __name__ == "__main__":
    main()
