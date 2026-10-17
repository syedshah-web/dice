# Session report 2026-10-17: Linux test failure (AWS Task 1)

Host: EC2 `m8a.16xlarge` (AMD EPYC 9R45, 64 vCPU, 247 GB), Amazon Linux 2023, GCC 11.5,
dnf OpenMPI 4.1.2, Boost 1.86 from `scripts/build_boost.sh`. This is the first run on real Linux hardware.

## Result

The CI "failure" was not a wrong energy. CI and this host both showed **PASSED=14 FAILED=0** (14 is
every check in `runSmallTests.sh`). `check_tests.sh` failed on `ERRORS=13–14`, and every one of those
lines was this OpenMPI message:

```
A system call failed during shared memory initialization ...
  System call: unlink(2) /dev/shm/vader_segment.<host>.<...>
  Error:       No such file or directory (errno 2)
```

The checker was right to flag it. The message comes from a real bug in Dice:

- **`SHCI.cpp`, end of `main`**: every rank ran `std::system("rm -rf /dev/shm* 2>/dev/null")` before
  `MPI_Finalize`. On Linux that deletes OpenMPI's vader segments while the job still uses them, and it
  deletes every other `/dev/shm` file the user can remove. As root, in Docker or a CI container, that
  is all of `/dev/shm`. On a shared node (ParallelCluster, several jobs per instance) it can break other
  jobs. macOS has no `/dev/shm`, so the suite was clean there.
  Reproduced here: a canary file `/dev/shm/canary_other_job` was deleted by the unmodified build
  ([aws_al2023_small_before.log](aws_al2023_small_before.log)).

## Changes (all listed in README "What was changed")

1. `SHCI.cpp`: replaced the `rm -rf` with `shared_memory_object::remove` on Dice's 7 segment names.
   `initSHM` creates all 7 with `open_or_create`, and not every run uses (and therefore unlinks) all of them.
2. `SHCIshm.cpp`: the segment-name suffix is now `time%1e6 + "_" + pid` from rank 0, broadcast to all ranks.
   Before, each rank used its own `time(NULL)`. Ranks share memory only if their names match when
   `initSHM` opens them, so a rank that started in a different second got a private zero-filled segment.
   This is a latent wrong-result bug: rare in small tests, more likely at scale. Two jobs started in the
   same second on one node also collided.
3. `scripts/build_boost.sh`: the `EXIT` trap now runs `rm -rf` with `$SUDO`. On a non-root AMI,
   `sudo b2 install` leaves root-owned files in the build tree. The plain `rm` failed, and `set -e` turned
   a successful install into exit 1. CI did not catch this because its container runs as root. This also
   covers the Task 5 item "confirm `install_deps.sh` on a real AL2023 AMI": with this fix it works.

## Verification on this host

| Run | PASSED | FAILED | ERRORS | `/dev/shm` after |
|-----|--------|--------|--------|------------------|
| before fix, `-np 2` | 14 | 0 | 14 | empty (canary deleted) |
| after fix, `-np 2` ([log](aws_al2023_small.log)) | 14 | 0 | 0 | canary kept, no Dice leftovers |
| after fix, `-np 8` ([log](aws_al2023_small_np8.log)) | 14 | 0 | 0 | empty |

## Other Task 1 questions

- **Restart tests (1.2)**: no script bug. `input2.dat` runs from scratch and writes the `.bkp`, then
  `input3.dat` (`restart`/`fullrestart`, longer schedule) resumes from it inside the same directory, so
  test order does not matter. `input1.dat` is a separate non-restart reference input (tighter schedule,
  `DoRDM`). `restart_trev` has no `input1.dat`, consistent with it never being run here.
- **Checker (1.1)**: left strict. With the fix it reports 0 errors, and the vader message does point to a
  real problem.
- **Not changed, noted**: `SHCIshm.cpp`/`SHCIshm.h` broadcast `size_t totalMemory` as `MPI_DOUBLE`. Both are
  8 bytes and MPI does not convert on a homogeneous cluster, so this is harmless in practice (unlike the
  4-byte `int` in `Davidson.cpp`). It would only matter on heterogeneous systems.
- Sanitizer rebuild (1.3) not run: there was no crash to chase.

## Next

Tasks 2–5 in [AWS_AGENT_TASKS.md](../AWS_AGENT_TASKS.md). Task 2 needs c7i/c7g instances. This host is
`m8a`, so its full-suite run could be recorded as an extra data point.
