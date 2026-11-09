"""Regression test: the hook installed by scripts/install_hooks.sh must work
when the commit is made from a linked git worktree.

In a linked worktree `.git` is a file, not a directory, so a hook that builds
`$(git rev-parse --show-toplevel)/.git/hooks/...` fails with "Not a
directory" and blocks every commit made from the worktree.

Run: python3 -m pytest scripts/tests/test_install_hooks.py
"""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parent.parent
INSTALLER = SCRIPTS / "install_hooks.sh"

# Stands in for the real bump so the test proves the wrapper reached it.
BUMP_STUB = '#!/bin/bash\ntouch "$(git rev-parse --show-toplevel)/bumped"\n'


def _git(cwd: Path, *args: str) -> subprocess.CompletedProcess[str]:
    """Run git in ``cwd`` with a fixed identity; never raises."""
    env = {
        **os.environ,
        "GIT_AUTHOR_NAME": "t",
        "GIT_AUTHOR_EMAIL": "t@t",
        "GIT_COMMITTER_NAME": "t",
        "GIT_COMMITTER_EMAIL": "t@t",
    }
    return subprocess.run(
        ["git", *args], cwd=cwd, env=env, capture_output=True, text=True, check=False
    )


def _make_repo(root: Path) -> None:
    """Create a minimal repo with an empty pre-commit config and a bump stub."""
    root.mkdir()
    (root / "scripts").mkdir()
    shutil.copy(INSTALLER, root / "scripts" / "install_hooks.sh")
    bump = root / "scripts" / "bump_patch_version.sh"
    bump.write_text(BUMP_STUB)
    bump.chmod(0o755)
    (root / ".pre-commit-config.yaml").write_text("repos: []\n")
    (root / ".gitignore").write_text("bumped\n")
    _git(root, "init", "-q", "-b", "main")
    _git(root, "add", "-A")
    assert _git(root, "commit", "-q", "--no-verify", "-m", "init").returncode == 0


@pytest.mark.skipif(shutil.which("pre-commit") is None, reason="needs pre-commit")
def test_hook_runs_from_linked_worktree(tmp_path: Path) -> None:
    """A commit from a linked worktree passes the gates and reaches the bump."""
    main = tmp_path / "main"
    _make_repo(main)
    installed = subprocess.run(
        ["bash", "scripts/install_hooks.sh"],
        cwd=main,
        capture_output=True,
        text=True,
        check=False,
    )
    assert installed.returncode == 0, installed.stderr

    wt = tmp_path / "wt"
    assert _git(main, "worktree", "add", "-q", "-b", "feat", str(wt)).returncode == 0
    (wt / "a.txt").write_text("a\n")
    _git(wt, "add", "a.txt")
    commit = _git(wt, "commit", "-q", "-m", "a")

    assert commit.returncode == 0, commit.stderr
    assert "Not a directory" not in commit.stderr
    assert (wt / "bumped").exists()


@pytest.mark.skipif(shutil.which("pre-commit") is None, reason="needs pre-commit")
def test_installer_runs_from_linked_worktree(tmp_path: Path) -> None:
    """Running the installer inside a worktree installs the shared hook."""
    main = tmp_path / "main"
    _make_repo(main)
    wt = tmp_path / "wt"
    assert _git(main, "worktree", "add", "-q", "-b", "feat", str(wt)).returncode == 0

    installed = subprocess.run(
        ["bash", "scripts/install_hooks.sh"],
        cwd=wt,
        capture_output=True,
        text=True,
        check=False,
    )

    assert installed.returncode == 0, installed.stderr
    assert (main / ".git" / "hooks" / "pre-commit.pre-commit-generated").exists()
