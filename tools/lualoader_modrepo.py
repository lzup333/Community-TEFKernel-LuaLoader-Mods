#!/usr/bin/env python3
"""Static repository and package manager for pure-Lua LuaLoader Mods."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path, PurePosixPath
from typing import Iterable


NATIVE_SUFFIXES = (".so", ".dll", ".dylib")
PKG_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
RELEASE_TAG = "mod-repository"
RELEASE_BASE_URL = "https://github.com/lzup333/Community-TEFKernel-LuaLoader-Mods/releases/download/mod-repository"
NEW_MOD_PROMOTION_DAYS = 7


class PackageRejected(ValueError):
    """The package is malformed or violates the repository format."""


class PackageSkipped(ValueError):
    """The package is intentionally skipped, currently for native binaries."""


@dataclass(frozen=True)
class PackageInfo:
    source: Path
    pkg_id: str
    name: str
    author: str
    version: str
    version_code: int
    info: dict
    manifest: dict
    luamod: dict
    main_path: str
    main_mtime: str
    main_mtime_epoch: float


@dataclass
class ImportReport:
    accepted: int = 0
    skipped_native: int = 0
    rejected: int = 0
    duplicates: int = 0
    errors: list[str] | None = None

    def __post_init__(self):
        if self.errors is None:
            self.errors = []


def default_repo() -> Path:
    return Path(os.environ.get("LUALOADER_MODREPO", "~/.local/share/lualoader-modrepo/repository")).expanduser()


def _safe_name(name: str) -> str:
    normalized = name.replace("\\", "/")
    path = PurePosixPath(normalized)
    if normalized.startswith("/") or path.is_absolute() or ".." in path.parts:
        raise PackageRejected(f"unsafe ZIP path: {name}")
    if not normalized or normalized.endswith("/"):
        return normalized
    return normalized


def _read_json(zf: zipfile.ZipFile, name: str) -> dict:
    try:
        value = json.loads(zf.read(name).decode("utf-8"))
    except KeyError as exc:
        raise PackageRejected(f"missing {name}") from exc
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise PackageRejected(f"invalid JSON: {name}") from exc
    if not isinstance(value, dict):
        raise PackageRejected(f"JSON object required: {name}")
    return value


def _manifest_file(manifest: dict) -> str:
    """Return the loader config named by Manifest.json.

    LuaLoader packages conventionally call this file luamod.json, but the
    manifest is the source of truth and older/community packages use names
    such as mod.json or loader.json.
    """
    name = manifest.get("file", "luamod.json")
    if not isinstance(name, str) or not name:
        raise PackageRejected("Manifest.json.file must be a non-empty path")
    return _safe_name(name)


def _is_native_binary(name: str) -> bool:
    lower = name.lower()
    return lower.endswith(NATIVE_SUFFIXES) or ".so." in lower


def _find_main(names: set[str], luamod: dict) -> str:
    requested = str(luamod.get("main", "main.lua"))
    candidates = [requested, f"Resources/lib/{requested}"]
    basename = PurePosixPath(requested).name
    candidates.extend([f"Resources/lib/{basename}", basename])
    for candidate in candidates:
        if candidate in names:
            return candidate
    suffix = "/" + basename
    matches = sorted(name for name in names if name.endswith(suffix))
    if matches:
        return matches[0]
    raise PackageRejected(f"main.lua not found (requested {requested})")


def _iso_mtime(info: zipfile.ZipInfo) -> tuple[str, float]:
    dt = datetime(*info.date_time, tzinfo=timezone.utc)
    return dt.isoformat().replace("+00:00", "Z"), dt.timestamp()


def scan_package(path: Path) -> PackageInfo:
    path = Path(path)
    if not zipfile.is_zipfile(path):
        raise PackageRejected(f"not a ZIP package: {path}")
    try:
        with zipfile.ZipFile(path) as zf:
            names = set()
            entries = []
            for entry in zf.infolist():
                safe = _safe_name(entry.filename)
                if safe and not safe.endswith("/"):
                    names.add(safe)
                    entries.append((entry, safe))
                    if _is_native_binary(safe):
                        raise PackageSkipped(f"native binary: {safe}")
            info = _read_json(zf, "Info.json")
            manifest = _read_json(zf, "Manifest.json")
            config_name = _manifest_file(manifest)
            if config_name not in names:
                raise PackageRejected(f"missing Manifest.json.file: {config_name}")
            luamod = _read_json(zf, config_name)
            pkg_id = str(info.get("pkgId", ""))
            luamod_id = str(luamod.get("pkg_id", ""))
            if not PKG_ID_RE.fullmatch(pkg_id):
                raise PackageRejected("invalid or missing Info.json.pkgId")
            if pkg_id != luamod_id:
                raise PackageRejected("Info.json.pkgId and luamod.json.pkg_id differ")
            if manifest.get("type") not in ("Mod", "mod"):
                raise PackageRejected("Manifest.json.type is not Mod")
            main_path = _find_main(names, luamod)
            main_info = next(entry for entry, safe in entries if safe == main_path)
            main_mtime, main_epoch = _iso_mtime(main_info)
            return PackageInfo(
                source=path,
                pkg_id=pkg_id,
                name=str(info.get("name", pkg_id)),
                author=str(info.get("author", "")),
                version=str(info.get("version", luamod.get("version", "0.0.0"))),
                version_code=int(info.get("versionCode", luamod.get("version_code", 0))),
                info=info,
                manifest=manifest,
                luamod=luamod,
                main_path=main_path,
                main_mtime=main_mtime,
                main_mtime_epoch=main_epoch,
            )
    except (zipfile.BadZipFile, OSError) as exc:
        raise PackageRejected(f"cannot read package {path}: {exc}") from exc


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _format_size(size: int) -> str:
    return f"{size / (1024 * 1024):.2f} MiB" if size >= 1024 * 1024 else f"{size / 1024:.1f} KiB"


def _normalize_zip(source: Path, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".tmp")
    with zipfile.ZipFile(source) as source_zip, zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED) as target:
        members = sorted((entry for entry in source_zip.infolist() if not entry.filename.endswith("/")), key=lambda e: e.filename)
        for entry in members:
            name = _safe_name(entry.filename)
            if not name:
                continue
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = entry.external_attr
            target.writestr(info, source_zip.read(entry))
    temporary.replace(output)


def _normalize_directory(source: Path, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".tmp")
    with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED) as target:
        for path in sorted(p for p in source.rglob("*") if p.is_file()):
            name = _safe_name(path.relative_to(source).as_posix())
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            target.writestr(info, path.read_bytes())
    temporary.replace(output)


def _extract_package(source: Path, target: Path) -> None:
    if target.exists():
        shutil.rmtree(target)
    target.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(source) as zf:
        for entry in zf.infolist():
            name = _safe_name(entry.filename)
            if not name:
                continue
            destination = target / Path(name)
            if entry.is_dir():
                destination.mkdir(parents=True, exist_ok=True)
            else:
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(zf.read(entry))


def _candidate(repo: Path, pkg: PackageInfo) -> dict:
    dist = repo / "dist" / f"{pkg.pkg_id}.tefpkg"
    info = pkg.info
    size = dist.stat().st_size if dist.exists() else 0
    return {
        "pkgId": pkg.pkg_id,
        "name": pkg.name,
        "author": pkg.author,
        "version": pkg.version,
        "versionCode": pkg.version_code,
        "brieflyDescribe": str(info.get("brieflyDescribe", info.get("description", ""))),
        "features": info.get("features", []),
        "sizeCategory": str(info.get("sizeCategory", "TINY")),
        "stableVerified": bool(info.get("stableVerified", False)),
        "experimental": bool(info.get("experimental", False)),
        "deprecated": bool(info.get("deprecated", False)),
        "iconUrl": "",
        "downloadUrl": f"{RELEASE_BASE_URL}/{pkg.pkg_id}.tefpkg",
        "downloadCount": 0,
        "publishedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "fileSize": _format_size(size),
        "sha256": _sha256(dist) if dist.exists() else "",
        "updateLog": "",
    }


def _prompt_duplicate(pkg: PackageInfo, existing: dict, source: Path) -> str:
    print(f"重复包名：{pkg.pkg_id}")
    print(f"  新包: version={pkg.version} versionCode={pkg.version_code} main.lua={pkg.main_mtime} source={source}")
    print(f"  旧包: version={existing.get('version', '?')} versionCode={existing.get('versionCode', '?')} "
          f"main.lua={existing.get('mainMtime', '?')} size={existing.get('size', '?')} "
          f"sha256={existing.get('sha256', '?')}")
    while True:
        answer = input("选择 [n]新包/[k]保留旧包/[s]跳过: ").strip().lower()
        if answer in {"n", "k", "s"}:
            return answer


def _load_index(repo: Path) -> dict:
    path = repo / "index.json"
    if not path.exists():
        return {"updatedAt": "", "loaderMinVersionCode": 37, "loaderMinVersion": "2.3.3", "mods": []}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise PackageRejected(f"invalid index.json: {exc}") from exc


def import_packages(repo_dir: Path, inputs: Iterable[Path], *, interactive: bool = True) -> ImportReport:
    repo = Path(repo_dir)
    repo.mkdir(parents=True, exist_ok=True)
    report = ImportReport()
    index = _load_index(repo)
    by_id = {item.get("pkgId"): item for item in index.get("mods", [])}
    paths = []
    for item in inputs:
        item = Path(item)
        if item.is_dir():
            paths.extend(sorted(p for p in item.rglob("*") if p.is_file() and p.suffix.lower() in {".zip", ".tefpkg"}))
        else:
            paths.append(item)
    for source in paths:
        try:
            pkg = scan_package(source)
            existing = by_id.get(pkg.pkg_id)
            if existing:
                report.duplicates += 1
                if not interactive:
                    report.errors.append(f"duplicate skipped: {pkg.pkg_id} ({source})")
                    continue
                decision = _prompt_duplicate(pkg, existing, source)
                if decision != "n":
                    if decision == "s":
                        report.errors.append(f"duplicate skipped: {pkg.pkg_id} ({source})")
                    continue
            package_dir = repo / "packages" / pkg.pkg_id
            dist_path = repo / "dist" / f"{pkg.pkg_id}.tefpkg"
            _extract_package(source, package_dir)
            _normalize_zip(source, dist_path)
            by_id[pkg.pkg_id] = _candidate(repo, pkg)
            report.accepted += 1
        except PackageSkipped as exc:
            report.skipped_native += 1
            report.errors.append(f"native skipped: {source}: {exc}")
        except (PackageRejected, ValueError, OSError) as exc:
            report.rejected += 1
            report.errors.append(f"rejected: {source}: {exc}")
    index["mods"] = sorted(by_id.values(), key=lambda item: item.get("pkgId", ""))
    index.pop("packages", None)
    index["loaderMinVersionCode"] = 37
    index["loaderMinVersion"] = "2.3.3"
    index["updatedAt"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    (repo / "index.json").write_text(json.dumps(index, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


def pack_packages(repo_dir: Path, output_dir: Path) -> list[Path]:
    repo = Path(repo_dir)
    output = Path(output_dir)
    output.mkdir(parents=True, exist_ok=True)
    assets = []
    for info_path in sorted((repo / "packages").glob("*/Info.json")) if (repo / "packages").exists() else []:
        pkg_id = json.loads(info_path.read_text(encoding="utf-8")).get("pkgId")
        if not isinstance(pkg_id, str) or not PKG_ID_RE.fullmatch(pkg_id):
            raise PackageRejected(f"invalid package id in {info_path}")
        asset = output / f"{pkg_id}.tefpkg"
        _normalize_directory(info_path.parent, asset)
        assets.append(asset)
    return assets


def rebuild_index(repo_dir: Path, download_counts: dict[str, int] | None = None,
                  asset_hashes: dict[str, str] | None = None,
                  asset_sizes: dict[str, int] | None = None) -> dict:
    repo = Path(repo_dir)
    counts = download_counts or {}
    hashes = asset_hashes or {}
    sizes = asset_sizes or {}
    current = _load_index(repo)
    previous = {item.get("pkgId"): item for item in current.get("mods", [])}
    now = datetime.now(timezone.utc)
    now_text = now.isoformat().replace("+00:00", "Z")
    packages = []
    for info_path in sorted((repo / "packages").glob("*/Info.json")) if (repo / "packages").exists() else []:
        package_dir = info_path.parent
        try:
            info = json.loads(info_path.read_text(encoding="utf-8"))
            manifest = json.loads((package_dir / "Manifest.json").read_text(encoding="utf-8"))
            config_name = _manifest_file(manifest)
            luamod = json.loads((package_dir / config_name).read_text(encoding="utf-8"))
            pkg_id = str(info["pkgId"])
            main_name = str(luamod.get("main", "main.lua"))
            main_candidates = [package_dir / main_name, package_dir / "Resources/lib" / main_name]
            main = next((p for p in main_candidates if p.is_file()), None)
            if main is None:
                matches = sorted(package_dir.rglob(Path(main_name).name))
                main = matches[0] if matches else None
            if main is None:
                continue
            dist = repo / "dist" / f"{pkg_id}.tefpkg"
            size = dist.stat().st_size if dist.exists() else 0
            published_at = previous.get(pkg_id, {}).get("publishedAt", now_text)
            packages.append({
                "pkgId": pkg_id,
                "name": str(info.get("name", pkg_id)),
                "author": str(info.get("author", "")),
                "version": str(info.get("version", luamod.get("version", "0.0.0"))),
                "versionCode": int(info.get("versionCode", luamod.get("version_code", 0))),
                "brieflyDescribe": str(info.get("brieflyDescribe", info.get("description", ""))),
                "features": info.get("features", []),
                "sizeCategory": str(info.get("sizeCategory", "TINY")),
                "stableVerified": bool(info.get("stableVerified", False)),
                "experimental": bool(info.get("experimental", False)),
                "deprecated": bool(info.get("deprecated", False)),
                "iconUrl": "",
                "downloadUrl": f"{RELEASE_BASE_URL}/{pkg_id}.tefpkg",
                "downloadCount": max(0, int(counts.get(pkg_id, 0))),
                "publishedAt": published_at,
                "fileSize": _format_size(sizes.get(pkg_id, size)),
                "sha256": hashes.get(pkg_id, _sha256(dist) if dist.exists() else ""),
                "updateLog": "",
            })
        except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError):
            continue
    cutoff = now - timedelta(days=NEW_MOD_PROMOTION_DAYS)

    def sort_key(item: dict) -> tuple[int, float, int, str]:
        try:
            published = datetime.fromisoformat(str(item["publishedAt"]).replace("Z", "+00:00"))
        except (KeyError, TypeError, ValueError):
            published = datetime.min.replace(tzinfo=timezone.utc)
        recent = published >= cutoff
        return (0 if recent else 1, -published.timestamp() if recent else 0,
                -item["downloadCount"], item["pkgId"])

    packages.sort(key=sort_key)
    result = {
        "loaderMinVersionCode": 37,
        "loaderMinVersion": "2.3.3",
        "updatedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "mods": packages,
    }
    (repo / "index.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return result


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=default_repo())
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("init")
    for name in ("add", "import"):
        command = sub.add_parser(name)
        command.add_argument("inputs", nargs="+", type=Path)
        command.add_argument("--non-interactive", action="store_true")
    sub.add_parser("list")
    remove = sub.add_parser("remove")
    remove.add_argument("pkg_id")
    sub.add_parser("rebuild-index")
    pack = sub.add_parser("pack")
    pack.add_argument("output", type=Path)
    sync = sub.add_parser("sync-github")
    sync.add_argument("--remote-url", help="GitHub repository URL")
    sync.add_argument("--remote", default="origin")
    sync.add_argument("--branch", default="main")
    sync.add_argument("--push", action="store_true", help="push after local commit")
    repo_add = sub.add_parser("repo-add")
    repo_add.add_argument("url")
    install = sub.add_parser("install")
    install.add_argument("pkg_id")
    install.add_argument("--target", type=Path)
    return parser


def _git(repo: Path, *args: str, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], cwd=repo, text=True, capture_output=True, check=check)


def sync_github(repo: Path, remote_url: str | None, remote: str, branch: str, push: bool) -> str:
    if not (repo / ".git").exists():
        _git(repo, "init", "-b", branch)
    rebuild_index(repo)
    _git(repo, "add", "-A")
    status = _git(repo, "diff", "--cached", "--quiet", check=False)
    if status.returncode != 0:
        _git(repo, "commit", "-m", "chore: update LuaLoader Mod repository")
    if remote_url:
        remotes = _git(repo, "remote", check=True).stdout.split()
        if remote in remotes:
            _git(repo, "remote", "set-url", remote, remote_url)
        else:
            _git(repo, "remote", "add", remote, remote_url)
    if push:
        if not remote_url and remote not in _git(repo, "remote").stdout.split():
            raise RuntimeError("no GitHub remote configured; pass --remote-url")
        _git(repo, "push", "-u", remote, branch)
        return f"pushed {remote}/{branch}"
    return f"prepared local commit; remote={remote} push={'enabled' if push else 'disabled'}"


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    repo = args.repo.expanduser()
    if args.command == "init":
        (repo / "packages").mkdir(parents=True, exist_ok=True)
        (repo / "dist").mkdir(parents=True, exist_ok=True)
        rebuild_index(repo)
        print(f"initialized {repo}")
        return 0
    if args.command in {"add", "import"}:
        report = import_packages(repo, args.inputs, interactive=not args.non_interactive)
        print(f"accepted={report.accepted} native-skipped={report.skipped_native} rejected={report.rejected} duplicates={report.duplicates}")
        for message in report.errors:
            print(message, file=sys.stderr)
        return 0 if not report.rejected else 2
    if args.command == "list":
        for item in _load_index(repo).get("mods", []):
            print(f"{item.get('pkgId')}\t{item.get('version')}\t{item.get('name')}")
        return 0
    if args.command == "remove":
        target = repo / "packages" / args.pkg_id
        dist = repo / "dist" / f"{args.pkg_id}.tefpkg"
        if target.exists():
            shutil.rmtree(target)
        if dist.exists():
            dist.unlink()
        rebuild_index(repo)
        return 0
    if args.command == "rebuild-index":
        rebuild_index(repo)
        return 0
    if args.command == "pack":
        assets = pack_packages(repo, args.output.expanduser())
        print("\n".join(str(asset) for asset in assets))
        return 0
    if args.command == "sync-github":
        try:
            print(sync_github(repo, args.remote_url, args.remote, args.branch, args.push))
            return 0
        except (OSError, RuntimeError, subprocess.CalledProcessError) as exc:
            print(f"sync failed: {exc}", file=sys.stderr)
            return 2
    if args.command == "repo-add":
        config = Path("~/.config/lualoader/modrepo.json").expanduser()
        config.parent.mkdir(parents=True, exist_ok=True)
        data = {}
        if config.exists():
            try:
                data = json.loads(config.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                data = {}
        repositories = data.setdefault("repositories", [])
        if args.url not in repositories:
            repositories.append(args.url)
        config.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"added repository {args.url} to {config}")
        return 0
    if args.command == "install":
        source = repo / "packages" / args.pkg_id
        if not source.is_dir():
            print(f"package not found: {args.pkg_id}", file=sys.stderr)
            return 2
        target_root = (args.target or Path("~/.local/share/lualoader-modrepo/installed")).expanduser()
        target = target_root / args.pkg_id
        if target.exists():
            print(f"install target exists: {target}; remove it explicitly before reinstalling", file=sys.stderr)
            return 2
        shutil.copytree(source, target)
        print(f"installed {args.pkg_id} -> {target}")
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
