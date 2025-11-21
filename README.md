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
