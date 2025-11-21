# Local DivideDat Dispatcher (submit `extract_events` as LSF jobs from local PC)

This script runs on your **local PC** and keeps submitting **split jobs** on KEKCC to cut
`runNNNNN.dat` into fixed chunks using your existing `extract_events` binary.

- No resident process on KEKCC, only LSF jobs (`bsub`) are created.
- The dispatcher keeps a **local daily log** under `./logs/`.
- Each job writes its own LSF stdout/stderr on KEKCC under `$OUT_DIR/lsf_out/`.

## How it works
1. The dispatcher SSHes to `kekcc` (login.cc.kek.jp) and runs a **login shell** that sources your `~/.bashrc`.
2. It detects the **latest** `run*.dat` in `$SRC_DIR`. If the latest changes to a new run, it **drains** the old one fully before switching.
3. To avoid premature extraction, it submits a short **probe job** (`divide_probe_<run>`) that runs:
   ```bash
   bsub ... extract_events <run.dat> <PROBE_DIR> 4294960000 4294960001
   ```
   and then reads `Max event number in file: N` from the LSF log to know how far the file has grown.
4. When `N >= next_end`, it submits an **extract job** for `[start,end]`:
   ```bash
   bsub ... extract_events <run.dat> <OUT_DIR> <start> <end>
   ```
5. De‑duplication:
   - Skip if the output chunk already exists: `<OUT_DIR>/<run>_<start>_<end>.dat`
   - Skip if a job `divide_extract_<run>_<start>_<end>` is already queued or running.

## Configure (edit inside the script)
- SSH alias: `REMOTE_HOST="kekcc"` (as in your `~/.ssh/config`)
- Paths:
  ```bash
  SRC_DIR="/group/.../datfile"
  OUT_DIR="/group/.../divided_datfile"
  EXTRACT_CMD="/home/.../extract_events"
  PROBE_DIR="$OUT_DIR/.probe"
  LSF_OUT_DIR="$OUT_DIR/lsf_out"
  ```
- Tuning:
  ```bash
  CHUNK_SIZE=10000
  INTERVAL=15
  QUEUE="l"
  MAX_JOBS=0      # 0 = unlimited
  ```

## Run (local PC)
```bash
chmod +x local_divideDat_dispatcher.sh
./local_divideDat_dispatcher.sh
```
- Logs are saved to `./logs/YYYY-MM-DD.divideDat_dispatcher.log` and also printed to the console (set `MIRROR_TO_CONSOLE=no` to log-only).

## Notes
- The script assumes KEKCC `~/.bashrc` prepares your LSF environment so that `bsub/bjobs` are available.
- `probe` jobs simply use the extractor with a range that cannot exist, so nothing is written except temporary files under `$PROBE_DIR` which are auto-cleaned by the extractor wrapper.
- The dispatcher does not create any split files locally; all results live in `$OUT_DIR` on KEKCC.
