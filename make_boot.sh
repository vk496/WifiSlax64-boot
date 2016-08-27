#!/bin/bash

### ROOT ###

if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

### ROOT ###

### DEPENDENCIAS ###

EXIT=1

if ! hash grub-mkimage 2>/dev/null; then
	echo "grub-mkimage not installed"
	EXIT=0
fi

if ! hash mkdosfs 2>/dev/null; then
	echo "mkdosfs not installed"
	EXIT=0
fi


if [ $EXIT -eq 0 ]; then
	exit 1
fi

### DEPENDENCIAS ###

############## Obtener ruta absoluta del directorio donde nos encontramos ##############

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  TARGET="$(readlink "$SOURCE")"
  if [[ $TARGET == /* ]]; then
    SOURCE="$TARGET"
  else
    DIR="$( dirname "$SOURCE" )" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
  fi
done

DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )" #Carpeta ubicada

# Fuente: http://stackoverflow.com/questions/59895/can-a-bash-script-tell-which-directory-it-is-stored-in

############## Obtener ruta absoluta del directorio donde nos encontramos ##############



### Create final directory ###

rm -Rf $DIR/ISO_BOOT
mkdir -p $DIR/ISO_BOOT
cp -R $DIR/ISO/* $DIR/ISO_BOOT

### Create final directory ###



### Initrd ###
echo -en "Initrd .."
find $DIR/ISO_BOOT/boot/initrd | cpio -o -H newc 2>/dev/null | xz -z -9 --check=crc32 > $DIR/ISO_BOOT/boot/initrd.xz >/dev/null

if [[ ${PIPESTATUS[2]} -eq 0 ]] && [[ ${PIPESTATUS[2]} -eq 0 ]]; then
	echo -e "\tok"
else
	echo -e "\terror"
	exit 1
fi

rm -Rf $DIR/ISO_BOOT/boot/initrd

### Initrd ###


### EFI ###

# Generamos la imagen EFI
echo -en "UEFI loader .."

grub-mkimage --format=x86_64-efi --output=$DIR/ISO_BOOT/EFI/BOOT/bootx64.efi --config=$DIR/ISO_BOOT/EFI/BOOT/grub-embedded.cfg --compression=xz --prefix=/EFI/BOOT part_gpt part_msdos fat ext2 hfs hfsplus iso9660 udf ufs1 ufs2 zfs chain linux boot appleldr ahci configfile normal regexp minicmd reboot halt search search_fs_file search_fs_uuid search_label gfxterm gfxmenu efi_gop efi_uga all_video loadbios gzio echo true probe loadenv bitmap_scale font cat help ls png jpeg tga test at_keyboard usb_keyboard >/dev/null

if [ $? -eq 0 ]; then
	echo -e "\tok"
else
	echo -e "\terror"
	exit 1
fi

#Creamos el efiboot.img
echo -en "efiboot.img .."
EXIT=0

dd if=/dev/zero of=$DIR/ISO_BOOT/EFI/BOOT/efiboot.img bs=1K count=1440 2>/dev/null; let EXIT=$EXIT+$?
mkdosfs -F 12 $DIR/ISO_BOOT/EFI/BOOT/efiboot.img >/dev/null; let EXIT=$EXIT+$?
MOUNTPOINT=$(mktemp -d); let EXIT=$EXIT+$?
mount -o loop $DIR/ISO_BOOT/EFI/BOOT/efiboot.img $MOUNTPOINT; let EXIT=$EXIT+$?
mkdir -p $MOUNTPOINT/EFI/BOOT; let EXIT=$EXIT+$?
cp -a $DIR/ISO_BOOT/EFI/BOOT/bootx64.efi $MOUNTPOINT/EFI/BOOT; let EXIT=$EXIT+$?
umount $MOUNTPOINT; let EXIT=$EXIT+$?
rmdir $MOUNTPOINT; let EXIT=$EXIT+$?
mv $DIR/ISO_BOOT/EFI/BOOT/efiboot.img $DIR/ISO_BOOT/boot/syslinux/; let EXIT=$EXIT+$?

if [ $EXIT -eq 0 ]; then
	echo -e "\tok"
else
	echo -e "\terror"
	exit 1
fi

### EFI ###
