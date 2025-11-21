# FROST monitor job dispatcher (KEKCC)

This repository contains a **local-side dispatcher script** that keeps several
FROST monitor jobs continuously running on KEKCC using the LSF batch system.

The dispatcher itself runs **on your local PC** and submits jobs to KEKCC
via SSH. It periodically checks whether a given job is running or queued, and
(if not) resubmits it so that each program is almost always running. For each
program, **only one job is allowed at a time**.

## Monitored programs on KEKCC

The dispatcher manages the following programs on KEKCC:

- **Calibration**
  - Path: `/home/nu/notani/FROST_monitor/calibration/src`
  - Executable: `./calibration`

- **Light-yield conversion**
  - Path: `/home/nu/notani/FROST_monitor/calibration/src`
  - Executable: `./convertlightyield`

- **Data-quality plotting**
  - Path: `/home/nu/notani/FROST_monitor/dataquality/src`
  - Executable: `./dataqualityplot`

- **Latest dat-file update script**
  - Path: `/home/nu/notani/FROST_monitor/monitor_latestdat/src`
  - Executable: `./update_latest_dat.sh`

Each of these is submitted as an LSF job and kept alive by the dispatcher.
If a job finishes (for example because of LSF wall-time limits), the dispatcher
detects that it is no longer running and submits a new job.

## How it works

- The script runs on your **local PC**.
- It uses the SSH alias `kekcc` to connect to the KEKCC login node
  (`login.cc.kek.jp`) as configured in your `~/.ssh/config`.
- It enables **SSH multiplexing (ControlMaster/ControlPersist)** to reuse a
  single persistent SSH connection. This avoids rate limiting and the error  
  `kex_exchange_identification: read: Connection reset by peer`.
- In each loop:
  1. For each monitored program, it checks via `bjobs -w` whether a job with
     the corresponding name is queued or running.
  2. If the job is **not present**, the dispatcher submits a new job using
     `bsub`.
  3. It then sleeps for a configurable `INTERVAL` before checking again.

Because LSF imposes wall-time limits, jobs may be killed once they exceed the
limit. From the dispatcher’s point of view this is fine: once the job disappears
from the queue, the dispatcher will simply submit a new one.

> **Important:** The dispatcher guarantees "at most one job per program"
> only if you run **a single instance** of the dispatcher.  
> Do **not** run multiple copies at the same time.

## Requirements

### On your **local PC**

- A working SSH setup to KEKCC with an alias named `kekcc`:

  ```sshconfig
  Host kekcc
    HostName login.cc.kek.jp
    User YOUR_KEK_USERNAME
    ServerAliveInterval 30
    ServerAliveCountMax 3
    TCPKeepAlive yes
    IdentitiesOnly yes
    IdentityFile ~/.ssh/id_ed25519_kek
  ```

- SSH key-based login (non-interactive).  
  Password or OTP login is **not supported** by the dispatcher.

### On **KEKCC**

The following programs must exist and be executable:

```
/home/nu/notani/FROST_monitor/calibration/src/calibration
/home/nu/notani/FROST_monitor/calibration/src/convertlightyield
/home/nu/notani/FROST_monitor/dataquality/src/dataqualityplot
/home/nu/notani/FROST_monitor/monitor_latestdat/src/update_latest_dat.sh
```

The LSF profile must be available at:

```
/opt/lsf/conf/profile.lsf
```

The dispatcher loads this profile automatically before running `bsub`/`bjobs`.

## Configuration overview

Inside the dispatcher script you will see settings like:

```bash
REMOTE_HOST="kekcc"
QUEUE="l"
INTERVAL=60
RCMD_RETRY=3
```

Per-program settings look like:

```bash
CALIB_DIR="/home/.../calibration/src"
CALIB_CMD="./calibration"
CALIB_JOB_NAME="calibration"
CALIB_LSF_OUT="/home/.../calibration/lsf_out"
```

You may adjust:

- `QUEUE`  
- `INTERVAL` (check frequency)
- `*_LSF_OUT` directories  
- `EXTRA_BSUB_OPTS` for additional LSF instructions

## How to run

1. Save the dispatcher script on your local PC, for example:

   ```
   local_frost_monitor_jobs_dispatcher.sh
   ```

2. Make it executable:

   ```bash
   chmod +x local_frost_monitor_jobs_dispatcher.sh
   ```

3. Start it:

   ```bash
   nohup ./local_frost_monitor_jobs_dispatcher.sh &
   ```

   (or run it inside `tmux` / `screen`)

4. Logs are written on your local PC under `./logs/`:

   ```
   2025-11-14.frost_monitor_jobs_dispatcher.log
   ```

## Stopping the dispatcher

Stop it by killing the process on your local PC:

```bash
ps aux | grep local_frost_monitor_jobs_dispatcher
kill <PID>
```

Running jobs already submitted to KEKCC will continue until they finish.

## Notes and caveats

- If a monitored program crashes immediately, the dispatcher will continuously resubmit it.
  Check the corresponding `.out` logs on KEKCC.
- Make sure to run **only one** copy of the dispatcher.
- The dispatcher assumes that each monitored program is safe to restart when stopped by the LSF time limit.
