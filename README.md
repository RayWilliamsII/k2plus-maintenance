# K2 Plus Maintenance Scripts

This repository contains maintenance, discovery, and snapshot scripts for a customized Creality K2 Plus / K2+ 3D printer.

The printer runs a Creality firmware based on OpenWrt / Tina Linux. The current working assumption for this project is that the printer is rooted and reachable over SSH as `root@k2plus.local`.

The purpose of this project is **not** to create a full restore image. Instead, it provides a repeatable way to:

- discover where meaningful printer configuration and customization lives;
- document the current filesystem, service, and customization layout;
- take file-based snapshots of relevant locations;
- create a known-good snapshot that can be compare to a later snapshot after a reset, firmware flash, or reapplication of customizations.

The snapshots are intended to support **verification**. For example, after reflashing firmware and reinstalling K2 Improvements, the snapshot can be compared against the last-known-good state to confirm that the important files and directory contents match expectations.

## Project Philosophy

This repository treats the printer as an appliance-like Linux system with several distinct layers:

| Layer | Meaning |
|---|---|
| `/rom` | Read-only Creality firmware baseline. Useful for determining what Creality changed between firmware versions. |
| `/overlay/upper` | Persistent OpenWrt overlay changes. Small changes here may be behaviorally significant. |
| `/mnt/UDISK` | Primary persistent storage for printer data, K2 Improvements, Fluidd, Moonraker, Creality user data, Entware, and related customizations. |
| `/opt` | Symlink into `/mnt/UDISK/opt`, used for Entware-style tooling. |

A small file is not assumed to be insignificant. A one-line init, config, or symlink change may materially affect printer behavior. The scripts therefore identify and snapshot important locations based on function, not size.

## Repository Layout

Expected layout:

```text
.
├── README.md
├── .gitignore
└── config/
    ├── snapshot_excludes.default.tsv
    └── snapshot_paths.default.tsv
├── runs/
├── snapshot_lkg/
├── snapshot_current/
└── scripts/
    ├── run_probe.sh
    ├── run_snapshot.sh
    ├── probes/
    │   ├── 1_capability_probe.sh
    │   ├── 2_paths_and_services.sh
    │   ├── 3_web_stack.sh
    │   ├── 4_vendor_web_server_config.sh
    │   ├── 5_size_footprint_inventory.sh
    │   ├── 6_persistent_directory_inventory.sh
    │   └── 7_manifest_inventory.sh
    └── snapshots/
        └── snapshot_pull.sh
```

Generated artifact output directories are excluded from Git:

```gitignore
runs/
snapshot_lkg/
snapshot_current/
```

## Prerequisites

On the workstation running these scripts:

- Bash
- SSH client
- SCP
- rsync
- Git
- SSH key authentication to `root@k2plus.local`

The printer should allow passwordless SSH from the workstation. The scripts use non-interactive SSH assumptions and are intended to fail rather than pause for password entry.

A typical local SSH config entry looks like:

```sshconfig
Host k2plus.local
  User root
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
```
### Target Host (K2 Plus Printer)

The examples shown assume that the K2 Plus printer is accessible via hostname.
For example, my printer resolves via mDNS as `k2plus.local`.

However, the scripts accept any SSH-reachable host value, including:

- mDNS hostnames (`k2plus.local`)
- regular DNS hostnames
- raw IPv4 addresses
- raw IPv6 addresses (with proper SSH syntax if needed)

Examples:

```bash
./scripts/run_probe.sh k2plus.local scripts/probes/1_capability_probe.sh
./scripts/run_probe.sh 192.168.1.42 scripts/probes/1_capability_probe.sh
./scripts/run_snapshot.sh 192.168.1.42 lkg
```
### Available Diskspace
The artifacts created by the probes are relatively small. However, the snapshots will be large. I would recommend 20 GB of free diskspace for all probes and two snapshots (lkg, current). Remember, the purpose of the snapshots is to offer file comparison only. You cannot use them to restore you system.  

### Sample Run Diskspace and Execution Time

