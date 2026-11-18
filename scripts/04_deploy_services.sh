#!/usr/bin/env bash
set -euo pipefail

: "${DEPLOY_ROOT:?DEPLOY_ROOT belum di-export oleh deploy.sh}"
: "${OS_ID:?OS_ID belum di-export oleh deploy.sh}"

info()    { echo "[INFO] $*"; }
success() { echo "[SUCCESS] $*"; }
warn()    { echo "[WARN] $*" >&2; }
error()   { echo "[ERROR] $*" >&2; }

# Jalankan sebagai root: langsung jika sudah root, via sudo jika bukan.
run_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

SERVICE_SRC="${DEPLOY_ROOT}/systemd/webapp.service"
SERVICE_DST="/etc/systemd/system/webapp.service"
NGINX_TPL="${DEPLOY_ROOT}/configs/nginx.conf.template"
NGINX_DST="/etc/nginx/conf.d/webapp.conf"
APP_SRC="${DEPLOY_ROOT}/app/app.py"
APP_FILE="/var/www/webapp/app.py"

# --- Muat .env ---
if [ ! -f "${DEPLOY_ROOT}/.env" ]; then
  error ".env tidak ditemukan. Salin dari env.example"
  exit 1
fi
set -a
# shellcheck source=/dev/null
source "${DEPLOY_ROOT}/.env"
set +a
: "${APP_PORT:?APP_PORT belum diisi di .env}"
: "${DOMAIN_NAME:?DOMAIN_NAME belum diisi di .env}"

# --- Pastikan envsubst tersedia (paket gettext) ---
if ! command -v envsubst >/dev/null 2>&1; then
  info "Memasang gettext untuk envsubst..."
  case "${OS_ID}" in
    rhel|rocky|almalinux|fedora) run_root dnf install -y gettext ;;
    ubuntu|debian) run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y gettext-base ;;
    *) error "OS_ID tidak didukung: ${OS_ID}"; exit 1 ;;
  esac
fi

# --- 1. Pasang unit systemd (hanya jika berbeda) ---
unit_changed=0
if ! run_root cmp -s "${SERVICE_SRC}" "${SERVICE_DST}"; then
  run_root install -m 0644 "${SERVICE_SRC}" "${SERVICE_DST}"
  run_root systemctl daemon-reload
  unit_changed=1
  success "webapp.service dipasang/diperbarui"
else
  info "webapp.service sudah sesuai"
fi

# --- 2. Render template Nginx (tulis hanya jika berbeda) ---
tmp="$(mktemp)"
trap 'rm -f "${tmp}"' EXIT
# shellcheck disable=SC2016
envsubst '${APP_PORT} ${DOMAIN_NAME}' < "${NGINX_TPL}" > "${tmp}"

if ! run_root cmp -s "${tmp}" "${NGINX_DST}"; then
  run_root tee "${NGINX_DST}" < "${tmp}" >/dev/null
  success "Konfigurasi Nginx ditulis ke ${NGINX_DST}"
else
  info "Konfigurasi Nginx sudah sesuai"
fi

# --- 3. Validasi sebelum reload ---
if ! run_root nginx -t; then
  error "nginx -t gagal, periksa ${NGINX_DST}"
  exit 1
fi

# --- 4. Pasang aplikasi (hanya jika berbeda) ---
app_changed=0
if [ -f "${APP_SRC}" ]; then
  if ! run_root cmp -s "${APP_SRC}" "${APP_FILE}"; then
    run_root install -o webapp -g webapp -m 0640 "${APP_SRC}" "${APP_FILE}"
    app_changed=1
    success "app.py dipasang/diperbarui di ${APP_FILE}"
  else
    info "app.py sudah sesuai"
  fi
else
  warn "${APP_SRC} tidak ditemukan di repositori"
fi

# --- 5. Jalankan service ---
if [ -f "${APP_FILE}" ]; then
  run_root systemctl enable --now webapp.service
  if [ "${unit_changed}" -eq 1 ] || [ "${app_changed}" -eq 1 ]; then
    run_root systemctl restart webapp.service
  fi
else
  run_root systemctl enable webapp.service
  warn "${APP_FILE} belum ada, webapp.service belum dijalankan"
fi

run_root systemctl reload nginx
success "Deploy services selesai"
