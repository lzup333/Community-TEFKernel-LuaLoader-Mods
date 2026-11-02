# Fixed Release Download Ranking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Store Mod packages as assets of one fixed GitHub Release and sort the TEFManager index by GitHub asset download counts.

**Architecture:** `packages/` remains the source tree. A reusable Python pack/index helper creates temporary `.tefpkg` files, the scheduled/push workflow manages the fixed Release, and the index generator reads Release asset counts through the GitHub API.

**Tech Stack:** Python 3 standard library, GitHub Actions, GitHub CLI/API, JSON.

**Spec:** `docs/superpowers/specs/2026-11-02-release-asset-download-ranking.md`

## Global Constraints

- Fixed Release tag is `mod-repository`.
- Release Asset names are `<pkgId>.tefpkg`.
- `dist/` is temporary and ignored; no package binaries are committed.
- Index sorting is `downloadCount` descending, then `pkgId` ascending.
- Scheduled rebuild runs every five hours.

## Review Focus

- Missing Release or missing Asset: create/recover the Release and treat count as zero.
- Asset names that do not map to a valid package id: ignore them without corrupting the index.
- GitHub API pagination/rate errors: fail the workflow rather than publishing a partial index.
- Package update with an existing asset: upload with replacement and preserve the stable URL.
- Empty package repository: generate a valid empty `mods` index.

### Task 1: Package source and index model

**Files:**
- Modify: `tools/lualoader_modrepo.py`
- Modify: `.gitignore`
- Modify: `README.md`

**Interfaces:**
- Produce `pack_packages(repo, output_dir) -> list[Path]`.
- Produce `rebuild_index(repo, download_counts=None) -> dict`.

- [ ] Make package-directory packing produce normalized `.tefpkg` files in a caller-provided temporary directory.
- [ ] Add `downloadCount` to each index entry and sort by count then `pkgId`.
- [ ] Change generated URLs to the fixed Release Asset URL.
- [ ] Ignore `dist/` and document that it is local temporary output.
- [ ] Run the existing available checks and inspect the generated index.

### Task 2: Fixed Release synchronization workflow

**Files:**
- Create: `.github/workflows/mod-repository.yml`
- Modify: `tools/lualoader_modrepo.py` or add a focused workflow helper if API logic is clearer

**Interfaces:**
- Consumes `packages/`, fixed tag `mod-repository`, and `GITHUB_TOKEN`.
- Produces Release Assets and a sorted `index.json` commit.

- [ ] Add push and `0 */5 * * *` schedule triggers.
- [ ] On push, package source directories and upload all assets with replacement.
- [ ] On schedule, query Release assets and rebuild only the index.
- [ ] Use `contents: write` and fail on incomplete API results.
- [ ] Run YAML/static checks locally.

### Task 3: Remove repository binaries and verify

**Files:**
- Delete: tracked `dist/*.tefpkg`
- Modify: `index.json`

- [ ] Rebuild the index with zero counts and Release Asset URLs.
- [ ] Remove tracked binary packages while retaining local generation support.
- [ ] Verify no tracked `dist/` or temporary test files remain.
- [ ] Commit and push the implementation.

