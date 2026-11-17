# Arsitektur Multi-Tier & Otomasi Bash

Proyek Team-Based Milestone 2 (UK5) mata kuliah Praktikum Sistem Operasi, Sekolah Vokasi UNS.
Satu perintah, `./deploy.sh`, menyiapkan seluruh server web (gateway Nginx, aplikasi backend
sebagai service systemd, dan database MariaDB) secara otomatis dan **idempoten**: dijalankan
sekali atau berkali-kali, keadaan akhir sistem tetap sama dan tidak error.

## Arsitektur

```text
 [ Internet / Public Client ]
            |  Port 80/443 (TCP)
            v
 [ Tier 1: Nginx Gateway / Reverse Proxy ]
            |  HTTP ke 127.0.0.1:8000 (loopback)
            v
 [ Tier 2: Backend App (systemd service: webapp) ]
            |  TCP 3306 (loopback saja)
            v
 [ Tier 3: Database MariaDB (terisolasi, bind 127.0.0.1) ]
```

Prinsip desain:

- **Isolasi layanan**: database hanya listen di `127.0.0.1`, tidak terekspos ke IP publik.
- **Least privilege**: aplikasi berjalan sebagai user sistem `webapp` tanpa shell (`/sbin/nologin`).
- **Idempotensi**: setiap skrip mengecek kondisi sebelum mengubah sistem.
- **Zero hardcoded credentials**: password dan secret hanya dari file `.env` berizin `0600`.

## Prasyarat

- Salah satu OS: **AlmaLinux**, **Rocky Linux**, atau **Ubuntu** (juga Debian/RHEL/Fedora).
- Akses `sudo` (atau login sebagai root).
- Koneksi internet untuk mengunduh paket.

## Quick Start

```bash
# 1. Salin template environment, lalu isi nilainya (DB_NAME, DB_USER, DB_PASS, dst.)
cp env.example .env
chmod 0600 .env
nano .env

# 2. Jalankan master installer
chmod +x deploy.sh
./deploy.sh
```

Setelah selesai, jalankan pengujian otomatis:

```bash
bash tests/health_check.sh
```

## Struktur Direktori

```text
project-root/
├── README.md                  # Arsitektur & Quick Start
├── deploy.sh                  # Master Idempotent Installer
├── env.example                # Template environment variable
├── systemd/
│   └── webapp.service         # Custom systemd unit
├── configs/
│   ├── nginx.conf.template    # Template Nginx reverse proxy (envsubst)
│   └── database.cnf           # Database hardening config
├── scripts/
│   ├── 01_setup_users.sh      # Provisioning user, group, direktori
│   ├── 02_install_deps.sh     # Instalasi paket (RHEL & Debian/Ubuntu)
│   └── 03_configure_sec.sh    # Firewall, SELinux, bind-address database
└── tests/
    └── health_check.sh        # Smoke test & load test ringan
```

## Menguji Idempotensi

Jalankan installer **dua kali berturut-turut** pada VM yang bersih. Keduanya harus selesai
tanpa error (exit code 0) dan run kedua tidak boleh menduplikasi konfigurasi apa pun.

```bash
./deploy.sh; echo "Run 1 exit code: $?"
./deploy.sh; echo "Run 2 exit code: $?"
bash tests/health_check.sh
```

Pada run kedua, skrip keamanan hanya mencetak pesan `[INFO] ... sudah ...` dan tidak
mengubah firewall, SELinux, maupun konfigurasi database.

## Keamanan yang Diterapkan (`scripts/03_configure_sec.sh`)

| Komponen | RHEL family (AlmaLinux/Rocky) | Debian family (Ubuntu) |
|---|---|---|
| Firewall | `firewalld` aktif, layanan `http` dibuka | `ufw`: SSH diizinkan dulu, lalu `Nginx HTTP`, lalu aktif |
| SELinux | Boolean `httpd_can_network_connect=on` | tidak berlaku |
| Database | `bind-address = 127.0.0.1` di konfigurasi MariaDB | sama |

## Pemeriksaan Kualitas

```bash
# Linting seluruh skrip (harus bersih tanpa peringatan)
shellcheck deploy.sh scripts/*.sh tests/*.sh

# Smoke test: service aktif, Nginx merespons, port 3306 tidak terekspos, load test 20 request
bash tests/health_check.sh
```

## Tim

Kelompok 3, Program Studi Sarjana Terapan Teknologi Informasi dan Kecerdasan Artifisial, Sekolah Vokasi UNS.

| No | Anggota | Peran |
|---|---|---|
| 1 | Muhammad Zaidan Fakhri | Integrator & Master Installer |
| 2 | Muhammad Fatih | Provisioning & Dependensi |
| 3 | Nauval Fadil Barata | Systemd & Gateway Nginx |
| 4 | Octa Fitria Aziza | Keamanan, Dokumentasi & QA |
