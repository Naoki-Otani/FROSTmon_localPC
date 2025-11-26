#!/usr/bin/env bash
# local_convertFromDatToRoot_dispatcher.sh
# Runs on YOUR LOCAL PC.
# Periodically scans remote divided .dat files on KEKCC and submits conversion jobs via:
#   ssh kekcc bash -c '. /opt/lsf/conf/profile.lsf; bsub ... convert_one_rayraw.sh <dat> <root>'
# There is NO dispatcher job on KEKCC; only workers (convert_one_rayraw.sh) run there.

set -Eeuo pipefail
IFS=$' \n\t'
export LC_ALL=C LANG=C

############################
# Config (EDIT THESE)
############################
source /home/daq/FROSTmon/config/config.env

REMOTE_HOST="kekcc"   # ssh alias to login.cc.kek.jp in your ~/.ssh/config

DIV_DIR="$DIV_DIR"
ROOT_DIR="$ROOT_DIR"
WORKER_SCRIPT="/home/nu/notani/FROST_monitor/OfflineAnalyzer/src/convert_one_rayraw.sh"  # path on KEKCC
LSF_OUT_DIR="$ROOT_DIR/lsf_out"

QUEUE="l"
JOB_NAME_PREFIX="rayraw"

INTERVAL=30            # seconds between scans
WAIT_STABLE_SECS=60    # remote stability window (file size unchanged)

# Concurrency cap for running/queued conversion jobs (0 = unlimited)
MAX_JOBS=0

# Extra bsub options if needed (e.g., email notifications)
EXTRA_BSUB_OPTS=""

# SSH retry (per logical command; each attempt may recycle the master connection)
RCMD_RETRY=3

############################
# SSH Multiplexing (ControlMaster)
############################
# Reuse a single persistent SSH connection to avoid server-side rate limiting and
# "kex_exchange_identification: read: Connection reset by peer" errors.
# ControlPath must be a stable, user-writable location.
SSH_CTL_PATH="${HOME}/.ssh/cm-%r@%h:%p"
SSH_BASE_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 \
  -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o TCPKeepAlive=yes \
  -o ControlMaster=auto -o ControlPersist=600 -S ${SSH_CTL_PATH}"

ensure_master(){
  ssh -O check $SSH_BASE_OPTS "$REMOTE_HOST" >/dev/null 2>&1 || \
    ssh -MNf $SSH_BASE_OPTS "$REMOTE_HOST"
}

############################
# Helpers
############################
ts(){ date "+%Y-%m-%d %H:%M:%S"; }

# Run a command on KEKCC without triggering login shell noise.
# We DO NOT source ~/.bashrc; we ONLY source LSF profile quietly.
_rcmd_once() {
  local cmd="$1"
  ssh $SSH_BASE_OPTS "$REMOTE_HOST" \
    /bin/bash -c ". /opt/lsf/conf/profile.lsf >/dev/null 2>&1 || true; $cmd"
}

# Robust remote command runner with SSH multiplexing, KeepAlive, and retries
rcmd() {
  local cmd="$1"
  local attempt=1
  local sleep_s=3

  # Try to ensure we have a live SSH master connection (best-effort).
  ensure_master >/dev/null 2>&1 || true

  while true; do
    if _rcmd_once "$cmd"; then
      return 0
    fi
    if (( attempt >= RCMD_RETRY )); then
      echo "[$(ts)] ERROR: rcmd failed after $RCMD_RETRY attempts: $cmd"
      return 1
    fi
    echo "[$(ts)] WARN: rcmd attempt $attempt/$RCMD_RETRY failed; retry in ${sleep_s}s: $cmd"
    # Recycle the master connection if it looks unhealthy, then back off
    ssh -O exit $SSH_BASE_OPTS "$REMOTE_HOST" >/dev/null 2>&1 || true
    ensure_master >/dev/null 2>&1 || true
    sleep "$sleep_s"
    attempt=$((attempt+1))
    sleep_s=$((sleep_s*2))
  done
}

r_exists() {
  local p="$1"
  rcmd "[[ -e \"$p\" ]]"
}

# Non-zero file size?
r_size_nonzero() {
  local p="$1"
  rcmd 'sz=$(stat -c%s "'"$p"'" 2>/dev/null || stat -f%z "'"$p"'" 2>/dev/null || echo -1); [[ "$sz" -gt 0 ]]'
}

# Size stable over WAIT_STABLE_SECS?
r_is_stable() {
  local p="$1"
  rcmd 's1=$(stat -c%s "'"$p"'" 2>/dev/null || stat -f%z "'"$p"'" 2>/dev/null || echo -1); sleep '"$WAIT_STABLE_SECS"'; s2=$(stat -c%s "'"$p"'" 2>/dev/null || stat -f%z "'"$p"'" 2>/dev/null || echo -1); [[ "$s1" -ge 0 && "$s1" == "$s2" ]]'
}

