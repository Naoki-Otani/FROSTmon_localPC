#!/usr/bin/env bash
# local_divideDat_dispatcher.sh
# Runs on YOUR LOCAL PC. (with SSH multiplexing for stability)
# Submits KEKCC LSF jobs to split run*.dat into CHUNK_SIZE events using extract_events.
# No resident process on KEKCC; only LSF jobs (probe/extract). Local daily logs are kept.
#
set -Eeuo pipefail
IFS=$' \n\t'
export LC_ALL=C LANG=C

############################
# Config (EDIT THESE)
############################
source /home/daq/FROSTmon/config/config.env
REMOTE_HOST="kekcc"   # SSH alias for login.cc.kek.jp in your ~/.ssh/config

# Remote paths on KEKCC
SRC_DIR="$DAT_DIR"
OUT_DIR="$DIV_DIR"
PROBE_DIR="$OUT_DIR/.probe"
LSF_OUT_DIR="$OUT_DIR/lsf_out"

# Extractor binary on KEKCC (DO NOT modify the binary itself)
EXTRACT_CMD="/home/nu/notani/FROST_monitor/divideevent/src/extract_events"

# Behavior
CHUNK_SIZE=10000           # events per split file
INTERVAL=300                # seconds between dispatcher scans
QUEUE="l"                  # LSF queue
MAX_JOBS=0                 # cap of active extract jobs (0 = unlimited). Probe jobs are lightweight.
PROBE_MIN_INTERVAL=300     # seconds: min interval between two probe submissions for the same run

# Job name prefixes
JOB_PREFIX_PROBE="divide_probe_"
JOB_PREFIX_EXTRACT="divide_extract_"

# Local logging
LOG_DIR="../logs"
MIRROR_TO_CONSOLE="yes"    # "yes" -> tee to console; "no" -> only file

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
  ssh -O check $SSH_BASE_OPTS "$REMOTE_HOST" >/dev/null 2>&1 || ssh -MNf $SSH_BASE_OPTS "$REMOTE_HOST"
}

############################
# Helpers (local / remote)
############################
ts(){ date "+%Y-%m-%d %H:%M:%S"; }

log_setup(){
  mkdir -p "$LOG_DIR"
  local lf="$LOG_DIR/$(date +%F).divideDat_dispatcher.log"
  if [[ "$MIRROR_TO_CONSOLE" == "yes" ]]; then
    exec > >(tee -a "$lf") 2>&1
  else
    exec >>"$lf" 2>&1
  fi
  echo "[$(ts)] --- local_divideDat_dispatcher.sh started ---"
  echo "[$(ts)] Logging to: $lf (mirror=$MIRROR_TO_CONSOLE)"
  echo "[$(ts)] REMOTE_HOST: $REMOTE_HOST"
  echo "[$(ts)] SRC_DIR    : $SRC_DIR"
  echo "[$(ts)] OUT_DIR    : $OUT_DIR"
  echo "[$(ts)] PROBE_DIR  : $PROBE_DIR"
  echo "[$(ts)] LSF_OUT    : $LSF_OUT_DIR"
  echo "[$(ts)] EXTRACT_CMD: $EXTRACT_CMD"
  echo "[$(ts)] CHUNK_SIZE : $CHUNK_SIZE"
}

# Robust remote command runner with SSH multiplexing, KeepAlive and retries
rcmd(){
  local cmd="$*"
  local tries=5 back=5 i
  # try to ensure we have a live master connection
  ensure_master >/dev/null 2>&1 || true
  for ((i=1;i<=tries;i++)); do
    if ssh $SSH_BASE_OPTS "$REMOTE_HOST" bash -lc "source ~/.bashrc >/dev/null 2>&1; $cmd"; then
      return 0
    fi
    echo "[$(ts)] WARN: rcmd attempt $i/$tries failed; retry in ${back}s: $cmd" >&2
    # recycle the master connection if it looks unhealthy, then backoff
    ssh -O exit $SSH_BASE_OPTS "$REMOTE_HOST" >/dev/null 2>&1 || true
    sleep "$back"; back=$(( back<60 ? back*2 : 60 ))
    ensure_master >/dev/null 2>&1 || true
  done
  echo "[$(ts)] ERROR: rcmd failed after $tries attempts: $cmd" >&2
  return 1
}

# Get newest run file path (or empty string)
latest_run_path(){
  rcmd "ls -t '$SRC_DIR'/run*.dat 2>/dev/null | head -n1 || true" || echo ""
}

