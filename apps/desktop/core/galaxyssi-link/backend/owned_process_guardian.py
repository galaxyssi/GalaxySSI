"""Launch nothing until the parent has assigned this process to its Windows job."""
from __future__ import annotations

import os
import subprocess
import sys


def main():
    if len(sys.argv) < 3 or os.read(0, 1) != b"G":
        return 125
    child = subprocess.Popen(sys.argv[2:], stdin=sys.stdin if sys.argv[1] == "pipe" else subprocess.DEVNULL,
                             stdout=sys.stdout, stderr=sys.stderr)
    return child.wait()


if __name__ == "__main__":
    raise SystemExit(main())
