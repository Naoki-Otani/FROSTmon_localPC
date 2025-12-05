# FROSTmon Execution Guide

This system requires the following to run continuously:

1.  **Three dispatcher scripts that must always stay running**
2.  **Two sync scripts (`figs_sync.sh` and `qsd_sync.sh`) that must run periodically via cron**

## 1. Start the Three Dispatchers

Run the following script once:

``` bash
/home/daq/FROSTmon/scripts/run_all_dispatchers.sh
```

This script automatically starts all three dispatchers and ensures they
keep running in the background.

## 2. Run `figs_sync.sh` Every 3 Minutes

Add this line to your crontab:

```cron
*/3 * * * * /home/daq/FROSTmon/scripts/figs_sync.sh
```

This makes `figs_sync.sh` run automatically every 3 minutes.

## 3. Run `qsd_sync.sh` Every 10 Minutes

Add this line to your crontab:

```cron
*/10 * * * * /home/daq/FROSTmon/scripts/qsd_sync.sh
```

This makes `qsd_sync.sh` run automatically every 10 minutes.

## Summary

-   Use **`run_all_dispatchers.sh`** to keep the 3 dispatcher processes
    running forever.
-   Use **crontab** to run **`figs_sinc.sh` every 3 minutes**.
-   Use **crontab** to run **`qsd_sync.sh` every 10 minutes**.

## IMPORTANT: Configure `config/config.env`

Before running FROSTmon on any new machine or DAQ environment, you **must**
edit:

```
config/config.env
```

This file contains **file paths and environment settings used by FROSTmon**, including:

- Paths on **KEKCC** used by `figs_sync.sh`
- Paths on **scbn** and **KEKCC (bsd)** used by `qsd_sync.sh`
- Local directories on the DAQ node

You must update all machine-specific paths in `config.env` so that they point to
the correct directories before starting the dispatcher scripts or enabling the
cron jobs. If these paths are left unchanged, the monitoring, dispatcher, and
sync jobs will fail to locate input/output files.

## Checking Running Dispatcher Processes

To verify that the three dispatcher scripts are running, use:

```bash
ps aux | grep local_ | grep dispatcher
```

You should see one process for each of the following:

- `local_divideDat_dispatcher.sh`
- `local_convertFromDatToRoot_dispatcher.sh`
- `local_frost_monitor_jobs_dispatcher.sh`

If you see multiple instances of the same script, it means the dispatcher
was started more than once.

## Stopping (Killing) Dispatcher Processes

To stop a specific dispatcher, find its PID from the command above and run:

```bash
kill <PID>
```

To stop all instances of a dispatcher:

```bash
pkill -f local_divideDat_dispatcher.sh
pkill -f local_convertFromDatToRoot_dispatcher.sh
pkill -f local_frost_monitor_jobs_dispatcher.sh
```

This will terminate the background processes started by `run_all_dispatchers.sh`.
