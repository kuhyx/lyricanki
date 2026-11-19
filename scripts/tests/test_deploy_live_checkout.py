"""scripts/deploy.sh builds from the live checkout, and only pushed code.

phone_deploy refuses production builds from a worktree (exit 49), so the
deploy pulls ~/src/lyricanki --ff-only and builds there, only when the pull
lands on a commit that contains the deploying checkout's HEAD, with no tracked edits.

Run: python3 -m pytest scripts/tests/test_deploy_live_checkout.py
"""

from __future__ import annotations

from pathlib import Path

from deploy_harness import calls, commit, git, run_deploy


def test_pulls_live_checkout_up_to_the_pushed_commit(env: dict[str, str]) -> None:
    """The board pushed from its worktree; the live checkout is one behind."""
    app, live = Path(env["DEPLOY_REPO_ROOT"]), Path(env["LIVE_CHECKOUT"])
    commit(app, "feature")
    git(app, "push", "-q", "origin", "HEAD:main")
    res = run_deploy(env)
    assert res.returncode == 0, res.stdout + res.stderr
    assert git(live, "rev-parse", "HEAD") == git(app, "rev-parse", "HEAD")


def test_unpushed_commit_never_ships(env: dict[str, str]) -> None:
    commit(Path(env["DEPLOY_REPO_ROOT"]), "unpushed")
    res = run_deploy(env)
    assert res.returncode != 0
    assert "not on origin" in res.stderr
    assert "phone_deploy" not in calls(env)


def test_uncommitted_edit_in_live_checkout_never_ships(env: dict[str, str]) -> None:
    (Path(env["LIVE_CHECKOUT"]) / ".gitignore").write_text("wip\n")
    res = run_deploy(env)
    assert res.returncode != 0
    assert "uncommitted" in res.stderr
    assert "phone_deploy" not in calls(env)


def test_diverged_live_checkout_fails_and_names_it(env: dict[str, str]) -> None:
    """Live has a local commit and origin moved on: ff-only cannot pull."""
    app = Path(env["DEPLOY_REPO_ROOT"])
    commit(app, "feature")
    git(app, "push", "-q", "origin", "HEAD:main")
    commit(Path(env["LIVE_CHECKOUT"]), "local-only")
    res = run_deploy(env)
    assert res.returncode != 0
    assert "cannot fast-forward" in res.stderr
    assert "phone_deploy" not in calls(env)


def test_live_checkout_ahead_of_origin_never_ships(env: dict[str, str]) -> None:
    commit(Path(env["LIVE_CHECKOUT"]), "local-only")
    res = run_deploy(env)
    assert res.returncode != 0
    assert "local commits" in res.stderr
    assert "phone_deploy" not in calls(env)


def test_missing_release_key_fails(env: dict[str, str]) -> None:
    (Path(env["LIVE_CHECKOUT"]) / "android" / "key.properties").unlink()
    res = run_deploy(env)
    assert res.returncode != 0
    assert "phone_deploy" not in calls(env)


def test_origin_moved_past_the_deployed_commit_still_ships(env: dict[str, str], tmp_path: Path) -> None:
    """Another push lands after ours: the newer origin HEAD contains our commit, so deploy it."""
    live = Path(env["LIVE_CHECKOUT"])
    other = tmp_path / "other"
    git(tmp_path, "clone", "-q", git(live, "remote", "get-url", "origin"), str(other))
    commit(other, "later")
    git(other, "push", "-q", "origin", "HEAD:main")
    res = run_deploy(env)
    assert res.returncode == 0, res.stdout + res.stderr
    assert git(live, "rev-parse", "HEAD") == git(other, "rev-parse", "HEAD")
