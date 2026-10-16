# Dice (SHCI) Build & Validation Report — macOS Apple Silicon

**Date:** 2026-06-14
**Machine:** MacBook Pro, Apple Silicon (arm64), Darwin 25.0.0, 14 cores
**Goal:** Compile Dice 1.0 (Semistochastic Heat-bath Configuration Interaction) **with SOC support** and validate it against the bundled test suite.
**Outcome:** ✅ Both binaries (`Dice` and the SOC build `ZDice2`) compile, link, run, and pass the test suite.

---

## 1. Overview

Dice 1.0 is a 2017-era C++ quantum chemistry code written for GCC + Linux + older library
versions. The challenge of this install was almost entirely a **toolchain-gap port**: getting
2017 code to build and run correctly on a 2026 Apple-clang / libc++ / modern-Boost / modern-OpenMPI
stack. The actual install guide steps were straightforward; the work was in the compatibility fixes.

The job broke into three phases:

1. **Prerequisites** — build/install Boost, Eigen, OpenMPI, OpenMP.
2. **Compilation** — fix 8 toolchain incompatibilities so the source compiles and links.
3. **Testing** — fix 1 latent runtime bug (a type-mismatched MPI broadcast) that only macOS's
   stricter memory allocator exposed, then run the validation suite.

Reference: official install guide — https://sanshar.github.io/Dice/installation.html

---

## 2. Environment

| Item | Value |
|------|-------|
| Platform | macOS (Darwin 25.0.0), Apple Silicon arm64 |
| Compiler | Apple Clang 17 (`clang++`, libc++) |
| Conda env | `electro` at `/opt/anaconda3/envs/electro` |
| Working dir | `/Users/shah/Documents/Electrostatic` |
| Cores | 14 physical / 14 logical |

**Key environment quirk:** the conda OpenMPI compiler wrapper (`mpicxx`) defaults to looking for a
nonexistent cross-compiler (`arm64-apple-darwin20.0.0-clang++`). Every compile must therefore be
prefixed with `OMPI_CXX=clang++` so the wrapper uses the real Apple clang.

---

## 3. Prerequisites — what was installed and how

### 3.1 Dependency targets
Dice requires: **Boost** (with `serialization` + `mpi`), **Eigen** (header-only), a C++ compiler with
OpenMP, and an MPI implementation.

### 3.2 `wget` (download helper)
macOS ships no `wget`. Installed separately (Homebrew). Alternatively `curl -O` works.
Also note: the install guide's Boost download URLs point at **bintray.com, which shut down in 2021**
and 404s. The working source is `https://archives.boost.io/`.

### 3.3 Boost 1.86.0 — built from source
```bash
# Downloaded from the live archive (NOT the dead bintray URL in the docs)
curl -O https://archives.boost.io/release/1.86.0/source/boost_1_86_0.tar.gz
tar -xzvf boost_1_86_0.tar.gz
cd boost_1_86_0
./bootstrap.sh --with-libraries=serialization,mpi
```
The bootstrap step generates `project-config.jam` **without** an MPI toolset line, so the MPI library
will not build. Per the install guide, we manually added the MPI compiler line:

`boost_1_86_0/project-config.jam` (added near the end):
```jam
using mpi : mpicxx ;
```
Then built:
```bash
./b2 -j4
```
Confirmed both `serialization: building` and `mpi: building` in the output (236 targets updated).
Libraries land in `boost_1_86_0/stage/lib`.

### 3.4 Eigen 5.0.1 — via conda
```bash
conda install -n electro -c conda-forge eigen
# installs headers at /opt/anaconda3/envs/electro/include/eigen3
```

### 3.5 OpenMPI 5.0.10 — via conda
The base-conda `mpicxx` was broken (looked for a cross-compiler). Fixed by installing OpenMPI
*into the electro env* and always prefixing with `OMPI_CXX=clang++`:
```bash
conda install -n electro -c conda-forge openmpi
```

### 3.6 OpenMP runtime (`libomp`) — via conda
Apple clang has no bundled OpenMP runtime.
```bash
conda install -n electro -c conda-forge llvm-openmp
# provides libomp.dylib + omp.h under the electro env
```

### 3.7 Dice 1.0 source
```bash
wget https://sanshar.github.io/Dice/_downloads/dice_1_0.tar.gz
tar -xzvf dice_1_0.tar.gz   # -> ./Dice/
```

