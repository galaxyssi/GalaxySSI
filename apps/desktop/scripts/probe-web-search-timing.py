"""Collect truthful search-phase timings in isolated state; live sources are opt-in."""
from __future__ import annotations

import argparse
import contextlib
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import threading
import time


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--query", action="append", default=[])
    parser.add_argument("--samples", type=int, default=5)
    parser.add_argument("--timeout", type=float, default=5)
    args = parser.parse_args()
    if not 1 <= args.samples <= 100 or not 1 <= args.timeout <= 60:
        parser.error("Use 1-100 samples and a 1-60 second source budget")
    if args.live and not args.query:
        parser.error("Live sources require an explicit --query")
    backend = Path(__file__).resolve().parents[1] / "core/galaxyssi-link/backend"
    sys.path.insert(0, str(backend))
    from web_intelligence import RawSearchResult, WebIntelligenceService

    root = Path(tempfile.mkdtemp(prefix="galaxyssi-web-timing-"))
    records = []
    print(json.dumps({"report_directory": str(root), "live_network": args.live}), flush=True)
    queries = args.query if args.live else ["\u641c\u7d22\u622a\u6b62\u65f6\u95f4\u9a8c\u8bc1"] * args.samples
    for index, query in enumerate(queries):
        service = WebIntelligenceService(root / str(index), credentials={})
        entered, release, finished = threading.Event(), threading.Event(), threading.Event()
        if not args.live:
            class FastSource:
                def search(self, *_args):
                    if not entered.wait(5):
                        raise RuntimeError("Controlled source did not start")
                    return [RawSearchResult("bing", 1, "Timing fixture", "https://example.com/evidence", "Fixture only")]
            class SlowSource:
                def search(self, *_args):
                    entered.set()
                    try:
                        release.wait(30)
                        return []
                    finally:
                        finished.set()
            service.engines["bing"] = FastSource()
            service.engines["duckduckgo"] = SlowSource()
        with contextlib.closing(service.store._connect()) as connection:
            synchronous = connection.execute("PRAGMA synchronous").fetchone()[0]
        started = time.perf_counter()
        try:
            result = service.search({"query": query, "engines": ["bing", "duckduckgo"],
                                     "engine_fanout": 2, "limit": 5, "use_cache": False,
                                     "timeout_seconds": args.timeout if args.live else 1})
            row = {"sample": index, "live_network": args.live, "synthetic_sources": not args.live,
                   "query_sha256": hashlib.sha256(query.encode()).hexdigest(),
                   "observed_elapsed_ms": round((time.perf_counter() - started) * 1000, 3),
                   "synchronous": synchronous, "status": result["status"],
                   "results": len(result["results"]), "timing": result["metadata"]["response_timing"],
                   "receipts": [{key: receipt.get(key) for key in ("source_id", "status", "error_code", "duration_millis")}
                                for receipt in result["receipts"]]}
            if not args.live:
                row["slow_finished_before_return"] = finished.is_set()
            records.append(row)
            (root / "report.json").write_text(json.dumps({"records": records}, indent=2), encoding="utf-8")
            print(json.dumps(row), flush=True)
        finally:
            release.set()
            if not args.live and not finished.wait(5):
                raise RuntimeError("Controlled source did not stop")
    if args.live:
        return 0 if all(row["results"] > 0 for row in records) else 1
    return 0 if all(not row["slow_finished_before_return"] and row["status"] == "partial" for row in records) else 1


if __name__ == "__main__":
    raise SystemExit(main())
