#!/bin/bash
set -euo pipefail

# ===== Config =====
source /home/daq/FROSTmon/config/config.env

SRC_HOST="kekcc"
SRC_DIR_LATESTDAT="$SRC_DIR_LATESTDAT"
SRC_DIR_DATAQUALITY="$SRC_DIR_DATAQUALITY"
SRC_DIR_DATAQUALITY_WITHBSD="$SRC_DIR_DATAQUALITY_WITHBSD"

DST_HOST="kuhep"
DST_DIR_LATESTDAT="/hep_web/member/otani/frostmonitor/figs/latestdat_info/"
DST_DIR_DATAQUALITY="/hep_web/member/otani/frostmonitor/figs/dataquality/"
DST_DIR_DATAQUALITY_WITHBSD="/hep_web/member/otani/frostmonitor/figs/dataquality_withBSD/"

LOCAL_DIR_LATESTDAT="/home/daq/FROSTmon/figs/latestdat_info"
LOCAL_DIR_DATAQUALITY="/home/daq/FROSTmon/figs/dataquality"
LOCAL_DIR_DATAQUALITY_WITHBSD="/home/daq/FROSTmon/figs/dataquality_withBSD"

# log file
LOG_DIR="/home/daq/FROSTmon/logs"
LOG_FILE="$LOG_DIR/figs_sync.log"

# ===== mkdir =====
mkdir -p "$LOCAL_DIR_LATESTDAT"
mkdir -p "$LOCAL_DIR_DATAQUALITY"
mkdir -p "$LOCAL_DIR_DATAQUALITY_WITHBSD"
mkdir -p "$LOG_DIR"

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

echo "[$(timestamp)] ===== sync start =====" >> "$LOG_FILE"

# ===== kekcc -> local =====
echo "[$(timestamp)] rsync from $SRC_HOST:$SRC_DIR_LATESTDAT to $LOCAL_DIR_LATESTDAT" >> "$LOG_FILE"
rsync -av \
  --partial --inplace \
  "${SRC_HOST}:${SRC_DIR_LATESTDAT}" \
  "$LOCAL_DIR_LATESTDAT" >> "$LOG_FILE" 2>&1

echo "[$(timestamp)] rsync from $SRC_HOST:$SRC_DIR_DATAQUALITY to $LOCAL_DIR_DATAQUALITY" >> "$LOG_FILE"
rsync -av \
  --partial --inplace \
  "${SRC_HOST}:${SRC_DIR_DATAQUALITY}" \
  "$LOCAL_DIR_DATAQUALITY" >> "$LOG_FILE" 2>&1

echo "[$(timestamp)] rsync from $SRC_HOST:$SRC_DIR_DATAQUALITY_WITHBSD to $LOCAL_DIR_DATAQUALITY_WITHBSD" >> "$LOG_FILE"
rsync -av \
  --partial --inplace \
  "${SRC_HOST}:${SRC_DIR_DATAQUALITY_WITHBSD}" \
  "$LOCAL_DIR_DATAQUALITY_WITHBSD" >> "$LOG_FILE" 2>&1

# ===== Convert PDFs to PNGs =====
convert_pdf_dir() {
  local DIR="$1"
  echo "[$(timestamp)] converting PDFs in $DIR to PNG..." >> "$LOG_FILE"

  find "$DIR" -type f -name "*.pdf" | while read -r pdf; do
    png="${pdf%.pdf}.png"

    # convert only if pdf is newer than png OR png does not exist
    if [[ ! -f "$png" || "$pdf" -nt "$png" ]]; then
      echo "[$(timestamp)] convert $pdf -> $png" >> "$LOG_FILE"
      convert -density 150 -define pdf:use-cropbox=true "$pdf" -quality 90 "$png"
    fi
  done
}

convert_pdf_dir "$LOCAL_DIR_DATAQUALITY"
convert_pdf_dir "$LOCAL_DIR_DATAQUALITY_WITHBSD"

# ===== local -> kuhep =====
echo "[$(timestamp)] rsync from $LOCAL_DIR_LATESTDAT to $DST_HOST:$DST_DIR_LATESTDAT" >> "$LOG_FILE"
rsync -av \
  --partial --inplace \
  --chmod=F644,D755 \
  "$LOCAL_DIR_LATESTDAT/" \
  "${DST_HOST}:${DST_DIR_LATESTDAT}" >> "$LOG_FILE" 2>&1

echo "[$(timestamp)] rsync from $LOCAL_DIR_DATAQUALITY to $DST_HOST:$DST_DIR_DATAQUALITY" >> "$LOG_FILE"
rsync -av \
  --partial --inplace \
  --chmod=F644,D755 \
  "$LOCAL_DIR_DATAQUALITY/" \
  "${DST_HOST}:${DST_DIR_DATAQUALITY}" >> "$LOG_FILE" 2>&1

echo "[$(timestamp)] rsync from $LOCAL_DIR_DATAQUALITY_WITHBSD to $DST_HOST:$DST_DIR_DATAQUALITY_WITHBSD" >> "$LOG_FILE"
rsync -av \
  --partial --inplace \
  --chmod=F644,D755 \
  "$LOCAL_DIR_DATAQUALITY_WITHBSD/" \
  "${DST_HOST}:${DST_DIR_DATAQUALITY_WITHBSD}" >> "$LOG_FILE" 2>&1

echo "[$(timestamp)] ===== sync end =====" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"
