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


