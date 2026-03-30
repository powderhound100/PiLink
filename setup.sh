#!/usr/bin/env bash
# PiLink Setup Wizard
# Interactive guided setup for SSH connectivity to your Raspberry Pi.
# Run: bash setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="${SCRIPT_DIR}/pilink.conf"

# ─── Colors (if terminal supports them) ──────────────────────────────────────
if [[ -t 1 ]]; then
    BOLD='\033[1m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    CYAN='\033[0;36m'
    RESET='\033[0m'
else
    BOLD='' GREEN='' YELLOW='' RED='' CYAN='' RESET=''
fi

banner() { echo -e "\n${BOLD}${CYAN}$1${RESET}"; }
ok()     { echo -e "  ${GREEN}OK${RESET} $1"; }
warn()   { echo -e "  ${YELLOW}!!${RESET} $1"; }
fail()   { echo -e "  ${RED}FAIL${RESET} $1"; }
ask()    { echo -en "  ${BOLD}$1${RESET} "; }

# ─── Header ──────────────────────────────────────────────────────────────────
clear 2>/dev/null || true
echo -e "${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║         PiLink Setup Wizard              ║"
echo "  ║   SSH pipeline for Claude Code + Pi      ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${RESET}"
echo "  This wizard will walk you through connecting"
echo "  to your Raspberry Pi in 5 steps."
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# STEP 1: Gather Pi connection details
# ══════════════════════════════════════════════════════════════════════════════
banner "[1/5] Pi Connection Details"
echo ""

# --- Pi IP address ---
ask "Pi IP address (e.g. 10.0.0.245):"
read -r PI_IP
if [[ -z "$PI_IP" ]]; then
    fail "IP address cannot be empty."
    exit 1
fi

# --- Pi username ---
ask "Pi username [pi]:"
read -r PI_USER
PI_USER="${PI_USER:-pi}"

# --- SSH alias ---
ask "SSH alias name [pi]:"
read -r SSH_ALIAS
SSH_ALIAS="${SSH_ALIAS:-pi}"

ok "Will connect as ${PI_USER}@${PI_IP} (alias: ${SSH_ALIAS})"

# ══════════════════════════════════════════════════════════════════════════════
# STEP 2: SSH key generation
# ══════════════════════════════════════════════════════════════════════════════
banner "[2/5] SSH Key Setup"
echo ""

KEY_NAME="pilink_${SSH_ALIAS}"
KEY_PATH="$HOME/.ssh/${KEY_NAME}"

# Ensure .ssh directory exists
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [[ -f "$KEY_PATH" ]]; then
    ok "SSH key already exists: ${KEY_PATH}"
    echo ""
    ask "Regenerate key? (y/N):"
    read -r REGEN
    if [[ "${REGEN,,}" == "y" ]]; then
        rm -f "$KEY_PATH" "${KEY_PATH}.pub"
        echo "  Generating new ed25519 key..."
        ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "pilink-${SSH_ALIAS}" -q
        ok "Key generated: ${KEY_PATH}"
    else
        ok "Keeping existing key."
    fi
else
    echo "  Generating ed25519 key: ${KEY_PATH}"
    ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "pilink-${SSH_ALIAS}" -q
    ok "Key generated: ${KEY_PATH}"
fi

# ══════════════════════════════════════════════════════════════════════════════
# STEP 3: SSH config entry
# ══════════════════════════════════════════════════════════════════════════════
banner "[3/5] SSH Config"
echo ""

SSH_CONFIG="$HOME/.ssh/config"
CONFIG_BLOCK="Host ${SSH_ALIAS}
    HostName ${PI_IP}
    User ${PI_USER}
    IdentityFile ${KEY_PATH}
    StrictHostKeyChecking accept-new
    ServerAliveInterval 30
    ServerAliveCountMax 3"

# Check if alias already exists
if [[ -f "$SSH_CONFIG" ]] && grep -q "^Host ${SSH_ALIAS}$" "$SSH_CONFIG" 2>/dev/null; then
    warn "SSH config already has 'Host ${SSH_ALIAS}' entry."
    echo ""
    echo "  Existing entry:"
    # Print until next Host block or end
    sed -n "/^Host ${SSH_ALIAS}$/,/^Host /{ /^Host [^${SSH_ALIAS}]/!p; }" "$SSH_CONFIG" | head -10 | sed 's/^/    /'
    echo ""
    ask "Replace it? (y/N):"
    read -r REPLACE_SSH
    if [[ "${REPLACE_SSH,,}" == "y" ]]; then
        # Remove old entry (from Host line to next Host line or EOF)
        # Use a temp file for safety
        TMP_CONF=$(mktemp)
        awk -v alias="Host ${SSH_ALIAS}" '
            $0 == alias { skip=1; next }
            /^Host / { skip=0 }
            !skip { print }
        ' "$SSH_CONFIG" > "$TMP_CONF"
        mv "$TMP_CONF" "$SSH_CONFIG"
        echo "" >> "$SSH_CONFIG"
        echo "$CONFIG_BLOCK" >> "$SSH_CONFIG"
        ok "SSH config entry replaced."
    else
        ok "Keeping existing SSH config entry."
    fi
else
    # Append new entry
    [[ -f "$SSH_CONFIG" ]] && echo "" >> "$SSH_CONFIG"
    echo "$CONFIG_BLOCK" >> "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"
    ok "Added to ~/.ssh/config:"
    echo "$CONFIG_BLOCK" | sed 's/^/    /'
fi

# ══════════════════════════════════════════════════════════════════════════════
# STEP 4: Install key on Pi
# ══════════════════════════════════════════════════════════════════════════════
banner "[4/5] Install Key on Pi"
echo ""
echo "  This will copy your public key to the Pi."
echo "  You will be asked for the Pi password ONE TIME."
echo ""
ask "Install key now? (Y/n):"
read -r INSTALL_KEY
INSTALL_KEY="${INSTALL_KEY:-y}"

if [[ "${INSTALL_KEY,,}" == "y" ]]; then
    echo ""
    echo "  Running ssh-copy-id..."
    if ssh-copy-id -i "$KEY_PATH" "${SSH_ALIAS}" 2>&1; then
        echo ""
        ok "Key installed on Pi."
    else
        echo ""
        fail "ssh-copy-id failed."
        echo ""
        echo "  Troubleshooting:"
        echo "    - Is the Pi powered on and on the network?"
        echo "    - Can you ping ${PI_IP}?"
        echo "    - Is SSH enabled? (sudo raspi-config → Interface → SSH)"
        echo ""
        echo "  You can retry manually later:"
        echo "    ssh-copy-id -i ${KEY_PATH} ${SSH_ALIAS}"
        echo ""
        ask "Continue anyway? (y/N):"
        read -r CONT
        if [[ "${CONT,,}" != "y" ]]; then
            exit 1
        fi
    fi
else
    warn "Skipped key install. Run manually later:"
    echo "    ssh-copy-id -i ${KEY_PATH} ${SSH_ALIAS}"
fi

# ══════════════════════════════════════════════════════════════════════════════
# STEP 5: Configure PiLink
# ══════════════════════════════════════════════════════════════════════════════
banner "[5/5] PiLink Configuration"
echo ""

# --- Service name ---
ask "Systemd service to manage (leave blank for none):"
read -r SVC_NAME

# --- Deploy directory ---
ask "Remote deploy directory (leave blank for none):"
read -r DEPLOY_PATH

# Write pilink.conf
cat > "$CONF_FILE" << CONF
# PiLink Configuration — generated by setup.sh
# Override with env vars: PILINK_HOST, PILINK_SERVICE, PILINK_DEPLOY_DIR

# SSH host alias (matches ~/.ssh/config Host entry)
HOST="${SSH_ALIAS}"

# Systemd service name (leave empty if none)
SERVICE="${SVC_NAME}"

# Remote directory for git-based OTA deploys (leave empty to disable)
DEPLOY_DIR="${DEPLOY_PATH}"
CONF

ok "Wrote ${CONF_FILE}"
echo ""
echo "  Config:"
echo "    HOST       = ${SSH_ALIAS}"
echo "    SERVICE    = ${SVC_NAME:-<none>}"
echo "    DEPLOY_DIR = ${DEPLOY_PATH:-<none>}"

# ══════════════════════════════════════════════════════════════════════════════
# Verify
# ══════════════════════════════════════════════════════════════════════════════
banner "Verifying connection..."
echo ""

if bash "${SCRIPT_DIR}/pilink.sh" ping 2>/dev/null; then
    ok "SSH connection verified!"
    echo ""

    # Quick system info
    echo "  Pi info:"
    bash "${SCRIPT_DIR}/pilink.sh" info 2>/dev/null | sed 's/^/    /'
else
    fail "Could not connect to Pi."
    echo ""
    echo "  Check:"
    echo "    1. Is the Pi on and connected to the network?"
    echo "    2. Can you ping ${PI_IP}?"
    echo "    3. Was the SSH key installed? Try:"
    echo "       ssh ${SSH_ALIAS}"
fi

# ══════════════════════════════════════════════════════════════════════════════
# Done
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║         Setup Complete!                  ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${RESET}"
echo "  Quick start:"
echo "    bash pilink.sh ping          # test connection"
echo "    bash pilink.sh exec 'ls /'   # run a command"
echo "    bash pilink.sh info          # system info"
echo "    bash pilink.sh status        # service status"
echo ""
echo "  Claude Code integration:"
echo "    Add to your project's CLAUDE.md:"
echo "      bash ${SCRIPT_DIR}/pilink.sh <command> [args...]"
echo ""
echo "  GitHub CLI:"
echo "    gh extension install powderhound100/gh-pilink"
echo "    gh pilink ping"
echo ""
