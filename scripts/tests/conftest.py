"""Fixtures for the scripts/deploy.sh tests; the harness lives in deploy_harness.py."""

from __future__ import annotations

from typing import TYPE_CHECKING

import pytest
from deploy_harness import make_env

if TYPE_CHECKING:
    from pathlib import Path


@pytest.fixture
def env(tmp_path: Path) -> dict[str, str]:
    """Isolated PATH, state dir, pack, origin, live checkout and worktree."""
    return make_env(tmp_path)
