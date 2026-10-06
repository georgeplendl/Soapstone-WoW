"""Uploads a Soapstone release zip to CurseForge.

    py tools/release.py build --tag v0.6.0          # first: the zip, in dist/
    py tools/curseforge.py upload --tag v0.6.0      # then: upload it
    py tools/curseforge.py upload --dry-run         # show what would be sent

Reads, from Soapstone/Soapstone.toc at the chosen ref:
  ## Version:             the file's version (dist/Soapstone-v<version>.zip)
  ## Interface:           the game version, 16001 -> "1.60.1"
  ## X-Curse-Project-ID:  the CurseForge project

The changelog is that version's section of CHANGELOG.md, as markdown. The
game version's numeric id is looked up by name through CurseForge's API;
set CF_GAME_VERSION_IDS (comma-separated ids) to skip the lookup, e.g. if
the name matches more than one game version.

Needs CF_API_TOKEN (authors.curseforge.com > Settings > API tokens), except
with --dry-run. The GitHub workflow (.github/workflows/release.yml) runs
`upload --tag` after each GitHub Release when the CF_API_TOKEN secret is set.
"""

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
import uuid

from release import DIST, ADDON, TOC, changelog_notes, check, fail, git

API = "https://wow.curseforge.com/api"
USER_AGENT = "Soapstone-release (https://github.com/georgeplendl/Soapstone-WoW)"
RELEASE_TYPE = "beta"  # alpha | beta | release; beta while WoW Forever is in beta
RELATIONS = [{"slug": "tomtom", "type": "optionalDependency"}]


def toc_field(ref, name):
    toc = git("show", f"{ref}:{TOC}")
    match = re.search(rf"^## {re.escape(name)}:\s*(.+?)\s*$", toc, re.MULTILINE)
    if not match:
        fail(f"no '## {name}:' line in {TOC} at {ref}")
    return match.group(1)


def game_version_name(interface):
    """16001 -> "1.60.1", 11502 -> "1.15.2": the version CurseForge lists."""
    if not re.fullmatch(r"\d{5,6}", interface):
        fail(f"## Interface: {interface} isn't a single interface number")
    n = int(interface)
    return f"{n // 10000}.{n // 100 % 100}.{n % 100}"


def request(path, token, data=None, headers=None):
    req = urllib.request.Request(f"{API}{path}", data=data, headers={
        "X-Api-Token": token, "User-Agent": USER_AGENT, **(headers or {})})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as e:
        fail(f"CurseForge {path}: HTTP {e.code}: {e.read().decode(errors='replace')[:500]}")


def game_version_ids(name, token):
    override = os.environ.get("CF_GAME_VERSION_IDS", "").strip()
    if override:
        return [int(i) for i in override.split(",")]
    matches = [v for v in request("/game/versions", token) if v.get("name") == name]
    if len(matches) == 1:
        return [matches[0]["id"]]
    if matches:
        types = {t["id"]: t for t in request("/game/version-types", token)}
        forever = [v for v in matches
                   if "forever" in (types.get(v["gameVersionTypeID"], {}).get("slug") or "").lower()]
        if len(forever) == 1:
            return [forever[0]["id"]]
        found = ", ".join(f"{v['id']} ({types.get(v['gameVersionTypeID'], {}).get('name', '?')})"
                          for v in matches)
        fail(f"several CurseForge game versions are named {name}: {found}. "
             "Set CF_GAME_VERSION_IDS to the right one.")
    fail(f"CurseForge has no game version named {name}. Set CF_GAME_VERSION_IDS.")


def multipart(fields, file_field, file_name, file_bytes):
    boundary = uuid.uuid4().hex
    parts = []
    for key, value in fields.items():
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{key}"\r\n\r\n{value}\r\n'.encode())
    parts.append((f'--{boundary}\r\nContent-Disposition: form-data; name="{file_field}"; '
                  f'filename="{file_name}"\r\nContent-Type: application/zip\r\n\r\n').encode())
    parts.append(file_bytes)
    parts.append(f"\r\n--{boundary}--\r\n".encode())
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def upload(ref, tag, dry_run):
    version, _ = check(ref, tag)
    project = toc_field(ref, "X-Curse-Project-ID")
    gv_name = game_version_name(toc_field(ref, "Interface"))
    zip_path = DIST / f"{ADDON}-v{version}.zip"
    metadata = {
        "displayName": f"{ADDON} v{version}",
        "releaseType": os.environ.get("CF_RELEASE_TYPE", RELEASE_TYPE),
        "changelog": changelog_notes(version),
        "changelogType": "markdown",
        "relations": {"projects": RELATIONS},
    }
    print(f"project       {project}")
    print(f"file          {zip_path.relative_to(DIST.parent)}")
    print(f"game version  {gv_name}")
    print(f"release type  {metadata['releaseType']}")

    if dry_run:
        print("dry run: nothing uploaded")
        print(json.dumps(metadata, indent=2))
        return
    token = os.environ.get("CF_API_TOKEN")
    if not token:
        fail("CF_API_TOKEN isn't set")
    if not zip_path.exists():
        fail(f"{zip_path} doesn't exist; run tools/release.py build first")

    metadata["gameVersions"] = game_version_ids(gv_name, token)
    print(f"game version ids {metadata['gameVersions']}")
    body, content_type = multipart({"metadata": json.dumps(metadata)}, "file",
                                   zip_path.name, zip_path.read_bytes())
    result = request(f"/projects/{project}/upload-file", token, body, {"Content-Type": content_type})
    print(f"uploaded: CurseForge file id {result.get('id')}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["upload"])
    parser.add_argument("--ref", default="HEAD", help="tag or commit to release (default HEAD)")
    parser.add_argument("--tag", help="require this tag name to equal v<.toc version>")
    parser.add_argument("--dry-run", action="store_true", help="print what would be uploaded")
    args = parser.parse_args()
    upload(args.ref, args.tag, args.dry_run)


if __name__ == "__main__":
    main()
