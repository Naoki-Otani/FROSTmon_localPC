#!/usr/bin/env bash
# local_frost_monitor_jobs_dispatcher.sh
# Runs on YOUR LOCAL PC.
#
# Keeps several FROST monitor programs continuously running on KEKCC
# by periodically checking LSF jobs and (re)submitting them via SSH.
#
# Programs on KEKCC:
#   /home/nu/notani/FROST_monitor/calibration/src/calibration
#   /home/nu/notani/FROST_monitor/calibration/src/convertlightyield
#   /home/nu/notani/FROST_monitor/dataquality/src/dataqualityplot
#   /home/nu/notani/FROST_monitor/monitor_latestdat/src/update_latest_dat.sh
#
# For each program, at most ONE job is allowed at a time.
# If the job disappears (e.g. wall-time limit), a new job is submitted.

set -Eeuo pipefail
IFS=$' \n\t'
export LC_ALL=C LANG=C

############################
# Config (EDIT THESE)
############################
REMOTE_HOST="kekcc"   # ssh alias to login.cc.kek.jp in your ~/.ssh/config
QUEUE="l"             # LSF queue name
INTERVAL=60           # seconds between scans
RCMD_RETRY=3          # SSH retries per logical command

# Extra bsub options (e.g. time limit, email, resources). Can be empty.
EXTRA_BSUB_OPTS=""

############################
# Per-program configuration
############################

# 1) Calibration
CALIB_DIR="/home/nu/notani/FROST_monitor/calibration/src"
CALIB_CMD="./calibration"
CALIB_JOB_NAME="calibration"
CALIB_LSF_OUT="/home/nu/notani/FROST_monitor/calibration/lsf_out"

# 2) Light-yield conversion
LY_DIR="/home/nu/notani/FROST_monitor/calibration/src"
LY_CMD="./convertlightyield"
LY_JOB_NAME="convertlightyield"
LY_LSF_OUT="/home/nu/notani/FROST_monitor/calibration/lsf_out"

# 3) Data-quality plot
DQ_DIR="/home/nu/notani/FROST_monitor/dataquality/src"
DQ_CMD="./dataqualityplot"
DQ_JOB_NAME="dataqualityplot"
DQ_LSF_OUT="/home/nu/notani/FROST_monitor/dataquality/lsf_out"

# 4) Sync BSD
BSD_DIR="/home/nu/notani/FROST_monitor/dataquality_withBSD/src"
BSD_CMD="./sync_bsd.sh"
BSD_JOB_NAME="sync_bsd"
BSD_LSF_OUT="/home/nu/notani/FROST_monitor/dataquality_withBSD/lsf_out"

# 5) Data-quality plot with BSD
DQWITHBSD_DIR="/home/nu/notani/FROST_monitor/dataquality_withBSD/src"
DQWITHBSD_CMD="./dataqualityplot_withBSD"
DQWITHBSD_JOB_NAME="dataqualityplot_withBSD"
DQWITHBSD_LSF_OUT="/home/nu/notani/FROST_monitor/dataquality_withBSD/lsf_out"

# 6) Latest dat-file updater
LATEST_DIR="/home/nu/notani/FROST_monitor/monitor_latestdat/src"
LATEST_CMD="./update_latest_dat.sh"
LATEST_JOB_NAME="update_latest_dat"
LATEST_LSF_OUT="/home/nu/notani/FROST_monitor/monitor_latestdat/lsf_out"

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

# Run a command on KEKCC, sourcing only the LSF profile (no ~/.bashrc noise).
_rcmd_once() {
  local cmd="$1"
  ssh $SSH_BASE_OPTS "$REMOTE_HOST" \
    /bin/bash -c ". /opt/lsf/conf/profile.lsf >/dev/null 2>&1 || true; $cmd"
}

# Robust remote command runner with SSH multiplexing and retries
rcmd() {
  local cmd="$1"
  local attempt=1
  local sleep_s=3

  # Make sure we have a live SSH master connection (best-effort)
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
    # recycle the master connection if unhealthy, then back off
    ssh -O exit $SSH_BASE_OPTS "$REMOTE_HOST" >/dev/null 2>&1 || true
    ensure_master >/dev/null 2>&1 || true
    sleep "$sleep_s"
    attempt=$((attempt+1))
    sleep_s=$((sleep_s*2))
  done
}

# Check if a job with the given name exists (queued or running), with debug logging.
job_exists() {
  local jname="$1"
  local raw

  # bjobs -w -J でジョブ名フィルタ。ジョブが無いときは「Job <...> is not found」か空。
  # "|| true" を付けて、exit code が非0でも rcmd がエラー扱いしないようにする。
  raw="$(
    rcmd "bjobs -w -J '$jname' 2>/dev/null || true" 2>/dev/null || true
  )"

  # デバッグ用に生の出力をログに残す（最初のうちは役立つ）
  # echo "[$(ts)] DEBUG: job_exists($jname) raw bjobs output:" >&2
  # if [[ -z "$raw" ]]; then
  #   echo "[$(ts)] DEBUG:  (empty output)" >&2
  # else
  #   echo "$raw" | sed 's/^/[BJOBS] /' >&2
  # fi

  # まったく何も出ていない → ジョブ無し
  if [[ -z "$raw" ]]; then
    return 1
  fi

  # 「Job <xxx> is not found」というメッセージが含まれていればジョブ無し
  if grep -qi 'is not found' <<<"$raw"; then
    return 1
  fi

  # JOBID 行（先頭が数字っぽい行）が1つでもあれば「存在する」とみなす
  if grep -E '^[[:space:]]*[0-9]+' <<<"$raw" >/dev/null 2>&1; then
    return 0
  fi

  # それ以外は一応「無い」と判定
  return 1
}

