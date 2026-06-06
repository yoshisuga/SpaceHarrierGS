#!/bin/sh
set -e
DISK="${1:-./SpaceHarrier.2mg}"
MERLIN="./Merlin32-1.1"
CADIUS="./cadius"
MACROS="./macros"
APP_NAME="SpaceHarrier"
APP_PATH="$(pwd)/$APP_NAME"
SRC="$HOME/Downloads/SpaceHarrierGSSource/Space.Harrier"

echo "==> Assembling..."
$MERLIN -V $MACROS App.s

echo "==> Updating app binary on disk: $DISK"
$CADIUS DELETEFILE "$DISK" /s/$APP_NAME 2>/dev/null || true
$CADIUS ADDFILE    "$DISK" /s "$APP_PATH"

echo "==> Syncing asset folders..."
# Create subdirs (silent if already exist)
$CADIUS CREATEFOLDER "$DISK" /s/MUS    2>/dev/null || true
$CADIUS CREATEFOLDER "$DISK" /s/PIC    2>/dev/null || true
$CADIUS CREATEFOLDER "$DISK" /s/PIC2   2>/dev/null || true
$CADIUS CREATEFOLDER "$DISK" /s/DRAGON 2>/dev/null || true

# Helper: delete-then-add a file (idempotent re-deploy)
add() {
    $CADIUS DELETEFILE "$DISK" "$2" 2>/dev/null || true
    $CADIUS ADDFILE    "$DISK" "$3" "$1"
}

# Root assets
add "$SRC/MOUNT"     /s/MOUNT     /s
add "$SRC/SHAPE.RUN" /s/SHAPE.RUN /s
add "$SRC/SIDEBAR"   /s/SIDEBAR   /s

# Music
add "$SRC/MUS/BLUE.WBNK"   /s/MUS/BLUE.WBNK   /s/MUS
add "$SRC/MUS/BLUE.MONDAY"  /s/MUS/BLUE.MONDAY  /s/MUS

# Shapes — PIC
add "$SRC/PIC/TREE.SHAPE"   /s/PIC/TREE.SHAPE   /s/PIC
add "$SRC/PIC/EXPLO.SHP"    /s/PIC/EXPLO.SHP    /s/PIC
add "$SRC/PIC/TIR.SHP"      /s/PIC/TIR.SHP      /s/PIC
add "$SRC/PIC/PIERRE.SHP"   /s/PIC/PIERRE.SHP   /s/PIC
add "$SRC/PIC/NUM.SHP"      /s/PIC/NUM.SHP      /s/PIC
add "$SRC/PIC/OMBRE.SHP"    /s/PIC/OMBRE.SHP    /s/PIC
add "$SRC/PIC/BUISSON.SHP"  /s/PIC/BUISSON.SHP  /s/PIC
add "$SRC/PIC/ROBOT.SHP"   /s/PIC/ROBOT.SHP    /s/PIC

# Shapes — PIC2
add "$SRC/PIC2/SHIP.SHP"    /s/PIC2/SHIP.SHP    /s/PIC2
add "$SRC/PIC2/TRIDENT.SHP" /s/PIC2/TRIDENT.SHP /s/PIC2
add "$SRC/PIC2/DIVERS.SHP"  /s/PIC2/DIVERS.SHP  /s/PIC2

# Shapes — DRAGON
add "$SRC/DRAGON/FACE.SHP"  /s/DRAGON/FACE.SHP  /s/DRAGON
add "$SRC/DRAGON/DER.SHP"   /s/DRAGON/DER.SHP   /s/DRAGON
add "$SRC/DRAGON/MID.SHP"   /s/DRAGON/MID.SHP   /s/DRAGON
add "$SRC/DRAGON/BACK.SHP"  /s/DRAGON/BACK.SHP  /s/DRAGON

# echo "==> Copying disk image to iCloud Drive..."
# cp "$DISK" "$HOME/Library/Mobile Documents/com~apple~CloudDocs/SpaceHarrier.2mg"

echo "==> Done. $APP_NAME + assets on the disk."
