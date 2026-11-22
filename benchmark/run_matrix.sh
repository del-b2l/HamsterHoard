#!/usr/bin/env bash
set -euo pipefail
BIN="${1:-./engine/build/hamsterhoard}"
CSV="${2:-results/benchmark.csv}"
CITIES="${CITIES:-300}"
POP="${POP:-500}"
GEN="${GEN:-300}"
SEED="${SEED:-42}"
mkdir -p "$(dirname "$CSV")"
run() {
  local ranks="$1" threads="$2"
  echo "Running MPI ranks=$ranks OpenMP threads/rank=$threads"
  mpirun -np "$ranks" "$BIN" --cities "$CITIES" --population "$POP" \
    --generations "$GEN" --threads "$threads" --seed "$SEED" --csv "$CSV"
}
run 1 1
run 1 2
run 1 4
run 2 1
run 4 1
run 2 2
echo "Measurements appended to $CSV"
