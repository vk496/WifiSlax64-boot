#!/bin/bash
# Porteus installation script by fanthom.
# Modified for wifislax thanks to fanthom

# Colores
CIERRE=${CIERRE:-"[0m"}
ROJO=${ROJO:-"[1;31m"}
VERDE=${VERDE:-"[1;32m"}
CYAN=${CYAN:-"[1;36m"}
AMARILLO=${AMARILLO:-"[1;33m"}
BLANCO=${BLANCO:-"[1;37m"}
ROSA=${ROSA:-"[1;35m"}

function check(){
if [ ! `which $1` ]; then echo "$1" >> /tmp/.sanity; fi
}

check grep
check sed
check sfdisk

## Failed sanity check
if [ -f /tmp/.sanity ]; then
	clear
	echo "Se necesitan las siguientes herramientas en su sistema:"
	echo
	cat /tmp/.sanity
	echo
	echo "Por favor instale  lo necesario y ejecute de nuevo el instalador."
	rm /tmp/.sanity
	sleep 1
	rm -rf $bin 2>/dev/null
	exit
fi

# Allow only root:
if [ `whoami` != root ]; then
    echo
    echo "El instalador necesita privilegio root"
    sleep 1
    rm -rf $bin 2>/dev/null
    exit
fi

PRT=`df -h . | tail -n1 | cut -d" " -f1`
echo "$PRT" | grep -q mmcblk && PRTN=`echo $PRT | sed s/[^p1-9]*//` || PRTN=`echo $PRT | sed s/[^1-9]*//`
[ "$PRTN" ] && DEV=`echo $PRT | sed s/$PRTN//` || DEV=$PRT
MPT=`df -h . | tail -n1 | cut -d% -f2 | cut -d" " -f2-`
IPT=`pwd`
PTH=`echo "$IPT" | sed s^"$MPT"^^ | rev | cut -d/ -f2- | rev`
FS=`grep -w $PRT /proc/mounts | head -n1 | cut -d" " -f3`
bin="$IPT/.wifislax_boot_installer"
log="$IPT/debug.txt"

# 'debug' function:
debug() {
[ "$LOADER" ] || LOADER=lilo
cat << ENDOFTEXT > "$log"
device: $DEV
partition: $PRT
partition number: $PRTN
partition mount point: $MPT
installation path: $IPT
subfolder: $PTH
filesystem: $FS
bootloader: $LOADER
error code: $1
system: `uname -n` `uname -r` `uname -m`
mount details: `grep -w "^$PRT" /proc/mounts`
full partition scheme:
`fdisk -l`

ENDOFTEXT
[ $LOADER = lilo -a "$1" ] && cat "$lilo_menu" >> "$log"
}

# 'fail_check' function:
fail_check() {
if [ $? -ne 0 ]; then
    echo
    echo 'La instalacion fallo con el codigo '"'$1'"'.'
    echo 'Por favor pregunta en el foro www.seguridadwireless.net'
    echo 'y postea la informacion '$log''
    echo
    echo 'Saliendo...'
    sleep 1
    rm -rf $bin 2>/dev/null
    debug $1
    exit $1
fi
}

# Set trap:
trap 'echo "Exited installer."; rm -rf $bin; exit 6' 1 2 3 9 15

clear
echo $VERDE
echo '                                                  
__        _____ _____ ___ ____  _        _   __  __
\ \      / |_ _|  ___|_ _/ ___|| |      / \  \ \/ /
 \ \ /\ / / | || |_   | |\___ \| |     / _ \  \  / 
  \ V  V /  | ||  _|  | | ___) | |___ / ___ \ /  \ 
   \_/\_/  |___|_|   |___|____/|_____/_/   \_/_/\_\'
echo 
echo "          $ROSA <<< $AMARILLO Bootloader Installer $ROSA >>>"
echo $CIERRE                                                  
echo "Este instalador hara $TARGET booteable para Wifislax."
if [ "$MBR" != "$TARGET" ]; then
   echo $AMARILLO
   echo "Alerta!"
   echo $CIERRE
   echo "El master boot record (MBR) de ${VERDE}$MBR${CIERRE} sera sobreescrito."
   echo "Solo Wifislax sera booteable en este dispositivo."
fi
echo
echo "Presiona ${CYAN}ENTER${CIERRE} para continuar, o ${ROJO}Ctrl+C${CIERRE} para salir..."
read junk

echo
echo "Flushing filesystem buffers..."
sync

if [ "$PRTN" ]; then
    # Setup MBR:
    dd if=$bin/mbr.bin of=$DEV bs=440 count=1 conv=notrunc >/dev/null 2>&1
    fail_check 1

    # Make partition active:
    sfdisk -A $DEV $PRTN >/dev/null 2>&1
    fail_check 2
fi


if echo "$FS" | egrep -q 'ext|vfat|msdos|ntfs|fuseblk|btrfs'; then
    echo
    echo "Usando extlinux bootloader..."
    LOADER=extlinux
else
    echo
    echo "Sistema de ficheros no soportado por favor usa uno de estos 'ext|vfat|msdos|ntfs|fuseblk|btrfs'"
    exit 0
fi



# Install extlinux:
$bin/extlinux.com -i "$IPT"/syslinux >/dev/null 2>&1
fail_check 3

# Delete installator files:
rm -rf $bin 2>/dev/null

echo "$VERDE"
echo "Instalacion completada con exito."
echo "$CERRAR"

exit 0
