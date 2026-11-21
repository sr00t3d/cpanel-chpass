#!/usr/bin/env bash
# ==============================================================================
#  chpass.sh — Safe cPanel/WHM Account Password Changer & Rotator CLI
# ==============================================================================
#  Author  : Percio Castelo <percio@perciocastelo.com.br>
#  Website : https://perciocastelo.com.br
#  Project : https://perciocastelo.com.br/projetos/en/cpanel-chpass.html
#  Repo    : https://github.com/sr00t3d/cpanel-chpass
#  License : Apache-2.0
#  Version : 2.0.0
#  Notes   : Clean-room Bash reimplementation inspired by `chpass` (`ecpp_2.pl`,
#            2012, Michael Karr / HostGator Toolbox). Modernized to use official
#            `whmapi1 passwd` (with `/scripts/chpass` fallback), CSPRNG passwords,
#            root/system-user guard, batch/reseller rotation, dry-run, and
#            structured table/json/csv outputs.
# ==============================================================================

set -uo pipefail
export LC_ALL=C

readonly SCRIPT_NAME="chpass.sh"
readonly SCRIPT_VERSION="2.0.0"

# Defaults
USER_ARG=""
PASS_ARG=""
BATCH_FILE=""
RESELLER=""
PASS_LEN=16
ALNUM_ONLY=0
UPDATE_MYSQL=1
ENABLE_DIGEST=0
DRY_RUN=0
SAVE_FILE=""
FORMAT="table"
QUIET=0
NO_COLOR=0

TIMESTAMP_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
ENGINE=""

# Colors
RED="" GREEN="" YELLOW="" CYAN="" BOLD="" RESET=""

