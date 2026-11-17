#!/usr/bin/env bash
# =============================================================================
# scripts/03_configure_sec.sh
# Konfigurasi keamanan: firewall, SELinux, dan pembatasan bind-address MariaDB.
#
# Dipanggil oleh deploy.sh dengan:  bash scripts/03_configure_sec.sh
# Variabel dari deploy.sh        :  OS_ID, DEPLOY_ROOT (di-export)
# Sifat                          :  idempoten (aman dijalankan berulang kali)
# =============================================================================
set -euo pipefail
set -o errtrace
IFS=$'\n\t'

# --- Logging & penanganan error ---------------------------------------------
info() { printf '[INFO] %s\n' "$*"; }
ok()   { printf '[SUCCESS] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }

on_error() {
  local line_no=$1
  local last_command=$2
  echo "[CRITICAL ERROR] 03_configure_sec.sh: perintah '${last_command}' gagal di baris ${line_no}!" >&2
}
trap 'on_error $LINENO "$BASH_COMMAND"' ERR
trap 'echo "[INFO] 03_configure_sec.sh dibatalkan oleh pengguna." >&2; exit 130' INT TERM

# Jalankan perintah dengan hak root (langsung jika sudah root, sudo jika bukan).
run() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

# --- Variabel dari deploy.sh (dengan fallback bila dijalankan mandiri) ------
DEPLOY_ROOT="${DEPLOY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
if [ -z "${OS_ID:-}" ] && [ -f /etc/os-release ]; then
  OS_ID="$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"')"
fi
: "${OS_ID:?OS_ID tidak terdefinisi dan /etc/os-release tidak ditemukan}"

# --- Keluarga RHEL: firewalld ------------------------------------------------
configure_firewall_rhel() {
  info "Mengonfigurasi firewalld (keluarga RHEL)..."

  if ! command -v firewall-cmd >/dev/null 2>&1; then
    warn "firewalld belum terpasang, mencoba memasang..."
    run dnf install -y firewalld
  fi

  run systemctl enable --now firewalld

  local need_reload=0
  if run firewall-cmd --permanent --query-service=http >/dev/null 2>&1; then
    info "Layanan HTTP sudah diizinkan di konfigurasi permanen."
  else
    run firewall-cmd --permanent --add-service=http
    need_reload=1
    ok "Layanan HTTP ditambahkan ke konfigurasi permanen."
  fi

  # Reload hanya bila ada perubahan, atau aturan runtime belum sinkron.
  local runtime_ok=0
  if run firewall-cmd --query-service=http >/dev/null 2>&1; then
    runtime_ok=1
  fi
  if [ "$need_reload" -eq 1 ] || [ "$runtime_ok" -eq 0 ]; then
    run firewall-cmd --reload
    ok "firewalld di-reload."
  fi
}

# --- Keluarga RHEL: SELinux --------------------------------------------------
configure_selinux() {
  if ! command -v getenforce >/dev/null 2>&1; then
    warn "Perintah getenforce tidak ditemukan; langkah SELinux dilewati."
    return 0
  fi
  if [ "$(getenforce)" = "Disabled" ]; then
    warn "SELinux dalam keadaan Disabled; langkah boolean dilewati."
    return 0
  fi

  local current
  current="$(getsebool httpd_can_network_connect | awk '{print $NF}')"
  if [ "$current" = "on" ]; then
    info "Boolean httpd_can_network_connect sudah on."
  else
    run setsebool -P httpd_can_network_connect 1
    ok "Boolean httpd_can_network_connect diaktifkan (permanen)."
  fi
}

# --- Keluarga Debian/Ubuntu: ufw --------------------------------------------
configure_firewall_debian() {
  if ! command -v ufw >/dev/null 2>&1; then
    warn "ufw tidak tersedia; langkah firewall dilewati."
    return 0
  fi
  info "Mengonfigurasi ufw (keluarga Debian/Ubuntu)..."

  # Izinkan SSH TERLEBIH DAHULU agar sesi tidak terputus saat ufw diaktifkan.
  if run ufw app info OpenSSH >/dev/null 2>&1; then
    run ufw allow OpenSSH
  else
    run ufw allow 22/tcp
  fi

  if run ufw app info 'Nginx HTTP' >/dev/null 2>&1; then
    run ufw allow 'Nginx HTTP'
  else
    run ufw allow 80/tcp
  fi

  local status
  status="$(run ufw status)"
  case "$status" in
    *"Status: active"*)
      info "ufw sudah aktif."
      ;;
    *)
      run ufw --force enable
      ok "ufw diaktifkan."
      ;;
  esac
}

