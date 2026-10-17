# Dice 1.0 (SHCI) — portable build

Dice is a Semistochastic Heat-bath Configuration Interaction (SHCI) solver
([upstream docs](https://sanshar.github.io/Dice/), original README in
[README_original.md](README_original.md)). This repository packages Dice 1.0 with the
fixes needed to build on modern compilers, Boost and OpenMPI, and a Makefile that works on
Linux (x86_64 and arm64, including AWS EC2 and Graviton) and macOS without editing.

The build produces two binaries:

| Binary   | Purpose |
|----------|---------|
| `Dice`   | Standard (real) SHCI solver |
| `ZDice2` | Complex build (`-DComplex`) with spin–orbit coupling (SOC) support |

## What was changed from upstream Dice 1.0

- **Davidson.cpp**: a runtime memory-corruption bug is fixed. `MPI_Bcast(&brows, 1, MPI_DOUBLE, …)`
  on a 4-byte `int` is now `MPI_INT`. This crashed on macOS and is undefined behaviour everywhere.
- **integral.cpp, SHCInonessentials.cpp**: the removed MPI C++ bindings (`MPI::COMM_WORLD.Bcast`)
  are replaced with `MPI_Bcast`, which OpenMPI 5 requires.
- **SHCISortMpiUtils.h, SOChelper.cpp**: added Boost includes that Boost ≥1.7x no longer pulls in for you.
- **global.h**: added a `fabs(std::complex<double>)` overload for the complex (SOC) build.
- **Makefile**: rewritten to detect the OS, Eigen, Boost and OpenMP automatically. It now uses C++14
  (Eigen 3.4/5 needs it) and drops `-lrt` and the hard-coded paths.
- **SHCI.cpp**: the final `std::system("rm -rf /dev/shm* ...")` is replaced by removing only Dice's own
  shared-memory segments. On Linux the original deleted OpenMPI's segments before `MPI_Finalize`
  (`unlink ... No such file or directory` on every run) and any other job's shared memory on the node.
  It was a no-op on macOS, which has no `/dev/shm`.
- **SHCIshm.cpp**: shared-memory segment names now use a suffix (time + pid) chosen by rank 0 and broadcast.
  Before, each rank used its own `time(NULL)`. A rank that started in a different second opened a
  different, empty segment, and two jobs started in the same second on one node shared segments.
- **scripts/build_boost.sh**: the temp-dir cleanup uses `sudo` when the install did. It failed on a
  non-root AMI because `sudo b2 install` leaves root-owned files in the build tree.
- **tests/run*.sh**: `MPICOMMAND`, `PYTHON` and `HCIPATH` can be overridden from the environment.

The full macOS porting log, with root-cause analysis, is in [docs/BUILD_REPORT_macOS.md](docs/BUILD_REPORT_macOS.md).
CI ([.github/workflows/build.yml](.github/workflows/build.yml)) builds the code and runs the test suite on
Ubuntu 22.04/24.04 (x86_64), Ubuntu 24.04 arm64 and Amazon Linux 2023.

## Quick start on AWS

### Ubuntu AMI (simplest; x86_64 or Graviton)

```bash
git clone https://github.com/syedshah-web/dice.git && cd dice
./scripts/install_deps.sh            # apt: OpenMPI, Boost.MPI, Eigen, numpy
make -j"$(nproc)"
```

### Amazon Linux 2023

The distro has no Boost.MPI package, so the script builds Boost 1.86 from source into `/opt/boost`
(about 2–5 minutes):

```bash
sudo dnf install -y git
git clone https://github.com/syedshah-web/dice.git && cd dice
./scripts/install_deps.sh
export PATH=/usr/lib64/openmpi/bin:$PATH LD_LIBRARY_PATH=/usr/lib64/openmpi/lib:$LD_LIBRARY_PATH
make -j"$(nproc)" BOOST=/opt/boost
```

### AWS ParallelCluster / EFA (multi-node)

To use the EFA fabric, build against the MPI that ParallelCluster installs. Boost.MPI must be
compiled with that same MPI:

```bash
export PATH=/opt/amazon/openmpi/bin:$PATH        # or: module load openmpi
./scripts/build_boost.sh $HOME/boost              # builds against the mpicxx on PATH
make -j"$(nproc)" BOOST=$HOME/boost
```

With Intel MPI, run `make USE_INTEL=yes …` (uses `mpiicpc`) after building Boost with `MPICXX=mpiicpc`.

### Docker (any host, x86_64 or arm64)

```bash
docker build -t dice .
docker run --rm -v "$PWD":/work dice mpirun -np 8 Dice input.dat > output.dat
```

## Build options

```bash
make info                         # print the detected compiler, Eigen and Boost paths
make -j BOOST=/opt/boost          # Boost root (headers + lib/ or stage/lib)
make -j EIGEN=/path/to/eigen3     # directory that contains Eigen/Dense
make -j OPT="-march=native"       # tune for the build machine (binary then needs the same CPU family)
make -j USE_MPI=no                # serial build
make clean
```

The default flags carry no `-march`, so the binaries run on any instance of the same architecture.
For a fleet of identical instances, `OPT="-march=native"` is usually a few percent faster.
x86_64 and arm64 binaries are not interchangeable, so build on each architecture you run on.

On macOS, activate a conda env that has `openmpi eigen llvm-openmp` (or use Homebrew) and run
`make -j BOOST=/path/to/boost`. `OMPI_CXX=clang++` is set automatically.

## Running

A run directory needs an `input.dat` and an `FCIDUMP`:

```bash
mpirun -np 8 /path/to/dice/Dice   input.dat > output.dat
mpirun -np 8 /path/to/dice/ZDice2 input.dat > output.dat   # spin–orbit coupling
```

For hybrid MPI + OpenMP, keep `ranks × OMP_NUM_THREADS` ≤ physical cores. On EC2, one vCPU is one
hyperthread, so physical cores = vCPUs / 2 on most x86 instances. Graviton has no SMT, so there
vCPUs = cores.

```bash
export OMP_NUM_THREADS=4
mpirun -np 4 --bind-to socket Dice input.dat > output.dat
```

To use Dice from PySCF's `shciscf` module, set `SHCIEXE` in `pyscf/shciscf/settings.py` to the
absolute path of `Dice` (or `ZDice2`).

## Tests

```bash
cd tests
MPICOMMAND="mpirun -np 4" ./runSmallTests.sh 2>&1 | tee small.log   # O2 + restart, ~1 min
MPICOMMAND="mpirun -np 8" ./runTests.sh      2>&1 | tee full.log    # adds Cr2 and Mn-salen
../scripts/check_tests.sh full.log      # non-zero exit if anything FAILED
./clean.sh                              # remove generated files
```

Reference result on a 14-core Apple M-series machine: full suite 20/20 PASSED
([docs/macos_fulltests.log](docs/macos_fulltests.log)).
Amazon Linux 2023 on EC2 (x86_64, 64 vCPU, dnf OpenMPI 4.1 + Boost 1.86): small suite 14/14 PASSED with
0 errors at `-np 2` and `-np 8` ([docs/aws_al2023_small.log](docs/aws_al2023_small.log)). Full suite on
`m8a.16xlarge` (AMD EPYC 9R45, 64 cores), `mpirun -np 16`: 20/20 PASSED in 2m36s
([docs/aws_m8a.16xlarge_fulltests.log](docs/aws_m8a.16xlarge_fulltests.log)).

## License

GPL-3.0-or-later, as in upstream Dice (Sandeep Sharma et al.); see [LICENSE](LICENSE). The modifications in this repository are released under the same license.
