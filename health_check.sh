#!/usr/bin/env bash
# =============================================================================
# tests/health_check.sh
# Smoke test otomatis untuk stack Nginx -> webapp -> MariaDB.
# Cetak PASS/FAIL per pengecekan; exit 1 jika ada yang FAIL.
#
# Pemakaian : ./tests/health_check.sh
# Opsional  : BASE_URL, DB_PORT, LOAD_REQUESTS dapat di-override lewat env.
# =============================================================================
set -euo pipefail
IFS=$'\n\t'

BASE_URL="${BASE_URL:-http://127.0.0.1/}"
DB_PORT="${DB_PORT:-3306}"
LOAD_REQUESTS="${LOAD_REQUESTS:-20}"
SERVICES=(nginx mariadb webapp)
FAILED=0

pass() { printf '[PASS] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*"; FAILED=$((FAILED + 1)); }

check_services() {
  local svc
  for svc in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$svc"; then
      pass "Service ${svc} aktif"
    else
      fail "Service ${svc} tidak aktif"
    fi
  done
}

check_nginx_response() {
  if curl -fsS -o /dev/null --max-time 5 "$BASE_URL"; then
    pass "Nginx merespons di ${BASE_URL}"
  else
    fail "Nginx tidak merespons di ${BASE_URL}"
  fi
}

check_db_not_exposed() {
  if ! command -v ss >/dev/null 2>&1; then
    fail "Perintah ss tidak ditemukan (paket iproute/iproute2)"
    return 0
  fi

  local listeners exposed
  listeners="$(ss -ltn | awk '{print $4}' | grep -E ":${DB_PORT}\$" || true)"

  if [ -z "$listeners" ]; then
    pass "Port ${DB_PORT} tidak listen di TCP (tidak terekspos)"
    return 0
  fi

  # Selain 127.0.0.1 dan ::1 (0.0.0.0, *, [::], IP LAN) dianggap terekspos.
  exposed="$(printf '%s\n' "$listeners" | grep -Ev "^(127\.0\.0\.1|\[::1\]):${DB_PORT}\$" || true)"
  if [ -z "$exposed" ]; then
    pass "Port ${DB_PORT} hanya listen di loopback"
  else
    fail "Port ${DB_PORT} terekspos di: ${exposed//$'\n'/, }"
  fi
}

load_test() {
  local ok=0 start elapsed
  start=$SECONDS
  for _ in $(seq 1 "$LOAD_REQUESTS"); do
    if curl -fsS -o /dev/null --max-time 5 "$BASE_URL"; then
      ok=$((ok + 1))
    fi
  done
  elapsed=$((SECONDS - start))

  if [ "$ok" -eq "$LOAD_REQUESTS" ]; then
    pass "Load test ringan: ${ok}/${LOAD_REQUESTS} request sukses (${elapsed} detik)"
  else
    fail "Load test ringan: hanya ${ok}/${LOAD_REQUESTS} request sukses (${elapsed} detik)"
  fi
}

main() {
  echo "=== Health Check: $(date '+%Y-%m-%d %H:%M:%S') ==="
  check_services

  if command -v curl >/dev/null 2>&1; then
    check_nginx_response
  else
    fail "curl tidak ditemukan; cek respons Nginx dilewati"
  fi

  check_db_not_exposed

  if command -v curl >/dev/null 2>&1; then
    load_test
  else
    fail "curl tidak ditemukan; load test dilewati"
  fi

  echo "-------------------------------------------"
  if [ "$FAILED" -eq 0 ]; then
    echo "HASIL AKHIR: SEMUA CEK PASS"
  else
    echo "HASIL AKHIR: ${FAILED} CEK FAIL"
    exit 1
  fi
}

main "$@"
