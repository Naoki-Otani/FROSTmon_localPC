# QSD File Auto-Synchronization Script (`qsd_sync.sh`)

This document describes the script `qsd_sync.sh`, which automatically synchronizes QSD-related files between:

- **scbn** (source data directory containing QSD files)
- **Local machine** (staging area)
- **KEKCC** (`bsd` directory on the KEKCC side)

The script runs on the **Local machine** and is intended to be executed periodically via `cron`.

---

## 1. Script Overview

`qsd_sync.sh` performs the following sequence of operations:

### Step 1 — Sync from scbn → Local machine

The script pulls files from the QSD directory on `scbn` (as defined in `config.env`):

- Remote source (on scbn):
  - `${SCBN_DIR_QSDFILE}`

These files are synchronized to the local staging directory on the local machine:

- Local staging:
  - `/home/daq/FROSTmon/qsd`

The source and destination paths are configurable via:

- `/home/daq/FROSTmon/config/config.env`

with at least:

```bash
SCBN_DIR_QSDFILE="/path/on/scbn/dir_with_QSDfile"
KEKCC_DIR_BSD="/path/on/kekcc/bsd"
```

### Step 2 — Sync from Local machine → KEKCC (`bsd`)

After staging the files locally, the script synchronizes them to KEKCC:

- Local source:
  - `/home/daq/FROSTmon/qsd/`
- Remote destination (on KEKCC):
  - `${KEKCC_DIR_BSD}`

File permissions on KEKCC are set via `rsync`:

```bash
--chmod=F644,D755
```

so that uploaded files are readable by others while directories remain traversable.

### Step 3 — Logging

All operations are logged to:

```text
/home/daq/FROSTmon/logs/qsd_sync.log
```

Each run records:

- Timestamped start/end messages
- `rsync` commands executed
- Any warnings or errors produced by `rsync`

---

## 2. Script Location and Structure

### Script path

The script is expected to reside at:

```bash
/home/daq/FROSTmon/scripts/qsd_sync.sh
```

### Directory layout (typical)

```text
/home/daq/FROSTmon/
  ├── config/
  │   └── config.env          # Environment-style configuration file
  ├── qsd/                    # Local staging directory (created by script)
  ├── logs/
  │   └── qsd_sync.log        # Log file
  └── scripts/
      └── qsd_sync.sh         # This synchronization script
```

---

## 3. Requirements

### Software

- Bash
- `rsync`
- `ssh`
- `cron`

### SSH Access

The Local machine must be able to:

- SSH to **scbn** (via an SSH `Host` such as `scbn`)
- SSH to **KEKCC** (via an SSH `Host` such as `kekcc`)

Passwordless SSH (public key authentication) is strongly recommended for both directions, especially for unattended cron execution.

---

## 4. Installation

### 4.1 Place the script

Save the script as:

```bash
/home/daq/FROSTmon/scripts/qsd_sync.sh
```

### 4.2 Make it executable

```bash
chmod +x /home/daq/FROSTmon/scripts/qsd_sync.sh
```

### 4.3 Prepare configuration file

Ensure `/home/daq/FROSTmon/config/config.env` defines at least:

```bash
# Directory on scbn that contains QSD-related files
SCBN_DIR_QSDFILE="/path/on/scbn/dir_with_QSDfile"

# Destination 'bsd' directory on KEKCC
KEKCC_DIR_BSD="/path/on/kekcc/bsd"
```

You can add other variables as needed. The script loads this file via:

```bash
source /home/daq/FROSTmon/config/config.env
```

---

## 5. Manual Test Run

Before enabling cron, verify that the script works when run manually.

### 5.1 Run the script

```bash
/home/daq/FROSTmon/scripts/qsd_sync.sh
```

### 5.2 Check the log

```bash
tail -n 50 /home/daq/FROSTmon/logs/qsd_sync.log
```

Confirm that you see:

- A `sync start` and `sync end` block with timestamps
- `rsync` lines for:
  - `scbn:${SCBN_DIR_QSDFILE} -> /home/daq/FROSTmon/qsd`
  - `/home/daq/FROSTmon/qsd -> kekcc:${KEKCC_DIR_BSD}`
- No fatal errors

If there are SSH or permission issues, fix them before enabling cron.

---

## 6. Cron Setup (every 10 minutes)

The script is intended to be run periodically by `cron`.  
In this setup, it is configured to run **every 10 minutes**.

### 6.1 Edit crontab

```bash
crontab -e
```

### 6.2 Add the following line

```cron
*/10 * * * * /home/daq/FROSTmon/scripts/qsd_sync.sh
```

This will run `qsd_sync.sh` at every 0, 10, 20, 30, 40, and 50 minutes of each hour.

> Note: If you want cron's own output (stdout/stderr) to be logged elsewhere, you can extend the line, e.g.:
>
> ```cron
> */10 * * * * /home/daq/FROSTmon/scripts/qsd_sync.sh >> /home/daq/FROSTmon/logs/qsd_sync_cron_wrapper.log 2>&1
> ```

---

## 7. Managing Cron

### View current cron entries

```bash
crontab -l
```

### Temporarily disable the job

In `crontab -e`, comment out the line:

```cron
# */10 * * * * /home/daq/FROSTmon/scripts/qsd_sync.sh
```

### Re-enable the job

Remove the leading `#` and save the file.

---

## 8. Troubleshooting

### 8.1 Script works manually but not via cron

Common causes:

- **PATH differences**  
  Cron runs with a minimal environment. Use absolute paths in the script (which `qsd_sync.sh` already does) and, if necessary, set `PATH` explicitly at the top of the script, e.g.:
  ```bash
  PATH=/usr/local/bin:/usr/bin:/bin
  ```

- **SSH keys require a passphrase**  
  Cron cannot interactively type passphrases. Use keys without passphrases for this specific automation, or use an SSH agent that is active for the user running cron.

- **SSH host aliases not recognized**  
  Make sure `~/.ssh/config` is readable by the user whose crontab is used and that `Host scbn` / `Host kekcc` are correctly defined.

### 8.2 Check cron logs

On typical systems:

- Ubuntu/Debian:
  ```bash
  grep CRON /var/log/syslog
  ```

- RHEL/CentOS:
  ```bash
  tail -n 100 /var/log/cron
  ```

Look for lines containing `qsd_sync.sh` to confirm that cron is triggering the script.

### 8.3 rsync issues

- Use `-n` (dry-run) manually to see what would be transferred:
  ```bash
  rsync -avn scbn:${SCBN_DIR_QSDFILE}/ /home/daq/FROSTmon/qsd/
  ```

- Avoid adding `--delete` unless you fully understand its impact, as it will remove files on the destination that do not exist on the source.

---

## 9. Operational Notes

- Adjust the cron interval (`*/10 * * * *`) as needed, depending on how frequently QSD files are updated.
- Monitor the size of the log file `/home/daq/FROSTmon/logs/qsd_sync.log` and rotate it if necessary.
- Because synchronization is done in two stages (scbn → local → KEKCC), this script does **not** require direct SSH connectivity between scbn and KEKCC, which is useful in environments where such connections are restricted.
