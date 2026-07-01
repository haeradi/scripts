#!/usr/bin/env bash
# /home/ubuntu/scripts/daily-backup.sh
# Snapshot kode + secret + workflow n8n + systemd unit ke /home/ubuntu/backups/
# + auto-commit di assist-bot & hermes-v2-bot kalau ada perubahan tracked.
# Cron: 03:00 WITA tiap hari (~ 19:00 UTC sebelumnya).
# Retain 30 hari terakhir, sisanya prune.

set -u
TS=$(date +%Y-%m-%d_%H%M)
BACKUP_DIR="/home/ubuntu/backups"
N8N_CRED="/home/ubuntu/.config/n8n/credentials"
LOG_FILE="$BACKUP_DIR/.backup.log"

mkdir -p "$BACKUP_DIR"
exec >> "$LOG_FILE" 2>&1
echo
echo "===== $TS ====="

# 1) Auto-commit + push di repo aktif
for repo in /home/ubuntu/assist-bot /home/ubuntu/hermes-v2-bot /home/ubuntu/stnk-bot /home/ubuntu/astra-n8n-workflows /home/ubuntu/dis2-session-keeper; do
  if [ -d "$repo/.git" ]; then
    cd "$repo" || continue
    if [ -n "$(git status --porcelain)" ]; then
      git add -A
      if git commit -m "auto-snapshot $TS" >/dev/null 2>&1; then
        echo "  [git] auto-commit $repo OK"
      else
        echo "  [git] auto-commit $repo FAIL"
      fi
    else
      echo "  [git] $repo clean (no changes)"
    fi
    # Push kalau ada remote configured (private repo GitHub)
    if git remote get-url origin >/dev/null 2>&1; then
      if git push origin HEAD >/dev/null 2>&1; then
        echo "  [git] push $repo OK"
      else
        echo "  [git] push $repo FAIL (token expired? scope?)"
      fi
    fi
  fi
done

# 2) Build zip snapshot
SNAP="$BACKUP_DIR/snapshot-$TS.zip"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# 2a) Project sources (sans node_modules)
for proj in assist-bot hermes-v2-bot stnk-bot astra-n8n-workflows dis2-session-keeper; do
  src="/home/ubuntu/$proj"
  [ -d "$src" ] || continue
  dest="$TMP/$proj"
  mkdir -p "$dest"
  rsync -a \
    --exclude=node_modules --exclude='*.log' --exclude=.tmp --exclude=tmp \
    --exclude=playwright-report --exclude=test-results --exclude=trace.zip \
    --exclude=sessions --exclude=sessions.bak --exclude=.cache \
    "$src/" "$dest/" 2>/dev/null
done

# 2b) systemd user units
mkdir -p "$TMP/systemd-user"
cp -r /home/ubuntu/.config/systemd/user/*.service "$TMP/systemd-user/" 2>/dev/null
cp -r /home/ubuntu/.config/systemd/user/*.timer   "$TMP/systemd-user/" 2>/dev/null

# 2c) n8n workflow JSONs (semua workflow yang aktif di-export)
if [ -f "$N8N_CRED" ]; then
  N8N_KEY=$(grep -E '^N8N_API_KEY=' "$N8N_CRED" | cut -d= -f2-)
  N8N_URL=$(grep -E '^INSTANCE_URL=' "$N8N_CRED" | cut -d= -f2- | sed 's:/$::')
  if [ -n "$N8N_KEY" ] && [ -n "$N8N_URL" ]; then
    mkdir -p "$TMP/n8n"
    curl -sS -H "X-N8N-API-KEY: $N8N_KEY" "$N8N_URL/api/v1/workflows?limit=200" \
      > "$TMP/n8n/workflows-list.json" 2>/dev/null
    # Per-workflow detail
    python3 - <<EOF || true
import json, subprocess, os
key = os.environ.get("KEY","$N8N_KEY")
base = os.environ.get("BASE","$N8N_URL")
try:
    wfs = json.load(open("$TMP/n8n/workflows-list.json"))
    for w in wfs.get("data", []):
        wid = w["id"]; name = w["name"].replace("/","_")
        out = subprocess.run(["curl","-sS","-H",f"X-N8N-API-KEY: {key}",
                              f"{base}/api/v1/workflows/{wid}"],
                              capture_output=True, text=True)
        with open(f"$TMP/n8n/{wid}__{name}.json","w") as f: f.write(out.stdout)
except Exception as e:
    print(f"n8n export err: {e}")
EOF
    echo "  [n8n] workflows exported"
  fi
fi

# 2d) Crontab user (kalau ada)
crontab -l > "$TMP/crontab.txt" 2>/dev/null || echo "(no crontab)" > "$TMP/crontab.txt"

# Build zip — exclude node_modules eksplisit di rsync, jadi zip safe
( cd "$TMP" && zip -qr "$SNAP" . )
SIZE=$(du -h "$SNAP" | cut -f1)
echo "  [zip] $SNAP ($SIZE)"

# 3) Prune snapshot >30 hari
find "$BACKUP_DIR" -maxdepth 1 -name 'snapshot-*.zip' -mtime +30 -print -delete 2>/dev/null \
  | sed 's|^|  [prune] |'

echo "===== done $TS ====="
