param(
    [int]$Repetitions = 5
)

$ErrorActionPreference = "Stop"

if ($Repetitions -lt 1 -or $Repetitions -gt 5) {
    throw "Repetitions must be between 1 and 5 because the script uses five fixed seeds."
}

# Run this script from a Visual Studio Developer PowerShell/Command Prompt
# environment, or from a PowerShell session where MSVC, MPI, and CMake are available.

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Exe = Join-Path $ProjectRoot "engine\build\Release\hamsterhoard.exe"
$ResultsDir = Join-Path $ProjectRoot "results"

if (-not (Test-Path $Exe)) {
    throw "Executable not found: $Exe`nBuild the engine first with: cmake --build engine/build --config Release"
}

$MpiCommand = Get-Command mpiexec.exe -ErrorAction Stop
$MpiExec = $MpiCommand.Source
if (-not $MpiExec) { $MpiExec = $MpiCommand.Name }

New-Item -ItemType Directory -Force -Path $ResultsDir | Out-Null

# Configurations: total workers = MPI ranks * OpenMP threads per rank.
# This CPU has 2 physical cores and 4 logical processors; 4-worker
# configurations are useful to test but may not scale linearly.
$Configurations = @(
    [pscustomobject]@{ Ranks = 1; Threads = 1 },
    [pscustomobject]@{ Ranks = 1; Threads = 2 },
    [pscustomobject]@{ Ranks = 1; Threads = 4 },
    [pscustomobject]@{ Ranks = 2; Threads = 1 },
    [pscustomobject]@{ Ranks = 2; Threads = 2 },
    [pscustomobject]@{ Ranks = 4; Threads = 1 }
)

# Fixed workload for all configurations.
$Cities = 500
$TotalPopulation = 300
$Generations = 750
$Seeds = 42, 43, 44, 45, 46

$RawCsv = Join-Path $ResultsDir "full_benchmark_raw.csv"
$SummaryCsv = Join-Path $ResultsDir "full_benchmark_summary.csv"
$Rows = [System.Collections.Generic.List[object]]::new()

function Invoke-HamsterHoardRun {
    param(
        [int]$Ranks,
        [int]$Threads,
        [int]$Seed,
        [string]$Label
    )

    $Snapshot = Join-Path $ResultsDir ("benchmark_snapshot_r{0}_t{1}_{2}.json" -f $Ranks, $Threads, $Label)
    $StopFile = "$Snapshot.stop"
    if (Test-Path $StopFile) { Remove-Item $StopFile -Force }

    $PopulationPerRank = [int]($TotalPopulation / $Ranks)
    if (($PopulationPerRank * $Ranks) -ne $TotalPopulation) {
        throw "Total population $TotalPopulation must be divisible by MPI ranks ($Ranks)."
    }

    Write-Host ("  Run: MPI={0}, threads/rank={1}, population/rank={2}, seed={3} ({4})" -f $Ranks, $Threads, $PopulationPerRank, $Seed, $Label)

    $OutputLines = & $MpiExec -n $Ranks $Exe `
        --cities $Cities `
        --population $PopulationPerRank `
        --generations $Generations `
        --threads $Threads `
        --seed $Seed

    $ExitCode = $LASTEXITCODE
    $OutputText = ($OutputLines | ForEach-Object { "$_" }) -join "`n"

    if ($ExitCode -ne 0) {
        Write-Host $OutputText
        throw "HamsterHoard exited with code $ExitCode for MPI=$Ranks, threads/rank=$Threads, seed=$Seed."
    }

    $Match = [regex]::Match(
        $OutputText,
        'elapsed_s=([0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)\s+best=([0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)'
    )

    if (-not $Match.Success) {
        Write-Host $OutputText
        throw "Could not parse elapsed_s and best distance from the engine output."
    }

    # Remove the visualization snapshot so the results folder stays tidy.
    # The engine's reported elapsed time is read before this cleanup.
    if (Test-Path $Snapshot) { Remove-Item $Snapshot -Force }
    if (Test-Path $StopFile) { Remove-Item $StopFile -Force }

    return [pscustomobject]@{
        mpi_ranks       = $Ranks
        threads_per_rank = $Threads
        total_workers   = $Ranks * $Threads
        population_per_rank = $PopulationPerRank
        total_population = $PopulationPerRank * $Ranks
        seed            = $Seed
        run_label       = $Label
        elapsed_s       = [double]::Parse($Match.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture)
        best_distance   = [double]::Parse($Match.Groups[2].Value, [Globalization.CultureInfo]::InvariantCulture)
    }
}