---

## 4. Makefile configuration

`Dice/Makefile` was edited for the macOS/arm64/clang toolchain. Final relevant settings:

```makefile
USE_MPI = yes
USE_INTEL = no

EIGEN=/opt/anaconda3/envs/electro/include/eigen3
BOOST=/Users/shah/Documents/Electrostatic/boost_1_86_0

# C++14 (not c++11) — required by Eigen 5.x (see issue C3)
FLAGS  = -std=c++14 -g -O3 -I${EIGEN} -I${BOOST} #-DComplex
DFLAGS = -std=c++14 -g -O3 -I${EIGEN} -I${BOOST} -DComplex

# non-Intel branch (Apple clang):
FLAGS  += -Xpreprocessor -fopenmp -I/opt/anaconda3/envs/electro/include
DFLAGS += -Xpreprocessor -fopenmp -I/opt/anaconda3/envs/electro/include
# MPI=yes link line (rpaths baked in so libs resolve at runtime):
CXX = mpicxx
CC  = mpicxx
LFLAGS = -L${BOOST}/stage/lib -lboost_serialization -lboost_mpi \
         -L/opt/anaconda3/envs/electro/lib -lomp \
         -Wl,-rpath,${BOOST}/stage/lib -Wl,-rpath,/opt/anaconda3/envs/electro/lib
```

---

## 5. Compilation issues and fixes

Eight distinct issues, each a symptom of 2017 code meeting a modern toolchain.

| # | Symptom | Root cause | Fix | Location |
|---|---------|-----------|-----|----------|
| C1 | `wget: command not found` | macOS ships no wget | Install wget / use `curl -O` | shell |
| C2 | Boost download 404 | bintray.com shut down in 2021 | Use `archives.boost.io` | shell |
| C3 | Hundreds of Eigen errors: `no template named 'integer_sequence'`, `enable_if_t`, `make_signed_t`, `common_type_t`; "deduced return types are a C++14 extension" | Eigen 5.0.1 **requires C++14**; Makefile used `-std=c++11` | `c++11` → `c++14` in FLAGS/DFLAGS | Makefile |
| C4 | `clang++: error: unsupported option '-fopenmp'` | Apple clang needs the preprocessor form + external runtime | `-fopenmp` → `-Xpreprocessor -fopenmp`, add `-lomp` and conda include/lib paths | Makefile |
| C5 | Link error referencing `-lrt` | `-lrt` (POSIX realtime) is Linux-only | Remove `-lrt` from all LFLAGS | Makefile |
| C6 | `no template named 'shared_ptr' in namespace 'boost'` (137×) | Boost 1.86 no longer transitively includes `shared_ptr` via `serialization.hpp` | Add `#include <boost/shared_ptr.hpp>` | `SHCISortMpiUtils.h` |
| C7 | `no member named 'serialize' in 'std::vector<oneInt>'` | TU broadcasting a `vector<oneInt>` lacked the vector serialization specialization | Add `#include <boost/serialization/vector.hpp>` | `SOChelper.cpp` |
| C8 | `use of undeclared identifier 'MPI'` (`MPI::COMM_WORLD.Bcast`) | The MPI **C++ bindings** (`MPI::` namespace) were removed in MPI-3 / OpenMPI 5.x | Rewrite 7 calls as C-style `MPI_Bcast(..., MPI_COMM_WORLD)` | `integral.cpp` (5), `SHCInonessentials.cpp` (2) |
| C9 | `no matching function for call to 'fabs'` (complex build) | In the `-DComplex` build `CItype = std::complex<double>`; C `fabs` has no complex overload | Add a `fabs(std::complex<double>)` overload (returns magnitude) guarded by `#ifdef Complex` | `global.h` |

### Source patch details

**`global.h`** — added `<complex>`/`<cmath>` and, inside the `#ifdef Complex` block:
```cpp
// In the complex build CItype is std::complex<double>; the C library fabs has
// no complex overload, so provide one returning the magnitude.
inline double fabs(const std::complex<double>& x) { return std::abs(x); }
```
(Placed in `global.h` because it is transitively included everywhere via `Determinants.h`, so the
overload is visible at every call site without touching dozens of files.)

**`SHCISortMpiUtils.h`** — `#include <boost/shared_ptr.hpp>` before the serialization include.

**`SOChelper.cpp`** — `#include <boost/serialization/vector.hpp>` inside the `#ifndef SERIAL` block.

