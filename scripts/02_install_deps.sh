#!/usr/bin/env bash
# scripts/02_install_deps.sh
# Validasi file .env, pasang paket, dan aktifkan service.
# Membutuhkan variabel dari deploy.sh: OS_ID dan DEPLOY_ROOT.
set -euo pipefail
set -o errtrace

# Handler kegagalan: tampilkan perintah dan baris yang gagal.
on_error() {
    local line_no="$1"
    local last_cmd="$2"
    echo "[CRITICAL ERROR] Perintah '${last_cmd}' gagal di baris ${line_no}!" >&2
    exit 1
}
trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR
trap 'echo "[INFO] Skrip dibatalkan oleh pengguna." >&2; exit 130' INT TERM

: "${OS_ID:?Variabel OS_ID harus di-export oleh deploy.sh}"
: "${DEPLOY_ROOT:?Variabel DEPLOY_ROOT harus di-export oleh deploy.sh}"

ENV_FILE="${DEPLOY_ROOT}/.env"

run_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

# 1. Pastikan file .env ada
if [ ! -f "$ENV_FILE" ]; then
    echo "[ERROR] File .env tidak ditemukan di ${ENV_FILE}. Salin dari env.example." >&2
    exit 1
fi

# File berisi secret: batasi aksesnya hanya untuk pemilik
chmod 0600 "$ENV_FILE"

# 2. Muat variabel dari .env
set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

# 3. Validasi variabel wajib (gagal jika belum diset ATAU kosong)
: "${DB_NAME:?Variabel DB_NAME wajib didefinisikan!}"
: "${DB_USER:?Variabel DB_USER wajib didefinisikan!}"
: "${DB_PASS:?Variabel DB_PASS wajib didefinisikan!}"
echo "[INFO] File .env valid: DB_NAME, DB_USER, dan DB_PASS terisi."

# 4. Pasang paket sesuai keluarga distro
case "$OS_ID" in
    rhel|rocky|almalinux|centos|fedora)
        echo "[INFO] Memasang paket pada keluarga RHEL..."
        run_root dnf install -y nginx mariadb-server python3-pip
        ;;
    ubuntu|debian)
        echo "[INFO] Memasang paket pada keluarga Debian/Ubuntu..."
        run_root env DEBIAN_FRONTEND=noninteractive apt-get update -y
        run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y \
            nginx mariadb-server python3-pip
        ;;
    *)
        echo "[ERROR] Distro ${OS_ID} belum didukung!" >&2
        exit 1
        ;;
esac

# 5. Aktifkan dan jalankan service
run_root systemctl enable --now mariadb
run_root systemctl enable --now nginx
echo "[SUCCESS] Paket terpasang dan service mariadb serta nginx aktif."
EOF
