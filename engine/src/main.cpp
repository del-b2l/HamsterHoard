#include <mpi.h>
#include <omp.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <numeric>
#include <random>
#include <sstream>
#include <stdexcept>
#include <utility>
#include <string>
#include <vector>

struct City { double x = 0.0, y = 0.0; };
using Route = std::vector<int>;

struct Config {
    int cities = 80;
    int population = 120;
    int generations = 200;
    int threads = 1;
    int migration_interval = 25;
    int migration_count = 1;
    unsigned seed = 42;
    std::string output;
    std::string csv;
};

static Config parse_args(int argc, char** argv) {
    Config c;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto value = [&]() -> std::string {
            if (i + 1 >= argc) throw std::runtime_error("Missing value for " + a);
            return argv[++i];
        };
        if (a == "--cities") c.cities = std::stoi(value());
        else if (a == "--population") c.population = std::stoi(value());
        else if (a == "--generations") c.generations = std::stoi(value());
        else if (a == "--threads") c.threads = std::stoi(value());
        else if (a == "--migration-interval") c.migration_interval = std::stoi(value());
        else if (a == "--migration-count") c.migration_count = std::stoi(value());
        else if (a == "--seed") c.seed = static_cast<unsigned>(std::stoul(value()));
        else if (a == "--output") c.output = value();
        else if (a == "--csv") c.csv = value();
        else if (a == "--help") {
            std::cout << "--cities N --population N --generations N --threads N "
                         "--migration-interval N --migration-count N --seed N"
                         "--output FILE --csv FILE\n";
            std::exit(0);
        }
    }
    if (c.cities < 3 || c.population < 4 || c.generations < 1 || c.threads < 1)
        throw std::runtime_error("cities>=3, population>=4, generations>=1 and threads>=1 required");
    return c;
}

static double distance(const City& a, const City& b) {
    const double dx = a.x - b.x, dy = a.y - b.y;
    return std::sqrt(dx * dx + dy * dy);
}

static double fitness(const Route& r, const std::vector<City>& cities) {
    double total = 0.0;
    for (size_t i = 0; i < r.size(); ++i)
        total += distance(cities[r[i]], cities[r[(i + 1) % r.size()]]);
    return total;
}

static Route ordered_crossover(const Route& a, const Route& b, std::mt19937_64& rng) {
    const int n = static_cast<int>(a.size());
    std::uniform_int_distribution<int> pick(0, n - 1);
    int left = pick(rng), right = pick(rng);
    if (left > right) std::swap(left, right);
    Route child(n, -1);
    std::vector<bool> used(n, false);
    for (int i = left; i <= right; ++i) {
        child[i] = a[i];
        used[a[i]] = true;
    }
    int pos = (right + 1) % n;
    for (int k = 0; k < n; ++k) {
        const int gene = b[(right + 1 + k) % n];
        if (!used[gene]) {
            child[pos] = gene;
            used[gene] = true;
            pos = (pos + 1) % n;
        }
    }
    return child;
}

static void mutate(Route& r, std::mt19937_64& rng) {
    if (r.size() < 2) return;
    std::uniform_int_distribution<int> pick(0, static_cast<int>(r.size()) - 1);
    int a = pick(rng), b = pick(rng);
    if (a > b) std::swap(a, b);
    if (std::uniform_int_distribution<int>(0, 1)(rng) == 0) {
        std::swap(r[a], r[b]);                 // swap mutation
    } else {
        std::reverse(r.begin() + a, r.begin() + b + 1); // inversion mutation
    }
}

static int tournament(const std::vector<double>& scores, std::mt19937_64& rng) {
    std::uniform_int_distribution<int> pick(0, static_cast<int>(scores.size()) - 1);
    int best = pick(rng);
    for (int k = 0; k < 3; ++k) {
        const int candidate = pick(rng);
        if (scores[candidate] < scores[best]) best = candidate;
    }
    return best;
}

