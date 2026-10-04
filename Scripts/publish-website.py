#!/usr/bin/env python3
"""Publish only the public HTML/CSS pages to the existing origin/gh-pages site."""
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "docs/app-store/web"
FILES = ["index.html", "styles.css"] + [
    f"{kind}-{language}.html"
    for kind in ("privacy", "support")
    for language in ("uk", "en", "ru")
]


def git(*args, data=None, env=None):
    return subprocess.check_output(
        ["git", *args], cwd=ROOT, input=data, env=env
    ).decode().strip()


def main():
    payloads = {name: (SITE / name).read_bytes() for name in FILES}
    for name, payload in payloads.items():
        if name.endswith(".html") and any(
            marker in payload
            for marker in (b"data-publication-pending", b"data-contact-pending")
        ):
            raise SystemExit(f"Unfinished publication details: {name}")
    payloads[".nojekyll"] = b""

    remote = git("ls-remote", "origin", "refs/heads/gh-pages")
    parent = None
    if remote:
        git("fetch", "origin", "gh-pages")
        parent = git("rev-parse", "FETCH_HEAD")

    # A temporary index leaves the working branch and normal staging area intact.
    with tempfile.TemporaryDirectory(prefix="bookreign-pages-") as directory:
        env = dict(os.environ, GIT_INDEX_FILE=str(Path(directory) / "index"))
        git("read-tree", "--empty", env=env)
        for name, payload in sorted(payloads.items()):
            blob = git("hash-object", "-w", "--stdin", data=payload)
            git("update-index", "--add", "--cacheinfo", f"100644,{blob},{name}", env=env)
        tree = git("write-tree", env=env)

    if parent and git("rev-parse", f"{parent}^{{tree}}") == tree:
        print(f"Website is already up to date: {parent}")
        return
    parents = ["-p", parent] if parent else []
    commit = git("commit-tree", tree, *parents, "-m", "Publish Bookreign support and privacy pages")
    # Never force-push: concurrent website updates must be reviewed first.
    git("push", "origin", f"{commit}:refs/heads/gh-pages")
    print(f"Published website commit: {commit}")
    print("GitHub Pages must use branch gh-pages and folder / in repository settings.")


if __name__ == "__main__":
    main()
