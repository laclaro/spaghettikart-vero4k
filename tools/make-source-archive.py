#!/usr/bin/env python3
"""Builds a self-contained source archive for building SpaghettiKart for the Vero 4K+ without network access.

The archive holds:
- the committed files of this folder (build scripts, patches, launcher, README),
- SpaghettiKart, libultraship and Torch at the commits in patches/BASE, as shallow git repositories
  (SpaghettiKart reaches back to its last tag, which `git describe` needs for the version string),
- mirrors/: a minimal bare repository for every git repository the build clones (CMake FetchContent, Torch's
  sub-build and their submodules), holding just the pinned tag or commit, and mirrors/gitconfig, which redirects
  the original URLs to those mirrors. build.sh uses it when mirrors/ exists; `./build.sh --offline` also cuts the
  network.
- downloads/: the single headers the build downloads (sse2neon, semver, stb_image).
- VERSION: the release (git describe of this folder), for the package version.

The list of repositories comes from a finished build in build/vero (run ./build.sh first). Everything is copied
from local clones; no network is needed. Not included: the Vero sysroot and the game data (see README.md).

usage: tools/make-source-archive.py [output.tar.gz]
"""
import datetime
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SK = os.path.join(ROOT, "source", "SpaghettiKart")
BUILD = os.path.join(ROOT, "build", "vero")
NAME = "spaghettikart-vero"
WORK = "/work"  # where build.sh mounts this folder in the build container
DOWNLOADS = ["sse2neon/sse2neon.h", "semver/semver.hpp", "stb/stb_image.h"]


