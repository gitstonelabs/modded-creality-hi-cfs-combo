#!/usr/bin/env bash
# install.sh - installer for the modded Creality Hi + CFS combo.
#
# What it does:
#   1. Preflight checks (klipper dir, config dir, git).
#   2. Clones/updates the creality-cfs-klipper repo and pins it to a known commit.
#   3. Installs creality_cfs.py into klippy/extras/.
#   4. Copies this repo's config/*.cfg into the printer config dir. An existing
#      same-named file is backed up to .bak once (an existing .bak is never
#      overwritten). A file you have edited (differs from the shipped one) is
#      left alone unless you re-run with FORCE=1.
#   5. Prints the manual next steps (placeholders, firmware, CAN, restart).
#
# Idempotent: safe to run more than once. Re-running never wipes your filled-in
# placeholders and never clobbers the first backup. It NEVER restarts Klipper
# for you.

set -euo pipefail

# --- Settings (override via environment) ------------------------------------
KLIPPER_DIR="${KLIPPER_DIR:-$HOME/klipper}"
CONFIG_DIR="${CONFIG_DIR:-$HOME/printer_data/config}"
CFS_URL="https://github.com/gitstonelabs/creality-cfs-klipper"
CFS_REF="73731e9"
CFS_CACHE="${CFS_CACHE:-$HOME/creality-cfs-klipper}"
FORCE="${FORCE:-0}"   # FORCE=1 overwrites configs you have edited (backup kept)

# Resolve this repo's root (script lives in <repo>/scripts/).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
REPO_CONFIG_DIR="$REPO_DIR/config"

# --- 1. Preflight -------------------------------------------------------------
fail() { echo "ERROR: $*" >&2; exit 1; }

[ -d "$KLIPPER_DIR" ] || fail "Klipper not found at '$KLIPPER_DIR'. Install Klipper first, or set KLIPPER_DIR."
[ -d "$KLIPPER_DIR/klippy/extras" ] || fail "'$KLIPPER_DIR/klippy/extras' not found; KLIPPER_DIR does not look like a Klipper source tree."
[ -d "$CONFIG_DIR" ]  || fail "Printer config dir not found at '$CONFIG_DIR'. Set CONFIG_DIR if yours differs."
command -v git >/dev/null 2>&1 || fail "git is not on PATH. Install git and re-run."
[ -d "$REPO_CONFIG_DIR" ] || fail "Repo config dir not found at '$REPO_CONFIG_DIR'. Run this script from a full checkout."

echo "==> Klipper:      $KLIPPER_DIR"
echo "==> Config dir:   $CONFIG_DIR"
echo "==> CFS cache:    $CFS_CACHE (pinned to $CFS_REF)"

# --- 2. Fetch the CFS driver repo, pinned -------------------------------------
if [ ! -d "$CFS_CACHE/.git" ]; then
    echo "==> Cloning $CFS_URL"
    git clone "$CFS_URL" "$CFS_CACHE"
else
    echo "==> Updating existing clone at $CFS_CACHE"
    git -C "$CFS_CACHE" fetch
fi
echo "==> Pinning to commit $CFS_REF"
git -C "$CFS_CACHE" checkout "$CFS_REF"

# --- 3. Install the Klipper module --------------------------------------------
CFS_MODULE_SRC="$CFS_CACHE/src/creality_cfs.py"
CFS_MODULE_DST="$KLIPPER_DIR/klippy/extras/creality_cfs.py"
[ -f "$CFS_MODULE_SRC" ] || fail "Module not found at '$CFS_MODULE_SRC'. Clone may be broken."
echo "==> Installing creality_cfs.py -> $CFS_MODULE_DST"
cp "$CFS_MODULE_SRC" "$CFS_MODULE_DST"

# --- 4. Install the config set -------------------------------------------------
# NOTE: the CFS repo's cfs_macros.cfg is deliberately NOT installed. This
# combo's config/macros.cfg provides its own T0-T3 and cut macros.
echo "==> Installing configs from $REPO_CONFIG_DIR"
for src in "$REPO_CONFIG_DIR"/*.cfg; do
    name="$(basename "$src")"
    if [ "$name" = "cfs_macros.cfg" ]; then
        echo "    skip $name (this repo ships its own macros.cfg)"
        continue
    fi
    dst="$CONFIG_DIR/$name"
    if [ -f "$dst" ]; then
        if cmp -s "$src" "$dst"; then
            echo "    $name unchanged, skipping"
            continue
        fi
        # $dst differs from the shipped file: it holds the user's edits
        # (filled placeholders). Never overwrite those on a re-run unless
        # explicitly forced.
        if [ "$FORCE" != "1" ]; then
            echo "    $name exists and differs from the shipped copy, skipping"
            echo "      (your edits are preserved; re-run with FORCE=1 to overwrite)"
            continue
        fi
        if [ -e "$dst.bak" ]; then
            echo "    keeping existing $name.bak (never overwritten)"
        else
            echo "    backing up existing $name -> $name.bak"
            cp "$dst" "$dst.bak"
        fi
    fi
    echo "    installing $name"
    cp "$src" "$dst"
done

# --- 5. Next steps (manual) ----------------------------------------------------
cat <<'NEXT_STEPS'

================================================================================
 INSTALL COMPLETE - MANUAL STEPS REQUIRED BEFORE KLIPPER WILL START
================================================================================

1. Fill the placeholders in the installed configs:
     printer.cfg   [mcu] serial          -> Octopus by-id path (ls /dev/serial/by-id/)
     printer.cfg   X/Y run_current       -> set for your steppers
     ebb42.cfg     [mcu EBB] canbus_uuid -> ~/klipper/scripts/canbus_query.py can0
     eddy.cfg      [mcu eddy] serial     -> Eddy by-id path (then CAN after flashing)
     eddy.cfg      y_offset / z_offset   -> measure + calibrate
     cfs.cfg       serial_port           -> CH340/CH341 RS485 dongle by-id path

2. Build and flash firmware (see INSTALL.md for the full menuconfig matrix):
     Octopus V1.0 (STM32F446, USB), EBB42 Gen2 (STM32G0B1, USB then CAN),
     Eddy Duo (RP2040, USB then CAN).

3. Bring up the CAN bus for the EBB + Eddy:
     ./scripts/setup-can.sh
   (bitrate must match the firmware CAN speed; exactly two 120R terminators)

4. Restart Klipper YOURSELF once the placeholders are filled, e.g.:
     sudo systemctl restart klipper
   This script never restarts Klipper for you.

5. Work through docs/bring-up-checklist.md, including the safety gates
   (bed SSR / AC isolation, cutter hall 3.3V signal) before applying power.
================================================================================
NEXT_STEPS
