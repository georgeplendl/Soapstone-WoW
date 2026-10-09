"""Uploads a Soapstone release zip to CurseForge, and writes its page text.

    py tools/release.py build --tag v0.6.0          # first: the zip, in dist/
    py tools/curseforge.py upload --tag v0.6.0      # then: upload it
    py tools/curseforge.py upload --dry-run         # show what would be sent
    py tools/curseforge.py check                    # token + game version, no upload
    py tools/curseforge.py page                     # README.md -> the CurseForge page text
    py tools/curseforge.py page --check             # fail if that text is out of date

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
`upload --tag` after each GitHub Release when the CF_API_TOKEN secret is set,
and the Tests workflow runs `check` on every push and pull request, so a
token or game version that stops working shows up before release day.

CurseForge's API has no way to change a project's page, so its text is
pasted in by hand from docs/CurseForge/description.md. `page` writes that
file from README.md, so the two always say the same: it drops the title,
anything between <!-- github-only --> and <!-- /github-only -->, and other
comments, uncomments <!-- curseforge-only ... --> blocks, turns in-page
links into plain text, and makes relative links and pictures point at
GitHub (pictures from main). The Tests workflow runs `page --check`.
"""

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
import uuid

from release import DIST, ADDON, ROOT, TOC, changelog_notes, check, fail, git

README = ROOT / "README.md"
PAGE = ROOT / "docs" / "CurseForge" / "description.md"
REPO_URL = "https://github.com/georgeplendl/Soapstone-WoW"
RAW_URL = "https://raw.githubusercontent.com/georgeplendl/Soapstone-WoW/main/"

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
        # CurseForge echoes a malformed token back in its error; never print it.
        body = e.read().decode(errors="replace")
        try:  # the decoded message, so JSON escapes can't hide the token from replace()
            body = json.loads(body).get("errorMessage") or body
        except (ValueError, AttributeError):
            pass
        for form in (token, json.dumps(token)[1:-1]):
            body = body.replace(form, "***")
        body = body[:500]
        hint = token_hint(token) if "malformed" in body.lower() else ""
        fail(f"CurseForge {path}: HTTP {e.code}: {body}{hint}")


def token_hint(token):
    """Says what a token CurseForge calls malformed looks like, without showing it."""
    if token.startswith("$2a$"):
        shape = "a CurseForge for Studios API key (it starts with $2a$), which can't upload"
    else:
        shape = (f"{len(token)} characters, not the xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx "
                 "(36 characters) of an author token")
        if any(c in token for c in "\"' "):
            shape += ", and it has quotes or spaces in it"
    return (f"\nThe token is {shape}. Make an author token at "
            "https://authors.curseforge.com/#/settings/api-tokens and save it as CF_API_TOKEN.")


def api_token():
    token = os.environ.get("CF_API_TOKEN", "").strip()
    if not token:
        fail("CF_API_TOKEN isn't set")
    if not token.isascii():
        fail("CF_API_TOKEN has characters no token has (curly quotes or invisible ones, "
             "often picked up by copy and paste). Copy it again and save it as CF_API_TOKEN.")
    return token


