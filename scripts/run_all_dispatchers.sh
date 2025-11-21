#!/usr/bin/env bash
set -euo pipefail

SCRIPTS_DIR="/home/daq/FROSTmon/scripts"

cd "$SCRIPTS_DIR"

# ===== Helper =====
start_if_not_running() {
    local name="$1"
    local script="$2"

    # Already running?
    if pgrep -f "$script" > /dev/null 2>&1; then
        echo "[INFO] $name is already running."
    else
        echo "[INFO] Starting $name ..."
        nohup "$SCRIPTS_DIR/$script" >/dev/null 2>&1 &
    fi
}

# ===== Start 3 dispatchers =====
start_if_not_running "divideDat"        "local_divideDat_dispatcher.sh"
start_if_not_running "convertFromDat"   "local_convertFromDatToRoot_dispatcher.sh"
start_if_not_running "frost_monitor"    "local_frost_monitor_jobs_dispatcher.sh"

echo "[INFO] All dispatchers are ensured running."
