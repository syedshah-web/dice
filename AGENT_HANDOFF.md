# Message to the agent running on AWS

Hi. You're picking up Dice (SHCI quantum chemistry solver, C++/MPI/OpenMP, from 2017) after it was
ported to modern toolchains and packaged for Linux/AWS. The work so far was done from a Mac with no
Linux machine available, so **you are the first to run this on real Linux hardware.**

**Read in this order:**
1. `AWS_AGENT_TASKS.md`: your task list, by priority.
2. `docs/SESSION_REPORT_2026-10-16.md`: what was changed in the last session and why.
3. `README.md`: build and run instructions. `docs/BUILD_REPORT_macOS.md` explains the original source fixes.

**State of play:**
- `make` succeeds on Ubuntu 22.04/24.04 (x86_64 and arm64) and Amazon Linux 2023. This is
  confirmed by GitHub Actions.
- `tests/runSmallTests.sh` fails on all of them, cause unknown (logs could not be read without
  GitHub auth). On macOS, the same code passes the full suite 20/20.
- **Your first job is to reproduce that failure on an EC2 instance and find out whether it is real.**
  It could be a crash or a wrong energy, or just `scripts/check_tests.sh` matching harmless stderr.
  Quick start:
  ```bash
  git clone https://github.com/syedshah-web/dice.git && cd dice
  ./scripts/install_deps.sh && make -j"$(nproc)"
  cd tests && MPICOMMAND="mpirun -np 2" ./runSmallTests.sh 2>&1 | tee small.log
  ../scripts/check_tests.sh small.log
  ```
  Then look at `small.log` and each test's `output.dat`.

**Shortcut:** CI run `38943797940` (commit 86d7a2b) prints the failing log lines as annotations,
readable without auth. Check them before anything else:
```bash
curl -s https://api.github.com/repos/syedshah-web/dice/actions/runs/38943797940/jobs | python3 -c "import json,sys;[print(j['id'],j['name'],j['conclusion']) for j in json.load(sys.stdin)['jobs']]"
curl -s "https://api.github.com/repos/syedshah-web/dice/check-runs/<job_id>/annotations?per_page=100"
```
(With `gh` authenticated, `gh run view 38943797940 --log-failed` gives the full logs.)

**Things to know:**
- The test scripts always exit 0. A pass/fail verdict comes only from `check_tests.sh` or from grepping
  `PASSED`/`FAILED`.
- One memory-corruption bug was already found: an `MPI_Bcast` of an `int` declared as `MPI_DOUBLE` in
  `Davidson.cpp`. If you see crashes, look for more datatype mismatches of that kind first.
- `SHCIshm.cpp` uses shared memory. In Docker, give the container `--shm-size=1g` or more.
- Boost.MPI must be built against the same MPI you run with. For EFA/ParallelCluster, use
  `scripts/build_boost.sh` with `/opt/amazon/openmpi/bin` on PATH.

**Ground rules:** keep source changes minimal and record each one in the README's "What was changed"
list. Never edit the `trusted*` reference files to make tests pass. Get CI on `main` green
(`.github/workflows/build.yml`) and commit any AWS test logs under `docs/`.

Good luck. Please leave a short report of your own in `docs/` for whoever comes next.
