#!/bin/bash

INTERVAL="${1:-5}"
LOG_FILE="monitor.log"

if ! [[ "$INTERVAL" =~ ^[1-9][0-9]*$ ]]; then
    echo "Usage: $0 [interval_in_seconds]"
    exit 1
fi

echo "Monitoring started. Interval: ${INTERVAL}s"
echo "Press Ctrl+C to stop."

while true; do
    {
        echo "========================================"
        echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "--- System uptime ---"
        uptime
        echo "--- Memory usage ---"
        free -h
        echo "--- Disk usage ---"
        df -h /
        echo
    } >> "$LOG_FILE"

    echo "System information saved to $LOG_FILE"
    sleep "$INTERVAL"
done
