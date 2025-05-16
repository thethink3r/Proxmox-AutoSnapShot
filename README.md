
# Proxmox-AutoSnapShot

## Create User & Group with Permissions

You need to create a user in Proxmox with permissions for `VM.Audit` and `VM.Snapshot`.

Create a custom role named `Snapshot` that includes these two privileges.

Then, create a group named `Snapshot` and assign the `Snapshot` role to the group on the `/vms` path.

## Create API Token

Create an API token for the user `snapshot@pve` with the name `AutoSnap`.

In the script, configure the following variables:
- `API_Token_ID` should be `snapshot@pve!AutoSnap`
- `API_Token_Secret` should be the token secret (⚠️ shown only once when the token is created in Proxmox)

## Run via systemd Timer

Example `.service` and `.timer` units are provided in the `systemd` folder.

To enable the systemd timers:

```bash
ln -s /opt/autosnap/systemd/autosnap.service /etc/systemd/system/autosnap.service
ln -s /opt/autosnap/systemd/autosnap.timer /etc/systemd/system/autosnap.timer
ln -s /opt/autosnap/systemd/cleanup.service /etc/systemd/system/cleanup.service
ln -s /opt/autosnap/systemd/cleanup.timer /etc/systemd/system/cleanup.timer
chmod +x /opt/autosnap/autosnap.sh
systemctl daemon-reload
systemctl enable --now autosnap.timer
systemctl enable --now cleanup.timer
```

In this example, snapshots are taken every 15 minutes from Monday to Friday between 06:00 and 18:00.  
Cleanup runs daily at 05:00 in the morning.

## Function Description

This script creates snapshots of running VMs on a Proxmox server.

Snapshot names follow the format: `autosnap-YYYYMMDDHHMM`.

The script checks if a snapshot with the current timestamp already exists and deletes old ones based on the retention policy.

- Snapshots are taken every 15 minutes.
- Snapshots from the last 2 hours are all kept.
- From 2 to 3 hours ago, only snapshots at HH:00 and HH:30 are kept.
- Older than 3 hours: only snapshots at HH:00 are kept.
- Snapshots not from today are deleted.

The script checks if a VM is locked before creating or deleting snapshots.

The script can also be run with the `-clean` parameter to only delete old snapshots without creating new ones.

## Parameters

### No parameter

Running `/opt/autosnap/autosnap.sh` will create a snapshot.

The timestamp is rounded down to the last 15-minute mark and used as the snapshot name.

Example: If the current time is `16.05.2025 09:23`, the snapshot name will be `autosnap-202505160915`.

Every full hour, a cleanup is performed before taking a new snapshot.

### `-clean` parameter

Only cleanup is performed, no new snapshots are created.

Retention policy:
- Keep all snapshots from the last hour.
- Between 1–3 hours: keep only those taken at HH:00 and HH:30.
- Older than 3 hours: keep only hourly snapshots.
- Delete all snapshots not from today.

Only snapshots starting with `autosnap-` are affected. All others are ignored.

## TAGS

The script supports filtering by Proxmox tags.

If enabled, only VMs with the defined tag (e.g., `AutoSnapshot`) will be processed.

By default, tag filtering is disabled and **all** running VMs are included.
