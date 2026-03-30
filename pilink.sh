#!/usr/bin/env bash
# pilink.sh — SSH pipeline for Claude Code ↔ Raspberry Pi collaboration
# Standalone tool for managing remote Pi (or any Linux host) from Windows/Mac/Linux
#
# Usage: bash pilink.sh <command> [args...]
# Config: Set PILINK_HOST env var or edit config below

set -euo pipefail

# ─── Configuration ───────────────────────────────────────────────────────────
# Override via environment: PILINK_HOST, PILINK_SERVICE, PILINK_DEPLOY_DIR
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/pilink.conf"

# Defaults
HOST="${PILINK_HOST:-pi}"
SERVICE="${PILINK_SERVICE:-}"
DEPLOY_DIR="${PILINK_DEPLOY_DIR:-}"

# Load config file if it exists
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

SSH="ssh $HOST"

# ─── Usage ───────────────────────────────────────────────────────────────────
usage() {
    cat <<'USAGE'
PiLink — SSH pipeline for Claude Code ↔ Raspberry Pi

Usage: pilink.sh <command> [args...]

  Connection
    ping                    Test SSH connectivity
    info                    System info (hostname, uptime, temp, disk, memory)

  Remote Execution
    exec "cmd"              Run command on remote host
    sudo "cmd"              Run command with sudo

  File Operations
    read /path/file         Print remote file contents
    write /path/file        Write stdin to remote file (base64-safe)
    edit /path/file "old" "new"   Sed replacement on remote file
    push local remote       SCP file to remote host
    pull remote local       SCP file from remote host
    tail /path/file [n]     Tail last n lines of a file (default 20)

  Service Management
    status                  Service + system overview
    logs [n]                Journalctl last n lines (default 50)
    restart                 Restart the configured service
    start                   Start the configured service
    stop                    Stop the configured service

  Deployment
    deploy                  Full OTA: git pull → build → restart

  Setup
    setup-key               Generate and install SSH key for passwordless access
    test-config             Validate config and connectivity

Config: Edit pilink.conf or set PILINK_HOST, PILINK_SERVICE, PILINK_DEPLOY_DIR env vars.
USAGE
    exit 1
}

# ─── Helpers ─────────────────────────────────────────────────────────────────
require_service() {
    if [[ -z "$SERVICE" ]]; then
        echo "Error: No service configured. Set SERVICE in pilink.conf or PILINK_SERVICE env var."
        exit 1
    fi
}

require_deploy_dir() {
    if [[ -z "$DEPLOY_DIR" ]]; then
        echo "Error: No deploy directory configured. Set DEPLOY_DIR in pilink.conf or PILINK_DEPLOY_DIR env var."
        exit 1
    fi
}

# ─── Commands ────────────────────────────────────────────────────────────────

cmd_ping() {
    $SSH "echo 'SSH OK — \$(hostname) — \$(date)'"
}

cmd_info() {
    $SSH bash -s <<'REMOTE'
echo "Hostname: $(hostname)"
echo "Uptime:   $(uptime -p)"
echo "Kernel:   $(uname -r)"
echo "Arch:     $(uname -m)"
if command -v vcgencmd &>/dev/null; then
    echo "Temp:     $(vcgencmd measure_temp)"
fi
echo "Memory:   $(free -h | awk '/Mem:/{print $3 "/" $2}')"
echo "Disk:     $(df -h / | awk 'NR==2{print $3 "/" $2 " (" $5 " used)"}')"
echo "Load:     $(cat /proc/loadavg | awk '{print $1, $2, $3}')"
REMOTE
}