# Extract base run name "runNNNNN" from a full path
run_base_from_path(){
  local p="$1"
  p="${p##*/}"; echo "${p%.dat}"
}

# Count LSF jobs whose name starts with a prefix
r_jobs_count(){
  local pfx="$1"
  rcmd "bjobs -w 2>/dev/null | awk '\$1 ~ /^'\"\$pfx\"'/ {c++} END{print c+0}'" || echo 0
}

# Check if a named job exists (queued or running)
r_job_exists(){
  local name="$1"
  rcmd "bjobs -w 2>/dev/null | awk '\$1==\"$name\"{f=1}END{exit(!f)}'"
}

# Compute next chunk [start end] by inspecting existing split files on KEKCC.
# Logic: read max_end from filenames '<run>_<start>_<end>.dat' and compute locally.
r_next_chunk_for_run(){
  local run="$1"
  local max_end
  max_end="$(rcmd "ls -1 '$OUT_DIR'/${run}_*_*.dat 2>/dev/null | awk 'match(\$0,/_[0-9]+_([0-9]+)\\.dat$/,a){print a[1]}' | sort -n | tail -1 || true" || true)"
  if [[ -z "$max_end" ]]; then
    echo "0 $((CHUNK_SIZE-1))"
    return
  fi
  if ! [[ "$max_end" =~ ^[0-9]+$ ]]; then
    echo "0 $((CHUNK_SIZE-1))"
    return
  fi
  local next_start=$((max_end + 1))
  local next_end=$((next_start + CHUNK_SIZE - 1))
  echo "$next_start $next_end"
}

# Submit a probe job to learn the current max event in <run>.dat.
submit_probe_job(){
  local run="$1"
  local file="$SRC_DIR/${run}.dat"
  local pstart=4294960000
  local pend=$((pstart+1))
  local jname="${JOB_PREFIX_PROBE}${run}"
  local lsfout="$LSF_OUT_DIR/${jname}.out"
  echo "[$(ts)] PROBE submit: $jname"
  rcmd "mkdir -p '$PROBE_DIR' '$LSF_OUT_DIR' && bsub -q '$QUEUE' -J '$jname' -o '$lsfout' '$EXTRACT_CMD' '$file' '$PROBE_DIR' '$pstart' '$pend'" || true
}

# Read the probe result from LSF log. Echos integer max event, or -1 if not ready/missing.
probe_max_from_log(){
  local run="$1"
  local jname="${JOB_PREFIX_PROBE}${run}"
  local lsfout="$LSF_OUT_DIR/${jname}.out"

  # If job still exists, not ready
  if r_job_exists "$jname"; then
    echo -1
    return
  fi

  # Take only the last "Max event number..." line's numeric value (avoid concatenation)
  local val
  val="$(rcmd "awk -F': ' '/^Max event number in file: /{v=\$2} END{if(v!=\"\") print v}' '$lsfout' 2>/dev/null || true" || true)"
  if [[ -n "$val" && "$val" =~ ^[0-9]+$ ]]; then
    echo "$val"
  else
    echo -1
  fi
}

# Submit an extract job for [start,end]. Skips if output exists or job already queued.
submit_extract_job(){
  local run="$1" start="$2" end="$3"
  local file="$SRC_DIR/${run}.dat"
  local base="${run}_${start}_${end}"
  local out="$OUT_DIR/${base}.dat"
  local jname="${JOB_PREFIX_EXTRACT}${base}"
  local lsfout="$LSF_OUT_DIR/${jname}.out"

  # Already produced?
  if rcmd "[[ -f '$out' ]]" ; then
    echo "[$(ts)] SKIP (exists): $base"
    return 0
  fi
  # Already queued/running?
  if r_job_exists "$jname"; then
    echo "[$(ts)] SKIP (queued): $jname"
    return 0
  fi

  echo "[$(ts)] EXTRACT submit: $jname"
  rcmd "mkdir -p '$OUT_DIR' '$LSF_OUT_DIR' && bsub -q '$QUEUE' -J '$jname' -o '$lsfout' '$EXTRACT_CMD' '$file' '$OUT_DIR' '$start' '$end'" || true
}

