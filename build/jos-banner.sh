#!/bin/sh
# JOS boot banner. Installed into the initrd as /jos-banner.sh and run by /init
# before handing over to the FOS userland. ASCII only: it must render on a
# serial console, a laptop panel, and GRUB without a font dependency.

VERSION="$(cat /etc/jos-version 2>/dev/null || echo unknown)"

if [ -r /etc/jos-logo.txt ]; then
  cat /etc/jos-logo.txt
else
  echo "JOS"
fi

printf '\n  JOS - Jonathan'\''s OS  %s\n' "$VERSION"
printf '  Secure Boot imaging runtime for FOG\n\n'