Write-Host ""
Write-Host "HamsterHoard full benchmark"
Write-Host "CPU: 2 physical cores / 4 logical processors"
Write-Host "Workload: $Cities cities, total population $TotalPopulation across ranks, $Generations generations"
Write-Host "Measured runs: $($Configurations.Count * $Repetitions)"
Write-Host "Results folder: $ResultsDir"
Write-Host ""

# Warm-up once per configuration; warm-up runs are not included in CSV.
foreach ($Config in $Configurations) {
    Write-Host ("Warm-up: MPI={0}, threads/rank={1}" -f $Config.Ranks, $Config.Threads)
    $null = Invoke-HamsterHoardRun -Ranks $Config.Ranks -Threads $Config.Threads -Seed 41 -Label "warmup"
}

# Delete old raw output so this run is a clean benchmark batch.
if (Test-Path $RawCsv) { Remove-Item $RawCsv -Force }

foreach ($Config in $Configurations) {
    Write-Host ""
    Write-Host ("=== MPI {0} x OpenMP {1} ===" -f $Config.Ranks, $Config.Threads)

    foreach ($Seed in $Seeds | Select-Object -First $Repetitions) {
        $Row = Invoke-HamsterHoardRun -Ranks $Config.Ranks -Threads $Config.Threads -Seed $Seed -Label "seed$Seed"
        $Rows.Add($Row)

        # Save after every run so partial results survive an interruption.
        $Rows | Export-Csv -Path $RawCsv -NoTypeInformation -Encoding UTF8
    }
}

$BaselineRows = @($Rows | Where-Object { $_.mpi_ranks -eq 1 -and $_.threads_per_rank -eq 1 })
$BaselineMean = ($BaselineRows | Measure-Object -Property elapsed_s -Average).Average

$Summary = [System.Collections.Generic.List[object]]::new()

foreach ($Config in $Configurations) {
    $GroupRows = @($Rows | Where-Object {
        $_.mpi_ranks -eq $Config.Ranks -and $_.threads_per_rank -eq $Config.Threads
    })

    $Times = @($GroupRows | ForEach-Object { [double]$_.elapsed_s } | Sort-Object)
    $MeanTime = ($Times | Measure-Object -Average).Average
    $MeanBest = ($GroupRows | Measure-Object -Property best_distance -Average).Average
    $MedianTime = if ($Times.Count % 2 -eq 1) {
        $Times[[int](($Times.Count - 1) / 2)]
    } else {
        ($Times[($Times.Count / 2) - 1] + $Times[$Times.Count / 2]) / 2
    }

    $SumSquares = 0.0
    foreach ($Time in $Times) { $SumSquares += [Math]::Pow(($Time - $MeanTime), 2) }
    $StdDev = if ($Times.Count -gt 1) { [Math]::Sqrt($SumSquares / ($Times.Count - 1)) } else { 0.0 }

    $Speedup = $BaselineMean / $MeanTime
    $Workers = $Config.Ranks * $Config.Threads
    $Efficiency = ($Speedup / $Workers) * 100.0

    $Summary.Add([pscustomobject]@{
        mpi_ranks          = $Config.Ranks
        threads_per_rank   = $Config.Threads
        total_workers      = $Workers
        total_population    = $TotalPopulation
        population_per_rank = [int]($TotalPopulation / $Config.Ranks)
        repetitions        = $GroupRows.Count
        mean_time_s        = [Math]::Round($MeanTime, 6)
        median_time_s      = [Math]::Round($MedianTime, 6)
        std_dev_s          = [Math]::Round($StdDev, 6)
        speedup            = [Math]::Round($Speedup, 4)
        efficiency_percent  = [Math]::Round($Efficiency, 2)
        mean_best_distance = [Math]::Round($MeanBest, 4)
    })
}

$Summary | Export-Csv -Path $SummaryCsv -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "=== Benchmark summary ==="
$Summary | Format-Table mpi_ranks, threads_per_rank, total_workers, mean_time_s, median_time_s, std_dev_s, speedup, efficiency_percent, mean_best_distance -AutoSize

Write-Host ""
Write-Host "Raw results:     $RawCsv"
Write-Host "Summary results: $SummaryCsv"
Write-Host "Benchmark complete."
