#!/bin/bash

# Check if exactly three arguments are provided
if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <iso_path> <ks_file> <output_iso>"
  echo "Example: $0 Rocky-9.5-x86_64-dvd.iso ks-server.cfg Rocky-9.5-server-kickstart.iso"
  exit 1
fi

# Configuration
ISO_PATH="$1"
KS_FILE="$2"
OUTPUT_ISO="$3"
WORK_DIR="work"
MOUNT_DIR="/mnt/iso"

# Check if ISO and Kickstart file exist
if [ ! -f "$ISO_PATH" ]; then
  echo "Error: ISO file $ISO_PATH not found."
  exit 1
fi
if [ ! -f "$KS_FILE" ]; then
  echo "Error: Kickstart file $KS_FILE not found."
  exit 1
fi

# Get ISO label
ISO_LABEL=$(blkid -o value -s LABEL "$ISO_PATH")
if [ -z "$ISO_LABEL" ]; then
  echo "Error: Could not determine ISO label."
  exit 1
fi
echo "Detected ISO label: $ISO_LABEL"

# Create and clean work directory
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

# Mount ISO and copy contents
sudo mkdir -p "$MOUNT_DIR"
sudo mount -o loop "$ISO_PATH" "$MOUNT_DIR"
sudo rsync -av "$MOUNT_DIR/" "$WORK_DIR/"
sudo umount "$MOUNT_DIR"
sudo rmdir "$MOUNT_DIR"

# Copy Kickstart file
cp "$KS_FILE" "$WORK_DIR/ks.cfg"

# Set permissions
sudo chmod -R u+rw "$WORK_DIR"

# Update isolinux.cfg for BIOS
cat << EOF > "$WORK_DIR/isolinux/isolinux.cfg"
default kickstart
timeout 0

menu background splash.png
menu title Rocky Linux 9.5 Installation
menu vshift 8
menu rows 18
menu margin 8
menu helpmsgrow 15
menu tabmsgrow 13
menu cmdlinerow 13
menu endrow -2
menu passwordrow 11
menu timeoutrow 10
menu color border 0 #00000000 #00000000 none
menu color sel 7 #ffffffff #ff000000 none
menu color hotsel 0 #ff000000 #ffffffff none
menu color tabmsg 0 #ff000000 #ffffffff none
menu color unsel 0 #ff000000 #ffffffff none
menu color hotkey 7 #ffffffff #ff000000 none
menu color help 0 #ff000000 #ffffffff none
menu color scrollbar 0 #ff000000 #ffffffff none
menu color timeout 0 #ff000000 #ffffffff none
menu color timeout_msg 0 #ff000000 #ffffffff none
menu color cmdmark 0 #ff000000 #ffffffff none
menu color cmdline 0 #ff000000 #ffffffff none

label linux
  menu label ^Install Rocky Linux 9.5
  kernel vmlinuz
  append initrd=initrd.img inst.stage2=hd:LABEL=$ISO_LABEL quiet

label kickstart
  menu label ^Install Rocky Linux 9.5 Server with Kickstart
  kernel vmlinuz
  append initrd=initrd.img inst.stage2=hd:LABEL=$ISO_LABEL inst.ks=hd:LABEL=$ISO_LABEL:/ks.cfg

label check
  menu label ^Check media and install Rocky Linux 9.5
  kernel vmlinuz
  append initrd=initrd.img inst.stage2=hd:LABEL=$ISO_LABEL rd.live.check quiet
EOF

# Update grub.cfg for UEFI
cat << EOF > "$WORK_DIR/EFI/BOOT/grub.cfg"
set default="1"
set timeout=0

menuentry 'Install Rocky Linux 9.5' {
  linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=$ISO_LABEL quiet
  initrdefi /images/pxeboot/initrd.img
}

menuentry 'Install Rocky Linux 9.5 Server with Kickstart' --class rocky {
  linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=$ISO_LABEL inst.ks=hd:LABEL=$ISO_LABEL:/ks.cfg
  initrdefi /images/pxeboot/initrd.img
}

menuentry 'Test this media & install Rocky Linux 9.5' {
  linuxefi /images/pxeboot/vmlinuz inst.stage2=hd:LABEL=$ISO_LABEL rd.live.check quiet
  initrdefi /images/pxeboot/initrd.img
}
EOF

# Run genisoimage
genisoimage -o "$OUTPUT_ISO" -b isolinux/isolinux.bin -c isolinux/boot.cat --no-emul-boot --boot-load-size 4 --boot-info-table -J -R -V "$ISO_LABEL" -eltorito-alt-boot -e images/efiboot.img -no-emul-boot "$WORK_DIR/"

# Check if ISO was created
if [ -f "$OUTPUT_ISO" ]; then
  echo "ISO created successfully: $OUTPUT_ISO"
else
  echo "Error: Failed to create ISO."
  exit 1
fi
