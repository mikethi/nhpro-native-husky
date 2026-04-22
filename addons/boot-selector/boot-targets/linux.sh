#!/bin/sh
# boot-targets/linux.sh – NetHunter Pro (Linux) boot target
# Google Pixel 8 Pro (husky / zuma)
#
# Default target.  Extracts the embedded real initrd (stored as
# /real-initrd.cpio.gz by build.sh) on top of the current tmpfs, then
# execs the real /init to continue the normal NetHunter Pro boot sequence.
#
# No kexec needed – this is a straight handoff to the existing initrd.

run_target() {
    echo "boot-selector[linux]: loading NetHunter Pro initrd" >/dev/console

    if [ -f /real-initrd.cpio.gz ]; then
        gzip -cd /real-initrd.cpio.gz | \
            cpio --extract --make-directories \
                 --no-absolute-filenames \
                 --preserve-modification-time 2>/dev/null
    elif [ -f /real-initrd.cpio ]; then
        cpio --extract --make-directories \
             --no-absolute-filenames \
             --preserve-modification-time < /real-initrd.cpio 2>/dev/null
    else
        echo "boot-selector[linux]: WARNING – real-initrd not found; continuing anyway" >/dev/console
    fi

    echo "boot-selector[linux]: exec real /init" >/dev/console
    # exec replaces this process; the real init takes over as PID 1
    exec /init "$@"
}
