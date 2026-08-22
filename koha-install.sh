#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║   KOHA ILS — PRODUCTION-GRADE AUTO-INSTALLER                               ║
# ║   Ubuntu 24.04.4 LTS  •  Latest Stable  •  Fully Unattended               ║
# ║   Smart Detection  •  Retry Logic  •  Full Rollback  •  Self-Test          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# ── LICENSE ───────────────────────────────────────────────────────────────────
#
#   MIT License
#
#   Copyright (c) 2026 koha-autoinstall contributors
#   https://github.com/yourusername/koha-autoinstall
#
#   Permission is hereby granted, free of charge, to any person obtaining a
#   copy of this software and associated documentation files (the "Software"),
#   to deal in the Software without restriction, including without limitation
#   the rights to use, copy, modify, merge, publish, distribute, sublicense,
#   and/or sell copies of the Software, and to permit persons to whom the
#   Software is furnished to do so, subject to the following conditions:
#
#   The above copyright notice and this permission notice shall be included in
#   all copies or substantial portions of the Software.
#
#   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
#   THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
#   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
#   DEALINGS IN THE SOFTWARE.
#
# ── PROJECT ───────────────────────────────────────────────────────────────────
#
#   Repository : https://github.com/yourusername/koha-autoinstall
#   Koha home  : https://koha-community.org
#   Report bugs: https://github.com/yourusername/koha-autoinstall/issues
#
#   Version    : 1.0.0
#   Released   : 2026-03-17
#   Maintained : yes
#
# ── USAGE ─────────────────────────────────────────────────────────────────────
#
#   sudo bash koha-install.sh
#
#   No arguments needed. All credentials and configuration are auto-generated.
#   A credentials file is saved to /root/koha-credentials-<timestamp>.txt
#   A full install log is saved to  /var/log/koha-install-<timestamp>.log
#
# ── DISCLAIMER ────────────────────────────────────────────────────────────────
#
#   This script modifies system packages, databases, and service configuration.
#   Always run on a dedicated server or VM. Review the script before running
#   on any system you care about. The authors accept no liability for data
#   loss, system damage, or security issues arising from use of this script.
#
# ─────────────────────────────────────────────────────────────────────────────
#
# PRODUCTION HARDENING:
#   [✔] Lock file          — prevents concurrent runs
#   [✔] OS version gate    — Ubuntu 22+ required, 24 recommended
#   [✔] Fatal error handler — full-screen panel + rollback on any failure
#   [✔] Signal traps       — SIGINT/SIGTERM/SIGHUP handled cleanly
#   [✔] EXIT trap          — cursor always restored, lock always removed
#   [✔] apt lock detection — waits up to 5 min for apt to free
#   [✔] Retry wrapper      — network ops retry 3x with exponential back-off
#   [✔] Per-step disk guard — checked before every heavy apt operation
#   [✔] RAM minimum guard  — 1 GB minimum enforced
#   [✔] Service verification — confirms each service is active after start
#   [✔] UFW auto-open      — ports 80 + 8080 opened if UFW is active
#   [✔] Rollback machine   — push_rollback/run_rollback unwinds on failure
#   [✔] run_live strict    — hard-fail or soft-warn per call site
#   [✔] Post-install test  — HTTP smoke test + DB auth verification
#   [✔] /root write check  — verified before credentials are written
#   [✔] Detection engine   — checks & purges each component before reinstalling
#   [✔] Live dashboard     — fixed header + dual progress bars + scrolling feed
# ══════════════════════════════════════════════════════════════════════════════

# ── Deliberately NOT using set -e here; we handle every error explicitly ─────
# set -e causes (( expr )) returning 0 to kill the script, among other traps.
# Instead we use || fatal / || true at every call site.
set -uo pipefail

[[ $EUID -ne 0 ]] && { echo "Run as root: sudo bash $0"; exit 1; }

# ══════════════════════════════════════════════════════════════════════════════
# LOCK FILE
# ══════════════════════════════════════════════════════════════════════════════
LOCK_FILE="/var/run/koha-installer.lock"
if [[ -f "$LOCK_FILE" ]]; then
    OLD_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
        echo "ERROR: Another install is already running (PID ${OLD_PID})."
        echo "       If stale: sudo rm -f ${LOCK_FILE}"
        exit 1
    fi
    rm -f "$LOCK_FILE"
fi
echo $$ > "$LOCK_FILE"

# ══════════════════════════════════════════════════════════════════════════════
# ANSI PALETTE
# ══════════════════════════════════════════════════════════════════════════════
E=$'\033'
R="${E}[0m"  BD="${E}[1m"  DM="${E}[2m"
F1="${E}[91m" F2="${E}[92m" F3="${E}[93m" F4="${E}[94m"
F5="${E}[95m" F6="${E}[96m" F7="${E}[97m" F8="${E}[90m"
N2="${E}[32m" N3="${E}[33m" N7="${E}[37m"  BK="${E}[30m"
BG2="${E}[102m" BG3="${E}[103m" BG4="${E}[104m" BG5="${E}[105m" BG6="${E}[106m"
HC="${E}[?25l" SC="${E}[?25h" CL="${E}[2K" ED="${E}[J" CR=$'\r'

TW=$(tput cols  2>/dev/null || echo 80); [[ $TW -lt 80 ]] && TW=80
TH=$(tput lines 2>/dev/null || echo 24); [[ $TH -lt 20 ]] && TH=24

# ══════════════════════════════════════════════════════════════════════════════
# LOGGING — fd3 = real terminal for UI; stdout/stderr → log file
# ══════════════════════════════════════════════════════════════════════════════
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG="/var/log/koha-install-${TIMESTAMP}.log"
exec 3>&1
exec >>"$LOG" 2>&1

ui()  { printf '%b\n' "$*" >&3; }
uinl(){ printf '%b'   "$*" >&3; }
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

