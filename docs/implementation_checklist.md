# Two-week implementation checklist

## Must-have (submit only after tested)
- [ ] Build the C++ engine with CMake, MPI and OpenMP.
- [ ] Validate that every chromosome is a permutation of city IDs.
- [ ] Validate fitness against a hand-computed small route.
- [ ] Run 1 MPI rank × 1 OpenMP thread as sequential baseline.
- [ ] Run OpenMP with 2 and 4 threads.
- [ ] Run MPI with 2 and 4 ranks (subject to hardware).
- [ ] Run at least one hybrid configuration.
- [ ] Verify migration exchanges valid routes and does not deadlock.
- [ ] Open the Godot project and confirm the 3D scene runs.
- [ ] Confirm Godot launches the engine and receives snapshots.
- [ ] Export CSV measurements from repeated runs.
- [ ] Calculate speedup and efficiency from measured data.
- [ ] Write report and prepare to explain each algorithm component.

## Nice-to-have only if time remains
- [ ] Replace snapshot-file bridge with TCP.
- [ ] Add hamster models and animations.
- [ ] Add route convergence chart in Godot.
- [ ] Add experiment-history screen.
- [ ] Add TSPLIB dataset import.
