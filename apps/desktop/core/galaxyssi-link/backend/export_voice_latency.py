"""Export content-free GalaxySSI voice latency diagnostics."""
from __future__ import annotations

import argparse
from pathlib import Path

from voice_latency import voice_latency_tracer


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        help="Optional destination for the redacted JSON report.",
    )
    args = parser.parse_args()
    destination = voice_latency_tracer().export_content_free_diagnostics(args.output)
    print(destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

