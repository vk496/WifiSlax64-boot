#!/bin/bash

### ROOT ###

if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

### ROOT ###

### DEPENDENCIAS ###

DEPENDENCIAS=( grub-mkimage mkdosfs makeself )
EXIT=1

for var in "${DEPENDENCIAS[@]}"; do
	if ! hash $var 2>/dev/null; then
		echo "$var not installed"
		EXIT=0
	fi
done

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


### RUTA ###

if [ $# -gt 1 ]; then
	echo "Ilegar number of arguments"
	exit 1
else

	if [ $# -eq 1 ] && [[ -d $1 ]]; then
		OUTPUT=$(mktemp -d)
		FINAL_OUTPUT=$1
	else
		echo -e "You can set a target folder with the first argument\n"
		OUTPUT=$DIR/ISO_BOOT
	fi

fi

### RUTA ###


### Create final directory ###

if [ $OUTPUT = $DIR/ISO_BOOT ]; then
	rm -Rf $OUTPUT
	mkdir -p $OUTPUT
else
	if [[ -d $FINAL_OUTPUT/boot ]]; then
		num=$RANDOM
		echo "boot alredy exists in $FINAL_OUTPUT. Backup folder to boot_$num"
		mv $FINAL_OUTPUT/boot $FINAL_OUTPUT/boot_$num
	fi

	if [[ -d $FINAL_OUTPUT/EFI ]]; then
		num=$RANDOM
		echo "EFI alredy exists in $FINAL_OUTPUT. Backup folder to EFI_$num"
		mv $FINAL_OUTPUT/EFI $FINAL_OUTPUT/EFI_$num
	fi

	if [ $num ]; then
		echo
	fi
fi

cp -R $DIR/ISO/* $OUTPUT

### Create final directory ###



### Initrd ###
echo -en "Initrd .."
find $OUTPUT/boot/initrd | cpio -o -H newc 2>/dev/null | xz -z -9 --check=crc32 > $OUTPUT/boot/initrd.xz >/dev/null

if [[ ${PIPESTATUS[2]} -eq 0 ]] && [[ ${PIPESTATUS[2]} -eq 0 ]]; then
	echo -e "\t\tok"
else
	echo -e "\t\terror"
	exit 1
fi

rm -Rf $OUTPUT/boot/initrd

### Initrd ###


### EFI ###

# Generamos la imagen EFI
echo -en "UEFI loader .."
EXIT=0

#Shim loader signed by Microsoft
mv $OUTPUT/EFI/BOOT/shimx64.efi.signed $OUTPUT/EFI/BOOT/bootx64.efi; let EXIT=$EXIT+$?

mv $OUTPUT/EFI/BOOT/MokManager.efi.signed $OUTPUT/EFI/BOOT/MokManager.efi; let EXIT=$EXIT+$?

#Process to generate grub loader. We dont generate it because is signed by Wifislax Team :)

#grub-mkimage --format=x86_64-efi --output=grubx64.efi --config=grub-embedded.cfg --compression=xz --prefix=/EFI/BOOT all_video appleldr at_keyboard bitmap_scale boot cat chain configfile echo efi_gop efi_uga ext2 fat font gfxmenu gfxterm gzio halt help hfs hfsplus iso9660 jpeg linux linuxefi loadbios loadenv ls minicmd normal part_gpt part_msdos png probe reboot regexp search search_fs_file search_fs_uuid search_label test tga true udf ufs1 ufs2 usb_keyboard zfs
#sbsign --key wifislax.key --cert wifislax.crt --output grubx64.efi.signed grubx64.efi
#rm grubx64.efi

#Grub signed by Wifislax Team :)
mv $OUTPUT/EFI/BOOT/grubx64.efi.signed $OUTPUT/EFI/BOOT/grubx64.efi; let EXIT=$EXIT+$?

if [ $EXIT -eq 0 ]; then
	echo -e "\t\tok"
else
	echo -e "\t\terror"
	exit 1
fi

#Creamos el efiboot.img
echo -en "efiboot.img .."
EXIT=0

dd if=/dev/zero of=$OUTPUT/EFI/BOOT/efiboot.img bs=1K count=4320 2>/dev/null; let EXIT=$EXIT+$?
mkdosfs -F 12 $OUTPUT/EFI/BOOT/efiboot.img >/dev/null; let EXIT=$EXIT+$?
MOUNTPOINT=$(mktemp -d); let EXIT=$EXIT+$?
mount -o loop $OUTPUT/EFI/BOOT/efiboot.img $MOUNTPOINT; let EXIT=$EXIT+$?
mkdir -p $MOUNTPOINT/EFI/BOOT; let EXIT=$EXIT+$?
cp -a $OUTPUT/EFI/BOOT/bootx64.efi $MOUNTPOINT/EFI/BOOT; let EXIT=$EXIT+$?
cp -a $OUTPUT/EFI/BOOT/MokManager.efi $MOUNTPOINT/EFI/BOOT; let EXIT=$EXIT+$?
cp -a $OUTPUT/EFI/BOOT/grubx64.efi $MOUNTPOINT/EFI/BOOT; let EXIT=$EXIT+$?
umount $MOUNTPOINT; let EXIT=$EXIT+$?
rmdir $MOUNTPOINT; let EXIT=$EXIT+$?
mv $OUTPUT/EFI/BOOT/efiboot.img $OUTPUT/boot/syslinux/; let EXIT=$EXIT+$?

if [ $EXIT -eq 0 ]; then
	echo -e "\t\tok"
else
	echo -e "\t\terror"
	exit 1
fi

### EFI ###


### Linux installer ###
echo -en "Linux installer .."
EXIT=0

mkdir -p $OUTPUT/boot/tmp; let EXIT=$EXIT+$?
mv $OUTPUT/boot/wifislax_bootloader_installer $OUTPUT/boot/tmp/.wifislax_bootloader_installer; let EXIT=$EXIT+$?

makeself --target . --notemp $OUTPUT/boot/tmp/ $OUTPUT/boot/Linux_Wifislax_Boot_Installer.com "Wifislax Bootloader Installer" ".wifislax_bootloader_installer/installer.com" &>/dev/null; let EXIT=$EXIT+$?

if [ $EXIT -eq 0 ]; then
	echo -e "\tok"
else
	echo -e "\terror"
	exit 1
fi

chmod 444 $OUTPUT/boot/Linux_Wifislax_Boot_Installer.com

rm -Rf $OUTPUT/boot/tmp

### Linux installer ###


### Copy if path specified ###

if [ $FINAL_OUTPUT ]; then
	cp -Rf $OUTPUT/* $FINAL_OUTPUT/
	rm -Rf $OUTPUT
else

FINAL_OUTPUT=$OUTPUT

fi

### Copy if path specified ###


echo -e "\nBOOT FOLDER: $FINAL_OUTPUT"