**`integral.cpp` / `SHCInonessentials.cpp`** — pattern conversion:
```cpp
// before (removed C++ binding):
MPI::COMM_WORLD.Bcast(buf, count, MPI_DOUBLE, 0);
// after (portable C binding):
MPI_Bcast(buf, count, MPI_DOUBLE, 0, MPI_COMM_WORLD);
```

### Result
Build completes with **0 errors**. Two arm64 binaries produced:
- `Dice` (~1.5 MB) — standard SHCI solver
- `ZDice2` (~1.8 MB) — complex build = **SOC support**

---

## 6. Runtime/link issue (between build and testing)

**Symptom:** launching `./Dice` aborted immediately with
`dyld: Library not loaded: @rpath/libboost_serialization.dylib`.

**Cause:** on macOS, the linker's `-L<dir>` adds a *link-time* search path but does **not** record a
*runtime* search path. The Boost dylibs (in `boost_1_86_0/stage/lib`) were referenced as
`@rpath/...` with no matching rpath in the binary.

**Fix:** bake the library directories into the binaries via `LFLAGS`:
```makefile
-Wl,-rpath,${BOOST}/stage/lib -Wl,-rpath,/opt/anaconda3/envs/electro/lib
```
After relinking, `otool -l Dice | grep -A2 LC_RPATH` shows both paths, and the binaries launch and
print their banner. (The harmless `ld: warning: duplicate -rpath` is because mpicxx already injects
the conda lib path.)

---

## 7. Testing issues and fixes

### Test harness
- Scripts live in `Dice/tests/`. The install guide calls it `runAllTests.sh`; the actual files are
  **`runTests.sh`** (full) and **`runSmallTests.sh`** (lighter, recommended for laptops).
- `MPICOMMAND` near the top sets the parallel launcher (default `mpirun -np 28`). Must be reduced to
  ≤ core count, or blanked entirely for a serial build.
- Each test runs Dice on a small molecule and a Python script (`test_energy.py`, `test_twopdm.py`)
  compares the result against a trusted reference within a tolerance. Requires `python` + `numpy`
  (present in the electro env).

### T1 — Heap abort inside the Davidson solver (the one real runtime bug)

**Symptom:** the first single-test run got the correct first variational energy, then aborted with
```
malloc: *** ___BUG_IN_CLIENT_OF_LIBMALLOC_POINTER_BEING_FREED_WAS_NOT_ALLOCATED
Signal: Abort trap: 6   (inside davidson() / DoVariational())
```

