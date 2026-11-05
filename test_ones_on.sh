#!/bin/bash
PID=$1
SIZE_MB=$2

echo "======================================="
echo "  TEST: ${SIZE_MB}MB ONES (ZSWAP ON)"
echo "======================================="

echo "---------------------------------------"
echo "MEMORY STATE AT MEASUREMENT"
echo "---------------------------------------"

free -h

echo
grep -E 'MemAvailable|SwapFree|Zswap|Zswapped|CommitLimit|Committed_AS' /proc/meminfo

echo
swapon --show

echo
echo "ZSWAP pool_limit_hit:"
sudo cat /sys/kernel/debug/zswap/pool_limit_hit

echo "---------------------------------------"

echo "Measuring ONES process started by C..."
echo "Process PID: $PID"

RSS=$(cat /proc/$PID/status 2>/dev/null | grep VmRSS | awk '{print $2}')
echo "RSS: ${RSS} KB (~$((RSS/1024))MB)"


STORED=$(sudo cat /sys/kernel/debug/zswap/stored_pages)
POOL=$(sudo cat /sys/kernel/debug/zswap/pool_total_size)
WRITEBACK=$(sudo cat /sys/kernel/debug/zswap/written_back_pages)
SAME=$(sudo cat /sys/kernel/debug/zswap/same_filled_pages)
REJECT_POOR=$(sudo cat /sys/kernel/debug/zswap/reject_compress_poor)
ZSWAP_KB=$(grep '^Zswap:' /proc/meminfo | awk '{print $2}')
ZSWAPPED_KB=$(grep '^Zswapped:' /proc/meminfo | awk '{print $2}')
# Only calculate whole-program compression ratio
# if the process is still alive and RSS was successfully measured
if [ -n "$RSS" ] && [ "$RSS" -gt 0 ]; then

    SWAP_TOTAL_KB=$(grep '^SwapTotal:' /proc/meminfo | awk '{print $2}')
    SWAP_FREE_KB=$(grep '^SwapFree:' /proc/meminfo | awk '{print $2}')
    SWAP_USED_KB=$((SWAP_TOTAL_KB - SWAP_FREE_KB))

    BACKING_SWAP_KB=$((SWAP_USED_KB - ZSWAPPED_KB))

    if [ "$BACKING_SWAP_KB" -lt 0 ]; then
           BACKING_SWAP_KB=0
    fi

    TOTAL_AFTER_KB=$((RSS + ZSWAP_KB + BACKING_SWAP_KB))
    ORIGINAL_KB=$((SIZE_MB * 1024))

    if [ "$TOTAL_AFTER_KB" -gt 0 ]; then
        WHOLE_RATIO=$(echo "scale=2; $ORIGINAL_KB / $TOTAL_AFTER_KB" | bc)

        echo "  Original footprint:              ${SIZE_MB} MB"
        echo "  Regular resident memory RSS:     ${RSS} KB"
        echo "  Physical ZSWAP memory:           ${ZSWAP_KB} KB"
        echo "  Swap used:                       ${SWAP_USED_KB} KB"
        echo "  Backing swap used:               ${BACKING_SWAP_KB} KB"
        echo "  Total memory after compression:  ${TOTAL_AFTER_KB} KB"
        echo "  Whole-program compression ratio: ${WHOLE_RATIO}:1"
    fi

else
    echo "  RSS unavailable - process may have been killed."
    echo "  Whole-program compression ratio: INVALID"
fi

echo "  stored_pages:         $STORED"
echo "  pool_total_size:      $POOL bytes"
echo "  same_filled_pages:    $SAME"
echo "  written_back_pages:   $WRITEBACK"
echo "  reject_compress_poor: $REJECT_POOR"
echo "  Zswap memory used:    ${ZSWAP_KB} KB"
echo "  Zswapped original:    ${ZSWAPPED_KB} KB"

if [ "$ZSWAP_KB" -gt 0 ]; then
    RATIO=$(echo "scale=2; $ZSWAPPED_KB / $ZSWAP_KB" | bc)
    echo "  Effective ZSWAP storage ratio: ${RATIO}:1"
else
    echo "  Effective ZSWAP storage ratio: N/A"
fi


echo
echo "POST-RUN OOM CHECK"
sudo dmesg | grep -i -E "oom|killed process|out of memory" | tail -20

CG="/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/app.slice/memory-test-scope.scope"

echo "---------------------------------------"
echo "CGROUP MEMORY FOR memory_test"
echo "---------------------------------------"

echo "Cgroup memory.current:      $(cat $CG/memory.current)"
echo "Cgroup memory.swap.current: $(cat $CG/memory.swap.current)"
echo "Cgroup memory.zswap.current: $(cat $CG/memory.zswap.current)"
echo "======================================="
echo "              DONE"
echo "======================================="
