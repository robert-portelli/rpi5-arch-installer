#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# ufw-firstboot.bash
#
# Purpose
#   One-time (first-boot) initialization of UFW rules in the target system.
#
# State management
#   This script uses a state directory plus symlinks under /var/lib/ufw-firstboot
#   to record what happened and to make execution deterministic across boots.
#
#   Layout
#     /var/lib/ufw-firstboot/
#       state/                     Versioned state records (append-only).
#         <UTC_TIMESTAMP>.txt      A record describing the run context/results.
#       current -> state/<...>.txt Symlink to the most recent successful record.
#       done    -> state/<...>.txt Symlink used as the run-once completion marker.
#
#   Semantics
#     - done exists:
#         The script completed successfully at least once and should not be run
#         again. The script exits immediately if this marker is present.
#     - current:
#         Convenience pointer to the latest successful run record (same target as
#         done). Used for quick inspection and troubleshooting.
#     - state/<timestamp>.txt:
#         A durable, auditable record of the run. Records are never modified in
#         place; each run attempts to create a new record.
#
#   Atomicity and crash-safety
#     - State records are written to a temporary file then atomically renamed
#       into place (mv on the same filesystem).
#     - Symlinks are updated using ln -sfn, which replaces the link atomically.
#       As a result, the system will always observe either the previous state
#       or the new state; it will not observe partially-written state.
#
#   Auditing and review
#     - Determine if the script has ever completed successfully:
#         ls -l /var/lib/ufw-firstboot/done
#     - View the latest successful run record:
#         cat "$(readlink -f /var/lib/ufw-firstboot/current)"
#     - Review historical runs:
#         ls -1 /var/lib/ufw-firstboot/state/
#
# Notes
#   - The systemd unit should gate execution with:
#       ConditionPathExists=!/var/lib/ufw-firstboot/done
#     The script also checks for the done marker to remain safe if started
#     manually or if unit gating changes.
# -----------------------------------------------------------------------------

set -euo pipefail

BASE="/var/lib/ufw-firstboot"
STATE_DIR="${BASE}/state"
CURRENT_LINK="${BASE}/current"
DONE_LINK="${BASE}/done"

mkdir -p "$STATE_DIR"
chmod 0755 "$BASE" "$STATE_DIR"

if [[ -e "$DONE_LINK" ]]; then
    exit 0
fi

ts="$(date -u +%Y%m%dT%H%M%SZ)"
new_state="${STATE_DIR}/${ts}.txt"
tmp_state="${new_state}.tmp"

# Collect useful diagnostics / metadata for debugging.
{
    echo "timestamp=${ts}"
    echo "kernel=$(uname -r)"
    echo "cmdline=$(cat /proc/cmdline)"
} >"$tmp_state"

# Atomic commit of the state file.
mv -f "$tmp_state" "$new_state"

# Apply ufw
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw --force enable

# Atomically update symlink to "current"
ln -sfn "$new_state" "$CURRENT_LINK"

# Mark completion as a symlink too (points at the same state record).
ln -sfn "$new_state" "$DONE_LINK"

# Optional: disable the unit after success (not required if ConditionPathExists is used)
systemctl disable ufw-firstboot.service || true
