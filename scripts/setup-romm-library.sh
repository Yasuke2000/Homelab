#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# setup-romm-library.sh
#
# Creates the RomM library folder structure on Synology NAS.
# Run via SSH:
#   ssh nas 'bash -s' < scripts/setup-romm-library.sh
#
# Or from repo root:
#   ssh hackerman@10.0.20.14 'bash -s' < scripts/setup-romm-library.sh
# ---------------------------------------------------------------------------

set -euo pipefail

LIBRARY="/volume1/roms"

echo "Creating RomM library at $LIBRARY..."

# Platforms playable in browser via EmulatorJS
for p in snes gba n64 psx nes gb gbc nds segaMD segaMS segaGG sega32x segaCD pce atari2600 atari7800 lynx arcade ws ngp psp; do
  mkdir -p "$LIBRARY/roms/$p"
done

# Platforms NOT playable in browser (native emulator only)
for p in saturn 3ds; do
  mkdir -p "$LIBRARY/roms/$p"
done

# BIOS directories (only platforms that need them)
for p in psx segaCD segaSaturn pce 3do lynx; do
  mkdir -p "$LIBRARY/bios/$p"
done

chmod -R 777 "$LIBRARY"
chown -R 1024:100 "$LIBRARY" 2>/dev/null || true

echo ""
echo "Done! Structure created:"
find "$LIBRARY" -maxdepth 2 -type d | sort

echo ""
echo "Next steps:"
echo "  - Add ROMs to $LIBRARY/roms/{platform}/"
echo "  - PS1 BIOS: place scph1001.bin in $LIBRARY/bios/psx/"
echo "  - Then scan: romm.daviddelporte.com → Settings → Scan"
echo ""
echo "Platforms with EmulatorJS browser play:"
echo "  snes, gba, n64, psx, nes, gb, gbc, nds, segaMD, psp, arcade, ..."