# Typewriter effect — defined at top level so fd3 is in scope
typewrite(){
    local text="$1" colour="${2:-$F6}" delay="${3:-0.016}"
    printf "  %b" "$colour" >&3
    local i=0
    while [[ $i -lt ${#text} ]]; do
        printf '%s' "${text:$i:1}" >&3
        sleep "$delay" 2>/dev/null || true
        i=$(( i + 1 ))
    done
    printf '%b\n' "$R" >&3
}

# ══════════════════════════════════════════════════════════════════════════════
# DRAWING HELPERS
# ══════════════════════════════════════════════════════════════════════════════
rep(){ printf '%*s' "$2" '' | tr ' ' "$1"; }

strip_ansi(){
    # Strip ANSI escape sequences — pure bash, no subshell
    local s="$1" out="" i=0 ch
    while [[ $i -lt ${#s} ]]; do
        ch="${s:$i:1}"
        if [[ "$ch" == $'\033' ]]; then
            i=$(( i + 1 ))
            # skip until end of escape sequence
            while [[ $i -lt ${#s} ]]; do
                ch="${s:$i:1}"
                i=$(( i + 1 ))
                [[ "$ch" =~ [A-Za-z] ]] && break
            done
        else
            out+="$ch"
            i=$(( i + 1 ))
        fi
    done
    printf '%s' "$out"
}

centre(){
    local raw; raw=$(strip_ansi "$1")
    local len=${#raw}
    local pad=$(( (TW - len) / 2 ))
    [[ $pad -lt 0 ]] && pad=0
    ui "$(rep ' ' $pad)${1}"
}
hline(){ ui "${1}$(rep "${3:-─}" $TW)${R}"; }

BX="${F6}"
box_top()  { ui "${BX}╔$(rep '═' $((TW-2)))╗${R}"; }
box_bot()  { ui "${BX}╚$(rep '═' $((TW-2)))╝${R}"; }
box_mid()  { ui "${BX}╠$(rep '═' $((TW-2)))╣${R}"; }
box_blank(){ ui "${BX}║$(rep ' ' $((TW-2)))║${R}"; }
box_line(){
    local text="$1"
    local raw; raw=$(strip_ansi "$text")
    local len=${#raw}
    local pad=$(( TW - len - 4 ))
    [[ $pad -lt 0 ]] && pad=0
    ui "${BX}║${R} ${text}$(rep ' ' $pad) ${BX}║${R}"
}

tag_ok()    { ui "  ${BG2}${BK}  OK   ${R} ${N2}${1}${R}"; }
tag_info()  { ui "  ${BG4}${BK}  INFO ${R} ${F6}${1}${R}"; }
tag_warn()  { ui "  ${BG3}${BK}  WARN ${R} ${N3}${1}${R}"; }
tag_err()   { ui "  ${E}[101m${BK}  ERR  ${R} ${F1}${1}${R}"; }
tag_purge() { ui "  ${BG5}${BK}  PURGE${R} ${F5}${1}${R}"; }
tag_retry() { ui "  ${BG3}${BK}  RETRY${R} ${F3}${1}${R}"; }

# ══════════════════════════════════════════════════════════════════════════════
# LIVE DASHBOARD — fixed header + scrolling feed
# ══════════════════════════════════════════════════════════════════════════════
HEADER_LINES=11
FEED_LINES=$(( TH - HEADER_LINES - 1 ))
[[ $FEED_LINES -lt 5 ]] && FEED_LINES=5
FEED_BUF=()   # plain array — no declare -a needed

draw_header(){
    printf "${E}[1;1H" >&3
    printf "${F6}$(rep '═' $TW)${R}\n" >&3
    local title=" KOHA ILS AUTO-INSTALLER  •  Ubuntu 24.04.4 LTS  •  $(date '+%H:%M:%S') "
    local tlen=${#title}
    local tpad=$(( (TW - tlen) / 2 ))
    [[ $tpad -lt 0 ]] && tpad=0
    printf "%s${BD}${F7}%s${R}\n" "$(rep ' ' $tpad)" "$title" >&3
    printf "${F6}$(rep '═' $TW)${R}\n" >&3

    # Overall progress bar
    local pct=0 bw=$(( TW - 20 ))
    local filled=0 empty=$bw
    if [[ $PROG_TOTAL -gt 0 ]]; then
        pct=$(( STEP_NUM * 100 / PROG_TOTAL ))
        filled=$(( STEP_NUM * bw / PROG_TOTAL ))
        empty=$(( bw - filled ))
    fi
    local bc="$F1"
    [[ $pct -ge 34 ]] && bc="$F3"
    [[ $pct -ge 67 ]] && bc="$F2"
    printf "  ${bc}$(rep '█' $filled)${F8}$(rep '░' $empty)${R}  ${BD}${F3}%3d%%${R}  ${DM}step %d/%d${R}\n" \
        "$pct" "$STEP_NUM" "$PROG_TOTAL" >&3

    # Spinner + step label
    local sf="${SPIN_FRAMES[$SPIN_IDX]}"
    local label_w=$(( TW - 18 ))
    printf "  ${F6}%s${R}  ${BD}${F3}[%d/%d]${R}  ${BD}${F7}%-${label_w}s${R}\n" \
        "$sf" "$STEP_NUM" "$PROG_TOTAL" "${CURRENT_STEP_LABEL:- }" >&3

    # Sub-step bar
    local sbw=$(( TW - 20 )) sfilled=0 sempty=$sbw
    if [[ $SUB_TOTAL -gt 0 ]]; then
        sfilled=$(( SUB_STEP * sbw / SUB_TOTAL ))
        sempty=$(( sbw - sfilled ))
    fi
    local sub_lbl="${CURRENT_SUBSTEP:- }"
    printf "  ${F5}$(rep '▪' $sfilled)${F8}$(rep '·' $sempty)${R}  ${DM}%-20s${R}\n" \
        "$sub_lbl" >&3

    # Detection/status row
    local drow="${DETECT_STATUS:- }"
    printf "  ${DM}%-$(( TW - 2 ))s${R}\n" "$drow" >&3

    # Stats row
    local el=$(( $(date +%s) - START_TS ))
    printf "  ${DM}Elapsed: %02d:%02d  •  Pkgs: %d  •  Purged: %d  •  Retries: %d  •  Log: %s${R}\n" \
        "$(( el / 60 ))" "$(( el % 60 ))" \
        "$PKG_COUNT" "$PURGE_COUNT" "$RETRY_COUNT" "$LOG" >&3

    # Feed header
    printf "${F8}$(rep '─' $TW)${R}\n" >&3
    local fhdr_pad=$(( TW - 38 ))
    [[ $fhdr_pad -lt 0 ]] && fhdr_pad=0
    printf "  ${BD}${F4}▼  Live Activity Feed${R}  ${DM}(real-time output)${R}%s\n" \
        "$(rep ' ' $fhdr_pad)" >&3
    printf "${F8}$(rep '─' $TW)${R}\n" >&3
}

redraw_feed(){
    printf "${E}[$((HEADER_LINES+1));1H${ED}" >&3
    local count=${#FEED_BUF[@]}
    local start=0
    [[ $count -gt $FEED_LINES ]] && start=$(( count - FEED_LINES ))
    local i=$start
    while [[ $i -lt $count ]]; do
        printf '%b\n' "${FEED_BUF[$i]}" >&3
        i=$(( i + 1 ))   # arithmetic — safe, never returns non-zero this way
    done
}

feed_line(){
    local text="$1"
    local raw; raw=$(strip_ansi "$text")
    local rlen=${#raw}
    if [[ $rlen -gt $(( TW - 4 )) ]]; then
        text="${text:0:$(( TW - 7 ))}${DM}...${R}"
    fi
    FEED_BUF+=("  ${text}")
    draw_header
    redraw_feed
}
feed_sep(){ feed_line "${F8}$(rep '·' $(( TW - 4 )))${R}"; }

# ══════════════════════════════════════════════════════════════════════════════
# SPINNER
# ══════════════════════════════════════════════════════════════════════════════
SPIN_FRAMES=('⣾' '⣽' '⣻' '⢿' '⡿' '⣟' '⣯' '⣷')
SPIN_IDX=0
SPIN_PID=0

spinner_start(){
    (
        local idx=0
        while true; do
            idx=$(( (idx + 1) % 8 ))
            SPIN_IDX=$idx
            draw_header
            sleep 0.1
        done
    ) &
    SPIN_PID=$!
    disown "$SPIN_PID" 2>/dev/null || true
}

spinner_stop(){
    if [[ $SPIN_PID -ne 0 ]]; then
        kill "$SPIN_PID" 2>/dev/null || true
        wait "$SPIN_PID" 2>/dev/null || true
        SPIN_PID=0
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
# GLOBAL STATE
# ══════════════════════════════════════════════════════════════════════════════
CURRENT_STEP_LABEL=""
CURRENT_SUBSTEP=""
DETECT_STATUS=""
SUB_STEP=0
SUB_TOTAL=1
PKG_COUNT=0
PURGE_COUNT=0
RETRY_COUNT=0
START_TS=$(date +%s)
STEP_NUM=0
PROG_TOTAL=14        # 13 install steps + 1 smoke-test step

INSTANCE=""
MARIADB_ROOT_PASS=""
KOHA_DB_PASS=""
KOHA_VER=""
MARIA_VER=""
APACHE_VER=""
CRED_FILE=""
SERVER_IP=""
UBUNTU_VER=""
STAFF_CODE="000"
OPAC_CODE="000"
SMOKE_FAIL=0

ROLLBACK_STACK=()
ROLLBACK_RUNNING=0
INSTALL_SUCCEEDED=0
FAILED_STEP=""
FAILED_CMD=""

# ══════════════════════════════════════════════════════════════════════════════
# FATAL ERROR HANDLER + ROLLBACK
# ══════════════════════════════════════════════════════════════════════════════
fatal(){
    FAILED_STEP="${1:-unknown step}"
    FAILED_CMD="${2:-}"
    log "FATAL: step='${FAILED_STEP}' cmd='${FAILED_CMD}'"
    handle_fatal
}

handle_fatal(){
    # Guard against recursion
    if [[ $ROLLBACK_RUNNING -eq 1 ]]; then
        printf "${SC}" >&3 2>/dev/null || true
        rm -f "$LOCK_FILE" 2>/dev/null || true
        exit 1
    fi
    ROLLBACK_RUNNING=1
    spinner_stop

    printf "${SC}" >&3 2>/dev/null || true
    clear >&3 2>/dev/null || true

    hline "${F1}" "═"
    printf "${E}[101m${BK}$(rep ' ' $TW)${R}\n" >&3
    centre "${E}[101m${BK}${BD}   ✘   INSTALLATION FAILED   ${R}"
    printf "${E}[101m${BK}$(rep ' ' $TW)${R}\n" >&3
    hline "${F1}" "═"
    ui ""
    ui "  ${F1}${BD}Failed at:${R}  ${F7}${FAILED_STEP}${R}"
    [[ -n "$FAILED_CMD" ]] && ui "  ${F1}${BD}Command:${R}   ${DM}${FAILED_CMD}${R}"
    ui ""
    ui "  ${F3}Attempting rollback of completed steps...${R}"
    ui "  ${DM}Full log: ${LOG}${R}"
    ui ""
    hline "${F8}" "─"
    ui ""

    run_rollback

    ui ""
    hline "${F1}" "─"
    ui "  ${F3}Rollback complete. Review the log:${R}"
    ui "  ${BD}${F7}  sudo cat ${LOG}${R}"
    ui ""
    ui "  ${DM}Last 15 log lines:${R}"
    while IFS= read -r line; do
        ui "  ${F8}${line}${R}"
    done < <(tail -15 "$LOG" 2>/dev/null)
    ui ""
    hline "${F1}" "═"

    INSTALL_SUCCEEDED=99   # sentinel — tell EXIT trap not to call us again
    rm -f "$LOCK_FILE" 2>/dev/null || true
    exit 1
}

# ── Signal traps ──────────────────────────────────────────────────────────────
handle_signal(){
    FAILED_STEP="User interrupt (signal: $1)"
    FAILED_CMD=""
    log "Signal $1 received"
    handle_fatal
}
trap 'handle_signal INT'  INT
trap 'handle_signal TERM' TERM
trap 'handle_signal HUP'  HUP

# EXIT trap — fires on every exit; only calls handle_fatal when unexpected
trap '_ec=$?
    spinner_stop
    printf "${SC}" >&3 2>/dev/null || true
    rm -f "$LOCK_FILE" 2>/dev/null || true
    if [[ $INSTALL_SUCCEEDED -eq 0 && $ROLLBACK_RUNNING -eq 0 && $_ec -ne 0 ]]; then
        [[ -z "$FAILED_STEP" ]] && FAILED_STEP="Unexpected error (exit code $_ec)"
        handle_fatal
    fi
' EXIT

# ══════════════════════════════════════════════════════════════════════════════
# ROLLBACK STATE MACHINE
# ══════════════════════════════════════════════════════════════════════════════
push_rollback(){ ROLLBACK_STACK+=("$1"); log "ROLLBACK_STACK push: $1"; }

run_rollback(){
    local stack_size=${#ROLLBACK_STACK[@]}
    if [[ $stack_size -eq 0 ]]; then
        ui "  ${DM}Nothing to roll back.${R}"
        return 0
    fi

    ui "  ${F5}Rolling back ${stack_size} step(s)...${R}"
    ui ""
    local i=$(( stack_size - 1 ))
    while [[ $i -ge 0 ]]; do
        local step="${ROLLBACK_STACK[$i]}"
        ui "  ${F5}↩${R}  ${DM}Rolling back: ${step}${R}"
        log "ROLLBACK: $step"
        case "$step" in
            memcached)
                systemctl stop memcached 2>/dev/null || true
                DEBIAN_FRONTEND=noninteractive apt-get purge -yq memcached 2>/dev/null || true
                ;;
            koha_instance)
                a2dissite "$INSTANCE" 2>/dev/null || true
                koha-stop "$INSTANCE" 2>/dev/null || true
                koha-remove "$INSTANCE" 2>/dev/null || true
                rm -rf "/etc/koha/sites/${INSTANCE}" 2>/dev/null || true
                ;;
            koha_db)
                mysql -u root -p"${MARIADB_ROOT_PASS}" 2>/dev/null <<SQL || true
DROP DATABASE IF EXISTS koha_${INSTANCE};
DROP USER IF EXISTS 'koha_${INSTANCE}'@'localhost';
FLUSH PRIVILEGES;
SQL
                ;;
            koha_common)
                DEBIAN_FRONTEND=noninteractive apt-get purge -yq koha-common 2>/dev/null || true
                rm -rf /etc/koha 2>/dev/null || true
                ;;
            koha_repo)
                rm -f /etc/apt/sources.list.d/koha.list \
                       /usr/share/keyrings/koha-keyring.gpg 2>/dev/null || true
                apt-get update -q 2>/dev/null || true
                ;;
            apache)
                systemctl stop apache2 2>/dev/null || true
                DEBIAN_FRONTEND=noninteractive apt-get purge -yq apache2 apache2-bin apache2-data 2>/dev/null || true
                ;;
            mariadb)
                systemctl stop mariadb 2>/dev/null || true
                DEBIAN_FRONTEND=noninteractive apt-get purge -yq \
                    mariadb-server mariadb-client mariadb-common 2>/dev/null || true
                rm -rf /var/lib/mysql /etc/mysql 2>/dev/null || true
                ;;
        esac
        ui "  ${F8}  ✔ rolled back: ${step}${R}"
        i=$(( i - 1 ))
    done
    DEBIAN_FRONTEND=noninteractive apt-get autoremove -yq 2>/dev/null || true
    ui ""
    ui "  ${F5}Rollback finished.${R}"
}

# ══════════════════════════════════════════════════════════════════════════════
# APT LOCK GUARD
# ══════════════════════════════════════════════════════════════════════════════
wait_for_apt(){
    local waited=0 max=300
    while fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock \
                /var/cache/apt/archives/lock /var/lib/dpkg/lock \
                >/dev/null 2>&1; do
        if [[ $waited -eq 0 ]]; then
            feed_line "${F3}⏳${R}  apt is locked by another process — waiting (max 5 min)..."
            log "apt lock detected, waiting..."
        fi
        sleep 5
        waited=$(( waited + 5 ))
        if [[ $waited -ge $max ]]; then
            fatal "apt lock" "apt lock not released after ${max}s"
        fi
    done
    [[ $waited -gt 0 ]] && feed_line "${F2}✔${R}  apt lock released after ${waited}s"
}

# ══════════════════════════════════════════════════════════════════════════════
# DISK SPACE GUARD — call before heavy apt operations
# ══════════════════════════════════════════════════════════════════════════════
require_disk_gb(){
    local required="${1:-2}"
    local free_gb
    free_gb=$(df -BG / | awk 'NR==2{gsub("G","",$4);print $4}')
    if [[ $free_gb -lt $required ]]; then
        fatal "Disk space" "Need ${required} GB on /, only ${free_gb} GB available"
    fi
    feed_line "${F2}✔${R}  ${DM}Disk: ${free_gb} GB free (${required} GB required)${R}"
}

# ══════════════════════════════════════════════════════════════════════════════
# RETRY WRAPPER — retry a command up to N times with exponential back-off
# Usage: with_retry <attempts> <initial_delay_sec> <desc> <cmd> [args...]
# ══════════════════════════════════════════════════════════════════════════════
with_retry(){
    local max="$1" delay="$2" desc="$3"
    shift 3
    local attempt=1 ec=0
    while [[ $attempt -le $max ]]; do
        ec=0
        "$@" 2>&1 || ec=$?
        if [[ $ec -eq 0 ]]; then
            return 0
        fi
        if [[ $attempt -lt $max ]]; then
            RETRY_COUNT=$(( RETRY_COUNT + 1 ))
            tag_retry "Attempt ${attempt}/${max} failed for '${desc}' — retrying in ${delay}s..."
            log "RETRY ${attempt}/${max}: ${desc} (exit ${ec})"
            sleep "$delay"
            delay=$(( delay * 2 ))
        fi
        attempt=$(( attempt + 1 ))
    done
    fatal "$desc" "$*"
}

# ══════════════════════════════════════════════════════════════════════════════
# SERVICE HEALTH CHECK
# ══════════════════════════════════════════════════════════════════════════════
verify_service(){
    local svc="$1"
    local attempts=0
    while [[ $attempts -lt 12 ]]; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            feed_line "${F2}✔${R}  ${DM}Service verified active: ${svc}${R}"
            return 0
        fi
        sleep 1
        attempts=$(( attempts + 1 ))
    done
    fatal "Service start" "${svc} not active after 12s ($(systemctl is-active "$svc" 2>/dev/null || echo unknown))"
}

# ══════════════════════════════════════════════════════════════════════════════
# run_live — stream a command's output into the live feed
#   $1 = human description
#   $2 = 0 (hard-fail on error) | 1 (soft-warn on error)
#   $3... = command + args
# ══════════════════════════════════════════════════════════════════════════════
run_live(){
    local desc="$1" soft="$2"
    shift 2
    CURRENT_SUBSTEP="$desc"
    SUB_STEP=$(( SUB_STEP + 1 ))
    feed_line "${F3}▶${R} ${BD}${F7}${desc}${R}"
    log "RUN(soft=${soft}): $*"

    local exit_code=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        local dline="$line"
        case "$line" in
            *"Unpacking "*)
                dline="${F5}${line}${R}"
                PKG_COUNT=$(( PKG_COUNT + 1 ))
                ;;
            *"Purging "*)
                dline="${F5}${line}${R}"
                PURGE_COUNT=$(( PURGE_COUNT + 1 ))
                ;;
            *"Removing "*)
                dline="${F1}${line}${R}"
                PURGE_COUNT=$(( PURGE_COUNT + 1 ))
                ;;
            *"Setting up "*) dline="${F2}${line}${R}";;
            *"Get:"*|*"Fetched"*|*"Download"*) dline="${F6}${line}${R}";;
            *"WARNING"*|*"warning"*) dline="${F3}${line}${R}";;
            *"ERROR"*|*"error"*|*"failed"*) dline="${F1}${line}${R}";;
            *"Processing"*|*"Preparing"*) dline="${F4}${line}${R}";;
            *"Reading"*|*"Building"*|*"Calculating"*) dline="${DM}${line}${R}";;
            *) dline="${F8}${line}${R}";;
        esac
        feed_line "$dline"
        log "$line"
    done < <("$@" 2>&1) || exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        if [[ $soft -eq 1 ]]; then
            feed_line "${F3}⚠ Non-fatal: '${desc}' exited ${exit_code}${R}"
            log "SOFT-FAIL (exit $exit_code): $*"
        else
            feed_line "${F1}✘ Command failed (exit ${exit_code}): ${desc}${R}"
            log "HARD-FAIL (exit $exit_code): $*"
            fatal "$desc" "$*"
        fi
    else
        feed_line "${F2}✔ ${desc}${R}"
    fi
    return $exit_code
}

