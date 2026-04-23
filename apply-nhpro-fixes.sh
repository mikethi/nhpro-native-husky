#!/usr/bin/env bash
# apply-nhpro-fixes.sh
# ─────────────────────────────────────────────────────────────────────────────
# Applies the nhpro-native-husky USB gadget / HW-init / modem-FUSE overlay
# changes from the branch  copilot/analyze-logs-for-insights  to your local
# clone of mikethi/nhpro-native-husky.
#
# Run from the root of your local clone:
#   bash apply-nhpro-fixes.sh
#
# What it does:
#   1. Verifies you are inside the correct git repository.
#   2. Fetches the remote branch.
#   3. Checks out only the overlay files from that branch (non-destructive –
#      your working tree and current branch are NOT changed).
#   4. Reports what was applied.
#
# Files applied:
#   nethunter-pro/overlays/husky/usr/local/bin/nhpro-hw-init
#   nethunter-pro/overlays/husky/usr/local/bin/nhpro-usb-gadget
#   nethunter-pro/overlays/husky/usr/local/bin/nhpro-modem-mount
#   nethunter-pro/overlays/husky/usr/local/bin/nhpro-usb-mode
#   nethunter-pro/overlays/husky/etc/systemd/system/nhpro-hw-init.service
#   nethunter-pro/overlays/husky/etc/systemd/system/nhpro-usb-gadget.service
#   nethunter-pro/overlays/husky/etc/systemd/system/firmware-modem.service
#   nethunter-pro/overlays/husky/usr/lib/udev/rules.d/60-husky-sysfs.rules
#   nethunter-pro/devices/zuma/packages-phosh.yaml
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REMOTE="origin"
BRANCH="copilot/analyze-logs-for-insights"
REMOTE_REF="refs/remotes/${REMOTE}/${BRANCH}"

# Files to pull from the branch
FILES=(
  nethunter-pro/overlays/husky/usr/local/bin/nhpro-hw-init
  nethunter-pro/overlays/husky/usr/local/bin/nhpro-usb-gadget
  nethunter-pro/overlays/husky/usr/local/bin/nhpro-modem-mount
  nethunter-pro/overlays/husky/usr/local/bin/nhpro-usb-mode
  nethunter-pro/overlays/husky/etc/systemd/system/nhpro-hw-init.service
  nethunter-pro/overlays/husky/etc/systemd/system/nhpro-usb-gadget.service
  nethunter-pro/overlays/husky/etc/systemd/system/firmware-modem.service
  nethunter-pro/overlays/husky/usr/lib/udev/rules.d/60-husky-sysfs.rules
  nethunter-pro/devices/zuma/packages-phosh.yaml
)

# ── Sanity check ──────────────────────────────────────────────────────────────
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "ERROR: not inside a git repository. Run this script from the root of" >&2
  echo "       your nhpro-native-husky clone." >&2
  exit 1
fi

REPO_URL=$(git remote get-url "${REMOTE}" 2>/dev/null || true)
if [[ "${REPO_URL}" != *nhpro-native-husky* ]]; then
  echo "WARNING: remote '${REMOTE}' URL does not look like nhpro-native-husky:" >&2
  echo "         ${REPO_URL}" >&2
  read -r -p "Continue anyway? [y/N] " reply
  [[ "${reply,,}" == "y" ]] || { echo "Aborted."; exit 1; }
fi

# ── Fetch the branch ──────────────────────────────────────────────────────────
echo ">>> Fetching ${REMOTE}/${BRANCH} …"
git fetch "${REMOTE}" "${BRANCH}:${REMOTE_REF}" 2>&1 | sed 's/^/    /'

# ── Create parent directories (git checkout does this, but be explicit) ───────
for f in "${FILES[@]}"; do
  mkdir -p "$(dirname "${f}")"
done

# ── Check out each file from the remote branch ────────────────────────────────
echo ">>> Applying files from ${BRANCH}:"
for f in "${FILES[@]}"; do
  git checkout "${REMOTE_REF}" -- "${f}"
  echo "    OK  ${f}"
done

# ── Ensure scripts are executable ────────────────────────────────────────────
for script in \
  nethunter-pro/overlays/husky/usr/local/bin/nhpro-hw-init \
  nethunter-pro/overlays/husky/usr/local/bin/nhpro-usb-gadget \
  nethunter-pro/overlays/husky/usr/local/bin/nhpro-modem-mount \
  nethunter-pro/overlays/husky/usr/local/bin/nhpro-usb-mode; do
  chmod +x "${script}"
done

echo ""
echo ">>> Done.  Files have been staged in your index."
echo "    Review with:  git diff --cached"
echo "    Commit with:  git commit -m 'feat: apply nhpro USB gadget / HW-init / modem-FUSE overlay'"
echo ""
echo "    To deploy on device (inside the built image root):"
echo "      systemctl enable nhpro-hw-init.service"
echo "      systemctl enable nhpro-usb-gadget.service"
echo "      systemctl enable firmware-modem.service"
