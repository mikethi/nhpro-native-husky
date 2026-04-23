#!/bin/sh
# boot-targets/menu.sh — interactive boot menu
# Google Pixel 8 Pro (husky / zuma)
#
# Displays an ASCII boot menu on the UART console (ttySAC0, 115200 8N1)
# and waits up to MENU_TIMEOUT seconds for a key press.
# On timeout, boots the default target (linux / NetHunter Pro).
#
# Activate with:
#   ./scripts/set-target.sh set menu
# Or one-shot via fastboot:
#   fastboot boot -c 'boot_target=menu' boot-selector.img
#
# Requires: busybox read -t (timeout support)

MENU_TIMEOUT=10

run_target() {
    local c=" "
    # Clear any pending input
    read -r -t 1 c </dev/console 2>/dev/null || true

    while true; do
        echo "" >/dev/console
        echo "╔══════════════════════════════════════════════════╗" >/dev/console
        echo "║   nhpro-native-husky  —  Google Pixel 8 Pro     ║" >/dev/console
        echo "║   SoC: Tensor G3 (zuma / Samsung GS301)         ║" >/dev/console
        echo "╠══════════════════════════════════════════════════╣" >/dev/console
        echo "║                                                  ║" >/dev/console
        echo "║   1.  linux       NetHunter Pro  (default)       ║" >/dev/console
        echo "║   2.  android-a   Android slot_a                 ║" >/dev/console
        echo "║   3.  android-b   Android slot_b                 ║" >/dev/console
        echo "║   4.  gsi         Android GSI                    ║" >/dev/console
        echo "║   5.  recovery-a  Recovery slot_a                ║" >/dev/console
        echo "║   6.  recovery-b  Recovery slot_b                ║" >/dev/console
        echo "║                                                   ║" >/dev/console
        echo "╚═══════════════════════════════════════════════════╝" >/dev/console
        echo "" >/dev/console
        printf "  Enter 1-6 (default=1, timeout ${MENU_TIMEOUT}s): " \
               >/dev/console

        CHOICE=""
        read -r -t "$MENU_TIMEOUT" CHOICE </dev/console 2>/dev/null || true

        case "$CHOICE" in
            1|"linux"|"")     SELECTED="linux"      ;;
            2|"android-a")   SELECTED="android-a"  ;;
            3|"android-b")   SELECTED="android-b"  ;;
            4|"gsi")         SELECTED="gsi"         ;;
            5|"recovery-a")  SELECTED="recovery-a" ;;
            6|"recovery-b")  SELECTED="recovery-b" ;;
            *)
                echo "" >/dev/console
                echo "  Unknown choice '${CHOICE}' — please try again." \
                     >/dev/console
                continue
                ;;
        esac
        break
    done

    echo "" >/dev/console
    echo "boot-selector[menu]: selected → ${SELECTED}" >/dev/console

    # shellcheck disable=SC1090
    . "/boot-targets/${SELECTED}.sh"
    run_target
}