# Convenience wrappers
run_hard(){ run_live "$1" 0 "${@:2}"; }
run_soft(){ run_live "$1" 1 "${@:2}"; }

# ══════════════════════════════════════════════════════════════════════════════
# STEP / STEP_DONE
# ══════════════════════════════════════════════════════════════════════════════
step(){
    STEP_NUM=$(( STEP_NUM + 1 ))
    CURRENT_STEP_LABEL="$1"
    SUB_STEP=0
    SUB_TOTAL="${2:-4}"
    CURRENT_SUBSTEP="Starting..."
    log "═══ STEP $STEP_NUM/$PROG_TOTAL: $1 ═══"
    feed_line ""
    feed_line "${F6}$(rep '─' $(( TW - 4 )))${R}"
    feed_line "  ${F6}◆${R}  ${BD}${F3}[${STEP_NUM}/${PROG_TOTAL}]${R}  ${BD}${F7}${1}${R}"
    feed_line "${F6}$(rep '─' $(( TW - 4 )))${R}"
    spinner_start
}

step_done(){
    spinner_stop
    CURRENT_SUBSTEP="Complete ✔"
    SUB_STEP=$SUB_TOTAL
    feed_line "  ${F2}✔${R}  ${N2}Step ${STEP_NUM} complete${R}"
    draw_header
    log "STEP $STEP_NUM complete"
}

