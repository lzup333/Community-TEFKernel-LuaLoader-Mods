#!/usr/bin/env python3
"""Rebuild index.json from fixed GitHub Release asset download counts."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import urllib.error
import urllib.request
from pathlib import Path

from lualoader_modrepo import RELEASE_TAG, pack_packages, rebuild_index


def _get_json(url: str, token: str) -> object:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "Community-TEFKernel-LuaLoader-Mods",
        },
    )
    try:
        with urllib.request.urlopen(request) as response:
            return json.load(response)
    except (urllib.error.HTTPError, urllib.error.URLError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"GitHub API request failed: {url}: {exc}") from exc


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY", ""))
    parser.add_argument("--token", default=os.environ.get("GITHUB_TOKEN", ""))
    parser.add_argument("--tag", default=RELEASE_TAG)
    args = parser.parse_args()
    if not args.repository or not args.token:
        raise SystemExit("GITHUB_REPOSITORY and GITHUB_TOKEN are required")

    api_root = f"https://api.github.com/repos/{args.repository}"
    release = _get_json(f"{api_root}/releases/tags/{args.tag}", args.token)
    if not isinstance(release, dict) or not isinstance(release.get("id"), int):
        raise SystemExit("fixed Mod repository release was not found")
    counts = {}
    for page in range(1, 101):
        assets = _get_json(f"{api_root}/releases/{release['id']}/assets?per_page=100&page={page}", args.token)
        if not isinstance(assets, list):
            raise SystemExit("GitHub returned an invalid release asset list")
        for asset in assets:
            if not isinstance(asset, dict):
                raise SystemExit("GitHub returned an invalid release asset")
            name = asset.get("name", "")
            if isinstance(name, str) and name.endswith(".tefpkg"):
                counts[name[:-7]] = int(asset.get("download_count", 0))
        if len(assets) < 100:
            break
    else:
        raise SystemExit("too many release assets; pagination limit reached")

    import tempfile
    with tempfile.TemporaryDirectory(prefix="lualoader-mod-assets-") as temporary:
        generated = pack_packages(args.repo, Path(temporary))
        hashes = {}
        sizes = {}
        for asset in generated:
            digest = hashlib.sha256(asset.read_bytes()).hexdigest()
            hashes[asset.name[:-7]] = digest
            sizes[asset.name[:-7]] = asset.stat().st_size
        result = rebuild_index(args.repo, counts, hashes, sizes)
    print(f"rebuilt index: {len(result['mods'])} mods")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