############################
# Main loop
############################
main(){
  log_setup

  # Warm up a persistent SSH master connection up front (best-effort).
  ensure_master >/dev/null 2>&1 || true

  local active_run=""
  local latest_path latest_run next_start next_end max_event njobs

  # per-run probe throttling state (active runのみ管理)
  local last_probe_ts=0
  local last_probe_val=-1
  local last_probe_inflight=0   # 0:なし / 1:投入済み（結果待ち）

  while true; do
    latest_path="$(latest_run_path || true)"
    latest_run=""
    [[ -n "$latest_path" ]] && latest_run="$(run_base_from_path "$latest_path")"

    # Initialize active run
    if [[ -z "$active_run" && -n "$latest_run" ]]; then
      active_run="$latest_run"
      echo "[$(ts)] Active run set to: $active_run"
      last_probe_ts=0
      last_probe_val=-1
      last_probe_inflight=0
    fi

    # If the latest changed, drain the old run fully first
    if [[ -n "$latest_run" && -n "$active_run" && "$latest_run" != "$active_run" ]]; then
      echo "[$(ts)] Run switch detected: $active_run -> $latest_run (drain old run)"

      # ensure a probe (throttled) for old run
      if (( last_probe_inflight == 0 )); then
        if ! r_job_exists "${JOB_PREFIX_PROBE}${active_run}"; then
          now=$(date +%s)
          if (( now - last_probe_ts >= PROBE_MIN_INTERVAL )); then
            submit_probe_job "$active_run"
            last_probe_ts=$now
            last_probe_inflight=1
          fi
        else
          last_probe_inflight=1
        fi
      fi

      # update probe value if ready
      max_event="$(probe_max_from_log "$active_run" || true)"
      if [[ "$max_event" =~ ^[0-9]+$ && "$max_event" -ge 0 ]]; then
        last_probe_val="$max_event"
        last_probe_inflight=0
      fi

      if (( last_probe_val >= 0 )); then
        while true; do
          read -r next_start next_end < <(r_next_chunk_for_run "$active_run")
          if (( next_start > last_probe_val )); then
            echo "[$(ts)] Drained $active_run up to max=$last_probe_val"
            break
          fi
          if (( next_end > last_probe_val )); then next_end="$last_probe_val"; fi
          submit_extract_job "$active_run" "$next_start" "$next_end"

          # Optional throttle
          if (( MAX_JOBS > 0 )); then
            njobs="$(r_jobs_count "$JOB_PREFIX_EXTRACT")"
            if (( njobs >= MAX_JOBS )); then
              break
            fi
          fi
        done

        # Switch to new run
        active_run="$latest_run"
        echo "[$(ts)] Switched active run to: $active_run"
        # reset probe state for new run
        last_probe_ts=0
        last_probe_val=-1
        last_probe_inflight=0
      else
        echo "[$(ts)] WAIT: need probe result for $active_run ..."
      fi

      sleep "$INTERVAL"
      continue
    fi

    # Normal processing
    if [[ -z "$active_run" ]]; then
      echo "[$(ts)] IDLE: waiting for first run file ..."
      sleep "$INTERVAL"
      continue
    fi

    # Decide next chunk
    read -r next_start next_end < <(r_next_chunk_for_run "$active_run")

    # Ensure probe exists / throttled
    if (( last_probe_inflight == 0 )); then
      if ! r_job_exists "${JOB_PREFIX_PROBE}${active_run}"; then
        now=$(date +%s)
        if (( now - last_probe_ts >= PROBE_MIN_INTERVAL )); then
          submit_probe_job "$active_run"
          last_probe_ts=$now
          last_probe_inflight=1
        fi
      else
        last_probe_inflight=1
      fi
    fi

    # Try to read probe result (update cache if available)
    max_event="$(probe_max_from_log "$active_run" || true)"
    if [[ "$max_event" =~ ^[0-9]+$ && "$max_event" -ge 0 ]]; then
      last_probe_val="$max_event"
      last_probe_inflight=0
    fi

    if (( last_probe_val >= next_end )); then
      submit_extract_job "$active_run" "$next_start" "$next_end"

      # Check throttle
      if (( MAX_JOBS > 0 )); then
        njobs="$(r_jobs_count "$JOB_PREFIX_EXTRACT")"
        if (( njobs >= MAX_JOBS )); then
          echo "[$(ts)] THROTTLE: active extract jobs=$njobs >= $MAX_JOBS"
          sleep "$INTERVAL"
          continue
        fi
      fi
    else
      echo "[$(ts)] WAIT: need end=$next_end but max=$last_probe_val (probing)"
      sleep "$INTERVAL"
      continue
    fi

    sleep "$INTERVAL"
  done
}

main "$@"