step_warn(){ feed_line "  ${F3}⚠${R}  ${N3}${1}${R}"; log "WARN: $1"; }

# ══════════════════════════════════════════════════════════════════════════════
# DETECTION ENGINE
# ══════════════════════════════════════════════════════════════════════════════
declare -A DETECT_RESULTS=()

detect_mariadb(){
    if dpkg -l mariadb-server 2>/dev/null | grep -q '^ii'; then
        DETECT_RESULTS[mariadb]="found"
    else
        DETECT_RESULTS[mariadb]="clean"
    fi
}
detect_apache(){
    if dpkg -l apache2 2>/dev/null | grep -q '^ii'; then
        DETECT_RESULTS[apache]="found"
    else
        DETECT_RESULTS[apache]="clean"
    fi
}
detect_koha_repo(){
    if [[ -f /etc/apt/sources.list.d/koha.list ]]; then
        DETECT_RESULTS[koha_repo]="found"
    else
        DETECT_RESULTS[koha_repo]="clean"
    fi
}
detect_koha_common(){
    if dpkg -l koha-common 2>/dev/null | grep -q '^ii'; then
        DETECT_RESULTS[koha_common]="found"
    else
        DETECT_RESULTS[koha_common]="clean"
    fi
}
detect_koha_instance(){
    if [[ -d "/etc/koha/sites/${INSTANCE}" ]]; then
        DETECT_RESULTS[koha_instance]="found"
    else
        DETECT_RESULTS[koha_instance]="clean"
    fi
}
detect_koha_db(){
    if mysql -u root -p"${MARIADB_ROOT_PASS}" -e "SHOW DATABASES;" 2>/dev/null \
            | grep -q "koha_${INSTANCE}"; then
        DETECT_RESULTS[koha_db]="found"
    else
        DETECT_RESULTS[koha_db]="clean"
    fi
}
detect_memcached(){
    if dpkg -l memcached 2>/dev/null | grep -q '^ii'; then
        DETECT_RESULTS[memcached]="found"
    else
        DETECT_RESULTS[memcached]="clean"
    fi
}

det_row(){
    local label="$1" key="$2"
    local status="${DETECT_RESULTS[$key]:-unknown}"
    local icon col msg
    case "$status" in
        clean) icon="✔"; col="$F2"; msg="not installed — fresh install";;
        found) icon="↻"; col="$F3"; msg="already installed — will purge & reinstall";;
        *)     icon="?"; col="$F8"; msg="unknown";;
    esac
    local llen=${#label}
    local lpad=$(( 22 - llen ))
    [[ $lpad -lt 0 ]] && lpad=0
    ui "    ${F8}│${R}  ${col}${icon}${R}  ${F7}${label}$(rep ' ' $lpad)${R}  ${F8}│${R}  ${col}${msg}${R}"
}

# ══════════════════════════════════════════════════════════════════════════════
# PURGE HELPERS
# ══════════════════════════════════════════════════════════════════════════════
purge_mariadb(){
    DETECT_STATUS="Purging MariaDB..."
    feed_line "${F5}◉  PURGE${R}  ${BD}Stopping and removing MariaDB completely${R}"
    run_soft "Stopping MariaDB"         bash -c 'systemctl stop mariadb 2>/dev/null || true'
    run_soft "Purging MariaDB packages" bash -c 'DEBIAN_FRONTEND=noninteractive apt-get purge -yq mariadb-server mariadb-client mariadb-common mariadb-server-core* libmariadbd* 2>/dev/null || true'
    run_soft "Removing MariaDB data"    bash -c 'rm -rf /var/lib/mysql /etc/mysql /var/log/mysql 2>/dev/null || true'
    run_soft "Autoremove"               bash -c 'DEBIAN_FRONTEND=noninteractive apt-get autoremove -yq 2>/dev/null || true'
    tag_purge "MariaDB fully removed"
    log "MariaDB purged"
}
purge_apache(){
    DETECT_STATUS="Purging Apache2..."
    feed_line "${F5}◉  PURGE${R}  ${BD}Stopping and removing Apache2 completely${R}"
    run_soft "Stopping Apache2"          bash -c 'systemctl stop apache2 2>/dev/null || true'
    run_soft "Purging Apache2 packages"  bash -c 'DEBIAN_FRONTEND=noninteractive apt-get purge -yq apache2 apache2-bin apache2-data apache2-utils 2>/dev/null || true'
    run_soft "Removing Apache2 configs"  bash -c 'rm -rf /etc/apache2 /var/log/apache2 /var/www/html 2>/dev/null || true'
    run_soft "Autoremove"                bash -c 'DEBIAN_FRONTEND=noninteractive apt-get autoremove -yq 2>/dev/null || true'
    tag_purge "Apache2 fully removed"
    log "Apache2 purged"
}
purge_koha_repo(){
    DETECT_STATUS="Removing old Koha repo..."
    feed_line "${F5}◉  PURGE${R}  ${BD}Removing old Koha apt repository${R}"
    run_soft "Removing Koha repo files"  bash -c 'rm -f /etc/apt/sources.list.d/koha.list /usr/share/keyrings/koha-keyring.gpg 2>/dev/null || true'
    run_soft "Refreshing apt index"      apt-get update -q
    tag_purge "Koha repository removed"
    log "Koha repo removed"
}
purge_koha_instance(){
    DETECT_STATUS="Removing Koha instance..."
    feed_line "${F5}◉  PURGE${R}  ${BD}Removing Koha instance: ${INSTANCE}${R}"
    run_soft "Disabling Apache site"     bash -c "a2dissite ${INSTANCE} 2>/dev/null || true"
    run_soft "Stopping Koha services"    bash -c "koha-stop ${INSTANCE} 2>/dev/null || true"
    run_soft "Removing Koha instance"    bash -c "koha-remove ${INSTANCE} 2>/dev/null || true"
    run_soft "Removing instance dir"     bash -c "rm -rf /etc/koha/sites/${INSTANCE} 2>/dev/null || true"
    tag_purge "Koha instance '${INSTANCE}' removed"
    log "Koha instance purged"
}
purge_koha_db(){
    DETECT_STATUS="Dropping Koha database..."
    feed_line "${F5}◉  PURGE${R}  ${BD}Dropping koha_${INSTANCE} database and user${R}"
    mysql -u root -p"${MARIADB_ROOT_PASS}" 2>/dev/null <<SQL || true
DROP DATABASE IF EXISTS koha_${INSTANCE};
DROP USER IF EXISTS 'koha_${INSTANCE}'@'localhost';
FLUSH PRIVILEGES;
SQL
    feed_line "${F2}✔ Database and user dropped${R}"
    tag_purge "Database koha_${INSTANCE} dropped"
    log "Koha DB dropped"
}
purge_koha_common(){
    DETECT_STATUS="Purging koha-common..."
    feed_line "${F5}◉  PURGE${R}  ${BD}Purging koha-common and all Koha packages${R}"
    run_soft "Stopping Koha instances"   bash -c 'for i in $(koha-list 2>/dev/null); do koha-stop "$i" 2>/dev/null || true; done; true'
    run_soft "Purging koha-common"       bash -c 'DEBIAN_FRONTEND=noninteractive apt-get purge -yq koha-common 2>/dev/null || true'
    run_soft "Removing /etc/koha"        bash -c 'rm -rf /etc/koha 2>/dev/null || true'
    run_soft "Autoremove"                bash -c 'DEBIAN_FRONTEND=noninteractive apt-get autoremove -yq 2>/dev/null || true'
    tag_purge "koha-common fully removed"
    log "koha-common purged"
}
purge_memcached(){
    DETECT_STATUS="Purging Memcached..."
    feed_line "${F5}◉  PURGE${R}  ${BD}Stopping and removing Memcached${R}"
    run_soft "Stopping Memcached"  bash -c 'systemctl stop memcached 2>/dev/null || true'
    run_soft "Purging memcached"   bash -c 'DEBIAN_FRONTEND=noninteractive apt-get purge -yq memcached 2>/dev/null || true'
    tag_purge "Memcached removed"
    log "Memcached purged"
}

