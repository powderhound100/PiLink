<p align="center">
  <img src="https://img.shields.io/badge/bash-4.0+-blue?logo=gnubash&logoColor=white" alt="Bash 4.0+">
  <img src="https://img.shields.io/badge/platform-Windows%20%7C%20Mac%20%7C%20Linux-brightgreen" alt="Platform">
  <img src="https://img.shields.io/badge/target-Raspberry%20Pi-c51a4a?logo=raspberrypi&logoColor=white" alt="Raspberry Pi">
  <img src="https://img.shields.io/badge/AI-Claude%20Code-blueviolet" alt="Claude Code">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

# PiLink

**SSH pipeline tool for Claude Code ↔ Raspberry Pi collaboration.**

PiLink wraps SSH and SCP into simple, scriptable subcommands so that [Claude Code](https://claude.ai/claude-code) (or any AI coding assistant) can operate on a remote Raspberry Pi directly from your dev machine — executing commands, reading/writing files, managing services, and deploying code over the air.

> Built for the [GROUNDLINK](https://github.com/powderhound100/groundlink-leo-comms) project — a multi-SDR Raspberry Pi node for ADS-B, UAT, and FM radio streaming.

---

## Why PiLink?

When using AI coding assistants like Claude Code, you often need the AI to interact with remote hardware — but giving it raw SSH access is messy and error-prone. PiLink solves this by providing:

- **Simple subcommands** — `ping`, `exec`, `read`, `write`, `deploy`, etc.
- **Base64-safe file writes** — binary and special characters handled correctly
- **Service management** — start/stop/restart/logs via systemd
- **One-command OTA deploys** — `git pull → build → restart` in a single call
- **SSH key setup** — generates and installs ed25519 keys automatically
- **Config file** — one file to set host, service, and deploy directory
- **Zero dependencies** — just bash, ssh, and scp (all pre-installed on most systems)

---

## Quick Start

### 1. Clone

```bash
git clone https://github.com/powderhound100/PiLink.git
cd PiLink
```

### 2. Configure

Edit `pilink.conf` with your Pi's details:

```bash
HOST="pi"                        # SSH host alias (from ~/.ssh/config) or user@ip
SERVICE="my-app"                 # systemd service name (optional)
DEPLOY_DIR="/opt/my-app"         # remote git repo for OTA deploys (optional)
```

### 3. Set Up SSH (one-time)

If you don't already have passwordless SSH to your Pi:

```bash
bash pilink.sh setup-key
```

This will:
1. Generate an ed25519 key pair (`~/.ssh/pilink_pi`)
2. Install the public key on your Pi (you'll enter your password once)
3. Print the `~/.ssh/config` entry to add

Add it to your `~/.ssh/config`:

```
Host pi
    HostName 10.0.0.245          # Your Pi's IP address
    User pi                       # Your Pi's username
    IdentityFile ~/.ssh/pilink_pi
    StrictHostKeyChecking no
```

### 4. Test

```bash
bash pilink.sh ping
# SSH OK — raspberrypi — Sun Mar 30 12:00:00 UTC 2026

bash pilink.sh test-config
# HOST:       pi
# SERVICE:    my-app
# DEPLOY_DIR: /opt/my-app
# SSH: OK
```

---

## Commands Reference

### Connection

| Command | Description |
|---------|-------------|
| `ping` | Test SSH connectivity |
| `info` | System info — hostname, uptime, temp, disk, memory, load |
| `test-config` | Validate config file and SSH connection |

### Remote Execution

| Command | Description |
|---------|-------------|
| `exec "cmd"` | Run a command on the Pi |
| `sudo "cmd"` | Run a command with `sudo` |

### File Operations

| Command | Description |
|---------|-------------|
| `read /path/file` | Print remote file to stdout |
| `write /path/file` | Write stdin to remote file (base64-safe for binary) |
| `edit /path/file "old" "new"` | Find-and-replace in a remote file |
| `push local remote` | Copy local file to Pi via SCP |
| `pull remote local` | Copy Pi file to local machine via SCP |
| `tail /path/file [n]` | Show last *n* lines of a remote file (default: 20) |

### Service Management

| Command | Description |
|---------|-------------|
| `status` | System overview + service status |
| `logs [n]` | Last *n* lines from journalctl (default: 50) |
| `restart` | Restart the configured systemd service |
| `start` | Start the service |
| `stop` | Stop the service |

### Deployment

| Command | Description |
|---------|-------------|
| `deploy` | Full OTA: `git pull` → `build.sh` → `systemctl restart` |

### Setup

| Command | Description |
|---------|-------------|
| `setup-key` | Generate ed25519 key and install on Pi |

---

## Usage Examples

```bash
# Run a command
bash pilink.sh exec "uname -a"
bash pilink.sh exec "ls -la /opt/my-app"

# Read and write files
bash pilink.sh read /etc/hostname
echo "new config content" | bash pilink.sh write /opt/my-app/config.toml

# Edit a config in-place
bash pilink.sh edit /opt/my-app/config.toml "port = 8080" "port = 9090"

# Transfer files
bash pilink.sh push ./firmware.bin /opt/my-app/firmware.bin
bash pilink.sh pull /var/log/syslog ./pi-syslog.txt

# Service management
bash pilink.sh status
bash pilink.sh logs 200
bash pilink.sh restart

# Deploy new code (if DEPLOY_DIR is a git repo)
bash pilink.sh deploy
```

---

## Configuration

PiLink reads `pilink.conf` (same directory as the script) and supports environment variable overrides:

| Env Variable | Config Key | Default | Description |
|-------------|-----------|---------|-------------|
| `PILINK_HOST` | `HOST` | `pi` | SSH host alias or `user@ip` |
| `PILINK_SERVICE` | `SERVICE` | *(empty)* | systemd service to manage |
| `PILINK_DEPLOY_DIR` | `DEPLOY_DIR` | *(empty)* | Remote git directory for OTA |

Environment variables take priority over the config file.

---

## Using with Claude Code

Add this to your project's `CLAUDE.md` to give Claude Code access to your Pi:

```markdown
## Pi Access

Use PiLink for all Raspberry Pi operations — never SSH manually.

    bash /path/to/PiLink/pilink.sh <command> [args...]

Examples:
    bash /path/to/PiLink/pilink.sh ping
    bash /path/to/PiLink/pilink.sh exec "systemctl status my-app"
    bash /path/to/PiLink/pilink.sh logs 100
```

Claude Code will then use PiLink automatically whenever it needs to interact with the Pi.

---

## Requirements

| Requirement | Notes |
|------------|-------|
| **Bash 4.0+** | Git Bash on Windows, native on Mac/Linux |
| **SSH client** | OpenSSH (pre-installed on most systems) |
| **scp** | For file transfers (`push`/`pull`) |
| **systemd** | On the remote host, for service management |

---

## Troubleshooting

**`SSH: FAILED` on `test-config`**
- Check that your `~/.ssh/config` has the correct `Host`, `HostName`, `User`, and `IdentityFile`
- Verify the Pi is on the network: `ping <pi-ip>`
- Run `ssh -v pi` to debug the SSH connection

**`Permission denied` on remote commands**
- Ensure the Pi user has `sudo` privileges (ideally passwordless via `NOPASSWD` in sudoers)
- Check file permissions on the remote path

**`No service configured`**
- Set `SERVICE` in `pilink.conf` or pass `PILINK_SERVICE=my-app` as an env var

**`base64: invalid option -- 'w'` on macOS**
- macOS `base64` doesn't support `-w0`. Install GNU coreutils: `brew install coreutils` and use `gbase64`, or pipe through `tr -d '\n'`

---

## Project Structure

```
PiLink/
├── pilink.sh          # Main script — all commands in one file
├── pilink.conf        # Configuration (host, service, deploy dir)
├── CLAUDE.md          # Instructions for Claude Code
├── README.md          # This file
├── LICENSE            # MIT License
└── .gitignore
```

---

## License

MIT — see [LICENSE](LICENSE).

---

<p align="center">
  Built with 🛠️ by <a href="https://github.com/powderhound100">powderhound100</a> and <a href="https://claude.ai">Claude</a>
</p>
