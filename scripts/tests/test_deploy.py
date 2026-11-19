"""scripts/deploy.sh must exit non-zero unless its own health check passes.

adb and phone_deploy.sh are stubbed so every path runs without a phone:
the stub adb answers from a state dir, and each test flips one fact
(phone gone, pack missing, app crashed, app not running) to see the
deploy fail. The green path proves the same script exits 0 when all
facts hold.

The checkouts are real git repos: a bare origin, the live checkout (a clone,
like ~/src/lyricanki) and the deploying checkout (a git worktree of it, like
a board session's). phone_deploy refuses production builds from a worktree
(exit 49), so the deploy must build from the live checkout after pulling it,
and only when the pull lands exactly on the commit being deployed.

Run: python3 -m pytest scripts/tests/test_deploy.py
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

import pytest

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


def _git(cwd: Path, *args: str) -> str:
    return subprocess.run(
        ["git", "-C", str(cwd), *args],
        env={**os.environ, **GIT_ENV},
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()


def _commit(repo: Path, name: str, content: str | None = None) -> None:
    (repo / name).write_text(name if content is None else content)
    _git(repo, "add", name)
    _git(repo, "commit", "-q", "-m", name)


@pytest.fixture
def env(tmp_path: Path) -> dict[str, str]:
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
    _git(tmp_path, "clone", "-q", str(origin), str(live))
    _commit(live, ".gitignore", "android/key.properties\n")
    _git(live, "push", "-q", "origin", "HEAD:main")
    (live / "android").mkdir()
    (live / "android" / "key.properties").write_text("storeFile=x\n")
    app = tmp_path / "app"
    _git(live, "worktree", "add", "-q", "--detach", str(app))
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


def _run(env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(DEPLOY)],
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )


def _calls(env: dict[str, str]) -> str:
    calls = Path(env["FAKE_ADB_STATE"]) / "calls"
    return calls.read_text() if calls.exists() else ""


def test_green_path_exits_zero_and_never_wipes(env: dict[str, str]) -> None:
    res = _run(env)
    assert res.returncode == 0, res.stdout + res.stderr
    calls = _calls(env)
    assert f"phone_deploy {env['LIVE_CHECKOUT']} --release" in calls
    assert "uninstall" not in calls and "pm clear" not in calls


def test_pulls_live_checkout_up_to_the_pushed_commit(env: dict[str, str]) -> None:
    """The board pushed from its worktree; the live checkout is one behind."""
    app, live = Path(env["DEPLOY_REPO_ROOT"]), Path(env["LIVE_CHECKOUT"])
    _commit(app, "feature")
    _git(app, "push", "-q", "origin", "HEAD:main")
    res = _run(env)
    assert res.returncode == 0, res.stdout + res.stderr
    assert _git(live, "rev-parse", "HEAD") == _git(app, "rev-parse", "HEAD")


def test_unpushed_commit_never_ships(env: dict[str, str]) -> None:
    _commit(Path(env["DEPLOY_REPO_ROOT"]), "unpushed")
    res = _run(env)
    assert res.returncode != 0
    assert "not on origin" in res.stderr
    assert "phone_deploy" not in _calls(env)


def test_uncommitted_edit_in_live_checkout_never_ships(env: dict[str, str]) -> None:
    (Path(env["LIVE_CHECKOUT"]) / ".gitignore").write_text("wip\n")
    res = _run(env)
    assert res.returncode != 0
    assert "uncommitted" in res.stderr
    assert "phone_deploy" not in _calls(env)


def test_diverged_live_checkout_fails_and_names_it(env: dict[str, str]) -> None:
    """Live has a local commit and origin moved on: ff-only cannot pull."""
    app = Path(env["DEPLOY_REPO_ROOT"])
    _commit(app, "feature")
    _git(app, "push", "-q", "origin", "HEAD:main")
    _commit(Path(env["LIVE_CHECKOUT"]), "local-only")
    res = _run(env)
    assert res.returncode != 0
    assert "cannot fast-forward" in res.stderr
    assert "phone_deploy" not in _calls(env)


def test_live_checkout_ahead_of_origin_never_ships(env: dict[str, str]) -> None:
    _commit(Path(env["LIVE_CHECKOUT"]), "local-only")
    res = _run(env)
    assert res.returncode != 0
    assert "local commits" in res.stderr
    assert "phone_deploy" not in _calls(env)


def test_missing_release_key_fails(env: dict[str, str]) -> None:
    (Path(env["LIVE_CHECKOUT"]) / "android" / "key.properties").unlink()
    res = _run(env)
    assert res.returncode != 0
    assert "phone_deploy" not in _calls(env)


def test_second_run_is_idempotent(env: dict[str, str]) -> None:
    assert _run(env).returncode == 0
    res = _run(env)
    assert res.returncode == 0, res.stdout + res.stderr


def test_phone_unplugged_fails(env: dict[str, str]) -> None:
    (Path(env["FAKE_ADB_STATE"]) / "online").unlink()
    res = _run(env)
    assert res.returncode != 0
    assert "phone_deploy" not in _calls(env)


def test_missing_pack_fails_before_touching_phone(env: dict[str, str]) -> None:
    Path(env["LYRICANKI_PACK"]).unlink()
    env["LIVE_CHECKOUT"] = env["FAKE_ADB_STATE"]  # no pack fallback there
    res = _run(env)
    assert res.returncode != 0
    assert _calls(env) == ""


def test_crash_on_launch_fails(env: dict[str, str]) -> None:
    (Path(env["FAKE_ADB_STATE"]) / "crash").touch()
    assert _run(env).returncode != 0


def test_app_not_running_fails(env: dict[str, str]) -> None:
    (Path(env["FAKE_ADB_STATE"]) / "running").unlink()
    assert _run(env).returncode != 0


def test_build_failure_fails(env: dict[str, str]) -> None:
    (Path(env["FAKE_ADB_STATE"]) / "build_fails").touch()
    assert _run(env).returncode != 0


def test_install_not_updated_fails(env: dict[str, str]) -> None:
    pd = Path(env["PHONE_DEPLOY"])
    pd.write_text("#!/bin/bash\nexit 0\n")
    assert _run(env).returncode != 0


def test_crash_followed_by_long_log_fails(env: dict[str, str]) -> None:
    """A real logcat keeps writing after the match; SIGPIPE must not hide it."""
    (Path(env["FAKE_ADB_STATE"]) / "crash").touch()
    (Path(env["FAKE_ADB_STATE"]) / "noisy").touch()
    assert _run(env).returncode != 0