# ══════════════════════════════════════════════════════════════════════════════
# SPLASH SCREEN
# ══════════════════════════════════════════════════════════════════════════════
printf "${HC}" >&3
clear >&3
ui ""
hline "${F6}" "═"
ui ""
centre "${BD}${F7}  ██╗  ██╗ ██████╗ ██╗  ██╗ █████╗${R}"
centre "${BD}${F6}  ██║ ██╔╝██╔═══██╗██║  ██║██╔══██╗${R}"
centre "${BD}${F4}  █████╔╝ ██║   ██║███████║███████║${R}"
centre "${BD}${F5}  ██╔═██╗ ██║   ██║██╔══██║██╔══██║${R}"
centre "${BD}${F1}  ██║  ██╗╚██████╔╝██║  ██║██║  ██║${R}"
centre "${DM}${F8}  ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝${R}"
ui ""
centre "${BD}${F3}Library Information System — Production Installer${R}"
centre "${DM}${N7}Ubuntu 24.04.4 LTS  •  Latest Stable  •  Fail-Safe  •  Auto-Rollback${R}"
ui ""
hline "${F6}" "═"
sleep 1

typewrite "Running production-grade pre-flight checks before anything is installed..."
sleep 0.5

# ══════════════════════════════════════════════════════════════════════════════
# PRE-FLIGHT CHECKS
# ══════════════════════════════════════════════════════════════════════════════
ui ""
ui "  ${BD}${F3}◆  Pre-flight Checks${R}"
hline "${F8}" "─"
ui ""

# 1. OS version gate
uinl "  ${F6}⣾${R}  Checking OS..."; sleep 0.3; printf "${CR}${CL}" >&3
UBUNTU_VER=$(lsb_release -ds 2>/dev/null || echo "Unknown")
UBUNTU_ID=$(lsb_release -is  2>/dev/null || echo "Unknown")
UBUNTU_REL=$(lsb_release -rs 2>/dev/null || echo "0")
UBUNTU_MAJ="${UBUNTU_REL%%.*}"

if [[ "$UBUNTU_ID" != "Ubuntu" ]]; then
    tag_err "Not Ubuntu (detected: ${UBUNTU_ID}) — this installer requires Ubuntu"
    fatal "OS check" "Not Ubuntu"
fi
if [[ "$UBUNTU_MAJ" -lt 22 ]]; then
    tag_err "Ubuntu ${UBUNTU_REL} is too old — requires 22.04+ (24.04 recommended)"
    fatal "OS check" "Ubuntu ${UBUNTU_REL} < 22"
fi
if [[ "$UBUNTU_MAJ" -ne 24 ]]; then
    tag_warn "Ubuntu ${UBUNTU_REL} — tested on 24.04; proceeding with caution"
else
    tag_ok "OS: ${UBUNTU_VER}"
fi

# 2. RAM
uinl "  ${F6}⣾${R}  Checking RAM..."; sleep 0.2; printf "${CR}${CL}" >&3
RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
if [[ $RAM_MB -lt 1024 ]]; then
    tag_err "Only ${RAM_MB} MB RAM — Koha requires at least 1 GB"
    fatal "RAM check" "${RAM_MB} MB < 1024 MB"
fi
tag_ok "RAM: ${RAM_MB} MB"

# 3. Disk space
uinl "  ${F6}⣾${R}  Checking disk..."; sleep 0.2; printf "${CR}${CL}" >&3
DISK_FREE=$(df -BG / | awk 'NR==2{gsub("G","",$4);print $4}')
if [[ $DISK_FREE -lt 5 ]]; then
    tag_err "Only ${DISK_FREE} GB free on / — need at least 5 GB"
    fatal "Disk space" "${DISK_FREE} GB < 5 GB"
fi
if [[ $DISK_FREE -lt 10 ]]; then
    tag_warn "Disk: ${DISK_FREE} GB free (10 GB+ recommended)"
else
    tag_ok "Disk: ${DISK_FREE} GB free"
fi

LOG_DISK=$(df -BM /var/log | awk 'NR==2{gsub("M","",$4);print $4}')
if [[ $LOG_DISK -lt 500 ]]; then
    tag_warn "/var/log: only ${LOG_DISK} MB free — install log may be truncated"
fi

# 4. Network
uinl "  ${F6}⣾${R}  Checking network..."; sleep 0.3; printf "${CR}${CL}" >&3
if ! ping -c1 -W8 debian.koha-community.org >/dev/null 2>&1; then
    tag_err "Cannot reach debian.koha-community.org — check network"
    fatal "Network" "No route to debian.koha-community.org"
fi
if ! ping -c1 -W5 archive.ubuntu.com >/dev/null 2>&1; then
    tag_warn "Cannot reach archive.ubuntu.com — apt upgrade may fail"
fi
tag_ok "Network: debian.koha-community.org reachable"

# 5. systemd
uinl "  ${F6}⣾${R}  Checking systemd..."; sleep 0.2; printf "${CR}${CL}" >&3
SYSD_STATE=$(systemctl is-system-running 2>/dev/null || echo "unknown")
case "$SYSD_STATE" in
    running|degraded) tag_ok "systemd: ${SYSD_STATE}";;
    *) tag_warn "systemd state: ${SYSD_STATE} — service starts may fail";;
esac

# 6. /root writable
uinl "  ${F6}⣾${R}  Checking /root writable..."; sleep 0.2; printf "${CR}${CL}" >&3
if ! touch /root/.koha_write_test 2>/dev/null; then
    tag_err "/root is not writable — credentials cannot be saved"
    fatal "Filesystem" "/root not writable"
fi
rm -f /root/.koha_write_test
tag_ok "/root is writable"
ui ""
sleep 0.5

# ══════════════════════════════════════════════════════════════════════════════
# AUTO-GENERATE VARIABLES
# ══════════════════════════════════════════════════════════════════════════════
gen_pass(){ tr -dc 'A-Za-z0-9!@#%^&*' </dev/urandom 2>/dev/null | head -c 24; }
gen_id(){   tr -dc 'a-z0-9'           </dev/urandom 2>/dev/null | head -c 8;  }

INSTANCE="koha$(gen_id)"
MARIADB_ROOT_PASS="$(gen_pass)"
KOHA_DB_PASS="$(gen_pass)"
OPAC_PORT="80"
INTRA_PORT="8080"
KOHA_CHANNEL="stable"
SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
CRED_FILE="/root/koha-credentials-${TIMESTAMP}.txt"

ui "  ${BD}${F3}◆  Auto-generated configuration${R}"; ui ""
ui "     ${F6}Instance   ${F8}│${R} ${F7}${INSTANCE}${R}"
ui "     ${F6}OPAC port  ${F8}│${R} ${F7}:${OPAC_PORT}${R}"
ui "     ${F6}Staff port ${F8}│${R} ${F7}:${INTRA_PORT}${R}"
ui "     ${F6}Channel    ${F8}│${R} ${F7}${KOHA_CHANNEL} (latest stable)${R}"
ui "     ${F6}Passwords  ${F8}│${R} ${N2}auto-generated 24-char${R}"
ui ""

install -m 600 /dev/null "$CRED_FILE"
cat > "$CRED_FILE" <<CREDS
# ═══════════════════════════════════════════════════════════
#  Koha ILS — Installation Credentials
#  Generated : $(date)
#  Log file  : $LOG
# ═══════════════════════════════════════════════════════════

[System]
server_ip      = $SERVER_IP
ubuntu_version = $UBUNTU_VER

[MariaDB]
root_password  = $MARIADB_ROOT_PASS

[Koha Database]
db_name        = koha_${INSTANCE}
db_user        = koha_${INSTANCE}
db_password    = $KOHA_DB_PASS

[Koha Instance]
instance_name  = $INSTANCE
koha_channel   = $KOHA_CHANNEL

[Staff Interface / Web Installer]
url            = http://${SERVER_IP}:${INTRA_PORT}
username       = koha_${INSTANCE}
password       = $KOHA_DB_PASS

[OPAC — Public Catalogue]
url            = http://${SERVER_IP}:${OPAC_PORT}
CREDS
tag_ok "Credentials saved → ${CRED_FILE}  (chmod 600)"
ui ""

# ══════════════════════════════════════════════════════════════════════════════
# DETECTION SCAN
# ══════════════════════════════════════════════════════════════════════════════
ui ""
hline "${F3}" "═"
centre "${BD}${F3}  SYSTEM DETECTION SCAN  ${R}"
hline "${F3}" "═"
ui ""

uinl "  ${F6}⣾${R}  Scanning..."; sleep 0.5
detect_mariadb
detect_apache
detect_koha_repo
detect_koha_common
detect_memcached
printf "${CR}${CL}" >&3