def git(*args, cwd=None, capture=True):
    result = subprocess.run(["git", *args], cwd=cwd, check=True, text=True,
                            stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else None


def read_base():
    base = {}
    with open(os.path.join(ROOT, "patches", "BASE")) as f:
        for line in f:
            if line.strip() and not line.startswith("#"):
                repo, commit = line.split()[:2]
                base[repo] = commit
    return base


def shallow_repo(src, commit, dest, url, with_tag=False):
    """Creates dest as a git repository checked out at commit, fetched from the local repository src."""
    depth = 1
    tag = None
    if with_tag:
        tag = git("describe", "--tags", "--abbrev=0", commit, cwd=src)
        depth = int(git("rev-list", "--count", f"{tag}..{commit}", cwd=src)) + 1
    os.makedirs(dest, exist_ok=True)
    git("init", "-q", dest)
    git("-c", "protocol.version=2", "fetch", "-q", f"--depth={depth}", f"file://{src}", commit, cwd=dest)
    if tag:
        git("fetch", "-q", f"--depth={depth}", f"file://{src}", f"refs/tags/{tag}:refs/tags/{tag}", cwd=dest)
    git("-c", "advice.detachedHead=false", "checkout", "-q", commit, cwd=dest)
    git("remote", "add", "origin", url, cwd=dest)


def submodules(repo):
    """(url, commit, checkout) for the submodules of repo, recursively."""
    if not os.path.exists(os.path.join(repo, ".gitmodules")):
        return []
    # Exit status 1 means no matches (some repositories ship an empty .gitmodules).
    found = subprocess.run(["git", "config", "-f", ".gitmodules", "--get-regexp", r"^submodule\..*\.(path|url)$"],
                           cwd=repo, text=True, stdout=subprocess.PIPE)
    if found.returncode not in (0, 1):
        sys.exit(f"cannot read {repo}/.gitmodules")
    entries = {}
    for line in found.stdout.splitlines():
        key, value = line.split(maxsplit=1)
        name, field = key[len("submodule."):].rsplit(".", 1)
        entries.setdefault(name, {})[field] = value
    result = []
    for entry in entries.values():
        commit = git("ls-tree", "HEAD", entry["path"], cwd=repo).split()[2]
        checkout = os.path.join(repo, entry["path"])
        result.append((entry["url"], commit, checkout))
        result += submodules(checkout)
    return result


def fetched_repositories():
    """(url, ref, local clone) for every repository CMake cloned in the build, including nested submodules."""
    repos = []
    for top, _, files in os.walk(BUILD):
        for name in files:
            if not name.endswith("-gitclone.cmake"):
                continue
            text = open(os.path.join(top, name)).read()
            url = re.search(r'clone --no-checkout.*"([^"]+)" "([^"]+)"', text)  # the last two arguments
            ref = re.search(r'checkout "([^"]+)" --', text)
            # The clone goes to <deps dir>/<name>-src; the script sits in <deps dir>/<name>-subbuild/...
            deps_dir = top.split("-subbuild")[0].rsplit("/", 1)[0]
            clone = os.path.join(deps_dir, url.group(2))
            repos.append((url.group(1), ref.group(1), clone))
            repos += submodules(clone)
    return repos


def mirror_path(url):
    return re.sub(r"^[a-z]+://", "", url).rstrip("/").removesuffix(".git") + ".git"


def add_mirror(mirrors, url, ref, clone):
    """Adds ref (a tag, branch or commit) from the local clone to the minimal bare mirror for url."""
    dest = os.path.join(mirrors, mirror_path(url))
    if not os.path.exists(dest):
        os.makedirs(dest)
        git("init", "-q", "--bare", dest)
    src = f"file://{clone}"
    for spec in (f"refs/tags/{ref}:refs/tags/{ref}", f"refs/heads/{ref}:refs/heads/{ref}"):
        if subprocess.run(["git", "fetch", "-q", "--depth=1", src, spec], cwd=dest,
                          stderr=subprocess.DEVNULL).returncode == 0:
            return
    # A commit: fetch it and keep a branch on it, so clones of the mirror contain it.
    git("-c", "protocol.version=2", "fetch", "-q", "--depth=1", src, ref, cwd=dest)
    git("update-ref", f"refs/heads/pinned-{ref}", ref, cwd=dest)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        ROOT, f"{NAME}-src-{datetime.date.today():%Y%m%d}.tar.gz")
    if not os.path.isdir(BUILD):
        sys.exit("build/vero is missing: run ./build.sh first (the fetched repositories are read from it)")
    if git("status", "--porcelain", "--untracked-files=no", cwd=ROOT):
        print("warning: uncommitted changes in this folder are not included", file=sys.stderr)

    base = read_base()
    torch = git("ls-tree", base["SpaghettiKart"], "torch", cwd=SK).split()[2]

    with tempfile.TemporaryDirectory() as stage:
        dest = os.path.join(stage, NAME)
        os.makedirs(dest)
        archive = subprocess.run(["git", "archive", "HEAD"], cwd=ROOT, check=True, stdout=subprocess.PIPE).stdout
        subprocess.run(["tar", "-x", "-C", dest], input=archive, check=True)
        # Without git history, tools/make-deb.sh takes the package version from here.
        version = subprocess.run(["git", "describe", "--tags", "--match", "[0-9]*"], cwd=ROOT, text=True,
                                 stdout=subprocess.PIPE)
        if version.returncode == 0:
            with open(os.path.join(dest, "VERSION"), "w") as f:
                f.write(version.stdout)

        src = os.path.join(dest, "source", "SpaghettiKart")
        shallow_repo(SK, base["SpaghettiKart"], src, "https://github.com/HarbourMasters/SpaghettiKart",
                     with_tag=True)
        shallow_repo(os.path.join(SK, "libultraship"), base["libultraship"], os.path.join(src, "libultraship"),
                     "https://github.com/Kenix3/libultraship")
        shallow_repo(os.path.join(SK, "torch"), torch, os.path.join(src, "torch"),
                     "https://github.com/HarbourMasters/Torch")

        mirrors = os.path.join(dest, "mirrors")
        config = ["# Redirects the repositories the build clones to the local mirrors (written by",
                  "# tools/make-source-archive.py, used by build.sh).",
                  "[protocol \"file\"]", "\tallow = always"]
        repos = fetched_repositories()
        urls = sorted({url for url, _, _ in repos})
        # insteadOf rewrites URL prefixes: one URL must not start with another.
        for a in urls:
            for b in urls:
                if a != b and b.startswith(a):
                    sys.exit(f"{a} is a prefix of {b}; the mirror redirection would mix them up")
        for url, ref, clone in repos:
            add_mirror(mirrors, url, ref, clone)
            print(f"mirror {url} {ref}")
        for url in urls:
            config += [f'[url "file://{WORK}/mirrors/{mirror_path(url)}"]', f"\tinsteadOf = {url}"]
        with open(os.path.join(mirrors, "gitconfig"), "w") as f:
            f.write("\n".join(config) + "\n")

        # Single files the build downloads with file(DOWNLOAD); build.sh copies them into build/vero/_deps, where
        # the patched build finds them and skips the download.
        for name in DOWNLOADS:
            target = os.path.join(dest, "downloads", name)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            shutil.copy(os.path.join(BUILD, "_deps", name), target)

        with tarfile.open(out, "w:gz") as tar:
            tar.add(dest, arcname=NAME)
    print(f"{out}: {os.path.getsize(out) / 2**20:.0f} MiB")


if __name__ == "__main__":
    main()
