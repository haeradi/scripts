#!/bin/bash
# Sheet sync watchdog — silent kalau OK, alert kalau ada masalah.
# Dipanggil via cron no_agent=True: exit 0 + stdout kosong = silent.
# Kalau ada issue: print alert message, cron deliver ke bos.

set -uo pipefail

DOKUMEN=/home/ubuntu/assist-bot/cache/dokumen.json
CASHMAP=/home/ubuntu/assist-bot/cache/cash-spks.json
NOW=$(date +%s)

# Threshold: cache boleh basi max 90 menit (assist-dokumen.timer 30m + 3x tolerance)
MAX_AGE_SEC=5400

issues=()

# 1. Cache dokumen ada + fresh?
if [ ! -f "$DOKUMEN" ]; then
    issues+=("❌ cache/dokumen.json HILANG")
else
    age=$((NOW - $(stat -c %Y "$DOKUMEN")))
    if [ "$age" -gt "$MAX_AGE_SEC" ]; then
        issues+=("⚠️ dokumen.json basi ${age}s (>${MAX_AGE_SEC}s)")
    fi
fi

# 2. Cache cash-map ada + fresh?
if [ ! -f "$CASHMAP" ]; then
    issues+=("❌ cache/cash-spks.json HILANG")
else
    age=$((NOW - $(stat -c %Y "$CASHMAP")))
    if [ "$age" -gt "$MAX_AGE_SEC" ]; then
        issues+=("⚠️ cash-spks.json basi ${age}s (>${MAX_AGE_SEC}s)")
    fi
fi

# 3. Timer masih aktif?
for timer in assist-dokumen.timer assist-sheet-sync.timer; do
    if ! systemctl --user is-active --quiet "$timer" 2>/dev/null; then
        issues+=("❌ $timer TIDAK AKTIF")
    fi
done

# 4. Last service run success? (cek 2 tick terakhir — kalau kedua fail = alert)
for svc in assist-dokumen.service assist-sheet-sync.service; do
    result=$(systemctl --user show "$svc" -p Result --value 2>/dev/null)
    if [ "$result" != "success" ] && [ -n "$result" ]; then
        issues+=("⚠️ $svc last result: $result")
    fi
done

# 5. Sheet pending count sanity check (nol = kemungkinan sync fail)
if [ -f "$DOKUMEN" ]; then
    pending=$(python3 -c "import json; print(json.load(open('$DOKUMEN')).get('pendingCount', 0))" 2>/dev/null || echo 0)
    if [ "$pending" -lt 10 ]; then
        issues+=("⚠️ dokumen.json pending count = $pending (sangat rendah, cek Banpen)")
    fi
fi

# Silent kalau OK
if [ "${#issues[@]}" -eq 0 ]; then
    exit 0
fi

# Kalau ada issue: print alert
echo "🚨 Sheet sync watchdog alert ($(date +'%H:%M %Z'))"
echo ""
for issue in "${issues[@]}"; do
    echo "$issue"
done
echo ""
echo "Cek: systemctl --user status assist-dokumen assist-sheet-sync"
echo "Link sheet: https://docs.google.com/spreadsheets/d/1Bh5naLfxbiXktoni2Z0_3nrOYy1EVaUmYjhfpChzbyo"