ui "    ${F8}┌──────────────────────────────────────────────────────────────────┐${R}"
ui "    ${F8}│${R}  ${BD}${F7}  Component              ${F8}│  Status${R}"
ui "    ${F8}├──────────────────────────────────────────────────────────────────┤${R}"
det_row "MariaDB Server"  "mariadb"
det_row "Apache2"         "apache"
det_row "Koha Repository" "koha_repo"
det_row "koha-common"     "koha_common"
det_row "Memcached"       "memcached"
ui "    ${F8}└──────────────────────────────────────────────────────────────────┘${R}"
ui ""

NEEDS_REINSTALL=0
for key in mariadb apache koha_repo koha_common memcached; do
    if [[ "${DETECT_RESULTS[$key]:-clean}" == "found" ]]; then
        NEEDS_REINSTALL=$(( NEEDS_REINSTALL + 1 ))
    fi
done

if [[ $NEEDS_REINSTALL -gt 0 ]]; then
    ui "  ${BG5}${BK}  ${BD}${NEEDS_REINSTALL} component(s) found — will be purged and reinstalled fresh  ${R}"
else
    ui "  ${BG2}${BK}  ${BD}Clean system — no existing components found. Fresh install.  ${R}"
fi
ui ""
sleep 1

# Switch to live dashboard mode
clear >&3
FEED_BUF=()
draw_header
redraw_feed

# ══════════════════════════════════════════════════════════════════════════════
# ══  INSTALLATION STEPS  ════════════════════════════════════════════════════
# ══════════════════════════════════════════════════════════════════════════════

# ── 1. System update ──────────────────────────────────────────────────────────
step "Updating system packages" 3
    DETECT_STATUS="Step 1: refreshing system packages"
    wait_for_apt
    require_disk_gb 1
    run_hard "Refreshing apt package index" \
        apt-get update -q
    run_hard "Upgrading existing packages" \
        bash -c 'DEBIAN_FRONTEND=noninteractive apt-get upgrade -yq'
    run_hard "Installing essential tools" \
        bash -c 'DEBIAN_FRONTEND=noninteractive apt-get install -yq curl wget gnupg2 software-properties-common apt-transport-https ca-certificates lsb-release unzip vim'
step_done
tag_ok "System packages up to date"

# ── 2. MariaDB install ────────────────────────────────────────────────────────
step "Installing MariaDB database server" 3
    if [[ "${DETECT_RESULTS[mariadb]:-clean}" == "found" ]]; then
        DETECT_STATUS="Detected: MariaDB already installed → purging"
        feed_line "${F3}⚠${R}  ${BD}${F3}MariaDB detected — purging for clean install${R}"
        feed_sep; purge_mariadb; feed_sep
    else
        feed_line "${F2}✔${R}  ${DM}MariaDB not present — clean install${R}"
    fi
    DETECT_STATUS="Installing MariaDB fresh"
    require_disk_gb 2
    wait_for_apt
    run_hard "Installing mariadb-server mariadb-client" \
        bash -c 'DEBIAN_FRONTEND=noninteractive apt-get install -yq mariadb-server mariadb-client'
    run_hard "Enabling and starting MariaDB" systemctl enable --now mariadb
    verify_service mariadb
    push_rollback "mariadb"
step_done
MARIA_VER=$(mariadb --version 2>/dev/null | awk '{print $5}' | tr -d ',')
tag_ok "MariaDB ${MARIA_VER} installed and verified"

# ── 3. Secure MariaDB ─────────────────────────────────────────────────────────
step "Securing MariaDB — setting root password" 1
    DETECT_STATUS="Step 3: securing MariaDB"
    feed_line "${F3}▶${R} Setting root password, removing anonymous users and test DB"
    mysql -u root <<SQL || fatal "MariaDB secure" "mysql -u root failed"
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MARIADB_ROOT_PASS}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQL
    feed_line "${F2}✔ SQL executed${R}"
    mysql -u root -p"${MARIADB_ROOT_PASS}" -e "SELECT 1;" >/dev/null 2>&1 \
        || fatal "MariaDB root password" "Cannot authenticate with new root password"
    feed_line "${F2}✔ Root password verified${R}"
step_done
tag_ok "Root password set and verified  •  test DB dropped"

# ── 4. Apache2 ───────────────────────────────────────────────────────────────
step "Installing Apache2 web server" 3
    if [[ "${DETECT_RESULTS[apache]:-clean}" == "found" ]]; then
        DETECT_STATUS="Detected: Apache2 → purging"
        feed_line "${F3}⚠${R}  ${BD}${F3}Apache2 detected — purging for clean install${R}"
        feed_sep; purge_apache; feed_sep
    else
        feed_line "${F2}✔${R}  ${DM}Apache2 not present — clean install${R}"
    fi
    require_disk_gb 1
    wait_for_apt
    run_hard "Installing apache2" \
        bash -c 'DEBIAN_FRONTEND=noninteractive apt-get install -yq apache2'
    run_hard "Enabling and starting Apache2" systemctl enable --now apache2
    verify_service apache2
    push_rollback "apache"
step_done
APACHE_VER=$(apache2 -v 2>/dev/null | awk '/Server version/{print $3}')
tag_ok "${APACHE_VER} installed and verified"

# ── 5. Koha repository ────────────────────────────────────────────────────────
step "Adding Koha '${KOHA_CHANNEL}' apt repository" 3
    if [[ "${DETECT_RESULTS[koha_repo]:-clean}" == "found" ]]; then
        DETECT_STATUS="Detected: Koha repo → removing and re-adding"
        feed_line "${F3}⚠${R}  ${BD}${F3}Koha repo exists — removing and re-adding fresh${R}"
        feed_sep; purge_koha_repo; feed_sep
    else
        feed_line "${F2}✔${R}  ${DM}Koha repo not present — adding fresh${R}"
    fi
    with_retry 3 5 "Download Koha GPG key" \
        bash -c 'wget -qO - https://debian.koha-community.org/koha/gpg.asc | gpg --dearmor -o /usr/share/keyrings/koha-keyring.gpg'
    feed_line "${F3}▶${R} Writing /etc/apt/sources.list.d/koha.list"
    echo "deb [signed-by=/usr/share/keyrings/koha-keyring.gpg] https://debian.koha-community.org/koha ${KOHA_CHANNEL} main" \
        > /etc/apt/sources.list.d/koha.list
    feed_line "${F2}✔ Repository file written${R}"
    with_retry 3 5 "apt-get update with Koha repo" apt-get update -q
    apt-cache show koha-common >/dev/null 2>&1 \
        || fatal "Koha repository" "koha-common not found — check network or GPG key"
    feed_line "${F2}✔ Repository verified — koha-common is available${R}"
    push_rollback "koha_repo"
step_done
tag_ok "Repo verified: debian.koha-community.org  •  channel: ${KOHA_CHANNEL}"

# ── 6. koha-common ───────────────────────────────────────────────────────────
step "Installing koha-common — largest step, please wait" 2
    if [[ "${DETECT_RESULTS[koha_common]:-clean}" == "found" ]]; then
        DETECT_STATUS="Detected: koha-common → purging"
        feed_line "${F3}⚠${R}  ${BD}${F3}koha-common detected — purging for clean install${R}"
        feed_sep; purge_koha_common; feed_sep
        if [[ ! -f /etc/apt/sources.list.d/koha.list ]]; then
            feed_line "${F3}▶${R} Re-adding Koha repo after purge..."
            echo "deb [signed-by=/usr/share/keyrings/koha-keyring.gpg] https://debian.koha-community.org/koha ${KOHA_CHANNEL} main" \
                > /etc/apt/sources.list.d/koha.list
            apt-get update -q
        fi
    else
        feed_line "${F2}✔${R}  ${DM}koha-common not present — clean install${R}"
    fi
    require_disk_gb 3
    wait_for_apt
    with_retry 2 15 "Install koha-common" \
        bash -c 'DEBIAN_FRONTEND=noninteractive apt-get install -yq koha-common'
    dpkg -l koha-common 2>/dev/null | grep -q '^ii' \
        || fatal "koha-common" "dpkg shows koha-common not properly installed after apt"
    push_rollback "koha_common"
step_done
KOHA_VER=$(dpkg -l koha-common 2>/dev/null | awk '/koha-common/{print $3}' | head -1)
tag_ok "koha-common ${KOHA_VER} installed and verified"

