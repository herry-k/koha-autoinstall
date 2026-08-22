<div align="center">

```
██╗  ██╗ ██████╗ ██╗  ██╗ █████╗
██║ ██╔╝██╔═══██╗██║  ██║██╔══██╗
█████╔╝ ██║   ██║███████║███████║
██╔═██╗ ██║   ██║██╔══██║██╔══██║
██║  ██╗╚██████╔╝██║  ██║██║  ██║
╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝
```

# koha-autoinstall

**One-command, production-grade installer for the Koha Integrated Library System**

[![Platform](https://img.shields.io/badge/platform-Ubuntu%2024.04%20LTS-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com)
[![Koha](https://img.shields.io/badge/Koha-25.11%20stable-4A90D9?logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAyNCAyNCI+PHBhdGggZmlsbD0id2hpdGUiIGQ9Ik0xMiAyQzYuNDggMiAyIDYuNDggMiAxMnM0LjQ4IDEwIDEwIDEwIDEwLTQuNDggMTAtMTBTMTcuNTIgMiAxMiAyem0wIDE4Yy00LjQxIDAtOC0zLjU5LTgtOHMzLjU5LTggOC04IDggMy41OSA4IDgtMy41OSA4LTggOHoiLz48L3N2Zz4=)](https://koha-community.org)
[![Shell](https://img.shields.io/badge/shell-bash%205%2B-4EAA25?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)](CONTRIBUTING.md)
[![Stars](https://img.shields.io/github/stars/yourusername/koha-autoinstall?style=social)](https://github.com/yourusername/koha-autoinstall)

</div>

---

## What is this?

A single Bash script that installs a **fully working Koha ILS** on Ubuntu 24.04 LTS in one command — no manual configuration, no hardcoded passwords, no guesswork. It runs completely unattended, detects and removes any previous installation, shows a live colour GUI dashboard while it works, and leaves you with a complete credentials file and install log when done.

### What is Koha?

[Koha](https://koha-community.org) is the world's first free and open-source Integrated Library System (ILS). Used by thousands of libraries globally, it handles cataloguing, circulation, acquisitions, serials, OPAC (public catalogue), and more.

---

## Quick Start

```bash
# Download
wget https://raw.githubusercontent.com/herry-k/koha-autoinstall/main/koha-install.sh

# Run
sudo bash koha-install.sh
```

That's it. The script handles everything — you don't answer a single prompt.

---

## Terminal Preview

```
╔══════════════════════════════════════════════════════════════════════════════╗
║         KOHA ILS AUTO-INSTALLER  •  Ubuntu 24.04.4 LTS  •  14:32:07        ║
╠══════════════════════════════════════════════════════════════════════════════╣
  ████████████████████████████████░░░░░░░░░░░░░░░░░░░░   69%   step 9/14
  ⣾  [9/14]  Creating Koha database and DB user
  ▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪·····  Checking for existing database
  Detected: MariaDB already installed → purging first
  Elapsed: 04:21  •  Pkgs: 183  •  Purged: 47  •  Retries: 0
──────────────────────────────────────────────────────────────────────────────
  ▼  Live Activity Feed  (real-time output)
──────────────────────────────────────────────────────────────────────────────
  ◉  PURGE  Dropping database koha_abc123 and user
  ▷  DROP DATABASE IF EXISTS koha_abc123
  ▷  DROP USER IF EXISTS 'koha_abc123'@'localhost'
  ✔  Database and user dropped
  ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄
  ▶  Creating database koha_xyz789 (utf8mb4)
  ✔  Database and user auth verified
  ✔  Step 9 complete
  OK    DB: koha_xyz789  •  user auth verified  •  utf8mb4
```

---

## Features

### 🎨 Full-Colour Live Dashboard
- Fixed 11-line header with dual animated progress bars (overall + sub-step)
- Live scrolling activity feed showing real apt output, package names, and command results
- Colour-coded output: cyan for downloads, green for success, magenta for packages, red for errors
- Braille spinner (`⣾⣽⣻⢿⡿⣟⣯⣷`) animating at 10fps during every step
- Progress bar colour shifts red → yellow → green as installation advances
- Real-time counters: elapsed time, packages installed, packages purged, retry count

### 🔍 Smart Detection Engine
Before installing anything, the script scans for existing components:

| Component | Detection method | Action if found |
|---|---|---|
| MariaDB | `dpkg -l mariadb-server` | Stop → purge → remove `/var/lib/mysql` |
| Apache2 | `dpkg -l apache2` | Stop → purge → remove `/etc/apache2` |
| Koha repository | `/etc/apt/sources.list.d/koha.list` | Remove file + GPG key → re-add |
| koha-common | `dpkg -l koha-common` | Stop instances → purge → remove `/etc/koha` |
| Koha DB | `SHOW DATABASES` via mysql | `DROP DATABASE` + `DROP USER` |
| Koha instance | `/etc/koha/sites/<instance>` | `a2dissite` → `koha-remove` → `rm -rf` |
| Memcached | `dpkg -l memcached` | Stop → purge |

A detection table is displayed before any changes are made.

### 🔒 Production Hardening

| Feature | Detail |
|---|---|
| **Lock file** | `/var/run/koha-installer.lock` — rejects concurrent runs, checks PID liveness |
| **OS gate** | Aborts on non-Ubuntu or Ubuntu < 22.04; warns on non-24.04 |
| **RAM guard** | Hard abort if less than 1 GB RAM |
| **Disk guard** | Checked globally (min 5 GB) and before every heavy step individually |
| **apt lock wait** | Polls for apt lock up to 5 minutes with 5s sleep, then fatal error |
| **Retry logic** | `with_retry <n> <delay> <desc> <cmd>` — exponential back-off, used for network ops |
| **No `set -e`** | Avoids `(( expr ))` = 0 silent kills; every error handled explicitly with `\|\| fatal` |
| **Service verification** | `verify_service <name>` waits up to 12s confirming systemd `is-active` |
| **Config verification** | Koha sites.conf values confirmed via `grep` after writing |
| **DB auth test** | Both root and Koha DB user logins are tested after credential setup |
| **Apache syntax test** | `apache2ctl configtest` required before restart |
| **UFW auto-open** | Ports 80 and 8080 opened automatically if UFW is active |
| **Signal trapping** | `SIGINT` `SIGTERM` `SIGHUP` all invoke clean error + rollback |
| **EXIT trap** | Always restores cursor, removes lock file; calls `handle_fatal` on unexpected exits only |
| **Cursor safety** | `tput civis` / `tput cnorm` managed — terminal is never left with hidden cursor |

### 🔁 Rollback State Machine
Every successfully completed step pushes its name onto `ROLLBACK_STACK`. If any subsequent step fails:

1. Full-screen red error panel shown with failed step name and command
2. Stack unwound in **reverse order** — removes only what this run installed
3. `apt autoremove` called to clean orphaned packages
4. Last 15 log lines printed to terminal
5. Credentials file (if created) left in place for reference

### 🧪 Post-Install Smoke Test (Step 14)
- HTTP `curl` to `http://127.0.0.1:80` (OPAC) and `:8080` (Staff) — checks 200/301/302/303
- MariaDB connection test as the Koha DB user with the generated password
- Results shown in summary box and written to credentials file

---

## Requirements

| Requirement | Minimum | Recommended |
|---|---|---|
| OS | Ubuntu 22.04 LTS | **Ubuntu 24.04.4 LTS** |
| RAM | 1 GB | 4 GB+ |
| Disk | 5 GB free | 20 GB+ |
| Network | Required | Stable broadband |
| Privileges | root / sudo | root / sudo |
| Bash | 4.0+ | 5.0+ (default on 24.04) |

No other dependencies — no Python, no Node, no Docker. Pure Bash + standard Ubuntu packages.

---

## What Gets Installed

| Component | Version | Purpose |
|---|---|---|
| **Koha** | latest stable (~25.11) | Library management system |
| **MariaDB** | distro default (~10.11) | Database backend |
| **Apache2** | distro default (~2.4) | Web server |
| **Memcached** | distro default | Session and object cache |
| **Zebra** | via koha-common | Bibliographic search engine |
| **Perl modules** | various | Koha runtime dependencies |

---

## Output Files

After a successful install, two files are created:

### `/root/koha-credentials-<timestamp>.txt` (chmod 600)
```ini
[System]
server_ip      = 192.168.1.105
ubuntu_version = Ubuntu 24.04.4 LTS

[MariaDB]
root_password  = Xk9!mNq3#Rp7vWe2@Yt5zL8

[Koha Database]
db_name        = koha_abc7f3c1
db_user        = koha_abc7f3c1
db_password    = Bv4@Jd8!Wn2^Hs6#Ym9pKx1

[Staff Interface / Web Installer]
url            = http://192.168.1.105:8080
username       = koha_abc7f3c1
password       = Bv4@Jd8!Wn2^Hs6#Ym9pKx1

[OPAC — Public Catalogue]
url            = http://192.168.1.105:80

[Smoke Test Results]
staff_http     = 302
opac_http      = 302
smoke_status   = PASSED

[Installation Stats]
packages_added  = 247+
packages_purged = 0
retry_count     = 0
total_time      = 8m34s
log_file        = /var/log/koha-install-20260317_143201.log
```

### `/var/log/koha-install-<timestamp>.log`
Full verbose log of every command, its output, and timestamps. Survives across sessions. View with:
```bash
sudo cat /var/log/koha-install-*.log
```

---

## After Install — Next Steps

1. Open the **Staff URL** in your browser: `http://<server-ip>:8080`
2. Log in with the credentials from the credentials file
3. Follow the **Koha web installer wizard** (5–10 minutes)
4. Create your **library branch** and **superlibrarian account**
5. Start cataloguing!

> **Tip:** The web installer must be completed before Koha is usable. It sets up the database schema, mandatory system preferences, and your first library.

---

## Error Recovery

If the install fails at any step:

```
╔══════════════════════════════════════════════════════════════════╗
║                  ✘   INSTALLATION FAILED                        ║
╠══════════════════════════════════════════════════════════════════╣
  Failed at:  Installing koha-common
  Command:    apt-get install -yq koha-common

  Attempting rollback of completed steps...
  ↩  Rolling back: koha_repo
  ↩  Rolling back: apache
  ↩  Rolling back: mariadb
  Rollback finished.

  Review the log:  sudo cat /var/log/koha-install-*.log
```

The script rolls back automatically and leaves your system clean. Fix the underlying issue (network, disk, etc.) and run again — the detection engine will handle any partial state.

---

## Security Notes

- All passwords are generated with `/dev/urandom` — 24 characters, mixed alphanumeric + symbols
- Credentials are written to `/root/koha-credentials-<timestamp>.txt` with `chmod 600` — readable only by root
- Passwords are **never** passed as command-line arguments (no `ps` / shell history exposure)
- MariaDB is secured: root password set, anonymous users removed, test database dropped, remote root login disabled
- No passwords are ever hardcoded in the script

---

## Uninstalling

To remove a Koha installation created by this script:

```bash
# Get the instance name from your credentials file
INSTANCE=$(grep instance_name /root/koha-credentials-*.txt | awk '{print $3}')

# Stop and remove
sudo a2dissite "$INSTANCE"
sudo koha-stop "$INSTANCE"
sudo koha-remove "$INSTANCE"
sudo apt-get purge -y koha-common mariadb-server apache2 memcached
sudo apt-get autoremove -y
sudo rm -rf /etc/koha /var/lib/mysql /etc/mysql /etc/apache2
```

---

## Troubleshooting

<details>
<summary><b>Script exits immediately after pre-flight checks</b></summary>

Check the log file for the exact error:
```bash
sudo cat /var/log/koha-install-*.log | tail -30
```

Common causes:
- **apt locked**: another process (unattended-upgrades, snap) holds the dpkg lock. Wait and retry.
- **No network**: `ping debian.koha-community.org` — if it fails, fix your network config.
- **Low disk**: `df -h /` — need at least 5 GB free.
</details>

<details>
<summary><b>Smoke test returns HTTP 000</b></summary>

Koha may still be initialising. Wait 30 seconds and try:
```bash
curl -I http://localhost:8080
curl -I http://localhost:80
```
If still failing, check Apache:
```bash
sudo systemctl status apache2
sudo journalctl -u apache2 --no-pager | tail -20
```
</details>

<details>
<summary><b>Web installer shows database error</b></summary>

The DB password in `koha-conf.xml` may not match. Check:
```bash
sudo grep '<pass>' /etc/koha/sites/*/koha-conf.xml
sudo cat /root/koha-credentials-*.txt | grep db_password
```
If they differ, update `koha-conf.xml` and restart Apache.
</details>

<details>
<summary><b>Port 80 or 8080 already in use</b></summary>

Find what's using the port:
```bash
sudo ss -tlnp | grep ':80\b'
sudo ss -tlnp | grep ':8080'
```
Stop the conflicting service or edit the script to change `OPAC_PORT` and `INTRA_PORT` before running.
</details>

<details>
<summary><b>Stale lock file prevents re-run</b></summary>

```bash
sudo rm -f /var/run/koha-installer.lock
```
</details>

---

## File Structure

```
koha-autoinstall/
├── koha-install.sh      # Main installer script (1,406 lines)
├── README.md            # This file
├── LICENSE              # MIT License
└── CONTRIBUTING.md      # Contribution guidelines
```

---

## How It Works

```
START
  │
  ├─ Lock file check ──────────────────────────── abort if already running
  ├─ Pre-flight checks
  │    ├─ OS version gate (Ubuntu 22+)
  │    ├─ RAM ≥ 1 GB
  │    ├─ Disk ≥ 5 GB
  │    ├─ Network connectivity
  │    ├─ systemd operational
  │    └─ /root writable
  │
  ├─ Auto-generate credentials (24-char random passwords)
  ├─ Save credentials → /root/koha-credentials-*.txt (chmod 600)
  │
  ├─ Detection scan ───────────────────────────── show table of found components
  │
  ├─ Switch to live dashboard (clear screen, fixed header)
  │
  ├─ Step 1:  System update
  ├─ Step 2:  MariaDB ──────── detect → purge if found → install fresh → verify
  ├─ Step 3:  Secure MariaDB ─ set root password → verify auth
  ├─ Step 4:  Apache2 ──────── detect → purge if found → install fresh → verify
  ├─ Step 5:  Koha repo ────── detect → remove if found → re-add → verify
  ├─ Step 6:  koha-common ──── detect → purge if found → install fresh → verify
  ├─ Step 7:  Configure koha-sites.conf → verify written values
  ├─ Step 8:  Enable Apache modules → verify Apache starts
  ├─ Step 9:  Create Koha DB + user ── detect → drop if found → create → verify auth
  ├─ Step 10: Create Koha instance ─── detect → remove if found → create → verify
  ├─ Step 11: Apache vhost ──── configtest → enable → verify Apache starts
  ├─ Step 12: Memcached ────── detect → purge if found → install → verify
  ├─ Step 13: Perl modules + UFW rules + restart all services + verify all
  ├─ Step 14: Smoke test ─────── HTTP curl to :80 and :8080 + DB auth test
  │
  ├─ INSTALL_SUCCEEDED=1 ──────────────────────── disarm EXIT trap
  ├─ Append smoke results + stats to credentials file
  └─ Print full colour summary box
       System info, detection results, smoke test, URLs, credentials, file paths
```

On **any failure** in steps 2–14:
```
fatal() → handle_fatal() → run_rollback() → unwind ROLLBACK_STACK in reverse → exit 1
```

---

## Contributing

Pull requests are welcome! Please:

1. Fork the repo and create a feature branch
2. Test on a clean Ubuntu 24.04 VM before submitting
3. Run `bash -n koha-install.sh` to verify syntax
4. Keep the live dashboard working — test with a real terminal (not just syntax check)
5. Document any new step in this README

See [CONTRIBUTING.md](CONTRIBUTING.md) for full guidelines.

### Known Improvement Areas
- [ ] Support for Ubuntu 22.04 Jammy (currently warned, not blocked)
- [ ] Optional domain/FQDN argument for named vhosts
- [ ] HTTPS/Let's Encrypt auto-setup post-install
- [ ] Optional Z39.50 target configuration
- [ ] Multi-instance support
- [ ] Ansible role wrapping this script

---

## Tested On

| Environment | Status |
|---|---|
| Ubuntu 24.04.4 LTS (bare metal) | ✅ Tested |
| Ubuntu 24.04.4 LTS (VirtualBox VM) | ✅ Tested |
| Ubuntu 24.04.4 LTS (KVM/QEMU) | ✅ Tested |
| Ubuntu 24.04.4 LTS (AWS EC2 t3.medium) | ✅ Tested |
| Ubuntu 24.04.4 LTS (DigitalOcean Droplet) | ✅ Tested |
| Ubuntu 22.04.4 LTS | ⚠️ Works with warning |
| Ubuntu 20.04 LTS | ❌ Blocked (too old) |
| Debian 12 | ❌ Not supported |

---

## License

MIT License — see [LICENSE](LICENSE) for full text.

---

## Acknowledgements

- [Koha Community](https://koha-community.org) — for building and maintaining the world's most widely deployed open-source ILS
- [Koha Debian packages](https://debian.koha-community.org) — for the excellent apt repository and packaging
- All the library staff around the world who rely on Koha every day

---

<div align="center">

**Made with ❤️ for libraries everywhere**

[⭐ Star this repo](https://github.com/yourusername/koha-autoinstall) · [🐛 Report a bug](https://github.com/yourusername/koha-autoinstall/issues) · [💡 Request a feature](https://github.com/yourusername/koha-autoinstall/issues)

</div>
