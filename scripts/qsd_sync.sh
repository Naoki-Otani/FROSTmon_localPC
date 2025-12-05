#!/bin/bash
set -euo pipefail

########################################
# Load configuration
########################################
# Expected variables in config.env:
#   SCBN_DIR_QSDFILE : directory on scbn that contains QSDfile
#   KEKCC_DIR_BSD    : target directory "bsd" on KEKCC
source /home/daq/FROSTmon/config/config.env

########################################
# Hosts
########################################
# These hostnames should be resolvable via SSH config (~/.ssh/config)
#   Host scbn  -> scbn00 (or similar)
#   Host kekcc -> login.cc.kek.jp (or similar)
SCBN_HOST="scbn"
KEKCC_HOST="kekcc"

########################################
# Directories
########################################
# Remote source/destination directories (from config.env)
SRC_DIR_QSDFILE="$SCBN_DIR_QSDFILE"
DST_DIR_BSD="$KEKCC_DIR_BSD"

# Local staging directory (on this DAQ machine)
LOCAL_DIR_QSDFILE="/home/daq/FROSTmon/qsd"

# Log file
LOG_DIR="/home/daq/FROSTmon/logs"
LOG_FILE="$LOG_DIR/qsd_sync.log"

########################################
# Prepare directories
########################################
mkdir -p "$LOCAL_DIR_QSDFILE"
mkdir -p "$LOG_DIR"

########################################
# Helper: timestamp
########################################
timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

echo "[$(timestamp)] ===== scbn -> kekcc(bsd) sync start =====" >> "$LOG_FILE"

########################################
# Step 1: scbn -> local
########################################
# Sync all files in the directory that contains QSDfile on scbn
echo "[$(timestamp)] rsync from ${SCBN_HOST}:${SRC_DIR_QSDFILE} to ${LOCAL_DIR_QSDFILE}" >> "$LOG_FILE"
rsync -av \
  --partial --inplace \
  "${SCBN_HOST}:${SRC_DIR_QSDFILE}/" \
  "$LOCAL_DIR_QSDFILE/" >> "$LOG_FILE" 2>&1

########################################
# Step 2: local -> KEKCC (bsd)
########################################
# Sync from local staging directory to KEKCC bsd directory
echo "[$(timestamp)] rsync from ${LOCAL_DIR_QSDFILE} to ${KEKCC_HOST}:${DST_DIR_BSD}" >> "$LOG_FILE"
rsync -av \
  --partial --inplace \
  --chmod=F644,D755 \
  "$LOCAL_DIR_QSDFILE/" \
  "${KEKCC_HOST}:${DST_DIR_BSD}" >> "$LOG_FILE" 2>&1

echo "[$(timestamp)] ===== scbn -> kekcc(bsd) sync end =====" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"