# ── 7. koha-sites.conf ────────────────────────────────────────────────────────
step "Configuring koha-sites.conf" 1
    DETECT_STATUS="Step 7: configuring koha-sites.conf"
    SITES_CONF="/etc/koha/koha-sites.conf"
    [[ -f "$SITES_CONF" ]] || fatal "koha-sites.conf" "File not found — koha-common install may have failed"
    cp "$SITES_CONF" "${SITES_CONF}.bak.${TIMESTAMP}"
    sc(){ sed -i "s|^${1}=.*|${1}=\"${2}\"|" "$SITES_CONF"; }
    sc INTRAPORT  "$INTRA_PORT"; sc INTRAPREFIX ""; sc INTRASUFFIX "-intra"
    sc OPACPORT   "$OPAC_PORT";  sc OPACPREFIX  ""; sc OPACSUFFIX  ""
    sc MEMCACHED_SERVERS "127.0.0.1:11211"; sc MEMCACHED_PREFIX "koha_"
    sc ZEBRA_MARC_FORMAT "marc21"; sc ZEBRA_LANGUAGE "en"
    grep -q "INTRAPORT=\"${INTRA_PORT}\"" "$SITES_CONF" \
        || fatal "koha-sites.conf" "INTRAPORT not written correctly"
    feed_line "${F2}✔ OPAC :${OPAC_PORT}  •  Staff :${INTRA_PORT}  •  MARC21/en  •  Memcached set${R}"
step_done
tag_ok "koha-sites.conf configured and verified"

# ── 8. Apache modules ─────────────────────────────────────────────────────────
step "Enabling Apache modules" 2
    DETECT_STATUS="Step 8: enabling Apache modules"
    run_hard "Enabling: rewrite cgi deflate headers proxy_http" \
        a2enmod rewrite cgi deflate headers proxy_http
    run_hard "Restarting Apache2" systemctl restart apache2
    verify_service apache2
step_done
tag_ok "Apache modules enabled"

# ── 9. Koha database & user ───────────────────────────────────────────────────
step "Creating Koha database and DB user" 2
    DETECT_STATUS="Checking for existing Koha database..."
    detect_koha_db
    if [[ "${DETECT_RESULTS[koha_db]:-clean}" == "found" ]]; then
        DETECT_STATUS="Detected: Koha DB → dropping and recreating"
        feed_line "${F3}⚠${R}  ${BD}${F3}Database koha_${INSTANCE} detected — dropping and recreating${R}"
        feed_sep; purge_koha_db; feed_sep
    else
        feed_line "${F2}✔${R}  ${DM}Database not present — creating fresh${R}"
    fi
    feed_line "${F3}▶${R} ${BD}${F7}Creating database koha_${INSTANCE} (utf8mb4)${R}"
    mysql -u root -p"${MARIADB_ROOT_PASS}" <<SQL || fatal "Koha database" "CREATE DATABASE failed"
CREATE DATABASE IF NOT EXISTS koha_${INSTANCE}
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'koha_${INSTANCE}'@'localhost'
    IDENTIFIED BY '${KOHA_DB_PASS}';
GRANT ALL PRIVILEGES ON koha_${INSTANCE}.*
    TO 'koha_${INSTANCE}'@'localhost';
FLUSH PRIVILEGES;
SQL
    mysql -u root -p"${MARIADB_ROOT_PASS}" -e "SHOW DATABASES;" 2>/dev/null \
        | grep -q "koha_${INSTANCE}" \
        || fatal "Koha database" "koha_${INSTANCE} not found after CREATE"
    mysql -u "koha_${INSTANCE}" -p"${KOHA_DB_PASS}" -e "SELECT 1;" >/dev/null 2>&1 \
        || fatal "Koha DB user" "koha_${INSTANCE} cannot authenticate"
    feed_line "${F2}✔ Database and user auth verified${R}"
    push_rollback "koha_db"
step_done
tag_ok "DB: koha_${INSTANCE}  •  user auth verified  •  utf8mb4"

# ── 10. Koha instance ────────────────────────────────────────────────────────
step "Creating Koha instance '${INSTANCE}'" 3
    DETECT_STATUS="Checking for existing Koha instance..."
    detect_koha_instance
    if [[ "${DETECT_RESULTS[koha_instance]:-clean}" == "found" ]]; then
        DETECT_STATUS="Detected: Koha instance → removing and recreating"
        feed_line "${F3}⚠${R}  ${BD}${F3}Instance '${INSTANCE}' detected — removing and recreating${R}"
        feed_sep; purge_koha_instance; feed_sep
    else
        feed_line "${F2}✔${R}  ${DM}Instance not present — creating fresh${R}"
    fi
    run_hard "Running koha-create --use-db ${INSTANCE}" \
        koha-create --use-db "$INSTANCE"
    KOHA_CONF="/etc/koha/sites/${INSTANCE}/koha-conf.xml"
    [[ -f "$KOHA_CONF" ]] \
        || fatal "Koha instance" "koha-conf.xml not created at ${KOHA_CONF}"
    sed -i "s|<pass>.*</pass>|<pass>${KOHA_DB_PASS}</pass>|" "$KOHA_CONF"
    feed_line "${F2}✔ DB password injected into koha-conf.xml${R}"
    push_rollback "koha_instance"
step_done
tag_ok "Instance '${INSTANCE}' created"

# ── 11. Apache vhost ─────────────────────────────────────────────────────────
step "Configuring Apache virtual host" 3
    DETECT_STATUS="Step 11: Apache vhost"
    if ! grep -q "Listen ${INTRA_PORT}" /etc/apache2/ports.conf 2>/dev/null; then
        sed -i "/Listen 80/a Listen ${INTRA_PORT}" /etc/apache2/ports.conf
        feed_line "${F2}✔ Added Listen ${INTRA_PORT} to ports.conf${R}"
    fi
    run_soft "Disabling default site" bash -c 'a2dissite 000-default 2>/dev/null; true'
    run_hard "Enabling Koha site: ${INSTANCE}" a2ensite "$INSTANCE"
    apache2ctl configtest 2>&1 | grep -q 'Syntax OK' \
        || fatal "Apache config" "apache2ctl configtest failed"
    feed_line "${F2}✔ Apache config syntax OK${R}"
    run_hard "Restarting Apache2 with new vhost" systemctl restart apache2
    verify_service apache2
step_done
tag_ok "VHost '${INSTANCE}' enabled  •  config syntax OK  •  Apache restarted"

# ── 12. Memcached ────────────────────────────────────────────────────────────
step "Installing Memcached cache server" 3
    if [[ "${DETECT_RESULTS[memcached]:-clean}" == "found" ]]; then
        DETECT_STATUS="Detected: Memcached → purging"
        feed_line "${F3}⚠${R}  ${BD}${F3}Memcached detected — purging for clean install${R}"
        feed_sep; purge_memcached; feed_sep
    else
        feed_line "${F2}✔${R}  ${DM}Memcached not present — clean install${R}"
    fi
    wait_for_apt
    run_hard "Installing memcached" \
        bash -c 'DEBIAN_FRONTEND=noninteractive apt-get install -yq memcached'
    run_hard "Enabling and starting Memcached" systemctl enable --now memcached
    verify_service memcached
    push_rollback "memcached"
step_done
tag_ok "Memcached verified running on 127.0.0.1:11211"

# ── 13. Perl modules + UFW + restart ─────────────────────────────────────────
step "Perl modules, firewall rules, and final service restart" 5
    DETECT_STATUS="Step 13: Perl + UFW + final restart"
    run_soft "Installing Perl dependency packages" \
        bash -c 'DEBIAN_FRONTEND=noninteractive apt-get install -yq liblocale-codes-perl libmodule-install-perl libparams-validate-perl libtest-pod-perl libdbd-mysql-perl libxml-libxml-perl libnet-z3950-zoom-perl libyaz-dev yaz 2>/dev/null || true'
    if ! perl -MLocale::Language -e 1 >/dev/null 2>&1; then
        step_warn "Locale::Language not in apt — trying cpanminus"
        run_soft "Installing cpanminus" \
            bash -c 'DEBIAN_FRONTEND=noninteractive apt-get install -yq cpanminus'
        run_soft "Installing Locale::Language via cpanm" \
            bash -c 'cpanm --notest Locale::Language 2>/dev/null || true'
    fi
    # UFW — open ports only if UFW is active
    if systemctl is-active --quiet ufw 2>/dev/null; then
        feed_line "${F3}▶${R}  UFW active — opening ports ${OPAC_PORT} and ${INTRA_PORT}"
        run_soft "UFW allow :${OPAC_PORT} (OPAC)" \
            bash -c "ufw allow ${OPAC_PORT}/tcp comment 'Koha OPAC' 2>/dev/null || true"
        run_soft "UFW allow :${INTRA_PORT} (Staff)" \
            bash -c "ufw allow ${INTRA_PORT}/tcp comment 'Koha Staff' 2>/dev/null || true"
        feed_line "${F2}✔ UFW rules added for :${OPAC_PORT} and :${INTRA_PORT}${R}"
    else
        feed_line "${DM}  UFW not active — skipping firewall rules${R}"
    fi
    run_hard "Restarting MariaDB"   systemctl restart mariadb
    verify_service mariadb
    run_hard "Restarting Apache2"   systemctl restart apache2
    verify_service apache2
    run_hard "Restarting Memcached" systemctl restart memcached
    verify_service memcached
step_done
tag_ok "All services verified running  •  firewall configured"

