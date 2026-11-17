#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${DEPLOY_ROOT:-.}/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "[ERROR] File .env tidak ditemukan di ${ENV_FILE}. Salin dari env.example." >&2
    exit 1
fi

chmod 0600 "$ENV_FILE"

set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a

: "${DB_NAME:?Variabel DB_NAME wajib didefinisikan!}"
: "${DB_USER:?Variabel DB_USER wajib didefinisikan!}"
: "${DB_PASS:?Variabel DB_PASS wajib didefinisikan!}"
echo "[INFO] File .env valid: DB_NAME, DB_USER, dan DB_PASS terisi."

run_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

if [ -z "${OS_ID:-}" ]; then
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
    else
        OS_ID="unknown"
    fi
}

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

run_root systemctl enable --now mariadb
run_root systemctl enable --now nginx
echo "[SUCCESS] Paket terpasang dan service mariadb serta nginx aktif."
