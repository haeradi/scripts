#!/usr/bin/env bash
# /home/ubuntu/scripts/safe-edit.sh
# Wrapper buat ngedit kode kritis. Workflow:
#   1. verify (pre): pastiin kondisi awal sehat
#   2. snapshot: zip kondisi sekarang ke /home/ubuntu/backups/
#   3. show diff terakhir: kasih liat apa yg berubah sejak commit terakhir
#   4. user bisa ketik 'apply' (commit), 'rollback' (git checkout .), atau 'snapshot' (zip lagi)
#   5. verify (post): test ulang. Kalau gagal, otomatis rollback dari git.
#
# Usage:
#   ./safe-edit.sh           # interactive: review state, no auto-action
#   ./safe-edit.sh apply     # auto-commit perubahan kalau verify post-edit OK
#   ./safe-edit.sh rollback  # paksa balik ke commit terakhir, buang perubahan
#
# Tujuan: tiap kali Bos atau gua ngubah kode, ada checkpoint sebelum & sesudah,
# dan kalau ada bug ke-introduce, satu command balik aman.

set -u
ACTION="${1:-status}"
REPOS=(/home/ubuntu/assist-bot /home/ubuntu/hermes-v2-bot)

run_verify() {
  /home/ubuntu/scripts/verify-assist.sh
  return $?
}

snapshot_now() {
  /home/ubuntu/scripts/daily-backup.sh >/dev/null 2>&1
  ls -t /home/ubuntu/backups/snapshot-*.zip 2>/dev/null | head -1
}

show_diff() {
  for repo in "${REPOS[@]}"; do
    [ -d "$repo/.git" ] || continue
    cd "$repo" || continue
    local changed
    changed=$(git status --porcelain | wc -l)
    if [ "$changed" -gt 0 ]; then
      echo "=== $repo ($changed file changed) ==="
      git --no-pager diff --stat
      echo
      git --no-pager diff | head -80
      echo "--- (truncated, lihat full diff: cd $repo && git diff)"
      echo
    fi
  done
}

case "$ACTION" in
  status)
    echo "=== Pre-edit verify ==="
    run_verify; PRE=$?
    echo
    echo "=== Snapshot saved ==="
    snap=$(snapshot_now)
    echo "  $snap"
    echo
    echo "=== Pending changes (uncommitted) ==="
    show_diff
    echo
    echo "Available actions:"
    echo "  $0 apply     # verify + commit perubahan kalau test pass"
    echo "  $0 rollback  # buang semua perubahan, balik ke commit terakhir"
    echo "  $0 snapshot  # bikin zip backup lagi"
    [ $PRE -eq 0 ] && exit 0 || exit 1
    ;;
  apply)
    echo "=== Pre-apply verify ==="
    if ! run_verify; then
      echo
      echo "❌ Pre-apply verify FAILED. Server kondisi udah rusak SEBELUM apply."
      echo "   Jangan apply. Cek logs:"
      echo "   journalctl --user -u assist-bot.service -n 50 --no-pager"
      exit 2
    fi

    # Restart untuk loading kode baru (kalau ada perubahan .js)
    has_js_change=0
    for repo in "${REPOS[@]}"; do
      cd "$repo" || continue
      [ -d .git ] || continue
      if git status --porcelain | grep -qE '\.js$'; then
        has_js_change=1; break
      fi
    done

    if [ $has_js_change -eq 1 ]; then
      echo
      echo "=== Restart assist-bot.service (kode .js berubah) ==="
      systemctl --user restart assist-bot.service
      sleep 3
    fi

    echo
    echo "=== Post-restart verify ==="
    if ! run_verify; then
      echo
      echo "❌ Post-restart verify FAILED. Auto-rollback…"
      for repo in "${REPOS[@]}"; do
        cd "$repo" || continue
        [ -d .git ] || continue
        git checkout -- . 2>/dev/null
      done
      systemctl --user restart assist-bot.service
      sleep 3
      run_verify
      echo
      echo "Rolled back to last commit. Snapshot pre-rollback ada di /home/ubuntu/backups/."
      exit 3
    fi

    echo
    echo "=== Commit perubahan ==="
    TS=$(date +%Y-%m-%d_%H%M)
    for repo in "${REPOS[@]}"; do
      cd "$repo" || continue
      [ -d .git ] || continue
      if [ -n "$(git status --porcelain)" ]; then
        git add -A
        git commit -m "safe-edit apply $TS" >/dev/null 2>&1 \
          && echo "  ✅ $repo committed" \
          || echo "  ⚠️  $repo commit failed"
      fi
    done
    echo
    echo "✅ Apply selesai, semua test pass."
    exit 0
    ;;
  rollback)
    echo "=== Snapshot before rollback ==="
    snap=$(snapshot_now)
    echo "  $snap"
    echo
    echo "=== Rollback ==="
    for repo in "${REPOS[@]}"; do
      cd "$repo" || continue
      [ -d .git ] || continue
      changed=$(git status --porcelain | wc -l)
      if [ "$changed" -gt 0 ]; then
        echo "  $repo: $changed file(s) reverted to last commit"
        git checkout -- .
      else
        echo "  $repo: clean (nothing to rollback)"
      fi
    done
    echo
    echo "=== Restart + verify ==="
    systemctl --user restart assist-bot.service
    sleep 3
    run_verify
    ;;
  snapshot)
    snap=$(snapshot_now)
    echo "Snapshot: $snap"
    ls -lah "$snap"
    ;;
  *)
    echo "Usage: $0 [status|apply|rollback|snapshot]"
    exit 1
    ;;
esac