# ── 14. Post-install smoke test ───────────────────────────────────────────────
step "Post-install smoke test — verifying Koha responds" 3
    DETECT_STATUS="Step 14: HTTP smoke test"
    sleep 3

    # Staff
    feed_line "${F3}▶${R}  HTTP test → http://127.0.0.1:${INTRA_PORT}"
    STAFF_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 10 --max-time 20 \
        "http://127.0.0.1:${INTRA_PORT}" 2>/dev/null || echo "000")
    if [[ "$STAFF_CODE" =~ ^(200|301|302|303)$ ]]; then
        feed_line "${F2}✔ Staff interface responded: HTTP ${STAFF_CODE}${R}"
    else
        feed_line "${F3}⚠ Staff interface: HTTP ${STAFF_CODE} — may still be starting${R}"
        log "SMOKE: Staff HTTP ${STAFF_CODE}"
        SMOKE_FAIL=1
    fi

    # OPAC
    feed_line "${F3}▶${R}  HTTP test → http://127.0.0.1:${OPAC_PORT}"
    OPAC_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 10 --max-time 20 \
        "http://127.0.0.1:${OPAC_PORT}" 2>/dev/null || echo "000")
    if [[ "$OPAC_CODE" =~ ^(200|301|302|303)$ ]]; then
        feed_line "${F2}✔ OPAC responded: HTTP ${OPAC_CODE}${R}"
    else
        feed_line "${F3}⚠ OPAC: HTTP ${OPAC_CODE} — may still be starting${R}"
        log "SMOKE: OPAC HTTP ${OPAC_CODE}"
        SMOKE_FAIL=1
    fi

    # DB auth
    feed_line "${F3}▶${R}  Testing DB connection as koha_${INSTANCE}..."
    if mysql -u "koha_${INSTANCE}" -p"${KOHA_DB_PASS}" "koha_${INSTANCE}" \
            -e "SHOW TABLES;" >/dev/null 2>&1; then
        feed_line "${F2}✔ DB connection verified${R}"
    else
        feed_line "${F3}⚠ DB connection test failed (non-fatal)${R}"
        SMOKE_FAIL=1
    fi

    if [[ $SMOKE_FAIL -ne 0 ]]; then
        step_warn "Some smoke tests returned unexpected results — see log and check URLs manually"
    fi
step_done
if [[ $SMOKE_FAIL -eq 0 ]]; then
    tag_ok "All smoke tests passed — Koha is responding"
else
    tag_warn "Smoke tests had warnings — check URLs manually"
fi

# ══════════════════════════════════════════════════════════════════════════════
# SUCCESS — disarm EXIT trap
# ══════════════════════════════════════════════════════════════════════════════
INSTALL_SUCCEEDED=1

# Append smoke results + stats to credentials file
cat >> "$CRED_FILE" <<CREDS

[Smoke Test Results]
staff_http    = ${STAFF_CODE}
opac_http     = ${OPAC_CODE}
smoke_status  = $([ "$SMOKE_FAIL" -eq 0 ] && echo "PASSED" || echo "WARNINGS")

[Installation Stats]
packages_added  = ${PKG_COUNT}+
packages_purged = ${PURGE_COUNT}
retry_count     = ${RETRY_COUNT}
total_time      = $(( ($(date +%s) - START_TS) / 60 ))m$(( ($(date +%s) - START_TS) % 60 ))s
log_file        = ${LOG}
CREDS

# ══════════════════════════════════════════════════════════════════════════════
# FINAL SUMMARY SCREEN
# ══════════════════════════════════════════════════════════════════════════════
spinner_stop
printf "${E}[${TH};1H" >&3
sleep 0.3
clear >&3

hline "${F2}" "▓"
printf "${BG2}${BK}$(rep ' ' $TW)${R}\n" >&3
centre "${BG2}${BK}${BD}   ✔   KOHA INSTALLATION COMPLETE   ${R}"
printf "${BG2}${BK}$(rep ' ' $TW)${R}\n" >&3
hline "${F2}" "▓"
ui ""
sleep 0.3

box_top; box_blank
box_line "  ${BD}${F3}★  System${R}"; box_blank
box_line "  ${F6}Koha version   ${F8}│${R}  ${F7}${KOHA_VER}${R}"
box_line "  ${F6}Ubuntu         ${F8}│${R}  ${F7}${UBUNTU_VER}${R}"
box_line "  ${F6}MariaDB        ${F8}│${R}  ${F7}${MARIA_VER}${R}"
box_line "  ${F6}Apache         ${F8}│${R}  ${F7}${APACHE_VER}${R}"
box_line "  ${F6}Instance       ${F8}│${R}  ${F7}${INSTANCE}${R}"
box_line "  ${F6}Server IP      ${F8}│${R}  ${F7}${SERVER_IP}${R}"
box_line "  ${F6}Pkgs installed ${F8}│${R}  ${F7}${PKG_COUNT}+${R}"
box_line "  ${F6}Pkgs purged    ${F8}│${R}  ${F5}${PURGE_COUNT}${R}"
box_line "  ${F6}Retries        ${F8}│${R}  ${F3}${RETRY_COUNT}${R}"
box_blank; box_mid; box_blank

box_line "  ${BD}${F3}★  Detection Results${R}"; box_blank
for key in mariadb apache koha_repo koha_common memcached koha_db koha_instance; do
    status="${DETECT_RESULTS[$key]:-n/a}"
    if   [[ "$status" == "found"  ]]; then icon="${F3}↻${R}"; note="${F3}purged & reinstalled${R}"
    elif [[ "$status" == "clean"  ]]; then icon="${F2}✔${R}"; note="${DM}fresh install${R}"
    else                                   icon="${DM}—${R}"; note="${DM}checked inline${R}"; fi
    klen=${#key}
    kpad=$(( 18 - klen ))
    [[ $kpad -lt 0 ]] && kpad=0
    box_line "  ${icon}  ${F7}${key}$(rep ' ' $kpad)${R}  ${F8}│${R}  ${note}"
done
box_blank; box_mid; box_blank

box_line "  ${BD}${F3}★  Smoke Test${R}"; box_blank
if [[ "$STAFF_CODE" =~ ^(200|301|302|303)$ ]]; then
    box_line "  ${F2}✔${R}  Staff interface  ${F8}│${R}  ${F2}HTTP ${STAFF_CODE}${R}"
else
    box_line "  ${F3}⚠${R}  Staff interface  ${F8}│${R}  ${F3}HTTP ${STAFF_CODE} — check manually${R}"
fi
if [[ "$OPAC_CODE" =~ ^(200|301|302|303)$ ]]; then
    box_line "  ${F2}✔${R}  OPAC             ${F8}│${R}  ${F2}HTTP ${OPAC_CODE}${R}"
else
    box_line "  ${F3}⚠${R}  OPAC             ${F8}│${R}  ${F3}HTTP ${OPAC_CODE} — check manually${R}"
fi
box_blank; box_mid; box_blank

box_line "  ${BD}${F3}★  Access URLs${R}"; box_blank
box_line "  ${F4}Staff / Installer  ${F8}│${R}  ${BD}${F6}http://${SERVER_IP}:${INTRA_PORT}${R}"
box_line "  ${F4}OPAC (Public)      ${F8}│${R}  ${BD}${F6}http://${SERVER_IP}:${OPAC_PORT}${R}"
box_blank; box_mid; box_blank

box_line "  ${BD}${F3}★  Login Credentials${R}"; box_blank
box_line "  ${F5}Username       ${F8}│${R}  ${F7}koha_${INSTANCE}${R}"
box_line "  ${F5}Password       ${F8}│${R}  ${F7}${KOHA_DB_PASS}${R}"
box_line "  ${F5}MariaDB root   ${F8}│${R}  ${F7}${MARIADB_ROOT_PASS}${R}"
box_blank; box_mid; box_blank

box_line "  ${BD}${F3}★  Saved Files${R}"; box_blank
box_line "  ${N2}Credentials    ${F8}│${R}  ${N7}${CRED_FILE}${R}"
box_line "  ${N2}Install log    ${F8}│${R}  ${N7}${LOG}${R}"
box_blank; box_mid; box_blank

box_line "  ${BD}${F3}★  Next Steps${R}"; box_blank
box_line "  ${F7}1.${R}  Open the Staff URL in your browser"
box_line "  ${F7}2.${R}  Log in with the username and password above"
box_line "  ${F7}3.${R}  Follow the Koha web installer wizard"
box_line "  ${F7}4.${R}  Create your library branch and superlibrarian account"
box_blank
box_line "  ${DM}View credentials:  sudo cat ${CRED_FILE}${R}"
box_blank
box_bot

ui ""
ELAPSED=$(( $(date +%s) - START_TS ))
ui "${DM}  Finished: $(date)  •  Time: $(( ELAPSED/60 ))m$(( ELAPSED%60 ))s  •  Log lines: $(wc -l < "$LOG")  •  ${LOG}${R}"
ui ""
hline "${F6}" "═"
ui ""
printf "${SC}" >&3

log "COMPLETE — Koha ${KOHA_VER}  instance=${INSTANCE}  ip=${SERVER_IP}  time=$(( ELAPSED/60 ))m$(( ELAPSED%60 ))s"
rm -f "$LOCK_FILE"
