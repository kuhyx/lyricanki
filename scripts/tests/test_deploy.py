"""scripts/deploy.sh must exit non-zero unless its own health check passes.

adb and phone_deploy.sh are stubbed so every path runs without a phone:
the stub adb answers from a state dir, and each test flips one fact
(phone gone, pack missing, app crashed, app not running) to see the
deploy fail. The green path proves the same script exits 0 when all
facts hold.

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
    && echo "Process: $FAKE_PKG, PID: 4242"; exit 0 ;;
  *) exit 0 ;;
esac
"""

# Stub phone_deploy.sh: a successful install bumps lastUpdateTime.
FAKE_PHONE_DEPLOY = r"""#!/bin/bash
echo "phone_deploy $*" >> "$FAKE_ADB_STATE/calls"
[[ -f $FAKE_ADB_STATE/build_fails ]] && exit 34
date +%s%N > "$FAKE_ADB_STATE/installed"
"""


@pytest.fixture
def env(tmp_path: Path) -> dict[str, str]:
    """Isolated PATH, state dir, pack and live checkout for one run."""
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
    live = tmp_path / "live"
    (live / "android").mkdir(parents=True)
    (live / "android" / "key.properties").write_text("storeFile=x\n")
    app = tmp_path / "app"
    (app / "android").mkdir(parents=True)
    return {
        **os.environ,
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
    assert "phone_deploy" in calls and "--release" in calls
    assert "uninstall" not in calls and "pm clear" not in calls
    key = Path(env["DEPLOY_REPO_ROOT"]) / "android" / "key.properties"
    assert key.stat().st_mode & 0o777 == 0o600


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
