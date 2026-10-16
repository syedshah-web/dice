#!/usr/bin/env bash
# Fail (exit 1) if a Dice test log contains failures or Python errors, or no passes.
#   ./tests/runSmallTests.sh 2>&1 | tee tests.log; ./scripts/check_tests.sh tests.log
set -u
log="$1"
pattern="FAILED|Traceback|Error|No such file|Abort|Segmentation fault|exited on signal"
pass=$(grep -c "PASSED" "$log" || true)
fail=$(grep -c "FAILED" "$log" || true)
err=$(grep -cE "Traceback|Error|No such file|Abort|Segmentation fault|exited on signal" "$log" || true)
echo "PASSED=$pass FAILED=$fail ERRORS=$err"
ok=0
[ "$fail" -eq 0 ] && [ "$err" -eq 0 ] && [ "$pass" -gt 0 ] || ok=1
if [ "$ok" -ne 0 ] && [ -n "${GITHUB_ACTIONS:-}" ]; then
    # Surface the problem lines as annotations (readable without downloading logs).
    echo "::error::PASSED=$pass FAILED=$fail ERRORS=$err"
    grep -nE -B3 "$pattern" "$log" | head -40 | while IFS= read -r line; do
        echo "::warning::${line//%/%25}"
    done
    tail -15 "$log" | while IFS= read -r line; do echo "::notice::tail: ${line//%/%25}"; done
fi
exit $ok