| Script | Diskspace | Runtime |
|--------|-----------|---------|
|1_capability_probe.sh|<25 kB|~1 min|
|2_paths_and_services.sh|<60 kB|~1 min|
|3_web_stack.sh|<25 kB|~1 min|
|4_vendor_web_server_config.sh|<5 kB|~1 min|
|5_size_footprint_inventory.sh|<5 kB|~1 min|
|6_persistent_directory_inventory.sh|<5 kB|~1 min|
|7_manifest_inventory.sh|<4 MB|~45 min|
|snapshot_pull.sh (lgg,current)|<7 GB|~25 min|

## Probe Execution Model

All probes are executed through:

```bash
./scripts/run_probe.sh <host> <probe_script>
```

Example:

```bash
./scripts/run_probe.sh k2plus.local scripts/probes/1_capability_probe.sh
```

`run_probe.sh` performs the following actions:

1. determines the repository root;
2. creates a run directory under `runs/<host>/`;
3. names the run directory using the timestamp and probe script name;
4. copies the selected probe script to `/tmp` on the printer;
5. executes the probe remotely with `sh`;
6. captures `stdout.txt`, `stderr.txt`, `exit_code.txt`, and `meta.json`.

A run directory is named similar to:

```text
runs/k2plus.local/2026-05-23T00-16-20-0400_1_capability_probe/
```

Each run contains:

```text
stdout.txt
stderr.txt
exit_code.txt
meta.json
```

The probe output is for discovery and documentation. It is not treated as the authoritative change-detection mechanism for the project.

`run_all_probes.sh` performs the following actions:

1. iterates over all probes location in `scripts/probes/`;
2. displays status of each probe as it is executed.

## Snapshot Configuration

Two configuration files can be found in the `config/` directory. These are used to specify which paths will be included within a snapshot and any child paths that will be excluded.

### `config/snapshot_paths.default.tsv`

Contains a tab delimited table consisting of four columns. This file determings which filesystem paths are included in a snapshot. Although the table does not contain column heads, the columns are as follows:

1. Disposition - Contains the value of `required`, `optional`, or `informational`.
- `required` - Path included in snapshot and run will about if path is not available.
- `optional` - Path included in snapshot and run will continue if path is not available.
- `informational` - This is for future implementation.  Currently ignored by snapshot run.
2. Path - Filesystem path to include in the snapshot.
3. Dereference - Contains the value of `0` or `1` and specifies whether symbolic links will be followed. Dereferencing will increase the size of the snapshot but can be helpful if trying to track down files overridden by symbolic links.
- `0` - Symbolic links are not de-referenced.
- `1` - Symbolic links are de-referenced.
4. Description - A description of the contents found in the Path.

`All columns must be populated for each path.`

### `config/snapshot_excludes.default.tsv`

Contains a tab-delimited table consisting of two columns.  This file contains filesystem paths that will be excluded from snapshots. This includes items like print job g-code, logs, timelapse videos, etc. Although the table does not contain column heads, the columns are as follows:

1. Path - Filesystem path to exclude from the snapshot.
2. Description - A description of the contents found in the Path.

`All columns must be populated for each path.`

## Snapshot Execution Model

Snapshots are executed through:

```bash
./scripts/run_snapshot.sh <host> {lkg|Default:current}
```

Examples:

```bash
./scripts/run_snapshot.sh k2plus.local lkg
./scripts/run_snapshot.sh k2plus.local current
or
./scripts/run_snapshot.sh k2plus.local
```

There are two snapshot directories:

```text
snapshot_lkg/
snapshot_current/
```

- `snapshot_lkg` is the last-known-good reference snapshot.
- `snapshot_current` is the working comparison snapshot.

When running either a `lkg` or `current` snapshot and the destination is not empty, you will be prompted to verify that you want to empty the directory.

Snapshots are **file copies for comparison**, not restore images. The snapshot script copies the contents of selected paths as they are accessed on the printer. It dereferences symlinks and preserves modification time, but does not preserve owners, groups, permissions, ACLs, or xattrs. Once generated, snapshots are not reused by the scripts. You can rename, delete or move them for whatever purpose you need.

The intended workflow is:

1. create or refresh `snapshot_lkg` when the printer is in a known-good state;
2. after firmware reset, firmware flash, or customization reinstall, run `snapshot_current`;
3. compare `snapshot_lkg` and `snapshot_current` using external diff/comparison tools.

## Script Reference

### `scripts/run_probe.sh`

Local runner for all probe scripts.

It accepts a target host and a probe script path, copies the probe to `/tmp` on the target, executes it remotely, and stores the execution results under `runs/<host>/<timestamp>_<probe_name>/`.

