# PiLink — Claude Code Instructions

## What This Is

PiLink is an SSH pipeline tool that lets Claude Code operate on a remote Raspberry Pi (or any Linux host) directly. It wraps SSH/SCP into simple subcommands.

## Usage

**Always use `bash pilink.sh`** for remote Pi operations — never SSH manually.

```bash
# Connection
bash pilink.sh ping                    # Test connectivity
bash pilink.sh info                    # System info (hostname, temp, disk, etc.)
bash pilink.sh test-config             # Validate config + SSH connection

# Remote execution
bash pilink.sh exec "command"          # Run any command on Pi
bash pilink.sh sudo "command"          # Run command with sudo

# File operations
bash pilink.sh read /path/file         # Read remote file
bash pilink.sh write /path/file        # Write stdin to remote file (base64-safe)
bash pilink.sh edit /path/file "old" "new"  # Sed replacement
bash pilink.sh push local remote       # SCP file to Pi
bash pilink.sh pull remote local       # SCP file from Pi
bash pilink.sh tail /path/file [n]     # Tail remote file

# Service management
bash pilink.sh status                  # Service + system overview
bash pilink.sh logs [n]                # Journalctl last n lines (default 50)
bash pilink.sh restart                 # Restart configured service
bash pilink.sh start                   # Start configured service
bash pilink.sh stop                    # Stop configured service

# Deployment
bash pilink.sh deploy                  # OTA: git pull → build → restart
```

## Configuration

Edit `pilink.conf` to set the SSH host, service name, and deploy directory. Or override with env vars: `PILINK_HOST`, `PILINK_SERVICE`, `PILINK_DEPLOY_DIR`.

## SSH Setup

Run `bash pilink.sh setup-key` to generate an ed25519 key and install it on the Pi for passwordless access. The SSH host alias should be configured in `~/.ssh/config`.

## Integration with Other Projects

To use PiLink from another project, either:
1. Reference it by absolute path: `bash D:/PiLink/pilink.sh exec "ls"`
2. Symlink or copy `pilink.sh` + `pilink.conf` into the other project's `tools/` directory
3. Set `PILINK_HOST` env var if you need a different host per project
