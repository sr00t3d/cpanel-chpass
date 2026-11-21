🇺🇸 **English** | [🇧🇷 Português (BR)](README-ptbr.md) | [🇪🇸 Español](README-es.md)

# cpanel-chpass — Safe cPanel/WHM Account Password Changer & Rotator CLI

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-2.0.0-brightgreen.svg)](https://github.com/sr00t3d/cpanel-chpass/releases)
[![Bash](https://img.shields.io/badge/Linux-Bash%204.0%2B-4EAA25?logo=gnu-bash&logoColor=white)](chpass.sh)

**`chpass.sh`** is a hardened Bash CLI for changing and rotating cPanel/WHM account passwords (with automatic MySQL sync) using official **`whmapi1 passwd`** (with `/scripts/chpass` fallback), CSPRNG strong password generation (`/dev/urandom`), strict protection against `root` / system accounts (`UID < 500`), batch & reseller rotation, `--dry-run`, `chmod 600` credential export, and `table`, `json`, and `csv` outputs.

> **Historical Inspiration:** Clean-room Bash reimplementation inspired by `chpass` (`ecpp_2.pl`, 2012, **Michael Karr** / HostGator Toolbox). Replaces the legacy internal Perl `Cpanel::ChangePasswd` call and weak `rand()` 12-char generator with official `whmapi1`, CSPRNG passwords, dry-run validation, and batch incident-response rotation.

---

## Features

- **Official cPanel/WHM API:** Uses `whmapi1 --output=json passwd` (syncing cPanel, FTP, SSH, and MySQL passwords) with automatic fallback to `/usr/local/cpanel/scripts/chpass`.
- **Protected Account Guard:** Refuses to modify `root`, `nobody`, `cpanel`, `mysql`, `exim`, or any user with `UID < 500` or missing `/var/cpanel/users/<user>`.
- **CSPRNG Strong Passwords:** Generates 16+ char passwords from `/dev/urandom` guaranteeing uppercase, lowercase, digits, and symbols (customizable via `-l/--length` or `--alnum`).
- **Batch & Reseller Rotation:** Rotate multiple accounts via `-f/--file users.txt` or an entire reseller via `-r/--reseller <name>` (`/etc/trueuserowners`), saving rotated credentials to a `chmod 600` file via `--save`.
- **Safe Dry-Run & Automation:** `--dry-run` simulates changes safely; `-o table|json|csv` integrates cleanly with runbooks and NOC tools.

---

## Direct Execution (Linux / cPanel)

```bash
# Dry-run test without cloning
bash <(curl -fsSL https://raw.githubusercontent.com/sr00t3d/cpanel-chpass/main/chpass.sh) alice --dry-run
```

---

## Installation & Usage

```bash
git clone https://github.com/sr00t3d/cpanel-chpass.git
cd cpanel-chpass
chmod +x chpass.sh

# Auto-generate a strong 16-char password for a cPanel account (syncs MySQL)
sudo ./chpass.sh alice

# Set an explicit password without changing MySQL password
sudo ./chpass.sh alice 'Str0ng#Pass2026!' --no-mysql

# Simulate batch rotation for a reseller in JSON
sudo ./chpass.sh -r myreseller --dry-run -o json

# Incident response: rotate all accounts in a list and save creds with chmod 600
sudo ./chpass.sh -f compromised.txt --save /root/rotated-creds.txt
```

---

## Real Output Example

### Single Account Dry-Run (`./chpass.sh demoacct --dry-run`)

```text
================================================================================
 chpass.sh v2.0.0 | cPanel Account Password Manager (whmapi1 / DRY-RUN) | 2026-11-21T06:46:40Z
================================================================================
USERNAME           PASSWORD             STATUS     MESSAGE
------------------ -------------------- ---------- ------------------------------
demoacct           k9#Lm2@pQ7xR4^vN     dry_run    Simulated via whmapi1 (mysql_sync=1, digest=0)

Summary: 1 processed | 1 ok | 0 failed
```

### Root Protection Guard (`./chpass.sh root --dry-run`)

```text
USERNAME           PASSWORD             STATUS     MESSAGE
------------------ -------------------- ---------- ------------------------------
root               -                    blocked    Refused: protected or invalid system user

Summary: 1 processed | 0 ok | 1 failed
```

---

## Author & License

Developed by **Percio Castelo** ([perciocastelo.com.br](https://perciocastelo.com.br)).
Inspired by `chpass` (`ecpp_2.pl`, 2012, **Michael Karr** / HostGator Toolbox).

Licensed under the [Apache License 2.0](LICENSE).
