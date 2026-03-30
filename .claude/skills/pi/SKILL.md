---
name: pi
description: Execute commands on a remote Raspberry Pi via SSH — ping, exec, read, write, edit, logs, status, restart, deploy, and more.
argument-hint: <command> [args...]
allowed-tools: Bash(bash */pilink.sh *)
---

Run PiLink commands on the remote Raspberry Pi.

## How to use

Pass the PiLink subcommand and arguments directly:

```bash
bash pilink.sh $ARGUMENTS
```

If pilink.sh is not in the current directory, use the full path (e.g., `bash D:/PiLink/pilink.sh $ARGUMENTS`).

## Available commands

- `/pi ping` — Test SSH connectivity
- `/pi info` — System info (hostname, temp, disk, memory, load)
- `/pi exec "command"` — Run any command on the Pi
- `/pi sudo "command"` — Run command with sudo
- `/pi read /path/file` — Print remote file contents
- `/pi write /path/file` — Write stdin to remote file (base64-safe)
- `/pi edit /path/file "old" "new"` — Find and replace in remote file
- `/pi tail /path/file [n]` — Tail last n lines (default 20)
- `/pi push local remote` — SCP file to Pi
- `/pi pull remote local` — SCP file from Pi
- `/pi status` — Service + system overview
- `/pi logs [n]` — Last n journal lines (default 50)
- `/pi restart` — Restart configured service
- `/pi start` — Start configured service
- `/pi stop` — Stop configured service
- `/pi deploy` — OTA: git pull → build → restart
- `/pi test-config` — Validate config and SSH connection
