"""scripts/deploy.sh must exit non-zero unless its own health check passes.

Each test flips one fact (phone gone, pack missing, app crashed, app not
running) and expects a red deploy; the green path expects exit 0. The stubs
and git repos live in deploy_harness.py.

Run: python3 -m pytest scripts/tests/test_deploy.py
"""

from __future__ import annotations

from pathlib import Path

from deploy_harness import calls, run_deploy


def test_green_path_exits_zero_and_never_wipes(env: dict[str, str]) -> None:
    res = run_deploy(env)
    assert res.returncode == 0, res.stdout + res.stderr
    log = calls(env)
    assert f"phone_deploy {env['LIVE_CHECKOUT']} --release" in log
    assert "uninstall" not in log and "pm clear" not in log


def test_second_run_is_idempotent(env: dict[str, str]) -> None:
    assert run_deploy(env).returncode == 0
    res = run_deploy(env)
    assert res.returncode == 0, res.stdout + res.stderr


def test_phone_unplugged_fails(env: dict[str, str]) -> None:
    (Path(env["FAKE_ADB_STATE"]) / "online").unlink()
    res = run_deploy(env)
    assert res.returncode != 0
    assert "phone_deploy" not in calls(env)


def test_missing_pack_fails_before_touching_phone(env: dict[str, str]) -> None:
    Path(env["LYRICANKI_PACK"]).unlink()
    env["LIVE_CHECKOUT"] = env["FAKE_ADB_STATE"]  # no pack fallback there
    res = run_deploy(env)
    assert res.returncode != 0
    assert calls(env) == ""


def test_crash_on_launch_fails(env: dict[str, str]) -> None:
    (Path(env["FAKE_ADB_STATE"]) / "crash").touch()
    assert run_deploy(env).returncode != 0


def test_app_not_running_fails(env: dict[str, str]) -> None:
    (Path(env["FAKE_ADB_STATE"]) / "running").unlink()
    assert run_deploy(env).returncode != 0


def test_build_failure_fails(env: dict[str, str]) -> None:
    (Path(env["FAKE_ADB_STATE"]) / "build_fails").touch()
    assert run_deploy(env).returncode != 0


def test_install_not_updated_fails(env: dict[str, str]) -> None:
    pd = Path(env["PHONE_DEPLOY"])
    pd.write_text("#!/bin/bash\nexit 0\n")
    assert run_deploy(env).returncode != 0


def test_crash_followed_by_long_log_fails(env: dict[str, str]) -> None:
    """A real logcat keeps writing after the match; SIGPIPE must not hide it."""
    (Path(env["FAKE_ADB_STATE"]) / "crash").touch()
    (Path(env["FAKE_ADB_STATE"]) / "noisy").touch()
    assert run_deploy(env).returncode != 0
