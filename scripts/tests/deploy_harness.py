"""Shared harness for the scripts/deploy.sh tests (stub adb, stub phone_deploy, git repos).
scripts/deploy.sh must exit non-zero unless its own health check passes.

adb and phone_deploy.sh are stubbed so every path runs without a phone:
the stub adb answers from a state dir, and each test flips one fact
(phone gone, pack missing, app crashed, app not running) to see the
deploy fail. The green path proves the same script exits 0 when all
facts hold.

The checkouts are real git repos: a bare origin, the live checkout (a clone,
like ~/src/lyricanki) and the deploying checkout (a git worktree of it, like
a board session's). phone_deploy refuses production builds from a worktree
(exit 49), so the deploy must build from the live checkout after pulling it,
and only when the pulled HEAD contains the commit being deployed.

Run: python3 -m pytest scripts/tests/test_deploy*.py
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent
DEPLOY = SCRIPTS / "deploy.sh"
SERIAL = "TESTSERIAL"
PKG = "com.kuhy.lyricanki"

# Stub adb: state lives in $FAKE_ADB_STATE; every call is logged.
FAKE_ADB = r"""#!/bin/bash
set -u
s="$FAKE_ADB_STATE"
echo "$*" >> "$s/calls"
[[ $1 == devices ]] && { echo "List of devices attached"; \
  [[ -f $s/online ]] && printf '%s\tdevice\n' "$FAKE_SERIAL"; exit 0; }
[[ $1 == -s ]] && shift 2
case "$*" in
  "shell dumpsys package "*)
    [[ -f $s/installed ]] && echo "    lastUpdateTime=$(cat "$s/installed")"; exit 0 ;;
  "shell pidof "*) [[ -f $s/running ]] && echo 4242; exit 0 ;;
  "shell stat -c %s "*) [[ -f $s/pushed ]] && cat "$s/pushed"; exit 0 ;;
  "push "*) stat -c %s "$2" > "$s/pushed"; exit 0 ;;
  "logcat -d"*) [[ -f $s/crash ]] && echo "FATAL EXCEPTION: main" \
    && echo "Process: $FAKE_PKG, PID: 4242" \
    && [[ -f $s/noisy ]] && seq 1 200000; exit 0 ;;
  *) exit 0 ;;
esac
"""

# Stub phone_deploy.sh: a successful install bumps lastUpdateTime. Like the
# real one, it refuses an app dir that is a git worktree (exit 49).
FAKE_PHONE_DEPLOY = r"""#!/bin/bash
echo "phone_deploy $*" >> "$FAKE_ADB_STATE/calls"
gd=$(git -C "$1" rev-parse --path-format=absolute --git-dir)
common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)
[[ $gd == "$common" ]] || { echo "refusing a worktree (exit 49)" >&2; exit 49; }
[[ -f $FAKE_ADB_STATE/build_fails ]] && exit 34
date +%s%N > "$FAKE_ADB_STATE/installed"
"""


GIT_ENV = {
    "GIT_AUTHOR_NAME": "t",
    "GIT_AUTHOR_EMAIL": "t@t",
    "GIT_COMMITTER_NAME": "t",
    "GIT_COMMITTER_EMAIL": "t@t",
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_CONFIG_NOSYSTEM": "1",
}


def git(cwd: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(cwd), *args],
        env={**os.environ, **GIT_ENV},
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()


def commit(repo: Path, name: str, content: str | None = None) -> None:
    (repo / name).write_text(name if content is None else content)
    git(repo, "add", name)
    git(repo, "commit", "-q", "-m", name)


def make_env(tmp_path: Path) -> dict[str, str]:
    """Isolated PATH, state dir, pack, origin, live checkout and worktree."""
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    adb = bin_dir / "adb"
    adb.write_text(FAKE_ADB)
    adb.chmod(0o755)
    pd = tmp_path / "phone_deploy.sh"
    pd.write_text(FAKE_PHONE_DEPLOY)
    pd.chmod(0o755)
    state = tmp_path / "state"
    state.mkdir()
    (state / "online").touch()
    (state / "installed").write_text("old\n")
    (state / "running").touch()
    pack = tmp_path / "lyricanki-es.sqlite"
    pack.write_bytes(b"x" * 1024)
    origin = tmp_path / "origin.git"
    subprocess.run(["git", "init", "-q", "--bare", "-b", "main", str(origin)], check=True)
    live = tmp_path / "live"
    git(tmp_path, "clone", "-q", str(origin), str(live))
    commit(live, ".gitignore", "android/key.properties\n")
    git(live, "push", "-q", "origin", "HEAD:main")
    (live / "android").mkdir()
    (live / "android" / "key.properties").write_text("storeFile=x\n")
    app = tmp_path / "app"
    git(live, "worktree", "add", "-q", "--detach", str(app))
    return {
        **os.environ,
        **GIT_ENV,
        "PATH": f"{bin_dir}:{os.environ['PATH']}",
        "FAKE_ADB_STATE": str(state),
        "FAKE_SERIAL": SERIAL,
        "FAKE_PKG": PKG,
        "DEPLOY_SERIAL": SERIAL,
        "LYRICANKI_PACK": str(pack),
        "PHONE_DEPLOY": str(pd),
        "LIVE_CHECKOUT": str(live),
        "DEPLOY_REPO_ROOT": str(app),
        "HEALTH_SETTLE_SECS": "0",
    }


def run_deploy(env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(DEPLOY)],
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )


def calls(env: dict[str, str]) -> str:
    calls = Path(env["FAKE_ADB_STATE"]) / "calls"
    return calls.read_text() if calls.exists() else ""