r_bjobs_count() {
  local pfx="$1"
  # Count jobs whose NAME starts with prefix
  rcmd 'bjobs -w 2>/dev/null | awk '\''$1 ~ /^'"$pfx"'/ {c++} END{print c+0}'\'''
}

submit_job() {
  local dat="$1"
  local root="$2"
  local base
  base="$(basename "$dat" .dat)"
  local jname="${JOB_NAME_PREFIX}_${base}"
  local lsfout="$LSF_OUT_DIR/${base}.out"

  echo "[$(ts)] SUBMIT: $jname"
  # NOTE: we assume $LSF_OUT_DIR exists already on KEKCC.
  # shellcheck disable=SC2086
  rcmd "bsub -q '$QUEUE' -J '$jname' -o '$lsfout' $EXTRA_BSUB_OPTS '$WORKER_SCRIPT' '$dat' '$root'"
}

############################
# Main loop
############################
main() {
  # ---- Local logging ----
  local LOG_DIR="../logs"
  mkdir -p "$LOG_DIR"
  local LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).convertFromDatToRoot_dispatcher.log"
  exec > >(tee -a "$LOG_FILE") 2>&1

  echo "[$(ts)] --- local_convertFromDatToRoot_dispatcher.sh started ---"
  echo "[$(ts)] Logging to: $LOG_FILE"
  echo "[$(ts)] local_convertFromDatToRoot_dispatcher.sh started (LOCAL PC → KEKCC)"
  echo "[$(ts)] REMOTE_HOST: $REMOTE_HOST"
  echo "[$(ts)] DIV_DIR    : $DIV_DIR"
  echo "[$(ts)] ROOT_DIR   : $ROOT_DIR"
  echo "[$(ts)] WORKER     : $WORKER_SCRIPT"
  echo "[$(ts)] INTERVAL   : ${INTERVAL}s, WAIT_STABLE_SECS: ${WAIT_STABLE_SECS}s"
  echo "[$(ts)] MAX_JOBS   : $MAX_JOBS (0=unlimited)"

  # Warm up a persistent SSH master connection up front (best-effort).
  ensure_master >/dev/null 2>&1 || true

  # Ensure remote LSF output directory exists on KEKCC.
  echo "[$(ts)] Ensuring LSF_OUT_DIR exists on KEKCC: $LSF_OUT_DIR"
  if ! rcmd "mkdir -p '$LSF_OUT_DIR'"; then
    echo "[$(ts)] ERROR: failed to create LSF_OUT_DIR on KEKCC: $LSF_OUT_DIR"
    exit 1
  fi

  while true; do
    # Concurrency throttle
    if (( MAX_JOBS > 0 )); then
      local njobs
      njobs="$(r_bjobs_count "$JOB_NAME_PREFIX" || echo 0)"
      if [[ -n "$njobs" && "$njobs" =~ ^[0-9]+$ ]] && (( njobs >= MAX_JOBS )); then
        echo "[$(ts)] THROTTLE: running/queued=$njobs >= MAX_JOBS=$MAX_JOBS; sleep $INTERVAL"
        sleep "$INTERVAL"
        continue
      fi
    fi

    # List newest-first remote .dat files
    mapfile -t files < <(rcmd "ls -t '$DIV_DIR'/*.dat 2>/dev/null || true")
    if (( ${#files[@]} == 0 )); then
      echo "[$(ts)] IDLE: no .dat in $DIV_DIR; sleep $INTERVAL"
      sleep "$INTERVAL"
      continue
    fi

    submitted_any="no"
    for dat in "${files[@]}"; do
      base="${dat##*/}"; base="${base%.dat}"
      root="$ROOT_DIR/${base}.root"
      doneflag="${root}.done"
      jname="${JOB_NAME_PREFIX}_${base}"

      # Skip if already converted/done
      if r_exists "$root" || r_exists "$doneflag"; then
        continue
      fi

      # Skip if job already queued/running
      if rcmd "bjobs -w 2>/dev/null | awk '\$1==\"$jname\"{f=1}END{exit(!f)}'"; then
        continue
      fi

      # Must be non-zero size
      if ! r_size_nonzero "$dat"; then
        echo "[$(ts)] SKIP (zero size): $base"
        continue
      fi

      # Stability check (remote)
      if ! r_is_stable "$dat"; then
        echo "[$(ts)] WAIT (growing): $base"
        continue
      fi

      # Submit
      submit_job "$dat" "$root" && submitted_any="yes"

      # Respect MAX_JOBS after each submit
      if (( MAX_JOBS > 0 )); then
        njobs="$(r_bjobs_count "$JOB_NAME_PREFIX" || echo 0)"
        if [[ -n "$njobs" && "$njobs" =~ ^[0-9]+$ ]] && (( njobs >= MAX_JOBS )); then
          break
        fi
      fi
    done

    if [[ "$submitted_any" != "yes" ]]; then
      echo "[$(ts)] IDLE: nothing to submit; sleep $INTERVAL"
    fi
    sleep "$INTERVAL"
  done
}

main "$@"
