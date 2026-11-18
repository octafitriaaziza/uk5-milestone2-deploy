#!/usr/bin/env bash
# Versi: Milestone 2 - Kelompok 3 (Zaidan Fakhri)
# deploy.sh - Master Idempotent Installer
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

error_handler() {
  local line_no=$1
  local last_command=$2
  echo "[CRITICAL ERROR] Perintah '$last_command' gagal di baris $line_no!" >&2
  exit 1
}

trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap 'echo "[INFO] Skrip dibatalkan oleh pengguna."; exit 130' INT TERM

echo "[INFO] Memulai deployment..."

# 1. Deteksi distro
if [ -f /etc/os-release ]; then
# shellcheck source=/etc/os-release
  . /etc/os-release
  OS_ID=$ID
else
  echo "[ERROR] OS tidak dikenali!" >&2
  exit 1
fi

case "$OS_ID" in
  rhel|rocky|almalinux|fedora)
    echo "[INFO] Terdeteksi keluarga RHEL: $OS_ID"
    ;;
  ubuntu|debian)
    echo "[INFO] Terdeteksi keluarga Debian: $OS_ID"
    ;;
  *)
    echo "[ERROR] Distro $OS_ID belum didukung!" >&2
    exit 1
    ;;
esac

export OS_ID
export DEPLOY_ROOT="$SCRIPT_DIR"

# 2. Jalankan modul secara berurutan
MODULES=(
  "$SCRIPT_DIR/scripts/01_setup_users.sh"
  "$SCRIPT_DIR/scripts/02_install_deps.sh"
  "$SCRIPT_DIR/scripts/03_configure_sec.sh"
  "$SCRIPT_DIR/scripts/04_deploy_services.sh"
)

for module in "${MODULES[@]}"; do
  if [ ! -f "$module" ]; then
    echo "[ERROR] Modul tidak ditemukan: $module" >&2
    exit 1
  fi
  echo "[INFO] Menjalankan $(basename "$module") ..."
  bash "$module"
done

echo "[SUCCESS] Deployment selesai."
