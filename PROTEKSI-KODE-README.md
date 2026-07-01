# PROTEKSI KODE — Cara Pakai

Setup proteksi kode aktif sejak 2026-05-22. Tujuan: gak ada lagi
"baikin error mulu". Kode penting di-versioning, di-backup harian,
dan di-test sebelum/sesudah edit.

## Yang Diproteksi

- /home/ubuntu/assist-bot/        (semua *.js + .env + queries/)
- /home/ubuntu/hermes-v2-bot/     (bot.js, motorkux.js, .env)
- ~/.config/systemd/user/         (semua *.service & *.timer)
- n8n workflow                    (export semua workflow JSON)

## 3 Tools Penting

### 1. Cek kondisi sekarang sehat / engga
```
/home/ubuntu/scripts/verify-assist.sh
```
Test 5 endpoint penting (health, accounts, lookup-engine, stock, service).
Exit 0 = semua OK, exit 1 = ada yg fail.

### 2. Backup harian (otomatis jam 03:00 WITA)
```
systemctl --user list-timers daily-backup.timer
```
Bikin zip ke /home/ubuntu/backups/snapshot-YYYY-MM-DD_HHMM.zip
(retain 30 hari, di luar itu auto-delete).

Manual: jalankan kapan aja:
```
/home/ubuntu/scripts/daily-backup.sh
```

### 3. Edit kode dengan safety net
```
/home/ubuntu/scripts/safe-edit.sh status     # cek state, snapshot, lihat diff
/home/ubuntu/scripts/safe-edit.sh apply      # verify + restart + commit kalau pass
/home/ubuntu/scripts/safe-edit.sh rollback   # buang perubahan, balik ke commit terakhir
/home/ubuntu/scripts/safe-edit.sh snapshot   # bikin zip backup ad-hoc
```

`apply` flow:
1. Verify pre (kalau service udah rusak duluan, abort — gak nutupin bug lain)
2. Restart assist-bot biar kode baru ter-load
3. Verify post — kalau gagal, AUTO-ROLLBACK ke commit terakhir + restart lagi
4. Kalau lolos, auto-commit perubahan dengan timestamp

## Skenario "Bos panik"

**Aduh, /cari mati lagi:**
```
/home/ubuntu/scripts/verify-assist.sh
```
Liat test mana yg ❌. Kalau cuma /lookup-engine, kemungkinan upstream lambat
(non-issue). Kalau /accounts ❌, refresh_token mati — kirim /authstart di
Telegram.

**Kemarin sore masih jalan, sekarang error:**
```
cd /home/ubuntu/assist-bot
git log --oneline -10                         # liat commit terakhir
git diff HEAD~1 HEAD                          # liat apa yg berubah
git checkout HEAD~1 -- <file>                 # rollback 1 file aja
# atau
git reset --hard HEAD~1                       # rollback semua
systemctl --user restart assist-bot.service
/home/ubuntu/scripts/verify-assist.sh
```

**Pengin liat kondisi 5 hari lalu:**
```
ls /home/ubuntu/backups/ | head
unzip -l /home/ubuntu/backups/snapshot-2026-05-17_0300.zip
unzip /home/ubuntu/backups/snapshot-2026-05-17_0300.zip -d /tmp/restore
# bandingin /tmp/restore/assist-bot dengan /home/ubuntu/assist-bot
diff -ur /tmp/restore/assist-bot /home/ubuntu/assist-bot
```

**N8N workflow rusak (tombol salah, ada node hilang):**
```
unzip /home/ubuntu/backups/snapshot-XXXX.zip -d /tmp/restore
ls /tmp/restore/n8n/                          # workflow JSON tersimpan
# Pakai skill n8n-api / curl PUT untuk restore workflow yg specific
```

## Catatan Penting

- .env DI-COMMIT ke git lokal supaya rollback bisa balikin token & secret juga.
  Repo ini cuma di VM, gak di-push GitHub. Kalau mau ke GitHub, scrub history
  dulu pakai `git filter-repo`.
- Backup zip + git lokal tersimpan di VM yang sama. Untuk safety lebih,
  copy backups/ ke laptop Bos sesekali (rsync / scp).
- safe-edit apply auto-rollback hanya untuk perubahan tracked di git.
  Perubahan di luar /assist-bot dan /hermes-v2-bot tidak ke-track.

Last updated: 2026-05-22
