# Open tasks for the AWS agent

Context: this repo is Dice 1.0 (SHCI) with portability fixes. Read [README.md](README.md) and
[docs/BUILD_REPORT_macOS.md](docs/BUILD_REPORT_macOS.md) first. The build is validated on macOS arm64
(full suite 20/20 PASSED). Linux has **only been checked by GitHub Actions CI**, and the results below
come from there.

## Current status (CI, commits on `main` as of 2026-10-16)

| Platform | Build (`make`) | `tests/runSmallTests.sh` |
|----------|----------------|--------------------------|
| Ubuntu 22.04 x86_64 (apt Boost 1.74, OpenMPI 4.1) | ✅ compiles | ❌ |
| Ubuntu 24.04 x86_64 (apt Boost 1.83, OpenMPI 4.1) | ✅ compiles | ❌ |
| Ubuntu 24.04 arm64 | ✅ compiles | ❌ |
| Amazon Linux 2023 (dnf OpenMPI + Boost 1.86 from source) | ✅ compiles | ❌ |

The cause of the test failure is **not known yet**. CI logs need GitHub auth, and the run with extra
diagnostics (commit 86d7a2b, which makes `scripts/check_tests.sh` print annotations) had not finished
when this file was written. It may be a real runtime problem or a false positive in
`scripts/check_tests.sh`.

---

## Task 1: Reproduce and fix the Linux test failure (highest priority)

On an EC2 instance (Ubuntu 22.04/24.04 is quickest):

```bash
git clone https://github.com/syedshah-web/dice.git && cd dice
./scripts/install_deps.sh
make -j"$(nproc)"
cd tests
MPICOMMAND="mpirun -np 2" ./runSmallTests.sh 2>&1 | tee small.log
../scripts/check_tests.sh small.log
```

Then work out which of these it is:

1. **Checker false positive.** `check_tests.sh` greps `Error|No such file|Abort|...` in the combined
   stdout+stderr log. Harmless OpenMPI or Python warnings could match. Look at the lines that match.
   If they are benign, tighten the pattern. Do not loosen it so far that real crashes pass.
2. **Script bug.** In `runSmallTests.sh` / `runTests.sh`, the `restart*` tests run only `input2.dat` and
   `input3.dat`, not `input1.dat`. Check that this matches upstream intent: they need a prior
   `*.bkp` and may depend on test order. Also check that the `here=`/`HCIPATH` changes resolve correctly.
3. **Real runtime bug** (crash, energy mismatch). Look at each test's `output.dat`. Prime suspects,
   by analogy with the `MPI_Bcast` int/double bug already fixed in `Davidson.cpp`:
   - other `MPI_Bcast` / `MPI_Allreduce` calls whose datatype does not match the C++ type
     (`grep -n "MPI_Bcast\|MPI_Allreduce\|MPI_Reduce" *.cpp *.h`)
   - shared memory in `SHCIshm.cpp` (boost interprocess / `/dev/shm` size limits; containers
     default to 64 MB `/dev/shm`)
   - GCC-specific UB that clang tolerated. Rebuild with `OPT="-fsanitize=address,undefined -O1"`
     and rerun a single test to check.
4. **Energy tolerance.** If energies differ only slightly from `trusted_hci.e`, compare against the
   tolerances in the run scripts. Stochastic tests (`*_stoc`, `*_seed`) can differ by platform RNG.
   Report the deltas rather than widening tolerances blindly.

Done when CI on `main` is green for all four jobs (`.github/workflows/build.yml`).

## Task 2: Full test suite on a real AWS instance

After Task 1, on a c7i (x86) and a c7g (Graviton) instance, run
`MPICOMMAND="mpirun -np <physical cores>" ./runTests.sh` (Cr2 + Mn-salen). Commit the logs as
`docs/aws_<instance>_fulltests.log` and add a results line to the README Tests section.

## Task 3: Multi-node / EFA validation (ParallelCluster)

Follow "AWS ParallelCluster / EFA" in the README: build Boost against `/opt/amazon/openmpi`, then run a
Cr2 test across 2 nodes with `mpirun -np N --hostfile …`. Check that EFA is actually used
(`FI_PROVIDER=efa`, `fi_info -p efa`). Write down any required env vars or Slurm script in
`docs/aws_parallelcluster.md`.

## Task 4: Verify the Dockerfile

`docker build -t dice .` on x86 and arm64, then run the small suite inside the container. Note that the
container needs `--shm-size=1g` or more (see Task 1.3). If the image works, consider adding a CI job that
builds it and pushes to ECR/GHCR.

## Task 5 (nice to have)

- Check whether `-march=native` (e.g. `OPT="-march=native"`) gives a measurable speedup on Cr2.
- `scripts/install_deps.sh` on Amazon Linux 2023 has only been exercised in a container. Confirm it on
  a real AL2023 AMI.
- Large reference files (`tests/cr2_*/{FCIDUMP,trusted2RDM.txt}`, ~50 MB each) could move to Git LFS.

## Ground rules

- Keep the source fixes minimal and explain each in the README "What was changed" list.
- Do not change reference data (`trusted*`) to make tests pass.