def game_version_ids(name, token):
    override = os.environ.get("CF_GAME_VERSION_IDS", "").strip()
    if override:
        return [int(i) for i in override.split(",")]
    versions = request("/game/versions", token)
    matches = [v for v in versions if v.get("name") == name]
    if len(matches) == 1:
        return [matches[0]["id"]]
    types = {t["id"]: t for t in request("/game/version-types", token)}

    def label(v):
        return f"{v['name']} = {v['id']} ({types.get(v['gameVersionTypeID'], {}).get('name', '?')})"

    if matches:
        forever = [v for v in matches
                   if "forever" in (types.get(v["gameVersionTypeID"], {}).get("slug") or "").lower()]
        if len(forever) == 1:
            return [forever[0]["id"]]
        fail(f"several CurseForge game versions are named {name}: "
             f"{', '.join(map(label, matches))}. Set CF_GAME_VERSION_IDS to the right one.")
    series = name.rsplit(".", 1)[0] + "."
    near = [v for v in versions if (v.get("name") or "").startswith(series)]
    hint = f" Close ones: {', '.join(map(label, near))}." if near else ""
    fail(f"CurseForge has no game version named {name}.{hint} Set CF_GAME_VERSION_IDS.")


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
    token = api_token()
    if not zip_path.exists():
        fail(f"{zip_path} doesn't exist; run tools/release.py build first")

    metadata["gameVersions"] = game_version_ids(gv_name, token)
    print(f"game version ids {metadata['gameVersions']}")
    body, content_type = multipart({"metadata": json.dumps(metadata)}, "file",
                                   zip_path.name, zip_path.read_bytes())
    result = request(f"/projects/{project}/upload-file", token, body, {"Content-Type": content_type})
    print(f"uploaded: CurseForge file id {result.get('id')}")


def verify(ref):
    """Checks the token works and the game version resolves; uploads nothing."""
    project = toc_field(ref, "X-Curse-Project-ID")
    gv_name = game_version_name(toc_field(ref, "Interface"))
    token = api_token()
    versions = {v["id"]: v for v in request("/game/versions", token)}  # fails on a bad token
    types = {t["id"]: t.get("name", "?") for t in request("/game/version-types", token)}
    print(f"project       {project}")
    print("token         accepted")
    source = "CF_GAME_VERSION_IDS" if os.environ.get("CF_GAME_VERSION_IDS", "").strip() else "looked up"
    for i in game_version_ids(gv_name, token):
        v = versions.get(i)
        if not v:
            fail(f"CurseForge has no game version with id {i}; check CF_GAME_VERSION_IDS")
        print(f"game version  {v['name']} = id {i}, {types.get(v['gameVersionTypeID'], '?')} ({source})")
    print("ok: ready to upload (nothing was uploaded)")


def page_text(readme):
    """The CurseForge page: the README without its GitHub-only parts."""
    text = re.sub(r"<!-- github-only -->.*?<!-- /github-only -->", "", readme, flags=re.S)
    text = re.sub(r"<!-- curseforge-only\n(.*?)-->", r"\1", text, flags=re.S)
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    text = re.sub(r"\A\s*# .*\n", "", text)  # CurseForge shows the title itself
    text = re.sub(r"\[([^\]]+)\]\(#[^)]*\)", r"\1", text)  # in-page links
    text = re.sub(r'(src=")(?!https?:)', lambda m: m[1] + RAW_URL, text)
    text = re.sub(r"(\]\()(?!https?:|#|mailto:)", lambda m: m[1] + f"{REPO_URL}/blob/main/", text)
    return re.sub(r"\n{3,}", "\n\n", text).strip() + "\n"


def page(check_only):
    text = page_text(README.read_text(encoding="utf-8"))
    rel = PAGE.relative_to(ROOT).as_posix()
    if check_only:
        if not PAGE.exists() or PAGE.read_text(encoding="utf-8") != text:
            fail(f"{rel} doesn't match README.md; run py tools/curseforge.py page and commit it")
        print(f"ok: {rel} matches README.md")
        return
    PAGE.write_text(text, encoding="utf-8", newline="\n")
    print(f"wrote {rel} from README.md")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["upload", "check", "page"])
    parser.add_argument("--ref", default="HEAD", help="tag or commit to release (default HEAD)")
    parser.add_argument("--tag", help="require this tag name to equal v<.toc version>")
    parser.add_argument("--dry-run", action="store_true", help="print what would be uploaded")
    parser.add_argument("--check", action="store_true", help="page: only check the file is up to date")
    args = parser.parse_args()
    if args.command == "check":
        verify(args.ref)
    elif args.command == "page":
        page(args.check)
    else:
        upload(args.ref, args.tag, args.dry_run)


if __name__ == "__main__":
    main()
