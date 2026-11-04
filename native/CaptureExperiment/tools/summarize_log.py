#!/usr/bin/env python3
"""Summarize returned harness logs without confusing proxies with display metrics."""
import argparse
import json
import math
from pathlib import Path


def percentile(values, percent):
    if not values:
        return None
    values = sorted(values)
    return values[max(0, math.ceil(percent * len(values)) - 1)]


def summarize(rows):
    seeks = [row["latencyMilliseconds"] for row in rows
             if row.get("event") == "seekCompletion" and row.get("completed") is True]
    samples = [row for row in rows if row.get("event") == "resourceSample"]
    exports = [row for row in rows if row.get("event") in
               {"exportCompleted", "exportEnded", "exportInterrupted"}]
    memory = [row["physicalFootprintBytes"] for row in samples if "physicalFootprintBytes" in row]
    return {
        "sessions": [row for row in rows if row.get("event") == "session"],
        "seekCompletionOnly": {
            "count": len(seeks), "p50Ms": percentile(seeks, .5),
            "p95Ms": percentile(seeks, .95), "maxMs": max(seeks, default=None),
        },
        "seekToDisplayedFrame": "NOT MEASURED by this probe",
        "droppedDisplayedFrames": "NOT MEASURED by this probe",
        "sampledPeakPhysicalFootprintBytes": max(memory, default=None),
        "actualPeakMemory": "Requires Instruments; 1 Hz samples can miss peaks",
        "thermalStatesObserved": sorted({row["thermalState"] for row in samples
                                        if "thermalState" in row}),
        "resourceSampleCount": len(samples),
        "exportOutcomes": exports,
        "recoveryEvents": [row for row in rows if row.get("event") == "recovered"],
        "errors": [row for row in rows if row.get("event") in
                   {"error", "openFailure", "exportMarkerFailure"}],
        "verdict": "NO AUTOMATIC PASS: independent decode, display, recovery and device evidence required",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logs", nargs="+", type=Path)
    args = parser.parse_args()
    rows = []
    for path in args.logs:
        for number, line in enumerate(path.read_text().splitlines(), 1):
            if not line.strip():
                continue
            try:
                row = json.loads(line)
                if not isinstance(row, dict):
                    raise ValueError("Expected an object")
                rows.append(row)
            except (json.JSONDecodeError, ValueError) as error:
                raise SystemExit(f"{path}:{number}: invalid log: {error}")
    print(json.dumps(summarize(rows), indent=2, allow_nan=False))


if __name__ == "__main__":
    main()