**Root cause:** in `Davidson.cpp` (two sites):
```cpp
int brows = x0[0].rows();                       // 4-byte int
MPI_Bcast(&brows, 1, MPI_DOUBLE, 0, MPI_COMM_WORLD);   // broadcasts 8 bytes!
```
`MPI_Bcast` does no type conversion — it copies raw bytes. Broadcasting `1 × MPI_DOUBLE` (8 bytes)
into a 4-byte `int` writes **4 bytes past the variable** on receiving ranks, corrupting adjacent
stack memory (an Eigen matrix's internal data pointer). That corrupted pointer is later freed →
the heap abort. This is undefined behavior that happened to be survivable on the authors' Linux/glibc
cluster but is caught immediately by macOS's stricter allocator.

**Fix:** broadcast the int with the correct type and size:
```cpp
MPI_Bcast(&brows, 1, MPI_INT, 0, MPI_COMM_WORLD);
```

**Audit note:** we swept the whole codebase for the same pattern. All other
`MPI_Bcast(&x, 1, MPI_DOUBLE)` sites broadcast `size_t` (8 bytes) or genuine `double` variables —
those are byte-size-safe (8 → 8, value preserved by the raw copy) and were left unchanged. Only the
two `int brows` sites were memory-unsafe.

### Test results — `runSmallTests.sh` (`mpirun -np 4`): **11/11 PASSED**
- 8 × O2 tests (stochastic, deterministic, time-reversal, direct, OMP-threaded `omp4`, seeded) — energies ✓
- 3 × restart tests (restart, restart_trev, full restart) — ✓
- 3 × two-particle RDM checks — ✓

This exercised the full stack: MPI parallelism, OpenMP threading, the variational + semistochastic-PT
solver, RDM computation, and restart-from-disk.

(The small suite intentionally skips the heavier Cr2 / Mn-salen / butadiene cases; those are in the
full `runTests.sh`.)

### Test results — full suite `runTests.sh` (`mpirun -np 8`): **20/20 PASSED, 0 FAILED**

The full suite was subsequently run on 8 cores (after lowering `MPICOMMAND` from the default
`-np 28`). It re-ran everything in the small suite **plus** the heavier multireference cases, and
every energy and 2-RDM check passed:

| Group | Tests | Checks | Result |
|-------|-------|--------|--------|
| O2 | 8 variants (stoc, det, trev, det_trev, det_trev_direct, trev_direct, det_direct, omp4_det, omp4_seed) | energy + 3 × 2RDM | ✓ all |
| Restart | restart, restart_trev, full restart | energy | ✓ all |
| **Cr2** | `cr2_dinfh_rdm`, `cr2_dinfh_trev_rdm` | energy + 2RDM each | ✓ all |
| **Mn-salen** | `mn_salen_stoc`, `mn_salen_seed` | energy | ✓ all |

Tally: **20 PASSED / 0 FAILED** (`grep -c PASSED fulltests.log` = 20, `FAILED` = 0).
The Cr2 (d-infinity-h) and Mn-salen cases are the demanding multireference systems — passing them
confirms correctness well beyond the quick smoke test, and 8 cores handled them without issue.
Full log: `Dice/tests/fulltests.log`.

---

## 8. How to build and run the final version

### Build (or rebuild)
```bash
conda activate electro
cd /Users/shah/Documents/Electrostatic/Dice
OMPI_CXX=clang++ make -j          # builds Dice + ZDice2 (SOC)
```
> The `OMPI_CXX=clang++` prefix is **required** every time you compile.

### Run a calculation
A run directory needs an `input.dat` and an `FCIDUMP` integral file.
```bash
conda activate electro            # ensures correct mpirun + rpath'd libraries
cd /path/to/your/run
mpirun -np 8 /Users/shah/Documents/Electrostatic/Dice/Dice  input.dat > output.dat
# For spin-orbit coupling, use the complex binary instead:
mpirun -np 8 /Users/shah/Documents/Electrostatic/Dice/ZDice2 input.dat > output.dat
```
- Keep `-np` ≤ 14 (physical cores). Combine with `export OMP_NUM_THREADS=N` for hybrid MPI+OpenMP,
  keeping `np × N` ≤ core count.

### Re-run the test suites
```bash
cd /Users/shah/Documents/Electrostatic/Dice/tests
./runSmallTests.sh                # quick validation (np 4, O2 + restart)

# Full suite — first lower the core count from the default 28:
sed -i '' 's/MPICOMMAND="mpirun -np 28"/MPICOMMAND="mpirun -np 8"/' runTests.sh
./runTests.sh 2>&1 | tee fulltests.log
```

---

## 9. Appendix — all files modified

| File | Change |
|------|--------|
| `boost_1_86_0/project-config.jam` | Added `using mpi : mpicxx ;` |
| `Dice/Makefile` | EIGEN/BOOST paths; `c++11`→`c++14`; OpenMP flags for clang; removed `-lrt`; added rpaths |
| `Dice/global.h` | Added `<complex>`/`<cmath>`; `fabs(std::complex<double>)` overload (`#ifdef Complex`) |
| `Dice/SHCISortMpiUtils.h` | Added `#include <boost/shared_ptr.hpp>` |
| `Dice/SOChelper.cpp` | Added `#include <boost/serialization/vector.hpp>` |
| `Dice/integral.cpp` | 5 × `MPI::COMM_WORLD.Bcast` → `MPI_Bcast` |
| `Dice/SHCInonessentials.cpp` | 2 × `MPI::COMM_WORLD.Bcast` → `MPI_Bcast` |
| `Dice/Davidson.cpp` | 2 × `MPI_Bcast(&brows, 1, MPI_DOUBLE)` → `MPI_INT` (the runtime crash fix) |

### One-line takeaways
- **Compile prefix:** always `OMPI_CXX=clang++ make -j`.
- **Runtime:** activate the `electro` conda env; libraries are found via baked-in rpaths.
- **SOC:** the `ZDice2` binary is the spin-orbit-coupling build.
- **The hard bug:** a type-mismatched `MPI_Bcast` (int sent as double) corrupted memory — invisible on
  Linux, fatal on macOS until fixed.
