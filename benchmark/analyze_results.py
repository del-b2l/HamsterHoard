#!/usr/bin/env python3
"""Add speedup and efficiency columns using the 1-rank/1-thread baseline."""
import csv
import sys
from pathlib import Path

if len(sys.argv) != 3:
    raise SystemExit("Usage: python3 benchmark/analyze_results.py input.csv output.csv")

source, destination = map(Path, sys.argv[1:])
with source.open(newline="") as f:
    rows = list(csv.DictReader(f))

baselines = [float(r["elapsed_seconds"]) for r in rows
             if int(r["mpi_processes"]) == 1 and int(r["omp_threads"]) == 1]
if not baselines:
    raise SystemExit("No sequential baseline row (mpi_processes=1, omp_threads=1) found.")
baseline = baselines[0]

fields = list(rows[0].keys()) + ["speedup", "efficiency_percent"]
with destination.open("w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=fields)
    writer.writeheader()
    for row in rows:
        elapsed = float(row["elapsed_seconds"])
        workers = int(row["mpi_processes"]) * int(row["omp_threads"])
        speedup = baseline / elapsed if elapsed > 0 else 0.0
        efficiency = 100.0 * speedup / workers if workers > 0 else 0.0
        row["speedup"] = f"{speedup:.6f}"
        row["efficiency_percent"] = f"{efficiency:.3f}"
        writer.writerow(row)
print(f"Wrote {destination}; baseline={baseline:.6f}s")
