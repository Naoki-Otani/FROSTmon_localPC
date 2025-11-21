# FROST Monitor Figure Auto-Synchronization Script

This document explains the usage and structure of the script `figs_sync.sh`, which automatically synchronizes monitoring figures between:

- **kekcc** (source of data)
- **Local machine** (intermediate processing)
- **kuhep** (public-facing web server)

The script runs on the **local node** and is intended to be executed periodically via `cron`.

---

## 1. Script Overview

`figs_sync.sh` performs the following sequence:

### **Step 1 — Sync from kekcc → Local machine**

The script pulls updated files from:

- `/group/nu/ninja/work/otani/FFROST_beamdata/test/latestdat_info/`
- `/group/nu/ninja/work/otani/FROST_beamdata/test/dataquality/`
- `/group/nu/ninja/work/otani/FROST_beamdata/test/dataquality_withBSD/`

It saves them under:

- `/home/daq/FROSTmon/scripts/figs/latestdat_info`
- `/home/daq/FROSTmon/scripts/figs/dataquality`
- `/home/daq/FROSTmon/scripts/figs/dataquality_withBSD`

### **Step 2 — Convert PDFs → PNGs (local)**

All PDF files found in the downloaded directories are converted to PNG using ImageMagick.

The script now uses:

```bash
convert -density 150 -define pdf:use-cropbox=true input.pdf -quality 90 output.png
```

This ensures:

- PDF **CropBox** is respected  
- No unwanted margins are introduced  
- Generated PNG reflects the visible PDF region

### **Step 3 — Sync from Local → kuhep**

After conversion, updated data is uploaded to:

- `/hep_web/member/otani/frostmonitor/figs/latestdat_info/`
- `/hep_web/member/otani/frostmonitor/figs/dataquality/`
- `/hep_web/member/otani/frostmonitor/figs/dataquality_withBSD/`

### **Step 4 — Logging**

All operations are logged in:

```
/home/daq/FROSTmon/scripts/logs/figs_sync.log
```

---

## 2. Requirements

### **Software**
- Bash
- rsync
- ssh
- ImageMagick (`convert`)
- cron

### **Access**
- Local → kekcc SSH
- Local → kuhep SSH
- Passwordless SSH strongly recommended

---

## 3. Installation

### **Place the script**

```
/home/daq/FROSTmon/scripts/figs_sync.sh
```

### **Make executable**

```bash
chmod +x /home/daq/FROSTmon/scripts/figs_sync.sh
```

### **Verify ImageMagick**

```bash
convert -version
```

---

## 4. Manual Test Run

Run:

```bash
/home/daq/FROSTmon/scripts/figs_sync.sh
```

View log:

```bash
tail -n 50 /home/daq/FROSTmon/scripts/logs/figs_sync.log
```

---

## 5. Cron Setup (every 3 minutes)

Edit cron:

```bash
crontab -e
```

Add:

```cron
*/3 * * * * /home/daq/FROSTmon/scripts/figs_sync.sh
```

---

## 6. Managing Cron

View:

```bash
crontab -l
```

Disable:

```cron
# */3 * * * * /home/daq/FROSTmon/scripts/figs_sync.sh
```

Enable: remove `#`.

---

## 7. Troubleshooting

### Script works manually but not in cron
- PATH issues — consider exporting PATH explicitly  
- SSH keys require passphrase — use ssh-agent or passwordless keys  
- `convert` not found — use full path (`/usr/bin/convert`)

### Check cron logs

Ubuntu/Debian:

```bash
grep CRON /var/log/syslog
```

RHEL/CentOS:

```
/var/log/cron
```

---

## 8. Operational Notes

- Adjust sync interval if needed  
- Avoid `--delete` in rsync unless fully understood  
- Monitor log size  
- CropBox-based PNG export avoids layout distortion
