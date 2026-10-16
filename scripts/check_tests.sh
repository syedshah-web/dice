#!/usr/bin/env bash
# Fail (exit 1) if a Dice test log contains failures or Python errors, or no passes.
#   ./tests/runSmallTests.sh 2>&1 | tee tests.log; ./scripts/check_tests.sh tests.log
set -u
log="$1"
pass=$(grep -c "PASSED" "$log" || true)
fail=$(grep -c "FAILED" "$log" || true)
err=$(grep -cE "Traceback|No such file|Abort|Segmentation|signal" "$log" || true)
echo "PASSED=$pass FAILED=$fail ERRORS=$err"
[ "$fail" -eq 0 ] && [ "$err" -eq 0 ] && [ "$pass" -gt 0 ]
