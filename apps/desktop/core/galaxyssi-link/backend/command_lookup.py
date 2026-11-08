"""Reuse executable lookup within one request, never across configuration changes."""
from contextlib import contextmanager
from contextvars import ContextVar
import os
import shutil

_lookups = ContextVar("desktop_command_lookups", default=None)


@contextmanager
def command_lookup_scope():
    if _lookups.get() is not None:
        yield
        return
    token = _lookups.set({})
    try:
        yield
    finally:
        _lookups.reset(token)


def which(command: str) -> str | None:
    cache = _lookups.get()
    if cache is None:
        return shutil.which(command)
    key = (command, os.environ.get("PATH", ""), os.environ.get("PATHEXT", ""), os.getcwd())
    if key not in cache:
        cache[key] = shutil.which(command)
    return cache[key]