Primary usage:

```bash
./scripts/run_probe.sh k2plus.local scripts/probes/1_capability_probe.sh
```

### `scripts/run_snapshot.sh`

Local runner for snapshot operations.

It accepts a target host and snapshot mode (`lkg` or `current`), then executes the snapshot implementation script while capturing stdout, stderr, exit code, and metadata under `runs/<host>/<timestamp>/`.

Primary usage:

```bash
./scripts/run_snapshot.sh k2plus.local lkg
./scripts/run_snapshot.sh k2plus.local current
```

### `scripts/probes/1_capability_probe.sh`

Initial capability and system layout probe.

This read-only probe gathers broad system facts, including:

- kernel and OpenWrt/Tina Linux identity;
- BusyBox/tool availability;
- mount and filesystem layout;
- overlay/persistence clues;
- top-level directory listings;
- relevant running processes;
- listening ports;
- init scripts and symlinks.

This probe establishes the baseline environment and confirms which tools are available on the printer.

### `scripts/probes/2_paths_and_services.sh`

Focused path, service, Nginx, Fluidd, Moonraker, and K2 Improvements probe.

This read-only probe gathers:

- key symlink targets such as `/opt` and `/etc/init.d/moonraker`;
- focused process and port information;
- Nginx configuration test and full expanded configuration;
- web root and Fluidd/Mainsail discovery;
- `printer_data` inventory;
- K2 Improvements footprint;
- key init script contents;
- high-value symlink targets.

This probe identifies where Fluidd, Moonraker, K2 Improvements, and important service definitions actually live.

### `scripts/probes/3_web_stack.sh`

Vendor web stack and service probe.

This read-only probe investigates the Creality vendor web components, including:

- `/usr/bin/web-server` existence and embedded string hints;
- web/camera-related init scripts;
- `/etc/init.d/webrtc`;
- `/etc/init.d/app` and `/etc/init.d/device_manager`;
- running `web-server` and `webrtc` processes;
- web-server-related configuration discovery;
- Dropbear SSH key/config state;
- quick backup classification hints.

This probe helps distinguish the Creality vendor web stack from the Fluidd/Moonraker stack.

### `scripts/probes/4_vendor_web_server_config.sh`

Vendor web-server configuration probe.

This read-only probe looks for vendor web configuration and persistent Creality user configuration. It gathers:

- `/var/www/html` inventory;
- possible `httpd.conf` and web-server config files;
- key vendor configuration files such as `system_config.json` and `log_config.json`;
- selected non-secret values from `system_config.json` when `jq` is available;
- K2 Improvements Git status using `/opt/bin` when available.

This probe helps identify which vendor-managed files are persistent and relevant to compare after a reset or reconfiguration.

### `scripts/probes/5_size_footprint_inventory.sh`

Filesystem size and footprint inventory probe.

This read-only probe reports filesystem and directory footprint information for:

- `/rom`;
- `/usr`;
- `/bin`;
- `/etc`;
- `/overlay`;
- `/mnt/UDISK`;
- `/opt`.

It resolves symlinks, reports mount information, reports `df` data, counts files and directories, and provides a top-level `/rom` breakdown while excluding submounts such as `/rom/dev`.

This probe is informational. It is used to understand filesystem topology and scope, not to make cleanup decisions.

### `scripts/probes/6_persistent_directory_inventory.sh`

Persistent directory inventory probe.

This read-only probe performs a depth-limited inventory of the primary persistent areas:

- `/mnt/UDISK`;
- `/overlay`;
- common subpaths such as `/mnt/UDISK/printer_data`, `/mnt/UDISK/root`, `/mnt/UDISK/creality`, `/mnt/UDISK/opt`, and `/overlay/upper`.

It reports size and file/directory counts for immediate child directories. The goal is to determine which persistent locations are relevant for snapshotting and comparison.

### `scripts/probes/7_manifest_inventory.sh`

Manifest-style verification inventory probe.

This read-only probe emits tab-delimited manifest information for selected areas:

- `/rom`;
- `/overlay/upper`;
- `/mnt/UDISK/printer_data` with noisy areas pruned;
- `/mnt/UDISK/creality/userdata` with noisy areas pruned;
- `/mnt/UDISK/root`;
- `/mnt/UDISK/root/k2-improvements` when present;
- `/mnt/UDISK/opt` when present.