# Submit a persistent-style job for a given program (single instance)
submit_program_job() {
  local workdir="$1"
  local cmd="$2"
  local jname="$3"
  local lsfout_dir="$4"

  echo "[$(ts)] SUBMIT: $jname (workdir=$workdir)"

  # NOTE: %J in output filename will be replaced with LSF job ID
  rcmd "mkdir -p '$lsfout_dir' && \
        cd '$workdir' && \
        bsub -q '$QUEUE' -J '$jname' -o '$lsfout_dir/${jname}.%J.out' $EXTRA_BSUB_OPTS $cmd"
}

############################
# Main loop
############################
main() {
  # ---- Local logging ----
  local LOG_DIR="./logs"
  mkdir -p "$LOG_DIR"
  local LOG_FILE="$LOG_DIR/$(date +%Y-%m-%d).frost_monitor_jobs_dispatcher.log"
  exec > >(tee -a "$LOG_FILE") 2>&1

  echo "[$(ts)] --- local_frost_monitor_jobs_dispatcher.sh started ---"
  echo "[$(ts)] Logging to: $LOG_FILE"
  echo "[$(ts)] REMOTE_HOST: $REMOTE_HOST"
  echo "[$(ts)] QUEUE      : $QUEUE"
  echo "[$(ts)] INTERVAL   : ${INTERVAL}s"
  echo "[$(ts)] EXTRA_BSUB : $EXTRA_BSUB_OPTS"

  echo "[$(ts)] Program config:"
  echo "  CALIB : dir=$CALIB_DIR cmd=$CALIB_CMD job=$CALIB_JOB_NAME out=$CALIB_LSF_OUT"
  echo "  LY    : dir=$LY_DIR    cmd=$LY_CMD    job=$LY_JOB_NAME    out=$LY_LSF_OUT"
  echo "  DQ    : dir=$DQ_DIR    cmd=$DQ_CMD    job=$DQ_JOB_NAME    out=$DQ_LSF_OUT"
  echo "  LATEST: dir=$LATEST_DIR cmd=$LATEST_CMD job=$LATEST_JOB_NAME out=$LATEST_LSF_OUT"

  # Warm up a persistent SSH master connection (best-effort)
  ensure_master >/dev/null 2>&1 || true

  while true; do
    echo "[$(ts)] Scan loop start"

    # 1) calibration
    if job_exists "$CALIB_JOB_NAME"; then
      echo "[$(ts)] CALIB: job '$CALIB_JOB_NAME' already running/queued"
    else
      submit_program_job "$CALIB_DIR" "$CALIB_CMD" "$CALIB_JOB_NAME" "$CALIB_LSF_OUT"
    fi

    # 2) convertlightyield
    if job_exists "$LY_JOB_NAME"; then
      echo "[$(ts)] LY   : job '$LY_JOB_NAME' already running/queued"
    else
      submit_program_job "$LY_DIR" "$LY_CMD" "$LY_JOB_NAME" "$LY_LSF_OUT"
    fi

    # 3) dataqualityplot
    if job_exists "$DQ_JOB_NAME"; then
      echo "[$(ts)] DQ   : job '$DQ_JOB_NAME' already running/queued"
    else
      submit_program_job "$DQ_DIR" "$DQ_CMD" "$DQ_JOB_NAME" "$DQ_LSF_OUT"
    fi

    # 4 ) sync_bsd
    if job_exists "$BSD_JOB_NAME"; then
      echo "[$(ts)] BSD  : job '$BSD_JOB_NAME' already running/queued"
    else
      submit_program_job "$BSD_DIR" "$BSD_CMD" "$BSD_JOB_NAME" "$BSD_LSF_OUT"
    fi

    # 5 ) dataqualityplot_withBSD
    if job_exists "$DQWITHBSD_JOB_NAME"; then
      echo "[$(ts)] DQBSD: job '$DQWITHBSD_JOB_NAME' already running/queued"
    else
      submit_program_job "$DQWITHBSD_DIR" "$DQWITHBSD_CMD" "$DQWITHBSD_JOB_NAME" "$DQWITHBSD_LSF_OUT"
    fi

    # 6) update_latest_dat.sh
    if job_exists "$LATEST_JOB_NAME"; then
      echo "[$(ts)] LATEST: job '$LATEST_JOB_NAME' already running/queued"
    else
      submit_program_job "$LATEST_DIR" "$LATEST_CMD" "$LATEST_JOB_NAME" "$LATEST_LSF_OUT"
    fi

    echo "[$(ts)] Scan loop end; sleep $INTERVAL"
    sleep "$INTERVAL"
  done
}

main "$@"
