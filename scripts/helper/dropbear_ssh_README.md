# dropbear_ssh_helper.sh

A Bash script that automates SSH key generation and deployment to a remote host running **Dropbear** (commonly found on embedded systems, routers, and single-board computers such as Raspberry Pi).

---

## Overview

`dropbear_ssh_helper` walks through five guarded steps:

1. Verifies the target is reachable via mDNS
2. Tests whether an existing SSH key already works (exits early if it does)
3. Prompts you before making any changes
4. Generates an `ed25519` key and updates your local `~/.ssh/config`
5. Deploys the public key to the remote host and verifies the connection

---

## Requirements

- **macOS or Linux** with Bash 4+
- `ping`, `ssh`, `ssh-keygen` available in `PATH`
- The target host must be reachable via **mDNS** (`.local` name resolution)
- The target must be running **Dropbear** or OpenSSH as its SSH daemon

---

## Usage

```bash
./dropbear_ssh_helper <target-mDNS-name> <ssh-user>
```

| Argument | Description | Example |
|---|---|---|
| `<target-mDNS-name>` | The `.local` hostname of the remote device | `k2plus` or `k2plus.local` |
| `<ssh-user>` | The SSH user on the remote device | `root` |

**Examples:**

```bash
# Connect as user 'root' to k2plus.local
./dropbear_ssh_helper k2plus root

# The .local suffix is optional — both forms work
./dropbear_ssh_helper k2plus.local root

# Connect as root (uses Dropbear's /etc/dropbear/authorized_keys path)
./dropbear_ssh_helper k2plus root
```

---

## What the Script Does

### Step 1 — mDNS Reachability Check
Pings the target host twice. Exits immediately if unreachable.

### Step 2 — Existing SSH Test
Attempts a passwordless SSH connection using any keys already loaded. If this succeeds, the script exits with no changes made.

### Step 3 — User Confirmation
Prompts `[y/N]` before creating any keys or modifying any files.

### Step 4 — Key Generation
Generates an `ed25519` key pair at `~/.ssh/<source-host>_<target-host>`. Skips generation if the key file already exists.

### Step 5 — SSH Config Update
Appends (or updates) a `Host` block in `~/.ssh/config`:

```
Host k2plus.local
    User pi
    IdentityFile ~/.ssh/mymachine_k2plus
    IdentitiesOnly yes
```

If an entry for the target already exists but points to a different key, you are prompted before any change is made.

### Step 6 — Key Deployment
Removes any stale `known_hosts` entry for the target, then copies the public key to the remote host.

Key is written to:
- `/home/<user>/.ssh/authorized_keys` — for regular users
- `/etc/dropbear/authorized_keys` — when `<ssh-user>` is `root`

### Step 7 — Verification
Performs a final passwordless SSH connection using the new key. Exits with a non-zero status and an error message if verification fails.

---

## Generated Files

| File | Description |
|---|---|
| `~/.ssh/<source>_<target>` | Private key |
| `~/.ssh/<source>_<target>.pub` | Public key |
| `~/.ssh/config` | Updated with a `Host` block for the target |

---

## Troubleshooting

**"not reachable via mDNS"**
Ensure the target is powered on, on the same network, and that mDNS/Bonjour is enabled. On Linux, `avahi-daemon` must be running.

**Verification failed**
Check that the Dropbear daemon on the target is running and that `authorized_keys` has the correct permissions (`600`). Review Dropbear logs on the target device.

**Entry exists with a different key**
The script will prompt you to update `~/.ssh/config`. If you decline, SSH may fall back to password authentication.

---

## Notes

- The script uses `set -euo pipefail` and will exit on any unexpected error.
- No changes are made to the remote host unless you confirm at the prompt in Step 3.
- Existing keys are never overwritten; generation is skipped if the key file is already present.