init_colors() {
  if [[ "$NO_COLOR" -eq 0 && -t 1 && -z "${NO_COLOR:-}" && "$FORMAT" == "table" ]]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[0;33m'
    CYAN=$'\033[0;36m'
    BOLD=$'\033[1m'
    RESET=$'\033[0m'
  else
    RED="" GREEN="" YELLOW="" CYAN="" BOLD="" RESET=""
  fi
}

show_help() {
  cat <<'USAGE'
chpass.sh v2.0.0 — Safe cPanel/WHM Account Password Changer & Rotator CLI

Usage:
  chpass.sh <username> [password] [options]
  chpass.sh -f <users.txt> [options]
  chpass.sh -r <reseller> [options]

Options:
  -f, --file <path>          Rotate passwords for users listed in file (one per line)
  -r, --reseller <user>      Rotate passwords for all accounts owned by reseller (/etc/trueuserowners)
  -l, --length <num>         Generated password length (default: 16, min: 12)
  --alnum                    Generate alphanumeric-only password (no symbols)
  --no-mysql                 Do not update the account's MySQL password (default: sync MySQL)
  --digest                   Enable Digest Authentication (WebDisk)
  --dry-run                  Simulate password changes without modifying any account
  --save <path>              Save rotated credentials to a chmod 600 file
  -o, --output <fmt>         Output format: table (default), json, csv
  -q, --quiet                Suppress banner header
  --no-color                 Disable ANSI colors
  -V, --version              Show version and exit
  -h, --help                 Show this help and exit

Security Guards:
  - Never modifies root or privileged system accounts (UID < 500 or missing /var/cpanel/users/<user>)
  - Uses CSPRNG (/dev/urandom) for automatic strong passwords when omitted
  - Writes --save output with strict chmod 600 permissions

Examples:
  chpass.sh alice
  chpass.sh alice 'Str0ng#Pass2026!'
  chpass.sh alice --dry-run -o json
  chpass.sh -r myreseller --dry-run
  chpass.sh -f compromised.txt --save /root/rotated-creds.txt
USAGE
}

is_protected_user() {
  local u="$1"
  case "$u" in
    root|nobody|cpanel|mysql|mailnull|exim|dovecot|named|sshd|apache|www-data|bin|daemon|adm|sys)
      return 0 ;;
  esac
  if [[ ! "$u" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    return 0
  fi
  local uid
  uid="$(id -u "$u" 2>/dev/null || echo "")"
  if [[ -n "$uid" && "$uid" =~ ^[0-9]+$ && "$uid" -lt 500 ]]; then
    return 0
  fi
  return 1
}

generate_password() {
  local len="$1"
  local charset='A-Za-z0-9'
  if [[ "$ALNUM_ONLY" -eq 0 ]]; then
    charset='A-Za-z0-9@#%^&*+=_-'
  fi
  local pass=""
  local tries=0
  while [[ "$tries" -lt 20 ]]; do
    tries=$((tries + 1))
    pass="$(LC_ALL=C tr -dc "$charset" </dev/urandom 2>/dev/null | head -c "$len")"
    if [[ "${#pass}" -eq "$len" && "$pass" =~ [A-Z] && "$pass" =~ [a-z] && "$pass" =~ [0-9] ]]; then
      if [[ "$ALNUM_ONLY" -eq 1 || "$pass" =~ [@#%^\&*+=_-] ]]; then
        printf '%s' "$pass"
        return 0
      fi
    fi
  done
  printf '%s' "$pass"
}

detect_engine() {
  if command -v whmapi1 >/dev/null 2>&1; then
    ENGINE="whmapi1"
  elif [[ -x /usr/local/cpanel/scripts/chpass ]]; then
    ENGINE="scripts-chpass"
  elif [[ -x /scripts/chpass ]]; then
    ENGINE="scripts-chpass"
  else
    ENGINE="none"
  fi
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

change_single_account() {
  local user="$1"
  local pass="$2"

  if is_protected_user "$user"; then
    printf 'blocked\x1fRefused: protected or invalid system user'
    return 1
  fi

  if [[ "$DRY_RUN" -eq 0 && ! -f "/var/cpanel/users/${user}" ]]; then
    printf 'error\x1fcPanel account not found (/var/cpanel/users/%s missing)' "$user"
    return 1
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'dry_run\x1fSimulated via %s (mysql_sync=%d, digest=%d)' "$ENGINE" "$UPDATE_MYSQL" "$ENABLE_DIGEST"
    return 0
  fi

  if [[ "$(id -u)" -ne 0 ]]; then
    printf 'error\x1fRoot privileges required to change cPanel account passwords'
    return 1
  fi

  local out rc=0
  if [[ "$ENGINE" == "whmapi1" ]]; then
    out="$(whmapi1 --output=json passwd "user=${user}" "password=${pass}" "enabledigest=${ENABLE_DIGEST}" "db_pass_update=${UPDATE_MYSQL}" 2>&1)" || rc=$?
    if [[ "$rc" -eq 0 ]] && printf '%s' "$out" | grep -q '"result"[[:space:]]*:[[:space:]]*1'; then
      printf 'ok\x1fPassword updated via whmapi1 (mysql_sync=%d)' "$UPDATE_MYSQL"
      return 0
    else
      local reason
      reason="$(printf '%s' "$out" | tr '\n' ' ' | sed 's/.*reason":"//;s/".*//' | cut -c1-120)"
      printf 'error\x1fwhmapi1 failed: %s' "${reason:-unknown error}"
      return 1
    fi
  elif [[ "$ENGINE" == "scripts-chpass" ]]; then
    local bin="/usr/local/cpanel/scripts/chpass"
    [[ -x "$bin" ]] || bin="/scripts/chpass"
    out="$("$bin" "$user" "$pass" 2>&1)" || rc=$?
    if [[ "$rc" -eq 0 ]]; then
      printf 'ok\x1fPassword updated via %s' "$bin"
      return 0
    else
      printf 'error\x1f%s failed: %s' "$bin" "$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-120)"
      return 1
    fi
  else
    printf 'error\x1fNeither whmapi1 nor /scripts/chpass found on this host'
    return 1
  fi
}

main() {
  [[ "$#" -eq 0 ]] && { show_help; exit 1; }

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      -h|--help)      show_help; exit 0 ;;
      -V|--version)   printf '%s %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"; exit 0 ;;
      -f|--file)      BATCH_FILE="${2:-}"; shift 2 ;;
      -r|--reseller)  RESELLER="${2:-}"; shift 2 ;;
      -l|--length)    PASS_LEN="${2:-16}"; shift 2 ;;
      --alnum)        ALNUM_ONLY=1; shift ;;
      --no-mysql)     UPDATE_MYSQL=0; shift ;;
      --digest)       ENABLE_DIGEST=1; shift ;;
      --dry-run)      DRY_RUN=1; shift ;;
      --save)         SAVE_FILE="${2:-}"; shift 2 ;;
      -o|--output)    FORMAT="${2:-table}"; shift 2 ;;
      --output=*)     FORMAT="${1#*=}"; shift ;;
      -q|--quiet)     QUIET=1; shift ;;
      --no-color)     NO_COLOR=1; shift ;;
      -*)             printf '[ERR] Unknown option: %s (use -h for help)\n' "$1" >&2; exit 1 ;;
      *)
        if [[ -z "$USER_ARG" ]]; then
          USER_ARG="$1"; shift
        elif [[ -z "$PASS_ARG" ]]; then
          PASS_ARG="$1"; shift
        else
          printf '[ERR] Unexpected argument: %s\n' "$1" >&2; exit 1
        fi ;;
    esac
  done

  if [[ ! "$PASS_LEN" =~ ^[0-9]+$ || "$PASS_LEN" -lt 12 ]]; then
    printf '[ERR] --length must be an integer >= 12 (got: %s)\n' "$PASS_LEN" >&2
    exit 1
  fi
  case "$FORMAT" in
    table|json|csv) ;;
    *) printf '[ERR] Invalid output format: %s (expected table, json, or csv)\n' "$FORMAT" >&2; exit 1 ;;
  esac

  init_colors
  detect_engine

  local -a TARGET_USERS=()
  if [[ -n "$USER_ARG" ]]; then
    TARGET_USERS+=("$USER_ARG")
  fi
  if [[ -n "$BATCH_FILE" ]]; then
    [[ -r "$BATCH_FILE" ]] || { printf '[ERR] Cannot read file: %s\n' "$BATCH_FILE" >&2; exit 1; }
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%$'\r'}"
      line="${line%%#*}"
      line="$(printf '%s' "$line" | tr -d '[:space:]')"
      [[ -n "$line" ]] && TARGET_USERS+=("$line")
    done < "$BATCH_FILE"
  fi
  if [[ -n "$RESELLER" ]]; then
    [[ -r /etc/trueuserowners ]] || { printf '[ERR] /etc/trueuserowners not found.\n' >&2; exit 1; }
    local rline ru rowner
    while IFS= read -r rline || [[ -n "$rline" ]]; do
      [[ -z "$rline" || "$rline" == \#* ]] && continue
      ru="${rline%%:*}"
      rowner="$(printf '%s' "${rline#*:}" | tr -d '[:space:]')"
      if [[ "$rowner" == "$RESELLER" ]]; then
        TARGET_USERS+=("$ru")
      fi
    done < /etc/trueuserowners
  fi

  if [[ "${#TARGET_USERS[@]}" -eq 0 ]]; then
    printf '[ERR] No target cPanel username(s) provided. Use -h for help.\n' >&2
    exit 1
  fi

  if [[ -n "$SAVE_FILE" ]]; then
    umask 077
    : > "$SAVE_FILE"
    chmod 600 "$SAVE_FILE"
  fi

  local -a RESULTS=() # user<US>password<US>status<US>message
  local ok_count=0 err_count=0
  local u p res st msg
  for u in "${TARGET_USERS[@]}"; do
    if [[ "${#TARGET_USERS[@]}" -eq 1 && -n "$PASS_ARG" ]]; then
      p="$PASS_ARG"
    else
      p="$(generate_password "$PASS_LEN")"
    fi
    res="$(change_single_account "$u" "$p")" || true
    IFS=$'\x1f' read -r st msg <<<"$res"
    if [[ "$st" == "ok" || "$st" == "dry_run" ]]; then
      ok_count=$((ok_count + 1))
      if [[ -n "$SAVE_FILE" ]]; then
        printf '%s:%s\n' "$u" "$p" >> "$SAVE_FILE"
      fi
    else
      err_count=$((err_count + 1))
      p=""
    fi
    RESULTS+=("${u}"$'\x1f'"${p}"$'\x1f'"${st}"$'\x1f'"${msg}")
  done

  case "$FORMAT" in
    json)
      printf '{\n'
      printf '  "tool": "%s",\n' "$SCRIPT_NAME"
      printf '  "version": "%s",\n' "$SCRIPT_VERSION"
      printf '  "timestamp": "%s",\n' "$TIMESTAMP_UTC"
      printf '  "engine": "%s",\n' "$ENGINE"
      printf '  "dry_run": %s,\n' "$([[ "$DRY_RUN" -eq 1 ]] && echo true || echo false)"
      printf '  "mysql_sync": %s,\n' "$([[ "$UPDATE_MYSQL" -eq 1 ]] && echo true || echo false)"
      printf '  "total": %d,\n' "${#RESULTS[@]}"
      printf '  "succeeded": %d,\n' "$ok_count"
      printf '  "failed": %d,\n' "$err_count"
      printf '  "results": [\n'
      local i=0 n="${#RESULTS[@]}" row
      for row in "${RESULTS[@]}"; do
        IFS=$'\x1f' read -r u p st msg <<<"$row"
        i=$((i + 1))
        printf '    {"username":"%s","password":"%s","status":"%s","message":"%s"}%s\n' \
          "$(json_escape "$u")" "$(json_escape "$p")" "$(json_escape "$st")" "$(json_escape "$msg")" \
          "$([[ "$i" -lt "$n" ]] && echo ',' || echo '')"
      done
      printf '  ]\n}\n'
      ;;
    csv)
      printf 'username,password,status,message\n'
      local row
      for row in "${RESULTS[@]}"; do
        IFS=$'\x1f' read -r u p st msg <<<"$row"
        printf '"%s","%s","%s","%s"\n' "$u" "$p" "$st" "$msg"
      done
      ;;
    table)
      if [[ "$QUIET" -eq 0 ]]; then
        printf '%s================================================================================%s\n' "$CYAN" "$RESET"
        printf ' %s%s v%s%s | cPanel Account Password Manager (%s%s) | %s\n' \
          "$BOLD" "$SCRIPT_NAME" "$SCRIPT_VERSION" "$RESET" "$ENGINE" \
          "$([[ "$DRY_RUN" -eq 1 ]] && echo ' / DRY-RUN' || echo '')" "$TIMESTAMP_UTC"
        printf '%s================================================================================%s\n' "$CYAN" "$RESET"
        printf '%-18s %-20s %-10s %s\n' "USERNAME" "PASSWORD" "STATUS" "MESSAGE"
        printf '%-18s %-20s %-10s %s\n' "------------------" "--------------------" "----------" "------------------------------"
      fi
      local row col
      for row in "${RESULTS[@]}"; do
        IFS=$'\x1f' read -r u p st msg <<<"$row"
        case "$st" in
          ok)      col="$GREEN" ;;
          dry_run) col="$YELLOW" ;;
          *)       col="$RED" ;;
        esac
        printf '%-18s %-20s %s%-10s%s %s\n' "$u" "${p:--}" "$col" "$st" "$RESET" "$msg"
      done
      if [[ "$QUIET" -eq 0 ]]; then
        printf '\nSummary: %d processed | %d ok | %d failed\n' "${#RESULTS[@]}" "$ok_count" "$err_count"
        [[ -n "$SAVE_FILE" ]] && printf 'Saved  : %s (chmod 600)\n' "$SAVE_FILE"
      fi
      ;;
  esac

  [[ "$err_count" -gt 0 ]] && exit 1
  exit 0
}

main "$@"
