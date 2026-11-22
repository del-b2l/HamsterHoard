# HamsterHoard — minimal two-week implementation

A deliberately small Godot 4 + C++17 project implementing the proposal's core:
- TSP solved by a genetic algorithm (permutation chromosomes, tournament selection,
  ordered crossover, swap/inversion mutation, elitism).
- OpenMP parallel fitness evaluation and offspring generation within each island.
- MPI island model: one population per rank, ring migration of the best route.
- Godot 3D viewer/controller: launches the MPI executable and visualizes snapshots.
- CSV timing output for sequential (1 rank × 1 thread), OpenMP, MPI and hybrid runs.

This is a starter project, not a claim that the large proposal-scale workload has already
been benchmarked. Start with the small defaults, validate correctness, then scale up.

## Requirements

- Godot 4.x (standard build; no .NET needed)
- C++17 compiler
- CMake 3.16+
- MPI implementation (Open MPI or MPICH)
- OpenMP support in the compiler

Linux/Ubuntu packages (example):
```bash
sudo apt update
sudo apt install build-essential cmake libopenmpi-dev openmpi-bin
```

Windows: install a C++ toolchain, CMake, and an MPI distribution such as Microsoft MPI.
The Godot launcher currently uses `mpiexec -n` on Windows and `mpirun -np` elsewhere.
You may need to adjust the launcher arguments for your MPI distribution.

## Build the engine

From the repository root:
```bash
cmake -S engine -B engine/build -DCMAKE_BUILD_TYPE=Release
cmake --build engine/build --config Release -j
```

Executable:
- Linux/macOS: `engine/build/hamsterhoard`
- Windows: `engine/build/Release/hamsterhoard.exe` (depending on generator)

## Run the Godot application

1. Open `godot/project.godot` in Godot.
2. Run the project.
3. In the left panel, set the engine executable path if your build output differs.
4. Set MPI processes, OpenMP threads, cities, population/island and generations.
5. Press **Start**. Godot launches the MPI program and polls a JSON snapshot file.
6. Press **Stop** to request a graceful stop at a generation boundary.

The initial defaults are intentionally small so the project is easy to test. The Godot
scene is a minimal 3D visualization, not a full game. It draws the best route and city
markers, and shows per-rank fitness values when available.

## Manual command-line runs / benchmarking

Run these from the repository root (Linux examples):

Sequential baseline:
```bash
mpirun -np 1 ./engine/build/hamsterhoard --cities 300 --population 500 --generations 300 --threads 1 --seed 42 --csv results.csv
```

OpenMP:
```bash
mpirun -np 1 ./engine/build/hamsterhoard --cities 300 --population 500 --generations 300 --threads 2 --seed 42 --csv results.csv
mpirun -np 1 ./engine/build/hamsterhoard --cities 300 --population 500 --generations 300 --threads 4 --seed 42 --csv results.csv
```

MPI:
```bash
mpirun -np 2 ./engine/build/hamsterhoard --cities 300 --population 500 --generations 300 --threads 1 --seed 42 --csv results.csv
```

Hybrid:
```bash
mpirun -np 2 ./engine/build/hamsterhoard --cities 300 --population 500 --generations 300 --threads 2 --seed 42 --csv results.csv
```

The program appends one row per completed run to the CSV. Use identical city count,
population per island, generations and seed when comparing configurations. Run each
configuration several times and report mean/median time. Do not present example or
unmeasured values as results.

Add speedup and efficiency columns after collecting runs:
```bash
python3 benchmark/analyze_results.py results/benchmark.csv results/analysis.csv
```
The script uses the first 1-rank × 1-thread row as the sequential baseline.

MPI launch examples can require special flags in virtualized/root environments. Follow
your MPI distribution's local instructions rather than blindly adding flags.

## Stop behavior and snapshots

The C++ engine writes `snapshot.json` atomically (temporary file then rename) every
few generations when `--output` is supplied. Rank 0 is the coordinator and writes the
snapshot. MPI migration is performed by all ranks in a ring at the configured interval.
A `stop.flag` file requests a stop at the next generation boundary.

The Godot app writes those files in its `user://` directory. For a manual run, pass
your own `--output` and `--csv` paths.

## Scope and honest limitations

- The benchmark executable is the authoritative implementation of MPI/OpenMP.
  Godot's own threads are not used as a substitute.
- MPI ranks are islands; OpenMP threads work inside each rank.
- The visualization is deliberately lightweight and uses representative colony
  markers, not one rendered hamster per GA individual.
- TSP is NP-hard. GA results are heuristic, not guaranteed optimal.
- For 5,000–10,000 cities and 10,000+ individuals per island, memory/runtime can
  become very large. Increase sizes gradually and profile before attempting the
  proposal's maximum values.
- The first version sends snapshots through a shared local file rather than live
  sockets. This keeps the two-week deliverable buildable and integrated: Godot
  launches, controls and monitors the computation. If time remains, replace the
  file bridge with TCP.
- This project is a starter implementation. Understand, test, document and adapt
  every part before submission; be prepared to explain it in the viva.
