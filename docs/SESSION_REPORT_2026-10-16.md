# Session report: packaging Dice for multi-platform / AWS use

**Date:** 2026-10-16
**Repo:** https://github.com/syedshah-web/dice (branch `main`)
**Starting point:** the Dice 1.0 tree in `~/Documents/Electrostatic/Dice`, which had been ported to and
validated on macOS arm64 in June 2026 (see [BUILD_REPORT_macOS.md](BUILD_REPORT_macOS.md); full suite 20/20 PASSED).

## Goal

Publish Dice so it builds on machines other than the original MacBook, mainly AWS EC2 (x86_64 and
Graviton), without hand-editing paths.

## What was done

### 1. Clean repository
- Copied the patched sources, LICENSE (GPL-3) and the test suite into a fresh git repo.
- Excluded build products (`obj/`, `obj_z/`, `Dice`, `ZDice2`, `build.log`), test run outputs, editor
  backups, `.DS_Store`, and the cluster-specific `dft.mk` (hard-coded paths to another user's home).
- Kept the June macOS build report and full-suite log under `docs/`. Renamed the upstream README to
  `README_original.md`.
- Extended `.gitignore` for build and test artifacts.

### 2. Portable Makefile
The old Makefile had absolute macOS/conda paths and Apple-clang-only OpenMP flags. The new one:
- Detects the OS (`uname`): Linux uses `-fopenmp`; macOS uses `-Xpreprocessor -fopenmp -lomp` and
  sets `OMPI_CXX=clang++` automatically.
- Finds Eigen automatically (conda, `/usr/include/eigen3`, `/usr/local`, Homebrew), or takes `EIGEN=`.
- Uses system Boost by default. `BOOST=<root>` accepts both a source tree (`stage/lib`) and an install
  prefix (`lib`/`lib64`), and bakes in an rpath.
- Adds `OPT=` for opt-in tuning (no `-march` by default, so binaries stay portable), `USE_MPI=no` for a
  serial build, `USE_INTEL=yes`, a `make info` target, auto-creation of the `obj` dirs, and a `clean` that
  needs no dependencies.
- Removed the hostname-based `include dft.mk`.
- **Verified on macOS:** clean build with 0 errors, and the `o2_omp1_det` test PASSED with `mpirun -np 4`.

### 3. Test scripts
In `tests/runSmallTests.sh` and `tests/runTests.sh`, `MPICOMMAND`, `PYTHON` (default `python3`) and
`HCIPATH` can now be overridden from the environment, and the binary path is resolved relative to the script.

### 4. AWS / Linux tooling
- `scripts/install_deps.sh`: apt (Ubuntu/Debian), dnf (Amazon Linux 2023/RHEL; builds Boost from
  source because there is no Boost.MPI package), brew (macOS).
- `scripts/build_boost.sh`: builds Boost 1.86 (serialization + mpi) against whatever `mpicxx` is on PATH.
  This is needed for ParallelCluster/EFA (`/opt/amazon/openmpi`) or Intel MPI. It downloads from
  archives.boost.io, since the bintray URLs in the upstream docs are dead.
- `scripts/check_tests.sh`: turns the test logs (which always exit 0) into pass/fail. Under GitHub
  Actions it also prints the matching lines as annotations.
- `Dockerfile` (Ubuntu 22.04, multi-arch) and `.dockerignore`.
- `.github/workflows/build.yml`: CI on Ubuntu 22.04, Ubuntu 24.04, Ubuntu 24.04 arm64 and an
  Amazon Linux 2023 container. Each job builds, runs the small test suite and checks the result.

### 5. Documentation
- `README.md`: what changed from upstream, AWS quick starts (Ubuntu, AL2023, ParallelCluster/EFA,
  Docker), build options, MPI × OpenMP sizing on EC2 (vCPU = hyperthread on x86, = core on Graviton),
  PySCF `shciscf` hookup, tests.
- `AWS_AGENT_TASKS.md`: prioritized open work for the agent running on AWS.

### 6. Publishing
Pushed over SSH (as `syedshah-web`). HTTPS had no stored credentials. Commits:
`f6b0ec5` (initial), `86d7a2b` (CI diagnostics, checkout@v5), `cad0223` (task list), plus this report.
GitHub warns that two `trusted2RDM.txt` files (~50 MB) are over its 50 MB recommendation. This is
under the 100 MB hard limit, so it is not blocking.

## Results

| Platform | Build | Small test suite |
|----------|-------|------------------|
| macOS arm64 (local, this session) | ✅ | ✅ spot check (`o2_omp1_det`) |
| Ubuntu 22.04 x86_64 (CI) | ✅ | ❌ |
| Ubuntu 24.04 x86_64 (CI) | ✅ | ❌ |
| Ubuntu 24.04 arm64 (CI) | ✅ | ❌ |
| Amazon Linux 2023 (CI) | ✅ | ❌ |

**The source compiles on all four Linux targets**, including the Boost-from-source path. The test step
fails on all of them, and the root cause is **not yet diagnosed**. CI logs need GitHub authentication,
and none was available here (no `gh` CLI, no token). The second CI run, which adds diagnostic
annotations, was still in progress when the work was handed off. It is unclear whether this is a real
runtime problem on GCC/Linux or a false positive in `check_tests.sh`'s error pattern. Because every
platform fails the same way, a shared cause (script or checker) is somewhat more likely than a
platform bug.

## Not done / handed off
See `AWS_AGENT_TASKS.md`: fix the Linux test failure, run the full suite on c7i/c7g, validate
multi-node EFA, verify the Docker image, and some optional items (`-march=native` benchmark, Git LFS).