Each manifest line includes type, mode, owner IDs, size, mtime, optional SHA256 for small files, symlink target, and path.

This probe is useful for producing a structured inventory, but the project does not rely solely on hashes or manifests for change detection. Actual file snapshots are preferred for final comparison.

### `scripts/snapshots/snapshot_pull.sh`

Snapshot implementation script used by `run_snapshot.sh`.

This script pulls selected file trees from the printer into either `snapshot_lkg` or `snapshot_current`.

Included source paths:

```text
/mnt/UDISK/printer_data
/mnt/UDISK/root
/mnt/UDISK/creality
/overlay/upper
/mnt/UDISK/opt
/rom
```

Excluded noisy or low-value paths include:

```text
/mnt/UDISK/printer_data/logs
/mnt/UDISK/creality/userdata/log
/mnt/UDISK/creality/userdata/delay_image
/mnt/UDISK/timelapse
/mnt/UDISK/ai_image
/mnt/UDISK/layers_image
/mnt/UDISK/tmp
/mnt/UDISK/opt/tmp
```

Snapshot behavior:

- uses `rsync` over SSH;
- dereferences symlinks with `-L`;
- preserves modification times with `-t`;
- does not preserve permissions, owners, groups, ACLs, or xattrs;
- writes `_snapshot_metadata.txt` into the snapshot directory.

The metadata file records mode, timestamp, target host, runner host/user, repository branch/commit, kernel info, and OpenWrt release info.

## Snapshot Notes

The snapshot directories should not be committed to Git.

Recommended `.gitignore` entries:

```gitignore
runs/
snapshot_lkg/
snapshot_current/
```

The snapshots are intended for external directory comparison tools. They are not intended to be rsynced back to the printer as a restoration method.

## Git Executable Permissions

This is only relevant to those creating their own scripts to ensure that their scripts aren't committed to Git without first settings the executable bit.  Git tracks the executable bit for scripts. Before committing shell scripts, ensure they are executable:

```bash
chmod +x scripts/run_probe.sh
chmod +x scripts/run_snapshot.sh
chmod +x scripts/probes/*.sh
chmod +x scripts/snapshots/*.sh
```

Verify executable mode in Git:

```bash
git ls-files --stage
```

Executable scripts should show mode `100755`; non-executable files show `100644`.

If needed, force the executable bit into Git:

```bash
git update-index --chmod=+x scripts/run_probe.sh
```

## Safety Notes

- Probe scripts are intended to be read-only.
- Snapshot scripts copy files from the printer to the workstation; they do not modify the printer.
- `snapshot_current` and `snapshot_lkg` directories are intentionally wiped before repopulation but require confirmation before proceeding.
- Guardrails are included to avoid wiping unexpected directories.
- The scripts assume SSH key-based access to the printer.

## Typical Workflow

Initial discovery:

```bash
./scripts/run_probe.sh k2plus.local scripts/probes/1_capability_probe.sh
./scripts/run_probe.sh k2plus.local scripts/probes/2_paths_and_services.sh
./scripts/run_probe.sh k2plus.local scripts/probes/3_web_stack.sh
./scripts/run_probe.sh k2plus.local scripts/probes/4_vendor_web_server_config.sh
./scripts/run_probe.sh k2plus.local scripts/probes/5_size_footprint_inventory.sh
./scripts/run_probe.sh k2plus.local scripts/probes/6_persistent_directory_inventory.sh
./scripts/run_probe.sh k2plus.local scripts/probes/7_manifest_inventory.sh
```

Create last-known-good snapshot:

```bash
./scripts/run_snapshot.sh k2plus.local lkg
```

Create current comparison snapshot later:

```bash
./scripts/run_snapshot.sh k2plus.local current
```

Then compare:

```text
snapshot_lkg/
snapshot_current/
```

using your preferred directory comparison tool.

## Additional Scripts

### `scripts/dropbear_ssh_helper.sh`

Script will validate that a valid SSH connection exists between the workstation and the target K2Plus machine and create a persistent SSH key is approved.  It will also remove any stale keys between the source machine and the K2Plus.

See [dropbear_ssh_README.md](/scripts/helper/dropbear_ssh_README.md)
