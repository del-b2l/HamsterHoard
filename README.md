# HamsterHoard 🐹

**A hybrid parallel Genetic Algorithm for the Traveling Salesman Problem (TSP)**

HamsterHoard is a parallel-computing project that solves the Traveling Salesman Problem using a Genetic Algorithm (GA). The project combines **MPI** and **OpenMP** to explore parallel execution and performance improvements.

The C++ engine performs the genetic algorithm computations, while Godot 4 provides a 3D visualization of the cities and the best route found.

## Features

- Genetic Algorithm for the Traveling Salesman Problem
- MPI island model with multiple populations
- Periodic migration of individuals between MPI ranks
- OpenMP parallelization within MPI ranks
- Hybrid MPI + OpenMP execution
- C++ engine integrated with Godot 4
- JSON snapshot communication between the engine and Godot
- Benchmarking of sequential and parallel configurations
- Runtime, speedup, and parallel efficiency analysis

## Project Architecture

HamsterHoard consists of three main components:

### 1. C++ Genetic Algorithm Engine

The engine implements the Genetic Algorithm using:

- Population initialization
- Tournament selection
- Ordered crossover
- Mutation
- Elitism
- Fitness evaluation based on route distance

Each individual represents a possible route through the cities.

### 2. MPI and OpenMP

MPI is used to implement an island model. Each MPI rank maintains its own population and periodically exchanges individuals with other ranks.

OpenMP parallelizes computationally intensive work within each MPI rank.

The project supports:

- Sequential execution
- OpenMP execution
- MPI execution
- Hybrid MPI + OpenMP execution

### 3. Godot 4 Visualization

Godot is used to visualize the TSP problem in 3D.

The C++ engine communicates with Godot through a JSON snapshot file. The engine writes information about the current best solution, and Godot reads the snapshot to update the visualization.

## Technologies Used

- C++
- MPI / Microsoft MPI
- OpenMP
- CMake
- Godot 4
- GDScript
- JSON
- PowerShell

## Requirements

The project was developed and tested on Windows.

Required software:

- Windows 10 or Windows 11
- Visual Studio Build Tools with the C++ build tools
- MSVC C++ compiler
- CMake
- Microsoft MPI
- Godot 4

Make sure the following commands are available in your development environment:

```bash
cmake --version
cl
mpiexec
```

## Building the C++ Engine

### 1. Clone the repository

```bash
git clone <YOUR_GITHUB_REPOSITORY_URL>
cd HamsterHoard
```

Replace the repository URL with your GitHub repository URL.

### 2. Configure the project

Open the **Developer Command Prompt for Visual Studio**.

Navigate to the project directory:

```bat
cd /d path\to\HamsterHoard
```

Configure the CMake project:

```bat
cmake -S engine -B engine/build
```

### 3. Build the Release version

```bat
cmake --build engine/build --config Release
```

After a successful build, the executable should be located at:

```text
engine/build/Release/hamsterhoard.exe
```

## Running the Engine

### Sequential execution

Run the engine with one MPI rank and one OpenMP thread:

```bat
engine\build\Release\hamsterhoard.exe --cities 80 --population 120 --generations 200 --threads 1 --seed 42
```

### OpenMP execution

Run with one MPI rank and two OpenMP threads:

```bat
engine\build\Release\hamsterhoard.exe --cities 80 --population 120 --generations 200 --threads 2 --seed 42
```

### MPI execution

Run with two MPI ranks and one thread per rank:

```bat
mpiexec -n 2 engine\build\Release\hamsterhoard.exe --cities 80 --population 60 --generations 200 --threads 1 --seed 42
```

### Hybrid MPI + OpenMP execution

Run with two MPI ranks and two OpenMP threads per rank:

```bat
mpiexec -n 2 engine\build\Release\hamsterhoard.exe --cities 80 --population 60 --generations 200 --threads 2 --seed 42
```

In MPI execution, the population value is the population maintained by each rank. Therefore, the total population is:

**Total population = MPI ranks × population per rank**

## JSON Snapshot for Godot

The engine can write JSON snapshots for the Godot visualization.

Example:

```bat
engine\build\Release\hamsterhoard.exe --cities 80 --population 120 --generations 200 --threads 1 --seed 42 --output snapshot.json
```

The snapshot file is created or updated by the C++ engine during execution, depending on the snapshot-writing configuration.

Godot reads the JSON snapshot to obtain information about the current best route and update the visualization.

Make sure the output path used by the C++ engine matches the path expected by the Godot project.

## Benchmarking

The project includes benchmark scripts for comparing sequential and parallel execution.

The benchmark evaluates different MPI and OpenMP configurations using a fixed workload.

Example workload:

| Parameter | Value |
|---|---:|
| Cities | 500 |
| Total population | 300 |
| Generations | 750 |
| Seeds | 42–51 |

The benchmark configurations include:

- 1 MPI rank × 1 thread
- 1 MPI rank × 2 threads
- 1 MPI rank × 4 threads
- 2 MPI ranks × 1 thread
- 2 MPI ranks × 2 threads
- 4 MPI ranks × 1 thread

Benchmark results are analyzed using runtime, speedup, and parallel efficiency.

### Performance Metrics

Speedup is calculated as:

**Speedup = Sequential runtime / Parallel runtime**

Parallel efficiency is calculated as:

**Efficiency = Speedup / Number of workers × 100%**

The benchmark measures the C++ engine separately from Godot rendering. Snapshot writing is disabled during performance measurements to reduce file I/O overhead.

## Hardware

The benchmark environment used:

- CPU: Intel Core i7-7600U
- Physical cores: 2
- Logical processors: 4
- Operating system: Windows
- Compiler: MSVC
- Build configuration: Release

Performance results may vary depending on the hardware, compiler, operating system, and system load.

## Results

The project evaluates the performance of sequential and parallel execution using:

- Runtime comparison
- Speedup graph
- Parallel efficiency graph

The results demonstrate how MPI and OpenMP affect performance and how communication overhead, synchronization, and hardware limitations influence parallel scaling.

Benchmark CSV files and graphs are available in the project's results directory.

## Repository Structure

```text
HamsterHoard/
├── engine/
│   ├── CMakeLists.txt
│   └── source files
├── godot/
│   ├── project.godot
│   ├── scenes/
│   └── scripts/
├── benchmark/
│   └── benchmark scripts
├── results/
│   ├── CSV files
│   └── performance graphs
├── docs/
├── README.md
└── .gitignore
```

The exact folder structure may vary depending on the final project organization.

## Future Improvements

- Improve parallel scalability
- Optimize MPI migration
- Improve visualization performance
- Add more benchmark workloads
- Explore alternative Genetic Algorithm operators

## Authors

HamsterHoard was developed as a university parallel-computing project.

**Team members:**
- Me
- Myself
- I

## License

This project was developed for educational purposes.