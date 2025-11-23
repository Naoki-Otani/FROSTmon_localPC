# FROSTmon Execution Guide

This system requires two things to run continuously:

1.  **Three dispatcher scripts that must always stay running**
2.  **One script (`figs_sync.sh`) that must run every 3 minutes**

## 1. Start the Three Dispatchers

Run the following script once:

``` bash
/home/daq/FROSTmon/scripts/run_all_dispatchers.sh
```

This script automatically starts all three dispatchers and ensures they
keep running in the background.

## 2. Run `figs_sync.sh` Every 3 Minutes

Add this line to your crontab:

    */3 * * * * /home/daq/FROSTmon/scripts/figs_sync.sh

This makes `figs_sync.sh` run automatically every 3 minutes.

## Summary

-   Use **`run_all_dispatchers.sh`** to keep the 3 dispatcher processes
    running forever.
-   Use **crontab** to run **`figs_sinc.sh` every 3 minutes**.

## IMPORTANT: Configure `config/config.env`

Before running FROSTmon on any new machine or DAQ environment, you **must**
edit:

```
config/config.env
```

This file contains **file paths used on KEKCC**.  
You must update all KEKCC-specific paths in `config.env` so that they point to
the correct directories on the local machine before starting the dispatcher
scripts.  
If the KEKCC paths are left unchanged, the monitoring and dispatcher jobs will
fail to locate input/output files.

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
