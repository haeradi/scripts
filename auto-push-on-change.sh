#!/usr/bin/env bash
# /home/ubuntu/scripts/auto-push-on-change.sh
# Run via systemd timer setiap 5 menit. Loop semua repo target,
# commit + push perubahan kalau ada.
#
# Behavior:
#   - Skip kalau repo clean (no-op, gak spam log).
#   - Commit semua dirty files ke 1 commit dengan message "auto-push $TS".
#   - Push ke origin/HEAD. Kalau push fail (token expired), log + lanjut.
#
# Log: /home/ubuntu/backups/.auto-push.log (rotate >5MB).

set -u
LOG_FILE="/home/ubuntu/backups/.auto-push.log"
# Read token from credentials file for git push
TOKEN=$(python3 -c "
import re
with open('/home/ubuntu/.git-credentials') as f:
    content = f.read()
m = re.search(r'https://haeradi:([^@]+)@github\.com', content)
if m: print(m.group(1))
" 2>/dev/null)

PUSH_URL="https://haeradi:${TOKEN}@github.com"

REPOS=(
  "/home/ubuntu/assist-bot"
  "/home/ubuntu/stnk-bot"
  "/home/ubuntu/hermes-v2-bot"
  "/home/ubuntu/dis2-session-keeper"
  "/home/ubuntu/motorkux-bot"
  "/home/ubuntu/surat-desa"
)

REPO_URLS=(
  "https://github.com/haeradi/assist-bot.git"
  "https://github.com/haeradi/stnk-bot.git"
  "https://github.com/haeradi/hermes-v2-bot.git"
  "https://github.com/haeradi/dis2-session-keeper.git"
  "https://github.com/haeradi/motorkux-bot.git"
  "https://github.com/haeradi/surat-desa.git"
)

mkdir -p "$(dirname "$LOG_FILE")"
exec >> "$LOG_FILE" 2>&1

TICK_TS=$(date -Iseconds)
PUSHED_ANY=0

for i in "${!REPOS[@]}"; do
  REPO="${REPOS[$i]}"
  REPO_URL="${REPO_URLS[$i]}"

  if [ ! -d "$REPO/.git" ]; then continue; fi
  cd "$REPO" || continue

  if [ -z "$(git status --porcelain)" ]; then
    continue # clean, skip silent
  fi

  CHANGED=$(git status --porcelain | wc -l)
  echo "$TICK_TS [auto-push] $(basename "$REPO") dirty=$CHANGED"

  git add -A
  COMMIT_MSG="auto-push $TICK_TS ($CHANGED files)"
  if git -c user.email='abdulradi17@gmail.com' -c user.name='Hae Radi' \
       commit -m "$COMMIT_MSG" >/dev/null 2>&1; then
    echo "  $(basename "$REPO") commit OK"
  else
    echo "  $(basename "$REPO") commit FAIL"
    continue
  fi

  if GIT_ASKPASS=echo git push "$REPO_URL" main >/dev/null 2>&1; then
    echo "  $(basename "$REPO") push OK"
    PUSHED_ANY=1
  else
    echo "  $(basename "$REPO") push FAIL (cek token github)"
  fi
done

# Rotate log kalau >5MB
if [ -f "$LOG_FILE" ]; then
  SIZE=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
  if [ "$SIZE" -gt 5242880 ]; then
    mv "$LOG_FILE" "${LOG_FILE}.$(date +%Y%m%d_%H%M%S)"
    echo "$TICK_TS log rotated" > "$LOG_FILE"
  fi
fi

# Prune old rotated logs >7 hari
find "$(dirname "$LOG_FILE")" -name '.auto-push.log.*' -mtime +7 -delete 2>/dev/null

exit 0