cmd_exec() {
    [[ $# -lt 1 ]] && { echo "Usage: pilink.sh exec \"command\""; exit 1; }
    $SSH "$*"
}

cmd_sudo() {
    [[ $# -lt 1 ]] && { echo "Usage: pilink.sh sudo \"command\""; exit 1; }
    $SSH "sudo $*"
}

cmd_read() {
    [[ $# -lt 1 ]] && { echo "Usage: pilink.sh read /path/to/file"; exit 1; }
    $SSH "cat '$1'"
}

cmd_write() {
    [[ $# -lt 1 ]] && { echo "Usage: pilink.sh write /path/to/file  (reads stdin)"; exit 1; }
    local remote_path="$1"
    local encoded
    encoded=$(base64 -w0)
    $SSH "echo '$encoded' | base64 -d > '$remote_path'"
}

cmd_edit() {
    [[ $# -lt 3 ]] && { echo "Usage: pilink.sh edit /path/to/file \"old\" \"new\""; exit 1; }
    local file="$1"
    local old="$2"
    local new="$3"
    local old_escaped new_escaped
    old_escaped=$(printf '%s\n' "$old" | sed 's/[&/\]/\\&/g; s/$/\\/' | sed '$ s/\\$//')
    new_escaped=$(printf '%s\n' "$new" | sed 's/[&/\]/\\&/g; s/$/\\/' | sed '$ s/\\$//')
    $SSH "sed -i 's/${old_escaped}/${new_escaped}/g' '$file'"
}

cmd_push() {
    [[ $# -lt 2 ]] && { echo "Usage: pilink.sh push local_file remote_path"; exit 1; }
    scp "$1" "${HOST}:$2"
}

cmd_pull() {
    [[ $# -lt 2 ]] && { echo "Usage: pilink.sh pull remote_path local_file"; exit 1; }
    scp "${HOST}:$1" "$2"
}

cmd_tail() {
    [[ $# -lt 1 ]] && { echo "Usage: pilink.sh tail /path/to/file [n]"; exit 1; }
    local file="$1"
    local lines="${2:-20}"
    $SSH "tail -n $lines '$file'"
}

cmd_logs() {
    require_service
    local lines="${1:-50}"
    $SSH "sudo journalctl -u $SERVICE --no-pager -n $lines"
}

cmd_status() {
    $SSH bash -s <<REMOTE
echo "=== System ==="
echo "Hostname: \$(hostname)"
echo "Uptime:   \$(uptime -p)"
if command -v vcgencmd &>/dev/null; then
    echo "Temp:     \$(vcgencmd measure_temp)"
fi
echo "Memory:   \$(free -h | awk '/Mem:/{print \$3 "/" \$2}')"
echo "Disk:     \$(df -h / | awk 'NR==2{print \$3 "/" \$2 " (" \$5 " used)"}')"
echo ""
$(if [[ -n "$SERVICE" ]]; then
    echo "echo '=== Service: $SERVICE ==='"
    echo "sudo systemctl status $SERVICE --no-pager 2>/dev/null || echo 'Service not found'"
else
    echo "echo '=== Services (no default configured) ==='"
fi)
echo ""
echo "=== Network ==="
ip -4 addr show | grep -oP 'inet \K[\d.]+/\d+' | head -5
REMOTE
}

cmd_restart() {
    require_service
    $SSH "sudo systemctl restart $SERVICE && echo 'Service restarted' && sudo systemctl status $SERVICE --no-pager"
}

cmd_start() {
    require_service
    $SSH "sudo systemctl start $SERVICE && echo 'Service started' && sudo systemctl status $SERVICE --no-pager"
}

cmd_stop() {
    require_service
    $SSH "sudo systemctl stop $SERVICE && echo 'Service stopped'"
}

cmd_deploy() {
    require_deploy_dir
    echo "=== OTA Deploy Starting ==="
    $SSH bash -s <<REMOTE
set -e
echo "[1/3] Git pull..."
cd $DEPLOY_DIR && sudo git pull

echo "[2/3] Building..."
if [ -f $DEPLOY_DIR/build.sh ]; then
    cd $DEPLOY_DIR && sudo bash build.sh
else
    echo "No build.sh found, skipping build step"
fi

echo "[3/3] Restarting service..."
$(if [[ -n "$SERVICE" ]]; then
    echo "sudo systemctl restart $SERVICE"
    echo "sleep 2"
    echo "sudo systemctl status $SERVICE --no-pager"
else
    echo "echo 'No service configured — skipping restart'"
fi)
echo ""
echo "=== Deploy Complete ==="
REMOTE
}

cmd_setup_key() {
    local key_name="pilink_$(echo "$HOST" | tr '.' '_')"
    local key_path="$HOME/.ssh/${key_name}"

    if [[ -f "$key_path" ]]; then
        echo "SSH key already exists at $key_path"
        echo "To reinstall, delete it first and re-run this command."
        return 0
    fi

    echo "Generating SSH key: $key_path"
    ssh-keygen -t ed25519 -f "$key_path" -N "" -C "pilink-${HOST}"

    echo ""
    echo "Installing public key on $HOST..."
    echo "You will be prompted for the remote password once."
    ssh-copy-id -i "$key_path" "$HOST"

    echo ""
    echo "Key installed. Add this to your ~/.ssh/config if not already there:"
    echo ""
    echo "  Host $HOST"
    echo "    IdentityFile $key_path"
    echo "    StrictHostKeyChecking no"
    echo ""
    echo "Test with: bash pilink.sh ping"
}

cmd_test_config() {
    echo "=== PiLink Config ==="
    echo "HOST:       $HOST"
    echo "SERVICE:    ${SERVICE:-<not set>}"
    echo "DEPLOY_DIR: ${DEPLOY_DIR:-<not set>}"
    echo "Config file: ${CONFIG_FILE}"
    echo ""
    echo "=== SSH Test ==="
    if $SSH "echo 'Connected to \$(hostname) as \$(whoami)'" 2>/dev/null; then
        echo "SSH: OK"
    else
        echo "SSH: FAILED — check your SSH config and key"
        exit 1
    fi
}

# ─── Main Dispatcher ────────────────────────────────────────────────────────
[[ $# -lt 1 ]] && usage

command="$1"
shift

case "$command" in
    ping)        cmd_ping ;;
    info)        cmd_info ;;
    exec)        cmd_exec "$@" ;;
    sudo)        cmd_sudo "$@" ;;
    read)        cmd_read "$@" ;;
    write)       cmd_write "$@" ;;
    edit)        cmd_edit "$@" ;;
    push)        cmd_push "$@" ;;
    pull)        cmd_pull "$@" ;;
    tail)        cmd_tail "$@" ;;
    logs)        cmd_logs "$@" ;;
    status)      cmd_status ;;
    restart)     cmd_restart ;;
    start)       cmd_start ;;
    stop)        cmd_stop ;;
    deploy)      cmd_deploy ;;
    setup-key)   cmd_setup_key ;;
    test-config) cmd_test_config ;;
    *)           echo "Unknown command: $command"; usage ;;
esac