# --- Database: pastikan hanya listen di loopback ----------------------------
configure_db_bind() {
  local want="127.0.0.1"
  local cnf="${DB_CNF:-}"

  if [ -z "$cnf" ]; then
    case "$OS_ID" in
      rhel|rocky|almalinux|fedora) cnf="/etc/my.cnf.d/mariadb-server.cnf" ;;
      ubuntu|debian)               cnf="/etc/mysql/mariadb.conf.d/50-server.cnf" ;;
    esac
  fi

  if [ ! -f "$cnf" ]; then
    warn "Konfigurasi MariaDB tidak ditemukan (${cnf}); langkah bind-address dilewati."
    return 0
  fi

  local pattern='^[[:space:]]*bind-address[[:space:]]*='
  local total bad changed=0
  total="$(grep -Ec "$pattern" "$cnf" || true)"
  bad="$(grep -E "$pattern" "$cnf" | grep -Evc '=[[:space:]]*127\.0\.0\.1[[:space:]]*$' || true)"

  if [ "$total" -eq 0 ]; then
    # Belum ada bind-address: sisipkan satu baris di bawah [mysqld].
    [ -f "${cnf}.bak" ] || run cp -a "$cnf" "${cnf}.bak"
    if grep -Eq '^\[mysqld\][[:space:]]*$' "$cnf"; then
      run sed -i '0,/^\[mysqld\][[:space:]]*$/s//[mysqld]\nbind-address = 127.0.0.1/' "$cnf"
    else
      printf '\n[mysqld]\nbind-address = %s\n' "$want" | run tee -a "$cnf" >/dev/null
    fi
    changed=1
    ok "bind-address = ${want} ditambahkan ke ${cnf}."
  elif [ "$bad" -gt 0 ]; then
    # Ada bind-address tetapi bukan 127.0.0.1: ganti nilainya (tanpa baris ganda).
    [ -f "${cnf}.bak" ] || run cp -a "$cnf" "${cnf}.bak"
    run sed -i -E "s|${pattern}.*\$|bind-address = ${want}|" "$cnf"
    changed=1
    ok "bind-address diubah menjadi ${want} di ${cnf}."
  else
    info "bind-address sudah ${want}; tidak ada perubahan."
  fi

  if [ "$changed" -eq 1 ]; then
    if systemctl is-active --quiet mariadb; then
      run systemctl restart mariadb
      ok "mariadb di-restart agar konfigurasi baru berlaku."
    else
      info "mariadb belum aktif; konfigurasi berlaku saat service dijalankan."
    fi
  fi
}

main() {
  info "Mulai konfigurasi keamanan (OS_ID=${OS_ID}, DEPLOY_ROOT=${DEPLOY_ROOT})"

  case "$OS_ID" in
    rhel|rocky|almalinux|fedora)
      configure_firewall_rhel
      configure_selinux
      ;;
    ubuntu|debian)
      configure_firewall_debian
      ;;
    *)
      echo "Distro ${OS_ID} belum didukung!" >&2
      exit 1
      ;;
  esac

  configure_db_bind
  ok "Konfigurasi keamanan selesai."
}

main "$@"
