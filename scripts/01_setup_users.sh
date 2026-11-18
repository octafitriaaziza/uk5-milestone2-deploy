#!/usr/bin/env bash
set -euo pipefail

APP_USER="webapp"
APP_GROUP="webapp"
APP_HOME="/var/www/webapp"
APP_DATA="${APP_HOME}/data"
APP_LOG="/var/log/webapp"

# Tentukan shell nologin yang tersedia di sistem
NOLOGIN_SHELL="/sbin/nologin"
[ -f /usr/sbin/nologin ] && NOLOGIN_SHELL="/usr/sbin/nologin"

# Jalankan perintah sebagai root: langsung jika sudah root, via sudo jika bukan.
run_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# 1. Group sistem
if getent group "$APP_GROUP" >/dev/null; then
    echo "[INFO] Group ${APP_GROUP} sudah tersedia."
else
    run_root groupadd -r "$APP_GROUP"
    echo "[SUCCESS] Group ${APP_GROUP} berhasil dibuat."
fi

# 2. User sistem tanpa shell interaktif
if id -u "$APP_USER" >/dev/null 2>&1; then
    echo "[INFO] User ${APP_USER} sudah tersedia."
else
    run_root mkdir -p "$(dirname "$APP_HOME")"
    run_root useradd -r -g "$APP_GROUP" -s "$NOLOGIN_SHELL" \
        -d "$APP_HOME" -m -c "Web Application Daemon" "$APP_USER"
    echo "[SUCCESS] User ${APP_USER} berhasil dibuat."
fi

# Buat direktori hanya jika belum ada, lalu laporkan statusnya.
ensure_dir() {
    local dir="$1"
    if run_root test -d "$dir"; then
        echo "[INFO] Direktori ${dir} sudah ada."
    else
        run_root mkdir -p "$dir"
        echo "[SUCCESS] Direktori ${dir} berhasil dibuat."
    fi
}

# 3. Direktori kerja
ensure_dir "$APP_DATA"
ensure_dir "$APP_LOG"

# 4. Kepemilikan dan permission (menetapkan ulang state yang diinginkan)
run_root chown -R "${APP_USER}:${APP_GROUP}" "$APP_HOME" "$APP_LOG"
run_root chmod 0750 "$APP_HOME" "$APP_LOG"
echo "[INFO] Kepemilikan ${APP_USER}:${APP_GROUP} dan permission 0750 telah diterapkan."