static void write_snapshot(const std::string& path, int generation, int rank,
                           double best, double average, const Route& route,
                           const std::vector<City>& cities, int world_size,
                           const std::vector<double>& rank_best) {
    if (path.empty()) return;
    const std::string temp = path + ".tmp";
    std::ofstream out(temp, std::ios::trunc);
    if (!out) return;
    out << std::setprecision(10);
    out << "{\"generation\":" << generation << ",\"rank\":" << rank
        << ",\"world_size\":" << world_size
        << ",\"best_distance\":" << best
        << ",\"average_distance\":" << average << ",\"best_route\":[";
    for (size_t i = 0; i < route.size(); ++i) {
        if (i) out << ',';
        out << route[i];
    }
    out << "],\"cities\":[";
    for (size_t i = 0; i < cities.size(); ++i) {
        if (i) out << ',';
        out << '[' << cities[i].x << ',' << cities[i].y << ']';
    }
    out << "],\"rank_best\":[";
    for (size_t i = 0; i < rank_best.size(); ++i) {
        if (i) out << ',';
        out << rank_best[i];
    }
    out << "]}";
    out.close();
    std::remove(path.c_str());
    std::rename(temp.c_str(), path.c_str());
}

int main(int argc, char** argv) {
    MPI_Init(&argc, &argv);
    int rank = 0, world = 1;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &world);

    int exit_code = 0;
    try {
        Config cfg = parse_args(argc, argv);
        omp_set_dynamic(0);
        omp_set_num_threads(cfg.threads);

        // Every rank creates the same city set; each rank gets a different population.
        std::mt19937_64 city_rng(cfg.seed);
        std::uniform_real_distribution<double> coord(0.0, 100.0);
        std::vector<City> cities(cfg.cities);
        for (auto& c : cities) { c.x = coord(city_rng); c.y = coord(city_rng); }

        std::mt19937_64 init_rng(cfg.seed + 1009u * static_cast<unsigned>(rank));
        Route base(cfg.cities);
        std::iota(base.begin(), base.end(), 0);
        std::vector<Route> population(cfg.population);
        for (auto& individual : population) {
            individual = base;
            std::shuffle(individual.begin(), individual.end(), init_rng);
        }

        std::vector<double> scores(cfg.population, 0.0);
        std::vector<std::mt19937_64> rngs;
        const int actual_threads = std::max(1, omp_get_max_threads());
        for (int t = 0; t < actual_threads; ++t)
            rngs.emplace_back(cfg.seed + 7919u * static_cast<unsigned>(rank + 1)
                              + 104729u * static_cast<unsigned>(t + 1));

        MPI_Barrier(MPI_COMM_WORLD);
        const double start = MPI_Wtime();
        double best_local = 0.0;
        Route best_route;


        for (int gen = 0; gen < cfg.generations; ++gen) {
            #pragma omp parallel for schedule(static)
            for (int i = 0; i < cfg.population; ++i)
                scores[i] = fitness(population[i], cities);

            int best_idx = static_cast<int>(std::min_element(scores.begin(), scores.end()) - scores.begin());
            int worst_idx = static_cast<int>(std::max_element(scores.begin(), scores.end()) - scores.begin());
            best_local = scores[best_idx];
            best_route = population[best_idx];

            // Ring migration: every rank sends its best route to next and receives from previous.
            if (world > 1 && cfg.migration_interval > 0 &&
                (gen + 1) % cfg.migration_interval == 0) {
                const int dest = (rank + 1) % world;
                const int source = (rank - 1 + world) % world;
                const int k = std::max(1, std::min(cfg.migration_count, cfg.population - 1));

                // Pack this island's k best chromosomes into one contiguous message.
                std::vector<int> order(cfg.population);
                std::iota(order.begin(), order.end(), 0);
                std::partial_sort(order.begin(), order.begin() + k, order.end(),
                    [&](int a, int b) { return scores[a] < scores[b]; });
                std::vector<int> outgoing(static_cast<size_t>(k) * cfg.cities);
                std::vector<int> incoming(static_cast<size_t>(k) * cfg.cities);
                for (int m = 0; m < k; ++m)
                    std::copy(population[order[m]].begin(), population[order[m]].end(),
                              outgoing.begin() + static_cast<size_t>(m) * cfg.cities);

                MPI_Sendrecv(outgoing.data(), k * cfg.cities, MPI_INT, dest, 7,
                             incoming.data(), k * cfg.cities, MPI_INT, source, 7,
                             MPI_COMM_WORLD, MPI_STATUS_IGNORE);

                // Replace the currently weakest member when an incoming migrant is better.
                for (int m = 0; m < k; ++m) {
                    Route migrant(cfg.cities);
                    std::copy(incoming.begin() + static_cast<size_t>(m) * cfg.cities,
                              incoming.begin() + static_cast<size_t>(m + 1) * cfg.cities,
                              migrant.begin());
                    const double migrant_score = fitness(migrant, cities);
                    const int current_worst = static_cast<int>(
                        std::max_element(scores.begin(), scores.end()) - scores.begin());
                    if (migrant_score < scores[current_worst]) {
                        population[current_worst] = std::move(migrant);
                        scores[current_worst] = migrant_score;
                    }
                }
                best_idx = static_cast<int>(std::min_element(scores.begin(), scores.end()) - scores.begin());
                worst_idx = static_cast<int>(std::max_element(scores.begin(), scores.end()) - scores.begin());
                best_local = scores[best_idx];
                best_route = population[best_idx];
            }

            // Preserve best route and generate the rest of the next population in parallel.
            std::vector<Route> next_population(cfg.population);
            next_population[0] = best_route;
            #pragma omp parallel
            {
                const int tid = omp_get_thread_num();
                auto& rng = rngs[tid];
                #pragma omp for schedule(static)
                for (int i = 1; i < cfg.population; ++i) {
                    const int p1 = tournament(scores, rng);
                    const int p2 = tournament(scores, rng);
                    Route child = ordered_crossover(population[p1], population[p2], rng);
                    std::uniform_real_distribution<double> chance(0.0, 1.0);
                    if (chance(rng) < 0.25) mutate(child, rng);
                    next_population[i] = std::move(child);
                }
            }
            population.swap(next_population);

            int snapshot_due = (!cfg.output.empty() &&
                ((gen + 1) % 5 == 0 || gen + 1 == cfg.generations)) ? 1 : 0;
            if (snapshot_due) {
                std::vector<double> rank_best;
                if (rank == 0) rank_best.resize(world);
                MPI_Gather(&best_local, 1, MPI_DOUBLE,
                           rank == 0 ? rank_best.data() : nullptr, 1, MPI_DOUBLE,
                           0, MPI_COMM_WORLD);
                if (rank == 0) {
                    const double avg = std::accumulate(scores.begin(), scores.end(), 0.0) / scores.size();
                    write_snapshot(cfg.output, gen + 1, rank, best_local, avg,
                                   best_route, cities, world, rank_best);
                }
            }

            if (!cfg.output.empty()) {
                int stop = 0;

                if (rank == 0) {
                    std::ifstream flag(cfg.output + ".stop");
                    if (flag.good()) stop = 1;
                }

                MPI_Bcast(&stop, 1, MPI_INT, 0, MPI_COMM_WORLD);

                if (stop) break;
            }
        }

        const double local_elapsed = MPI_Wtime() - start;
        double elapsed = 0.0;
        MPI_Allreduce(
            &local_elapsed,
            &elapsed,
            1,
            MPI_DOUBLE,
            MPI_MAX,
            MPI_COMM_WORLD
        );

        // Final best after the last offspring generation.
        #pragma omp parallel for schedule(static)
        for (int i = 0; i < cfg.population; ++i)
            scores[i] = fitness(population[i], cities);
        const int final_idx = static_cast<int>(std::min_element(scores.begin(), scores.end()) - scores.begin());
        const double final_best = scores[final_idx];

        double global_best = 0.0;
        MPI_Allreduce(&final_best, &global_best, 1, MPI_DOUBLE, MPI_MIN, MPI_COMM_WORLD);
        if (rank == 0) {
            std::cout << "Completed: ranks=" << world << " threads/rank=" << cfg.threads
                      << " generations=" << cfg.generations
                      << " elapsed_s=" << elapsed << " best=" << global_best << "\n";
            if (!cfg.csv.empty()) {
                std::ifstream existing(cfg.csv);
                const bool header = !existing.good();
                existing.close();
                std::ofstream csv(cfg.csv, std::ios::app);
                if (header) csv << "mpi_processes,omp_threads,cities,population_per_island,generations,seed,elapsed_seconds,best_distance\n";
                csv << world << ',' << cfg.threads << ',' << cfg.cities << ','
                    << cfg.population << ',' << cfg.generations << ',' << cfg.seed << ','
                    << std::setprecision(10) << elapsed << ',' << global_best << '\n';
            }
        }
    } catch (const std::exception& e) {
        int rank_now = 0;
        MPI_Comm_rank(MPI_COMM_WORLD, &rank_now);
        if (rank_now == 0) std::cerr << "Error: " << e.what() << "\n";
        exit_code = 1;
    }
    MPI_Finalize();
    return exit_code;
}
