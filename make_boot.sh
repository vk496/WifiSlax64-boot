#!/bin/bash

### ROOT ###

if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

### ROOT ###


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

find $DIR/ISO_BOOT/boot/initrd | cpio -o -H newc | xz -z -9 --check=crc32 > $DIR/ISO_BOOT/boot/initrd.xz
rm -Rf $DIR/ISO_BOOT/boot/initrd

### Initrd ###




### EFI ###

# Generamos la imagen EFI
grub-mkimage --format=x86_64-efi --output=$DIR/ISO_BOOT/EFI/BOOT/bootx64.efi --config=$DIR/ISO_BOOT/EFI/BOOT/grub-embedded.cfg --compression=xz --prefix=/EFI/BOOT part_gpt part_msdos fat ext2 hfs hfsplus iso9660 udf ufs1 ufs2 zfs chain linux boot appleldr ahci configfile normal regexp minicmd reboot halt search search_fs_file search_fs_uuid search_label gfxterm gfxmenu efi_gop efi_uga all_video loadbios gzio echo true probe loadenv bitmap_scale font cat help ls png jpeg tga test at_keyboard usb_keyboard

if [ $? -ne 0 ]; then
	echo "La imagen EFI no se generó correctamente"
	exit 1
fi

#Creamos el efiboot.img
dd if=/dev/zero of=$DIR/ISO_BOOT/EFI/BOOT/efiboot.img bs=1K count=1440
mkdosfs -F 12 $DIR/ISO_BOOT/EFI/BOOT/efiboot.img
MOUNTPOINT=$(mktemp -d)
mount -o loop $DIR/ISO_BOOT/EFI/BOOT/efiboot.img $MOUNTPOINT
mkdir -p $MOUNTPOINT/EFI/BOOT
cp -a $DIR/ISO_BOOT/EFI/BOOT/bootx64.efi $MOUNTPOINT/EFI/BOOT
umount $MOUNTPOINT
rmdir $MOUNTPOINT
mv $DIR/ISO_BOOT/EFI/BOOT/efiboot.img $DIR/ISO_BOOT/boot/syslinux/


### EFI ###
