#!/bin/sh
# This script was generated using Makeself 2.2.0

umask 077

CRCsum="1905609867"
MD5="b3749cd6a2f38aa005219d9b70b07846"
TMPROOT=${TMPDIR:=/tmp}

label="Wifislax Bootloader Installer"
script=".wifislax_bootloader_installer/bootinst.com;/bin/bash"
scriptargs=""
licensetxt=""
targetdir="."
filesizes="491520"
keep="y"
quiet="n"

print_cmd_arg=""
if type printf > /dev/null; then
    print_cmd="printf"
elif test -x /usr/ucb/echo; then
    print_cmd="/usr/ucb/echo"
else
    print_cmd="echo"
fi

unset CDPATH

MS_Printf()
{
    $print_cmd $print_cmd_arg "$1"
}

MS_PrintLicense()
{
  if test x"$licensetxt" != x; then
    echo $licensetxt
    while true
    do
      MS_Printf "Please type y to accept, n otherwise: "
      read yn
      if test x"$yn" = xn; then
        keep=n
 	eval $finish; exit 1        
        break;    
      elif test x"$yn" = xy; then
        break;
      fi
    done
  fi
}

MS_diskspace()
{
	(
	if test -d /usr/xpg4/bin; then
		PATH=/usr/xpg4/bin:$PATH
	fi
	df -kP "$1" | tail -1 | awk '{ if ($4 ~ /%/) {print $3} else {print $4} }'
	)
}

MS_dd()
{
    blocks=`expr $3 / 1024`
    bytes=`expr $3 % 1024`
    dd if="$1" ibs=$2 skip=1 obs=1024 conv=sync 2> /dev/null | \
    { test $blocks -gt 0 && dd ibs=1024 obs=1024 count=$blocks ; \
      test $bytes  -gt 0 && dd ibs=1 obs=1024 count=$bytes ; } 2> /dev/null
}

MS_dd_Progress()
{
    if test "$noprogress" = "y"; then
        MS_dd $@
        return $?
    fi
    file="$1"
    offset=$2
    length=$3
    pos=0
    bsize=4194304
    while test $bsize -gt $length; do
        bsize=`expr $bsize / 4`
    done
    blocks=`expr $length / $bsize`
    bytes=`expr $length % $bsize`
    (
        dd bs=$offset count=0 skip=1 2>/dev/null
        pos=`expr $pos \+ $bsize`
        MS_Printf "     0%% " 1>&2
        if test $blocks -gt 0; then
            while test $pos -le $length; do
                dd bs=$bsize count=1 2>/dev/null
                pcent=`expr $length / 100`
                pcent=`expr $pos / $pcent`
                if test $pcent -lt 100; then
                    MS_Printf "\b\b\b\b\b\b\b" 1>&2
                    if test $pcent -lt 10; then
                        MS_Printf "    $pcent%% " 1>&2
                    else
                        MS_Printf "   $pcent%% " 1>&2
                    fi
                fi
                pos=`expr $pos \+ $bsize`
            done
        fi
        if test $bytes -gt 0; then
            dd bs=$bytes count=1 2>/dev/null
        fi
        MS_Printf "\b\b\b\b\b\b\b" 1>&2
        MS_Printf " 100%%  " 1>&2
    ) < "$file"
}

MS_Help()
{
    cat << EOH >&2
Makeself version 2.2.0
 1) Getting help or info about $0 :
  $0 --help   Print this message
  $0 --info   Print embedded info : title, default target directory, embedded script ...
  $0 --lsm    Print embedded lsm entry (or no LSM)
  $0 --list   Print the list of files in the archive
  $0 --check  Checks integrity of the archive
 
 2) Running $0 :
  $0 [options] [--] [additional arguments to embedded script]
  with following options (in that order)
  --confirm             Ask before running embedded script
  --quiet		Do not print anything except error messages
  --noexec              Do not run embedded script
  --keep                Do not erase target directory after running
			the embedded script
  --noprogress          Do not show the progress during the decompression
  --nox11               Do not spawn an xterm
  --nochown             Do not give the extracted files to the current user
  --target dir          Extract directly to a target directory
                        directory path can be either absolute or relative
  --tar arg1 [arg2 ...] Access the contents of the archive through the tar command
  --                    Following arguments will be passed to the embedded script
EOH
}

MS_Check()
{
    OLD_PATH="$PATH"
    PATH=${GUESS_MD5_PATH:-"$OLD_PATH:/bin:/usr/bin:/sbin:/usr/local/ssl/bin:/usr/local/bin:/opt/openssl/bin"}
	MD5_ARG=""
    MD5_PATH=`exec <&- 2>&-; which md5sum || type md5sum`
    test -x "$MD5_PATH" || MD5_PATH=`exec <&- 2>&-; which md5 || type md5`
	test -x "$MD5_PATH" || MD5_PATH=`exec <&- 2>&-; which digest || type digest`
    PATH="$OLD_PATH"

    if test "$quiet" = "n";then
    	MS_Printf "Verifying archive integrity..."
    fi
    offset=`head -n 502 "$1" | wc -c | tr -d " "`
    verb=$2
    i=1
    for s in $filesizes
    do
		crc=`echo $CRCsum | cut -d" " -f$i`
		if test -x "$MD5_PATH"; then
			if test `basename $MD5_PATH` = digest; then
				MD5_ARG="-a md5"
			fi
			md5=`echo $MD5 | cut -d" " -f$i`
			if test $md5 = "00000000000000000000000000000000"; then
				test x$verb = xy && echo " $1 does not contain an embedded MD5 checksum." >&2
			else
				md5sum=`MS_dd "$1" $offset $s | eval "$MD5_PATH $MD5_ARG" | cut -b-32`;
				if test "$md5sum" != "$md5"; then
					echo "Error in MD5 checksums: $md5sum is different from $md5" >&2
					exit 2
				else
					test x$verb = xy && MS_Printf " MD5 checksums are OK." >&2
				fi
				crc="0000000000"; verb=n
			fi
		fi
		if test $crc = "0000000000"; then
			test x$verb = xy && echo " $1 does not contain a CRC checksum." >&2
		else
			sum1=`MS_dd "$1" $offset $s | CMD_ENV=xpg4 cksum | awk '{print $1}'`
			if test "$sum1" = "$crc"; then
				test x$verb = xy && MS_Printf " CRC checksums are OK." >&2
			else
				echo "Error in checksums: $sum1 is different from $crc" >&2
				exit 2;
			fi
		fi
		i=`expr $i + 1`
		offset=`expr $offset + $s`
    done
    if test "$quiet" = "n";then
    	echo " All good."
    fi
}

UnTAR()
{
    if test "$quiet" = "n"; then
    	tar $1vf - 2>&1 || { echo Extraction failed. > /dev/tty; kill -15 $$; }
    else

    	tar $1f - 2>&1 || { echo Extraction failed. > /dev/tty; kill -15 $$; }
    fi
}

finish=true
xterm_loop=
noprogress=n
nox11=n
copy=none
ownership=y
verbose=n

initargs="$@"

while true
do
    case "$1" in
    -h | --help)
	MS_Help
	exit 0
	;;
    -q | --quiet)
	quiet=y
	noprogress=y
	shift
	;;
    --info)
	echo Identification: "$label"
	echo Target directory: "$targetdir"
	echo Uncompressed size: 492 KB
	echo Compression: none
	echo Date of packaging: Fri May 27 17:23:54 CEST 2016
	echo Built with Makeself version 2.2.0 on linux-gnu
	echo Build command was: "/usr/bin/makeself.sh \\
    \"--notemp\" \\
    \"--nocomp\" \\
    \"--target\" \\
    \".\" \\
    \"./\" \\
    \"/root/Desktop/Linux_Wifislax_Boot_Installer.com\" \\
    \"Wifislax Bootloader Installer\" \\
    \".wifislax_bootloader_installer/bootinst.com;/bin/bash\""
	if test x$script != x; then
	    echo Script run after extraction:
	    echo "    " $script $scriptargs
	fi
	if test x"" = xcopy; then
		echo "Archive will copy itself to a temporary location"
	fi
	if test x"y" = xy; then
	    echo "directory $targetdir is permanent"
	else
	    echo "$targetdir will be removed after extraction"
	fi
	exit 0
	;;
    --dumpconf)
	echo LABEL=\"$label\"
	echo SCRIPT=\"$script\"
	echo SCRIPTARGS=\"$scriptargs\"
	echo archdirname=\".\"
	echo KEEP=y
	echo COMPRESS=none
	echo filesizes=\"$filesizes\"
	echo CRCsum=\"$CRCsum\"
	echo MD5sum=\"$MD5\"
	echo OLDUSIZE=492
	echo OLDSKIP=503
	exit 0
	;;
    --lsm)
cat << EOLSM
No LSM.
EOLSM
	exit 0
	;;
    --list)
	echo Target directory: $targetdir
	offset=`head -n 502 "$0" | wc -c | tr -d " "`
	for s in $filesizes
	do
	    MS_dd "$0" $offset $s | eval "cat" | UnTAR t
	    offset=`expr $offset + $s`
	done
	exit 0
	;;
	--tar)
	offset=`head -n 502 "$0" | wc -c | tr -d " "`
	arg1="$2"
    if ! shift 2; then MS_Help; exit 1; fi
	for s in $filesizes
	do
	    MS_dd "$0" $offset $s | eval "cat" | tar "$arg1" - $*
	    offset=`expr $offset + $s`
	done
	exit 0
	;;
    --check)
	MS_Check "$0" y
	exit 0
	;;
    --confirm)
	verbose=y
	shift
	;;
	--noexec)
	script=""
	shift
	;;
    --keep)
	keep=y
	shift
	;;
    --target)
	keep=y
	targetdir=${2:-.}
    if ! shift 2; then MS_Help; exit 1; fi
	;;
    --noprogress)
	noprogress=y
	shift
	;;
    --nox11)
	nox11=y
	shift
	;;
    --nochown)
	ownership=n
	shift
	;;
    --xwin)
	finish="echo Press Return to close this window...; read junk"
	xterm_loop=1
	shift
	;;
    --phase2)
	copy=phase2
	shift
	;;
    --)
	shift
	break ;;
    -*)
	echo Unrecognized flag : "$1" >&2
	MS_Help
	exit 1
	;;
    *)
	break ;;
    esac
done

if test "$quiet" = "y" -a "$verbose" = "y";then
	echo Cannot be verbose and quiet at the same time. >&2
	exit 1
fi

MS_PrintLicense

case "$copy" in
copy)
    tmpdir=$TMPROOT/makeself.$RANDOM.`date +"%y%m%d%H%M%S"`.$$
    mkdir "$tmpdir" || {
	echo "Could not create temporary directory $tmpdir" >&2
	exit 1
    }
    SCRIPT_COPY="$tmpdir/makeself"
    echo "Copying to a temporary location..." >&2
    cp "$0" "$SCRIPT_COPY"
    chmod +x "$SCRIPT_COPY"
    cd "$TMPROOT"
    exec "$SCRIPT_COPY" --phase2 -- $initargs
    ;;
phase2)
    finish="$finish ; rm -rf `dirname $0`"
    ;;
esac

if test "$nox11" = "n"; then
    if tty -s; then                 # Do we have a terminal?
	:
    else
        if test x"$DISPLAY" != x -a x"$xterm_loop" = x; then  # No, but do we have X?
            if xset q > /dev/null 2>&1; then # Check for valid DISPLAY variable
                GUESS_XTERMS="xterm rxvt dtterm eterm Eterm kvt konsole aterm"
                for a in $GUESS_XTERMS; do
                    if type $a >/dev/null 2>&1; then
                        XTERM=$a
                        break
                    fi
                done
                chmod a+x $0 || echo Please add execution rights on $0
                if test `echo "$0" | cut -c1` = "/"; then # Spawn a terminal!
                    exec $XTERM -title "$label" -e "$0" --xwin "$initargs"
                else
                    exec $XTERM -title "$label" -e "./$0" --xwin "$initargs"
                fi
            fi
        fi
    fi
fi

if test "$targetdir" = "."; then
    tmpdir="."
else
    if test "$keep" = y; then
	if test "$quiet" = "n";then
	    echo "Creating directory $targetdir" >&2
	fi
	tmpdir="$targetdir"
	dashp="-p"
    else
	tmpdir="$TMPROOT/selfgz$$$RANDOM"
	dashp=""
    fi
    mkdir $dashp $tmpdir || {
	echo 'Cannot create target directory' $tmpdir >&2
	echo 'You should try option --target dir' >&2
	eval $finish
	exit 1
    }
fi

location="`pwd`"
if test x$SETUP_NOCHECK != x1; then
    MS_Check "$0"
fi
offset=`head -n 502 "$0" | wc -c | tr -d " "`

if test x"$verbose" = xy; then
	MS_Printf "About to extract 492 KB in $tmpdir ... Proceed ? [Y/n] "
	read yn
	if test x"$yn" = xn; then
		eval $finish; exit 1
	fi
fi

if test "$quiet" = "n";then
	MS_Printf "Uncompressing $label"
fi
res=3
if test "$keep" = n; then
    trap 'echo Signal caught, cleaning up >&2; cd $TMPROOT; /bin/rm -rf $tmpdir; eval $finish; exit 15' 1 2 3 15
fi

leftspace=`MS_diskspace $tmpdir`
if test -n "$leftspace"; then
    if test "$leftspace" -lt 492; then
        echo
        echo "Not enough space left in "`dirname $tmpdir`" ($leftspace KB) to decompress $0 (492 KB)" >&2
        if test "$keep" = n; then
            echo "Consider setting TMPDIR to a directory with more free space."
        fi
        eval $finish; exit 1
    fi
fi

for s in $filesizes
do
    if MS_dd_Progress "$0" $offset $s | eval "cat" | ( cd "$tmpdir"; UnTAR x ) 1>/dev/null; then
		if test x"$ownership" = xy; then
			(PATH=/usr/xpg4/bin:$PATH; cd "$tmpdir"; chown -R `id -u` .;  chgrp -R `id -g` .)
		fi
    else
		echo >&2
		echo "Unable to decompress $0" >&2
		eval $finish; exit 1
    fi
    offset=`expr $offset + $s`
done
if test "$quiet" = "n";then
	echo
fi

cd "$tmpdir"
res=0
if test x"$script" != x; then
    if test x"$verbose" = xy; then
		MS_Printf "OK to execute: $script $scriptargs $* ? [Y/n] "
		read yn
		if test x"$yn" = x -o x"$yn" = xy -o x"$yn" = xY; then
			eval $script $scriptargs $*; res=$?;
		fi
    else
		eval $script $scriptargs $*; res=$?
    fi
    if test $res -ne 0; then
		test x"$verbose" = xy && echo "The program '$script' returned an error code ($res)" >&2
    fi
fi
if test "$keep" = n; then
    cd $TMPROOT
    /bin/rm -rf $tmpdir
fi
eval $finish; exit $res
./                                                                                                  0000755 0000000 0000000 00000000000 12722063107 007711  5                                                                                                    ustar   root                            root                                                                                                                                                                                                                   ./.wifislax_bootloader_installer/                                                                   0000700 0000000 0000000 00000000000 12722063147 016076  5                                                                                                    ustar   root                            root                                                                                                                                                                                                                   ./.wifislax_bootloader_installer/bootinst.com                                                       0000644 0000000 0000000 00000006560 12722063143 020454  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   #!/bin/bash

if [[ $(id -u) -ne 0 ]]; then
    echo "Not running as root"
    exit
fi

# Colores
CIERRE=${CIERRE:-"[0m"}
ROJO=${ROJO:-"[1;31m"}
VERDE=${VERDE:-"[1;32m"}
CYAN=${CYAN:-"[1;36m"}
AMARILLO=${AMARILLO:-"[1;33m"}
BLANCO=${BLANCO:-"[1;37m"}
ROSA=${ROSA:-"[1;35m"}

chmod 0777 /tmp &> /dev/null
set -e
TARGET=""
MBR=""
TEMPINSTALL=`pwd`
EXECUTABLES="$TEMPINSTALL/.wifislax_bootloader_installer"

# Funcion que limpia
f_exitmode() {
   rm -Rf $EXECUTABLES &>/dev/null
   exit 1
}

trap f_exitmode SIGHUP SIGINT

if [ $(uname -m) = x86_64 ]; then
LILOLOADER=lilo64.com
SYSLINUXLOADER=syslinux64.com
else
LILOLOADER=lilo32.com
SYSLINUXLOADER=syslinux32.com
fi

# Find out which partition or disk are we using
MYMNT=$(cd -P $(dirname $0) ; pwd)
while [ "$MYMNT" != "" -a "$MYMNT" != "." -a "$MYMNT" != "/" ]; do
   TARGET=$(egrep "[^[:space:]]+[[:space:]]+$MYMNT[[:space:]]+" /proc/mounts | cut -d " " -f 1)
   if [ "$TARGET" != "" ]; then break; fi
   MYMNT=$(dirname "$MYMNT")
done

if [ "$TARGET" = "" ]; then
   echo $ROJO
   echo "No encuentro el dispositivo."
   echo "Este seguro de ejecutar este script en un dispositivo montado."
   echo $CIERRE
   exit 1
fi

if [ "$(cat /proc/mounts | grep "^$TARGET" | grep noexec)" ]; then
   echo "El disco $TARGET esta montado con el parametro noexec, intentando remontar..."
   mount -o remount,exec "$TARGET"
   sleep 3
fi

MBR=$(echo "$TARGET" | sed -r "s/[0-9]+\$//g")
NUM=${TARGET:${#MBR}}
TMP="/tmp/$$"
mkdir -p "$TMP"
cd "$MYMNT"
cp -f $EXECUTABLES/$LILOLOADER "$TMP"
cp -f $EXECUTABLES/$SYSLINUXLOADER "$TMP"
chmod +x "$TMP"/*

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
clear

echo "Flushing filesystem buffers, this may take a while..."
sync

# setup MBR if the device is not in superfloppy format
if [ "$MBR" != "$TARGET" ]; then
   echo "Instalando ${CYAN}MBR${CIERRE} en ${VERDE}$MBR${CIERRE}..."
   "$TMP"/$LILOLOADER -S /dev/null -M $MBR ext # this must be here to support -A for extended partitions
   echo "Activando particion ${VERDE}$TARGET${CIERRE}..."
   "$TMP"/$LILOLOADER -S /dev/null -A $MBR $NUM
   echo "Actualizando ${CYAN}MBR${CIERRE} en ${VERDE}$MBR${CIERRE}..." # this must be here because LILO mbr is bad. mbr.bin is from syslinux
   cat $EXECUTABLES/mbr.bin > $MBR
fi

echo "Instalado ${CYAN}MBR${CIERRE} en ${VERDE}$TARGET${CIERRE}..."
chmod +t /tmp
"$TMP"/$SYSLINUXLOADER -i -s -f -d boot/syslinux $TARGET
rm -rf "$TMP" 2>/dev/null
rm -rf $EXECUTABLES 2>/dev/null
echo "El disco ${VERDE}$TARGET${CIERRE} es booteable ahora. Instalacion terminada."
echo
echo "Presiona ${AMARILLO}ENTER${CIERRE} para salir..."
read junk                                                                                                                                                ./.wifislax_bootloader_installer/lilo64.com                                                         0000644 0000000 0000000 00000524220 12706232442 017724  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   ELF          >    p=@     @       ¡         @ 8 	 @         @       @ @     @ @     ø      ø                   8      8@     8@                                          @       @     Ä	     Ä	                        b     b     Œ’      hÕ                    @     @b     @b                                T      T@     T@                            Påtd   <Ş     <ŞA     <ŞA                        Qåtd                                                  Råtd        b     b     è      è             /lib64/ld-linux-x86-64.so.2          GNU                   a   c      I   %   _       3           C              Y              @          ]       1       Z          	   b   \       B   !   0       N   >       .   X   S       K      8           ;   A                 T   D   J       4   U   =           6       M       Q   a       L   $      ^      [   :   ?       7           R   H           W                   `   E                  G                                                                                                                                                                                           '                      (   
      *           /   )                   5                 <                       "   ,                      O   F   -       V               P   2   #   &      9   +                           Ğ                     g                     3                     _                     6                     É                                          N                      X                     P                     Ã                      J                     0                     &                       ø    À b                                 ö                                           w    Ğ b            ‚                     $                     B                                           Q                     ò                     à                     ¨                      Á                     ,                                          8                     ì                                                               |                                          `                      „                     G                     ÿ                     }                     æ                                          $                     ë                     ¨                                                               µ                     +                     ™                     s                       ’                     A                     V                     ó                     ¦                     E                                          £     0 @                                   ‹                     ı                      ù                     ®                     M                     n                     Ú                     ½    œ½@     à       g                     ‚                      ä                     '                     +                     ò                     *                     @                     ”                       ­                     *                                          o                     8                     ´                     È                     /                     —                                          @                     ¹                     Ò                       ‹                     	                     Â                     %                                           Y                     u    à b             libdevmapper.so.1.02 dm_task_destroy _ITM_deregisterTMCloneTable dm_task_run dm_task_set_major dm_get_next_target __gmon_start__ dm_task_set_minor _Jv_RegisterClasses dm_task_get_driver_version dm_task_create _ITM_registerTMCloneTable libc.so.6 chroot fflush strcpy readdir sprintf _IO_putc srand fopen strncmp strrchr perror closedir strncpy unlink putchar realloc fstatfs stdin memchr strspn strdup strtol feof fdatasync fgets ungetc getchar warn strstr __errno_location fseek chdir read memcmp ctime stdout fputc fputs lseek fclose strtoul malloc getpass strcat strcasecmp realpath remove opendir __ctype_b_loc getenv sscanf stderr ioctl readlink strncasecmp creat strtoull fileno rename atoi lseek64 strchr getline __ctype_toupper_loc memmove uname access _IO_getc strcmp strerror __libc_start_main write vfprintf free __cxa_atexit __xstat __fxstat __xmknod Base GLIBC_2.2.5 GLIBC_2.3                                                                                                                     •ˆ    _        ì          ui	   d     ii   p      àb                   èb        4           ğb        N           øb        [           À b                   Ğ b                   à b        b           b                    b                   (b                   0b                   8b                   @b                   Hb                   Pb                   Xb        	           `b        
           hb                   pb                   xb                   €b                   ˆb                   b                   ˜b                    b                   ¨b                   °b                   ¸b                   Àb                   Èb                   Ğb                   Øb                   àb                   èb                   ğb                   øb                     b        !           b        "           b        #           b        $            b        %           (b        &           0b        '           8b        (           @b        )           Hb        *           Pb        +           Xb        ,           `b        -           hb        .           pb        /           xb        0           €b        1           ˆb        2           b        3           ˜b        5            b        6           ¨b        7           °b        8           ¸b        9           Àb        :           Èb        ;           Ğb        <           Øb        =           àb        >           èb        ?           ğb        @           øb        A            b        B           b        C           b        D           b        F            b        G           (b        H           0b        I           8b        J           @b        K           Hb        L           Pb        M           Xb        O           `b        P           hb        Q           pb        R           xb        S           €b        T           ˆb        U           b        V           ˜b        W            b        X           ¨b        Y           °b        Z           ¸b        \           Àb        ]           Èb        ^           Ğb        _           Øb        `           àb        a           HƒìH‹]ó! H…ÀtèË  è"  è±3 HƒÄÃ            ÿ5Ró! ÿ%Tó! @ ÿ%Ró! h    éàÿÿÿÿ%Jó! h   éĞÿÿÿÿ%Bó! h   éÀÿÿÿÿ%:ó! h   é°ÿÿÿÿ%2ó! h   é ÿÿÿÿ%*ó! h   éÿÿÿÿ%"ó! h   é€ÿÿÿÿ%ó! h   épÿÿÿÿ%ó! h   é`ÿÿÿÿ%
ó! h	   éPÿÿÿÿ%ó! h
   é@ÿÿÿÿ%úò! h   é0ÿÿÿÿ%òò! h   é ÿÿÿÿ%êò! h   éÿÿÿÿ%âò! h   é ÿÿÿÿ%Úò! h   éğşÿÿÿ%Òò! h   éàşÿÿÿ%Êò! h   éĞşÿÿÿ%Âò! h   éÀşÿÿÿ%ºò! h   é°şÿÿÿ%²ò! h   é şÿÿÿ%ªò! h   éşÿÿÿ%¢ò! h   é€şÿÿÿ%šò! h   épşÿÿÿ%’ò! h   é`şÿÿÿ%Šò! h   éPşÿÿÿ%‚ò! h   é@şÿÿÿ%zò! h   é0şÿÿÿ%rò! h   é şÿÿÿ%jò! h   éşÿÿÿ%bò! h   é şÿÿÿ%Zò! h   éğıÿÿÿ%Rò! h    éàıÿÿÿ%Jò! h!   éĞıÿÿÿ%Bò! h"   éÀıÿÿÿ%:ò! h#   é°ıÿÿÿ%2ò! h$   é ıÿÿÿ%*ò! h%   éıÿÿÿ%"ò! h&   é€ıÿÿÿ%ò! h'   épıÿÿÿ%ò! h(   é`ıÿÿÿ%
ò! h)   éPıÿÿÿ%ò! h*   é@ıÿÿÿ%úñ! h+   é0ıÿÿÿ%òñ! h,   é ıÿÿÿ%êñ! h-   éıÿÿÿ%âñ! h.   é ıÿÿÿ%Úñ! h/   éğüÿÿÿ%Òñ! h0   éàüÿÿÿ%Êñ! h1   éĞüÿÿÿ%Âñ! h2   éÀüÿÿÿ%ºñ! h3   é°üÿÿÿ%²ñ! h4   é üÿÿÿ%ªñ! h5   éüÿÿÿ%¢ñ! h6   é€üÿÿÿ%šñ! h7   épüÿÿÿ%’ñ! h8   é`üÿÿÿ%Šñ! h9   éPüÿÿÿ%‚ñ! h:   é@üÿÿÿ%zñ! h;   é0üÿÿÿ%rñ! h<   é üÿÿÿ%jñ! h=   éüÿÿÿ%bñ! h>   é üÿÿÿ%Zñ! h?   éğûÿÿÿ%Rñ! h@   éàûÿÿÿ%Jñ! hA   éĞûÿÿÿ%Bñ! hB   éÀûÿÿÿ%:ñ! hC   é°ûÿÿÿ%2ñ! hD   é ûÿÿÿ%*ñ! hE   éûÿÿÿ%"ñ! hF   é€ûÿÿÿ%ñ! hG   épûÿÿÿ%ñ! hH   é`ûÿÿÿ%
ñ! hI   éPûÿÿÿ%ñ! hJ   é@ûÿÿÿ%úğ! hK   é0ûÿÿÿ%òğ! hL   é ûÿÿÿ%êğ! hM   éûÿÿÿ%âğ! hN   é ûÿÿÿ%Úğ! hO   éğúÿÿÿ%Òğ! hP   éàúÿÿÿ%Êğ! hQ   éĞúÿÿÿ%Âğ! hR   éÀúÿÿÿ%ºğ! hS   é°úÿÿÿ%²ğ! hT   é úÿÿÿ%ªğ! hU   éúÿÿÿ%¢ğ! hV   é€úÿÿÿ%šğ! hW   épúÿÿÿ%’ğ! hX   é`úÿÿÿ%Šğ! hY   éPúÿÿÿ%‚í! f        ƒÿtƒÿt ƒÿtP‰ş1À¿–ŸA è<š  ¸vŸA Ã¸dŸA Ã¸‰ŸA ÃAWAVI‰÷AUATDoÿUS¿0 @ Hìx  H‹~" HÇÑ¾" VA HÇæˆ"     ÇÀˆ"     Ç¦¾"     ÇÀˆ" ÿÿÿÿH‰‰¾" H‹H‰D$8èÔ, …À¿VA u¿6,A èÁ, …Àt¿›VA 1Àè›™  ¿ !b E1äE1öèíØ  ÇD$4    ÇD$0    ÇD$H    ÇD$,    ÇD$(    HÇD$@    HÇD$    HÇD$    HÇD$    HÇD$     E…í„ˆ	  I‹WI_€:-…Ï	  ¾J¿©VA H‰T$XAmÿ‰ÎˆL$O‰L$PèqúÿÿH…À‹L$PH‹T$Xt%€z tLzëAAƒí…íI_M‹€	  D‰íë(‰Î¿½VA H‰T$Pè-úÿÿH…ÀtH‹T$P€z …V	  E1ÿŠD$OƒèA<9‡D	  ¶Àÿ$Å¸eA L‰|$éj  …í„(  H‹C€8-„  HƒÃÿÍH‰D$@é  1ÉL‰ú¾'`A é™  1ÉL‰ú¾R­A éŠ  1É1Ò¾ÉVA ¿ !b èÖ×  Ç‡"    é  L‰=ç¼" éù  1ÉL‰ú¾ÑVA éM  1ÉL‰ú¾£A é>  Ç’†"    L‰=|" éÅ  1ÉL‰ú¾6tA é  Ç‘†"    é§  ƒe†" é›  Çr†"    éŒ  1ÉL‰ú¾×VA éà   …íL‰=}†" HÇD$ W‘A „e  H‹C€8-H‰D$ „&  HƒÃÿÍéH  ƒ†" é<  ƒú…" é0  1ÉL‰ú¾VA é„   …í„÷  H‹C€8-„ê  HƒÃÿÍH‰D$@éÚ  Ç»…"    éí  ¾=   L‰ÿèiøÿÿH…ÀI‰Ät!LhÆ  1ÉL‰ş¿ !b L‰êM‰ìè~Ö  é·  ¾ßVA L‰ÿèóöÿÿ…Àu1É1Ò¾ãVA ¿ !b èUÖ  é  ¾íVA L‰ÿèÊöÿÿ…Àu1É1Ò¾ôVA ëÕ¾:A L‰ÿè®öÿÿ…ÀuÇ4…"    éR  1É1ÒL‰şë¬Ç…"    é:  L‹+A€} tIƒÅÿÅë>…í„  L‹kHƒÃë,M…öu01ÀL‰ïHƒÉÿò®‰Ï÷×èÂ—  I‰ÆÆ  L‰îL‰÷ÿÍèãúÿÿ…íuĞéá  1ÀL‰÷HƒÉÿò®L‹kL{H÷ÑH‰ÎHƒÉÿL‰ûL‰ïò®L‰÷H‰ÈH÷ĞÆè—  ¾.ØA H‰ÇI‰Æè•úÿÿë£1ÉL‰ú¾WA éîşÿÿ1ÉL‰ú¾WA éßşÿÿÇo„"    ém  ÇD$H   H‹;€ tHGH‰D$éF  …í„9  H‹C€8-H‰D$„'  HƒÃÿÍé!  H‹€x tLxë…ítH‹SŠƒè0<	wHƒÃÿÍI‰×ëM…ÿt
L‰ÿè—  ë‹êƒ" …ÀyÇÜƒ"    ëÿÀ‰Òƒ" ƒ=Ëƒ"  „Ä   H‹Æx" H‰‡¹" é±   1É1Ò¾WA ¿ !b è`Ô  H‹Çfƒ"    €x+…‡   ÇRƒ" ÿÿÿÿë{1ÉL‰ú¾WA éÏıÿÿè  éĞ  ÿIƒ" ëZ1ÉL‰ú¾%WA é®ıÿÿÇD$(   ëAL‰|$ë:M‰üÇD$0   ë-HÇD$ W‘A ë"M‰üÇD$4   ëA¾@tA ëL‰|$ÇD$,   I‰ßA‰íéÒúÿÿ‹„$ø   ‰Ââ ğ  ú €  „‘  ¾ZA ¿ !b èYÕ  …ÀuèFw  ƒ=¼‚"  ˆ³  ƒ=¯‚"  tH‹®w" H‰o¸" ¾ÉVA ¿ !b èÕ  ¾íUA ¿ !b ‰x‚" èÕ  ¾÷UA ¿ !b ‰Ãè÷Ô  ¿ !b ¾VA ‰N‚" èâÔ  ‹C‚" ‰‚" ¿ZA Èƒø¦ùÿÿƒ=ó"  …s  ‚" í" u¿fZA 1Àèó“  ÇÕ"    ƒ=ò"  t¿ZA 1ÀèÔ“  H‹=ñ" H…ÿt
H‹t$ è¨ó  ƒ|$, …  M…ö„Å  ¿ !b ¾VA è­Ô  H…À¿şUA t¿ !b ¾VA è”Ô  H‰ÇL‰öè#*  1ÿéô  Š„$Ÿ  1í»    ˆÂ€â @•ÅuÀè‰Ãƒã9Y" …®	  ;-)" …¢	  ƒ=L"  „È
  ¾'`A ¿ !b è-Ô  H´$p  H‰Çè²  Š„$p  <ú…	  ‹„$|  H|$hA½   ½
   »@œ  H‰D$hèJóÿÿ¿Á\A H‰Æ1Àè{óÿÿ¿Ñ\A èÑòÿÿ·´$   ¿â\A iö•  ÆŸ  ‰ğ™A÷ı™÷ı‰ğ‰Ñ™÷û‰Ê‰Æ1Àè=óÿÿ·´$œ   fƒşÿ…y	  ¿	]A èòÿÿö„$§   ¸VA ¾LªA ¿J]A HDğ1Àèÿòÿÿö„$§   ¸$VA ¾@tA ¿a]A HDğ1Àèİòÿÿö„$Œ  ¿]A u¿©]A è$òÿÿö„$Œ  »(VA ½@tA H‰Ş¿Ì]A HDõ1ÀèŸòÿÿö„$Œ  €H‰î¿ë]A HDó1Àè„òÿÿö„$Œ   ¿!^A HEİ1ÀH‰Şèiòÿÿö„$Œ  ¾-VA ¿Z^A HEõ1ÀèLòÿÿö„$Œ  @¸7VA ¾2VA ¿q^A HDğ1Àè*òÿÿ¶´$š   @„ö…˜  ¿œ^A èoñÿÿfƒ¼$     …  ¿ç^A èVñÿÿf¼$p  òô„·  ¿R_A è<ñÿÿƒ==" ~‹´$È  ¿”_A 1ÀèÀñÿÿ¿©_A èñÿÿH„$r  Hœ$p  L´$v  E1íH‰D$€; …   AÿÅHƒÃ6AƒıuêD‰çèèñÿÿ‹œ$l  H¼$p  º·Á¾ü  è¿“  9Ã„'ıÿÿH‹=»s" èVóÿÿH‹5w´" ¿idA è…ñÿÿ¿   è»ôÿÿHƒ|$ uZ¿4WA è™ïÿÿH…ÀH‰D$uF¿ÆNA è•" …À¿…WA …ĞõÿÿHƒ|$ ‹D$(‹L$4•ÃD$0¶ÃĞÿÈ¢   H‹|$8èI  H‹D$€8 t°¾üUA ¿9WA è€óÿÿH‹|$H‰¼}" èïïÿÿ…ÀyèVïÿÿ‹8èOôÿÿH‹t$H‰Â¿JWA é-  ¿Ä~A èCğÿÿ…ÀyH‹t$¿XWA 1Àèª  ¿¡A è$ğÿÿ…À‰=ÿÿÿèïÿÿ‹8è ôÿÿ¿yWA H‰Æ1Àè«  ƒ|$0 tH‹t$@L‰çè»é  ƒ=~}"  ƒ|$( „Ì   1À¹@tA º   ¾   ¿•WA èîïÿÿƒ=K}"  t¿ªWA è;ïÿÿë¾·WA ¿ÈWA 1ÀèÈïÿÿƒ|$( tƒ="}"  ¹  ¿ØWA è
ïÿÿ‹}" …À~;ÿÈt7H¼$p  è¿ïÿÿ…Àu&H„$p  HŒ$t  ¿LYA H‚   H‰Æ1Àèeïÿÿ¿
   èûíÿÿƒ|$( tƒ=µ|" L  èQ  éB  ƒ=|"  ~H‹q" H‰^²" è6â  ‹G|" ¿hYA Pÿ…Â…ãóÿÿ1íHƒ|$ t*H‹|$¾™YA è¢íÿÿ…ÀtH‹|$¾ŸYA 1íèíÿÿ…À@•Åƒ=ø{"  tH‹=oq" è …ít„Ût
H‹|$è›  ƒ|$4 tH‹t$@L‰çè1â  H‹=å±" E1äèoÆ  …ÀA‰Åx¿ !b è2Í  A‰Ä¾WA ¿ !b è_Î  ƒ=Ÿ{"  º    HÂ‰‘{" ‹·{" ƒø~ƒøÇy{"     ~D‰æ¿¤YA 1Àè,îÿÿ…íu„Ût
H‹|$è  H´$à   D‰ïèÚ …À‰tøÿÿè½ìÿÿ‹8è¶ñÿÿH‹5?±" H‰Â¿ÀYA é’  ƒ¼$ü    tH‹5!±" ¿ÍYA ë¨tH‹5±" ¿èYA 1ÀèÿŒ  1Àö„$ø   $•À‰à°" é(øÿÿ¾ZA ¿ !b èêÍ  H…Àt¾ZA ¿ !b èÖÍ  H‰Çèú  ‰Òz" ƒ=Ëz"  ‰øÿÿÇ»z"     é øÿÿÿÈu%…Û¾íUA u…Ò¾÷UA ¸VA HDğ¿RZA 1ÀèqŒ  ‹Kz" ÇMz"     Çgz"     ƒøuÇ4z"    ëƒøuÇGz"    1Ûé#øÿÿ1ÛÿÈ”Ãéøÿÿ¾WA ¿ !b è'Í  H‰ÃH‹D$H…Àu¾'`A ¿ !b èÍ  ‹T$HH‰ŞH‰ÇèèÀ  é2øÿÿ¾%WA ¿ !b èèÌ  H…ÀH‰Ãt8¾0¿“[A èeìÿÿH…Àt
Ç†y"    ¾3¿™[A èIìÿÿH…Àt
Çjy"    ƒ=cy"  uè ƒ=•y"  t<ƒ=ˆy"  u	ƒ=[y"  t*ƒ=‚y" ~!ƒ=Iy"  ¸VA ¾LZA ¿Ÿ[A HDğ1ÀèC‹  ¾6tA ¿ !b èFÌ  H‰ÇèÉ/  ‹y" …Û„€  ¾VA ¿ !b »şUA èÌ  H…Àt¾VA ¿ !b èÌ  H‰ÃH¼$¨   1ÒH‰ŞèN  H´$p  º   ‰ÇA‰ÄèNìÿÿH=   tè1êÿÿ‹8è*ïÿÿH‰ŞH‰Â¿Ì[A é
  H´$p  º   D‰çèìÿÿH=   tèøéÿÿ‹8èñîÿÿH‰ŞH‰Â¿à[A éÑ   º   ¾   D‰çèOëÿÿH…ÀèÅéÿÿ‹8è¾îÿÿH‰ŞH‰Â¿ó[A é   H´$ˆ   º    D‰çè©ëÿÿHƒø tèéÿÿ‹8è‡îÿÿH‰ŞH‰Â¿\A ëjº   HÇÆ ÿÿÿD‰çèæêÿÿH…Àè\éÿÿ‹8èUîÿÿH‰ŞH‰Â¿+\A ë8H´$p  º   D‰çèCëÿÿH=   „Cöÿÿè"éÿÿ‹8èîÿÿH‰ŞH‰Â¿A\A 1ÀèÃˆ  …Û¾÷UA u„Ò¾VA ¸VA HDğ¿V\A 1Àè$êÿÿ‰zw" ‰-Pw" é(öÿÿ<ëu¶´$q  ƒÆë<é¿\A …Íîÿÿ¿´$q  ƒÆH„$p  º   )òHcöHÆH‰ÇHcÒèZìÿÿ€¼$p  ú¿£\A …îÿÿéöÿÿiö•  ¿#]A ÆŸ  ‰ğ™A÷ı™÷ı‰ğ‰Ñ™÷û‰Ê‰Æ1Àè†éÿÿé`öÿÿ¿½^A 1Àèuéÿÿéa÷ÿÿ¾R­A ¿ !b è¿É  H…À·´$    u¿_A èJéÿÿéO÷ÿÿ‰ò¿'_A 1ÀÁâè4éÿÿé9÷ÿÿH´$r  ¿q_A 1Àèéÿÿé:÷ÿÿf¼$p  òô…P÷ÿÿH´$r  ¿s_A 1Àèòèÿÿé7÷ÿÿf‹S2¸@tA A¹¯£A A¸«£A ¹»£A ¾-ØA ¿±_A öÆ@LDÈ€æH‰ÚLDÀE…íHEÈƒ=v"  HNğ1ÀèŸèÿÿƒ= v" ~h¶s/¶S0¶K.D¶C-@ˆ÷@€ç`tB1À@€ÿ`u¶C1Áà¿À_A Â¸÷UA ÁâÑºVA ÁáDÁ@öÆ HDĞæ   1Àè<èÿÿë¿Ô_A 1Àè.èÿÿ¿
   èÄæÿÿƒ=…u"  Šöÿÿf‹k2f÷Å t
¿ö_A èbçÿÿf÷Å t
¿`A èQçÿÿf…íy
¿,`A èBçÿÿ@öÅ€u¿L`A è2çÿÿë@öÅ¸SVA ¾@VA HDğ¿\`A 1Àè²çÿÿ@öÅ¸fVA ¾2VA HDğ¿}`A 1Àè”çÿÿf÷Å ¸lVA ¾=»A HDğ¿¡`A 1ÀA‰ïèrçÿÿfAƒç„–   @öÅ¿½`A t*1À¿ã`A èPçÿÿ·s4fƒşştwfƒşıu¿aA ë¿ò`A èæÿÿë¿ù`A ëò‰ò¿aA 1Àèçÿÿf÷Å ¿aA t¿.aA è`æÿÿ‹s$…öu¿JaA èOæÿÿë¿baA 1Àèáæÿÿ@€å t
¿„aA è1æÿÿMcÅMkÀ6B¶”  B¶¼  B¶„Ÿ  B¶´   HÁâH‰ÑHÁàHÁæH	ùH¼$¨   H	ÈH‰ÂH‰ğB¶´¡  H	ĞHÁæ H	ÆèáP  …À¿°aA „  Ht$tº   D‰çèçÿÿHƒøt
¿ÉaA éëÿÿ¶t$x‹D$tH¼$¨   HÁæ H	Æè•P  …À¿÷aA t8H´$p  º   D‰çèÑæÿÿH=   t
¿bA éÇêÿÿf¼$p  òôt¿CbA è9åÿÿëH´$r  ¿SbA 1ÀèÃåÿÿ¶T$z¶|$y¶D${¶t$|HÁâH‰ÑHÁàHÁæH	ùH¼$¨   H	ÈH‰ÂH‰ğ¶t$}H	ĞHÁæ H	ÆèîO  …À¿gbA tLH´$p  º   D‰çè*æÿÿH=   t
¿„bA é êÿÿ€¼$p   tH´$p  ¿²bA 1Àè*åÿÿë
¿ÅbA è~äÿÿfE…ÿ…‡óÿÿ¶”$„   ¶¼$ƒ   ¶„$…   ¶´$†   HÁâH‰ÑHÁàHÁæH	ùH¼$¨   H	ÈH‰ÂH‰ğ¶´$‡   H	ĞHÁæ H	Æè0O  …À„Q  H´$p  º   D‰çèmåÿÿH=   t
¿ÔbA écéÿÿH‹|$º   ¾cA è§ãÿÿ…Àu(¾Œ$x  ¾”$w  ¿cA ¾´$v  D¾„$y  ë>º   ¾cA L‰÷èiãÿÿ…Àt2¾Œ$x  ¾”$w  ¿;cA ¾´$v  D¾„$y  1ÀèäÿÿévòÿÿD·¼$‚  H„$p  IÇIo2A¶7@„ötOA¶W„ÒtF€úÿu/@€şÿu)A¶w@€şÿu¿lcA èãÿÿë¿³cA 1Àè«ãÿÿIƒÇëº¿ïcA 1ÀIƒÇè•ãÿÿë¨¶u @„ö„ùñÿÿ¶U¶M¿dA D¶E1ÀHƒÅÂ¾  ècãÿÿëÎ¿PdA è·âÿÿéÅñÿÿè÷  ƒ=®p" A‰Æ~‹k¦" ‰Æ¿ydA 1Àè-ãÿÿè›p  ƒ=‰p" ~ƒ=\¦"  t‹5hp" ¿§dA 1Àèãÿÿ¾]A ¿ !b AƒÍÿèOÃ  H…Àt¾]A ¿ !b è;Ã  H‰Çè—ƒ  A‰Å¾ÑVA ¿ !b è!Ã  H…Àt¾ÑVA ¿ !b èÃ  H‰Çèiƒ  ‰Ã¾×VA ¿ !b ½şUA èïÂ  ¾VA ¿ !b I‰ÇèİÂ  H…Àt¾VA ¿ !b èÉÂ  H‰Å¾'`A ¿ !b è·Â  E‰ñE‰è‰ÙL‰úH‰îH‰Çè8¡  E…ät$¿€+b èÀ  ¿€+b èàÀ  …Àt¿ÊdA 1Àèbº  èã®  …À¿×dA „âæÿÿ¿ôdA ˆÕæÿÿèÚ®  è&¯  èr¯  èñ¯  ƒ=Jo" ~èNo  ƒ=¥"  tè¢  ëxƒ=(o"  uMƒ=#o"  t
¿eA èáÿÿ¾WA ¿ !b èşÁ  H…Àt	1Ò¾   ë¾WA ¿ !b èáÁ  1Ò1öH‰Çè·¯  ë"èw³  ƒ=™n"  t
¿&eA è½àÿÿ¿TeA è³àÿÿƒ=´n" ~è¸n  ‹5cn" …öt@ƒş~¿eA 1Àè*áÿÿë¿ eA 1Àèáÿÿƒ=Qn"  ¸zVA ¾qVA ¿±eA HDğ1ÀèûàÿÿHÄx  1À[]A\A]A^A_Ã€    1íI‰Ñ^H‰âHƒäğPTIÇÀĞOA HÇÁ`OA HÇÇ "@ è—áÿÿôfD  H=c" Hc" UH)øH‰åHƒøvH‹Ò! H…Àt	]ÿàfD  ]Ã@ f.„     H=Áb" H5ºb" UH)şH‰åHÁşH‰ğHÁè?HÆHÑştH‹éÑ! H…Àt]ÿàf„     ]Ã@ f.„     €=±b"  ubUHçÏ! H‹¨b" H‰åATSHÛÏ! L%ÌÏ! H)ÓHÁûHƒëH9Øs@ HƒÀH‰ub" AÿÄH‹jb" H9Øråèÿÿÿ[A\]ÆMb" óÃ H=‘Ï! Hƒ? ué.ÿÿÿfD  H‹1Ñ! H…ÀtéUH‰åÿĞ]éÿÿÿS¾/   H‰ûè’ßÿÿHPH…ÀH‹=œ¢" ¾¤PA HEÚ1ÀH‰Úè¡àÿÿH‹=‚¢" H‰Ùº@tA ¾çPA 1Àè†àÿÿH‹=g¢" º@tA ¾,QA 1ÀènàÿÿH‹=O¢" º@tA ¾hQA 1ÀèVàÿÿH‹=7¢" º@tA ¾¦QA 1Àè>àÿÿH‹=¢" H‰Ùº@tA ¾åQA 1Àè#àÿÿH‹=¢" H‰Ùº@tA ¾RA 1ÀèàÿÿH‹=é¡" H‰Ùº@tA ¾MRA 1ÀèíßÿÿH‹=Î¡" H‰Ùº@tA ¾RA 1ÀèÒßÿÿH‹=³¡" H‰Ùº@tA ¾ÃRA 1Àè·ßÿÿH‹=˜¡" H‰Ùº@tA ¾úRA 1ÀèœßÿÿH‹=}¡" H‰Ùº@tA ¾6SA 1ÀèßÿÿH‹=b¡" H‰Ùº@tA ¾`SA 1ÀèfßÿÿH‹=G¡" H‰Ùº@tA ¾‹SA 1ÀèKßÿÿ¿   èáÿÿPƒ=Qk" >  ‹5-^" º·Á¿¤b è3€  ÿÀt9‹^" ¿¤b º·Ápüè€  ÷Ğ¿³SA ‰ÆÁèfÁÆ†àÁæ·À	Æ1Àè‘İÿÿ‹5»A" º·Á¿„‚b èá  ÿÀt9‹¢A" ¿„‚b º·ÁpüèÅ  ÷Ğ¿»SA ‰ÆÁèfÁÆ†àÁæ·À	Æ1Àè?İÿÿ‹5I" º·Á¿d^b è  ÿÀt9‹0" ¿d^b º·Ápüès  ÷Ğ¿ÃSA ‰ÆÁèfÁÆ†àÁæ·À	Æ1ÀèíÜÿÿ‹5×ö! º·Á¿D8b è=  ÿÀt9‹¾ö! ¿D8b º·Ápüè!  ÷Ğ¿ËSA ‰ÆÁèfÁÆ†àÁæ·À	Æ1Àè›Üÿÿ‹5%ì! º·Á¿ä-b èë~  ÿÀt9‹ì! ¿ä-b º·ÁpüèÏ~  ÷Ğ¿ÓSA ‰ÆÁèfÁÆ†àÁæ·À	Æ1ÀèIÜÿÿ‹5ô! º·Á¿$6b è™~  ÿÀt9‹úó! ¿$6b º·Ápüè}~  ÷Ğ¿ÛSA ‰ÆÁèfÁÆ†àÁæ·À	Æ1Àè÷Ûÿÿ‹5¡ñ! º·Á¿4b èG~  ÿÀt9‹ˆñ! ¿4b º·Ápüè+~  ÷Ğ¿ãSA ‰ÆÁèfÁÆ†àÁæ·À	Æ1Àè¥Ûÿÿ¿ìSA èûÚÿÿ¿UA 1ÀèÛÿÿ¿UA èåÚÿÿº   ¾   ¿)UA 1ÀèoÛÿÿ¹   º   ¾   ¿?UA 1ÀèTÛÿÿƒÎÿ¿gUA 1ÀèEÛÿÿjjº   jj¾   ¿‚UA A¹   A¸   ¹   1ÀèÛÿÿº   ¾6   ¿ÅUA 1ÀHƒÄ(éüÚÿÿSHcÿH‰ûèê!  …Àu‰Ş¿ˆgA èZy  ÷Ğ!Ø•ÂƒøÀ¶À!Ğ[ÃHcÿH‰úH‰øHÁê‰ÑH‰úHÁê áÿ  â ğÿÿ	Êƒút!S‰ûè•!  ‰Â‰Ø!Ğ…Òu‰Ş¿°gA 1Àèıx  [ÃSHcÿH‰ûèo!  …Àu‰Ş¿ÔgA èßx  ÷Ğ!ØƒøÀ¶À[ÃAWAV¾'`A AUAT¿ !b US»¡A Hì˜  èº  H…ÀH´$°   HEØH‰ßH‰È\" èÓ …ÀyH‰Ş¿ÿgA éÄ   ƒ=cg" ~‹”$Ø   ‹´$°   ¿hA 1ÀèßÙÿÿH‹„$Ø   H‰ÂHÁè HÁê% ğÿÿâÿ  	Ğƒø	t$¿ !b ¾WA è	º  1ÒH…À¿7hA „\
  é  ƒ=Ëf"  uH‹6\" €8/u€x u¿jhA 1Àè»x  è6g  ‹´$Ø   H¼$@  º   è²V  …ÀA‰ÅyH‹5ó[" ¿hA 1Àè±w  H‹¼$Ø  èy  H´$°   D‰ïH‰ÃH‰Å[" èà
 …Àˆ)  ‹„$È   % ğ  = `  t
H‰Ş¿±hA ë­H‹„$Ø   HT$¾	€D‰ï‰Œ" 1Àè)Ùÿÿ…ÀyH‰Ş¿ÊhA ézÿÿÿƒ=f" ~‹T$‹t$¿ëhA 1Àè›Øÿÿƒ|$ t¿iA 1Àèw  ƒ|$Y¿+iA víHT$h1À¾	H€D‰ïèÈØÿÿ…ÀyH‹5[" ¿RiA éÿÿÿƒ=´e" ~‹T$l‹t$h¿piA 1Àè6Øÿÿ‹T$D‹D$h…Òu ƒ|$ZuE…Àuƒ|$lZëAƒøuƒ|$l tD‹L$l‹L$¿iA H‹5¤Z" 1Àègv  ƒ|$x¿ÓiA …Nÿÿÿƒ=2e"  u(ƒ=e"  uƒ= e"  Çòd"    u¿jA 1Àèøv  ¾WA ¿ !b èû·  H…ÀH‰Ãº   tW¾;İA H‰Çè3Öÿÿ…Àº   tA¾;jA H‰ßèÖÿÿ…Àº   t+¾@jA H‰ßèÖÿÿ…Àº   t¾IjA H‰ßèñÕÿÿƒøÒƒÂ‰û›" ‹”$ˆ   1ÉÇdš"    Çnd"    ÇTš" ÿ   Ç2š"     ‰Ğ¶ÒÇ³Y"     0À€Î	Ç Y"     Áà	ĞH‹H^" ‰[" H‰£]" H…Ò„-  ;tH‹R±ëë„ÉtH‰ƒ]" ƒ=d" ~<P‹„$¬   ¿MjA PD‹Œ$°   1ÀD‹„$¬   ‹Œ$¨   ‹”$”   ‹´$   èhÖÿÿZY‹„$„   ;„$˜   v%ƒ=—c"  ¿•jA „µıÿÿ1À¿ßjA è„u  ‹„$„   ‰D$ÇÛš"     E1öE1äÇ$   E1ÿ1í;l$¾  HT$1À¾	€D‰ï‰l$èOÖÿÿ…Àyè¦Ôÿÿ‹8èŸÙÿÿ‰êH‰Æ¿%kA é$  ‹T$ ‹D$$âÿ  ‰Ñ‰Â¶À0ÒÁáÁâ	Ê	Âƒ=c" ‰âY" ~‰î¿FkA 1Àè’Õÿÿ‹5ÌY" …öu¿fkA 1Àÿ7X" èÂt  é!  H¼$è  º   èÀR  öD$,tH‹´$€  ¿—kA 1ÀèDÕÿÿÿúW" éé  ‹5sY" H|$0ƒÊÿ¹   è“+  ¿    èCu  ƒ=xb" H‰Ù[" ~‹AY" ‹t$0¿»kA 1ÀèñÔÿÿH‹º[" ‹D$0‹= Y" ‰B‹D$<‰:‰B‹D$4‰B‹D$8‰B‹D$@‰BHcè—" …Òu‰v[" ‰-`™" +j[" ‰<• £b …À‰• ¤b t
ÇÊ—"    ƒ<$ t;èùÿÿ…Àt2E…ÿHc—" tD94… ¤b ”À¶À!$ëH˜A¿   D‹4… ¤b I‰Ä‹T$0;ƒ—" Hcd—" }‰t—" ‰[" ƒ=‡a" ‰… ¢b H‹áZ" H‹z[" H‰s[" H‰Q~!ƒ=:—"  t‹… ¤b ‹q¿ıkA 1À‰ÑèÜÓÿÿH‹Œ$€  H¼$  ºÿ  H‰ÎH‰L$èºÒÿÿH‹L$1öÆ„$   H‰ÏèjE  H…ÀuH¼$  èt  Hcº–" …ÉH‰ÊH‰Í £b u#H‹LZ" ‹L$<‰H‹L$4‰H‹L$8‰H‹L$@‰HÿÂ‰€–" ÿÅé8ıÿÿH¼$@  èõR  Hce–" D…<$Ç… ¢b     Ç… £b     tƒ=V–" uÇJ–"    ëLc%İY" Ç«U"     1íE1íD;-–" Æ   ‹£—" Pıƒúw ¢b     ëPƒøuK‹ –" ƒøu ¢b     ë.ƒøu/‹½ £b èŸ÷ÿÿ…À‹… ¢b t€Ì‰… ¢b ë€Ì ‰… ¢b ÿ/U" ƒ=8—" tGƒ=«•" tƒ=¢•" u5ë‹½ £b èÎ÷ÿÿ…Àtæ ¢b    ëD9µ ¤b u‹½ £b è/÷ÿÿ…ÀuÜAÿÅHƒÅé-ÿÿÿƒ=Ü–" ÇÊT"     „°   ƒ=Å–" …Ö  éá  H´$°   ‰Çè³ …ÀyH‰Ş¿ŸhA é”øÿÿ‹„$È   % ğ  = `  „Í   ‹”$Ø   H‰Ş¿(lA 1Àèp  è÷ÿÿ…Àt­ ¢b    HcJT" ‹´”" 9… ¡b „.  Hc-0T" H‰ßL‰ëE‰!T" èÏq  H‰í ¡b H…Û„Gÿÿÿ€; „>ÿÿÿè=ÕÿÿH‹ H¾öDP tHÿÃëğ¾,   H‰ßèÑÿÿH…ÀI‰ÅtÆ  IÿÅ1À¾   H‰ßè°Óÿÿ…À‰Å‰ÿÿÿH‰Şé«÷ÿÿƒ=O^" ~‹”$Ø   H‰Ş¿ElA 1ÀèÏĞÿÿ‰ïE1öè5ÑÿÿHc~S" ‹è“" ‰… ¡b D;5Ú“" Icîÿÿÿ‹¼$Ø   èÉõÿÿB‹<µ £b A‰ÇIÿÆè¶õÿÿA9ÇuÌHc6S" H‹¼$Ø   ‰,… ¡b Hc­ £b H9Ç…±şÿÿH‰Ş¿elA é÷ÿÿƒ=~]"  …Åşÿÿ‹”$Ø   H‰Ş¿˜lA 1Àè&Ğÿÿéªşÿÿƒ=^“" uƒi]" H‹âV" ƒx y	‹F“" ‰P‹pF€‰57“" ƒøv¿ÉlA 1ÀèXn  ƒ=?]"  t¿ïlA 1ÀèÉÏÿÿƒ=â\" u!‹‚”" ƒèƒøvH‹5[R" ¿#mA 1Àèën  B‹¥ ¤b ëV„ÉtHÇ^V"     ¿    è¨o  ‹”$ˆ   H‰FV" Ç@ÿÿÿÿ‰Ñ¶Ò0É€Î	Áá	Ê‰H‹¿V" H‰¸V" H‰Pé”øÿÿHÄ˜  ‰Ğ[]A\A]A^A_ÃAWAVAUATUSRƒ=9\" Eä1íAƒäÀAƒìƒ=i\"  u/¾WA ¿ !b A½   èL¯  H…ÀH‰Åu¾WA ¿ !b è5¯  H‰ÅE1íƒ=2\" 1ÛAƒÎÿƒ=ƒ“" …  éÁ   ‹î‘" ¾nA ƒøtƒø¾nA tƒø¾nA ¸7¸A HEğ¿0nA 1À1ÛèwÎÿÿ9¡‘" ~§H‹İ £b ‹4 ¤b ¿CnA 1ÀHÿÃèQÎÿÿëØ…Ûtlƒ=¨["  u'‹4 ¤b H‹<İ £b E…ÿE‰øE‰áD‰éEDÆH‰êèß¤  ƒ=x["  H‹4İ £b ¸@tA º#nA ¿{nA HDĞ1ÀHÿÃèïÍÿÿ;‘" A‰ß|•éW  ƒ=<["  t‹èØŸ  ƒ=úZ"  t
¿&eA èÍÿÿ¿VnA èÍÿÿédÿÿÿƒ% [" ûƒ=["  t$è¡Ÿ  ƒ=ÃZ"  t
¿&eA èçÌÿÿ¿¯nA èİÌÿÿëH‹=$P" A¹ùÿÿÿE1ÀD‰éH‰ê1öè"¤  ƒ=»Z"  H‹5 P" ¸@tA º#nA ¿ÔnA HDĞ1Àè6Íÿÿ‹ø‘" ƒø„Ÿ  ƒøu1Ûƒ=ÑO"  uéŠ  1ÛƒøA¿@tA „°   A¿@tA éÅ   Hc ¡b €<… ¢b  I‰Æuƒ2Z" Lc5³S" ƒ=4Z" ~IcÆH‹4İ ¡b ¿oA ‹… ¤b 1Àè¬Ìÿÿƒ=	Z"  u$B‹4µ ¤b H‹<İ ¡b E‰áA¸   D‰éH‰êèC£  ƒ=ÜY"  H‹4İ ¡b º#nA ¿ÔnA ID×1ÀHÿÃèXÌÿÿƒ%©Y" û9O" Oÿÿÿé¸   ‹ ¢b öÄtHÿÃ9[" ééœ   <€L‹4İ £b u	ƒ=Ù" uMƒ=lY"  u‹4 ¤b E‰áA¸   D‰éH‰êL‰÷è¬¢  ƒ=EY"  H‹4İ £b º#nA ¿{nA ID×1ÀèÄËÿÿë¾WA ¿ !b è¬  ¾*nA H…À¸-nA HDğM‰ğL‰ñL‰ò¿/oA 1ÀèÙj  éTÿÿÿX[]A\A]A^A_ÃAUATUSHƒìH‹œ" ƒú~¾   ¿0pA 1ÀèĞi  1ÀI‰ı¹   H‰çI‰ä1íó«¾   1À9Â~$‹… ¢b D‹… ¤b ‰óHÿÀƒáHcùÓãD‰¼	İëØ1ÛHƒût:£İsA‹œIƒÅA‰Eüƒ=7"  tƒ=RX" ~A‹4œ¿PpA 1À‰òèÖÊÿÿHÿÃëÀƒ=2X" ~‰î¿npA 1ÀèºÊÿÿHƒÄH‰è[]A\A]ÃAUATI‰õUSHc÷RD‹%áQ" ‰ûº   D‰çèÊÊÿÿ…Ày¿‡pA ëº   ¾@tA D‰çH‰ÅèêÉÿÿHÿÈt
¿–pA è³h  ‹=Q" è Éÿÿ…À¿¥pA uçL‰ê‰î¿`¥b è–/  …Àu
¿¸pA è¤h  ‹=lQ" ÷Óº   HcóèUÊÿÿH…ÀxŠX[]A\A]ÃAWAV1ÀAUATHƒÉÿUSH‰ûH‰÷Hì(  ò®¿ÜpA H÷ÑHÿÉHùı  ‡R  1ÀI‰õH‰ß¾   èoÌÿÿ…ÀA‰ÄyèsÈÿÿ‹8èlÍÿÿH‰ŞH‰Â¿ÂA ë*1Ò¾   ‰ÇèÑÉÿÿH…ÀyèGÈÿÿ‹8è@ÍÿÿH‰ŞH‰Â¿ qA 1Àèèg  Ht$ º   D‰çM‰ïè)ÊÿÿH=   tèÈÿÿ‹8èÍÿÿH‰ŞH‰Â¿qA ëÃAŠ< uIÿÇëô„ÀM‰şt]AŠ¨ßtIÿÆëô„ÀtAÆ ëE1öH„$  Hl$ H‰D$L‰şH‰ïèŸÇÿÿ…ÀtHƒÅ6H;l$uæL‰ş¿RqA 1ÀèKg  M…ötAÆ 1Ò1öD‰çèüÈÿÿH…Àˆ'ÿÿÿA€} Ht$º   D‰çÀ÷Ğf%òôf‰D$èÈÿÿ…Àx:ƒøt¿&qA 1Àèôf  IƒÎÿ1íL‰ï@ˆèL‰ñL‰îò®D‰çH÷ÑH‰ÊèØÇÿÿ…ÀH‰ÂyèÇÿÿ‹8èÌÿÿH‰ŞH‰Â¿qA éÀşÿÿL‰ñL‰ï@ˆèò®HcÒH÷ÑH9Êu™D‰çè‡Èÿÿ…ÀyèÎÆÿÿ‹8èÇËÿÿH‰ŞH‰Â¿EqA é‚şÿÿHÄ(  []A\A]A^A_ÃATU¾€  SH‰ûHì  è=Ëÿÿ…Àyè„Æÿÿ‹8è}ËÿÿH‰ŞH‰Â¿kqA éÙ   L¤$   ‰ÇèÈÿÿ1À¹€   L‰çó«º   H‰Ş¿`¥b fÇ„$   mkèô)  ƒ=³Š"  ‹yN" ‰«N" ‰!Œ" tP‰ÇH‰æè!ù  …À¿xqA u9ƒ=©T" ~‹$‹5ò‹" ¿šqA 1Àè*ÇÿÿHcß‹" H;$tƒ=Ş‹" t	¿¼qA 1Àëi½   ‹=HN" º   L‰æèsÆÿÿH=   tè¦Åÿÿ‹8èŸÊÿÿH‰ŞH‰Â¿qA 1ÀèGe  ÿÍfÇ„$     u¹ºœ¥b ¾   ¿`¥b è	,  …Àu
¿èqA èe  HÄ  []A\ÃAVAUI‰ÖATUº·ÁSI‰ô¾ü  H‰ıHì   èÏh  ‹¬M" 1öº   ‰…ü  ‰ßèÆÿÿ1Ò‰ß¾   I‰ÅèÆÿÿH…À¿‡pA x#H‰î‰ßº   è¦Åÿÿ1ÛH=   ½   t¿–pA èed  ÿÃIƒÄÅ   ƒûtL‰â‰î¿`¥b èK+  …ÀuÜ‰Ş¿rA èWd  1öL‰ò¿`¥b è,+  …Àu
¿7rA è:d  ƒ=!S" ~'‹=ùL" H‰æèy÷  …À¿‹qA x‹t$0¿erA 1ÀèÅÿÿ‹=ÒL" 1ÒL‰îèÀÅÿÿI9Å¿rA …`ÿÿÿHÄ   []A\A]A^ÃH…ÿtYATD‹%œL" 1ÒUSH‰õH‰ûD‰çè‚ÅÿÿH9Åt¿•rA 1Àè«c  º    H‰ŞD‰çè¡ÄÿÿHƒø t¿¦rA 1Àè‰c  [¿`¥b ]A\ë¿`¥b é?*  SH‰û¿   èe  ‹‰ŠSHÇ@    ˆPH‹+L" H…ÒtH‰BëH‰!L" H‰L" [ÃATU1öSI‰üº   Hƒì‹-èK" ‰ïèÙÄÿÿ…À¿‡pA xº   L‰æ‰ïH‰ÃèşÃÿÿH=   t
¿–pA èÄb  HT$‰Ş¿`¥b è¹)  …Àu
¿·rA èÇb  H|$èIÿÿÿHƒÄ[]A\ÃHÇ‡K"     HÇ„K"     ÃAUATA‰õUSI‰ü‰Õ1ÛHƒì9ë}KAt HT$L‰çÁæ	èT)  …ÀtH|$èîşÿÿë!¿œ¥b èâşÿÿƒ==Q" ~‰Ş¿ÜrA 1ÀèÅÃÿÿHÿÃë±HƒÄ[]A\A]Ã¿œ¥b é±şÿÿAWAV1ÀAUAT¹€   USHì(  ƒ=ìP"  H\$ H‰|$H‰ßó«„„  ƒ=¨P" H‹-ÉJ" EíA÷ÕAƒí€H…ít9Æ~H‹mÿÀëïE1äA¿  1ÉE1öH…íu3ƒ=œP" ;  Aƒş¸@tA ºoVA HDĞD‰ö¿ırA 1ÀèÃÿÿé  H‹}H…ÿtÄDŠEŠGDˆÂ1Â‰Ö1Òæ¿   ”ÂuOAöÀ tIA€à@u¶w1ÒD9ş”Âu5ƒà¿ÆGˆGë)¨@D¶}„R  ¶WA9×…E  ƒà¿ÆGˆGé6  …ÒtjöE`t9¶E¶u Áà‰Â¶EÁà	Ğ	ğ¶uÆ¶GÁà‰Â¶GÁà	Ğ¶	Ğ9Æë%‹u ‹1Òæ ÿ ÿ% ÿ ÿ9Æu¶U ¶EĞ¶9Ğ”Â¶ÒAÄ   …Òt‰ÊD‰àÁúÁø9Âu¶UD9ê‰ĞŒ¦  D‰áH‰ıé³şÿÿL‹=LI" M…ÿu¿!sA 1ÀèU`  E1íE1ä1íA¾   ƒ=.O" I‹GH‰D$„   AŠGA¶w¿3sA A·OA·ƒà`<`DDî1ÀèÁÿÿƒ=åN"  u	ƒ=¸N"  tAA¶WA¶G¾÷UA ¿ZsA ÁàÁâ	ÂA¶	ÂD‰èÁà	Âƒ=…N"  ¸ùrA HEğ1Àè=Áÿÿ¿
   èÓ¿ÿÿE…ötH‹t$1ÿèuöÿÿHcõHF
H=   v@HŞ¿   èYöÿÿ‹=HH" º   H‰ŞèsÀÿÿH=   t
¿–pA è9_  ¹€   1ÀH‰ßó«1íA‹HcÅ¹   HØ‰AŠWˆPAŠGU‰Õƒà`<`tA¶OL‰ÿ‰T$AÌè(¿ÿÿL‹|$E1ö‹T$M…ÿ…¶şÿÿ…ÒtV‹=ÁG" º   H‰Şèì¿ÿÿH=   t;étÿÿÿ1Òé1şÿÿÿÀ‰L$AÿÆˆEH‹GH‰D$èÎ¾ÿÿH‹D$H‰ï‹L$H‰Eé.şÿÿHÄ(  D‰à[]A\A]A^A_ÃAWAVFÿAUATI‰üUSA‰ÎM‰çM‰å1ÛHƒìH‹=NG" ‰D$H…ÿ‰Ş„Ã   ‹D$1ö…Ò@•ÆH‹o)Ø9Æ~¿bsA 1Àè7^  E…ötqDŠGAöÀ`u‹ë81ÀAöÀ tAöÀ@t	ŠGˆƒF" ¶|F" ¶wÁà	ğ¶wÁà	ğ¶7Áà	ğAƒşu	A‰IƒÇë/DˆÆAƒàpA‰EƒæEˆEIƒÅAˆuúë‹IƒÄA‰D$ûŠGAˆD$ÿ‰T$HÿÃè¸½ÿÿH‰ï‹T$é2ÿÿÿ…Òt,Aƒşu	AÇ    ëE…öt¹   1ÀL‰ïë
¹   1ÀL‰çóªHƒÄ‰ğ[]A\A]A^A_ÃAUATI‰üUS‰Õ‰óHì  ƒ=(L"  ~
¿zsA è¾ÿÿA‹|$Hcó1ÒHÁæ	èá¾ÿÿH…À¿’sA x=‹=ÙE" º   1öE1íèÂ¾ÿÿH‰ÃëAÿÅA9í}YA‹|$º   H‰æè3¿ÿÿ…Ày
¿­sA è­\  =ÿ  HcĞ¹   Hâ)Á1ÀH‰×óª‹=|E" º   H‰æè§½ÿÿ…À¦¿ÈsA ëÂ÷Ãÿ  t¿ãsA 1Àè‚\  H‰Ø¹   ¿`¥b H™H÷ù‰ê‰ÆèÊùÿÿHÄ  H‰Ø[]A\A]ÃAVAUATUI‰üS‰óHì   ƒ=)K"  ~
¿şsA è½ÿÿ‹=÷D" º   1öE1öI‰åèİ½ÿÿH‰Å…ÛtU¸   û   L‰æ‰ÂL‰ïNÓAÿÆHcÊ)Óú   ó¤I‰ôt	)ĞHcÈ1Àóª‹=¤D" º   L‰îèÏ¼ÿÿ…À±¿tA è™[  ÷Åÿ  t¿ãsA 1Àè§[  H‰è¹   ¿`¥b H™H÷ùD‰ò‰ÆèîøÿÿHÄ   H‰è[]A\A]A^ÃATUSHìÀ   ƒ=Ä±! uƒ=·±! @‹­±! „´   Ç¥±!    Ç—±! @   1Û‰ŞH|$ƒÊÿÁæÎ   è
:  …ÀtzH‹¼$°   1À¾   èA¿ÿÿ…ÀA‰ÄxUHt$º   ‰Ç1íèG½ÿÿHÿÈuHT$¾  D‰ç1Àè¾¼ÿÿ÷Ğ‰ÅÁíD‰çè¿¼ÿÿ…ítH|$ÿÃèø;  ƒûtétÿÿÿH|$èä;  ‰õ°! ‰ØHÄÀ   []A\ÃAWAV¾üUA AUATI‰ıUSHìè  H…ÿt&èÄ¾ÿÿH…ÀI‰Äu/è§ºÿÿ‹8è ¿ÿÿL‰îH‰Â¿ÂA ëD¿1tA è™¾ÿÿH…ÀI‰Ä„   L‹5&C" H¬$ß   ëzƒøÌ   M…í¾1tA H‰êIEõ¿WtA 1ÀèZ  ¾
   H‰ïèk»ÿÿH…ÀtÆ  ¾#   H‰ïèV»ÿÿH…ÀtÆ  IƒÏÿH‰ï¾>tA èİ»ÿÿL‰ùH‰ÂH‰ï1Àò®H‰ÈH÷ĞLøH9ÂuL‰â¾   H‰ïè2¼ÿÿH…Àu•ëv¿    è=[  H‰ÃHHH@LKLCH‰ÚPHC¾AtA H‰ïP1Àè6½ÿÿƒøZY…/ÿÿÿD‰{H‹@B" M…öH‰6B" H‰Ct¿ptA 1Àè.Y  ÇB"    ésÿÿÿL‰çè=ºÿÿ¾üUA ¿˜tA Ç9~"     èT½ÿÿH…ÀH‰Ã„?  H¼$ß   H‰Ú¾   ès»ÿÿH…ÀuH‰ßèö¹ÿÿé  H¼$ß   º   ¾¦tA Æ„$ß   èb¹ÿÿ…Àu¶H¼$ß   H‰Ú¾   è)»ÿÿH…ÀttHL$(HT$H¼$ß   1À¾¬tA èF¼ÿÿƒøuÃH|$(¾UA è»ÿÿ…Àu°Hc‡}" ƒ=8G" ‹t$‰4…Àáb ~¿µtA 1Àè·¹ÿÿ‹a}" ÿÀƒø‰V}" †rÿÿÿH‰ßè8¹ÿÿHt$H¿ÏtA èIë  …ÀuL¿	   è‹¸ÿÿH…ÀH‰Ãt:H‰Çèû¸ÿÿ…Àt.Ht$º    H‰ßè5¹ÿÿ…ÀtH|$è‡¼ÿÿH‰ß‰¶@" è)½ÿÿHÄè  []A\A]A^A_Ã‹Ñ|" 1À9Â~HÿÀ9<…¼áb uğ¸   Ã1ÀÃH‰şHÁï HÁîç ğÿÿæÿ  	şşÿ  vQºÿ  1À¿ãtA èX  1ÀZÃHcö¶†@b ‰Â…À÷ÒEÂÃATU¿    SHì   èÒX  H‹5@" H‰Ç¹   ó¥¾ŞqA ¿€b Ç@ÿÿÿÿH‰ÃèÚ˜  H‰æH‰ÇH‰Åè.ê  …Àyè%·ÿÿ‹8è¼ÿÿH‰îH‰Â¿QuA 1ÀèÆV  ‹D$% ğ  = `  tH‰î¿útA é€   H‹˜?" H‹|$(D‹ I1üèÿÿÿH˜L…àuÕH‹D$(¿ b ‰èÜ•  ¿ b è¬–  ¾uA ¿ b èE˜  ƒÊÿH…Àt
H‰ÇèaX  ‰Â‰SH‹;?" H‰ĞëH‹@H…Àt‹9uñH‰î¿#uA 1Àè"V  H‰S¿€b H‰?" èo•  HÄ   []A\ÃAWAV¾]aA AUAT¿ !b USHì¨   èÅ—  ¿àb H‰Åè6•  ¿àb è–  Ht$H‰ïèé  …Ày5¾²…A ¿àb è%—  …À…¶  èãµÿÿ‹8èÜºÿÿH‰îH‰Â¿HuA 1Àè„U  ‹D$(% ğ  = `  tH‰î¿]uA éã   H‹|$8èİıÿÿ…ÀtH‹|$8H‰û@¶ÇHÁë0Û	ÃèÀıÿÿ÷Ğ…ØuÆ¿    èâV  I‰ÄH‹D$8¾~uA ¿àb H‰ÃA‰$HÁè HÁë% ğÿÿãÿ  	Ãèá–  ¾ƒuA ¿àb I‰ÇèÏ–  ¾‹uA ¿àb I‰Æè½–  ¾‘uA ¿àb I‰Åè«–  ¾›uA ¿àb H‰D$è—–  H…Àttûÿ  w[H‰ÇHcÛè«V  ¶“@b „Òt9ĞtH‰î¿ªuA 1Àè}T  ‰Âˆƒ@b ƒâ÷ƒút3‰Âƒâßƒút)=€   t"‰ÂH‰î¿ÛuA 1ÀèKT  ¾ÿ  ¿
vA 1Àè:T  ƒÈÿM…ÿtL‰ÿè:V  M…öA‰D$”ÂM…í”À„Òt„ÀtAÇD$ÿÿÿÿAÇD$ÿÿÿÿë%„Àt¿JvA ëcL‰÷èúU  L‰ïA‰D$èíU  A‰D$¾²…A ¿àb èD•  …Àt=M…ÿAÇD$    ¿rvA u#M…ö•ÂM…í•ÀÂuHƒ|$ uAƒÈÿë!¿ŸvA 1ÀèˆS  Hƒ|$ tæH‹|$è†U  A‰ÀH‹b<" E‰D$AÇD$    H‰ÂH…Òt‹
A9$uH‰î¿ÍvA é½şÿÿH‹Rëàƒ="B" I‰D$L‰%<" ~&A‹L$PH‰îA‹D$¿òvA PA‹$1ÀE‹L$èˆ´ÿÿZY¿€b èX’  ¿€b è(“  ¾]aA ¿ !b è²’  HÄ¨   []A\A]A^A_ÃUSH‰ûHìÈ   H‹Ö;" H9G„¼   ‹=©! H¸/dev/lvmÆD$ H‰D$ƒÿÿtè€´ÿÿ‹sH|$1Ò1Àè¯¶ÿÿ…À‰Å‰Õ¨! yHt$¿wA ë!HT$‰Ç¾˜ş€1Àè4´ÿÿ…ÀyHt$¿4wA 1Àè9R  ·t$¿VwA fƒş	v)‰ïè´ÿÿ‹sH|$1Òèú0  …À‰q¨! H‹sy¿|wA 1ÀèùQ  H‰5;" ‹=R¨! 1ÀH‰Ú¾0şÀèÃ³ÿÿ…Ày¿¨†A è5¶ÿÿ¿wA è£Q  HÄÈ   []ÃUSH‰ûHìØ   ‹GH;»:" „Ñ   H|$¾ÈxA ¹   ó¤‹=ê§! ƒÿÿtèt³ÿÿH|$1ö1Àè¦µÿÿ…À‰Å‰È§! yHt$¿ÛwA ë!HT$‰Ç¾ u€1Àè+³ÿÿ…ÀyHt$¿ıwA 1Àè0Q  ‹t$ƒşvƒşuƒ|$ u‹L$‹T$¿#xA 1ÀèQ  ‰ïèö²ÿÿ‹sH|$(1ÒèØ/  …À‰K§! y‹s¿ZxA 1ÀèØP  ‹CH‰ä9" ‹=*§! 1ÀH‰Ú¾ÇuÀèŸ²ÿÿ…Ày¿˜†A èµÿÿ¿|xA èP  HÄØ   []ÃAWAVA‰×AUATA‰õUSH‰ıHìè   ƒ=d?" ~¿ßxA 1Àèî±ÿÿMcåL‰ãL‰àHÁëHÁè ãÿ  % ğÿÿ	ÃuD‰î¿ûxA éÜ  Aı  u¿CyA 1Àé¢  E…ÿ„Z  H|$8º   D‰îèò.  ƒûWA‰Æ‡Ÿ   ƒûHƒş  ƒû/w^ƒû,ƒğ  ƒûw0ƒûƒ  ƒû„v  wƒû„y  éF  ƒû„Ê  ƒûëƒû!‚/  ƒû"†F  ƒû$„=  é  ƒû9wƒû8‚1  é%  ƒû<‚ü  ƒû?†v  ƒûAƒw  éå  ƒûwLƒûxƒZ  ƒûewƒûdƒL  ƒû[†à  ƒû]ëƒûp„Ù  wƒûhƒ*  é¢  ƒûr„  é”  û   wûˆ   ‚  é¢  ûÊ   „ü  wû³   „ˆ  é\  ƒışÿÿƒø†9  éH  ƒûWÇE   ÇE   ÇE   ÇE    ÇE ÿÿÿÿ‡Ÿ   ƒûHƒ’  ƒû/w^ƒû,ƒ„  ƒûw0ƒûƒ  ƒû„
  wƒû„  éÚ  ƒû„^  ƒûëƒû!‚Ã  ƒû"†Ú   ƒû$„Ñ   é¬  ƒû9wƒû8‚Å  é¹   ƒû<‚  ƒû?†
  ƒûAƒ  éy  ƒûwHƒûxƒî  ƒûewƒûdƒà  ƒû[vxƒû]ëƒûp„q  wƒûhƒÂ  é:  ƒûr„´  é,  û   wûˆ   ‚¥   é:  ûÊ   „”   wû³   „   éô  ƒışÿÿƒø†Õ   éà  AƒÎÿIÁìA¶ÅA€ä A	Ä1ÀAÁìƒûtèÄñÿÿB„ €   E…ÿ‰E „”  HT$1À¾  D‰÷èú®ÿÿ…ÀˆX  ¶D$‰E·D$
‰E¶D$	é  AƒÎÿIÁìèmñÿÿA€ä A¶ÕA	ÔAÁìE…ÿB„ €   ‰E „.  HT$1À¾  D‰÷è”®ÿÿ…Àˆò   ¶D$	¿óyA „À…™  é  ¿>zA èk­ÿÿ¿pzA èa­ÿÿ¿²zA èW­ÿÿ¿õzA èM­ÿÿD‰î¿{A 1ÀèXL  AƒÎÿIÁìèÓğÿÿA€ä A¶ÕA	ÔAÁìE…ÿB„ €   ‰E „”  HT$1À¾  D‰÷èú­ÿÿ…Àx\¶D$	¿…{A „À…  ëxAƒÎÿIÁìèwğÿÿA€ä A¶ÕA	ÔAÁìE…ÿB„ €   ‰E „8  HT$1À¾  D‰÷è­ÿÿ…Àyèõ«ÿÿ‹8èî°ÿÿD‰îH‰Â¿ÈyA 1Àè–K  ¶D$	„À…   ¿Ö{A èK  AƒÎÿHcÃŠ€@b „À„œ   ƒû„È   <?„şıÿÿ<uwIÁìèÔïÿÿA€ä A¶ÕA	ÔAÁìE…ÿB„ €   ‰E „•   HT$1À¾  D‰÷èû¬ÿÿ…ÀˆYÿÿÿ¶D$	¿:{A „À„wÿÿÿ¶T$‰U·T$
‰U‰EH‹D$‰Eë{<„èıÿÿ<„zşÿÿCÄƒøvCˆƒøvëğ   ƒûwD‰î¿"|A éGşÿÿD‰î¿’|A é:şÿÿE…ÿu1ƒ={9" ~{¿À|A èg«ÿÿëo‹D$ ÇE    ‰E‹D$$‰E‹D$‰EH|$8è˜+  ëÃAƒåD‰m ë¹D‰èHT$¾ €ƒàD‰÷‰E 1Àè¬ÿÿ…Ày­èmªÿÿ‹8èf¯ÿÿD‰îH‰Â¿ yA ésşÿÿHÄè   []A\A]A^A_ÃAUATUS‰ûQH‹ä2" H‰ÅH…ít9] „¦  H‹mëìƒ=¾2"  u(H‰ÅLcãH…ítD‹m L‰çè7òÿÿ!ØA9Å„u  H‹mëŞHcóH‰ğHÁè‰ÂH‰ğHÁè âÿ  % ğÿÿ	ĞƒøW‡Ø   ƒøArHÁî¶Û@€æ 	ŞÁîë)ƒø$tDv=ƒø7‡Ÿ   ƒø0‚‘   HÁî¶Û@€æ 	ŞÁîuè¾íÿÿ…À”À¶Àé  1Àé  ƒøuHÁî¶Û1À@€æ 	ŞÁî…õ   ëÈw*ƒøuHÁî¶Û@€æ 	ŞÁîë¶ƒø„iÿÿÿƒøu€ãë£ƒøtµs
¸   é¶   ƒè!ƒøv¡ëìƒø-ë^ƒø9v•ƒè<ƒøwÚé-ÿÿÿƒøp„Oÿÿÿw!ƒøewƒødƒÿÿÿƒø[†fÿÿÿƒø]ë<ƒøhë =   w =ˆ   ƒÿÿÿƒør„æşÿÿrŒƒøxr‡éÚşÿÿ=³   „úşÿÿ=Ê   …lÿÿÿé¿şÿÿƒ} u‰Ş¿Ó|A 1Àè#H  ‹Eƒøÿ„qşÿÿ¨éÜşÿÿZ[]A\A]ÃAWAVHcÆAUATUSH‰ÃH‰ıHì¨!  ‹5m" ‰T$H‰ÂHÁè HÁê% ğÿÿ‰L$âÿ  	Ğ1Ò9ò‰Ñ}<‹<•Àáb HÿÂ9øuìL¤$˜  ;Úl" }H‹¡0" H…À„ë  ;X„2  H‹ ëéƒ=k6" ~‹T$‰Ş¿“A 1Àèï¨ÿÿHcÓH‰ĞHÁè‰ÁH‰ĞHÁè áÿ  % ğÿÿ	Èƒø:umH¼$  H‰”$   H‰”$˜  Ç„$      Ç„$˜  ÿ   èFôÿÿH¼$˜  è9ôÿÿ‹„$˜  +„$  ¿±A =ÿ   t1ÀèãF  H‹œ$˜  H‰]0HcÃH‰ÂHÁè HÁê% ğÿÿâÿ  	Ğƒøuu9H¼$˜  ‰œ$   HÇ„$˜      Ç„$¤      èÑôÿÿ‹„$   H‰ÃH‰E0HcÓE1íH‰ĞHÁè‰ÁH‰ĞHÁè áÿ  % ğÿÿ	Èƒø	…Ù  HÁêD¶ëH¼$è   0Ò¾ßA 1ÀA	ÕD‰êè4«ÿÿH¼$è   1À¾   èPªÿÿ…ÀA‰ÄyDH¼$è   D‰ê¾éA 1Àè«ÿÿH¼$è   1À¾   èªÿÿ…ÀA‰ÄyH´$è   ¿hA é"  HT$X1À¾	€D‰çè¡§ÿÿ…ÀyH´$è   ¿ÊhA éø   ƒ|$X ¿iA …«şÿÿƒ|$\Y¿+iA †›şÿÿH”$˜  1À¾	H€D‰çèT§ÿÿ…ÀyH´$è   ¿RiA é«   ‹T$XD‹„$˜  …Òu&ƒ|$\ZuE…Àu
ƒ¼$œ  ZëAƒøu
ƒ¼$œ   t D‹Œ$œ  ‹L$\H´$è   ¿iA 1ÀèE  ƒ¼$¨  ¿ôA …şÿÿE1í9(k" ‹k" H”$  ¾	€D‰ç‰„$  A”Å1Àè¤¦ÿÿ…ÀyH´$è   ¿%€A 1Àè¦D  ‹”$˜  ‹œ$”  D‰ç‰Ğãÿ  ¶Ò0ÀÁãÁà	Ã	Óèo¦ÿÿLcãL‰çèîìÿÿƒ|$ •$…Àt€<$ tè¨3  H‹E-" I‰ÆM…ö„ÿ  A9tM‹vëìE1ÿëA¿   A‹V…Òu€<$ t‰Ş¿Ó|A 1ÀèD  A‹FƒøÿtCÿÂt?Aƒ~ÿt8E…ÿu31ÒAƒ~ÿ…³   é³  E‹>L‰çè[ìÿÿ!ØA9Çt¡M‹vM…öuåA¿   ƒ|$ u$L‰àIÁì HÁèAä ğÿÿ%ÿ  A	ÄAƒü…~  ‹T$‰ŞH‰ïèõòÿÿƒ|$ t
‰ŞH‰ïèÑ·  D‹e èˆ·  Aƒäƒ|$ÿ…G  A9ÄŒ>  M…ö„&  Aƒ~ÿ„  A‹Fº   ƒøÿt‰E A‹Fƒøÿt‰E…ÒA‹Ftƒøÿt‰EA‹Fƒøÿt‰EA‹FƒøÿtE…ÿu‰Eƒ|$ÿt‹D$‰E ƒ|$ u#ƒ=Î1" Ì  ‹U ‰Ş¿_€A 1ÀèO¤ÿÿé¶  ‹M…Étƒ} tƒ} u‹UD‹E‰Ş¿€A 1ÀèœB  ù   ~º   ‰Ş¿¹€A ë'u¾   ¿ï€A 1ÀèEC  ‹Mƒù@~º@   ‰Ş¿DA 1ÀèXB  u¾@   ¿|A 1ÀèC  ƒ=ü0"  u+‹M‹EÈÿÈ™÷}™÷ù=ÿ  ~º   ‰Ş¿ĞA 1ÀèãB  ƒ=ø0" ~;‹E‹MA¸   ‹U ‰Ş¿<‚A ƒøÿDEÀ1Àèj£ÿÿ‹M‹U¾@tA ¿w‚A 1ÀèS£ÿÿE…íD‰m$u‹} ‰ŞèV-  é§  ‹}f" ‰E é™  H¼$è   ƒÊÿ‰Şè|   H‹´$€  H¼$  º   è¢ÿÿÆ„$   1À¹  L‰çóªH¼$  º   L‰æèH¢ÿÿ…ÀI‰ÅyèŒ¡ÿÿ‹8ƒÿt[è€¦ÿÿL‰æH‰Â¿ÿ|A ëz€¼$˜  /H¼$  t¾/   è·¢ÿÿHxH…ÀH„$  HDøH„$  L‰æH)øH   èj¡ÿÿH¼$  L‰æèÚ£ÿÿH…Àu#è¡ÿÿ‹8è	¦ÿÿH´$  H‰Â¿-}A 1Àè¬@  H¼$  º   L‰æè¡ÿÿE…í‰ÿÿÿ¿   Æ„$   è¡ÿÿH…ÀH‰$u
¿[}A éùÿÿLcëH‹<$L‰îL‰èHÁîHÁè % ğÿÿæÿ  	Æè¨ ÿÿ…Àu
¿‘}A éJùÿÿIÁíH‹<$¶óA€å D	îè#¤ÿÿ…ÀtÛH‹<$è&¡ÿÿ…Àu
¿Ò}A éùÿÿ¿   èªA  I‰Æ‰XHÇ@    H‹é(" HÇD$    1ÛI‰L‰5Ô(" H‹<$H‹t$LL$PLD$HHL$@HT$8è²¡ÿÿH‹|$HH‰D$H…ÿ„Î  ¾÷UA èE¢ÿÿ…Àt
¿~A é—øÿÿ¿(   è)A  I‰ÅH‹D$8ƒ=f(" L‹|$PMEI‰EH‹D$@I‰EYL‰D$èÌ¤ÿÿI¾H‹ L‹D$öDPt<I¾WöDPt0A€:u)I¾WöDPtI¾WöDPtHL$0HT$,¾6~A ë>L‰D$ès¤ÿÿI¾H‹ öDPt8¾:   L‰ÿèH ÿÿH…Àt&L‹D$HL$0HT$,¾w~A 1ÀL‰ÿè…¢ÿÿƒøé«  ¾    L‰ÿè@ ÿÿH…ÀH‰D$uL‰ş¿D~A éØùÿÿH‹D$¾~A L‰çÆ  H‹T$P1Àèm£ÿÿHt$XL‰çè Ñ  …Àu^‹D$p% ğ  = `  tL‰æ¿‰~A éŒùÿÿH‹„$€   H‰ÂHÁê‰ÑH‰ÂHÁê áÿ  â ğÿÿ	Ê‰T$,H‰Â¶ÀHÁê0Ò	Ğ‰D$0éŞ   H‹T$P¾·~A L‰ç1Àèê¢ÿÿ¾üUA L‰çè-¢ÿÿH…ÀI‰ÇuL‰æ¿É~A éùÿÿH‰Â¾   L‰çèH ÿÿH…ÀuH‹t$P¿ A éóøÿÿHL$0HT$,1À¾3A L‰çè[¡ÿÿƒøt^HT$41À¾9A L‰çèB¡ÿÿÿÈtL‰æ¿<A é®øÿÿHcD$4H‰ÁH‰ÂHÁé¶Ò‰ÎH‰ÁHÁèHÁé æÿ  0Àá ğÿÿ	Ğ	ñ‰D$0‰L$,L‰ÿè@ÿÿH‹D$IU¾}~A HxÆ  1ÀèÔ ÿÿÿÈtH‹t$P¿D~A é>øÿÿ‹D$,I‹VÁàD$0…ÛI‰U A‰E DØM‰nHƒ|$ …ñüÿÿH‹<$è,¢ÿÿH¼$è   èè  …Ûu
¿jA é±õÿÿHcÃ‹5Èa" H‰ÂH‰E0HÁè HÁê% ğÿÿâÿ  	Ğ1Ò9ò‰ÑÀôÿÿ‹<•Àáb HÿÂ9øuèé­ôÿÿH‹@1ÛH…Àt£‹X H‹ ëóƒ=+%"  uI‰ÆécøÿÿE1ÿéføÿÿ‹u ¿7€A 1Àèî<  M…ö…ÍøÿÿéùÿÿHÄ¨!  []A\A]A^A_ÃAVAUA‰ÖATUH‰õS¾:   H‰ûH‰ïAƒÍÿHì    èyÿÿH…Àt"I‰ÄÆ  H‰î¿¦‚A 1Àè‹<  I|$è¿=  A‰Å1ÀD‰öH‰ïèÕŸÿÿ…À‰CyèÙ›ÿÿ‹8èÒ ÿÿH‰îH‰Â¿ÂA ë'Ht$‰ÇèÉÎ  …Àyè°›ÿÿ‹8è© ÿÿH‰îH‰Â¿ÀYA 1ÀèQ;  ‹D$(% ğ    ÿÿâ ĞÿÿtH‰î¿ì‚A 1Àè+;  = €  uH‹t$ëH‹t$8D‰êH‰s(¹   H‰ßèüòÿÿ‹T$(1Àâ ğ  ú €  u‹D$…À‰CÇC     t6‹{HT$1À¾   è°œÿÿ…Ày'è›ÿÿ‹8è  ÿÿH‰îH‰Â¿ƒA 1Àèz;  ÇC   ë)‹t$…öt÷Æÿ  t¿%ƒA 1Àèƒ:  ‰ğ¹   ™÷ù‰C‹CHÄ    []A\A]A^ÃUSH‰õH‰ûHì˜   ƒ=;)" ~¿BƒA 1ÀèÅ›ÿÿH‰æH‰ïèzÍ  …Àyèqšÿÿ‹8èjŸÿÿH‰îH‰Â¿QuA é   ‹D$% ğ    ÿÿâ ĞÿÿtH‰î¿ì‚A 1Àèî9  = €  uH‹$ëH‹D$(H‰ÂH‰C(HÁè HÁê% ğÿÿâÿ  	Ğƒøu	ÇC    ë41À¾   H‰ïèÙÿÿ…À‰Cyèİ™ÿÿ‹8èÖÿÿH‰îH‰Â¿ÂA 1Àè~9  ‹s(1ÉƒÊÿH‰ßèfñÿÿ‹D$ÇC$    ÇC    ÇC   % ğ  = €  ”À¶À‰C‹CHÄ˜   []ÃSH‰û‹…ÿtè›ÿÿÇC    [ÃAVAUA‰õATUI‰ÔSH‰ıHƒÄ€ƒ  tşÿ  ¿UƒA SD‰è¹   ™÷}™÷ùƒ} ‰D$„î   ‹}Ht$èpÿÿH|$sIeRu=‹}1Àº   ¾Í@è‘šÿÿƒøu¿„ƒA 1Àèš8  ƒ='" ~‹u¿ ƒA 1ÀèšÿÿH|$bS4Ru^‹}1Àº   ¾Í@èIšÿÿ…À¿¼ƒA u¹ƒ=A'" ~‹u¿×ƒA 1ÀèÈ™ÿÿ‹}è˜ÿÿ…À¿òƒA uƒ='" ~‹u¿„A 1ÀèŸ™ÿÿ‹}HT$1À¾   èë™ÿÿ…Ày
¿„A èÕ7  D‹t$E…ö„Õ  H‹U(H‰ĞHÁè‰ÁH‰ĞHÁè áÿ  % ğÿÿ	Èƒø:u3‹D$H|$H‰T$‰D$èáäÿÿH‹E0H9D$¿,„A …÷şÿÿ‹D$‰D$H‹M(‹}H‰ÈHÁè‰ÂH‰ÈHÁè âÿ  % ğÿÿ	ĞƒøuuT¯|$‰L$ÇD$    HcÿH‰|$H|$è‰åÿÿ‹D$¿S„A H;E0…şÿÿD‰è¾   ‹]™\$÷ş™÷}é¦   D‰èA¸   ‹\$™HcñA÷ø™÷ÿHcÁI‰ÀHÁè IÁè% ğÿÿAàÿ  D	ÀE1À¯ß‹=	\" ÚD9Ç~FF‹…Àáb IÿÀD9ÈuëL‹»" L‰ÈH…À„  9p„  H‹ ëéF‹…Àáb IÿÀD9ĞtÖD9ÇëH9ñtH;u0¿¼„A …Ñıÿÿ‹]Ó‹I%" ‹M …Òuƒ=%"  „ñ   ƒúÀƒà ƒÀ@	È1Éƒ=["  tƒ}$É÷Ñƒá	È‰ÙAˆ$ÁéAˆD$…Ò°DÁAˆD$‰ØÁøAˆD$‰ØÁø…ÒAˆD$tQ‹u…ö~6‹M…É~/‰Ø™÷ş™÷ù=ÿ  ~ ‹ç" Pƒø‰Û" ¿…A 1Àè‘6  ûÿû ~‰Ş¿9…A é  ƒ=’$" A¾   „  ƒ=O$"  A¶L$¸÷UA ‹uA¸ùrA A‰ÙD‰ê¿u…A LDÀ1Àèí–ÿÿéN  …ÛAˆL$AÆ$AÆD$ tMƒ} u‹u ¿œ…A é©   ‰Ø™÷}‰ØÿÂAˆ$™÷}™‰Ã÷}‰ØAˆT$™÷}=ÿ  ‰Ã~ºÿ  ‰Æ¿¿…A ë‹Uƒúÿt9Ú‰Ş¿ó…A 1Àèç4  ƒ=Î#" ~'‹uP¶ÉA¶$E¶D$D‰êA‰Ù¿'†A P1Àè?–ÿÿZYAˆ\$ÁûAÆD$ÁãA¾   A$éƒ   ¿e†A 1Àè‹4  H‹pLcÒH‰ğH…ÀtL‹@M9ĞwM‰ÃLXM9Úr$H‹ ëá1ÉH…ötH‹NHNH‹u0¿‚„A 1ÀèC4  Hcp PHcÆD)ÂI‰ÀHÁè IÁè% ğÿÿAàÿ  D	ÀE1Àé‰ıÿÿHƒì€D‰ğ[]A\A]A^ÃATUH‰ıSHì°   H‰t$‹Ht$ è:Ç  1Ò…Àˆ£   ‹t$ ¹   ƒÊÿH‰ï1Ûè¼ëÿÿH‹D$P¹   Hÿ  H™H÷ùH9Ã}nA‰ÜHT$H‰ïAÁä	D‰æèwúÿÿ…ÀtKŠD$8D$uAŠD$	8D$u7ŠD$
8D$u-ŠD$8D$u#ŠD$8D$u‹}1ÒIcôè•ÿÿH÷ĞH‰ÂHÁê?ëHÿÃéxÿÿÿº   HÄ°   ‰Ğ[]A\ÃAWAVAUATI‰üUSH‰õHì8  ƒ=ù!"  ~!H‰ş1À¿±†A è€”ÿÿL‰çèø6  ¿
   è“ÿÿ1ÒL‰æ¿ ¦b èİöÿÿ¾ ¦b ‰ÇA‰Åè Æ  …Àyè“ÿÿ‹8è ˜ÿÿL‰æH‰Âé+  Ht$0º   D‰ïèó”ÿÿH=   tèÖ’ÿÿ‹8èÏ—ÿÿL‰æH‰Â¿qA 1Àèw2  ¶”$!  »   H‰æD‰ï„ÒEÚº0   è«”ÿÿHƒø0uºH|$º   ¾À†A E1öèî’ÿÿ…Àuf|$ÿ‡¨  ƒ=!" ~ƒû¸@tA ºoVA HDĞ‰Ş¿Å†A 1Àè…“ÿÿƒû?~¾?   ¿ã†A ëqH‹M" ¹   1ö¿ ¦b Hÿ  H™H÷ù‰Âè,ÏÿÿsH}-è˜ÏÿÿE…öA‰ÇtöD$u Ã   A½   A9ß~GL‰æ¿,‡A 1Àè1  ‹t$÷Æÿ  t¿A‡A 1Àèv1  A‰ÅfM2 ¸   A)İEkíAıÿ  DNè¿ ¦b èøÿÿƒ=3 " ~!Aƒÿ¸@tA ºoVA HDĞD‰ş¿r‡A 1Àè¨’ÿÿ¾‡‡A ¿ b è÷r  H…ÀH‰Ãu¾‡‡A ¿ !b èàr  H…ÀH‰Ã„  E…öu¿‡A 1Àèß0  ƒ=Æ"  ~!H‰Ş¿·‡A 1ÀèM’ÿÿH‰ßèÅ4  ¿
   èÛÿÿ1ÒH‰Ş¿ ¦b èªôÿÿ¾ ¦b ‰ÇèğÃ  …Àyè×ÿÿ‹8èĞ•ÿÿH‰ŞH‰Â¿ÀYA éüıÿÿH‹Ù" ‰E$è·ÍÿÿH‹Ê" ¹   1ö¿ ¦b Hÿ  H™H÷ù‰Âè©ÍÿÿH}(1öèÎÿÿƒ="" ‰Ã~ƒøºoVA ¸@tA HDĞ‰Ş¿Ë‡A 1Àè—‘ÿÿ¾ã‡A ¿ !b è}q  …Àt#¾ğ‡A ¿ !b èjq  …Àuƒ=Ò" ~W¿ı‡A ëKAİAı p  ~1fƒM2 ¾ğ‡A ¿ !b è6q  …Àt¿?ˆA 1Àè}0  ëƒ="  ¾ëƒ=…" ~
¿ëˆA èqÿÿ¿ ¦b èLöÿÿëfƒM2A¾   éHıÿÿHÄ8  []A\A]A^A_ÃAUATI‰ÔUSH‰ıAPƒ=6"  H‰ó~H‰ò1ÀH‰ş¿,‰A è·ÿÿº   H‰î¿ ¦b è#óÿÿ¾-   H‰ßèˆÿÿH…ÀI‰Åt(H‰ßÆ  è1  I}‰Ãè1  )ØÿÀyH¿G‰A 1Àèâ.  ¾+   H‰ßèKÿÿH…ÀI‰ÅtH‰ßÆ  èÒ0  I}‰ÃèÇ0  ëH‰ßè½0  ‰Ã¸   ‰Ş‰Â¿ ¦b èûËÿÿI|$-¾<   èdÌÿÿ=  ‰Ã~H‰î¿,‡A 1Àèq.  ¿ ¦b è2õÿÿƒ=N" ~&Yƒû‰Ş¸@tA []A\A]ºoVA ¿r‡A HDĞ1Àé¾ÿÿX[]A\A]ÃAUAT¾U‰A US¿ b Hƒìèûo  Ht$1ÒH‰ÇH‰Åè›’ÿÿ=ÿ   H‰ÃA‰Å
H‹D$€8 tH‰î¿_‰A 1Àè­g  ¿Àb è7m  ¿Àb èn  ¾=jA ¿Àb è o  H…ÀI‰Äu¿€‰A 1Àèvg  Ht$1ÒL‰çè/’ÿÿ=ÿ   H‰Å
H‹D$€8 tL‰æ¿_‰A 1ÀèDg  ‰è	Ø„Ÿ   A‰ì‹S" 1ÀAÁäD‰æ	Ş9Á~=·¼  ãb 9÷‰úu‰ê‰Ş¿‰A 1Àè6-  @¶ÿHÿÀA9ıuÒ¶Ö‰é‰Ş¿·‰A 1Àè-  ƒùu¾   ¿ä‰A 1ÀèÏf  ƒ=è" ~‰ê‰Ş¿ŠA 1ÀènÿÿHcS" D	ãPf‰œ  ãb ‰S" ¾U‰A ¿ b è“l  HƒÄ[]A\A]ÃAUATA‰ôUSH‰ıHìH  Ht$èÜ¿  …ÀyèÓŒÿÿ‹8èÌ‘ÿÿH‰îH‰Â¿QuA 1Àèt,  ‹D$ % ğ  = €  uH‹\$ëH‹\$0H‰ßèĞÔÿÿ…ÀtE…ä‰ÚtI‰Á÷Ñ!ËÿËƒûv<1ÛE1íƒ=" ~gE…ä¸@tA ¹]A HEÈº2ŠA E…íHEÓH‰î¿9ŠA 1Àè„ÿÿë9!ĞH¼$˜   ƒÊÿ‰ÆA½   èÉ
  H‹¼$0  èÎ-  H¼$˜   H‰Ãè  ëE…í¸    HEÃHÄH  []A\A]ÃAWAV¸uŠA AUATI‰ıUSH‰õH‰ÓI‰ÎHì¨  H…ÿLDèE1äH…ÒtHL¾:E„ÿt?1ÀHƒÉÿH‰×ò®H÷ÑHÿÉHƒùw(ŠB„Àt<:uè>‹ÿÿH‹ E1äB‹¸P½ƒúwD`=1Û¾ŠA ¿ b èœl  H…ÛA‰Çu…Àu¾   H‰ïèUşÿÿH‰Ãƒ=ì"  ~-¸@tA H…ÛºƒŠA H‰ÁHDĞA¸—ŠA HEËH‰î¿ŠA 1ÀèUŒÿÿE…ÿt ¿ ¦b H‰îèZğÿÿH…Û¿¼ŠA „?  éh  1ÒH‰î¿ ¦b èŸîÿÿHt$‰ÇA‰Çèâ½  …ÀyèÉŠÿÿ‹8èÂÿÿH‰îH‰Â¿ÀYA é{  ƒ=W"  u‹|$81öèr  ëgH|$@   ~\1ÀH‰î¿èŠA è+  H|$@ÿ  ~BH´$   º   D‰ÿèrŒÿÿH=   u%H¼$¢  º   ¾À†A è³Šÿÿ…Àu
¿/‹A èÁ*  1Ò¾ş  D‰ÿè¦‹ÿÿH…ÀyèŠÿÿ‹8èÿÿH‰îH‰Âé  Ht$º   D‰ÿèŒÿÿƒøt%…Àyèê‰ÿÿ‹8èãÿÿH‰îH‰Âéœ  H‰î¿V‹A ëf|$UªtH‰î¿s‹A 1Àéª  ¾ª‹A ¿ b èÜj  ¾¶‹A ‰Å¿ b è4k  …ítH…Àt¿¾‹A 1Àè;)  …íu3H…Àu.¾ª‹A ¿ !b èj  ¾¶‹A ‰Å¿ !b èöj  …ít
H…À¿ŒA uÂ…íuXH…À„ó   H‰Çèÿ*  ‰Å@°ƒø	wD}0‰î¿DŒA 1ÀD‰úD‰ıèŸ)  E€ƒøvƒıv‰î¿{ŒA 1Àè²(  ƒışué¤   ƒÍÿ‹ÙN" ƒÀƒø‰ÍN" ~¾   ¿ä‰A 1ÀèNb  ƒ=g" ~4ƒıÿ¾‰ŠA tH¼$    ¾ºA ‰ê1Àè]ÿÿH´$    ¿²ŒA 1ÀèÉ‰ÿÿ‹wN" ÿÈƒø~PşHcÒf‹Œ ãb HcĞf‰Œ ãb ëŞÁåfÇeN" ÿÿ@€Íÿf‰-\N" H¬$   1À¹€  D‹=™! H‰ïH‰îó«Aÿ 
  H¼$    ¹€   ó¥vL‰î¿áŒA èÁ'  H…Û¾ä-b D‰ùH‰ïó¤u8ƒ=–"  ‹x" ‹5‚" ˆ„$´  ‰´$¼    ¿üŒA 1Àè‰ÿÿé  1ö1ÀH‰ßè¡‹ÿÿ…ÀA‰Åyè¥‡ÿÿ‹8èŒÿÿH‰ŞH‰Â¿ÂA ëZ1Ò¾¾  ‰Çè‰ÿÿH…Àyèy‡ÿÿ‹8èrŒÿÿH‰ŞH‰Â¿ qA ë.Huº@   D‰ïèd‰ÿÿHƒø@tèI‡ÿÿ‹8èBŒÿÿH‰ŞH‰Â¿qA 1Àèê&  ‹=Ê" H‰è1Ò1É@Šp@„öt9xtAˆğAƒàıA€øt*@şÎt%Æ@bë…Ét
¿A égıÿÿf‰”$®  ¹   Æ@€HƒÂHƒÀHƒú@u­…É¿;A „;ıÿÿD‰ïèkˆÿÿ‹5E" E…äDDæƒ=O" @ˆ´$°  Dˆ¤$±  ~A¶Ô@¶ö¿VA 1ÀèÁ‡ÿÿHcnL" AŸÿ  ¾ ãb ¹2   º€âb Áû	fÇ„  ãb   Hc K" Ç…€âb     ·„$²  HèƒûH‰Çó¤¹‚   H‰Öó¤~DcH¼$    Dˆ¤$‘  è•ÂÿÿëA¼   è‹ÃÿÿE1íA9İtH‰ïAÿÅHÅ   ènÂÿÿëçƒû	èeÃÿÿÿÃëòº   1ö¿ ¦b èâÂÿÿAt$I~-èLÃÿÿ¿ ¦b è2ìÿÿƒ=N" ~At$D‰â¿‚A 1ÀèĞ†ÿÿHÄ¨  []A\A]A^A_Ãƒ=W"  u0Hì˜   ¿ŸA H‰æèa¸  ÁøƒÀ‰5" ‹/" HÄ˜   ÿÈÃ‹" ÿÈÃS1ÛHÿÇ¾/   è\†ÿÿH…ÀH‰ÇtÿÃëç‰Ø[ÃAWAVI‰ÿAUATI‰ôUSH‰ÓHìØ   ƒ=£" ‰L$~H‰Ö¿¬A 1Àè&†ÿÿH‰ßL‰|$8èÉ…ÿÿH…ÀH‰ÅuèÌ„ÿÿ‹8èÅ‰ÿÿH‰ŞH‰Â¿ºA 1Àèm$  1öH‰ßèÙ…ÿÿÆ /I‰ÅH@H‰D$HD$@H‰D$ HcD$H‰D$(H‰ïè‡ÿÿH…ÀH‰Â„î   LrH‹|$H‰T$L‰öèÜ„ÿÿH‹t$ H‰ßèO·  …ÀH‹T$xÀI|$Ht$@¹$   ó¥A‹D$ % ğ  = `  uH‹D$(I9D$0u’é€   = @  u†€z.t€¾ÉA L‰÷èi†ÿÿ…À„kÿÿÿ¾ÏA L‰÷èT†ÿÿ…À„VÿÿÿHD$@M‰şH‰D$M…ötH‹t$I~èö&  …À….ÿÿÿM‹6ëà‹L$H|$8H‰ÚL‰æèşÿÿ…À„ÿÿÿH‰ïèk…ÿÿ¸   ëH‰ïè\…ÿÿAÆE  1ÀHÄØ   []A\A]A^A_ÃATUI‰üSH‹¥" ‰õH…Ût$H‹;L‰æè³…ÿÿ…Àu9ktW¿ÒA èê"  H‹[ë×ƒ=Ë" ~‰êL‰æ¿ñA 1ÀèP„ÿÿ¿   èr$  L‰çH‰Ãè®$  H‰H‹A" ‰kH‰7" H‰C[]A\ÃATUI‰üS¸A »A ‰õHƒìH‹=p" …öHEØè†ÿÿH‹=~" H‰ÙL‰â¾»_A 1Àè,…ÿÿH‹=e" èà…ÿÿH‹I" Ht$H‰çHÇD$    HÇ$    èû†ÿÿ…Ày
¿   è-‡ÿÿÿÈu‰èƒÈë2H‹<$~Šƒâß€úNt1À€úY”ÀtH…ÿ„zÿÿÿèúÿÿépÿÿÿ¸   HƒÄƒà[]A\Ã‹Gƒà„¨   USH‰û‰õHƒìD‹OH‹=¢" D‰L$è8…ÿÿH‹=±" è,…ÿÿHcD$H‹= " ¾A I‰À¶ĞH‰ÁIÁèI‰ÁHÁéA€à HÁè áÿ  A	ĞH‹% ğÿÿ	Á1Àè%„ÿÿ¾   ¿#A è¨şÿÿ…Àt…ítH‹5G" ¿HA èı‚ÿÿ1ÿè6†ÿÿHƒÄ[]ÃAVAUA‰ÕATU‰õSH‰ûHì   ƒ=é" ~¿VA 1Àès‚ÿÿ¸`«b H‹ H…À„½   ;huH‹0H¼$    èÿÿÇƒ        ë2HƒÀëÍƒ=œ" ~H´$    ‰ê¿—A 1Àè‚ÿÿH¼$    èô±  AƒıÿuD‰+é”  H¼$    1ÀD‰îèŸ„ÿÿ…À‰‰x  è €ÿÿH‹=E" ‹H”$    ¾½A 1Àèƒÿÿ‰ßè|…ÿÿH´$    H‰Â¿ÂA 1Àè   Ht$¿Ä~A èV³  …ÀyèM€ÿÿ‹8èF…ÿÿ¿pA H‰Æ1Àèñ  H¼$    ¾Ä~A HÇD$    èœ€ÿÿH|$H‰Â‰éH‰Şèîúÿÿ1Ò…À”Â‰“    uGLsE1äH¼$    D‰â¾~A 1Àè„ÿÿH¼$    L‰öèÍ²  …Àx)AÿÄAƒü3uÌ¿+A 1Àèn  H¼$    ‰îèBüÿÿéÑşÿÿH¼$    HcÕ¾€a  è«²  …Ày!è‚ÿÿ‹8è{„ÿÿH´$    H‰Â¿ŠA éúşÿÿH¼$    L‰öèV²  …À‰SşÿÿèIÿÿ‹8èB„ÿÿH´$    H‰Â¿QuA éÁşÿÿH¼$    èÓ   H‰ƒ˜   ‹HÄ   []A\A]A^ÃSH‰û‹?ƒÿÿt+è§€ÿÿ…Ày"èî~ÿÿ‹8èçƒÿÿH‹³˜   H‰Â¿EqA 1Àè‹  ƒ»     t7ƒ=i" ~H‹³˜   ‹S0¿OA 1ÀèéÿÿH‹»˜   èı~ÿÿH‹»˜   èê¯  H‹»˜   [éT~ÿÿAVæÿ  AUATU‰õSI‰şÁå»   Hì    H¼$   A‰İL‰öAÁåA¼   èÅ~ÿÿA	íH¼$    œ$  D‰îèÈúÿÿH¼$   ¾÷tA è¹‚ÿÿH´$   D‰âH‰ç1ÀèÄ‚ÿÿD‰îH‰çD	æè“úÿÿAÿÌuØÿËƒûÿuˆHÄ    []A\A]A^ÃAUATI‰üUS‰õHì0  ¾_ƒëaA‰ØAƒàE‰ÅD‰D$AÁåè+øÿÿ…Àt^D‹D$ÑûH¼$  ‰Ù‰Ú¾uA ƒáƒâş1Àè@‚ÿÿH´$  H¼$   èë}ÿÿ¾šA H‰ÇèşÿÿH¼$  ¾¡A èìÿÿI‰ÄëH¼$   L‰æè·}ÿÿ¾÷tA H‰ÇèÊÿÿåÿ  »   ‰îÁæA	õH´$   H|$‰Ú1ÀèÁÿÿD‰îH|$	ŞèùÿÿÿËu×D‰îL‰çè€ùÿÿHÄ0  []A\A]ÃATUSHì   ‹-l" …í~	Eÿ‰_" è4÷ÿÿ…À¾   t¿¿A è<ùÿÿ¾  ¿ÍA ë¿ÛA è&ùÿÿ¾  ¿äA èùÿÿ¾[   ¿íA »   èŒşÿÿ¾[   ¿öA è}şÿÿ¾Z   ¿ÿA ènşÿÿ¾Z   ¿‘A è_şÿÿ¾Y   ¿‘A èPşÿÿ¾Y   ¿‘A èAşÿÿ¾X   ¿#‘A è2şÿÿ¾X   ¿,‘A è#şÿÿ¾9   ¿5‘A èşÿÿ¾9   ¿>‘A èşÿÿ¾8   ¿G‘A èöıÿÿ¾8   ¿P‘A èçıÿÿè>öÿÿ¾ßA …À¸éA HEğ‰ÚH‰ç1Àè`€ÿÿ‰ŞH‰çÿËÎ 	  è+øÿÿƒûÿuÈèöÿÿ…Àu¾   ¿Y‘A èíüÿÿ¾"   ¿b‘A 1Ûè†ıÿÿ¾"   ¿k‘A A¼¦A èqıÿÿ¾!   ¿t‘A èbıÿÿ¾!   ¿}‘A èSıÿÿèªõÿÿ¾³A …À‰ÚIEôH‰ç1ÀèÑÿÿ³   H‰çÿÃè÷ÿÿƒûuÏ¾   ¿†‘A èıÿÿ¾   ¿‘A èıÿÿ¾   ¿˜‘A èõüÿÿ¾   ¿¡‘A èæüÿÿ‰-b	" HÄ   []A\ÃAWAVAUATA‰õUS¾WA H‰û¿ !b ‰ÍHì¸  M‰ÄH‰T$è\  H…Àu%¾WA ¿ !b è\  H…ÛuH…À„°   H‰ÃE1íëH…Ûu	H‰ÃA½   Ht$ H‰ßè9­  …Àˆ@  ‹D$8% ğ  = @  uDH‰ß¾¡A è„|ÿÿ…À¸@tA H¼$°   HDØA‰è¹'`A H‰Ú¾ª‘A 1Àèª~ÿÿHœ$°   éì   =    uH|$H  uéµ  = €  „Ê   H‰Ş¿µ‘A 1Àèf  H¼$°   Hœ$°   ‰éº'`A ¾w’A 1ÀE1íèF~ÿÿ1ö1ÀH‰ßèj}ÿÿA‰Çƒè xE…ít
D‰ÿè{ÿÿë+E…ÿx&1íƒ=ı"  „  L‰âH‰Ş¿å‘A 1Àè}zÿÿéû  Hce" 1Ò·Í9Ğ~HÿÂ9•\§b uğéÄ  =ş   à   Påÿÿ  ‰,…`§b ‰*" éÅ   H¼$°   H‰ŞèayÿÿH|$H‰Ã‰ê¾I”A 1Àè‹}ÿÿ¾/   H‰ßèzÿÿH…À¾.   HDÃH‰Çè
zÿÿH…ÀI‰ÇtWMwHt$L‰÷è{ÿÿ…À„ÿÿÿ1ÀHƒÉÿL‰÷ò®HƒùúuHt$L‰÷èëxÿÿéàşÿÿA€ u
Ht$L‰ÿë¾¥A L‰÷ë¾¥A H‰ßèŞ|ÿÿHt$H‰ßèÑ|ÿÿé¦şÿÿƒ=É"  …¯   ¾¤  H‰ßèÂ|ÿÿ…ÀA‰Çyèxÿÿ‹8èÿ|ÿÿH‰ŞH‰Â¿kqA ë0H‹t$º   ‰Çè¡xÿÿH=   tèÔwÿÿ‹8èÍ|ÿÿH‰ŞH‰Â¿qA 1Àèu  ƒ=\"  tH‰ÚL‰æ¿9’A 1ÀèàxÿÿHt$ D‰ÿè£ª  …ÀyèŠwÿÿ‹8èƒ|ÿÿH‰ŞH‰Â¿ÀYA ë´‹l$xë3ƒ="  tVH‰ÚL‰æ¿R’A 1Àè•xÿÿëBƒ=ô"  t9H‰ÚL‰æ¿
’A ëáD‰ÿèåxÿÿ…Àyè,wÿÿ‹8è%|ÿÿH‰ŞH‰Â¿EqA éSÿÿÿ‰èë1ÀHÄ¸  []A\A]A^A_ÃAUATA‰ÕUSHcïH‰ïA‰ôH‰ëHì¸  è¿ÿÿ…ÀuH‰ïè
¿ÿÿ÷Ğ…èt‰î¿…’A 1Àèv  AƒıH|$‰ŞÒ÷ÒƒâèFõÿÿH´$°   º   ‰Ç‰ÅèŸxÿÿH=   t/H‹=ø:" H‹”$    ¾½A 1ÀèüxÿÿH‹´$    ¿§’A 1Àè  AÿÍ…¾   H”$°   1ö‰Ù1ÿA¸Ø’A èˆûÿÿ‹Œ$h  ¶Á‰ÂÁâ	Ğ·ğ‰òÁâf9„$f  u$	ò9Êuf;„$l  ufÇ„$l    fÇ„$f    fƒ¼$l   D‰¤$h  u
fÇ„$l  ÏÉƒ=o"  u81Ò1ö‰ïè>wÿÿH…Àt¿õ’A 1Àèg  H´$°   º¾  ‰ïèYvÿÿH=¾  uØH|$è€öÿÿè¢xÿÿ‹„$h  HÄ¸  []A\A]Ã1À…ÿ•ÀÃUS‰ûHì¨   ƒ=/ÿ!  uw1ÿè*xÿÿHt$¿“A ‰ÿ! è5¨  …ÀuL‹D$(% ğ  =    u<1ö1À¿“A èyÿÿ…À‰Å~(Ht$º   ‰ÇèwÿÿHƒøu‰ïèŸvÿÿ‹D$1Áş! ‹=»ş! è
wÿÿ‰Ø¹  ™÷ùZ…ÛtèäyÿÿÿË‰˜ş! ëí‹ş! HÄ¨   []ÃAWAVAUATUS‰ı‰óHì  ƒ=9"  Ç´ş!    tƒ=#" ~,‰Ú‰î¿&“A 1Àè©uÿÿë¾“A ¿ !b èU  …ÀtÒ1Àéî  E€ƒø‡  Hcûès¼ÿÿ…À„  ƒå!ÃLcíBƒ<­ §b  …k  Bƒ<­ âb  …\  H|$º   ‰Şè›òÿÿ1Ò1ö‰ÇA‰ÇèluÿÿH…Àyèâsÿÿ‹8èÛxÿÿ‰ŞH‰Â¿N“A ë3H´$   º   D‰ÿèÊuÿÿH=   tè­sÿÿ‹8è¦xÿÿ‰ŞH‰Â¿o“A 1ÀèO  D‹¤$¸  E…ä…†   ƒ=!"  …h  H”$   A¸Ø’A ‰Ù1ö1ÿè°øÿÿéJ  A¾   E…ä„_  fƒ¼$¼   D‰¤$¸  u
fÇ„$¼  ÏÉƒ=Î"  tH‹”$    D‰á‰Ş¿«“A 1ÀèKtÿÿƒ=¨"  „8  H|$èíóÿÿ1À;˜ §b u	‰Ş¿"”A ëD;  âb uD‰æ¿N”A 1Àèƒ  HƒÀHƒø@uÍB‰­ §b F‰$­ âb B‹4­ §b 9óu'ƒ=D" B‹­ âb ~e•€   ‰Ş¿Õ”A 1Àè¾sÿÿëOH¼$°   ƒÊÿèñÿÿH¼$X  ƒÊÿ‰ŞèûğÿÿB‹­ §b L‹„$ğ  ‰îH‹”$H  @€Î€A‰Ù¿ƒ”A 1Àèç  ‰ØéÇ   1Àƒı—À÷Øé¸   ƒÈÿé°   ‰Ø¹  ™÷ùDrE…ö„ŸşÿÿèwÿÿAÿÎA‰ÄëêèwÿÿAÿÎA‰Ä…‡şÿÿ…À…ˆşÿÿ¿“A 1Àè€  1Ò1öD‰ÿè:sÿÿ…Àyè±qÿÿ‹8èªvÿÿ‰ŞH‰Â¿Ş“A éÿıÿÿH´$   º   D‰ÿèFrÿÿH=   „|şÿÿèuqÿÿ‹8ènvÿÿ‰ŞH‰Â¿ ”A éÃıÿÿHÄ  []A\A]A^A_ÃUS¿ø”A Rèàqÿÿƒ=iû!  t?¸ âb ½   HƒèÿÍƒx@ tô1Û‹ §b ‹ âb ³€   1À¿•A HÿÃè<rÿÿ9İ}ÙX[]ÃAWAVAUATUSHì˜  ƒ=´ú!  tÇD$    éO  ¾“A ¿ !b èóQ  …À‰D$uÜHƒ=ÿ!  L¬$  ¹€  Çoú!    L‰ïó«u2¾üUA ¿9WA è‘tÿÿH…ÀH‰Ïş! u¿s–A è÷  ÇD$   éà  HÇD$@    HÇD$(    ÇD$    ÇD$    ÇD$    H‹=…ş! èÈrÿÿ…Àu<H‹|$(H…ÿtèåoÿÿHÇD$(    HÇD$@    H‹Tş! Ht$@H|$(è}tÿÿH…ÀH‹|$(H…ÿ„0  è¥oÿÿé&  H‹|$(Ht$0º
   ètÿÿ…ÀH‰ÅtH‹D$0H9D$(„qÿÿÿ‰ïè··ÿÿ…ÀuBEÄƒøv,Eˆƒøv$ıÿ   u¿ã–A 1Àè  é=ÿÿÿ…ÿÿÿƒøw‰î¿©–A 1Àèä  H‹|$0Ht$8º
   è”sÿÿH‹|$8H9|$0I‰Æ„ışÿÿHt$0º
   è‚qÿÿè]tÿÿH‹H‹D$0H¾öDQ tHÿÀH‰D$0ëæöDQ uHÿÀH‰D$8H‹D$8H¾„ÒuäÆ  H‹\$0º   ¿—A H‰Şè:oÿÿ…ÀtHƒëH‰\$8H‹D$8€8/uHÿÀH‰D$8H‹D$8Ç /devƒ=Aı! Æ@/~H‹L$8D‰ò‰î¿—A 1Àè½oÿÿ‰ëD‰òH‹|$8ãÿ  A¶Æ0ÒÁãH´$°   Áâ	ÃÇ„$à      	ÓèE¡  …ÀA‰Ü‰É   H¼$@  ƒÊÿ‰ŞèÉìÿÿƒ=õ÷!  H‹\$8L‹¼$Ø  ugH‰ßèÎèÿÿƒø~L‰ÿèÁèÿÿ¹*•A ƒø¸@tA HOÈë%¹@tA tL‰ÿH‰L$èšèÿÿH‹L$ƒø¸û•A HMÈL‰úH‰Ş¿9—A 1Àè?  ÿ÷! ëL‰úH‰Ş¿——A 1Àè%  ƒ¼$à   H‹„$Ø  H‰D$8tD‰ò‰î¿±—A 1Àèı  H‹|$8D‰æèêÿÿD‰ãH‰ßè“µÿÿH‰ß‰ÅA‰Æè†µÿÿ÷ĞD!å‰ÃH‹îõ! D!ãH…Àt6;(u,ƒx u,…Û»ÿÿÿÿu#Hƒ=Ëû!  uH‹t$8¿÷—A 1Àè”  ëH‹@ëÅE…ö„Ãüÿÿ…Û»üÿÿ‹5Íö! M‰îL‰é1À1Ò9ò}…À…³  ÿÂ;iDÂHƒÁ8ëæ…À…  1Ò1ö‰ïèµõÿÿƒ=ö! ?A‰Ç~º@   ¾@   ¿2˜A é°	  H¼$è  ƒÊÿ‰îè!ëÿÿHc]ö! HcÕI‰ÔIÁìAäÿ  HkÁ8‰¬˜  H‰ĞHÁè % ğÿÿA	ÄAƒüuHÁê@¶Å‰Ö@€æ 	ğÁæ¶À€Ì@ëNAüş   uHÁê@¶Å‰Ö@€æ 	ğÁæ¶À€Ìë*Aü™   tAƒür‰èuHÁê@¶Å‰Ö@€æ 	ğÁæ¶À€Ì	ğHkÉ8H‹¼$€  ‰„œ  D‰¼°  H‰L$èk  ƒ=Yú! H‹L$H‰„  ~H‹Œ$€  D‰ú‰î¿ì˜A 1ÀèÉlÿÿH‹2ô! H…À„»   ;(…ª   Hc5Nõ! ‹HHkş8H‰„<¨  A€ƒøwoHcD$‰Œ<¸  ‰Œ<À  ƒáH£ÈsEFÿƒé€HcĞHœ$  HkÒ8;Œ¸  H<tÿÈëàHkö8H‹— òÿÿ1À¿™A H‹´4  è¬
  ¸   HÓà	D$ë&ÿÁt"H‹´$€  º   ¿A™A 1Àè
  H‹@é<ÿÿÿH¼$è  èªëÿÿ1ÒH|$hAƒü•Â‰îè¿¹ÿÿLc%yô! H|$h‰îè™~  ‹-gô! Mkä8E…ÿB‰„$¼  t6HcÅHŒ$  1ÒHkÀ8HÈ9ê}1E;~ uAƒNÿD$ƒˆòÿÿÿÂIƒÆ8ëŞHcÅÿD$HkÀ8ƒŒ   E‰ô! DcÿAƒü‡ŞùÿÿH‹|$8hÿèÚO  ¨„ÉùÿÿHcíH„$  McäHkí8HèƒŒ,   ƒ=ø! BÆ„ òÿÿ–ùÿÿH‹L$8H‹´,  ‰Ú¿„™A 1ÀèïjÿÿévùÿÿH‹=û÷! è~jÿÿƒ=?ø! ƒ=6ø! ~>‹5jó! ¿®™A 1Àèºjÿÿë*L‰ë1í;-Qó! }Ö‹S ‹s¿œ™A H‹1ÀÿÅHƒÃ8èjÿÿëÛ‹,ó! Pÿ…Ò1ÛE1íëxL‰èE1ÉAÿÁ‹XD9XL@8~1H¼$è  ¹   H‰Æó¥¹   H‰ÇL‰Æó¥H´$è  ¹   L‰Çó¥D9ÊL‰Àu¸ÿÊë£HcÃHkÀ8‹„˜  Áè%ÿ  =ş   t=™   tÿÃ; ò! |Òé5  ƒ=V÷! ~‰Ş¿Ë™A 1ÀèŞiÿÿ¾æ™A ¿ !b 1íèÂI  …À„   ¿í™A 1ÀA½   èÿ  ë­‹|$HT$H1À¾	€èüiÿÿ…À‰õ   AƒÌÿH¼$è  è<éÿÿƒ=äö! ~D‰æ¿©šA 1ÀèkiÿÿE…ä‰  Hƒ=Êö!  uHcÃ¿½šA HkÀ8H‹´  1Àè‰  ‹-Ûñ! ÿÅ;-Óñ! %ÿÿÿ9İ„ÿÿÿLcõH„$  LcãMkö8IÆƒ=mö! ~IkÄ8A‹v¿bšA ‹”˜  1ÀèèhÿÿMkä8H„$  H¼$è  º   B‹´$˜  N< èæÿÿ…À‰D$‰ÿÿÿI‹· òÿÿ¿hA 1Àè  ƒ|$H uƒ|$LYw¿yšA 1ÀA¼şÿÿÿèË  éêşÿÿ‹|$HT$h1À¾	H€èÅhÿÿ…ÀˆÉşÿÿƒ|$x……   E1ÿD;¼$˜   sx‹|$HT$T¾	€1ÀD‰|$TA¼   è…hÿÿ‹L$\‹t$XÁøA‹~‰Êâ ÿÿÿHÁâI‰Ğ‰òæÿ  â ğÿÿÁæHÁâ L	ÂA‰ğ¶ñD‰Á	ñH	ÊH9×DEàAÿÇE…ätƒé=şÿÿE1äé5şÿÿ„ˆşÿÿLcåMkô8Jƒ¼4¨   uJ¿    èÏ  B‹”4˜  Ç@ÿÿÿÿÇ@ÿÿÿÿÇ@ÿÿÿÿÇ@ÿÿÿÿ‰H‹æî! H‰ßî! H‰PJ‰„4¨  IkÄ8H‹”¨  ƒz tH‹´  ÇB    ¿Y›A 1Àè‚  Mkä81À¿›A ÿÉï! J‹Œ$  B‹”$°  B‹´$˜  èT  HcÅ;£ï! }-P¹   HkÀ8L„  HcÂHkÀ8L‰ÇH´  HcÂó¥ëË1À9İœÀÿÍ)Ãé‰ıÿÿƒ=!ô! ~UHœ$  1í;-Kï! }‹S ‹s¿œ™A H‹1ÀÿÅHƒÃ8èŠfÿÿëÛ¿Ö›A èŞeÿÿƒ|$ uƒ=Øó! ~q¿ğ›A èÄeÿÿëeƒ|$ t^Hœ$  1í‹ïî! 9Å}Ğ‹SöÂt:ÿÈ~¾   H‰ßèÚâÿÿë€âu°D‹cD‰çèvïÿÿº   ‰ÆD‰çèÏíÿÿƒcş‰C ÿÅHƒÃ8ë¬ƒ|$ „ü   E…ít¿œA 1Àè-  ‹î! ÇD$    DpÿH„$  IcŞHkÛ8HÃE1íE…ö~¸IcîH„$  L¬$  Hkí8E1äHÅ‹… òÿÿA9E uz‹…òÿÿA‹Mƒà…Át#1öH‰ßèâÿÿ…ÀD‰òt ¾   L‰ïè	âÿÿD‰âë€áD‰òu…ÀAEÔHcÒLkú8B‹Œ<˜  ‰Ï‰L$è‹îÿÿ‹L$º   ‰Æ‰ÏèáìÿÿÿD$B‰„<°  AÿÄIƒÅ8E9æ…jÿÿÿAÿÎHƒë8é9ÿÿÿƒ=Wò! ƒ=Nò! ~A‹t$¿ìœA 1ÀèÔdÿÿë/Hœ$  1í;-fí! }Ó‹S ‹s¿œ™A H‹1ÀÿÅHƒÃ8è¥dÿÿëÛH‹5ì! D‹9í! A»   ë:HcD$H£Ès!ƒÈÿL„$  ™€   A‰Á1ÿD9×|LAÁéu`L‰ØHÓà	D$H‹vH…ötp‹Nƒù~ï‹‰ĞÁè%ÿ  ƒø	tŞƒáƒù~ ±€   ¿A 1Àè•  A;Pt	A9X(DÇëA‰ùÿÇIƒÀ8ë•‰Ãƒë x™H˜ƒé€¿:A HkÀ8‹´˜  1ÀèX  ƒ=?ñ! ~‹t$¿lA 1ÀèÅcÿÿHœ$  ‹=[ì! 1ÒA¸   H‰Ø9ú}3‹p,ƒş~#ƒx0LcL$‰ñƒáI£Ér‰p0L‰ÆHÓæ	t$ÿÂHƒÀ8ëÉƒ=Öğ! ~‹t$¿A 1Àè\cÿÿ1íE1äA½   D;%îë! 4  ƒ{0KHcD$H£èsÿÅëöƒı0L‰è@ˆé•€   HÓà	D$ƒ=xğ! ‰S0~H‹3¿²A 1ÀèübÿÿëÇC0ÿÿÿÿHƒ{ uH¿    è  ‹SÇ@ÿÿÿÿÇ@ÿÿÿÿÇ@ÿÿÿÿÇ@ÿÿÿÿÇ@ÿÿÿÿ‰H‹#ê! H‰ê! H‰PH‰C‹C0H‹S‰Bƒàƒø‹S H˜‰… âb ‹S‰… §b ëT‹ë! ÇB    P…À‰òê! uº   ¾   ¿ÌA è˜  HcÕê! ¿VA HkÀ8‹”˜  H‹´  1Àèr  Çë!    AÿÄHƒÃ8é¿şÿÿƒ=qï! ~‹t$¿ˆA 1Àè÷aÿÿHcD$¾   H£ğr	ƒşÿtÿÎëñ‹|ê! 9ò¶ïÿÿƒÂƒî€¿§A 1Àè
  ‹D$HÄ˜  []A\A]A^A_ÃSH‰ûH‹=ä! è¨cÿÿH‰ßèpdÿÿ¿   èeÿÿSH‰ûHìĞ   „ÀH‰t$(H‰T$0H‰L$8L‰D$@L‰L$Ht7)D$P)L$`)T$p)œ$€   )¤$   )¬$    )´$°   )¼$À   H‹=ã! è+cÿÿH‹5L$" ¿\ŸA èZaÿÿH„$à   H‹=3$" HT$H‰ŞÇD$   ÇD$0   H‰D$HD$ H‰D$èÏcÿÿH‹5 $" ¿
   ènaÿÿ¿   èDdÿÿSHìĞ   „ÀH‰t$(H‰T$0H‰L$8L‰D$@L‰L$Ht7)D$P)L$`)T$p)œ$€   )¤$   )¬$    )´$°   )¼$À   ÿví! ƒ=‡í!  lH‰ûH‹=¯â! èJbÿÿH‹5k#" ¿¼ŸA èy`ÿÿH„$à   H‹=R#" HT$H‰ŞÇD$   ÇD$0   H‰D$HD$ H‰D$èîbÿÿH‹5#" ¿
   è`ÿÿHÄĞ   [ÃSHcßH‰ßè¸aÿÿH…Àu
¿ÆŸA èşÿÿH‰ÂH‰Ù1ÀH‰×óªH‰Ğ[ÃQHcöèbÿÿH…Àu
¿ÆŸA èçıÿÿZÃQè7cÿÿH…Àu
¿ÆŸA èĞıÿÿZÃS1ÒH‰ûHƒìHt$èÒ`ÿÿH‹T$H…Òt€: tH‰Ş¿ÔŸA 1Àè¾ıÿÿHƒÄ[ÃS1ÒH‰ûHƒìHt$èš`ÿÿH‹T$‰ÁH…Òt?Š„Òt9€úTt4€úMt'€úSt%€úHë
€úmt
€úhukÈ<ë€úst
€úttëkÉ<kÉ
ù Œ  vH‰Ş¿çŸA 1ÀèBıÿÿHƒÄ‰È[ÃATUº   S‰õH‰û¾cA HƒÇèÔ]ÿÿ…Àu‰ïè¹bÿÿ¿ü´A H‰Æë&H{º   ¾cA è¬]ÿÿ…Àt‰ïè‘bÿÿ¿ A H‰Æ1ÀèÜüÿÿD¶cA9ìt‰ïèqbÿÿD‰âH‰Æ¿, A 1Àè¹üÿÿf‹[
fût)D‰çèLbÿÿ¶ÏH‰Æ¶ÓA¹   A¸   ¿N A 1Àè…üÿÿ[]A\Ã1ÀH‹H9uH‹FH9G”À¶ÀÃUSI‰Ê‹‰öE1ÀE1Û÷ĞL9Æt4B¶,¹   ‰ÃA‰éAÓùÁëA1ÙA€áE‰ÙDEÊÀÿÉD1ÈƒùÿuÛIÿÀëÇ÷Ğ[A‰]ÃHƒìHL$ÇD$    è˜ÿÿÿHƒÄÃHì  ºÿ  H‰æèÜ\ÿÿ…À~H˜H‰æ¿| A Æ 1ÀèS]ÿÿHÄ  ÃAWAVA‰ÖAUATI‰üUSA‰õ‰ËD‰ÅHƒìH‹?Š„Òt*ˆT$H‰<$èaÿÿH¾T$I‰ÇH‹ H‹<$öPt.HÿÇI‰<$…í„·   ƒ=ê!  „ª   1ÀAÿÍ”À)Ã¯İé˜   1ÒL‰æè;^ÿÿ…í‰Ã‰Ât7I‹$Š
ƒáß€ùPuHÿÂI‰$™÷ı1ÒAƒı”ÂÂë1ÒAƒı”Â)Ğ‰Ú¯Å‰ÃD9ê|D9ò~H‹5kì! D‰ñD‰ê¿ƒ A 1ÀèãúÿÿI‹$¾0@„öt I‹H¾ÖöQu¿¢ A 1Àè¾úÿÿHÿÀI‰$ƒ=é! ~‰Ş¿º A 1Àè&\ÿÿHƒÄ‰Ø[]A\A]A^A_ÃUSH‰ûHìØ   ƒ=jé!  ~H…ÿ¾Æ A HE÷¿á A 1Àèè[ÿÿH…ÛH‰îü! t¾¡A H‰ßèÿ\ÿÿ…À…¤   Ht$@¿¡A èx  …Ày
¿ş A èúÿÿH‹l$@H‰èHÁè‰ÂH‰èHÁè âÿ  % ğÿÿ	Ğƒø	t#H‰ïèu¢ÿÿ÷ĞH!ÅHƒıv‹t$@¿¡A 1ÀèÚùÿÿH‹t$@º   ¿€¿b ‰5 " è§Øÿÿ‰<ü! H‹ı! Ç/ü!    H‰8ü! é‡   1À¾   H‰ßèÄ]ÿÿ…À‰ü! yèÅYÿÿ‹8è¾^ÿÿH‰ŞH‰Â¿ÂA ë'Ht$@‰ÇèµŒ  …ÀyèœYÿÿ‹8è•^ÿÿH‰ŞH‰Â¿QuA 1Àè=ùÿÿ‹D$X% ğ  = `  tÇe"     ëH‹D$h‰X" H‹5¥û! H|$1Òè½ÿÿ‹D$H|$‰:" èº¿ÿÿ‹=+" …ÿtèâ®ÿÿ…ÀuH…Û¾Ô A ¿;¡A HEóè˜ùÿÿ‹=Bû! º   ¾@Íb è[ÿÿH=   t'èêXÿÿ‹8èã]ÿÿH…ÛHDàû! H‰Â¿qA H‰Şé>ÿÿÿ¿@Ëb ¾@Íb ¹€   ó¥H‹= û! è€>  º   ƒø	DÂ‰*ç! ÿÈ~Sƒ=ç!  tJH‹5Öú! 1À¿W¡A ‹õæ! Çëæ!     èöøÿÿ1ö¿¡A è€Õÿÿ…Àu1ÿè#]ÿÿ‰Éæ! ÇÓæ!     HÄØ   []ÃUSH‰şQH‰ı¿€+b èÄ9  H…ÀuH‰î¿›¡A 1ÀèÌ÷ÿÿ1öH‰ÇH‰Ãè\ÿÿ…Àu¸   ëD¾¬¡A ¿ b è 9  …Àtƒ=ˆæ!  x&H‰Ş¿µ¡A 1ÀèYÿÿë¾¬¡A ¿ !b èó8  …ÀuÓë·1ÀZ[]ÃATU1ÀSHƒÉÿI‰üH‰õò®H÷ÑHYÿè;r  ‰ŞL‰ç1Ûèvr  èür  D‹$`ãb D‰d ƒ=æ! ~ H…Ûu¿Â¡A 1ÀèœXÿÿD‰æ¿ÆA 1ÀèXÿÿHÿÃHƒûuÁƒ=åå! ~[]A\¿
   éWÿÿ[]A\ÃAWAVAUATI‰ÔUSH‰óHƒìH…ö…G  ¾/   H‰ıè^XÿÿH…À„.  HX¾    H‰ßèXÿÿH…ÀtH‰Ş¿Õ¡A ë:€ú uÆ _HÿÀŠ„Òuï1ÀHƒÉÿH‰ßò®H÷ÑHAÿHƒøH‰$wH‰ØëH‰Ş¿¢A 1ÀèNöÿÿHÿÀŠ„Òt€úwòH‰Ş¿M¢A ëáHc­ø! ‹£ø! ‰D$I‰ÖHkÒ6E‰õHª@Äb D;l$‡   H‰îH‰ßè4Vÿÿ…Àu
H‰Ş¿¢A ëAöD$3McıtHƒ<$tIkÇ6ö€sÄb tCHƒÉÿ1ÀH‰ïò®Hƒùıu2è±UÿÿIk÷6H¾;H‹ H¾@Äb ‹ˆ9¸uH‰êH‰Ş¿¢¢A 1ÀèõÿÿAÿÅHƒÅ6énÿÿÿE…öt2¾£A ¿ !b èR7  H…ÀtH‰ŞH‰Çè”Uÿÿ…ÀuÇÎ÷!     E1íë:D‹-¾÷! Aƒıu¾   ¿Â¢A ë‹5zN! A9õ|¿å¢A 1ÀèõÿÿAE‰‹÷! Mcõ¹6   L‰æIkî6HÅ@Äb H‰ïó¤H‰ŞH‰ïè±Uÿÿ¾£A ¿ !b èÀ6  H…ÀtH‰ŞH‰ÇèUÿÿ…ÀufM2 €0æ! ¾£A ¿ !b è6  H…Àt1H‰ŞH‰ÇèÒTÿÿ…Àu"Mkö6€æ! fArÄb  @ëH‰ëH‰ØéòıÿÿHƒÄD‰è[]A\A]A^A_ÃAVAUATUS€? u
¿%£A é   I‰ıH‰õ¿ b ¾9£A ƒËÿè6  H…ÀI‰ÄtH‰êH‰Æ1ÿè>ıÿÿ‰Ã¾?£A ¿ b èó5  L‰ïH‰êH‰ÆèıÿÿöE3A‰ÅtPHcøHƒÊÿ1ÀHkÿ6H‰ÑHÇ@Äb ò®H÷ÑH‰ÏH×Hƒÿv(M…ätH‰ÑL‰çò®H‰ÈH÷ĞHĞHƒøv¿E£A 1Àè¨óÿÿƒ=â!  ˆí   Mcõ1À¿”£A Ikö6HÆ@Äb èUÿÿM…ätL‰æ¿£A 1ÀèóTÿÿIkÆ6ö€sÄb u…ÛxHcÃHkÀ6ö€sÄb t¿©£A 1ÀèÆTÿÿIkÆ6ö€sÄb @u…ÛxHcÃHkÀ6ö€sÄb @t¿­£A 1Àè™TÿÿMkö6Aö†rÄb  u…Ûx4HcÃHkÀ6ö€rÄb  t$¿ !b ¾ğ‡A è]4  …À¿±£A t¿µ£A 1ÀèSTÿÿE…ít…Ût¿
   èàRÿÿë
¿¹£A è”Sÿÿƒ=•á! ~B¶M0¶U/1ÀD¶M-D¶E.¾@tA ¿½£A èTÿÿ€=±á!  tº ¬b ¾@tA ¿â£A 1ÀèéSÿÿƒ=Já!  ~[]A\A]A^¿
   énRÿÿ[]A\A]A^ÃATU¾×VA S¿ !b è4  ¾R­A H‰Å¿ !b èş3  H…íI‰ÄuH…À»`^b ¸@8b HEØëJ¾ÈÚA H‰ï»€‚b èCWÿÿH…Àu3¾ï£A H‰ï»`^b è,WÿÿH…Àu¾pÙA H‰ïèWÿÿM…äuH…Àt»@8b èæa  …À‰òJ! ƒ=à! 	Hû@8b u¿ô£A 1ÀèZòÿÿHû`^b uƒ=ÂJ! u¿4¤A 1Àè<òÿÿHû@8b u4‹¥J! Pÿƒúw&ƒø¾·ÑA tÿÈ¾7¸A ¸ë£A HDğ¿¤A 1ÀèÿñÿÿH‰Ø[]A\ÃSH‰óHƒìH…ÿH‰|$uƒ=ºß!  „ì   fÇCNÿÿfÇCLÿÿéÛ   ¾;İA è!Qÿÿ…Àtá¿KNH|$A¸   ºL   ¾   HÇ9â! ¥A èùôÿÿ¿KLH|$f‰CNA¸   º   ¾   è×ôÿÿf‰CLH‹D$€8 u	ƒ=5ß!  tk¿K:‹ñH! H|$E1À1öè§ôÿÿƒ=ß!  f‰CFt¿È3ÌH! ë¿KH‹ÀH! H|$E1À1öèvôÿÿ¿KF‹§H! H|$f‰CHE1À1öèYôÿÿf‰CJHƒÄ[ÃUSHƒìH…ÿH‰|$uƒ=«Ş!  „º  HÇD$@tA f‹F2¹   H|$H‰óA¸   ¾   HÇ=á! ¥A ½   ‰ÂfÁúf÷ùºA   ˜Hèæóÿÿf‰C2‹C0H|$A¸   ¾   ‰ÂfÁúf÷ıº   ˜Hè¸óÿÿ¿K4H|$E1À¾   f‰C0º   è™óÿÿƒ=Ş!  f‰C4‹s0t‰ò‰ğ¹   fÁúf÷ı˜)Áë¿K6‰ò¿   ‰ğfÁúE1À¾   f÷ÿH|$º   ˜)ÂèFóÿÿf‰C6‹C8¾   ¿{4‰ÂfÁúf÷şfƒÿ¿Èf‹C2‰ÂufÁúf÷şºP   ˜)ÂëfÁúf÷şºP   ˜k÷ñ)ÂÿÏ‰Ğğ™÷ÿPH|$A¸   ¾   èÚòÿÿ¿S6¿KPH|$E1Àf‰C8¾   è¼òÿÿf‰CP¿C6¿S0ÁàĞ=à   ¿C4Pÿ¿C8¯Â¿S2„€   =€  ~¿¥A 1ÀèïÿÿHƒÄ[]ÃSHƒìH…ÿH‰|$uƒ=ÎÜ!  „í   HÇD$@tA ¿N:‹}F! H|$H‰óE1À1öHÇeß! <¥A è%òÿÿH‹T$f‰C:€: uƒ=ƒÜ!  „¢   ‹?F! H|$E1À1ö¿Èèòñÿÿ¿K:‹#F! H|$E1À1öf‰C<èÕñÿÿ¿K@‹F! H|$E1À1öf‰C>è¸ñÿÿH‹T$f‰C@€: u	ƒ=Ü!  t9‹ÖE! H|$¿ÈE1À1öè‰ñÿÿ¿K@‹ºE! H|$f‰CBE1À1öèlñÿÿf‰CDHƒÄ[ÃUS‰ûQƒ=	Ü! ~‰ş1À¿G¥A è‘Nÿÿ…ÛuH‹=vÿ! H…ÿ„   Z[]éNÿÿƒ=ÒÛ!  ußH‹=Uÿ! H…ÿtÓ1Ò1öè·Pÿÿ…Àt
¿b¥A è)QÿÿH‹òİ! H…Ût°H‹S H‹="ÿ! ¾q¥A 1À1íètOÿÿ‹+H‹=
ÿ! 1À¾~¥A HƒÅèZOÿÿHƒıuàH‹5íş! ¿
   è£NÿÿH‹[(ë«X[]ÃUSHì  ƒ=AÛ! ~
¿Ç¥A è-MÿÿH‹=¶ş! 1Ò1öèPÿÿ…Àt
¿Ç¥A èPÿÿH‹˜ş! H|$¾ÿ  è©NÿÿH…À„  ƒ=ñÚ! ~Ht$¿†¥A 1ÀèvMÿÿH|$¾>   è‡MÿÿH|$¾<   H‰ÃèEMÿÿH…ÀH‰D$„¬   €x"…¢   H…Û„™   €{ÿ"…   ÆCÿ ¿0   èHíÿÿH…ÀH‰Åu
¿ÆŸA èbëÿÿH‹³Ü! HÇE    H‰-¤Ü! H‰E(H‹D$HxèUíÿÿƒ=CÚ! H‰E ~H‰Æ¿¥A 1ÀèÆLÿÿH{1ÛHt$1ÒèÄOÿÿ‰D HƒÃHƒû„óşÿÿH‹|$ëÛ¿¦¥A 1Àè	ëÿÿƒ=ğÙ! ~
¿Ã¥A èÜKÿÿHÄ  []ÃH…ÿH‰út-1ÀHƒÉÿò®H÷ÑAÿ1ÉHcğHÖHÿÉ…ÀtÿÈÆ ëñH‰×éÍJÿÿÃUS¿@tA QèÏNÿÿH‰ÅHƒÉÿ1ÀH‰ïò®H‰ïH÷ÑHYÿè…ìÿÿHcû1ÒH‰ùHï…ÉtÆ ÿÉHÿÊëñZ[]ÃAUATI‰ıUSI‰ôR¾?£A ¿ b è6,  H…ÀH‰Ãu3¾`VA ¿€+b è,  H…ÀH‰Ãu¿€+b ¾Õ¥A è,  H…ÀH‰Ã¿Û¥A tl¾/   L‰ïè°KÿÿH‹-9Û! HPH…ÀHEÚH…ít1H‹EI9Å„ë   H…ÀuH‹} H‰Şè‹Lÿÿ…Àu	L‰méÍ   H‹m(ëÊ¿0   èjëÿÿH…ÀH‰Åu¿ÆŸA 1Àè¤éÿÿH‹ÓÚ! H‰ßL‰mH‰-ÅÚ! H‰E(èëÿÿH‰ŞH‰E ¿ö¥A 1ÀèùJÿÿ¿9¦A 1ÀèíJÿÿè¬şÿÿ¿K¦A I‰Å1ÀèÙJÿÿè˜şÿÿL‰îH‰ÇH‰ÃèöKÿÿ…Àt¿¦A èJÿÿH‰ßè>şÿÿL‰ïè6şÿÿë­¿
   è<IÿÿL‰ïè"şÿÿH‰ßH‰îè—ñÿÿH‰ßèşÿÿL‰çH‰î¹   ó¥X[]A\A]ÃAVAU1ÀATU¹6   Sº ¬b H‰ûHì  L¤$   óª1À¹€   L‰ç…öó«¹€   H‰×ó«„  ¾]¦A ¿ b è*  …Àu¾]¦A ¿ !b èù)  …Àuë0¾g¦A ¿ b èä)  …ÀtØ¿r¦A é  ¾g¦A ¿ !b èÇ)  …Àuã¾]¦A ¿ b è´)  …Àt¾ ¦A ¿ ¬b èMÿÿë¾]¦A ¿ !b è)  …ÀuÜ¾g¦A ¿ b è})  …Àt¾¤¦A ¿ ¬b èÕLÿÿë¾g¦A ¿ !b èY)  …ÀuÜ¾ZA ¿ b è¯)  H…ÀH‰Åu¾ZA ¿ !b è˜)  H…ÀH‰Å„@  ¾¨¦A H‰ïèÑGÿÿ…Àu/H‰æ¿¡A èĞz  …Ày
¿ş A èZçÿÿ1ö¿ ¬b èæHÿÿ‹$éñ   1ÀHƒÉÿH‰ïò®H‰ÊH÷ÒH‰ÑHÿÉHƒùvº   ¾¹¦A H‰ïèïGÿÿ…Àuë6Hƒùvº   ¾Ï¦A H‰ïèÑGÿÿ…Àuëu6º   ¾Ö¦A H‰ïè·Gÿÿ…Àu 1ö¿ ¬b ègHÿÿH‰êH‰Ç¾Æ¦A 1ÀèåKÿÿëuH‰æH‰ïèz  …Àx‹l$(ëCèILÿÿH¾U H‹ öDPuH‰î¿Ü¦A éİ  ƒ=Õ!  ~H‰î¿ş¦A 1ÀèHÿÿH‰ïè—èÿÿ‰Å1ö¿ ¬b èïGÿÿ‰êH‰Ç¾°¦A 1ÀènKÿÿ¾?§A ¿ b è=(  H…Àu¾?§A ¿ !b è)(  H…Àt'H‰ÇèHèÿÿ1ö‰Å¿ ¬b è Gÿÿ‰êH‰Ç¾G§A 1ÀèKÿÿ¾S§A ¿ b èî'  H…ÀH‰Åu¾S§A ¿ !b è×'  H…ÀH‰ÅtmfƒK2¾W§A H‰ïèFÿÿ…ÀufÇC4ÿÿëO¾ÉÚA H‰ïèöEÿÿ…Àt¾ÙÑA H‰ïèåEÿÿ…ÀufÇC4şÿë%¾^§A H‰ïèÌEÿÿ…ÀufÇC4ıÿëH‰ïè’çÿÿf‰C4¾§A ¿ !b èS'  ¾§A ¿ b H‰ÅèA'  H…ÀH‰ÆuH…ítKH‰î1ÀHƒÉÿH‰÷ò®H‰ÊH÷ÒH‰ÑHÿÉHùÿ  v¾ÿ  ¿b§A 1Àèåÿÿ¿ ¬b èøIÿÿ¾.ØA H‰ÇèëIÿÿ¾|§A ¿ b èÚ&  H…ÀI‰ÅtSH…íu¿†§A 1Àè¯åÿÿHƒÎÿ1À¿ ¬b H‰ñò®L‰ïH‰ÊH‰ñò®H÷ÒH‰ÈH÷ĞHDşH=ÿ  ‡{ÿÿÿL‰î¿ ¬b èIÿÿ¾«§A ¿ b èp&  H…ÀtH‰Æ¿ ¬b è@Eÿÿ€=©Ó!  t1ö¿ ¬b èÛEÿÿ€xÿ uÆ@ÿ ƒ=BÓ! ~¾ ¬b ¿³§A 1ÀèÇEÿÿ1ÀHƒÉÿ¿ ¬b ò®H‰ÊH÷ÒH‰ÑHÿÉHùÿ  v¾ÿ  ¿È§A èâäÿÿ½`b ë
€xÿ t'HƒÅL‹m M…ít3L‰î¿ ¬b è?IÿÿH…ÀtáH= ¬b uÓ€x=…  L‰î¿õ§A 1ÀèÃãÿÿ¾§tA ¿ b è/%  …ÀtfƒK2ë¾§tA ¿ !b è%  …Àuæ¾¨A ¿ !b è%  …Àu¾¨A ¿ b èï$  …Àu!ë2¾'¨A ¿ !b èÚ$  …ÀtØ¿1¨A 1ÀèOãÿÿ¾'¨A ¿ b è»$  …Àuá¾a¨A ¿ b è¨$  …ÀtI¿ b ¾'¨A è•$  …À¿h¨A u»¿ b ¾¨A è}$  …À¿”¨A u£¿ !b ¾S`A èÎ$  H…À¿Á¨A tŒ¾S`A ¿ b èµ$  H…ÀH‰Åt¿ b ¾a¨A è5$  …À¿í¨A t7éVÿÿÿ¾S`A ¿ !b è$  H…ÀH‰Å„¼   ¾a¨A ¿ b èı#  …À…¥   €}  Lk…†   Hƒ=šÓ!  uè¤$  H…Àtèğõÿÿ¾S`A ¿ b è($  H…Àu¾S`A ¿ !b è$  L‰îH‰Çè·÷ÿÿƒ=Ñ! ~A¿©A 1ÀE1öè“CÿÿC‹t5 1À¿ÆA IƒÆè~CÿÿIƒşuå¿
   èBÿÿëL‰îH‰ïèoêÿÿfK2€ ¾&©A ¿ b èA#  …ÀtfK2 €*Ó! ¾-©A ¿ b è!#  …ÀtfK2 €
Ó! f‹C2¿7©A f% f= „(şÿÿ¾c©A ¿ b èê"  …ÀtfK2 €€ÓÒ! ¾'¨A ¿ b èÊ"  …ÀtH…íu¿o©A éæıÿÿ¾'¨A ¿ !b è¨"  …ÀuŞ¾¨A ¿ b è•"  …ÀtH…íu¿›©A é±ıÿÿ¾¨A ¿ !b ès"  …ÀuŞë öC2€t¾'¨A ¿ b èX"  …ÀufƒK2ëH…ít,€}  t&ƒ=†"  tH‹5" ¿È©A 1Àè}áÿÿÇg"     ¾ş©A ¿ b è"  …ÀtfK2  ë¾ş©A ¿ !b èò!  …Àuå¾	ªA ¿ b èß!  …ÀtfK2 ë¾	ªA ¿ !b èÄ!  …Àuå¾JbA ¿ b è"  H…ÀH‰ÅtOf‹C2¿ªA ¨…ÇüÿÿƒÈ@I|$H‰îf‰C2fÇ„$   òôèÅ@ÿÿHczÑ! H‰ïC‰nÑ! èàáÿÿH‰İ`®b è&}ÿÿL‰çè |ÿÿ¿ ¬b è–|ÿÿHÄ  []A\A]A^Ãö@ß„Üûÿÿé¦ûÿÿSH‰óèåÿÿH‰ß¾@Íb ¹€   ó¥‹=â! [é{AÿÿAWAVº@Êb AUAT1ÀUSI‰şH‰×H‰óE‰ÄHìH  ÇÕá!     ÇÇá!     ‰$¹@   H´$°   ó«H‰ßD‰L$ètr  …Àx‹„$È   % ğ  = €  t
H‰Ş¿eªA ë)L‰÷èväÿÿ‹=A" ¾   è'  ƒ=ÄÍ! ~L‰ö¿ƒªA 1ÀèİŞÿÿuL‰ö¿¹ªA 1Àèßÿÿ¾:   H‰ßH‰Ká! è^@ÿÿH…ÀI‰ÆuH‰Ş¿@¯b èi?ÿÿ¾ìªA H‰Çè|Cÿÿë-H‰Ş¿@¯b Æ  èJ?ÿÿ¾ìªA H‰Çè]CÿÿIvH‰ÇèQCÿÿAÆ:¿@¯b èşwÿÿ¿@¯b è¾o  D‹5Öî! èìÿÿƒ=.Í!  H‰Ã~-H=@8b ¾BªA tH=`^b ¾=ªA ¸IªA HDğ¿îªA 1Àè”?ÿÿ¸@Íb ¾¤b ¹¶  H‰Çó¤D‰5}î! Lsè6{ÿÿ‹3L‰÷èŠÿÿH‰Ï! ¸ ®b ¹   H‰ÇL‰öº   ó¥¹   ¾c   ¿@Âb è ÿÿƒ=•Ì! Çå! LILO~%H	¾oVA º@tA ¿	«A Áá	ƒøHEÖ‰Æ1Àèü>ÿÿ·s¿9«A @€şf‰5àÎ! …  ƒ=CÌ! ~¿i«A 1ÀèÍ>ÿÿèzÿÿ¿@Âb èzÿÿ1Ò¹   ¾   ¿^Íb è”~ÿÿ‹f" 9\" …v
  ƒ=¯Ë! tƒ=Ê"  tƒ=E" tfƒí! @ö0" €t4ƒ=§"  u+¾“A ¿ !b èG  …Àu‹" ƒÀ€H˜‹… âb ‰>í! ƒ=—Ë! ~,‹3í! D‹(í! ¿ƒ«A ‹Ù" ‹5Ï" 1ÀfÁéƒáè>ÿÿH´$°   ¿@¯b è¯o  …À¿É«A ˆ
  ƒ=CË! H‹´$  ‰5Éì! ‰5£Í! ~¿ä«A 1Àè¹=ÿÿ¾NªA ¿ !b fÇ”î! Uªèÿ  ¾R­A I‰Æ¿ !b èí  M…ötH…À¿ú«A …¡	  Hû@8b fÇTÍ!   uö\Í! I‰Æu¿(¬A 1ÀèÜÿÿéC  M…ö„:  ƒ=¥Ê!  ~6Hû@8b ¸R­A ¾NªA HDğL‰ò¿[¬A 1Àè=ÿÿL‰÷èßÿÿ¿
   è¥;ÿÿH|$x1ÒL‰öètŸÿÿH´$°   ‰ÇA‰Çè´n  …Àyè›;ÿÿ‹8è”@ÿÿL‰öH‰Â¿QuA éø  Hû@8b tH¼$à   ¦   Â  HL$HHT$ Ht$D‰ÿè‰]  …ÀyèI;ÿÿ‹8èB@ÿÿL‰öH‰Â¿qA é¦  t	ƒø¨   ƒ=ÈÉ! ~·L$,D·D$.¿n¬A ‹T$(‹t$$1Àè?<ÿÿƒ|$ (ub|$$€  uX|$(à  uN·T$,·D$.¯ÂPüƒâûu9Hû@8b ¿š¬A …"  ƒøå  ƒ=±3! Ø  ¿º¬A 1Àè'ÛÿÿéÇ  Hû@8b ¿F­A …İ  éä  Hû@8b ¿Y­A …Æ  éÍ  Hû@8b ‰ÈuHA¹   H™H÷ùf‰pË! èIwÿÿH‹„$à   ¹   H|$x1öHÿ  H™H÷ù‰Âè‚|ÿÿ1ö¿Ëb è¦wÿÿƒ=²È! ~4ƒøºoVA ¹@tA HEÊ¾VªA Hû@8b º]ªA ¿†­A HEò‰Â1Àè;ÿÿH|$xèO ÿÿ¾˜­A ¿ !b èğ  …Àt€ßÊ! ¾®­A ¿ !b èÖ  …Àt€ÅÊ! E…äy¿¹­A 1ÀA¼È   èÚÿÿ¾ì­A ¿ !b è  H…ÀH‰Å„@  ö–Ê! ¿ó­A „·  ¾0@„öt¿b èp:ÿÿH…ÀuH‰î¿®A éúÿÿºb ÆEÊ! £)ĞÿÀˆ:Ê! ŠE„À„¿   <,uA½Àb E1ÀL}ëA¿H®A éU  1ÀHƒÉÿL‰ïò®L‰îL‰ÿH÷ÑHÿÉLcñL‰òè>9ÿÿ…ÀD‹D$„-  Ol5AÿÀA€}  D‰D$u½é  H-¡b º   ÑøƒøDÂAˆÀÅ    AƒàA÷ĞE!ÇDˆø	Ğˆ™É! AŠV„Ò…1  ƒ=Ç! ~¶5}É! ¿â®A 1Àè9ÿÿƒ<$$¾¢]A ¿ !b èn  …Àu¿ù®A è·ØÿÿÇ$   ¾¢]A ¿ !b èJ  …À¾0¯A ¿ !b •À¶Àf	Hè! è,  …Àt¿M¯A 1ÀèsØÿÿfƒ+è! èâ=  …Àu"öÓı! €tfè! € ƒ=eÆ! ¿t¯A ëƒ=UÆ! ~
¿¯A èA8ÿÿ¾ã‡A ¿ !b èÇ  …Àt¾ğ‡A ¿ !b è´  …Àufƒ¿ç!  ‹Æ! f	²ç! <$ Œ  ‹D$‰•ç! t i$   ¹•  ¿Ï¯A ™÷ù=ÿÿ  ~
é˜  ¸ÿÿ  Aü Œ  f‰FÈ! t0AiÄ   ¹•  ™÷ùƒøÿ‰Âu	f‰%È! ë=şÿ  ¿ô¯A ~
éS  ºşÿ  f‰È! ¾°A ¿ !b èq  H…ÀH‰Åu1Àˆ€@Àb HÿÀH=   uïë_1öH‰Ç1Àèš:ÿÿ…ÀA‰Äyè6ÿÿ‹8è—;ÿÿH‰îH‰Â¿ÂA 1Àè?Öÿÿº   ¾@Àb ‰Çè„8ÿÿH=   tH‰î¿$°A é5÷ÿÿD‰çè8ÿÿ¸pÊb Ht$P¹
   H‰Çó¥¾G°A ¿ !b èÒ  H…ÀH‰Å„–  öZÇ! u¿S°A 1ÀèŸÖÿÿA¾@Êb A¿DÊb D¾m E„í„Ã   D‰î¿b è7ÿÿH-b H‰$ƒ<$vD‰îë5ŠU„Òt$D¾â¿b D‰æèï6ÿÿH-b ƒøI‰ÅvD‰æë
¿°A é  ¿~°A 1ÀèPÕÿÿDŠeE„ät"èÈ:ÿÿH‹ I¾ÔöPtHƒÅë¿¹°A éĞ  HƒÅAƒıv¿Ù°A 1ÀèáÕÿÿDŠ$$AÁåIÿÆE	ìAƒäEˆfM9÷…/ÿÿÿ€=câ!  u¿±A 1Àè­ÕÿÿÆNâ! €=Hâ!  uŠ?â! ˆÂÀèÁâƒâp	Ğˆ-â! €='â!  uŠâ! ˆâ! €=â!  uŠ
â! ˆâ! ƒ=oÃ! Çíá! MENU~)¶êá! ¶âá! ¿>±A ¶5Õá! D¶Ğá! 1ÀèÒ5ÿÿ¾ƒ±A ¿ !b è!  H…ÀH‰Åtfö­Å! u¿±A 1ÀèòÔÿÿ1ÀHƒÉÿH‰ïò®H÷ÑHÿÉHƒù%v¾%   ¿¸±A èÌÔÿÿ¿IÊb º%   H‰îèn4ÿÿ¿IÊb 1ÀHƒÉÿò®H÷ÑHÿÉˆMá! ¾¥A ¿ !b è¤  H…ÀH‰Åtö0Å! u¿Ö±A 1ÀèuÔÿÿ¾@Êb H‰ïè‚ãÿÿHû@8b u,¿50á! ¿+á! ¯ğƒ=cÂ! ‰5½,! ~¿ÿ±A 1Àèç4ÿÿ¾<¥A ¿ !b è6  H…ÀH‰ÃtöÂÄ! u¿²A 1ÀèÔÿÿH‰ß¾@Êb èòäÿÿ¾¥A ¿ !b èı  H…ÀH‰Ãtö‰Ä! u¿@²A 1ÀèÎÓÿÿ¾@Êb H‰ßèÊáÿÿº@Äb 1À¹€  H‰×¾£A ó«¿ !b è³  H…ÀtÇ>Õ!    Ç0Õ!    ƒ=Á!  ë   ¿
   èÅ2ÿÿéÜ   ¿i²A 1Àè`Óÿÿéœõÿÿº   H‹Œ$à   HcÂH9ÁNøÿÿL‰ö¿k­A 1ÀèaÒÿÿºÿÿ  ëÖ¿²A 1ÀèNÒÿÿAƒø¸
   Nt5DDÀE‰ÇAÑøAÁçE	ÇAƒçäAƒÏDˆ=‰Ã! A¾6@„ö„ïùÿÿ¿¡b è3ÿÿH…À…ùÿÿL‰î¿z®A éóÿÿJÉ¿°®A €ùw‘€ú7uƒàşëƒÈˆ<Ã! A€~ ¿Ë®A „ŸùÿÿéiÿÿÿHÄH  []A\A]A^A_Ãƒ=#Ô!  ¸ÿÿÿÿDÔ! ÃR¾£A ¿ !b èl  H…Àt:‹5÷Ó! º@Äb 1À9ğ}f‹J2HƒÂ6öÅt€å¿´²A të	ÿÀëß¿ã²A 1ÀèIÑÿÿXÃR¾£A ¿ !b è  H…Àt:‹5¦Ó! º@Äb 1À9ğ}f‹J2HƒÂ6öÅ@tf…É¿³A yë	ÿÀëß¿6³A 1ÀèøĞÿÿXÃAVAUA¾(Êb D‹-gÂ! ATUS1íA9í~_H‹í`®b Š< uHÿÃëõ„ÀtCH‰ØŠöÂßtHÿÀëô„ÒtÆ  A¼@Äb H‰ŞL‰çèÒ0ÿÿ…ÀtIƒÄ6M9æuèH‰Ş¿RqA 1Àè€ĞÿÿHÿÅëœ[]A\A]A^Ãf‹Ø! f%‚ fƒÀ€u&R¾®­A ¿ !b èÌ  …Àt¾@Äb ¿X³A 1Àè<ĞÿÿXÃUS‰ÕHì  …Ò‰¤   ºËb ¾ Ëb ¿@Äb èkÿÿ¿ØÊb èfÿÿf‰LŞ! ¸˜Êb ¾ âb H‰Ç¹   º@Êb ó¥H‰Ö¿@Áb ¹@   º·Áó¥¾ø  ¿@Àb è±Óÿÿ‰.Õ! èmÿÿ¿@Àb èlÿÿ1É1Ò¾   ¿:®b èqÿÿH‹5ÕÀ! ¿ ®b è±kÿÿ…íˆ;  ë7‹¿õ! A¸}ŸA º@Ëb èµÿÿ…Àtƒ=x¾!  u‰p¾! ‰Şß! …í„%ÿÿÿ‹=ÈÑ! 1Ò1öè1ÿÿH…Ày+èy/ÿÿ‹8èr4ÿÿH‹5»Ñ! H‰Â¿ qA H…öHD5`Ò! é¼  ƒ=Ü½!  H‰ã„¾   €=lß! úA¹@Íb …«   ·]ß! ¸ş  ¿³A )È…É‰Ê„&  %ğÿ  ¾@Ëb ¹€   LcÀH‰çIà=€   ó¥·ÊL‰ÇL‰Îó¤PşÆ$ëÆD$ˆT$ëPıÆ$éf‰T$PHcÒ€<ëu#PHcÒ¶THcÊ€<¸uÿÂÁøHcÒfƒ=;½!  ~¿µ³A è'/ÿÿë¾@Íb ¹€   H‰ßó¥ƒ=½! ~;Hc=bô! è›vÿÿ‹5Wô! ‰Â¿Ö³A 1Àè/ÿÿ‹t$‹T$¿´A 1ÀfÁîƒæèr/ÿÿHc='ô! è`vÿÿ…Àt<Hc=ô! èPvÿÿ÷Ğ…
ô! u&H³¶  ºH   ¿öÎb è60ÿÿ…Àt¿&´A 1Àè Íÿÿè1ÿÿƒ=~¼!  uH‹=Ğ! º   H‰Şè….ÿÿH=   t-è¸-ÿÿ‹8è±2ÿÿH‹5úÏ! H‰Â¿qA H…öHD5ŸĞ! 1ÀèJÍÿÿƒ=ÉÏ!  t¿€¿b èv®ÿÿë8‹=±Ï! è /ÿÿ…Ày)¿\´A 1ÀèìÍÿÿè[-ÿÿ‹8èT2ÿÿH‹5Ï! H‰Â¿EqA ë¬…í]‹=©»! èÇßÿÿ¿@¯b èƒ^  H‹5kÏ! ¿@¯b èI1ÿÿ…Ày3¿\´A 1Àè•Íÿÿè-ÿÿ‹8èı1ÿÿH‹>Ï! H‰Á¾@¯b ¿™´A 1ÀèœÌÿÿƒ=ƒ»! ~
¿ª´A èo-ÿÿH‹=x°! è0ÿÿHÄ  []ÃQ1ö1ÿèhÿÿƒ=èÎ!  u‹=ÜÎ! èK.ÿÿë
¿€¿b èˆ­ÿÿ¿@¯b èŞ]  ƒ=&»! Z¿@¯b éÑ,ÿÿXÃS¿@b Hƒì@è|  ¿@b èL  ¿`VA èÔÿÿ…À„Ø   ¾‡‡A ¿ b èÓ  H…Àu¾‡‡A ¿ !b è¿  H…Àta1öH‰Çè0ÿÿ…ÀtS¾¬¡A ¿ b è4  …Àt-ƒ=œº!  ˆ‚   ¾`VA ¿€+b è}  ¿µ¡A H‰Æ1Àè-ÿÿëb¾¬¡A ¿ !b èô  …ÀuÀ¾   H‰çè‚âÿÿ¾`VA ¿€+b fƒL$2è7  ¾O‰A ¿@b H‰Ãè%  H…Àu&H‰æH‰ßè˜ÿÿH‰æH‰ßèÂÖÿÿ¿€+b è~
  HƒÄ@[Ã¾O‰A ¿@b èë  H‰âH‰ÆH‰ßèœ›ÿÿëÆUS¿ b HƒìHèI
  ¿ b è?
  ¿ b Çdğ!     Çşğ!     èû
  ¿Õ¥A èÂÒÿÿ…Àtp1öH‰çèÁáÿÿ¾Õ¥A ¿€+b è|  ¾ŸA ¿ b H‰Åèj  H…ÀH‰Ãu¾ŸA ¿ !b èS  H‰Ã¾A°A ¿ b èA  H‰îH‰ßH‰áH‰Âè£ÿÿH‰æH‰ïèİÕÿÿ¿€+b è™	  HƒÄH[]ÃAUATA‰ÕUSH‰õH‰ûHì¨  è†Ïÿÿf=€Ü! UªtH…ÛHDMÍ! ¿¼´A H‰Şë[º   ¾cA ¿BÍb è—*ÿÿ…ÀuH…ÛHD Í! ¿í´A H‰ŞèÅÉÿÿº   ¾cA ¿FÍb èg*ÿÿ…ÀtH…ÛHDğÌ! ¿µA H‰Ş1ÀëÌH…íu"‹Íï! H¼$Ÿ   H¬$Ÿ   ¾KµA 1Àèu.ÿÿ1ö1ÀH‰ïè™-ÿÿ…ÀA‰Äyè)ÿÿ‹8è–.ÿÿH‰îH‰Â¿ÂA é|  Ht$‰ÇèŠ\  …Àyèq)ÿÿ‹8èj.ÿÿH‰îH‰Â¿ÀYA éP  E…ít(‹“Ù! H9D$`tH…ÛHDEÌ! H‰ê¿[µA H‰Şé#  ƒ=Î·!  ~
¿ÉµA èº)ÿÿº¾  ¾@Íb D‰çè+ÿÿH=¾  tèû(ÿÿ‹8èô-ÿÿH‰îH‰Â¿qA éÚ   ‹=Ë! 1Ò1öèU*ÿÿH…Ày'èË(ÿÿ‹8èÄ-ÿÿH…ÛHDÁË! H‰Â¿ qA H‰ŞéŸ   ƒ=J·!  ~
¿âµA è6)ÿÿ‹=ÌÊ! º¾  ¾@Íb èA)ÿÿH=¾  t$èt(ÿÿ‹8èm-ÿÿH…ÛHDjË! H‰Â¿qA H‰ŞëKƒ=Ê!  t¿€¿b è;©ÿÿë=‹=vÊ! èå)ÿÿ…Ày.¿\´A 1Àè±Èÿÿè (ÿÿ‹8è-ÿÿH‹5bÊ! H‰Â¿EqA 1Àè½Çÿÿ1ÿèÌ,ÿÿAWAVE‰ÏAUATA‰ÍUS‰õI‰ÔD‰ÃHì  E…ÀD‹5Ø! H‰|$yD‰Â‰ÎL‰çè?÷ÿÿë„²   H|$¾@Íb ¹€   ó¥H‹|$èÇÌÿÿ¸@Íb Ht$¹¶  H‰ÇE‰ù‹¶! ó¤¾“A ¿ !b ‰-¯×! ‹-mí! D#®×! A	Á¨D-Ví! fD‰š×! è~  …Àu'ƒ=æµ! ~‰î¿ıµA èp(ÿÿE€H˜‹… âb ‰f×! ‰Ø@ˆ-c×! fÇ:Ù! UªÁø1Ã)Ã‰ÚD‰îL‰çèxöÿÿfD‰5<×! HÄ  []A\A]A^A_ÃS¾0VA H‰ûÇ#Ù!    è6)ÿÿ…ÀuH‹{ª! H‰4Ù! ë-¾üUA H‰ßH‰óØ! è®*ÿÿH…ÀH‰Ù! uH‰Ş¿*¶A è?Æÿÿ[H‹=ıØ! éh)ÿÿSH‰ûHìĞ   „ÀH‰t$(H‰T$0H‰L$8L‰D$@L‰L$Ht7)D$P)L$`)T$p)œ$€   )¤$   )¬$    )´$°   )¼$À   H‹=Â©! è])ÿÿH„$à   H‹=vê! HT$H‰ŞÇD$   ÇD$0   H‰D$HD$ H‰D$è*ÿÿH‹Ø! H…ÉuH‹57ê! ¿
   è¥'ÿÿë‹Ø! H‹=ê! ¾:¶A 1Àè*(ÿÿ¿   è`*ÿÿAWAVA‰ÏAUATI‰öUSI‰ÕH‰ûHƒì‹+ƒı„â   L‹cM…ä„º   L‰öL‰çL‰D$è>%ÿÿ…ÀL‹D$…   M…ít…ítL‰æ¿]¶A ë…íuL‰æ¿w¶A 1Àè£şÿÿHƒ{ t.L9C L‰æ¿¶A tä1À¿RZA è†ÅÿÿE…ÿuL‰ïè½$ÿÿ¸   ëmƒıu
HÇCˆÏb ë"…íuE…ÿL‰ètL‰ïL‰D$èqÆÿÿL‹D$H‰CH‹CL‰C H…ÀtÿĞëƒıuH‹[Hƒë(HƒÃ(éÿÿÿƒ;uœL‰5êÖ! L‰-ÛÖ! 1ÀHƒÄ[]A\A]A^A_ÃAVAUATUSHì   H‹=ÔÖ! I‰äè¬'ÿÿƒø{A‰ÅA”Æt
ˆ$Hl$ëH‰åH‹=¬Ö! è‡'ÿÿƒøÿ‰Ãu¿¤¶A ë
ƒø¿¹¶A 1Àèıÿÿƒø}uE„öuKAƒı{t(è3)ÿÿH‹HcÓf÷Q uƒû_tH‹5YÖ! ‰ßèB'ÿÿëH‰èL)àH=ÿ  u¿Ü¶A ë¬HÿÅˆ]ÿë€ÆE  L‰çèg#ÿÿH…ÀH‰ÕÕ! uL‰æ¿ó¶A èıÿÿè   HÄ   []A\A]A^ÃV‹ºÕ! …ÒtÇ¬Õ!     ëyH‹“Õ! H…Àt¾„ÒtHÿÀH‰}Õ! ëZH‹=¼Õ! è—&ÿÿƒøuH‹=«Õ! è†&ÿÿƒø\u+H‹=šÕ! èu&ÿÿƒø$º$   t"H‹5„Õ! ‰Çèm&ÿÿº\   ëƒø$‰ÂuYéşÿÿ‰ĞZÃAUATUSHì  èZÿÿÿP÷ƒúvƒø uƒø
uéÿÕ! ëáƒøÿ„Ÿ  ƒø#u0‹íÔ! …ÀuH‹=Õ! èõ%ÿÿë
ÇÑÔ!     ƒø
tÃÿÀuÕéj  ƒø=¿Ó¡A „  ƒø"H‰åtE1äH‰ãI½    @éÅ   H‰ãH‰ØH)èH=ş  –   è½şÿÿƒøÿu¿	·A ë-ƒø"„Ç   ƒø\u^èşÿÿƒø"•Áƒø\•Â„Ñtƒø
t¿·A 1Àè~ûÿÿƒø
u3èsşÿÿƒø töƒø	tñ…Àt‘ƒ=Ô!  t¿<·A 1ÀèƒÁÿÿ‰Ô! ¸    P÷ƒúw¿`·A ë²ˆHÿÃéXÿÿÿ¿Œ·A ë¡ƒø
u[ÿëÓ! E1äèşÿÿH‰ÚH)êHúş  aE…äu*Pƒú>wAI£Õs;ƒ=ªÓ!  u‹‰¢Ó! Æ H‰ïèÃÿÿë>ƒøÿuª¿¦·A éAÿÿÿƒø	² DÂHÿÃˆCÿë›E1äƒø\A”Ät’ˆHÿÃë‹¿µ·A éÿÿÿ1ÀHÄ  []A\A]ÃH‹jÓ! H…ÀuéşÿÿHÇUÓ!     ÃSH‰û‹3ƒşt@ƒştrƒşu"H‹[Hƒë(ë$H‹{H…ÿtè… ÿÿHÇC    ë¿Ç·A 1ÀèYÀÿÿHƒÃ(ë¹[ÃSI‰È¹   H‰óèöúÿÿÿÈtH‰Ş¿Ş·A 1Àèûùÿÿ[ÃATUH‰õSH‰ûD‹#AƒütEH‹{H…ÿt6H‰îè= ÿÿ…Àu*H‹{H…ÿu
H‰î¿ô·A ë'E…äuèüÿÿHÇC    []A\ÃHƒÃ(ë²H‰î¿¸A 1ÀèÄ¿ÿÿATUI‰üSH‹dÒ! H…ÛtH‹-PÒ! HÇMÒ!     éŒ   èÚşÿÿH…ÀH‰Ãtv¾Ó¡A H‰Çè6"ÿÿ…Àu¿ÊdA ë;èµşÿÿH…ÀH‰ÅtX¾Ó¡A H‰Çè"ÿÿ…Àt	H‰-Ò! ë>èşÿÿH…ÀH‰Åu¿?¸A 1Àèùÿÿ¾Ó¡A H‰ÇèŞ!ÿÿ…ÀuH‰Ş¿U¸A éˆ   1Àé†   1íƒ=õ­! ~H‰êH‰Ş¿k¸A 1Àèy ÿÿ1ÉM‰àH‰êH‰ŞL‰çè–ùÿÿ…Àu/A¼ b IƒÄI‹l$øH…ít/H‹}H…ÿtéH‰Şèíÿÿ…ÀtHƒÅ(ëåH‰ßè»ÿÿéãşÿÿ¸   ëH‰Ş¿¸A 1ÀèXøÿÿ[]A\ÃATUH‰õSH‰ûD‹#Aƒüt8H‹{H…ÿtH‰îè—ÿÿ…ÀuAÿÌt-H‰î¿¥¸A ëAƒüuH‹[Hƒë(HƒÃ(ë¿H‰î¿Ì¸A 1Àè+¾ÿÿ1ÀHƒ{ []A\•ÀÃATUH‰õSH‰ûD‹#Aƒüt8H‹{H…ÿtH‰îè.ÿÿ…ÀuE…ät-H‰î¿ê¸A ëAƒüuH‹[Hƒë(HƒÃ(ë¿H‰î¿¹A 1ÀèÂ½ÿÿH‹C[]A\ÃATUSHì  H‹5=Ğ! H¼$   è`ÿÿH¼$   ¾1¹A èn"ÿÿH¼$   èt¿ÿÿH‹
Ğ! H‰æH‰ÅH‰íÏ! H‰ßè¥P  …Àt
H‰Ş¿6¹A ëoH‰æH‰ïL‹d$Xè‡P  …Àu L;d$X~ƒ=å«!  uH‰êH‰Ş¿G¹A èï½ÿÿ1Òƒ=ş«!  ‹Ä«! ”Â…Ât6H‹†Ï! H‰ßènÿÿ…Àtè5ÿÿƒ8tH‰Ş¿‡¹A 1ÀèÛ¼ÿÿ¾€  H‰ßëV…ÀtHÇ8Ï!     1Àé´   H‹=:Ï! ¾üUA è !ÿÿH…ÀH‰Ï! uKƒ=«!  …Š   H‹=Ï! Ç6«!    ¾€  èl!ÿÿ…Àx)‰ÇèaÿÿH‹=êÎ! ¾³¹A è° ÿÿH‰ÉÎ! Hƒ=ÁÎ!  uH‹5ÈÎ! ¿¹A éVÿÿÿH‹·Î! H‰æH‰ßèlO  …ÀuöD$$tH‰Ş¿¶¹A èà¼ÿÿH‹}Î! HÄ  []A\ÃHÇF! Àb HÇC!     ÃH‹«Î! H…Àt@8xt@:x	tH‹@ëéÃAVAUA‰ÎATUA‰üS‰Õ‰óD¶êHƒìƒ=:á!  u¾    ¿û¹A 1Àè_õÿÿƒ=xª! E¶Î@¶í¶ÛE¶ä~$“¾  E‰È‰éD‰æ¿ ºA 1ÀD‰L$èàÿÿD‹L$‰ß‹ãà! ‰îÁçÁæD‰ÊD	çÁâ	ş	ÖHcĞ‰4•€âb 1Ò9Ğ~]‹•€âb 9Îu“¾  E‰È‰éD‰æ¿[ºA 1Àè»ÿÿD·ÁA9øu*A‰ÈAÁèE9èuÁé“¾  A‰è¶ÉD‰æ¿•ºA 1ÀèĞºÿÿHÿÂëŸÿÀ‰Yà! HƒÄ[]A\A]A^ÃUS1ÒH‰ıHƒìHt$è7ÿÿ=ÿ   H‰Ãw
H‹D$€8 tH‰î¿ÚºA 1ÀèLôÿÿHƒÄˆØ[]ÃAUATI‰ıUSA‰ÔQH‹-/Í! ‰óH…ít#H‹} L‰îè„ÿÿ…ÀuL‰î¿óºA è=ºÿÿH‹mëØ¿   èß»ÿÿL‰ïH‰Åè¼ÿÿH‰E DˆàDˆâƒğƒûÿEÃƒóAƒüÿˆEH‹ÌÌ! DÓˆU	H‰-¿Ì! H‰EX[]A\A]ÃAUATUSHì  ƒ=›Ş!  tƒ=à! „ü   1ö1Àèïÿÿ…ÀA‰Ä¿»A xº   H‰æ‰ÇèôÿÿH=   H‰ãt
¿!»A èg¹ÿÿº   H‰æ¿5»A è-ÿÿ…ÀtxHt$º   ¿:»A ½   èÿÿ…À„‚   ºû  ¾N   H‰çè†ÿÿA½û  H‰ÅH…ítEº   ¾?»A H‰ïèÖÿÿ…Àt(H}D‰ê¾N   H‰øH)Ø)ÂHcÒèFÿÿH‰ÅëÄ½   ë$½   ëŠD$<÷†í   f|$ t4ƒ<$ştN1íD‰çè¾ÿÿë1íƒ=«§! Ğ   ‰î¿ˆ»A 1Àè/ÿÿé½   ŠD$ÿÈ<wÂ¶D$„Àt¹Pÿ…Â„ˆ   ë¬1ÒD‰ç¾   è;ÿÿH=   ¿E»A …ÖşÿÿD‰çº   H‰ŞèªÿÿH=   ¿Y»A …µşÿÿHÃö  º
   ¾r»A H‰ß½   èÛÿÿ…À„Mÿÿÿº
   ¾}»A H‰ßèÁÿÿ…À…1ÿÿÿé.ÿÿÿ½   é$ÿÿÿ<ğ…ÿÿÿéÿÿÿHÄ  ‰è[]A\A]ÃAWAVA‰öAUATUSHcßH‰ßHìh  è8`ÿÿ…À„  H‰ßI‰İè%`ÿÿ‰Å‰Ãƒõÿ„ú  D!í„ñ  ƒ=v¦! ~D‰òD‰î¿¼A 1ÀèúÿÿD!ëH|$8ƒÊÿ¹   ‰Ş‰$èRoÿÿ¾ãVA ¿ !b èÆøÿÿ…Àtƒ=*¦! Àƒà‹4$H¼$°   ‰ÂDeÿè–ÿÿE…ö‰Ãu
ÇD$   ëA1Ò1ö‰ÇèÏÿÿH…Àt¿+¼A ëBHt$º$   ‰ßèBÿÿHƒø$uâ|$LILOu¾¶D$‰D$1Ò¾¾  ‰ßè‹ÿÿH…Ày
¿3¼A è”¶ÿÿHt$p‰ßº@   èûÿÿ…À¿I¼A „İ  ¿JÏA xÖHt$º   ‰ßèÖÿÿHƒøu	f|$Uªt
¿g¼A éß   ƒ=N¥! ~‰î¿‚¼A 1ÀèÖÿÿHD$pE1ÿHp@ŠP@ˆ×ƒç@€ÿt€úuE…ÿuD‹xë
¿š¼A é“   HƒÀH9ğuÎÇD$   ÇD$    ëGHt$º   ‰ßèEÿÿHƒø…†   f|$Uªu}Š„$„   ˆÂƒâ€úus‹„$ˆ   ‰D$ÿD$E1ä9l$dE…ÿt_‹D$1Ò‰ßB48HÁæ	HÆ¾  è¸ÿÿH…Ày¿Ó¼A 1ÀéÆ  Ht$pº@   ‰ßèÆÿÿHƒø@„fÿÿÿ¿ì¼A ë×¿½A ëĞ<t‰E1ÿëE…öMcôA•Ç…í~?E„ÿt:ƒ|$º   ¸?   EÂ9è|$L‰ğHÁà€|p xH‹”$H  ‰î¿'½A 1ÀèÔµÿÿL‰ğHÁà¶tt@ˆò‰ğƒâı€útş   tƒà<”Âƒş”À	Â¶Òëº   ‰ñ1Àƒáïƒù¸ÒX  HÓèƒà…Òu5E„ÿt0…À¹@tA ¸š»A HEÈ¿P½A D‰ê1ÀèZµÿÿH‹5?Ù! ¿¥½A èMÿÿL‰ò‹t$<HÁâŠLr¶DsAˆÍƒá?AÀíE¶íAÁåAÅ¶DqA¯õğ¯D$DƒıDLÿ…  ‹DxD9ÈrAıÿ  „o  D9È†f  E…ä¹uÑA tAƒü¹É]A tAƒü¹‘ÑA ¸€ÑA HDÈ‹4$AT$1À¿è½A D‰L$è£´ÿÿƒ=Œ¢!  D‹L$u+L‰ğH‹=wØ! D‰êHÁà¾ ¾A DŠDr¶Lq1ÀAƒà?ènÿÿL‰ñ1ÒHÁá‹tx‰ğ÷t$DA‰Ñ1Ò÷t$<ƒ=7¢!  ‰Åu+H‹=(Ø! AÿÁˆTqDˆLrD¶Â‰Á‰òE¶É¾O¾A 1Àèÿÿıÿ  ¸ÿ  ¾ãVA Oè¿ !b IÁæ‰èBˆl4sÁøÁàBD4rèôÿÿ…Àu¿ !b ¾ôVA è{ôÿÿ…À¿~¾A „8  ƒ=Ö¡!  t¿á¾A 1Àè°³ÿÿé.  ¾ôVA ¿ !b èEôÿÿ…ÀuÜ‹$H¼$_  ¾¿A è·ÿÿH¼$_  ¾¤  è•ÿÿ…À‰ÅyèÚÿÿ‹8èÓÿÿH´$_  H‰Â¿kqA ë\Ht$pº@   ‰Çèpÿÿ…ÀuH´$_  ¿¿A èT²ÿÿH¼$_  ˆ‹ûÿÿ‰ïè5ÿÿ…Ày#è|ÿÿ‹8èuÿÿH´$_  H‰Â¿EqA 1Àè²ÿÿƒ=ÿ !  ~H´$_  ¿0¿A 1Àèÿÿ‹4$¿V¿A 1Àèrÿÿ1Ò¾¾  ‰ßè¤ÿÿH…ÀˆûÿÿHt$pº@   ‰ßèÊÿÿ…Àu
¿‰¿A è¶±ÿÿ¿¨¿A ˆğúÿÿH¼$°   èİ’ÿÿHÄh  []A\A]A^A_ÃSH‹RÄ! H…Àt!H‹8H‹Xè‰ÿÿH‹=:Ä! è}ÿÿH‰.Ä! ëÓ[ÃATU¿Àb Sè°ğÿÿ¿Àb è€ñÿÿ¾W§A ¿Àb èóÿÿ¾zÁA I‰Ä¿Àb èóÿÿM…äH‰Ãt3ƒÍÿH…ÀtH‰ÇèUöÿÿ¶èL‰çèJöÿÿ¾˜ÌA ˆÃ¿@b èÓòÿÿ¶ó‰êë0H…Àu¿¾¿A 1Àè¥êÿÿH‰ßèöÿÿ¾˜ÌA ˆÃ¿@b è¢òÿÿ¶óƒÊÿH‰Çè;öÿÿ[]A\¾˜ÌA ¿@b érğÿÿP¿@b èôïÿÿZ¿@b éÃğÿÿAWAVAUATUSHì  ƒ=)Ÿ!  t
Ç9Ã!     Hƒ=QŸ!  ¾Õ¥A ¿ +b u¿€+b è)òÿÿƒ=,Ÿ! H‰Å~‹	Ã! H‰Æ¿ğ¿A 1Àèªÿÿ¾A°A ¿ b èùñÿÿ¾   H‰ÃH‰ïèRƒÿÿH…ÛuH…Àuƒ=®!  …  ëH‰Ãƒ=œ!  tH…Àu
¿ÀA èŸéÿÿƒ= Â!  t¿2ÀA 1ÀèŠéÿÿH…Ûu¿UÀA 1ÀèyéÿÿH´$€   H‰ßèáB  …ÀyèØÿÿ‹8èÑÿÿH‰ŞH‰Â¿QuA 1Àèy¯ÿÿL‹¤$¨   L‰çèéWÿÿH|$D!àƒÊÿ‰Æ¹   èJgÿÿL‹¤$¨   L‰çèÂWÿÿ‹”$˜   â ğ  ú `  u÷ĞD…àtH‰Ş¿xÀA 1Àèåèÿÿ1ö1ÀH‰ßèAÿÿ…ÀA‰Äy
H‰Ş¿§ÀA ë1Ò¾¾  ‰Çè²ÿÿH=¾  tH‰Ş¿¶ÀA 1ÀèÕ®ÿÿHt$@º@   D‰çèÿÿHƒø@t
H‰Ş¿ÛÀA ë×D‰çè¡ÿÿ1ÀHƒÉÿH‰ïò®ƒ=‡! H÷ÑD¾lş~AuĞ¿ıÀA èÿÿHT$@1ÉHr@¶zèˆòÿÿHƒøƒÙÿHƒÂH9òuçÿÉ~}H\$DE1äAƒí1¶;è`òÿÿH…ÀI‰ÇtTE‰æAÁæAƒÆƒ=äœ!  tH‰î¿ÁA 1Àèë®ÿÿÇÉœ!     ‹|$E9åA¶GA¶W	@¶ÿu‰Áë‰Ñ‰ÂD‰öè#òÿÿAÿÄHƒÃAƒüuHÄ  []A\A]A^A_ÃAVAU¾ŞqA ATU¿@b SHìĞ   èïÿÿHt$@H‰ÇI‰Äèá@  …ÀyèØÿÿ‹8èÑÿÿL‰æH‰Â¿QuA 1Àèy­ÿÿH‹\$hH‰ßèìUÿÿH|$!ØƒÊÿ‰Æ¹   èNeÿÿH‹l$hH‰ïèÉUÿÿ÷Ğ‰Ã‹D$X!ë% ğ  = `  u	…Ûtƒû~L‰æ¿7ÁA 1Àèéæÿÿ¿ b Çâ¿!    ÿËègìÿÿ¿ b Áãè4íÿÿ¾2³A ¿ b èÍîÿÿH…ÀH‰Å„Ì   1ÀHƒÉÿH‰ïò®H÷ÑHÿÉHƒùv@¾_   H‰ïè_ÿÿH…ÀI‰Ät3Lp¾W§A L‰÷èÖÿÿ…ÀA‰Åt*¾zÁA L‰÷èÂÿÿ…ÀtëE1íE1äëE1í¿VÁA 1Àè=æÿÿAÆ$ L‹%1¿! M…ätI‹<$H‰îèˆÿÿ…ÀtM‹d$ëä¿ªÁA 1Àè	æÿÿE…íA¶D$	A¶T$t‰Áë‰Ñ‰Â¶|$s@¶öèLğÿÿ¾Û¹A ¿ b è}íÿÿ…Àt3¶|$1Ò¶ó¹€   è%ğÿÿ¾Ù¹A ¿ b èVíÿÿ…Àt¿ÁA 1Àè™åÿÿ¾Ù¹A ¿ b è7íÿÿ…Àt¶|$¶ó1Éº€   èßïÿÿ¾ŞqA ¿@b èjëÿÿHÄĞ   []A\A]A^ÃP¿@b èÜêÿÿÇF¾!     ¿@b Zé¡ëÿÿPƒÊÿ¾   ¿ÁÁA èİğÿÿƒÊÿ¾   ¿ËÁA èËğÿÿƒÊÿ¾   ¿ÕÁA è¹ğÿÿƒÊÿ¾   ¿:»A è§ğÿÿƒÊÿ¾   ¿ÛÁA è•ğÿÿƒÊÿ¾   ¿åÁA èƒğÿÿYƒÊÿ¾   ¿ñÁA épğÿÿAUAT¸÷ÁA USH‰õH‰ûA¼   Hì˜  H…ö¾x   HDèH‰ïè)ÿÿH…Àu)¾X   H‰ïèÿÿH…Àu¾2   H‰ïE1äèÿÿH…ÀA•Ä1À¾   H‰ßD	%>™! è¥ÿÿ…À‰Åyèª
ÿÿ‹8è£ÿÿH‰ŞH‰Â¿
ÂA ë%H‰æ‰Çèœ=  …Àyèƒ
ÿÿ‹8è|ÿÿH‰ŞH‰Â¿ÂA 1Àè$ªÿÿ‹D$% ğ  = `  tƒ=ß˜!  u
H‰Ş¿+ÂA ëL‹d$(L‰çètRÿÿH˜L!àI9ÄtH‰Ş¿AÂA 1ÀèÛ©ÿÿL¤$   º   ‰ïL‰æèÿÿH=   tèı	ÿÿ‹8èöÿÿH‰ŞH‰Â¿qA éuÿÿÿ¾WA ¿ !b E1íèrëÿÿH…ÀA•Åu¾WA ¿ !b èZëÿÿ‹L$(D‰îH‰ÇI‰ØL‰âèùÿÿƒ=$˜!  ¾$6b ¸4b ¹¶  L‰çfÇ„$  UªHEğƒ=˜!  ó¤tK¾WA ¿ !b Ç„$H      fÇ„$L    fÇ„$F    èåêÿÿH…Àt<º   1öH‰Çèƒÿÿ‰„$H  ë$ƒ¼$H   u‹|$(è²“ÿÿfÇ„$L  ÏÉ‰„$H  1Ò1ö‰ïè{
ÿÿH…Àtèñÿÿ‹8èêÿÿH‰ŞH‰Â¿zÂA éişÿÿƒ=w—!  u3º   L‰æ‰ïè‚	ÿÿH=   tèµÿÿ‹8è®ÿÿH‰ŞH‰Â¿qA é-şÿÿ‰ïèG
ÿÿƒ=4—!  ¸ÂA º@tA ¿†ÂA H‰ŞHEĞ1Àè³	ÿÿ1ÿè<ÿÿAWAV1ÀAUATI‰şUS‰ó1öI‰×I‰ÍHì(  M‰Äè4ÿÿ…Ày
L‰ö¿ºÂA ëH´$   ‰Ç‰Åè5;  …ÀyL‰ö¿ËÂA 1ÀèÌ§ÿÿ‹„$¨   % ğ  = `  t
L‰ö¿İÂA ëÜH‹„$¸   H‰$Hc$H‰×H‰T$èPÿÿ…ÀH‹T$u
L‰ö¿õÂA ë¬H‰×è÷Oÿÿ÷Ğ…$uçHt$,‰ïº$   èµ	ÿÿHƒø$¿ÃA …Õ  H|$2º   ¾cA èòÿÿ…Àu€|$/u	…Û¸?   ë…Û¸   DØ‰ï1Ò¾¾  èÖÿÿH…À¿#ÃA ˆ‡  Ht$P‰ïº@   èG	ÿÿHƒø@¿ö¼A …g  Ht$*º   ‰ïè'	ÿÿHƒøu	f|$*Uªt
¿g¼A é=  M…ÿt:1Ò‰ï¾¸  èkÿÿH…À¿0ÃA ˆ  ‰ïº   L‰şèŞÿÿHƒø¿DÃA …ş   ƒû~i¸¾  E1ÿŠ”–şÿÿ@ˆÖƒæ@€şt€úuE…ÿu
D‹¼šşÿÿë
¿š¼A éÀ   M…ätI‰$IƒÄ„’şÿÿHƒÀIƒÅH=ş  )$AEğu¡ëE1ÿƒë…Ûÿ   Ç$    A¾   ë?Ht$*º   ‰ïè3ÿÿHƒø…   f|$*UªuxŠD$dˆÂƒâ€úuq‹D$h‰$…ÛoÿËE…ÿ„   ‹$1Ò‰ïDøHÁà	H¾  H‰ÆH‰D$è«
ÿÿH…Ày¿Ó¼A 1Àèt¥ÿÿHt$Pº@   ‰ïè¹ÿÿHƒø@„kÿÿÿ¿ì¼A ë×¿½A ëĞ<t‹E1ÿë(T$PM…äIEAU tIƒÄH‹L$I‰L$øAÿÆI‰Åéeÿÿÿ…Û~M…äAÆE tIÇ$    ëA¾   ‰ïèçÿÿHÄ(  D‰ğ[]A\A]A^A_ÃAWAV¸?   AUATUSH‰õH‰ûHì  ‹5„“! LD$HŒ$  …öEğ1Òè{üÿÿH…íA‰ÄuCH„$  1ÒD9â}HƒÀR€xğ tîH‰Ş¿WÃA 1ÀèôÿÿëH‰Ş¿]ÃA 1Àèãÿÿ1ÿèl	ÿÿH‰ïè^¦ÿÿ‰ÁÁéuA9Ä}D‰âH‰î¿~ÃA 1Àè0¤ÿÿ…À@ÿ‰D$tH˜¿¦ÃA HÁà€¼   „£   1À¾   H‰ßè3ÿÿ…À‰ÅxHœ$  E1öE1íA¿€   ë1è"ÿÿ‹8è	ÿÿH‰ŞH‰Â¿ÂA 1ÀèÃ£ÿÿƒ=¦’!  tXAÿÅIÿÆHƒÃE9ô~eD9t$º    AD×€{ tà:tÜAvˆ¿ÉÃA 1ÀèÿÿJ‹tô1Ò‰ïè™ÿÿH…Ày«¿ØÃA 1Àèb£ÿÿº   H‰Ş‰ïèYÿÿHƒøt“¿êÃA ëİ‰ïè5ÿÿE…ítƒ=’!  ¾@tA ¸#nA ¿ûÃA HEğé·şÿÿ¿$ÄA è÷ÿÿé¯şÿÿAWAV¿@b AUATUSHƒìHèVâÿÿ¿@b è&ãÿÿH‹Ùµ! ¾i   H‰ßèLÿÿ¾r   H‰ßH‰D$è:ÿÿ¾k   H‰ßH‰D$è(ÿÿ¾a   H‰ßH‰D$ èÿÿ¾R   H‰ßH‰D$(èÿÿHƒ|$ H‰D$0•ÂHƒ|$ •À	ĞHƒ|$  •ÂĞu$Hƒ|$( u1ÀHƒ|$0 ¿   •À(µ! „¥  ¾`VA ¿ +b èäÿÿ¾/   H‰ÇH‰D$èÉÿÿ¾?£A HƒøH‰Ã¿ b HƒÛÿèíãÿÿH…Àt¾?£A ¿ b èÙãÿÿH‰Ãë	H…ÛHD\$Hƒ=Í´!  uH‰ßèÎ£ÿÿH‰¼´! ¾9£A ¿ b è£ãÿÿ¾£A ¿ !b I‰Çè‘ãÿÿƒ=”! H‰Å~H‰ÆH‰Ú¿‡ÄA 1ÀèÿÿH…ít=H‰îH‰ßèµÿÿ…ÀtM…ÿt)H‰îL‰ÿè¡ÿÿ…Àuƒ=N! ~
¿¤ÄA è:ÿÿH‰-3´! ¾‡‡A ¿ b è"ãÿÿH…ÀI‰Åu¾‡‡A ¿ !b èãÿÿI‰Å¾°A ¿ !b èùâÿÿ¾§A H…ÀI‰Æ¿ b ¸QÄA LDğèÛâÿÿH…ÀH‰Åu¾§A ¿ !b èÄâÿÿH‰Å¾|§A ¿ b è²âÿÿ¾ZA ¿ b H‰$èŸâÿÿH…ÀI‰Äu¾ZA ¿ !b èˆâÿÿI‰ÄH‹! H‰ßH‰ÖH‰T$8èÀ ÿÿ…Àt!M…ÿ„ã   H‹T$8L‰ÿH‰Öè£ ÿÿ…À…Ë   Hƒ|$ t
H‹|$è9ÿÿHƒ|$ tM…í¿XÄA IEıè ÿÿHƒ|$  tL‰÷èÿÿHƒ|$( tHH…íuHƒ<$ ¿²ÄA tH…í•ÂHƒ<$ •À8ÂtH‹<$H…íHEıèÕ ÿÿëH‹$H‰î¿ËÄA 1Àè`ÿÿHƒ|$0 tM…ä¿uÄA IEüè§ ÿÿƒ=˜²!  tH‹=—²! H…ÿHD=”²! è‡ ÿÿ1ÿè°ÿÿHƒÄH¿ +b []A\A]A^A_éäŞÿÿP¿ b èÙŞÿÿ¿ b èÏŞÿÿ¿ b ÇôÄ!     ÇÅ!     è‹ßÿÿZ¿ +b é¦Şÿÿƒ=+! SH‰ûH‰=(! H‰5!²! ~H‰ò1ÀH‰ş¿ÒÄA è ÿÿH‹=²! ¾D   è| ÿÿ1ÒH…À•Â‰Ö±! tHÇá! @tA ¿ +b èCŞÿÿ¿ +b èßÿÿ…Àt¿ÊdA 1Àè•Øÿÿƒ=±!  t&H‹¥±! H…ÀtH‹=‘±! H…ÿHDøè…ÿşÿ1ÿè®ÿÿH‰Ş¿ôÄA 1Àè‰ÿÿSH‹O±! ¿ÅA è]ÿşÿH…Ûu[¿!ÅA éMÿşÿ¶K	¶S1ÀH‹3¿EÅA èÖÿşÿH‹[H…Ûuà[ÃUS¿dÅA R1À»€,b ½[ÅA è²ÿşÿH‹3H…öt!H‹SH‹K¿kÅA H…ÒHDÕ1ÀHƒÃ è‹ÿşÿë×X[]ÃUS‰ı1ÀHƒìhH‰T$H‰4$1Ò
HÿÀHƒøuô„Òu‰î¿}ÅA 1ÀèRÿşÿé  H|$¾`ÅA è~şşÿ¶T$H|$¾ºA 1À‰Óè¦ÿÿDŠD$¶D$H|$ ¶L$¾•ÅA D‰ÂAƒà?âÀ   1ÀèvÿÿDŠD$¶D$H|$@¶L$¾•ÅA D‰ÂAƒà?âÀ   1ÀèFÿÿ¶$€ú€uÆD$*ë„ÒtH|$¾ºA 1Àè!ÿÿ¸ ÔA H‹H‰ÆH…ÒtŠH8Ët
N	HƒÀ8ËuãÆD$HëHT$‹D$‰î¿ŸÅA P‹D$P1ÀLL$PLD$0HL$$èLşşÿXZHƒÄh[]ÃAUATUS»   Hì  ƒ=n‹!  u1Ûƒ=‡‹!  ŸÃƒ=}‹! LD$¸    ‰ŞHŒ$  HT$LNÀ÷ŞE1äƒæ?è?ôÿÿ‹t$ƒø‰ÅAŸÄº@,b ¿»ÅA 1ÀA	ÜèÊışÿ1ÀXHÁàH‹´  H‹”  ‰ßè%şÿÿHcÃƒøuÚE…äu"ƒ=şŠ! ~¿
   Ld$1Ûè#üşÿA½   ë<L¤$  IƒÄA€|$4 tÊDkHcÛHÁãH‹´  H‹”  D‰ïD‰ëè¼ıÿÿëÌ9ë}&I‹$ÿÃ¿ÎÅA ‰ŞIƒÄH™I÷ıI‹T$ø‰Á1ÀèışÿëÖHÄ  []A\A]Ãƒ=<Š!  A‰ĞA‰ÉuH‰úH‹=&À! ‰ñ1À¾ÜÅA é0şşÿÃAWAVA‰×AUATA‰üUS1ÀA‰Î¹   ‰óHƒì(E‰ÅDˆÍ‹T$`H|$ó«…ÒtH|$¾ÆA è ÿÿLL$D‰ñD‰æ¿ÆA E‰øD‰ê1Àè~üşÿ‰Ş¹ÆA ¿è  Ñîş?B v‰ğ1ÒHÿÁ÷÷1ÒÁà
÷÷‰Æëäşç  v5¿è  ‰ğ1Ò÷÷¿
   ‰Æ‰Ğ1Ò÷÷…ÀuHÿÁë¾I‰Â¿RÆA 1Àèüşÿë¾¿`ÆA 1ÀèüşÿA¼ Êš;¹è  D9ãsAƒüvD‰à1Ò÷ñA‰Äëé‰Ø1Ò¾6A A÷ô¿àÏb A½àÏb A¾è  ‰Ó‰Â1Àè>ÿşÿD‰à¹è  1Ò÷ñA‰ÄE…ät1IÿÅA€}  uö‰Ø1Ò¾iÆA A÷ôL‰ï‰Ó‰Â1ÀèÿşÿD‰à1ÒA÷öA‰ÄëÊ¿oÆA 1À¾àÏb èhûşÿ@€å¿}ÆA u¿™ÆA 1ÀèQûşÿ¿
   èçùşÿHƒÄ([]A\A]A^A_ÃUSQ‹«
! …Û‰½  1ö1À¿NÌA èÉışÿ…À‰ÃyÇ…
!    »   é•  1Ò¾   ‰Çè1ûşÿ=   u×º 
  ¾àĞb ‰ßè©ûşÿH= 
  u¾‰ßè:ûşÿº   ¾´ÆA ¿äĞb Ç!     èÜùşÿ…À‰ÃtÇ
!    »   é(  ‹$­! ƒèfƒøvÇõ	!    »   é  ¿5­! †zÿÿÿ=z	  vÇÍ	!    »   éİ   ‹-Ñ¬! ƒîº·Á¿äĞb è”œÿÿ9ÅtÇ	!    »   é­   fƒ=§¬! u<Š¤¬! HÇ|¬! öĞb HÇi¬! úĞb <vy<HÇP¬! şĞb tjHÇ3¬! Ñb ë]~[H¿m¬! Š^¬! HàĞb H‰4¬! H¿T¬! HàĞb €úH‰¬! v&HH€úH‰ü«! HHH‰é«! tHƒÀH‰Ô«! Çæ!     ‰ØZ[]ÃS‰ûè$şÿÿ…Àu¿é«! 9Ú|9ë`ƒû¾ÀÆA tƒû¾¹ÆA tƒû¾ÅÆA ºÊÆA HDòÿÈ¿ìÆA ¸ÑÆA HDøëƒûu¾ÀÆA ¿ìÆA 1Àèşøşÿ¸   ëƒû¾¹ÆA tãë´[ÃAWAVAUATUS‰ı¿   H‰óHƒìèhÿÿÿ…Àt1ÿèQüşÿA‰Ä¶U«! 9èvH¿K«! ‰èHÁàH”àĞb ëvı€   uH¿-«! HÂàĞb H‰Mª! ëVwA¼   é   ¶«! ƒè€9Åsç¶õª! 9ÅwÜDm€Jƒ<í Ğb  t
J‹í Ğb ë}ÿH‰ŞèHÿÿÿ…ÀtçA‰Äé·  1À¹
   H‰ßƒıó«vEHJH‰Å Ğb öBu†Š„ÀˆC„yÿÿÿ<u·B·JÁàÈ‰öBu€z u	f‹Bf…ÀuD¶bAÿÄéO  f‹z
‰ÁA½@   ƒá?f…É·ñH‰ùDEî¶ÍE‰èD‰kDq‰ÁáÀ   4    ¶ÌD‰sE¯Æ	ñA‰CA¯À9s‰ƒı@ˆ{HÇC    †ä  ¶ç©! „Àt?9Åw;1Éfƒ=Ñ©! ‰ïH¿5Ó©! ŸÁƒçÁáA@¯ÇÈ…ÉH„àĞb H‰Ct‹@ú‰C öBufzUªuf‹BˆCŠBˆCöCDE€ufƒ=s©! Û   EL‹<Å Ğb AöGIW H‰Å Ğb …¹   A€ …®   AöG„–   E;ouE;wtv‹óƒ! …À~lƒ=¸ƒ!  tƒø~^E‰ÁAöĞb uQ1À‰î¿3ÈA D‰D$L‰$è¡•ÿÿ‹K‹S¿—ÈA ‹sè;ùÿÿA‹OA‹W¿ÈA A‹wè%ùÿÿL‹$D‹D$A€‰Ğb A‹GA¯GA¯G;v‰‹I‹GH9Ğ~‰E‰ÇAö‡Ğb uAş   u‰î¿£ÈA 1Àè"•ÿÿAƒı@uZ1À‰î¿ãÈA è•ÿÿöCt*ƒ=í‚!  u=ƒ=ƒ!  ¸VA ¾)ÈA ¿+ÉA HEğ1Àè”ÿÿ‹Ä‚! â‚! u‰î¿SÉA 1ÀèÂ”ÿÿA€Ğb HƒÄD‰à[]A\A]A^A_ÃATU1íSHƒì0De‰ëHt$‰ßèWüÿÿ…ÀuPû€   u#¾t$¸@tA ºoVA ¿€ÉA @€şHDĞ1ÀèõşÿP‹D$0‰ßPDŠL$)D‹D$$‹L$ ‹T$‹t$èøÿÿZYÿÃA9Üu™ƒí€ı   uˆHƒÄ0[]A\ÃSHƒì0èQ•ÿÿHt$‰Ç‰ÃèĞûÿÿ…Àu'P‹D$0‰ßPDŠL$)D‹D$$‹L$ ‹T$‹t$è³÷ÿÿZYë‰Ş¿ŸÉA 1Àè€ôşÿHƒÄ0[ÃAWAV¿   AUATUSHƒìxèşúÿÿ…Àt1ÿèç÷şÿ¿ÊÉA 1Û½   E1äè£óşÿD«€   Ht$D‰ïèFûÿÿ…À…„   D‹|$(D‰îA‰ŞD‰ÿD‰|œ0èb}ÿÿ1Ò…À¾   ”ÂA	Ô…Àt‹T$(1ÉA9Î~1ÿ9TŒ0@•ÇHÿÁ!şëê!õ¹@tA …ÀA¸0VA ¸»£A D‰úLEÁ…ö¿áÉA HDÈD‰î1ÀHÿÃè­óşÿHƒû…`ÿÿÿ…í¸ÅÉA ¾(VA HEğ¿ùÉA 1Àè‡óşÿE…ät
¿ÊA èØòşÿ…íu
¿„ÊA èÊòşÿ¿
   è òşÿHƒÄx[]A\A]A^A_ÃATU¿   Sèßùÿÿ…Àt1ÿèÈöşÿH‹±¥! ·hı€  u¾ ,b ¿;ËA 1Àèóşÿëº€  ¾ ,b ¿FËA )ê1Àèúòşÿ‰ë‰î¿TËA Áã
1À‰Úë   èßòşÿèŸÿÿ‹ ¹   A‰Ü¿
   ÿ  ™÷ùƒÀÁà	A)Ä¸   A¬$ €ÿÿÁıı   Oèè<ñşÿº |  ¾ |  ¿}ËA 1Àè†òşÿD‰âD‰æ1ÉÁú¿¸ËA 1Àèoòşÿ‰è‰Ù‰ê‰ŞÁà¿óËA []A\)Á1ÀéRòşÿQè÷ÿÿƒÊÿ…Àu'fƒ=Õ¤! ~H‹´¤! ·P‰ĞˆÉ£! fÁèˆ¾£! ‰ĞZÃƒ={! S~
¿.ÌA èfñşÿƒ=Ïÿ   ¥   è¼öÿÿ…À…š   ¿5¤! º·Á¿äĞb ƒîè8”ÿÿ¿NÌA ‰X¤! ¾   1Àèlôşÿ…À‰Ã¿<ÌA x1Ò¾   ‰ÇèãñşÿH=   t
¿WÌA èéÿÿº 
  ¾àĞb ‰ßè ñşÿH= 
  uİ‰ßèáñşÿƒ=Ò~! ~
¿_ÌA è¾ğşÿÇ$ÿ      1À[ÃATUSèöÿÿA‰ÄƒÈÿE…ä…B  ¶-Î£! 1Û…í„ÿ  ƒ=ˆ~! ~
¿wÌA ètğşÿH‹…£! ¶¶P¶p¶@‰¨¢! ‰¢! ÿÀƒù‰5‹¢! ‰‰¢! uÇ}¢!    »   é£  ƒúO»   •  ƒıu
»   é†  ƒ=~! ~
¿†ÌA èûïşÿH‹£! €xwÖ¶@ƒ=ë}! ‰1¢! ~
¿ÌA èÑïşÿH‹Ú¢! €xu?ƒ=Å}! 	·@º   DMâDˆáÓø¶ÀÿÈƒøwÿ$Å€ÓA »   ë»   ë»   ë1í»   ë»   ƒıæ   ƒû…İ   Hƒ=e¢!  tƒ=\}! ~
¿µÌA èHïşÿH‹I¢! H…ÀtD€8Ç'¢!    tÇ¢!    ë)fx4ufx!Ct
Çÿ¡!    fx€Vtƒğ¡! ƒ=ù|! ~
¿ÑÌA èåîşÿH‹-Ş¡! »   fƒ} OuJHuº   ¿ÃÑA èîşÿ…Àu3fƒ}Ou,f‹Eƒàfƒøufƒ}
O»   uf‹E1Ûƒàfƒø”ÃƒÃƒ=‰|! ‰Ø~'D‹º ! ‹¸ ! ¿äÌA ‹± ! ‹5¯ ! 1Àèøîşÿ‰Ø[]A\ÃS¿   è‚õÿÿ…Àt1ÿèkòşÿè†ıÿÿH˜¿XÍA H‹4Å`ÔA H‰Ã1Àè½îşÿƒû~ƒûuƒ=` !  ¿fÍA ëAƒûtA¿…ÍA èôíşÿƒû~2¿£ÍA èåíşÿ¿ÂÍA èÛíşÿƒût¿àÍA èÌíşÿƒût
¿şÍA è½íşÿ‹¯ ! …Àt<ƒ=´{!  ¨t/¨¾)ÍA u¨¾ÍA uÿÈ¾:ÍA ¸GÍA HDğ[¿ÎA 1Àéîşÿ[ÃAWAVAUATUSH‰ûPƒ=h{!  
¿
   è”ìşÿA¿€,b HƒÍÿE1äE1íI‹7H…ötIH‰÷DˆàH‰éò®H‰ßH÷ÑHQÿHcÒ€|ÿ=L4MEõè²ïşÿ…ÀuL‰÷AÿW¿
   è=ìşÿ1ÿë$IƒÇ ë¯¿8ÎA èéìşÿè¹íÿÿ¿
   èìşÿ¿   è ñşÿHƒì8è/òÿÿ…Àt¸   ë'Ht$¿€   èdôÿÿ…ÀuæŠßŸ! ¾D$ƒâÿÂ9ÂuÒHƒÄ8ÃAWAVA‰öAUATUSH‰ıHì8  èÜñÿÿ…ÀtƒÈÿéH  ƒ=iz! ~D‰ö¿YÎA 1ÀèğìşÿMcşL‰ÿèß3ÿÿ…ÀtÑE1íA¼€   ƒËÿ¶jŸ! A9ÄHt$ D‰çèÓóÿÿ…ÀtAƒıuHë&‹D$,9Eu‹D$(9Eu‹D$$9EuAÿÅD‰ãAÿÄëµƒ=ëy! ¨  ‰Ş¿qÎA 1Àèoìşÿé•  L‰ÿè\3ÿÿH¼$ˆ   A!Æ1ÒD‰öè®iÿÿƒ=®y! ‰Ã~H‹”$   D‰ö¿ÎA 1Àè+ìşÿ1Ò‰ß¾¶  è]ìşÿH=¶  ¿ÉÎA uHt$º   ‰ßèÏìşÿHƒøt¿òÎA 1ÀègŠÿÿ‹D$1Ò‰ß¾¾  ‰D$èìşÿH=¾  ¿ÏA uÖHt$H‰ßº@   è‰ìşÿHƒø@¿=ÏA uºH¼$ˆ   èZkÿÿƒ=y! ~D‰î¿_ÏA 1Àè‰ëşÿAƒÏÿE1öE1íD‰ûAÿÌAƒütgHt$ D‰çè}òÿÿƒ=Çx! ~L‹D$8‹T$@¹   D‰æ¿ŠÏA 1Àè@ëşÿH‹t$8H|$Hº@   è,ìşÿ…ÀuAÿÅD‰ã‹D$@9D$uœ…Àt˜AÿÆE‰çëƒ=mx! 1  A¸jA AƒıA¼@tA L‰ÂD‰î¶ËIDÔ¿¶ÏA 1ÀL‰D$èÑêşÿAÿÍt7ƒ=-x! ~"L‹D$AƒşD‰ùD‰ö¿äÏA L‰ÂIDÔ1Àè¡êşÿAÿÎ…ˆıÿÿD‰ûHt$ ‰ßè ñÿÿ‹M…Ét;L$$u‹E…À„œ   ;D$(„’   ‹E¯E¯ÁA‰Ä‹Œw! ªw! uPDk€McíAö…Ğb u?1À‰Ş¿ĞA èy‰ÿÿ‹M‹U¿[ĞA ‹uèíÿÿ‹L$$‹T$(¿bĞA ‹t$,èıìÿÿA€Ğb ‹D$ ‹t$$‹L$(A9Ä‰uACÄ‰M¯Î…É~1Ò÷ñ‰E‰] ‰ØëAÿÍ…$ÿÿÿé+ÿÿÿHÄ8  []A\A]A^A_Ãƒ=Çv!  uORÇºv!    èC÷ÿÿ…Àx:Š,›! <şuŠ!›! P€€úv"„ÀtÇ‹v!    ëP€€úwèÇwv!    XÃS¿   èæïÿÿèóöÿÿ…Ày¿‚ĞA »   è’èşÿë;¶Êš! H‹¢›! ·P€ûşu¶²š! ‰Ş¿·ĞA 1ÀèéşÿÇv!     èGÿÿÿ‹v! ¾oĞA ƒøtƒø¾iĞA tƒø¾7¸A ¸rĞA HDğ1À¿êĞA è¾èşÿƒ=×u! vFƒûHcÃºvĞA H‹4ÅàÓA ë1ö1ÒC€ƒøwƒãº}ĞA H‹4İàÓA ëH…Òt¿%ÑA 1Àèoèşÿ[¿
   éçşÿA»àÚb ¹àÛb L‰Ú‹B43B HƒÂ3B3BüÑÀ‰B<H9ÑuæAWAV1ÉAUD‹5=­! ATD‹-8­! UD‹%4­! S‹-1­! E‰ñ‹,­! D‰ïD‰æA‰èA‰ßD‰ÈA‰òHƒÁÁÀÜÚb E1ÂA!úÁÏE1Â‰úD‰ÏB„™y‚ZDøHƒùPE‰Çt
A‰ğA‰Á‰Öë¾A¿0Ûb AºàÚb D‰É‰ÇIƒÂ1ÑÁÇ1ñŒ9¡ëÙnAJLD‰ÏÁÏA‰ÁDÁM9×A‰ğt‰Ö‰È‰úëÉA¹4Ûb A¸àÚb IƒÀM9Át:A‰ÿA‰úA	×A!ÒA!ÇÁÈE	×E‹œ   F”Ü¼‰ÎÁÆAò‰Ö‰ú‰Ç‰ÈCë½IƒÃM9Ùt1E‹ƒì   A‰ÂÁÈA1úA1ÒF„ÖÁbÊ‰ÎÁÆAğ‰Ö‰ú‰Ç‰ÈCëÆDñDèDçêŞ‰ï«! [‰ì«! ‰=ê«! ]‰ç«! ‰5å«! A\A]A^A_ÃHcÿ1ÀHÁï9Ç~‹…àÚb Ê‰…àÚb HÿÀëçÃÇŸ«! #EgÇ™«! ‰«ÍïÇ“«! şÜº˜Ç«! vT2Ç‡«! ğáÒÃÇ…«!     Çw«!     Ã‹p«! AVAUI‰ıATUS‰ó‰Çƒç?ğsÿX«! ‰N«! ½@   A‰îA)şD9ó|1HcÿL‰îD‰ñH‡àÚb McæD)óMåH‰Çó¤¿@   è6ÿÿÿè‰ıÿÿ1ÿëÄ…ÛtHcÿHcËL‰îH‡àÚb H‰Çó¤[]A\A]A^Ã‹åª! Sƒà?pH˜Æ€àÚb €ƒş8HcÖ~3»àÚb ¹@   1ÀHÚ)ñH‰×óª¿@   èÍşÿÿè ıÿÿ¹   1ÀH‰ßó«ëHÂàÚb ¹8   1À)ñH‰×óª¿8   è›şÿÿ‹uª! ‹sª! [‰ÂÁàÁê‰¢! Ê‰û¡! éÊüÿÿAUA½@tA AT@öÆUA‰ÔS½³£A ‰ÓL‰é‰òA¸   PHEÍ‰ğfÁúfA÷øD¿ÆH‰ş¿ÕA ˜P1Àèãäşÿ‰ÚA¿ÌA€äIDí¿   ‰ØfÁúf÷ÿAXH‰ê¿»ÕA []A\A]¿ğ1ÀÿÆé«äşÿR¿åÕA è äşÿ¿5¢! ¿øÕA 1Àèäşÿ¿5Œ¢! 1À¿ÖA èzäşÿfƒ=v¢! ~N¿q¢! º³£A ¿@tA A¸   ‰È¨HEú‰ÊfÁúfA÷øH‰ú¿@ÖA ¿ğ1Àè5äşÿ¿5N¢! ¿ÁÖA 1Àè"äşÿ¿¢! ¿5¢! ¿?×A XéÛşÿÿATUA‰ôS‰Õ1À¿Ö‰ËH‰ş¹Ğ-b ¿[×A èçãşÿfA9ìu¾Ğ-b ¿{×A 1ÀèĞãşÿë¿õºĞ-b ¿‰×A 1Àèºãşÿ1À¿×A è®ãşÿfA9Üu[]A\¿;İA éúâşÿ¿ó¿:×A 1À[]A\é‡ãşÿUS1ÛHì  H‹=åe! è€åşÿHcëè¨äşÿƒø
tHûş  wíˆHÿÃëâH‰çÆ, è¹ƒÿÿHÄ  []ÃAWAVAUATI‰ôUS1ÛHƒìH¿F¿.D¿~H‰|$¿
   ‰l$4‰D$‰D$8D‰|$<èáşÿ‹Dœ4H|$$¾˜×A A‰Ş‰D$‰Â1Àè_æşÿƒûu;l$A¹.İA tAƒşuD9ıA¹;İA tLL$$‹š¡! H‹İpİA ¿œ×A L‹İİA H‹t$Hÿ1ÀèâşÿèÿÿÿŠI‰Å„ÒuD‹t$ëjˆT$èààşÿH¾T$H‹ ‹ƒøTuHƒûuE¿4$ëCAƒşuƒøNëìHt$(1ÒL‰ïè¨ãşÿH‹L$(A‰ÆI9Ít;¡! s€9 t¿¾×A D‹t$èoáşÿfE‰4\L‰ïè’àşÿH…Ûu;l$uD‰t$8D9ıuD‰t$<HÿÃHƒû…ŞşÿÿHƒÄH[]A\A]A^A_ÃAWAVA‰ÈAUATI‰ôUS¸   ‰ÕHƒì ƒùE¿$ö¹P   ƒæÿÆƒúEÈD‰ÈAQA‰ÍE)ÅD¯ê™÷ıE‰éAÀ…Ò¸³£A º@tA HDÂ‰òPAPA‰ğD¯ÅH‰ş1À¿Â×A èTáşÿHƒÄ èÄıÿÿ€8 I‰ÆuA¿$ërHt$1ÒH‰Çèâşÿ‰ÃH‹D$I9ÆtL¾8E„ÿtèƒßşÿH‹ Bƒ<¸Pt¿ì×A A¿$èZàşÿèeßşÿH‹T$H‹ H¾ƒ<PtÿË¯İD9ë~¿ñ×A A¿$è*àşÿfA‰$L‰÷èMßşÿHƒÄ[]A\A]A^A_Ã¿µ! ¿¬! ¿5£! S‰û¿ö×A èƒüÿÿ¿™! ¿! ¿ØA ¿5‚! èdüÿÿ…Ût*fƒ=}!  x ¿r! ¿i! ¿ØA ¿5[! [é6üÿÿ[Ãfƒ=Q!  x9P¿E! ¿ØA ¿7! ¿5.! è
üÿÿ¿(! ¿5#! ¿ØA YéÌúÿÿ¿0ØA éPßşÿAUAT‰ÑUS1ÀH‰óA‰Õº   HƒìD¿H‰ş¿IØA èÆßşÿè:üÿÿ€8 I‰Ät0Ht$1ÒH‰Çèáşÿ…À‰Å~A9Å|
H‹D$€8 t¿¾×A 1Àè‰ßşÿ¿+L‰çèŞşÿf‰+HƒÄ[]A\A]ÃAUATI‰ıUSQºN   L‰î¿^ØA 1À1ÛèPßşÿèÄûÿÿH¾(I‰Ä@„ítèªİşÿH‹ »   ‹¨ƒøYt
1ÛƒøN•ÃÛL‰çè¨İşÿƒût­Z‰Ø[]A\A]ÃAWAVI‰öAUAT1öUSA‰üH‰Ó1ÒI‰ÍHƒì(ƒÍÿè#ßşÿº   L‰öD‰çè£ßşÿHƒø…ú  fA>BM½   …é  Ht$º   D‰çèvßşÿHƒøtƒÍÿéÉ  f‹D$fƒøuiHt$º
   D‰çèKßşÿHƒø
H‰ÁuÒ1ÀH‰ß‹T$ó«¿D$A¿   f‰S‰C¿D$‰Cf‹D$f‰C¯ÂˆÁÓå‰k$‰k A‹FA+F
Ç(   ‰Cë7fƒø(½   …F  Hsº&   D‰çèÔŞşÿHƒø&…Zÿÿÿ¿D$A¿   ‰¾ÀİA ¹   L‰ïó¥º   ½   ·KˆÈ¯CˆÁ‰ĞÓàPÿ=   ‰œ! ‰ Ô  ‡Û   »@İb 1íIcÏHcœ! 9Å}3H‰ÊH‰ŞD‰çH‰L$èRŞşÿH‹L$H9È…ÔşÿÿAƒÿuÆC ÿÅHƒÃëÂIcV
H…f   H9Âtº   1öD‰çè‚İşÿ1í‰&œ! ëiHt$º   D‰çèöİşÿHƒø…|şÿÿfƒ|$0½   u@Iuº.   D‰çèÎİşÿHƒø.…Tşÿÿ¿D$I}º   ¾cA A‰E èÜşÿ…Àtƒ½   HƒÄ(‰è[]A\A]A^A_ÃSH‰=›! 1ÀHƒÉÿH‰ûò®‰Ï÷ßèÎ|ÿÿH‰ŞH‰Çè×Ûşÿ¾ìªA H‰ÇèêßşÿH‹=[›! H‰\›! 1ö1Àè#ßşÿ…À‰?›! ¿uØA x'H‹==›! 1Àº¤  ¾A   èüŞşÿ…À‰›! y
¿ØA èzÿÿH‹=›! è  ‹=úš! ¹HÜb º@áb ¾háb è	ıÿÿƒ=si! ‰Ã~‰Æ¿¨ØA 1ÀèùÛşÿ…Ûy"è°Úşÿ‹8è©ßşÿH‹5ºš! H‰Â¿ÆØA 1ÀèMzÿÿÿËƒûwLÿ$İ@İA H‹5–š! ¿ÙØA ë0·®! ·¥! ¿ğØA H‹5uš! ¯Ğ1ÀèzÿÿH‹5dš! ¿ÙA 1Àèúyÿÿ[ÃAWAVA‰÷AUATI‰ÔUSH‰Í‰ûº   L‰æHì  ·IA¾   L‰$E1íˆÈ¯EˆÁAÓæè¹Úşÿº(   H‰î‰ßèªÚşÿIcÖ¾@İb ‰ßHÁâè—ÚşÿL‹$º0   ‰ßL‰Æè„ÚşÿHc5é™! 1ÒD‰ÿè3ÛşÿHt$º   D‰ÿè±Ûşÿ…À~.LcÀHt$‰ßL‰ÂL‰$H‰D$èBÚşÿL‹$L9ÀuH‹L$AÍë¼…Àt¿GÙA èÚşÿëƒÈÿëDBµf   D‰m1Ò1ö‰ßA‰D$
DèA‰D$è¶Úşÿº   L‰æ‰ßèçÙşÿº(   H‰î‰ßèØÙşÿ1ÀHÄ  []A\A]A^A_Ã…ÿS‰ût!‹5™! ‹=™! A¸HÜb ¹@áb ºháb èşÿÿ‹=ê˜! èÚşÿ‹=Û˜! èvÚşÿH‹=ß˜! è
  …Ût	ƒ=Sg!  tƒ=Ng! ![H‹=¼˜! é÷Øşÿ[H‹5§˜! H‹=¨˜! é³Üşÿ[ÃAWAV¾.   AUATUSH‰ıPèÉÙşÿH…ÀuH‰éºjÙA ¾oÙA ¿tÙA 1Àèxÿÿ¾jÙA H‰ÇH‰Ãè«Úşÿ…À…ë  èí»ÿÿH‰ïèH±ÿÿƒ=Çf! ~‰Æ¿ŸÙA 1ÀèOÙşÿ¿Àb èû·ÿÿƒ=¦f! ‰Ã~‰Æ¿µÙA 1Àè,Ùşÿ…ÛtH‰î¿ÌÙA é”  ¾R­A ¿Àb èj¹ÿÿH…ÀH‰Ãtw¾/   H‰ïA¼[ÙA èÙşÿH…ÀI‰Å„±   €;/„¨   HƒÎÿÆ@ H‰ï1ÀH‰ñò®H‰ßH÷ÑH‰ÊH‰ñò®H‰ÈH÷Ğ|ÿèÙxÿÿH‰îH‰Çèâ×şÿH‰ŞH‰Çè÷ÛşÿAÆE/H‰ÃëY¾.   H‰ïè ØşÿH…ÀI‰ÅtÆ  1ÀHƒÉÿH‰ïò®A¼aÙA H÷Ñyè…xÿÿH‰îH‰ÃH‰Çè‹×şÿ¾oÙA H‰ßèÛşÿM…ítAÆE .H‰ÚH‰î¿âÙA 1Àè"Øşÿ¿·£A è¨øÿÿ…À„   ƒ=qe!  ~H‰ÚL‰æ¿ÚA 1Àèõ×şÿH‰ßè/ûÿÿ¾¥A ¿Àb è<¸ÿÿ¾ Üb H‰Çè7†ÿÿ¾<¥A ¿Àb è ¸ÿÿ¾ Üb H‰Çèù‡ÿÿ¾¥A ¿Àb è¸ÿÿ¾ Üb H‰Çèî„ÿÿ¿   èKıÿÿ1ÿèÛşÿ¾oÙA H‰ßè«Øşÿ…ÀH‰î…ä  ¿ÚA A¼   è`×şÿH‰ïèšúÿÿè¨òÿÿ¿CÚA è©Öşÿ1ÿè”öÿÿè ÷ÿÿ¿QÚA 1Àè1×şÿè¥óÿÿI‰Åè”ÕşÿI¾U H‰ÃH‹ ‹ƒøQ„5  ƒøCtqƒøL„x  é<  ƒøT„y  ƒøW„  é%  ¿ÛA 1ÀèÕÖşÿèIóÿÿH¾I‰ÇH‹‹ƒøHt|bE1öƒøB…•   L‰ÿè8Õşÿ¿
   è>ÕşÿE…ö„å  ¿
   è+Õşÿ¿   èÓõÿÿ1À¿ŒÚA èuÖşÿfƒ=‰”!  xŠ¿¸ÚA 1Àè_ÖşÿéyÿÿÿƒøNtƒøTtë3¾ZÜb ¿ÁÚA ë ¾`Üb ¿ÍÚA ëfƒ=J”!  x¾fÜb ¿ÜÚA èáòÿÿë¿¾×A 1ÀèÖşÿA¾   éTÿÿÿº   ¾TÜb ¿ÛA è öÿÿº   ¾VÜb ¿-ÛA èìõÿÿfƒ=Ø“! A¾   ~,º   ¾XÜb ¿@ÛA 1Éèêóÿÿ¿µ“! ¾pÜb ¿MÛA è°õÿÿL‰ÿè(Ôşÿ¿
   è.ÔşÿE…ö„Õ  èÕğÿÿ¿çÚA 1ÀètÕşÿèèñÿÿH¾I‰ÇH‹‹ƒøD„UÿÿÿƒøPtE1öƒøBt¬¿¾×A 1Àè@Õşÿë2¹   º   ¾RÜb ¿]ÛA èYóÿÿ¹   º   ¾PÜb ¿nÛA è@óÿÿA¾   éaÿÿÿè¿ôÿÿ¿ŠÛA 1ÀèğÔşÿfƒ=“!  ¿šÛA y¿·ÛA 1ÀèÕÔşÿ¿ÛA 1ÀèÉÔşÿè=ñÿÿI‰Æ‹×’! H‹I¾f…À‹Šˆ­   ƒúC„„   DE1ÿƒúB…¯   L‰÷èÓşÿ¿
   èÓşÿE…ÿ„Æ  fƒ=Š’!  ˆgÿÿÿ¿{ÛA è¾ÓşÿéXÿÿÿƒúDtJƒúPum¹   º   ¾nÜb ¿ÅÛA èjòÿÿ¹   º   ¾lÜb ¿ĞÛA èQòÿÿëE¾fÜb ¿¿ÛA èĞğÿÿë4f-àyúf‰’! ë%E1ÿƒúB„^ÿÿÿƒúEufàxúëŞ¿¾×A 1ÀèÖÓşÿA¿   é:ÿÿÿ¿ÚÛA èQôÿÿ…À„˜  H‰ïè$tÿÿ¾.   H‰ÃH‰ÇèÁÓşÿH‰ß¾jÙA Æ  èñÖşÿH‰ß¾yÛA èTÖşÿH…ÀH‰Ãu
¿ıÛA èÊqÿÿH‰Æ¿ÜA èµÓşÿ1ÀH‰ê¾0ÜA H‰ßè£Ôşÿ‹U‘! D¿e‘! ¨„½  ¿ğ¿VA ‹/‘! D¿-‘! D¿5#‘! ¨„®  D¿ÀA¹VA f‹‘! ¨„³  ¿Ğ¹VA AWAR1ÀWVH‰ßASAV¾=ÜA è-Ôşÿ¿à! HƒÄ01À¾bÜA H‰ßèÔşÿ¿È! f;¿! t¾÷tA H‰ß1ÀèôÓşÿH‰Ş¿,   è§Òşÿ¿! f;“! t¾÷tA H‰ß1ÀèÈÓşÿH‰Ş¿;   è{Òşÿ¿t! 1À¾oÜA H‰ßè¥Óşÿ¿`! f;W! t¾÷tA H‰ß1Àè†ÓşÿH‰Ş¿,   è9Òşÿ¿6! f;+! t¾÷tA H‰ß1ÀèZÓşÿH‰Ş¿
   èÒşÿH‰Ş¿sÜA è@ÒşÿD¿! fE…ÀyH‰Ş¿€ÜA è%Òşÿé§   AöÀ¿5Û! A¹VA ufAÁøA¹@tA E¿ÀAÿÀf‹Â! ¨„i  ¿Ğ¹VA PV1À¾†ÜA H‰ßèÓÒşÿ¿”! f;‹! Y^t¾÷tA H‰ß1Àè²ÒşÿH‰Ş¿,   èeÑşÿ¿h! f;]! t¾÷tA H‰ß1Àè†ÒşÿH‰Ş¿
   è9ÑşÿH‰ßèÁĞşÿ¿”ÜA 1Ûè¥ñÿÿ…À”ÃtcH‰î¿±ÜA 1ÀèÿĞşÿ1ÿƒ=Z^!  @”Çè©öÿÿƒ=J^!  t9¿ËÜA è:Ğşÿë-¿öÜA 1Ûè\ñÿÿ…À”Ãt1ÿèzöÿÿë¿¾×A 1Àè°Ğşÿ»   L‰ïè3Ïşÿ¿
   è9Ïşÿ…Û…9ùÿÿéıøÿÿ¿İA 1Àèúnÿÿ‰Â¿@tA fÁúfA÷ü¿ğé4ıÿÿ‰Â¹   A¹@tA fÁúf÷ù˜D@é>ıÿÿ‰Â¹@tA fÁúfA÷ü˜Pé=ıÿÿ‰Â¹@tA fÁúfA÷ü˜Pé‡şÿÿUSH‰ıP¿   è7pÿÿH‰ïH‰ÃèspÿÿH‰H‹“! H‰“! H‰CZ[]ÃATUA¼xáb SH‹ş’! H‰ıH…Ût5H‹3H‰ïèóĞşÿ…ÀuH‹CI‰$H‹;è?ÎşÿH‰ß[]A\é3ÎşÿLcH‹[ëÆH‰î¿ğİA 1ÀènÿÿSH‹ª’! H…Àt}H‹8H‹Xè‘Îşÿ…Ày'è(Îşÿ‹8è!ÓşÿH‰ÂH‹’! ¿ŞA H‹01Àè”nÿÿëƒ=§\! ~H‹^’! ¿!ŞA H‹01Àè'ÏşÿH‹H’! H‹8è¨ÍşÿH‹=9’! èœÍşÿH‰-’! éwÿÿÿ[Ãf.„     @ AWAVA‰ÿAUATL%¦¾  UH-¾  SI‰öI‰ÕL)åHƒìHÁıèïÌşÿH…ít 1Û„     L‰êL‰öD‰ÿAÿÜHƒÃH9ëuêHƒÄ[]A\A]A^A_Ãf.„     óÃf.„     @ H!Ã  H…ÀtH‹1öéŠÑşÿf.„     1Ò1öéwÑşÿ€    H‰òH‰ş¿   éğÏşÿH‰ò‰ş¿   éaĞşÿHƒìHL$H‰T$‰òH‰ş1ÿè–ÏşÿHƒÄÃH‹Á½  Hƒøÿt(UH‰åSH¯½  Hƒì HƒëÿĞH‹HƒøÿuñHƒÄ[]óÃ HƒìèŸíşÿHƒÄÃ            usage: %s [ -C config_file ] -q [ -m map_file ] [ -v N | -v ... ]
 %7s%s [ -C config_file ] [ -b boot_device ] [ -c ] [ -g | -l | -L ]
 %12s[ -F ] [ -i boot_loader ] [ -m map_file ] [ -d delay ]
 %12s[ -v N | -v ... ] [ -t ] [ -s save_file | -S save_file ]
 %12s[ -p ][ -P fix | -P ignore ] [ -r root_dir ] [ -w | -w+ ]
 %7s%s [ -C config_file ] [ -m map_file ] -R [ word ... ]
 %7s%s [ -C config_file ] -I name [ options ]
 %7s%s [ -C config_file ] [ -s save_file ] -u | -U [ boot_device ]
 %7s%s -H				install only to active discs (RAID-1)
 %7s%s -A /dev/XXX [ N ]		inquire/activate a partition
 %7s%s -M /dev/XXX [ mbr | ext ]	install master boot record
 %7s%s -T help 			list additional options
 %7s%s -X				internal compile-time options
 %7s%s -V [ -v ]			version information

 1=0x%x
 2=0x%x
 3=0x%x
 B=0x%x
 C=0x%x
 M=0x%x
 N=0x%x

 
CFLAGS =  -Os -Wall -DHAS_VERSION_H -DHAS_LIBDEVMAPPER_H -DLILO=0xbb920890 -DLCF_BDATA -DLCF_DSECS=3 -DLCF_EVMS -DLCF_IGNORECASE -DLCF_LVM -DLCF_NOKEYBOARD -DLCF_ONE_SHOT -DLCF_PASS160 -DLCF_REISERFS -DLCF_REWRITE_TABLE -DLCF_SOLO_CHAIN -DLCF_VERSION -DLCF_VIRTUAL -DLCF_MDPRAID -DLCF_DEVMAPPER  With  device-mapper 
glibc version %d.%d
 Kernel Headers included from  %d.%d.%d
 Maximum Major Device = %d
 MAX_IMAGES = %d		c=%d, s=%d, i=%d, l=%d, ll=%d, f=%d, d=%d, ld=%d
 IMAGE_DESCR = %d   DESCR_SECTORS = %d

 geometric linear /boot/map LINEAR no linear/lba32 No u No   NOT Non- WILL will not specifying options booting this image won't No s suppress issu /etc/lilo.conf atexit(sync) atexit(purge) AbBCdDEfiImMPrsSTxZ cFglLpqtVXz compact delay install fix fix-table ignore ignore-table force-backup nowarn raid-extra-boot bios-passes-dl ROOT /proc/partitions chroot %s: %s root at %s has no /dev directory chdir /: %s atexit() failed LILO version %d.%d%s  (test mode) 22-November-2015  (released %s)
   * Copyright (C) 1992-1998 Werner Almesberger  (until v20)
  * Copyright (C) 1999-2007 John Coffman  (until v22)
  * Copyright (C) 2009-2015 Joachim Wiedorn  (since v23)
This program comes with ABSOLUTELY NO WARRANTY. This is free software 
distributed under the BSD License (3-clause). Details can be found in 
the file COPYING, which is distributed with this software. Running %s kernel %s on %s
 Only one of '-g', '-l', or '-L' may be specified chrul ebda main: cfg_parse returns %d
 fstat %s: %s %s should be owned by root %s should be writable only for root nodevcache verbose May specify only one of GEOMETRIC, LINEAR or LBA32 Ignoring entry '%s' LBA32 addressing assumed LINEAR is deprecated in favor of LBA32:  LINEAR specifies 24-bit
  disk addresses below the 1024 cylinder limit; LBA32 specifies 32-bit disk
  addresses not subject to cylinder limits on systems with EDD-BIOS extensions;
  use LINEAR only if you are aware of its limitations. YyTt1 NnFf0 COMPACT may conflict with %s on some systems read cmdline %s: %s read descrs %s: %s lseek over zero sector %s: %s read second params %s: %s lseek keytable %s: %s read keytable %s: %s Warning: mapfile created with %s option
 Cannot undo boot sector relocation. Cannot recognize boot sector. Installed:  %s
 Global settings:   Delay before booting: %d.%d seconds
   No command-line timeout   Command-line timeout: %d.%d seconds
   %snattended booting
   %sPC/AT keyboard hardware prescence check
   Always enter boot prompt   Enter boot prompt only on demand   Boot-time BIOS data%s saved
   Boot-time BIOS data auto-suppress write%s bypassed
   Large memory (>15M) is%s used to load initial ramdisk
   %sRAID installation
   Boot device %s be used for the Map file
   Serial line access is disabled   Boot prompt can be accessed from COM%d
   No message for boot prompt   Boot prompt message is %d bytes
   Bitmap file is %d paragraphs (%d bytes)
   No default boot command line   Default boot command line: "%s"
 Serial numbers %08X
 Images: %s%-15s %s%s%s  <dev=0x%02x,%s=%d>  <dev=0x%02x,hd=%d,cyl=%d,sct=%d>     Virtual Boot is disabled     Warn on Virtual boot     NoKeyboard Boot is disabled     No password     Password is required for %s
     Boot command-line %s be locked
     %single-key activation
     VGA mode is taken from boot image     VGA mode:  NORMAL EXTENDED ASK %d (0x%04x)
     Kernel is loaded "low"     Kernel is loaded "high"     No initial RAM disk     Initial RAM disk is %d bytes
        and is too big to fit between 4M-15M     Map sector not found Read on map file failed (access conflict ?) 2     Fallback sector not found Read on map file failed (access conflict ?) 3     No fallback     Fallback: "%s"
     Options sector not found Read on map file failed (access conflict ?) 4     Options: "%s"
     No options Read on map file failed (access conflict ?) 1 LILO     Pre-21 signature (0x%02x,0x%02x,0x%02x,0x%02x)
     Bad signature (0x%02x,0x%02x,0x%02x,0x%02x)
     Master-Boot:  This BIOS drive will always appear as 0x80 (or 0x00)     Boot-As:  This BIOS drive will always appear as 0x%02X
     BIOS drive 0x%02X is mapped to 0x%02X
     BIOS drive 0x%02x, offset 0x%x: 0x%02x -> 0x%02x
     Image data not found Checksum error
 raid_setup returns offset = %08X  ndisk = %d
 raid flags: at bsect_open  0x%02X
 Syntax error No images have been defined. Default image doesn't exist. Writing boot sector. The password crc file has *NOT* been updated. The boot sector and the map file have *NOT* been altered. %d warnings were  One warning was  %sed.
 M$@     $@     ²$@     Í$@     Ü$@     %@     }-@     %@     :%@     }-@     }-@     {%@     –%@     }-@     }-@     Ê%@     }-@     }&@     ,'@     C$@     R'@     l(@     }-@     K(@     }-@     ](@     }-@     }-@     }-@     }-@     }-@     }-@     }-@     r$@     $@     ¾$@     }-@     ò$@     %@     }-@     +%@     }-@     }-@     o%@     ‡%@     }-@     }-@     »%@     n&@     v(@     '@     ;'@     J'@     '@     (@     <(@     }-@     U(@     is_primary:  Not a valid device  0x%04X master:  Not a valid device  0x%04X is_accessible:  Not a valid device  0x%04X raid_setup: stat("%s") raid_setup: dev=%04X  rdev=%04X
 Not a RAID install, 'raid-extra-boot=' not allowed RAID1 install implied by 'boot=/'
 Unable to open %s Unable to stat %s %s is not a block device Unable to get RAID version on %s RAID_VERSION = %d.%d
 Raid major versions > 0 are not supported Raid versions < 0.90 are not supported Unable to get RAID info on %s GET_ARRAY_INFO version = %d.%d
 Incompatible Raid version information on %s   (RV=%d.%d GAI=%d.%d) Only RAID1 devices are supported as boot devices RAID install requires LBA32 or LINEAR; LBA32 assumed.
 auto mbr-only mbr RAID info:  nr=%d, raid=%d, active=%d, working=%d, failed=%d, spare=%d
 Not all RAID-1 disks are active; use '-H' to install to active disks only Partial RAID-1 install on active disks only; booting is not failsafe
 raid: GET_DISK_INFO: %s, pass=%d md: RAIDset device %d = 0x%04X
 Faulty disk in RAID-1 array; boot with caution!! disk %s marked as faulty, skipping
 RAID scan: geo_get: returns geo->device = 0x%02X for device %04X
 disk->start = %d		raid_offset = %d (%08X)
 %s (%04X) not a block device RAID list: %s is device 0x%04X
 Cannot write to a partition within a RAID set:  %s Warning: device outside of RAID set  %s  0x%04X
 Unusual RAID bios device code: 0x%02X Using BIOS device code 0x%02X for RAID boot blocks
 Boot sector on  %s  will depend upon the BIOS device code
  passed in the DL register being accurate.  Install Master Boot Records
  with the 'lilo -M' command, and activate the RAID1 partitions with the
  'lilo -A' command. MD_MIXED MD_PARALLEL MD_SKEWED  *NOT* Ex Im do_md_install: %s
   offset %08X  %s
 The map file has *NOT* been altered. The Master boot record of  %s  has%s been updated.
 The map file has *NOT* been updated. The boot record of  %s  has%s been updated.
 Specified partition:  %s  raid offset = %08X
 %splicit AUTO does not allow updating the Master Boot Record
  of '%s' on BIOS device code 0x80, the System Master Boot Record.
  You must explicitly specify updating of this boot sector with
  '-x %s' or 'raid-extra-boot = %s' in the
  configuration file. More than %d active RAID1 disks RAID offset entry %d  0x%08X
 RAID device mask 0x%04X
 lseek map file write map file fdatasync map file Hole found in map file (alloc_page) map_patch_first: String is too long lseek %s: %s read %s: %s write %s: %s map_patch_first: Bad write ?!? close %s: %s No image "%s" is defined creat %s: %s map_create: cannot fstat map file map_create:  boot=%04X  map=%04X
 map file must be on the boot RAID partition Hole found in map file (zero sector) Hole found in map file (descr. sector %d) Hole found in map file (default command line) Map file size: %d bytes.
 lseek map file to end map_close: lseek map_close: write Hole found in map file (app. sector) Covering hole at sector %d.
 LBA Compaction removed %d BIOS call%s.
 Empty map section   Mapped AL=0x%02x CX=0x%04x DX=0x%04x , %s=%d Map segment is too big. Calling map_insert_file map_insert_file: file seek map_insert_file: file read map_insert_file: map write Map file positioning error Calling map_insert_data map_insert_data: map write /etc/disktab  	 0x%x 0x%x %d %d %d %d Invalid line in %s:
"%s" DISKTAB and DISK are mutually exclusive /proc/devices Block %d %31s
 device-mapper major = %d
 /dev/mapper/control Major Device (%d) > %d %s is not a valid partition device start Duplicate geometry definition for %s do_disk: stat %s: %s  '%s' is not a whole disk device bios sectors heads cylinders max-partitions Cannot alter 'max-partitions' for known disk  %s disk=%s:  illegal value for max-partitions(%d) Implementation restriction: max-partitions on major device > %d Must specify SECTORS and HEADS together INACCESSIBLE and BIOS are mutually exclusive No geometry variables allowed if INACCESSIBLE Duplicate "disk =" definition for %s do_disk: %s %04X 0x%02X  %d:%d:%d
 can't open LVM char device %s
 LVM_GET_IOP_VERSION failed on %s
 LVM IOP %d not supported for booting
 can't open LVM block device %#x
 LV_BMAP error or ioctl unsupported, can't have image in LVM.
 Can't open EVMS block device %s.
 EVMS_GET_IOCTL_VERSION failed on %s.
 EVMS ioctl version %d.%d.%d does not support booting.
 Can't open EVMS block device %#x
 EVMS_GET_BMAP error or ioctl unsupported. Can't have image on EVMS volume.
 /dev/evms/block_device geo_query_dev: device=%04X
 Trying to map files from unnamed device 0x%04x (NFS/RAID mirror down ?) Trying to map files from your RAM disk. Please check -r option or ROOT environment variable. geo_query_dev FDGETPRM (dev 0x%04x): %s geo_query_dev HDIO_GETGEO (dev 0x%04x): %s HDIO_REQ not supported for your SCSI controller. Please use a DISK section WARNING: SATA partition in the high region (>15): LILO needs the kernel in one of the first 15 SATA partitions. If  you need support for kernel in SATA partitions of the high region  than try grub2 for this purpose!  Sorry, cannot handle device 0x%04x HDIO_REQ not supported for your Disk controller. Please use a DISK section HDIO_REQ not supported for your DAC960/IBM controller. Please use a DISK section HDIO_REQ not supported for your Array controller. Please use a DISK section Linux experimental device 0x%04x needs to be defined.
Check 'man lilo.conf' under 'disk=' and 'max-partitions=' Sorry, don't know how to handle device 0x%04x exit geo_query_dev Device 0x%04X: Configured as inaccessible.
 device-mapper: readlink("%s") failed with: %s device-mapper: realpath("%s") failed with: %s device-mapper: dm_task_create(DM_DEVICE_TABLE) failed device-mapper: dm_task_set_major() or dm_task_set_minor() failed device-mapper: dm_task_run(DM_DEVICE_TABLE) failed device-mapper: only linear boot device supported %02x:%02x %lu device-mapper: parse error in linear params ("%s") %u:%u %lu /dev/%s device-mapper: %s is not a valid block device /sys/block/%s/dev device-mapper: "%s" could not be opened. /sys mounted? device-mapper: read error from "/sys/block/%s/dev" %u:%u %x device-mapper: error getting device from "%s" device-mapper: Error finding real device geo_get: device %04X, all=%d
 This version of LVM does not support boot LVs /dev/md%d /dev/md/%d Only RAID1 devices are supported for boot images GET_DISK_INFO: %s BIOS drive 0x%02x may not be accessible Device 0x%04x: BIOS drive 0x%02x, no geometry.
 Device 0x%04X: Got bad geometry %d/%d/%d
 Device 0x%04X: Maximum number of heads is %d, not %d
 Maximum number of heads = %d (as specified)
   exceeds standard BIOS maximum of 255. Device 0x%04X: Maximum number of sectors is %d, not %d
 Maximum number of heads = %d (as specified)
   exceeds standard BIOS maximum of 63. device 0x%04x exceeds %d cylinder limit.
   Use of the 'lba32' option may help on newer (EDD-BIOS) systems. Device 0x%04x: BIOS drive 0x%02x, %d heads, %d cylinders,
 %15s%d sectors. Partition offset: %d sectors.
 %s:BIOS syntax is no longer supported.
    Please use a DISK section. %s: neither a reg. file nor a block dev. FIGETBSZ %s: %s Incompatible block size: %d
 geo_open_boot: %s
 Internal error: sector > 0 after geo_open_boot Cannot unpack ReiserFS file fd %d: REISERFS_IOC_UNPACK
 Cannot unpack Reiser4 file fd %d: REISER4_IOC_UNPACK
 Cannot perform fdatasync fd %d: fdatasync()
 ioctl FIBMAP LVM boot LV cannot be on multiple PVs
 EVMS boot volume cannot be on multiple disks.
 device-mapper: Sector outside mapped device? (%d: %u/%lu) device-mapper: mapped boot device cannot be on multiple real devices
 LINEAR may generate cylinder# above 1023 at boot-time. Sector address %d too large for LINEAR (try LBA32 instead). fd %d: offset %d -> dev 0x%02x, %s %d
 BIOS device 0x%02x is inaccessible geo_comp_addr: Cylinder number is too big (%d > %d) geo_comp_addr: Cylinder %d beyond end of media (%d) fd %d: offset %d -> dev 0x%02x, head %d, track %d, sector %d
 device-mapper: Mapped device suddenly lost? (%d)   evms_bmap       lvm_bmap Boot image: %s HdrS Setup length is %d sector%s.
 Setup length exceeds %d maximum; kernel setup will overwrite boot loader Kernel %s is too big Can't load kernel at mis-aligned address 0x%08x
 Mapped %d sector%s.
 initrd Kernel doesn't support initial RAM disks Mapping RAM disk %s RAM disk: %d sector%s.
 large-memory small-memory The initial RAM disk will be loaded in the high memory above 16M. The initial RAM disk is TOO BIG to fit in the memory below 15M.
  It will be loaded in the high memory it will be 
  assumed that the BIOS supports memory moves above 16M. The initial RAM disk will be loaded in the low memory below 15M. Boot device: %s, range %s
 Invalid range map-drive Invalid drive specification "%s" TO is required Mapping 0x%02x to 0x%02x already exists Ambiguous mapping 0x%02x to 0x%02x or 0x%02x Too many drive mappings (more than %d)   Mapping BIOS drive 0x%02x to 0x%02x
 (NULL) Name: %s  yields MBR: %s  (with%s primary partition check)
 /boot/chain.b , on  0/0x80 unsafe CHAIN Boot other: %s%s%s, loader %s
 TABLE and UNSAFE are mutually incompatible. 'other = %s' specifies a file that is longer
    than a single sector. This file may actually be an 'image =' Can't get magic number of %s First sector of %s doesn't have a valid boot signature master-boot boot-as 'master-boot' and 'boot-as' are mutually exclusive 'other=' options 'master-boot' and 'boot-as' are mutually exclusive global options Radix error, 'boot-as=%d' taken to mean 'boot-as=0x%x' Illegal BIOS device code specified in 'boot-as=0x%02x'   Swapping BIOS boot drive with %s, as needed
 Chain loader %s is too big Pseudo partition start: %d
 Duplicate entry in partition table Partition entry not found. boot_other:  drive=0x%02x   logical=0x%02x
 Mapped %d (%d+1+1) sectors.
 /dev/.devfsd scan_dir: %s
 opendir %s: %s .udev fd cache_add: LILO internal error Caching device %s (0x%04X)
 [Y/n] [N/y] 

Reference:  disk "%s"  (%d,%d)  %04X

LILO wants to assign a new Volume ID to this disk drive.  However, changing
the Volume ID of a Windows NT, 2000, or XP boot disk is a fatal Windows error.
This caution does not apply to Windows 95 or 98, or to NT data disks.
 
Is the above disk an NT boot disk?  Aborting ...
 lookup_dev:  number=%04X
 stat /dev: %s /tmp/dev.%d mknod %s: %s Created temporary device %s (0x%04X)
 Cannot proceed. Maybe you need to add this to your lilo.conf:
	disk=%s inaccessible
(real error shown below)
 Failed to create a temporary device Removed temporary device %s (0x%04X)
 /dev/ide/host%d/bus%d/target%d/lun0/ part%d disc /dev/loop/%d /dev/loop%d /dev/floppy/0 /dev/floppy/1 /dev/fd0 /dev/fd1 /dev/hdt /dev/hds /dev/hdr /dev/hdq /dev/hdp /dev/hdo /dev/hdn /dev/hdm /dev/hdl /dev/hdk /dev/hdj /dev/hdi /dev/sda /dev/hdh /dev/hdg /dev/hdf /dev/hde /dev/hdd /dev/hdc /dev/hdb /dev/hda %s/%s.%04X make_backup: %s not a directory or regular file %s exists - no %s backup copy made.
 Backup copy of %s has already been made in %s
 Backup copy of %s in %s
 Backup copy of %s in %s (test mode)
 /boot/%s.%04X VolumeID set/get bad device %04X
 VolumeID read error: sector 0 of %s not readable master disk volume ID record volid write error /dev/urandom static-bios-codes registering bios=0x%02X  device=0x%04X
 master boot record seek %04X: %s read master boot record %04X: %s Volume ID generation error Assigning new Volume ID to (%04X) '%s'  ID = %08X
 master boot record2 seek %04X: %s write master boot record %04X: %s register_bios: device code duplicated: %04X register_bios: volume ID serial no. duplicated: %08X Bios device code 0x%02X is being used by two disks
	%s (0x%04X)  and  %s (0x%04X) Using Volume ID %08X on bios %02X
  BIOS   VolumeID   Device   %02X    %08X    %04X
 
    The kernel was compiled with DEVFS_FS, but 'devfs=mount' was omitted
        as a kernel command-line boot parameter; hence, the '/dev' directory
        structure does not reflect DEVFS_FS device names. 
    The kernel was compiled without DEVFS, but the '/dev' directory structure
        implements the DEVFS filesystem. '/proc/partitions' does not exist, disk scan bypassed /proc/partitions references Experimental major device %d. /proc/partitions references Reserved device 255. /dev/ pf_hard_disk_scan: (%d,%d) %s
 '/proc/partitions' does not match '/dev' directory structure.
    Name change: '%s' -> '%s'%s Name change: '%s' -> '%s' '/dev' directory structure is incomplete; device (%d, %d) is missing. bypassing VolumeID scan of drive flagged INACCESSIBLE:  %s More than %d hard disks are listed in '/proc/partitions'.
    Disks beyond the %dth must be marked:
        disk=/dev/XXXX  inaccessible
    in the configuration file (/etc/lilo.conf).
 pf:  dev=%04X  id=%08X  name=%s
 Disks '%s' and '%s' are both assigned 'bios=0x%02X' Hard disk '%s' bios= specification out of the range [0x80..0x%02X] NT partition: %s %d %s
   %04X  %08X  %s
 pf_hard_disk_scan: ndevs=%d
 MDP-RAID detected,   k=%d
 noraid RAID controller present, with "noraid" keyword used.
    Underlying drives individually must be marked INACCESSIBLE. is_mdp:   %04X : %04X
 RAID versions other than 0.90 are not supported is_mdp: returns %d
 (MDP-RAID driver) the kernel does not support underlying
    device inquiries.  Each underlying drive of  %s  must
    individually be marked INACCESSIBLE. (MDP-RAID) underlying device flagged INACCESSIBLE: %s bypassing VolumeID check of underlying MDP-RAID drive:
	%04X  %08X  %s Resolve invalid VolumeIDs Resolve duplicate VolumeIDs Duplicated VolumeID's will be overwritten;
   With RAID present, this may defeat all boot redundancy.
   Underlying RAID-1 drives should be marked INACCESSIBLE.
   Check 'man lilo.conf' under 'disk=', 'inaccessible' option. device codes (user assigned pf) = %X
 BIOS code %02X is too big (device %04X) Devices %04X and %04X are assigned to BIOS 0x%02X device codes (user assigned) = %X
 device codes (BIOS assigned) = %X
 Filling in '%s' = 0x%02X
 Internal implementation restriction. Boot may occur from the first
    %d disks only. Disks beyond the %dth will be flagged INACCESSIBLE. 'disk=%s  inaccessible' is being assumed.  (%04X) device codes (canonical) = %X
 BIOS device code 0x%02X is used (>0x%02X).  It indicates more disks
  than those represented in '/proc/partitions' having actual partitions.
  Booting results may be unpredictable. Fatal:  First boot sector Second boot sector Chain loader Internal error: Unknown stage code %d Warning:  Out of memory Not a number: "%s" Not a valid timer value: "%s" %s doesn't have a valid LILO signature %s has an invalid stage code (%d) %s is version %d.%d. Expecting version %d.%d.  -> %s %s: value out of range [%d,%d] Invalid character: "%c" getval: %d
 current root. current root Reading boot sector from %s
 stat / Can't put the boot sector on logical partition 0x%04X %s is not on the first disk '-F' override used. Filesystem on  %s  may be destroyed. 
Proceed?  No variable "%s" optional Skipping %s
 Password SHS-160 = Image name, (which is actually the name) contains a blank character: '%s' Image name, label, or alias is too long: '%s' Image name, label, or alias contains an illegal character: '%s' Duplicate label "%s" Single-key clash: "%s" vs. "%s" Only %d image names can be defined Bitmap table has space for only %d images vmdefault nokbdefault Invalid image name. alias label SINGLE-KEYSTROKE requires the label or the alias to be only a single character Added %s  (alias %s)   @   &   +   ?   * %4s<dev=0x%02x,hd=%d,cyl=%d,sct=%d>
 %4s"%s"
 MDA menu Unable to determine video adapter in use in the present system. Video adapter (CGA) is incompatible with the boot loader selected for
  installation ('install = menu'). Video adapter (%s) is incompatible with the boot loader selected for
  installation ('install = bitmap'). bmp-timer bmp-table 'bmp-table' may spill off screen bmp-colors pw_file_update:  passw=%d
 pw_file_update label=<"%s">  0x%08X    %s
 Password file: label=%s
 Ill-formed line in .crc file end pw_fill_cache other Need label to get password 
Entry for  %s  used null password
    *** Phrases don't match *** Type passphrase:  Please re-enter:  read-only read-write Conflicting READONLY and READ_WRITE settings. ro  rw  current root=%x  /dev/mapper/ root=%s  LABEL= UUID= Illegal 'root=' specification: %s Warning: cannot 'stat' device "%s"; trying numerical conversion
 ramdisk ramdisk=%d  vga normal ask Command line options > %d addappend ADDAPPEND used without global APPEND literal check_options: "%s"
 Command line options > %d will be truncated. APPEND or LITERAL may not contain "%s" restricted mandatory MANDATORY and RESTRICTED are mutually exclusive bypass MANDATORY and BYPASS are mutually exclusive RESTRICTED and BYPASS are mutually exclusive BYPASS only valid if global PASSWORD is set PASSWORD and BYPASS not valid together Password found is vmwarn vmdisable VMWARN and VMDISABLE are not valid together nokbdisable MANDATORY is only valid if PASSWORD is set. RESTRICTED is only valid if PASSWORD is set. %s should be readable only for root if using PASSWORD bmp-retain single-key LOCK and FALLBACK are mutually exclusive TEXT BITMAP MENU message Bitmap Message Map %s is not a regular file. Filesystem would be destroyed by LILO boot sector: %s boot record relocation beyond BPB is necessary: %s ~ Using %s secondary loader
 Secondary loader: %d sector%s (0x%0X dataend).
 Ill-formed boot loader; no second stage section install(2) flags: 0x%04X
 bios_boot = 0x%02X  bios_map = 0x%02X  map==boot = %d  map S/N: %08X
 Cannot get map file status Map time stamp: %08X
 'bitmap' and 'message' are mutually exclusive Non-bitmap capable boot loader; 'bitmap=' ignored. Mapping %s file %s width=%d height=%d planes=%d bits/plane=%d
 Message specifies a bitmap file Video adapter does not support VESA BIOS extensions needed for
  display of 256 colors.  Boot loader will fall back to TEXT only operation. Unsupported bitmap Not a bitmap file %s is too big (> %d bytes) %s: %d sector%s.
 el-torito-bootable-cd unattended UNATTENDED used; setting TIMEOUT to 20s (seconds). serial Serial line not supported by boot loader Invalid serial port in "%s" (should be 0-3) Serial syntax is <port>[,<bps>[<parity>[<bits>]]] Serial speed = %s; valid parity values are N, O and E Only 7 or 8 bits supported Syntax error in SERIAL Serial Param = 0x%02X
 no PROMPT with SERIAL; setting DELAY to 20 (2 seconds) suppress-boot-time-BIOS-data boot-time BIOS data will not be saved. BIOS data check was okay on the last boot BIOS data check will include auto-suppress check Maximum delay is 59:59 (3599.5secs). Maximum timeout is 59:59 (3599.5secs). keytable %s: bad keyboard translation table menu-scheme 'menu-scheme' not supported by boot loader Invalid menu-scheme color: '%c' Invalid menu-scheme syntax Invalid menu-scheme punctuation menu-scheme BG color may not be intensified menu-scheme "black on black" changed to "white on black" Menu attributes: text %02X  highlight %02X  border %02X  title %02X
 menu-title 'menu-title' not supported by boot loader menu-title is > %d characters 'bmp-table' not supported by boot loader image_menu_space = %d
 'bmp-colors' not supported by boot loader 'bmp-timer' not supported by boot loader The boot sector and map file are on different disks. Unsupported baud rate VMDEFAULT image cannot have VMDISABLE flag set VMDEFAULT image does not exist. NOKBDEFAULT image cannot have NOKBDISABLE flag set NOKBDEFAULT image does not exist. Mandatory PASSWORD on default="%s" defeats UNATTENDED First stage loader is not relocatable. Boot sector relocation performed Failsafe check:  boot_dev_nr = 0x%04x 0x%04x
 map==boot = %d    map s/n = %08X
 LILO internal error:  Would overwrite Partition Table The system is unbootable !
	 Run LILO again to correct this. rename %s %s: %s End  bsect_update Boot sector of %s does not have a boot signature Boot sector of %s has a pre-21 LILO signature Boot sector of %s doesn't have a LILO signature /boot/boot.%04X Timestamp in boot sector of %s differs from date of %s
Try using the -U option if you know what you're doing. Reading old boot sector. Restoring old boot sector. Using s/n from device 0x%02X
 vga= kbd= nobd Cannot open: %s  at or above line %d in file '%s'
 '%s' doesn't have a value Value expected for '%s' Duplicate entry '%s' EOF in variable name control character in variable name variable name too long unknown variable "%s" EOF in quoted string Bad use of \ in quoted string internal error: again invoked twice \n and \t are not allowed in quoted strings Quoted string is too long \ precedes EOF Token is too long Unknown syntax code %d cfg_set: Can't set %s internal error (cfg_unset %s, unset) internal error (cfg_unset %s, unknown Value expected at EOF Syntax error after %s cfg_parse:  item="%s" value="%s"
 Unrecognized token "%s" cfg_get_flag: operating on non-flag %s cfg_get_flag: unknown item %s cfg_get_strg: operating on non-string %s cfg_get_strg: unknown item %s .shs Cannot stat '%s' '%s' more recent than '%s'
   Running 'lilo -p' is recommended. Could not delete '%s' Could not create '%s' w+ '%s' readable by other than 'root' deactivate automatic reset change Too many change rules (more than %d)   Adding rule: disk 0x%02x, offset 0x%x, 0x%02x -> 0x%02x
 Repeated rule: disk 0x%02x, offset 0x%x, 0x%02x -> 0x%02x Redundant rule: disk 0x%02x, offset 0x%x: 0x%02x -> 0x%02x -> 0x%02x "%s" is not a byte value Duplicate type name: "%s" part_nowrite check: part_nowrite: read: XFSB NTFS NTLDR part_nowrite lseek: part_nowrite swap check: SWAPSPACE2 SWAP-SPACE part_nowrite: %d
   A DOS/Windows system may be rendered unbootable.
  The backup copy of this boot sector should be retained. part_verify:  dev_nr=%04x, type=%d
 bs read lseek partition table Short read on partition table read boot signature failed part_verify:  part#=%d
 invalid partition table: second extended partition found secondary lseek64 failed secondary read pt failed read second boot signature failed Partition %d on %s is not marked Active. partition type 0x%02X on device 0x%04X is a dangerous place for
    a boot sector.%s I will assume that you know what you're doing and I will proceed.
 Device 0x%04X: Inconsistent partition table, %d%s entry   CHS address in PT:  %d:%d:%d  -->  LBA (%d)
   LBA address in PT:  %d  -->  CHS (%d:%d:%d)
 Either FIX-TABLE or IGNORE-TABLE must be specified
If not sure, first try IGNORE-TABLE (-P ignore) The partition table is *NOT* being adjusted. /boot/part.%04X Short write on %s Backup copy of partition table in %s
 Writing modified partition table to device 0x%04X
 Short write on partition table write partition table At least one of NORMAL and HIDDEN must be present do_cr_auto: other=%s has_partition=%d
 TABLE may not be specified AUTOMATIC must be before PARTITION TABLE must be set to use AUTOMATIC "%s" doesn't contain a primary partition table Cannot open %s Cannot seek to partition table of %s Cannot read Partition Table of %s partition = %d
 CHANGE AUTOMATIC assumed after "other=%s" "%s" isn't a primary partition Type name must end with _normal or _hidden ACTIVATE and DEACTIVATE are incompatible Unrecognized type name FAT16_lba FAT32_lba FAT32 DOS16_big DOS16_small DOS12 /boot/mbr.b *NOT*  Cannot open %s: %s stat: %s : %s %s not a block device %s is not a master device with a primary partition table seek %s; %s The Master Boot Record of  %s  has %sbeen updated.
 Cannot open '%s' Cannot fstat '%s' Not a block device '%s' Not a device with partitions '%s' read header lseek failed lseek vol-ID failed read vol-ID failed %s%d
 No active partition found on %s
 %s: not a valid partition number (1-%d) Cannot activate an empty partition pt[%d] -> %2x
 PT lseek64 failed PT write failure The partition table has%s been updated.
 No partition table modifications are needed. us.ktl No initial ramdisk specified No root specified identify: dtem=%s  label=%s
 setting  dflt No append= was specified %s %s
 identify_image: id='%s' opt='%s'
 No image found for "%s" 		Type Normal Hidden 	 **** no change-rules defined **** %20s  0x%02x  0x%02x
          usage: 	lilo -T %s%s	%s
 %4d			     ** empty **
 %4d:%d:%d %4d%18s%5s%11s%14s%12u%12u
  vol-ID: %08X

%s
 %4d%20ld%12d
     %s: %d cylinders, %d heads, %d sectors
 KMGT vol-ID: %08X     bios=0x%02x, cylinders=%d, heads=%d, sectors=%d	%s
 	(%3u.%02u%cb 	(%3u%cb ,%03u %14s sectors) 	LBA32 supported (EDD bios) 	C:H:S supported (PC bios) LiLo 22.5.1 22.0 24.2 22.5.7 Only 'root' may do this.

 The information you requested is not available.

Booting your system with LILO version %s or later would provide the re-
quested information as part of the BIOS data check.  Please install a more
recent version of LILO on your hard disk, or create a bootable rescue floppy
or rescue CD with the 'mkrescue' command.

 GEOMETRIC Int 0x13 function 8 and function 0x48 return different
head/sector geometries for BIOS drive 0x%02X fn 08 fn 48 LILO is compensating for a BIOS bug: (drive 0x%02X) heads > 255 LILO will try to compensate for a BIOS bug: (drive 0x%02X) sectors > 63 LBA32 addressing should be used, not %s Drive 0x%02X may not be usable at boot-time. 
BIOS reports %d hard drive%s
 Unrecognized BIOS device code 0x%02x
  all 
  BIOS     Volume ID
   0x%02X     %08X %s%s
 
Volume ID's are%s unique.
    '-' marks an invalid Volume ID which will be automatically updated
	the next time  /sbin/lilo  is executed.    '*' marks a volume ID which is duplicated.  Duplicated ID's must be
	resolved before installing a new boot loader.  The volume ID may
	be cleared using the '-z' and '-M' switches.     no %s
     %s = %dK
     Conventional Memory = %dK    0x%06X
     The First stage loader boots at:  0x%08X  (0000:%04X)
     The Second stage loader runs at:  0x%08X  (%04X:%04X)
     The kernel cmdline is passed at:  0x%08X  (%04X:%04X)
 purge: called purge: can't open /dev/mem purge:  purge: successful write get video mode determine adapter type get display combination check Enable Screen Refresh check VESA present mode = 0x%02x,  columns = %d,  rows = %d,  page = %d
 bug is present bugs are present is supported is not supported %s adapter:

 No graphic modes are supported     640x350x16    mode 0x0010     640x480x16    mode 0x0012
     320x200x256   mode 0x0013     640x480x256   mode 0x0101     800x600x256   mode 0x0103 
Enable Screen Refresh %s.
 Unrecognized option to '-T' flag bios_dev:  device %04X
 bios_dev: match on geometry alone (0x%02X)
 bios_dev:  masked device %04X, which is %s
 bios_device: seek to partition table - 8 bios_device: read partition table - 8 bios_device: seek to partition table bios_device: read partition table bios_dev: geometry check found %d matches
 bios_dev: (0x%02X)  vol-ID=%08X  *PT=%0*lX
 bios_dev: PT match found %d match%s (0x%02X)
 bios_dev: S/N match found %d match%s (0x%02X)
 Kernel & BIOS return differing head/sector geometries for device 0x%02X Kernel   BIOS maybe no yes floppy hard No information available on the state of DL at boot. BIOS provided boot device is 0x%02x  (DX=0x%04X).
 
Unless overridden, 'bios-passes-dl = %s' will be assumed.   If you
actually booted from the %s %s drive, then this assumption is okay. first second 3rd 7th 8th 9th 10th 11th 12th 13th 14th 15th 16th EGA MCGA VGA VGA/VESA DOS extended WIN extended Linux ext'd Linux Swap Linux Native Minix Linux RAID help Print list of -T(ell) options State of DL as passed to boot loader ChRul List partition change-rules EBDA Extended BIOS Data Area information geom= <bios> Geometry CHS data for BIOS code 0x80, etc. geom Geometry for all BIOS drives table= Partition table information for /dev/hda, etc. video Graphic mode information vol-ID Volume ID check for uniqueness  4.A     .A     +.A     +.A     +.A     +.A     .A     .A     +.A     $.A     $.A     $.A     rÑA     xÑA     ÑA     ¤ÑA     ©ÑA     ®ÑA     ƒÑA     ‡ÑA     ‹ÑA     ÑA     ”ÑA     ™ÑA     ÑA     £ÑA     ¨ÑA     ­ÑA     7¸A     ë£A     ·ÑA     ²ÑA     ¶ÑA     »ÑA     ¿ÑA     ¿ÑA     ñÁA           åÁA           ÛÁA           :»A           ÕÁA           ËÁA           ÁÁA           ÈÑA            ÕÑA            âÑA     …       îÑA     ‚       ùÑA     ƒ       ÒA            ÒA     ı                       %sColumn(X): %d%s (chars) or %hdp (pixels)    Row(Y): %d%s (chars) or %hdp (pixels)
 
Table dimensions:   Number of columns:  %hd
   Entries per column (number of rows):  %hd
   Column pitch (X-spacing from character 1 of one column to character 1
      of the next column):  %d%s (chars)  %hdp (pixels)
   Spill threshold (number of entries filled-in in the first column
      before entries are made in the second column):  %hd
 Table upper left corner:
   %sForeground: %hd%sBackground:  transparent%s %hd%s Shadow:  %hd %s text %s color (0..%d%s) [%s]:  ??? %s (%d..%d) or (%dp..%dp) [%d%s or %dp]:  ???1 ???2    Normal:   Highlight:       Timer:   Timer position:
   
	The timer is DISABLED. %s (%d..%d) [%hd]:   %s (yes or no) [%c]:   Cannot open bitmap file Cannot open temporary file get_std_headers:  returns %d
 read file '%s': %s Not a bitmap file '%s' Unsupported bitmap file '%s' (%d bit color) Unrecognized auxiliary header in file '%s' Error reading input Using Assuming .dat .bmp '%s'/'%s' filename extension required:  %s cfg_open returns: %d
 cfg_parse returns: %d
 Illegal token in '%s' Transfer parameters from '%s' to '%s' %s bitmap file:  %s
 Editing contents of bitmap file:  %s
 
Text colors: 
Commands are:  L)ayout, C)olors, T)imer, Q)uit, W)rite:   
Text color options:  N)ormal, H)ighlight,  T)imer,  Normal text Highlight text Timer text 
Layout options:  D)imensions, P)osition, B)ack:   
Number of columns Entries per column Column pitch Spill threshold 
Table UL column Table UL row 
Timer colors: 
Timer setup:   C)olors, P)osition, D)isable E)nable Timer 
Timer col Timer row Save companion configuration file? Open .dat file #
# generated companion file to:
#
 bitmap = %s
 bmp-table = %d%s,%d%s;%d,%d,%d%s,%d
 bmp-colors = %d, bmp-timer =  none
 %d%s,%d%s;%d, Save changes to bitmap file? Writing output file:  %s
 ***The bitmap file has not been changed*** Abandon changes? Unknown filename extension:  %s fg bg ,transparent ,none ‹BA     ‹BA     ™BA     ½BA     ½BA             'İA     *İA     ÎÌA             @tA     -İA     :İA                             0   LILOP `   €                     Internal error: temp_unregister %s (temp) %s: %s Removed temporary file %s
 ;  À   t>şÿT  4Dşÿ¼  dDşÿ¼  4_şÿ$  ”`şÿ|  #bşÿ”  eşÿ  Heşÿ,  “eşÿL  ¾eşÿl  épşÿÌ  ˜tşÿ  guşÿT  vşÿŒ  /xşÿÜ  ƒyşÿ	  ²zşÿ\	  {şÿŒ	  \{şÿ¬	  Ú{şÿÜ	  ñ{şÿô	  _|şÿ,
  i|şÿD
   €şÿ”
  9şÿä
  8‚şÿ$  ƒşÿl  ıƒşÿ¤  í†şÿ  ‡şÿ  Y‡şÿ4  ˆşÿl  Ã‹şÿÌ  ÓŒşÿü  ÷şÿ,  ”şÿ|  †–şÿ¼  ’¢şÿ  +¤şÿT  Y¥şÿ„  r¥şÿ¤  Šªşÿü  e«şÿ4  1¯şÿ„  ^°şÿÔ  Û±şÿ  å²şÿT  V¹şÿ¤  ˜¹şÿ¼  ¸¹şÿÜ  q»şÿ,  ö»şÿ\  À¼şÿŒ  u½şÿ¼  Í¿şÿ  PÀşÿ$  úÀşÿl  ÿÁşÿ¬  &Äşÿä  ×Çşÿ4  gÉşÿt  oÉşÿŒ  *Êşÿ¼  ‡Íşÿ  àÍşÿ4  lŞşÿ„  Şşÿœ  `ßşÿÔ  @àşÿü  màşÿ  ‡àşÿ4  àşÿL  Öàşÿl  TáşÿŒ  âşÿ¼  'âşÿÔ  yâşÿü  ”âşÿ  Éâşÿ,  ÿãşÿ|  ›æşÿ¬  "çşÿÔ  ¬çşÿ  *êşÿ\  Oìşÿ¬  iíşÿÜ  zîşÿ  Xğşÿ4  gñşÿ\  +òşÿ”  ¢óşÿÄ  ØóşÿÜ   ôşÿ  ¨õşÿD  åşşÿŒ  	ÿşÿ¬  âÿÿü  öÿÿ  Gÿÿ,  ˜ÿÿD  ÿÿ„  Tÿÿœ  ÿÿÌ  eÿÿì  —ÿÿ  ^ÿÿ<  Øÿÿl  öÿÿ¼  \ÿÿÜ  Dÿÿü  jÿÿL  [ÿÿ”  ïÿÿ´  Óÿÿô  ğÿÿ  =ÿÿ,  cÿÿL  Êÿÿ|  	 ÿÿ¬  r ÿÿÜ  Õ ÿÿ  “"ÿÿD  ª"ÿÿ\  É"ÿÿt  Ø#ÿÿ´  $ÿÿÜ  ©$ÿÿ  ·&ÿÿT  -ÿÿ¤  2-ÿÿÄ  ñ-ÿÿô  .ÿÿ   Å0ÿÿ\   	3ÿÿ¤   )3ÿÿ¼   ©3ÿÿÔ   h6ÿÿ!  ²9ÿÿT!  ‚;ÿÿŒ!  ?ÿÿÜ!  J?ÿÿô!  @ÿÿ"  I@ÿÿ,"  @ÿÿT"  ÑAÿÿ”"  CÿÿÔ"  5Cÿÿì"  ÜDÿÿ<#  °Fÿÿl#  +GÿÿŒ#  ¸JÿÿÜ#  CKÿÿ$  šKÿÿL$  ÃLÿÿœ$  ÂMÿÿÌ$  úMÿÿä$  ÄNÿÿ%  #Qÿÿ4%  ÿQÿÿT%  ¤RÿÿŒ%  äRÿÿ¤%  fVÿÿô%  ¿Vÿÿ&  °Wÿÿ,&  XYÿÿ|&  {Yÿÿ”&  ÂYÿÿ¬&  MZÿÿì&  æZÿÿ'  i[ÿÿD'  \ÿÿ\'  \ÿÿ”'  Ø\ÿÿ¼'  H^ÿÿ(  f_ÿÿd(  ×_ÿÿ„(  $`ÿÿœ(  ¤`ÿÿÔ(  aÿÿ)  Vcÿÿ\)  –dÿÿ|)  ĞeÿÿÌ)  Sfÿÿô)  ùoÿÿL*  -pÿÿt*  Špÿÿ¤*  $qÿÿÄ*  ”qÿÿ+  ¤qÿÿ$+  Ôqÿÿ<+  äqÿÿT+  ôqÿÿl+         zR x      Yşÿ*                  zR x  $      8şÿ°   FJw€ ?;*3$"       D   Zşÿ   Aƒ  $   \   ‡[şÿõ   A­B G(B0w   L   „    =şÿÉ   BBE B(ŒE0†A8ƒL°%Ÿ8C0A(B BBB         Ô   ^şÿ0    Aƒn          ô   ^şÿK    jƒ`Ã           ?^şÿ+    Aƒi       \   4  J^şÿ+   BBG B(ŒF0†A8ƒLĞ•ØMàmØAĞ.8C0A(B BBB    L   ”  işÿ¯   BBB B(ŒA0†A8ƒA@™8A0A(B BBB       4   ä  tlşÿÏ    BBŒA †A(ƒDp¼(C ABB4     mşÿ¥    BBŒD †A(ƒD0‘(A ABBL   T  xmşÿ#   BBD B(ŒE0†A8ƒMàû8A0A(B BBB      4   ¤  KoşÿT   BŒA†F ƒJ°< AAB      D   Ü  gpşÿ/   BBE ŒA(†F0ƒRÀ0A(A BBB      ,   $  Nqşÿh    GŒJ†A ƒBÃFÆBÌ      T  †qşÿB    Aƒ@      ,   t  ¨qşÿ~    BŒA†C ƒL0g AAB   ¤  öqşÿ           4   ¼  õqşÿn    BBŒD †A(ƒK@S(A ABB   ô  +rşÿ
           L     rşÿ—   BBD B(ŒF0†A8ƒGàq8D0A(B BBB      L   \  duşÿ9   BBE B(ŒD0†A8ƒOP8C0A(B BBB       <   ¬  Mvşÿÿ    BBŒD †A(ƒK°á(D ABB       D   ì  wşÿŞ    BBB ŒA(†D0ƒI°¾0D(A BBB       4   4  ¢wşÿç    BŒA†A ƒGà× AAB       \   l  Qxşÿğ   BBG B(ŒD0†A8ƒG 
¨
M°
K¨
A 
¯8A0A(B BBB       Ì  ázşÿ!              ä  êzşÿK    bT 4   ü  {şÿ4   BŒA†F ƒG° AAB      \   4  |şÿ6   BBG B(ŒF0†A8ƒGàÆèNğQèAàj8A0A(B BBB      ,   ”  ï~şÿ   A†AƒJàAA      ,   Ä  Ïşÿ$   A†AƒJğAA      L   ô  Ã€şÿ™   BBE B(ŒD0†A8ƒJ t8A0A(B BBB      <   D  ‡şÿö   BBŒA †A(ƒC0æ(A ABB       L   „  Âˆşÿ   BBE B(ŒA0†A8ƒMàCç8A0A(B BBB      D   Ô  ~”şÿ™   BBE ŒA(†D0ƒVĞl0A(A BBB      ,     Ï•şÿ.   A†AƒM°AA         L  Í–şÿ    AƒW       T   l  Æ–şÿ   BBE ŒA(†D0ƒG°-¸ZÀH¸A°§0D(A BBB     4   Ä  †›şÿÛ    BŒA†D ƒGĞÆ CAB       L   ü  )œşÿÌ   BBB B(ŒD0†A8ƒJğª8A0A(B BBB      L   L	  ¥Ÿşÿ-   BBŒD †A(ƒE0ò
(K ABBUA(A ABB      <   œ	  ‚ şÿ}   BBŒF †A(ƒI@b(A ABB       <   Ü	  ¿¡şÿ
   BBŒD †A(ƒJğğ(A ABB       L   
  ‰¢şÿq   BBG B(ŒD0†A8ƒPàD8A0A(B BBB         l
  ª¨şÿB    P f   „
  Ô¨şÿ     Aƒ^       L   ¤
  Ô¨şÿ¹   BBE B(ŒD0†A8ƒJ”8A0A(B BBB      ,   ô
  =ªşÿ…    BŒA†D ƒzAB      ,   $  ’ªşÿÊ    BŒA†D ƒP0« DAB,   T  ,«şÿµ    M†AƒI0›AÃAÆ      D   „  ±«şÿX   BBE ŒA(†C0ƒJĞ!80A(A BBB         Ì  Á­şÿƒ    Aƒ}      D   ì  $®şÿª    BHB ŒA(†C0ƒR°@0A(A BBB       <   4  †®şÿ   BBŒD †A(ƒIÀ`ì(A ABB       4   t  K¯şÿ'   BŒA†A ƒG   AAB      L   ¬  :±şÿ±   BBB B(ŒD0†A8ƒVğ!ƒ8A0A(B BBB      <   ü  ›´şÿ   BBŒD †A(ƒSàm(A ABB         <  ëµşÿ           ,   T  Ûµşÿ»    A†AƒIÀ­AA       L   „  f¶şÿ]   BBB B(ŒA0†A8ƒKÀ=8A0A(B BBB      $   Ô  s¹şÿY    A†AƒF NAAL   ü  ¤¹şÿŒ   BBB B(ŒA0†A8ƒGĞ!p8A0A(B BBB         L  àÉşÿ"    Aƒ     d  êÉşÿÒ    AƒJà         „  p/şÿ0    PN $   œ  „Êşÿà    AƒGàÖA          Ä  <Ëşÿ-    Aƒk          ä  IËşÿ    AX    ü  KËşÿ    AU      JËşÿ8    AƒI lA    4  bËşÿ~    AƒI pC,   T  ÀËşÿº    BŒA†F ƒ­AB         „  JÌşÿ           $   œ  KÌşÿR    A†AƒKD         Ä  uÌşÿ    DV    Ü  xÌşÿ5    GmL   ô  •Ìşÿ6   BBE B(ŒD0†A8ƒLP8C0A(B BBB       ,   D  {Íşÿœ   A†AƒJğAA      $   t  çÏşÿ‡    A†AƒD ~AA4   œ  FĞşÿŠ    BŒA†C ƒr
ABJAAB  L   Ô  ˜Ğşÿ~   BBB B(ŒD0†A8ƒGP\8D0A(B BBB       L   $  ÆÒşÿ%   BBB ŒA(†A0ƒ
(A BBBJA(A BBB   ,   t  ›Ôşÿ   BŒA†F ƒAB     $   ¤  …Õşÿ   AƒG A       ,   Ì  nÖşÿŞ   A†AƒD0ÕAA       $   ü  Øşÿ   AƒD A       4   $  ÙşÿÄ    A†AƒC l
AAE‰AA    ,   \  Ùşÿw   A†AƒG°kAA         Œ  ÖÚşÿ6           $   ¤  ôÚşÿH    A†AƒF }AA <   Ì  Ûşÿˆ   BBŒD †A(ƒD0t(A ABB       D     \Üşÿ=	   BBD ŒA(†F0ƒOÀ	
0A(A BBBA      T  Qåşÿ$    Aƒ^       L   t  UåşÿÙ   BBG B(ŒC0†A8ƒS€ª8A0A(B BBB         Ä  Şòşÿ              Ü  ÚòşÿQ    AO   ô  óşÿQ    AO<     Lóşÿ„    BBO ŒA(†A0ƒg(A BBB         L  óşÿ8    Re ,   d  °óşÿÇ   A†AƒI ¹AA         ”  G÷şÿJ    A}
JA   $   ´  q÷şÿ2   AƒIP
AA    $   Ü  {øşÿÇ    A†AƒI`¹AA,     ùşÿz   BBŒD †A(ƒMĞ!       L   4  dûşÿ   BBE B(ŒD0†A8ƒOĞô8A0A(B BBB          „  2üşÿf    AƒY         ¤  xüşÿè    AƒJà      L   Ä  @ışÿ&   BBE B(ŒD0†A8ƒJP8A0A(B BBB       D     şşÿñ    BBB ŒA(†A0ƒG°Ù0A(A BBB          \  ¿şşÿ”    AŠ
EC  <   |  3ÿşÿä   BBŒA †A(ƒG°Ğ(A ABB         ¼  × ÿÿ              Ô  Ü ÿÿM    AƒK         ô  	ÿÿ&    Aƒd       ,     ÿÿg    BŒA†D ƒG
ABA   ,   D  Fÿÿ?   BŒA†D ƒ4AB     ,   t  Uÿÿi    BŒA†D ƒ[AB      ,   ¤  ÿÿc    BŒA†D ƒXAB      4   Ô  Áÿÿ¾   BŒA†A ƒG°	® AAB           Gÿÿ              $  Fÿÿ           <   <  Mÿÿ   BBE ŒA(†D0ƒL@ì0A(A BBB$   |  ÿÿA    A†AƒI0qCA 4   ¤  5ÿÿ    BBŒD †A(ƒD0|(A ABB<   Ü  ÿÿ   BBŒA †A(ƒG°ø(C ABB      L     [ÿÿK   BBE B(ŒA0†A8ƒM #&8A0A(B BBB         l  Vÿÿ0    Aƒn       ,   Œ  fÿÿ¿    BŒA†F ƒ¤AB         ¼  õÿÿ    AK L   Ô  óÿÿ¾   BBB B(ŒA0†A8ƒGĞ¢8A0A(B BBB      D   $  aÿÿD   BBG ŒA(†F0ƒG€"0A(A BBB         l  ]ÿÿ     AZ    „  eÿÿ€    Am,   œ  Íÿÿ¿   BBŒF †A(ƒSÀ       L   Ì  \ÿÿJ   BBD B(ŒD0†A8ƒQà8D0A(B BBB      4     VÿÿĞ   BBG B(ŒA0†A8ƒMĞ     L   T  îÿÿŠ   BBG B(ŒA0†A8ƒD€c8F0A(B BBB         ¤  (ÿÿ>    As    ¼  Nÿÿ»    Hƒ     Ô  ñÿÿD    AƒW
Ja $   ô  ÿÿF    A†AƒF {AA <     3ÿÿB   A†AƒH€ˆEWˆA€DAA      <   \  5ÿÿ<   BBŒA †A(ƒLÀ#(A ABB         œ  1 ÿÿ(           L   ´  A ÿÿ§   BBE B(ŒD0†A8ƒP`|8A0A(B BBB       ,     ˜!ÿÿÔ   A†AƒA ÎAA          4  <#ÿÿ{    Aƒy      L   T  —#ÿÿ   BBB B(ŒA0†A8ƒNPg8D0A(B BBB       <   ¤  Ô&ÿÿ‹    BŒA†C ƒDPBXG`\XAPV AAB    ,   ä  'ÿÿW    AƒD@XHGP\HA@TA     L     F'ÿÿ)   BBG B(ŒA0†A8ƒD°8A0A(B BBB      ,   d  (ÿÿÿ    BŒA†F ƒêAB         ”  î(ÿÿ8    Av    ¬  )ÿÿÊ    HƒÁ      ,   Ì  ¸)ÿÿ_   BŒA†A ƒWAB        ü  ç+ÿÿÜ    AƒÍ
LA4     £,ÿÿ¥    BBB B(ŒA0†A8ƒD@         T  -ÿÿ@    D@{ L   l  8-ÿÿ‚   BBE B(ŒA0†A8ƒJğ`8A0A(B BBB         ¼  j0ÿÿY    JN   Ô  «0ÿÿñ    Aƒæ      L   ô  |1ÿÿ¨   jBD I(ŒH0†H8ƒ=Ã0MÆ(NÌ BÍBÎBÏ          D   Ô2ÿÿ#              \   ß2ÿÿG           <   t   3ÿÿ‹    HBE ŒA(†A0ƒr(A BBB         ´   Y3ÿÿ™    Gƒv      4   Ô   Ò3ÿÿƒ    BHŒE †D(ƒS0C(I ABB   !  4ÿÿ¢    Aœ4   $!  §4ÿÿ‚    BŒA†D ƒ[
ABJKAB  $   \!  ñ4ÿÿK    A†AƒI }AAL   „!  5ÿÿp   BBB B(ŒD0†A8ƒF€R8A0A(B BBB      T   Ô!  46ÿÿ   BBE B(ŒD0†A8ƒKX_`fhBpZP—8A0A(B BBB       ,"  ú6ÿÿq    VƒT
EA   L"  K7ÿÿM    Ks 4   d"  €7ÿÿ€    BBŒC †A(ƒQ@`(A ABB4   œ"  È7ÿÿg    BBŒD †A(ƒA0T(C ABBL   Ô"  ÷7ÿÿK   BBE B(ŒC0†A8ƒO` 8C0A(B BBB          $#  ò9ÿÿ@   Aƒ>     L   D#  ;ÿÿ:   BBE B(ŒD0†A8ƒTĞ8A0A(B BBB      $   ”#  ü;ÿÿƒ    Cƒ^
LA
SA  T   ¼#  W<ÿÿ¦	   BBG B(ŒA0†A8ƒD@ºHBPCXA`EhBpU@?HAP^HA@ $   $  ¥Eÿÿ4    A†AƒD kAA ,   <$  ±Eÿÿ]    BŒA†G ƒr
ABE       l$  ŞEÿÿŒ    AƒŠ      D   Œ$  XFÿÿe    BBE B(ŒH0†H8ƒM@r8A0A(B BBB    Ô$  €Fÿÿ              ì$  xFÿÿ)              %  Fÿÿ              %  ˆFÿÿ              4%  €Fÿÿ    D Z                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         ÿÿÿÿÿÿÿÿ        ÿÿÿÿÿÿÿÿ                                     ì              €@            ˆPA            x@            Ø@            @     
       z                                           b            p                           @            h@            ¨       	              şÿÿo    @     ÿÿÿo           ğÿÿo    R@                                                                                                                                     @b                     Æ@     Ö@     æ@     ö@     @     @     &@     6@     F@     V@     f@     v@     †@     –@     ¦@     ¶@     Æ@     Ö@     æ@     ö@     @     @     &@     6@     F@     V@     f@     v@     †@     –@     ¦@     ¶@     Æ@     Ö@     æ@     ö@     @     @     &@     6@     F@     V@     f@     v@     †@     –@     ¦@     ¶@     Æ@     Ö@     æ@     ö@      @      @     & @     6 @     F @     V @     f @     v @     † @     – @     ¦ @     ¶ @     Æ @     Ö @     æ @     ö @     !@     !@     &!@     6!@     F!@     V!@     f!@     v!@     †!@     –!@     ¦!@     ¶!@     Æ!@     Ö!@     æ!@     ö!@     "@     "@     &"@     6"@     F"@     V"@                                                             ÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿÿ               ?        ?       ??          ?? ?          ??   ????                                ?                                                                                                                                                                                                                                                                                                                                                                                                   ¶A      ¶A     §tA     %¶A                     kbgcrmywKBGCRMYW NnOoEe                         110 150 300 600 1200 2400 4800 9600 19200 38400 57600 115200 ? ? ? ? 56000  0123    ÿÿÿÿ       €+b      +b      !b      b      b     @b      b     àb     €b      b     Àb     @b     Àb     @b      b     Àb                                             R­A                                     <¥A                                     ¥A                                     ¥A                                                                                                   Û¹A                                    Ù¹A                                     2³A                                                                           ä¹A     CA                             ŞqA     A                                                                            zÁA                                     W§A                                                                                   î¹A     >A                             ˜ÌA     nA                                                                            =jA                                                                                            uA                                                                                            ŞqA     •e@                                                                                    ~uA                                     ‘uA                                     ‹uA                                    ²…A                                     ›uA                                     ƒuA                                                                                    ¶‹A                                    ô¹A     EA                             ŸA                                     U‰A     š@                            ª‹A                                     A°A                                    ŠA                                             b                             O‰A                                             b                                             |§A                                     §A                                     ‡‡A                                     ?§A                                    ]¦A                                    g¦A                                     ZA                                     S§A                                             b                                                     9£A                                    ş©A                                    a¨A                                     JbA                                     ?£A                                     «§A                                    §tA                                    '¨A                                    c©A                                    ¬¡A                                     S`A                                    ¨A                                    	ªA                                    -©A                                    &©A                                                                            §A                                     WA                                     %WA                                     R­A                                     <¥A                                    ş©A                                     ¥A                                     ¥A                                     '`A                                     ¶‹A                                    tÒA     -A                            ÉVA                                     £A                                     ÑVA                                     ]aA     Éf@                             6tA                                    ˜­A                                     JbA                                    ãVA                                     WA                                    íUA                                    ôVA                                     ‡‡A                                     ×VA                                     °A                                    ã‡A                                    VA                                    ÷UA                                     ŸA                                    §tA                                    '¨A                                     VA                                    ª‹A                                     G°A                                     ƒ±A                                     NªA                                    ZA                                     £A                                    æ™A                                    WA                                    ¬¡A                                     S`A                                    ¢]A                                     WA                                     ?§A                                    ]¦A                                    g¦A                                    ¨A                                     ZA                                     ì­A                                    	ªA                                    ğ‡A                                    “A                                    0¯A                                     ]A                                    ®­A                                     ZA                                     S§A                                     £A                                                                            `VA     ¾A                             Õ¥A     HA                                                                            `VA     ¡ğ@                             Õ¥A     Óñ@                                                                    Extended BIOS Data Area (EBDA)  ÿÿÿÿ                            		 Type  Boot      Start           End      Sector    #sectors  ÒA     …A             ÒA     ~uA     û4A             :ÒA     _ÒA     AA             eÒA     ÒA     ÿ*A             †ÒA     ªÒA     )A     °ÒA     ·ÒA     âÒA     ô(A             çÒA     ÓA      A     À-b     ÓA     :ÓA     _/A             @ÓA     YÓA     Ö)A             `ÓA                                     <device>    ÿÿÿÿ                   üëY   LILO     ¸                                                                        1ÛÓ¼ |‰å°=¹ÿÿò®&ŠG< wør‰>X ŒZ Ä>T è;¾¸ƒ<ÿu!Š& ŠD<ÿuˆà$€‰†Ä‰D8ÄuƒÆÆDÿÿ‰6T ¹ ¾ ‰ïó¥¾$|€~øuO&¬<€rI<wE&¬Àu?&¬<)t<(u5t¹ &¬Àx)t< r#âò¹ &¬Àx< râôè¬ ‰V$‹6 f‹Tf‰V¹  ¾ ¿¾ó¥¾ê­Àt:®t:PèQ XP¢®èx 8Ğu1À» ëè; é| ŒØ» À£²‰°¸‹®¹ Ír7XÄ°Ã¾ ã­&8u&ˆ'Æ´é ÿö´t¸‹®ÒtÄ°ÍrÃ¾Hè 1Òê |         V‹ ¾¸­	Àt8Ôu÷ˆÂ^Ã‹>T ƒ= tèê èÚÿ‹6 Æ¾1ÀØÀ» |‰Ü‰õPS6€?út€?ëu7PŠG˜@@ÃX€?úu(6fLILOu.fƒ>X  t.ÄX wü&fÇLILOˆÖ²şËPS¬Àt	´» Íëò[XÃRewrite error.
 `­	Àt$WëGG&ƒ= t&8%uó&Še&Çÿÿ8Ät‰CC_ë×&‹GG@tøH‰tCCëïaÃQV6ÿÍÁàÀ1ÿfÁà6f‡L f£¹- ¾^ó¥&‰^YÃ`‰å&ƒ= t4¹0 ƒì`‰ş‰ç­«	Àtâøë è uè¨ÿ‰æ‰óèbÿ‰æ¹0 ó¥‰ìaÃôëıQV6Ä>L 	ÿu;ŒÇÿ  s3ƒÿ`r.1ÿ¹ ¾^ó¦u&‹> ë1ÿ¹ ¾Uó¦u&‹=ÿF rÿP v1ÿ	ÿ^YÃPU‰åœV¾Z PU‰åë
LILO Z œV¾Z .‹t	Àt8Âuòˆâ^‰F‹F‹n š    U‰å‡Fœ€üt€üt	‹F
	ÀtˆÂ‹FF
]ƒÄÏ                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     FvjS                               úë1  LILO   |          ^¬Àt	´» Íëò¹ ´†ÍÍ1ÀĞ¼ |û‰áSVR‰ÎüØÀ¿ ¹ ó¥êV  `¸ ³6Íaf‹>¸f	ÿt´²€Í¶Ê’º€ è¡ f;>¸}tBâó’¾¾f1ÿ¹ èö€‰õx?ƒÆâñf‡ïf1ÿfïf‰>èm ¾¾}ö€x!ƒÆèç tåè\ÿNo partition active
 f‹Dfè8 >ş}Uªu1ÀX<şuˆÔ^[’ÿ.èÿNo boot sig. in partition
 `½ ¾»ªU´AÍrûUªu	öÁt´Bë?R´ÍrCQÀé†é‰ÏYÁê’@ƒá?÷á“¡‹9Ús"÷ó9øwÀä†à’öñâ‰ÑAZˆÆ¸Ä\ÍraÃ´@ZMt0äÍë‘èŒşDisk read error
 ŠD<t<t<…uf‹|Ã                                                                      HÀ“                               úë1  LILO   |          ^¬Àt	´» Íëò¹ ´†ÍÍ1ÀĞ¼ |û‰áSVR‰ÎüØÀ¿ ¹ ó¥êV  `¸ ³6Íaf‹>¸f	ÿt´²€Í¶Ê’º€ èš f;>¸}tBâó’¾¾¹ ö€‰õx3ƒÆâôèƒÿNo partition active
 ö€yèeÿInvalid PT
 ƒÆâæ‰îf‹Df£è= >ş}Uªu1ÀX<şuˆÔ^[’ÿ.è*ÿNo boot signature in partition
 `½ ¾»ªU´AÍrûUªu	öÁt´Bë?R´ÍrCQÀé†é‰ÏYÁê’@ƒá?÷á“¡‹9Ús"÷ó9øwÀä†à’öñâ‰ÑAZˆÆ¸Ä\ÍraÃ´@ZMt0äÍë‘è“şDisk read error
                                                                                                  `ç»¯                             &  ëN    LILO                                  ÿÿ  “  ÿÿ   “                  ü¡.‰ô$ÍÁà-€À1ö1ÿ1À¹ ó¥Ç ¹ ó«h~ Ëèƒ¹  ´Ít0äÍâô°LèÓ	j Å6x €|	w¿4%¹ ó¥&ÆEøj úÇx 4%Œz û.Æ% èc
ŒËÛÃë ¹ 9Ëv‰ËÇü$ (‰t	O ‰r	ŒÉ)ÙÁáÓ‰Ìf> LILOuf>K%MAGEu€> un>
 ufÇ%@%¿€4Š&ô$d  8Ät«1À«df¡ f; u7èŞ
è#» .¾à-­‘­’¬èò
‚Ç €Çşï-rë¾ .¿üfh·Áèc÷f;t»+"ë»C"ë»§"èÑôëıèô
s%¿ .öÿt÷E2 tWu6¹6 ó¤öÿuö_ëãƒÇ6ëŞèÿ
r%¿ .öÿt÷E2 €tWu6¹6 ó¤öÿuö_ëãƒÇ6ëŞ1Û‰î‰ø» -Š‡ş d » *‹Û-‹İ- ß-èA
r» *?òôu	Çmkè™	ëLÆG ëFéÿÆ è7¾ .¹ 0Òöÿt%‰óèƒÆşÂöÂuèëS° è[C9óvôƒÆ#âÖöÂtèıé€ »ç$èíf1Àf£%¢ç$Ç% €‡ 	%Ç%çè*
r€>  tdö uÇ%ÈèQr=d€>şşu&dŠÿdˆşdÄø&f?LILOud‹6ü&€< të¾*€< u¡%ÿàèpÇ%@%¾%»Æ!è_»P%ŠÀtSè`[CuòÆO% &€<ÿt&ŠFë!èÄéÿ¹Ãèx€>ù t
<àtÀ„JÀtÓ<	tÛ<?t×Àtk<ta<t{<tYw¹<tV<tR< r­w8Gÿt¦ûO't 0ä‰CSèîPèÇX[ûQ%u‹è¹ ¿ .ˆÄ÷E2 tŠèk8àu€} t&ƒÇ6âåébÿéÓ éS¡%è=[s»ª#è•ÆP% éÿÇ%E%Æ% 0Àˆ¾P%¿T'Æ% ¬ªÀuúûP%t	€ÿ uKˆ¾P%‰÷f<nobdu€| wd€ ë4f<vga=u	è¾‚½şë%f<kbd=uèëf<locku€| wÆ%ƒÆOëf<mem=uè9¬ª< tÀuöèôÿQ%tUë èÍ‚Š »"èØébşûP%t-KS»ï$èÇ[SÆ ¸P%)Øtè£ë¡ğ‹î9Øt“èË“è¼[éVşèlS1Àëáè›ëÆT' €>P% u¡» .1Àè§s¸ èÔr¸ @¹ …G2uƒÃ6âö» .‰Ş¿P%¬ˆGÀuøÇ ÿÿ¾P%¬Àt< u÷€< uÆDÿ N‰6%÷G2  t1ÀèÇsè­÷G2 t0èBs+Ç ÿÿS»a#è
¹kèKP< rè
è X[<yt<YtéyıöG2€töG2t€< ué¬ SÇ ÿÿ»Ë#èËU‰åì ‰æ1ÿ¹êè<tD<t/<t+<t<twä< ràÿ sÚ6ˆFG°*èëÎ	ÿtÊè NOëÃGOt¿è Në÷»ï$èsÃ1ÉAès)şWVè™
èÒ
è‹^¾¤4¹ ó¦^_tAQ¹ ‰÷1ÀóªY‰ì][	Ét	»Ö#è/é¹üÆO%=S»Í!è [Sè^VƒÆ-1À£; ¢? £ú$­‘­’¬V‹ü$èq» *‹Û-‹İ- ß-èÛÿ6 *» *èmX=òôt=mku» *?òôuè$» *èP‹6%¿ 6¹ÿşP%t¤â÷ëPX^VP¬ÀtªIë÷¾ *€< t/° ªIt5f<mem=uèÉ¬< tïÀtªIt< tã¬ëñ&€}ÿ uOA‹6%¬ªÀtâøˆt	1Ûèà ^­“­>% €t¡%ë÷Ã t&£úS÷Ã u€>% t»R'ÇòôVèw^1É&ñu±r	‰ÈÁàŒÃÃÃ€ ŒÈ9Ãv»%#èõ1ÛQèŠ Yâù[÷Ã t_&Æ ÷Ã t&¡ £; &  ¢? &>  vŒÈ+t	Áà ,&£$ &€ €^ÿ6;  ? PèµX¢? [‰; ˜	Øt1ÀÀ»  è ëè ëmh 1Ûè ëûè	 »º#èméÙøè XÃèøÿëLS‹6ú$‹ü$‹‹PŠ@	Éu	Òu[XÃƒÆ‰6ú$şü‚OÇú$  Šø$S‹ü$è’X¢ø$°.è$ë¶ö t¾ (Æ¸ KŠô$Íèºò1ÀîˆÂÍt	¿ 6ŒÈ+t	ÁàÇ&f>HdrSt@d€ r	f> LILOu!ƒ>
 u> u‹ ˆ ÇT €4ŒV d‹şé’ Š>? fÁã‹; fÁãf¡%f	Àtf)Øs»„"é›ø&>rŒÀf·Ğf·ÿfÁâfú&f‰(ë&Ç  ?£&‰>" »Ö!è;dö t»ó!è-ë*€ş-èad‹şèÙ
t&Ç  è°»ç!è	€&ş-ïè?¸ è÷ö %ÿtùèŞÄ 6ê    [PŒÀ	ÀXtëKS» Ã1Ûè@ ¢ù$[PQV‰Ş1ÉŠ.ù$ÿ6> SQV´‡Í^Y[rX:&? uÁé)ÀLDÀ^YXÃ[P»‘$ë&SQRèu‰ÇrZY[Áà ärÃsŒÀ À‰øÃP»ı!èd Xˆàè' èb Çú$  éÁö<ar<zw, Ã`¸: è<ö %ÿtùaÃPÀèè X$'ğ@ë4<
u°è+ °
<u€>ù u
S´Í0äÍ[ëè CŠÀuÔÃ°è °
Sè .ƒ>ö$ u» ´Í[ÃR.‹
%	ÒtƒÂPì¨t.Æ%¨ tñƒêXîZÃ¡ è¯ ´Íu,‹
%	ÒtƒÂì¨tƒêì$u€>ù tè+ö %tÑXÿá0äÍS» ,×[dö tö uÇ ÿÿÃèZ ´Í$_u&´Íu ‹
%	Òt€>% uƒÂì¨u	ö %tÔøÃùÃj úf¡p .f£%Çp kŒr ûÃj f¡%&f£p Ã	Àtú£ş$Æ % ûÃÆ %ÿÃœ.>ş$ÿÿt.ÿş$u.Æ %ÿ.fÿ6%Ï‹ ‹   » ,Ãèëÿdö €u
ö uè Ã‹Û-‹İ- ß-dö u0Æ;è{ Æ; s `€ütP»å"èyşXˆàè<şèwşë»#èhşaùÃöÂu´™ëÖV‹6i€âğÑîs`Æ;è8 Æ; aB	öuè^ëÓ  ècÿè r¾ ,¿øfh·Áè› ÷f;t»b"é?õÃètöÂ`u
P´èãYˆÈÃŠ&ø$†ğöÂ töÂ@tˆôˆ&ø$¶—ˆğöÂtèjèıˆÈÃf`àĞØr)ö t"f¸hXMVf1Ûf‰ÇºXVf¹
   fíf9ûøuf@tùfaÃPö tú°îæ`äd$túä`û4îuùXÃU‰åVWSQf1ÀfHGOt¹ &ŠFÑãfÑà€× Ğïsf3Fâîëâf÷ĞY[_^ÉÂ Sf¡%f	À…ì dö  „Ô f1Òf1öf1Ûëf	ÛttfRf¸ è  fºPAMSf¹   ¿ %ÍfZr`f=PAMSuXfƒùuRƒ>0%uÉf¡$%f¬ %
f¡,%f¬(%
f> %   r¨f> %  @ sf;6(%w–f‹ %f‹6(%fòë‡f	Òtf’ëU1É1Ò¸èùÍr;	Ét‰È	Òt‰Óf·Ûf·ÀfÁãf¹ @  f9ØwfËf‰Øëf   f9ÈufØë´ˆÍf·Àf   f» <  f9Øv2dö  uf“f»   t	>rf‹,fKfÁë
fCf9Ørf“[fÁèf·Ûf)Øf=   s»¦$è üfÁà£%£; fÁè¢%¢? Ãÿ6ü$ÿ6ú$Çü$ *‹D2$ d ƒÆ$f1Àf£%f­f£%fÿ  fÁè“­‘­’¬	ÛtBVS‹ü$èûÇú$  [èJşfƒ>% tr	f¡%&f£ f¡%&f£ j »  è÷ø° è{û^ú$ü$Ã
LI0000‹ şÊx[1À†ğPRÍj@[Ñã‹.‰
%[öÃútÁë.ŠŸüRƒÂì€îZR“îBˆàîBB“$îZRƒÂ°îZû¹  ìâıƒÂì¾ø¹ .¬èûâùÃUWV¿¤4f‹f‹uf‹Mf‹Uf‹})Ûf‰õf!ÍfVf÷Öf!Öf	õf^fÅ™y‚Zèt ƒûPrŞf‰Õf1Íf1õfÅ¡ëÙnè\ û  rçf‰Íf!õfQf	ñf!Ñf	ÍfYfí$Cäpè9 ûğ rİf‰Õf1Íf1õfí*>5è  û@rç»¤4ffwfOfWf^_]Ãfıf‰×f‰ÊfÁÎf‰ñf‰ÆfÁÀfÅƒû@sf‹‡À4ë6SƒÃ4ƒã<f‹‡À4ƒëƒã<f3‡À4ƒëƒã<f3‡À4ƒëƒã<f3‡À4fÑÀf‰‡À4[fèƒÃÃW¹ ¿À4f‹†ÄfÁÀ†Äf«âñ_ÃU‰åW¿¤4fÇ#EgfÇE‰«ÍïfÇEşÜº˜fÇEvT2fÇEğáÒÃf)Àf‰Ef‰E_ÉÃU‰åVW‹>¸4ƒç?f·Ff¸4fƒ¼4 ‹v¹@ )ù9ÈrÇÀ4)ÈPó6¤èuÿècşX)ÿëâÇÀ4‰Áó6¤_^ÉÃU‰åVW‹>¸4ƒç?Æ…À4€G)Àƒÿ8v¹@ )ùÇÀ4óªè7ÿè%ş¹8 ¿À4)Àë	¹8 )ùÇÀ4óªèÿf¡¸4f‹¼4f¤ÃfÁàf‰ø4f£ü4èïı_^ÉÃVSR0äPQSˆÖ€âöÆ t9<w5P»ªU´AÍXr*ûUªu$öÁt[YXPfj WQSPj‰æ¸ Bèw dëo[YSWQPSRWQ´èd r|QÀé†é‰ÏYÁê’@Iƒá?A÷á–XZ9òsd÷ö9øw^Àä†à’öñ(á‰ÎşÄ â‰ÑZ[†ğXP9ğr‰ğP´è [^Y_r;Ùƒ× “[ Ç Ç–)ğu“ë+€Ì U½ `ÍsMt1ÀÍaMëğ‰åf]ÃY_ë´@Z[YY_[ùYZ[^Ã  `1É1Ò‡€4è¢tW	Òt&‹GG	Àt8ğuóˆ&ô$_&‰¿X-¹ f1Àóf¯ty1É¿ 4èÙ f«f	ÀtdWQ‰ù¿ 4)ùÁéItòf¯u»eè÷èD÷Y_fÇEü    ë;¾X-¹ ‰÷ã/òf¯u*Uü)òÁê[S9ÓtˆŞÊ€€V»€4‹7CC9Öt		öuô‰Wş‰7^Y_AƒùrŒ¾˜-‹Ô-1Ûf1ÀÑês/f­fPf‹‡X-¿ 4¹ òf¯u½üË‰ùÁé¸ Óà	if…@4ëfXƒÃƒû@rÂaÃO
Error: Duplicated Volume ID
 SRQWQ´²€è«şYr!8ÑsˆÊ¹ » (€Ê€ˆî¸èşr&f‹‡¸ëf1Àù_YZ[ÃVPS¾€4ˆÓ€ã.Š&ô$öÂu
.­	Àt	8Øuö€âpâ[X^ÃU‰åƒ>i ud d> ëWQ‰×ƒçÁç‹@4‹½B4Nü~şY_]ÃQVj &Ä>L 	ÿu;ŒÇÿ  s3ƒÿ`r.1ÿ¹ ¾ró¦u&‹> ë1ÿ¹ ¾ió¦u&‹=ÿF rÿP v1ÿ	ÿ^YÃPU‰åœV¾ PU‰åë
LILO      LiLo              j » ~¹ ¶ ¸èŠı·¶¹H ró¤Ã°ÿóªëøR´A»ªUÍ†àŸZ«‰Ø«‘«r!ûUªuR‰şW´HÇ Í_†àŸƒÇ«ZÃ`j`¿ ‰>˜RÍ«Í«X«‰>š´Íj@Š„ «“«€ûué€ €ÿPr{´»ÿÍ«“«€üwl¸ Í«“«€ûu_<r[W¹4º€V½!C¸ »6 Í_«‘«’«•«¸ OÍ&‹&‹M«“«‘«ƒûOu'ùVEu!=SAu¸O¹Í&‹«“«¸O¹Í&‹«“«¹ 1Ò‰>’Q´RÍ†àŸ«’«‘«’ZrşÈyÒyYë6RW´Í†àŸ‰ıŒÃ_«‘«’«Zr€ú€u˜YPÒx•«“«ëèÆşˆYşÂâ­ÒW¹ ²€y£–”:wèyşBëô‰>ŒW1ÿ¾‚¹ ó¤_¾ )÷fh·Áè‘ö&f£  aÃ‰ØöÿtCëø)Ã“Ã`ƒ>  tD‹Ö-‹Ø- Ú-» (èZóècñh 1ÛSè÷[‡ = rwÆ èÍó1ÛèÁóëÿö$Çø1ö1ÿ¹ » .è—ÿ	Àt+÷G2 t	èÀõs‰6ğ÷G2 @t	èåõr‰6ğ9ør—ƒÃ6FâÎ‰6ò‰>ô‰ğ‹4-ØHöó:P-w P-‹6-8Øv“¢ö1À‰ñèk@âú¡îöP%ÿu¡ğèMaÃûP%tS»ï$è#ó[KëïÃVPèéÿ^kö6Æ .¬Àt
ˆCSèó[ëñ^Ã˜‹îÂ	Òy1Ò¡ò9Âr‰ÂJ¡î9Ğt
è’èô èºÿë]°€üPtÏöØ€üHtÈ‹ò€üOtÌ€üGtÅ ö’¡îöò’€üMu	B:4-r¤ë!€üIuöŞˆğë—€üQuöÖ ğëŒöØ€üKuÒuè€üSué¤ìé-ë`1À9ø£ö$£øtèéaÃ`öM-ÿx^º--‰d‰g¡ş$;ktJ£k@t,÷&m÷6o;it6£i1Ò÷6qÔ
00†Ä£d’Ô
00†Ä£ghF-jhdÿ6L-ÿ6N-è,ƒÄaÃ  :      •@œ< `£îh@-ë`h:-€>ù tJ‰Ã° ‹ôAA¿ÛQWóªkó6Æ .¿Ü¬Àtªëø‹2-¡0-‹6ö9ór8-)óëôÁãØPQè¸ƒÄ
ƒÄaÃ                                       ÿÿ              ÿÿ  ¬PƒşÀ% ÅİX(äÃ`¿P'.Å6ş‰Ñ= Œİwst~èÔÿPÁøªXI$ªâñëmƒù ~+è¾ÿˆÇˆÃ	Àt)Áè±ÿëPÁøªXşÏtP$ªXşÏÿuëÛuĞã.è‘ÿˆÇ)ÁˆÆşÆ€æëèÿPÁøªXşÏt
$ªşÏ€ÿ uéötèfÿ³ƒù Åè\ÿèYÿ.‰6ş.Œ aÃÈ  `j ‹…0ä‰Nş¯Á¾D–‰ÑƒáÁú¸ÿ kûPÓÈ×‰FúÇFü  ºÎÅ^&¬(äh  ÓÈP÷Ğ#FúPŠg8'XtPˆÄ°ïŠg& %Xã
°ïŠG& EŠG8t‹FüÁÀP°ïŠg& %Xã†Ä°ïŠg& eX‰FüPˆÄ°ïŠ& Xã	°ïŠ& EƒÇPÿNşuƒaÉÃ U‰å¸ è ‹N‹^‹VÅvãÿvÿv¬.ƒ>vèëèÿƒÂâêƒÄ1Àèl ÉÃ `PR¾P'‰÷´P¹ &¬ĞèĞÓĞèĞ×ĞèĞÒĞèĞÖâìˆØªˆøªˆĞªˆğªşÌuÙ[Áû_kÿPh  ¾P'¸ºÄïWV‰ÙP¬& ƒÆGâöX^_ĞäFöÄuâaÃ ƒ>w9ºÎ;t0£HtHtR¸ºÄïZ¸ ï¸ë¸ë¸
ï¸ ï¸ ï¸ÿïÃ È  VW‰úŒü‰^îŒFğ&?BMu&ƒ u&ƒ(t&ƒt¸ ùé,¡ú‹ü £ş‰ ‰Fê‰VìÂ‰Ã&€?(t2&‹G&÷g
‰Fş‰Á¸ Óà™‰Fú&€uM&àuEƒùtGƒùu;ë0&‹G&÷g‰Fş‰Á¸ Óà™‰Fú&€u&àuƒùtƒùu	Ç é£ ¸ ùé™Ç¿ (fÇVBE2¸ OÍ=O uwf=VESAun¸O‹Í=O u\‹… £‹… £‹ ¸	 ã@Ñéëù£‘f¸ÿÿÿÿfÓàf÷Ğf£
f÷Ğf%ÿÿÿ f£ö…  tŠ… $<u‹¸OÍ=O t1¸ ùéı »  ¸ Í<u
€ût€ût¸ ùéà »1 ¸Í¡Íº »  ¸$Í»6 ¸ÍÄ^ê&‹76ş 1ÛS.ƒ>wˆß¸ Í»ÿ?¬öçöóˆÁ¬öçöóˆÅ¬öçöóˆÆ0Ò[¸Í‹~ê€=tFC9^úÁÄ^î&‹G
&‹WúƒÒ Áâü£ş‰ 1Àè¡ı¸ è›ıÄ^ê¸àº€&€?É÷Ñ&#O‰Ë¾(¿Êƒ>v¾H¿-Hx“ÿÖ“ÿ×ëõ1Àèaı»6 ¸ Í1À_^ÉÃ 1ÀèMı»1 ¸ Í¸ ÍÃPQR÷&ØƒÒ ‰ÇŠ#>
­Ğ;t£’S1É1Û¸OÍ[ZYXÃ`¾P'‹
1Û1ÿ…Ïuè³ÿC¤9ÓróaÃ`¿P'Å6şŒİ…ÀtK·ë:ëè´ú‘ˆÏ„ÿtèªú)Êóª„ÿtƒú æƒú ~è•ú‘)ÊˆËãè‹úªâúĞësèú·ƒú Áèwúètúë‰Ñèmúªâú.‰6ş.Œ aÃÈ
  `j ‹…0ä‰Nş‰^ü‰Vú¯Á¾\–0íÄ~&Š&Šu&ŠU¬‰FøV“‹Fú‰Fö¾ 1ÿ.…>
uS‹Fü‹^öèäş[¸ 8Îtˆğ˜Ğås8ÊtˆĞ˜ĞãsˆÈ˜şÄ€üw&ˆGÿFöNuÁÿFüŠnøĞí^ÿNşu¢aÉÃƒÆ1ÀÀ¬Àt< uNÃ1É<ar, ,0<
r
<r',<s!ÑárÑárÑárÑár Á¬Àt< t<,tëÉ» $è¸ê¬Àt¹< tµëõè ë®è ë &‹‰ÚƒÂƒú>rº &;t&‰ &‰Ã»Z$èyêXë¾ƒÆV»< ^V‹	Ét,CC¬èêŠ'Cäu
Àt< tëá8àtçŠCÀuùëÔXN‰%øÃ^èÊ r‰Á	Òuëì»Ş#è'êf1Àf£%ùÃıÿASK şÿEXTENDED şÿEXT ÿÿNORMAL   Qèƒ r)Š€Ë €ûkt¹ €ûgt¹
 €ûmtNfÓèëfÑàrâùFøŠYÃf¸   ëòVƒÆè¾ÿr6€û@ufPFè±ÿfZr+f=   wfĞf=   v€Ë €û ufƒ>% uf£%^Ã[Ã»À"èxééäßè RPfXÃ1À1Ò¹
 €<9wH€<0rCuFII€<Xt€<xuÉF1ÛŠ€Ë €ë0r'8Ër€ÃÙ8ËsR÷áØƒÒ [R“÷á	Òu	ZÂr“FëÏùÃøÃQVW¹ ¾ .1ÛV¿P%öÿt4ŠFè©èˆÄŠGè¡èÀt< uät+ö u	Ûu[Së8àtÓ^ƒÆ6VâÄ^	Ûu¡îèæö1À_^YÃ[‰Ø- .±6öñ˜‹>î£î€>ù t9øt—è¿ö—è°öùëÔboot:  Loading  BIOS data check  successful
 bypassed
 
Error 0x No such image. [Tab] shows a list.
 O - Timestamp mismatch
 O - Descriptor checksum error
 O - Keytable read/checksum error
 Kernel and Initrd memory conflict
 O - Signature not found
 
vga/mem=  requires a numeric value
 
Map file write; BIOS error code = 0x 
Map file: WRITE PROTECT
 EBDA is big; kernel setup stack overlaps LILO second stage
 WARNING:  Booting in Virtual environment
Do you wish to continue? [y/n]  
*Interrupted*
 
Unexpected EOF
 Password:  Sorry.
 
Valid vga values are ASK, NORMAL, EXTENDED or a decimal number.
 
Invalid hexadecimal number. - Ignoring remaining items.
 
Keyboard buffer is full. - Ignoring remaining items.
 
Block move error 0x 
Initial ramdisk loads below 4Mb; kernel overwrite is possible.
 O 24.2              (               ÿ                                                  auto BOOT_IMAGE                                                                                                                                                                             ¾/Î.                             $  ëN    LILO                                  ÿÿ  “  ÿÿ   “                  ü¡.‰Â"ÍÁà-`À1ö1ÿ1À¹ ó¥Ç ¹ ó«h~ ËèŞ¹  ´Ít0äÍâô°Lèç	j Å6x €|	w¿#¹ ó¥&ÆEøj úÇx #Œz û.ÆÚ" è¾
ŒËÛÃë ¹ 9Ëv‰ËÇÊ" &‰–	O ‰”	ŒÉ)ÙÁáÓ‰Ìf> LILOuf>#MAGEu€> un>
 ufÇÜ"#¿€2Š&Â"d  8Ät«1À«df¡ f; u7è9è~» ,¾à+­‘­’¬èM‚Ê €Çşï+rë¾ ,¿üfh·Áè¾÷f;t»úë» ë»v èåôëıèOs%¿ ,öÿt÷E2 tWu6¹6 ó¤öÿuö_ëãƒÇ6ëŞèZr%¿ ,öÿt÷E2 €tWu6¹6 ó¤öÿuö_ëãƒÇ6ëŞ1Û‰R‰d» +Š‡ş d è » (‹Û+‹İ+ ß+è™
r» (?òôu	Çmkèñ	ëTÆG ëNéÿÆ èHÿÄ"¾ ,¹ 0Òöÿt%‰óè+ƒÆşÂöÂuè%ëS° è$[C9óvôƒÆ#âÖöÂtè
ÿÄ"é€ »¶"èöf1Àf£ê"¢¶"Çè" €‡ 	Ô"ÇÖ"òèz
r€>  tdö uÇÖ"øè¡r=d€>şşu&dŠÿdˆşdÄø&f?LILOud‹6ü&€< tëP¾(€< uF¡Ö"ÿàè—ƒ>  t,èv‹Ö+‹Ø+ Ú+‹Ê"èŞèä1Û‡ h Æ 1ÛèHÇÜ"#¾Û"»•è5»#ŠÀtSè6[CuòÆ# &€<ÿt	&ŠFëéÉş¹óèŸ<àtÀ„S<	té<?tåÀtk<ta<t{<tYwÇ<tV<tR< r»w8Gÿt´û%t®0ä‰CSèÒPèfX[û#u™èq¹ ¿ ,ˆÄ÷E2 tŠè]8àu€} t&ƒÇ6âåépÿéÓ éS¡Ô"èh[s»y!èyÆ# éõşÇÜ"#ÆÚ" 0Àˆ¾#¿"%ÆÏ" ¬ªÀuúû#t	€ÿ uKˆ¾#‰÷f<nobdu€| wd€ ë4f<vga=u	è]‚˜şë%f<kbd=uè¶ëf<locku€| wÆÏ"ƒÆOëf<mem=uèØ¬ª< tÀuöèØÿ#tUë èl‚Š »Öè¼é=şû#t-KS»¾"è«[SÆ ¸#)ØtèBë¡T‹R9Øt“èô“èæ[édşèyS1ÀëáèëÆ"% €># u¡» ,1ÀèÒs¸ èÿr¸ @¹ …G2uƒÃ6âö» ,‰Ş¿#¬ˆGÀuøÇ ÿÿ¾#¬Àt< u÷€< uÆDÿ N‰6Ş"÷G2 t0è~s+Ç ÿÿS»0!èÿ¹ŠèP< rèÿèõX[<yt<YtéeıöG2€töG2t€< ué¬ SÇ ÿÿ»š!èÀU‰åì ‰æ1ÿ¹	èD<tD<t/<t+<t<twä< ràÿ sÚ6ˆFG°*è“ëÎ	ÿtÊè NOëÃGOt¿è Në÷»¾"èhÃ1ÉAèh)şWVèÕ
èèW‹^¾¤2¹ ó¦^_tAQ¹ ‰÷1ÀóªY‰ì][	Ét	»¥!è$é¥üÆ#=S»œè[Sè^VƒÆ-1À£; ¢? £È"­‘­’¬V‹Ê"èt» (‹Û+‹İ+ ß+èÿ6 (» (èmX=òôt=mku» (?òôuè`» (èP‹6Ü"¿ 4¹ÿş#t¤â÷ëPX^VP¬ÀtªIë÷¾ (€< t/° ªIt5f<mem=uèy¬< tïÀtªIt< tã¬ëñ&€}ÿ uOA‹6Ş"¬ªÀtâøˆ–	1Ûèà ^­“­>è" €t¡è"ë÷Ã t&£úS÷Ã u€>Ï" t» %ÇòôVè³^1É&ñu±”	‰ÈÁàŒÃÃÃ€ ŒÈ9Ãv»ô èê1ÛQèŠ Yâù[÷Ã t_&Æ ÷Ã t&¡ £; &  ¢? &>  vŒÈ+–	Áà *&£$ &€ €^ÿ6;  ? PèñX¢? [‰; ˜	Øt1ÀÀ»  è ëè ëmh 1Ûè ëûè	 »‰!èbéºøè XÃèøÿëLS‹6È"‹Ê"‹‹PŠ@	Éu	Òu[XÃƒÆ‰6È"şü‚RÇÈ"  ŠÆ"S‹Ê"è•X¢Æ"°.èë¶ö t¾ &Æ¸ KŠÂ"Íè£èôºò1ÀîˆÂÍ–	¿ 4ŒÈ+–	ÁàÇ&f>HdrSt@d€ ”	f> LILOu!ƒ>
 u> u‹ ˆ ÇT €2ŒV d‹şé’ Š>? fÁã‹; fÁãf¡à"f	Àtf)Øs»S éyø&>rŒÀf·Ğf·ÿfÁâfú&f‰(ë&Ç  ?£&‰>" »¥è-dö t»Âèë*€ş+èšd‹şèt&Ç  èê»¶èû €&ş+ïèx¸ è0öÎ"ÿtùèÄ 4ê    [PŒÀ	ÀXtëKS» Ã1Ûè@ ¢Ç"[PQV‰Ş1ÉŠ.Ç"ÿ6> SQV´‡Í^Y[rX:&? uÁé)ÀLDÀ^YXÃ[P»`"ë&SQRè®‰ÇrZY[Áà ärÃsŒÀ À‰øÃP»ÌèV Xˆàè' èT ÇÈ"  éŸö<ar<zw, Ã`¸: èuöÎ"ÿtùaÃPÀèè X$'ğ@ë&<
u°è °
<uèÍëè CŠÀuâÃ°è °
Sè_ .ƒ>Ä" uUR€>e tAèJ<uÒu6ŠŠ°
şÎë'<
u:6‹s
< r;Šu`¸Š>†‹d‹ŠÍaşÎèZ» ´Í[ÃR.‹Ø"	ÒtƒÂPì¨t.ÆÚ"¨ tñƒêXîZÃ¡ è¨ ´Íu%‹Ø"	ÒtƒÂì¨tƒêì$uè"öÎ"tØXÿá0äÍS» *×[dö tö uÇ ÿÿÃèZ ´Í$_u&´Íu ‹Ø"	Òt€>Ú" uƒÂì¨u	öÎ"tÔøÃùÃj úf¡p .f£Ğ"Çp ÆŒr ûÃj f¡Ğ"&f£p Ã	Àtú£Ì"ÆÎ" ûÃÆÎ"ÿÃœ.>Ì"ÿÿt.ÿÌ"u.ÆÎ"ÿ.fÿ6Ğ"Ï‹ ‹   » *Ãèëÿdö €u
ö uè Ã‹Û+‹İ+ ß+dö u0Æ–è{ Æ– s `€ütP»´ è2şXˆàèşè0şë»Ú è!şaùÃöÂu´™ëÖV‹6Ä€âğÑîs`Æ–è8 Æ– aB	öuè^ëÓ  ècÿè r¾ *¿øfh·Áè› ÷f;t»1 éäôÃètöÂ`u
P´èãYˆÈÃŠ&Æ"†ğöÂ töÂ@tˆôˆ&Æ"¶—ˆğöÂtèjèıˆÈÃf`àĞØr)ö t"f¸hXMVf1Ûf‰ÇºXVf¹
   fíf9ûøuf@tùfaÃPö tú°îæ`äd$túä`û4îuùXÃU‰åVWSQf1ÀfHGOt¹ &ŠFÑãfÑà€× Ğïsf3Fâîëâf÷ĞY[_^ÉÂ Sf¡ê"f	À…ì dö  „Ô f1Òf1öf1Ûëf	ÛttfRf¸ è  fºPAMSf¹   ¿î"ÍfZr`f=PAMSuXfƒùuRƒ>ş"uÉf¡ò"f¬î"
f¡ú"f¬ö"
f>î"   r¨f>î"  @ sf;6ö"w–f‹î"f‹6ö"fòë‡f	Òtf’ëU1É1Ò¸èùÍr;	Ét‰È	Òt‰Óf·Ûf·ÀfÁãf¹ @  f9ØwfËf‰Øëf   f9ÈufØë´ˆÍf·Àf   f» <  f9Øv2dö  uf“f»   –	>rf‹,fKfÁë
fCf9Ørf“[fÁèf·Ûf)Øf=   s»u"è¹ûfÁà£á"£; fÁè¢ã"¢? Ãÿ6Ê"ÿ6È"ÇÊ" (‹D2$ d ƒÆ$f1Àf£à"f­f£ä"fÿ  fÁè“­‘­’¬	ÛtBVS‹Ê"èİúÇÈ"  [èJşfƒ>à" t”	f¡à"&f£ f¡ä"&f£ j »  è»ø° è4û^È"Ê"Ã
LI0000‹ şÊx[1À†ğPRÍj@[Ñã‹.‰Ø"[öÃútÁë.ŠŸWRƒÂì€îZR“îBˆàîBB“$îZRƒÂ°îZû¹  ìâıƒÂì¾S¹ .¬èûâùÃUWV¿¤2f‹f‹uf‹Mf‹Uf‹})Ûf‰õf!ÍfVf÷Öf!Öf	õf^fÅ™y‚Zèt ƒûPrŞf‰Õf1Íf1õfÅ¡ëÙnè\ û  rçf‰Íf!õfQf	ñf!Ñf	ÍfYfí$Cäpè9 ûğ rİf‰Õf1Íf1õfí*>5è  û@rç»¤2ffwfOfWf^_]Ãfıf‰×f‰ÊfÁÎf‰ñf‰ÆfÁÀfÅƒû@sf‹‡À2ë6SƒÃ4ƒã<f‹‡À2ƒëƒã<f3‡À2ƒëƒã<f3‡À2ƒëƒã<f3‡À2fÑÀf‰‡À2[fèƒÃÃW¹ ¿À2f‹†ÄfÁÀ†Äf«âñ_ÃU‰åW¿¤2fÇ#EgfÇE‰«ÍïfÇEşÜº˜fÇEvT2fÇEğáÒÃf)Àf‰Ef‰E_ÉÃU‰åVW‹>¸2ƒç?f·Ff¸2fƒ¼2 ‹v¹@ )ù9ÈrÇÀ2)ÈPó6¤èuÿècşX)ÿëâÇÀ2‰Áó6¤_^ÉÃU‰åVW‹>¸2ƒç?Æ…À2€G)Àƒÿ8v¹@ )ùÇÀ2óªè7ÿè%ş¹8 ¿À2)Àë	¹8 )ùÇÀ2óªèÿf¡¸2f‹¼2f¤ÃfÁàf‰ø2f£ü2èïı_^ÉÃVSR0äPQSˆÖ€âöÆ t9<w5P»ªU´AÍXr*ûUªu$öÁt[YXPfj WQSPj‰æ¸ Bèw dëo[YSWQPSRWQ´èd r|QÀé†é‰ÏYÁê’@Iƒá?A÷á–XZ9òsd÷ö9øw^Àä†à’öñ(á‰ÎşÄ â‰ÑZ[†ğXP9ğr‰ğP´è [^Y_r;Ùƒ× “[ Ç Ç–)ğu“ë+€Ì U½ `ÍsMt1ÀÍaMëğ‰åf]ÃY_ë´@Z[YY_[ùYZ[^Ã  `1É1Ò‡€2è¢tW	Òt&‹GG	Àt8ğuóˆ&Â"_&‰¿X+¹ f1Àóf¯ty1É¿ 2èÙ f«f	ÀtdWQ‰ù¿ 2)ùÁéItòf¯u»ÀèG÷è÷Y_fÇEü    ë;¾X+¹ ‰÷ã/òf¯u*Uü)òÁê[S9ÓtˆŞÊ€€V»€2‹7CC9Öt		öuô‰Wş‰7^Y_AƒùrŒ¾˜+‹Ô+1Ûf1ÀÑês/f­fPf‹‡X+¿ 2¹ òf¯u½üÍ‰ùÁé¸ Óà	Äf…@2ëfXƒÃƒû@rÂaÃO
Error: Duplicated Volume ID
 SRQWQ´²€è«şYr!8ÑsˆÊ¹ » &€Ê€ˆî¸èşr&f‹‡¸ëf1Àù_YZ[ÃVPS¾€2ˆÓ€ã.Š&Â"öÂu
.­	Àt	8Øuö€âpâ[X^ÃU‰åƒ>Ä ud d> ëWQ‰×ƒçÁç‹@2‹½B2Nü~şY_]ÃQVj &Ä>L 	ÿu;ŒÇÿ  s3ƒÿ`r.1ÿ¹ ¾Îó¦u&‹> ë1ÿ¹ ¾Äó¦u&‹=ÿF rÿP v1ÿ	ÿ^YÃPU‰åœV¾  PU‰åë
LILO      LiLo              j » ~¹ ¶ ¸è‰ı·¶¹H ró¤Ã°ÿóªëøR´A»ªUÍ†àŸZ«‰Ø«‘«r!ûUªuR‰şW´HÇ Í_†àŸƒÇ«ZÃ`j`¿ ‰>ôRÍ«Í«X«‰>ö´Íj@Š„ «“«€ûué€ €ÿPr{´»ÿÍ«“«€üwl¸ Í«“«€ûu_<r[W¹4º€V½!C¸ »6 Í_«‘«’«•«¸ OÍ&‹&‹M«“«‘«ƒûOu'ùVEu!=SAu¸O¹Í&‹«“«¸O¹Í&‹«“«¹ 1Ò‰>îQ´RÍ†àŸ«’«‘«’ZrşÈyÒyYë6RW´Í†àŸ‰ıŒÃ_«‘«’«Zr€ú€u˜YPÒx•«“«ëèÆşˆêYşÂâ­ÒW¹ ²€y£òğ:êwèyşBëô‰>èW1ÿ¾Ş¹ ó¤_¾ )÷fh·Áèö&f£  aÃ‰ØöÿtCëø)Ã“Ã´Íµ<t	j@Š.„ ˆáşÉ‰Š<u
fÿ6†f‚ÃPSQ´0ÿÍY[XÃPS´0ÿÍ[XÃR‹ŠşÆ0ÒèéÿZÃS´0ÿÍ´Í[ÃQSP´0ÿÍXPˆã¹ ´	ÍX[YÃPSRˆÄŠCÀtèÙÿşÂëòZ[XÃRQPÀyşÉşÂşÂ¸ ÊÍXYZ¨tOPV% ‰ÆÁæ´6Š&„‡ÊQ¬èÿşÂşÉŠuõF¬èÿşÆşÍŠuõYQF¬èÿşÊşÉŠuõF¬ètÿşÎşÍŠuõY‡Ñ^XÃ`˜‰ÆŠœoÁæ´j¿ ‡Ñˆéë`˜‰ÆŠœ]Áæ´X¿ ‡Ñè*ÿˆÜ:uŠd:DuŠdˆàŠ&„èÿúşÉt#èÿˆÜ:uŠd:DuŠdˆàŠ&„èúşúşÉuİèäşˆÜ:uŠd:DuŠdˆàŠ&„è×şaÃÚÄ¿³ÙÄÀ³ÉÍ»º¼ÍÈºÖÄ·º½ÄÓºÕÍ¸³¾ÍÔ³ÄÍ³ÃÅ´ºÇ×¶³ÆØµºÌÎ¹³ºÄÂÅÁÍÑØÏÄÒ×ĞÍËÎÊGqGNp  `èPşRè"ş‰Ê€>e u1ÉŠ>†° èšş1ö1ÿ¹ » ,èóı	Àt+÷G2 t	èôs‰6T÷G2 @t	è@ôr‰6T9ør—ƒÃ6FâÎ‰6X‰>Z»hè¶ıŠŠ(ÃĞëS‰ğ³<~şÃˆ^ ØşÈöó<°˜£\	 ˆÆ°öãˆÂŠŠ(ÑĞéµ°ƒŠ>‚èş‰`‰bRÊê‰fZ€Å‰å‡V ˆî»h …èÍıZ€Å°è^şQşÅ.\°èRş‰ÊRÂ ‚»”ö t»²èışÆ»Ñè–ışÆ»÷èı‹f»è„ıZY(îŠ&^¾ ,‹>X‰V€Á°èëıQR‰ÊÂ‹\9ùr‰ùãS‰ó ‚èMıPR€êˆÄ÷D2  °Uu°FöD2@u°LöD2u	°W÷D2 tè	ışÂöD2€t°PöD2t°RèôüZXşÆOƒÆ6â­ZY€ÁşÌt°èvıë¡Rö#ÿu¡Tè„Z€>e u‹`b0Ò€Æ‰dèˆüaÃû#tS»¾"èúï[KëïÃVPèéÿ^kö6Æ ,¬Àt
ˆCSèêï[ëñ^Ã˜‹RÂ	Òy1Ò¡X9Âr‰ÂJ¡R9Ğt
è’èèºÿë]°€üPtÏöØ€üHtÈ‹X€üOtÌ€üGtÅ \’¡Röò’€üMu	B:^r¤ë!€üIuöŞˆğë—€üQuöÖ ğëŒöØ€üKuÒuè€üSué—éé.è`‹`‹b°€Š>†èüaÃ`‹d‹Š0À·èıû‰Êè£ûaÃ`ƒ>f teº--‰»‰¾¡Ì";ÅtQ£Å@t#÷&Ç÷6É1Ò÷6ËÔ
00†Ä£»’Ô
00†Ä£¾èLûR‹fŠ&‚¾»»À¹ ¬:tèeûˆCşÂâñZè4ûaÃ  :  *****  •@œ< S£RŠ>ƒëSŠ>‚QRPèşúR‹VÂ‹ZAAS‹\9Ør€Â)Øëõ Æ[èÿúˆüèûşÂâôZèÙúXZY[Ãf?MENUu	f‹Wf‰‚ƒÃ	ŠGÿÀt˜‘ènú9Èu=% sW¿hŠC>ªÀu÷_Ã                      GNU/Linux - LILO 24 - Boot Menu       --:-- Hit any key to cancel timeout Hit any key to restart timeout Use  arrow keys to make selection Enter choice & options, hit CR to boot ƒÆ1ÀÀ¬Àt< uNÃ1É<ar, ,0<
r
<r',<s!ÑárÑárÑárÑár Á¬Àt< t<,tëÉ»ï!èıì¬Àt¹< tµëõè ë®è ë &‹‰ÚƒÂƒú>rº &;t&‰ &‰Ã»)"è¾ìXë¾ƒÆV»^V‹	Ét,CC¬èbìŠ'Cäu
Àt< tëá8àtçŠCÀuùëÔXN‰è"øÃ^èÊ r‰Á	Òuëì»­!èlìf1Àf£ê"ùÃıÿASK şÿEXTENDED şÿEXT ÿÿNORMAL   Qèƒ r)Š€Ë €ûkt¹ €ûgt¹
 €ûmtNfÓèëfÑàrâùFøŠYÃf¸   ëòVƒÆè¾ÿr6€û@ufPFè±ÿfZr+f=   wfĞf=   v€Ë €û ufƒ>ê" uf£ê"^Ã[Ã» è½ëéâè RPfXÃ1À1Ò¹
 €<9wH€<0rCuFII€<Xt€<xuÉF1ÛŠ€Ë €ë0r'8Ër€ÃÙ8ËsR÷áØƒÒ [R“÷á	Òu	ZÂr“FëÏùÃøÃQVW¹ ¾ ,1ÛV¿#öÿt4ŠFèüêˆÄŠGèôêÀt< uät+ö u	Ûu[Së8àtÓ^ƒÆ6VâÄ^	Ûu¡Rèpü1À_^YÃ[‰Ø- ,±6öñ˜‹>R£R€>e t9øt—èIü—è;üùëÔboot:  Loading  BIOS data check  successful
 bypassed
 
Error 0x No such image. [Tab] shows a list.
 O - Timestamp mismatch
 O - Descriptor checksum error
 O - Keytable read/checksum error
 Kernel and Initrd memory conflict
 O - Signature not found
 
vga/mem=  requires a numeric value
 
Map file write; BIOS error code = 0x 
Map file: WRITE PROTECT
 EBDA is big; kernel setup stack overlaps LILO second stage
 WARNING:  Booting in Virtual environment
Do you wish to continue? [y/n]  
*Interrupted*
 
Unexpected EOF
 Password:  Sorry.
 
Valid vga values are ASK, NORMAL, EXTENDED or a decimal number.
 
Invalid hexadecimal number. - Ignoring remaining items.
 
Keyboard buffer is full. - Ignoring remaining items.
 
Block move error 0x 
Initial ramdisk loads below 4Mb; kernel overwrite is possible.
 O 24.2             &               ÿ                                                  auto BOOT_IMAGE                                                                                                                                                                                                                               §¤                                ëN    LILO                                  ÿÿ  “  ÿÿ   “                  ü¡.‰šÍÁà-àÀ1ö1ÿ1À¹ ó¥Ç ¹ ó«h~ ËèL¹  ´Ít0äÍâô°Lè®	j Å6x €|	w¿Ø¹ ó¥&ÆEøj úÇx ØŒz û.Æ° è,
ŒËÛÃë ¹ 9Ëv‰ËÇ  ‰V	O ‰T	ŒÉ)ÙÁáÓ‰Ìf> LILOuf>ïMAGEu€> un>
 ufÇ²ä¿€*Š&šd  8Ät«1À«df¡ f; u7è§
èì» $¾à#­‘­’¬è»
‚½ €Çşï#rë¾ $¿üfh·Áè,÷f;t»Òë»êë»Nè¬ôëıè½
s%¿ $öÿt÷E2 tWu6¹6 ó¤öÿuö_ëãƒÇ6ëŞèÈ
r%¿ $öÿt÷E2 €tWu6¹6 ó¤öÿuö_ëãƒÇ6ëŞ» #Š‡ş d »  ‹Û#‹İ# ß#è
r»  ?òôu	Çmkèl	ëLÆG ëFéÿÆ è¾ $¹ 0Òöÿt%‰óèƒÆşÂöÂuèıëS° èü[C9óvôƒÆ#âÖöÂtèâé€ »èÒf1Àf£À¢Ç¾ €‡ 	ªÇ¬İèı	r€>  tdö uÇ¬ºè$r=d€>şşu&dŠÿdˆşdÄø&f?LILOud‹6ü&€< tëM¾ €< uC¡¬ÿàƒ>  t,èU‹Ö#‹Ø# Ú#‹ è¶è¾1Û‡ h Æ 1Ûè'Ç²ä¾±»mè»ôŠÀtSè[CuòÆó &€<ÿt	&ŠFëéÔş¹µè(Àtç<	tï<?tëÀtf<t\<tv<tTwÍ<tQ<tM< rÁw8Gÿtºûót´0ä‰CSè·[ûõu¤èT¹ ¿ $ˆÄ÷E2 tŠè@8àu€} t&ƒÇ6âåé{ÿéÓ éâ S¡ªèù[s»QècÆô éÿÇ²éÆ° 0Àˆ¾ô¿øÆ¥ ¬ªÀuúûôt	€ÿ uKˆ¾ô‰÷f<nobdu€| wd€ ë4f<vga=u	èx‚¦şë%f<kbd=uèÑëf<locku€| wÆ¥ƒÆOëf<mem=uèó¬ª< tÀuöèÂÿõt:ë è‡‚o »®è¦éKşûôt	KS»–è•[é“şûôt÷S»–è„[Këïè„ëÆø €>ô u¼» $1Àè~s¸ è«r¸ @¹ …G2uƒÃ6âö» $‰Ş¿ô¬ˆGÀuøÇ ÿÿ¾ô¬Àt< u÷€< uÆDÿ N‰6´÷G2 t0è*s+Ç ÿÿS»è¹Lè=P< rèèúX[<yt<YtéıöG2€töG2t€< ué¬ SÇ ÿÿ»rèÅU‰åì ‰æ1ÿ¹Ëèó<tD<t/<t+<t<twä< ràÿ sÚ6ˆFG°*è˜ëÎ	ÿtÊè NOëÃGOt¿è Në÷»–èmÃ1ÉAèm)şWVè
èº
è‹^¾¤*¹ ó¦^_tAQ¹ ‰÷1ÀóªY‰ì][	Ét	»}è)éÎüÆó=S»tè[Sè^VƒÆ-1À£; ¢? £­‘­’¬V‹ èr»  ‹Û#‹İ# ß#èÃÿ6  »  èmX=òôt=mku»  ?òôuè»  èP‹6²¿ ,¹ÿşôt¤â÷ëPX^VP¬ÀtªIë÷¾  €< t/° ªIt5f<mem=uè¯¬< tïÀtªIt< tã¬ëñ&€}ÿ uOA‹6´¬ªÀtâøˆV	1Ûèà ^­“­>¾ €t¡¾ë÷Ã t&£úS÷Ã u€>¥ t»öÇòôVè_^1É&ñu±T	‰ÈÁàŒÃÃÃ€ ŒÈ9Ãv»Ìèï1ÛQèŠ Yâù[÷Ã t_&Æ ÷Ã t&¡ £; &  ¢? &>  vŒÈ+V	Áà "&£$ &€ €^ÿ6;  ? PèX¢? [‰; ˜	Øt1ÀÀ»  è ëè ëmh 1Ûè ëûè	 »aègéøøè XÃèøÿëLS‹6‹ ‹‹PŠ@	Éu	Òu[XÃƒÆ‰6şü‚PÇ  ŠœS‹ è“X¢œ°.èë¶ö t¾ Æ¸ KŠšÍèüºò1ÀîˆÂÍV	¿ ,ŒÈ+V	ÁàÇ&f>HdrSt@d€ T	f> LILOu!ƒ>
 u> u‹ ˆ ÇT €*ŒV d‹şé’ Š>? fÁã‹; fÁãf¡¶f	Àtf)Øs»+éºø&>rŒÀf·Ğf·ÿfÁâfú&f‰(ë&Ç  ?£&‰>" »}è5dö t»šè'ë*€ş#èId‹şèÁ
t&Ç  è™»è€&ş#ïè'¸ èßö¤ÿtùèÆÄ ,ê    [PŒÀ	ÀXtëKS» Ã1Ûè@ ¢[PQV‰Ş1ÉŠ.ÿ6> SQV´‡Í^Y[rX:&? uÁé)ÀLDÀ^YXÃ[P»8ë&SQRè\‰ÇrZY[Áà ärÃsŒÀ À‰øÃP»¤è] Xˆàè' è[ Ç  éßö<ar<zw, Ã`¸: è#ö¤ÿtùaÃPÀèè X$'ğ@ë-<
u°è$ °
<uS´Í0äÍ[ëè CŠÀuÛÃ°è °
Sè	 » ´Í[ÃR.‹®	ÒtƒÂPì¨t.Æ°¨ tñƒêXîZÃ¡ è¥ ´Íu"‹®	ÒtƒÂì¨tƒêì$uö¤tÛXÿá0äÍS» "×[dö tö uÇ ÿÿÃèZ ´Í$_u&´Íu ‹®	Òt€>° uƒÂì¨u	ö¤tÔøÃùÃj úf¡p .f£¦Çp 4Œr ûÃj f¡¦&f£p Ã	Àtú£¢Æ¤ ûÃÆ¤ÿÃœ.>¢ÿÿt.ÿ¢u.Æ¤ÿ.fÿ6¦Ï‹ ‹   » "Ãèëÿdö €u
ö uè Ã‹Û#‹İ# ß#dö u0Æè{ Æ s `€ütP»Œè‹şXˆàèUşè‰şë»²èzşaùÃöÂu´™ëÖV‹62€âğÑîs`Æè8 Æ aB	öuè^ëÓ  ècÿè r¾ "¿øfh·Áè› ÷f;t»	évõÃètöÂ`u
P´èãYˆÈÃŠ&œ†ğöÂ töÂ@tˆôˆ&œ¶—ˆğöÂtèjèıˆÈÃf`àĞØr)ö t"f¸hXMVf1Ûf‰ÇºXVf¹
   fíf9ûøuf@tùfaÃPö tú°îæ`äd$túä`û4îuùXÃU‰åVWSQf1ÀfHGOt¹ &ŠFÑãfÑà€× Ğïsf3Fâîëâf÷ĞY[_^ÉÂ Sf¡Àf	À…ì dö  „Ô f1Òf1öf1Ûëf	ÛttfRf¸ è  fºPAMSf¹   ¿ÄÍfZr`f=PAMSuXfƒùuRƒ>ÔuÉf¡Èf¬Ä
f¡Ğf¬Ì
f>Ä   r¨f>Ä  @ sf;6Ìw–f‹Äf‹6Ìfòë‡f	Òtf’ëU1É1Ò¸èùÍr;	Ét‰È	Òt‰Óf·Ûf·ÀfÁãf¹ @  f9ØwfËf‰Øëf   f9ÈufØë´ˆÍf·Àf   f» <  f9Øv2dö  uf“f»   V	>rf‹,fKfÁë
fCf9Ørf“[fÁèf·Ûf)Øf=   s»MèüfÁà£·£; fÁè¢¹¢? Ãÿ6 ÿ6Ç   ‹D2$ d ƒÆ$f1Àf£¶f­f£ºfÿ  fÁè“­‘­’¬	ÛtBVS‹ è/ûÇ  [èJşfƒ>¶ tT	f¡¶&f£ f¡º&f£ j »  èù° èû^ Ã
LI0000‹ şÊx[1À†ğPRÍj@[Ñã‹.‰®[öÃútÁë.ŠŸÅRƒÂì€îZR“îBˆàîBB“$îZRƒÂ°îZû¹  ìâıƒÂì¾Á¹ .¬è"ûâùÃUWV¿¤*f‹f‹uf‹Mf‹Uf‹})Ûf‰õf!ÍfVf÷Öf!Öf	õf^fÅ™y‚Zèt ƒûPrŞf‰Õf1Íf1õfÅ¡ëÙnè\ û  rçf‰Íf!õfQf	ñf!Ñf	ÍfYfí$Cäpè9 ûğ rİf‰Õf1Íf1õfí*>5è  û@rç»¤*ffwfOfWf^_]Ãfıf‰×f‰ÊfÁÎf‰ñf‰ÆfÁÀfÅƒû@sf‹‡À*ë6SƒÃ4ƒã<f‹‡À*ƒëƒã<f3‡À*ƒëƒã<f3‡À*ƒëƒã<f3‡À*fÑÀf‰‡À*[fèƒÃÃW¹ ¿À*f‹†ÄfÁÀ†Äf«âñ_ÃU‰åW¿¤*fÇ#EgfÇE‰«ÍïfÇEşÜº˜fÇEvT2fÇEğáÒÃf)Àf‰Ef‰E_ÉÃU‰åVW‹>¸*ƒç?f·Ff¸*fƒ¼* ‹v¹@ )ù9ÈrÇÀ*)ÈPó6¤èuÿècşX)ÿëâÇÀ*‰Áó6¤_^ÉÃU‰åVW‹>¸*ƒç?Æ…À*€G)Àƒÿ8v¹@ )ùÇÀ*óªè7ÿè%ş¹8 ¿À*)Àë	¹8 )ùÇÀ*óªèÿf¡¸*f‹¼*f¤ÃfÁàf‰ø*f£ü*èïı_^ÉÃVSR0äPQSˆÖ€âöÆ t9<w5P»ªU´AÍXr*ûUªu$öÁt[YXPfj WQSPj‰æ¸ Bèw dëo[YSWQPSRWQ´èd r|QÀé†é‰ÏYÁê’@Iƒá?A÷á–XZ9òsd÷ö9øw^Àä†à’öñ(á‰ÎşÄ â‰ÑZ[†ğXP9ğr‰ğP´è [^Y_r;Ùƒ× “[ Ç Ç–)ğu“ë+€Ì U½ `ÍsMt1ÀÍaMëğ‰åf]ÃY_ë´@Z[YY_[ùYZ[^Ã  `1É1Ò‡€*è¢tW	Òt&‹GG	Àt8ğuóˆ&š_&‰¿X#¹ f1Àóf¯ty1É¿ *èÙ f«f	ÀtdWQ‰ù¿ *)ùÁéItòf¯u».è ÷è]÷Y_fÇEü    ë;¾X#¹ ‰÷ã/òf¯u*Uü)òÁê[S9ÓtˆŞÊ€€V»€*‹7CC9Öt		öuô‰Wş‰7^Y_AƒùrŒ¾˜#‹Ô#1Ûf1ÀÑês/f­fPf‹‡X#¿ *¹ òf¯u½üÕ‰ùÁé¸ Óà	2f…@*ëfXƒÃƒû@rÂaÃO
Error: Duplicated Volume ID
 SRQWQ´²€è«şYr!8ÑsˆÊ¹ » €Ê€ˆî¸èşr&f‹‡¸ëf1Àù_YZ[ÃVPS¾€*ˆÓ€ã.Š&šöÂu
.­	Àt	8Øuö€âpâ[X^ÃU‰åƒ>2 ud d> ëWQ‰×ƒçÁç‹@*‹½B*Nü~şY_]ÃQVj &Ä>L 	ÿu;ŒÇÿ  s3ƒÿ`r.1ÿ¹ ¾<ó¦u&‹> ë1ÿ¹ ¾2ó¦u&‹=ÿF rÿP v1ÿ	ÿ^YÃPU‰åœV¾  PU‰åë
LILO      LiLo              j » ~¹ ¶ ¸è‰ı·¶¹H ró¤Ã°ÿóªëøR´A»ªUÍ†àŸZ«‰Ø«‘«r!ûUªuR‰şW´HÇ Í_†àŸƒÇ«ZÃ`j`¿ ‰>bRÍ«Í«X«‰>d´Íj@Š„ «“«€ûué€ €ÿPr{´»ÿÍ«“«€üwl¸ Í«“«€ûu_<r[W¹4º€V½!C¸ »6 Í_«‘«’«•«¸ OÍ&‹&‹M«“«‘«ƒûOu'ùVEu!=SAu¸O¹Í&‹«“«¸O¹Í&‹«“«¹ 1Ò‰>\Q´RÍ†àŸ«’«‘«’ZrşÈyÒyYë6RW´Í†àŸ‰ıŒÃ_«‘«’«Zr€ú€u˜YPÒx•«“«ëèÆşˆXYşÂâ­ÒW¹ ²€y£`^:XwèyşBëô‰>VW1ÿ¾L¹ ó¤_¾ )÷fh·Áèö&f£  aÃƒÆ1ÀÀ¬Àt< uNÃ1É<ar, ,0<
r
<r',<s!ÑárÑárÑárÑár Á¬Àt< t<,tëÉ»ÇèÌó¬Àt¹< tµëõè ë®è ë &‹‰ÚƒÂƒú>rº &;t&‰ &‰Ã»èóXë¾ƒÆV»^V‹	Ét,CC¬è*óŠ'Cäu
Àt< tëá8àtçŠCÀuùëÔXN‰¾øÃ^èÊ r‰Á	Òuëì»…è;óf1Àf£ÀùÃıÿASK şÿEXTENDED şÿEXT ÿÿNORMAL   Qèƒ r)Š€Ë €ûkt¹ €ûgt¹
 €ûmtNfÓèëfÑàrâùFøŠYÃf¸   ëòVƒÆè¾ÿr6€û@ufPFè±ÿfZr+f=   wfĞf=   v€Ë €û ufƒ>À uf£À^Ã[Ã»gèŒòééè RPfXÃ1À1Ò¹
 €<9wH€<0rCuFII€<Xt€<xuÉF1ÛŠ€Ë €ë0r'8Ër€ÃÙ8ËsR÷áØƒÒ [R“÷á	Òu	ZÂr“FëÏùÃøÃQVW¹ ¾ $1ÛV¿ôöÿt4ŠFèÄñˆÄŠGè¼ñÀt< uät%ö u	Ûu[Së8àtÓ^ƒÆ6VâÄ^	Ûu1À_^YÃ[‰Ø- $±6öñ˜ùëîboot:  Loading  BIOS data check  successful
 bypassed
 
Error 0x No such image. [Tab] shows a list.
 O - Timestamp mismatch
 O - Descriptor checksum error
 O - Keytable read/checksum error
 Kernel and Initrd memory conflict
 O - Signature not found
 
vga/mem=  requires a numeric value
 
Map file write; BIOS error code = 0x 
Map file: WRITE PROTECT
 EBDA is big; kernel setup stack overlaps LILO second stage
 WARNING:  Booting in Virtual environment
Do you wish to continue? [y/n]  
*Interrupted*
 
Unexpected EOF
 Password:  Sorry.
 
Valid vga values are ASK, NORMAL, EXTENDED or a decimal number.
 
Invalid hexadecimal number. - Ignoring remaining items.
 
Keyboard buffer is full. - Ignoring remaining items.
 
Block move error 0x 
Initial ramdisk loads below 4Mb; kernel overwrite is possible.
 O 24.2                          ÿ                                                  auto BOOT_IMAGE         ìvÔ                               úë!´LILO                  €     ¸ÀĞ¼ ûRSVüØ1í`¸ ³6Ía°èf°
èa°Lè\`€úşuˆò» Šv‰Ğ€ä€0àx
<söF@u.ˆòf‹vf	öt#R´²€SÍ[rW¶Êº Bf1À@è` f;·¸tâïZSŠv¾  èß ´™füLILOu)^h€1ÛèÉ uû¾ ‰÷¹
 ´šó¦u°®u
U°IèÏ Ë´@° èÇ è´ şN t¼èaé\ÿôëı`UUfPSjj‰æSöÆ`tpöÆ t»ªU´AÍrûUªuöÁuAR´Ír´QÀé†é‰ÏYÁê’@Iƒá?A÷á“‹D‹T
9Ús’÷ó9øwŒÀä†à’öñâ‰ÑAZˆÆë´B[½ `ÍsMt¸1ÀÍaMëğfPYXˆæ¸ëádaÃf­f	Àt
fFè_ÿ€ÇÃÁÀè ÁÀ$'ğ@`» ´ÍaÃ                                                                        ‰tbGCC: (GNU) 5.3.0  .shstrtab .interp .note.ABI-tag .hash .dynsym .dynstr .gnu.version .gnu.version_r .rela.dyn .rela.plt .init .plt.got .text .fini .rodata .eh_frame_hdr .eh_frame .ctors .dtors .jcr .dynamic .got.plt .data .bss .comment                                                                              8@     8                                                 T@     T                                     !             x@     x                                 '             @           H	                          /             Ø@     Ø      z                             7   ÿÿÿo       R@     R      Æ                            D   şÿÿo       @           P                            S             h@     h      ¨                            ]      B       @           p                          g             €@     €      $                              b             °@     °      °                            m             `"@     `"                                    v             p"@     p"      .                            |             ˆPA     ˆP                                   ‚              PA      P     œ                              Š             <ŞA     <Ş                                  ˜             HäA     Hä     |%                             ¢             b                                        ©             (b     (                                   °             8b     8                                   µ             @b     @                                 q             àb     à                                   ¾              b           è                            Ç              b           ¤                              Í             À b     ¤      ÀB                              Ò      0               ¤                                                         µ      Û                                                                                                                                                                                                                                                                                                                                                                                                              ./.wifislax_bootloader_installer/syslinux32.com                                                     0000644 0000000 0000000 00000276504 12721171720 020665  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   ELF              û4   |w     4   	 ( % "    4   4€4€               T  TT                    € €L<  L<            ?   Ï Ï ”  €š           4?  4Ï4ÏÈ   È            h  hh              Påtd°6  °¶°¶ì   ì         Qåtd                          Råtd ?   Ï Ïà   à         /lib/ld-linux.so.2           GNU               %   *       !                          #   (       &                '         $                         )             
             "      %                                                                       	                                                                                                   h              ©   @c     ñ              ş              0             "             |              o              &   Dc     ;              4              ·   Hc     -              Ñ              5                           A              ›              Ø              ‹              °                           @              !              ê              Ê                 $ª     ¾              ƒ              )                          â              W              ’              H              “              ¢   `c     v              }              ù              P               libc.so.6 _IO_stdin_used strcpy exit optind perror unlink popen getpid pread64 calloc __errno_location open64 memcmp fputs fclose strtoul malloc asprintf getenv optarg stderr system optopt getopt_long pclose fwrite mkstemp64 fprintf fdopen memmove sync pwrite64 strerror __libc_start_main ferror setenv free __fxstat64 __gmon_start__ GLIBC_2.2 GLIBC_2.0 GLIBC_2.1                                                            ii   O     ii   Y     ii   c      üÏ  @c  Dc	  Hc  `c%  Ğ  Ğ  Ğ  Ğ  Ğ   Ğ  $Ğ  (Ğ
  ,Ğ  0Ğ  4Ğ  8Ğ  <Ğ  @Ğ  DĞ  HĞ  LĞ  PĞ  TĞ  XĞ  \Ğ  `Ğ  dĞ  hĞ  lĞ  pĞ  tĞ   xĞ!  |Ğ"  €Ğ#  „Ğ$  ˆĞ&  ŒĞ'  Ğ(  ”Ğ)  Sƒìèg  ÃGG  ‹ƒüÿÿÿ…ÀtèR  è-	  èø   ƒÄ[Ã   ÿ5Ğÿ%Ğ    ÿ%Ğh    éàÿÿÿÿ%Ğh   éĞÿÿÿÿ%Ğh   éÀÿÿÿÿ%Ğh   é°ÿÿÿÿ%Ğh    é ÿÿÿÿ% Ğh(   éÿÿÿÿ%$Ğh0   é€ÿÿÿÿ%(Ğh8   épÿÿÿÿ%,Ğh@   é`ÿÿÿÿ%0ĞhH   éPÿÿÿÿ%4ĞhP   é@ÿÿÿÿ%8ĞhX   é0ÿÿÿÿ%<Ğh`   é ÿÿÿÿ%@Ğhh   éÿÿÿÿ%DĞhp   é ÿÿÿÿ%HĞhx   éğşÿÿÿ%LĞh€   éàşÿÿÿ%PĞhˆ   éĞşÿÿÿ%TĞh   éÀşÿÿÿ%XĞh˜   é°şÿÿÿ%\Ğh    é şÿÿÿ%`Ğh¨   éşÿÿÿ%dĞh°   é€şÿÿÿ%hĞh¸   épşÿÿÿ%lĞhÀ   é`şÿÿÿ%pĞhÈ   éPşÿÿÿ%tĞhĞ   é@şÿÿÿ%xĞhØ   é0şÿÿÿ%|Ğhà   é şÿÿÿ%€Ğhè   éşÿÿÿ%„Ğhğ   é şÿÿÿ%ˆĞhø   éğıÿÿÿ%ŒĞh   éàıÿÿÿ%Ğh  éĞıÿÿÿ%”Ğh  éÀıÿÿÿ%üÏf        L$ƒäğÿqüU‰åWVSQìˆ$  ‹Y‹1èoşÿÿ£„e‹£€ePj SVè  ƒÄƒ= Ñ uPPj j@èÃ  ƒ= Ñ u-ƒ=Ñ u$ƒ=Ñ uƒ=Ñ uƒ=Ñ 	ƒ=(Ñ tPPÿ5@chPªèÿÿÿé—   ƒìh—ªèøıÿÿƒÄ‰Ã…Àu»KªWWjÿ5 ÑèûüÿÿƒÄ‰…tÛÿÿ…Àyƒìÿ5 ÑéÆ   …ˆÛÿÿVVPÿµtÛÿÿè|  ƒÄ…Àx×ƒ=,Ñ u:‹…˜Ûÿÿ% ğ  - `  © Ğÿÿt#Sÿ5 Ñhªÿ5@cè.şÿÿÇ$   è²ıÿÿƒì1Ò¡$ÑRPh   h€cÿµtÛÿÿè  ƒÄj h€cèƒ  ƒÄ…Àt	ƒìPé  …„ÛÿÿQShÛªPèïıÿÿƒÄ…Àx
‹…„Ûÿÿ…Àu	ƒìSèz  ƒìPèüüÿÿƒÄ…ÀxHRRhöªPè8ıÿÿƒÄ‰Ã…Àt21ÒPP¡$ÑRPÿµtÛÿÿÿ5„ehøªSèmıÿÿƒÄSèüÿÿƒÄ…Àtƒìÿµ„Ûÿÿë˜ƒìSèùûÿÿƒÄ…ÀuåWjÿµ„ÛÿÿhX«èıÿÿƒÄ…Àtƒìÿ5€eè
üÿÿéçşÿÿƒìh eè`  Ç$a«èlüÿÿ[^höªh«è»ûÿÿƒÄ‰Ã…Àuƒìh±«èo  ‹=¬¶PWjh@ÓèÁûÿÿƒÄ9ÇuØSh   jh eè¨ûÿÿƒÄ=   u¼ƒìSèEüÿÿƒÄ¨u¬¶Ä…Àu¥Çÿ  PÁï	PjWèôüÿÿZY‰…pÛÿÿÿµtÛÿÿh“è{  j ‰Æhµ¬j Pè2  ƒÄ1ÛPVèé  ƒÄ‰Á	Ñt 9û}‹pÛÿÿ‰Ù‰TÙQRPVCè  ƒÄëÚƒìVèÕ  ^_j ÿ5Ñÿ5Ñÿ5ÑS1ÛÿµpÛÿÿèœ  ¹@Óÿ  ƒÄ Áø	‰…lÛÿÿ;lÛÿÿ}N‹…pÛÿÿ‹5$Ñƒì1ÿ‹TØ‹Ø¤Â	Áà	‰hÛÿÿğúCRPh   QÿµtÛÿÿèA  ‹hÛÿÿÁ   ƒÄ ëª‹5Ñ…ö„'  èÛÿÿQQhÎ«S½ØëÿÿèvúÿÿƒÄ¹   …ìÛÿÿŠ„Òtq€ú/t€ú\u…É¹   u[ëF€ú't1É€ú!u:1É9øsGPÆ '9ús3PÆ@\9ús(P‰•pÛÿÿŠˆP9½pÛÿÿsÆ@'ƒÀë9øsˆ@ë
‰Ğë‹…pÛÿÿFë‰…ÉuÆ /@RRhÓ«PèÜùÿÿƒÄµèëÿÿShà«Vèçúÿÿ‰4$èúÿÿƒÄSh ¬VèĞúÿÿ‰4$èøùÿÿƒÄ¨u¶Ä…Àt Pÿ5€eh"¬ÿ5@cècúÿÿÇ$K¬ëWShk¬Vèúÿÿ‰4$ëƒìhK¬è«ùÿÿƒÄ¨u¶Ä…ÀtSÿ5€eh¬ÿ5@cèúÿÿƒÄƒìÿµ„Ûÿÿèåøÿÿ1Ò¡$Ñ‰$Ph   h€cÿµtÛÿÿèå  ƒÄjh€cè  1Ò¡$Ñ‰$Ph   h€cÿµtÛÿÿèi  ƒÄÿµtÛÿÿèúÿÿèúÿÿeğY1À[^_]aüÃ1í^‰áƒäğPTRh©h ©QVh0‹èdùÿÿôf‹$Ãffffff¸Cc-@cƒøv¸    …ÀtU‰åƒìÇ$@cÿĞÉÃ´&    ¸@c-@cÁø‰ÂÁêĞÑøtº    …ÒtU‰åƒì‰D$Ç$@cÿÒÉÃv ¼'    €=dc uHU¡hc‰åV¾(ÏS»,Ïë(ÏÁûK9Øst& @£hcÿ†¡hc9ØrîèIÿÿÿ[Ædc^]Ã´&    ¼'    ¸0Ï‹…ÒuéPÿÿÿº    …ÒtòU‰åƒì‰$ÿÒÉé6ÿÿÿU‰åƒìÿuÿ5€eh,ªÿ5@cèGøÿÿÇ$   èË÷ÿÿU‰åƒìè@øÿÿƒìÿ0è¦÷ÿÿ‰$ÿuÿ5€eh(ªÿ5@cè
øÿÿƒÄjè÷ÿÿU‰åWVSƒìÇEä    ‹]‹u‹}…ÛtWƒìWVSÿuÿuèøÿÿƒÄ …Àu
ƒìh4ªëƒøÿuèÇ÷ÿÿ‹ ƒøtÉƒìPè'÷ÿÿ‰$è9ÿÿÿ‰ÁEÁùÆÏEä)Ãë¥‹Eäeô[^_]ÃU‰åWVS‹u‹}‰ğ÷e¯ş‰Á‰Ó¡$Ñû1ÒÈÚ‰E[‰U^_]éMÿÿÿU‰åWVSƒìÇEä    ‹]‹u‹}…ÛtWƒìWVSÿuÿuèŸõÿÿƒÄ …Àu
ƒìh?ªëƒøÿuè÷ÿÿ‹ ƒøtÉƒìPètöÿÿ‰$è†şÿÿ‰ÁEÁùÆÏEä)Ãë¥‹Eäeô[^_]ÃU‰åWV‹U‹Eƒúu!‰Ç¾@Ñ¹   ƒÀZó¤¾šÑ¹i   ‰Çó¥ë*ƒúu%f‹@ÑƒÀTf‰P¬¾”ÑŠBÑ¹ª  ˆP®‰Çó¤^_]ÃU‰åWVSƒì,‹uŠF<ğtºÁ¬<÷†ø  ·F=   t,ˆ şÿÿº­ù   ‡Ö  Hÿ…Á…Ë  ºó¬éÁ  ·Ff…Àu*€~ u$€~ u€~ ufƒ~ ufƒ~ u
ƒ~  „6  ¶Nº#­ˆM×…É„z  Yÿ…Ë…o  ·V1Û‰Ñ…Òu‹N 1Û·~1Ò)ÁÓ‰MÈ1Ò‰]Ìf‰}Ô‰}ØÇEÜ    ‰ø…ÿu‹F$1Ò¶N‰Mà‰Ë¯Ú÷eà‹MÈÚ)Á‹]Ì·FÓƒÀÁø	™)ÁÓºB®…Ûˆü  …ÿu‹F$1Ò‰EØ‰UÜ‹Eà‹}Ü÷eØ¯}à‰Uä‰Eà}äº1®‹EäEà„Æ  ¶E×1ÒRPSQèî  ƒÄ‰Ã‰Uàƒú G  |=ôÿ  ‡×   º®fƒ}Ô „‰  €~&)…ÿ   ~6Pjh¦®Wè…óÿÿƒÄ…Àu!ƒ}à ğ   Œ×   ûô  ‡Ş   éÆ   Pjh¯®WèOóÿÿƒÄ…Àu!ƒ}à ŒÁ   ¡   ûô  †¯   é   Sjh¸®WèóÿÿƒÄº™­…À„ò   QjhÁ®WèûòÿÿƒÄ…Àt]‹V:‹F6‰ÕĞ£ÑĞºÀĞéÂ   ƒ}à ]|=ôÿÿwTºL­€~B)…¤   FR‰UàRjh¸®Pè§òÿÿƒÄºL­…À…€   1Òƒ} tx‹EÇ    ëmºì­ëfºÃ­ë_ºd­ëX^PjhÊ®Sè^òÿÿƒÄ…Àt/Pjh”®SèIòÿÿƒÄ…ÀtPjh®Sè4òÿÿƒÄºs®…Àu1Òƒ} t	‹EÇ    eô‰Ğ[^_]ÃU‰åWVSƒì\»@Ó‹=¬¶‹u‡ÿ  Áè	‰EĞƒÀ;EÄ  ;ş²>tƒÃëó·K‰M´Á@Ó‰Mä‹N‹Uä‰MØ‹·Rƒ} ‰Š@Ñ‹Mä·Q‹MØ‰Š@ÑN‰M°t‹Mä·QfÇ‚@ÑÍÁïPş‰}Ìf‰SfÇC
 ‰{ƒ} tfÇC ‹}ä·W
º@Ó‰}à‹}ä·O9È~QQÿ5@chÓ®é†  kÉ
1À‹}àóª‹EĞÇEÔ    HÇEØ    ‰E¤ÇEÜ    1ÀÇEÈ €  ‹MÔ‹}¤Q@Áâ	9ù‰UÄ„½   ‹}Ô‹MÔ…À‹|ş‰}À‹|Î‰}¼¿   „€   x1É‰úÁâ	‰U¸‰ÂUØMÜ‰U¨‰M¬‹M¨3MÀ‰M ‹M¬3M¼‰Ê‹M 	Ñu}¸ÿÿ  w‹MÈ‹U¸T
ÿ3UÄâ  ÿÿt‹}à‹UØ‹MÜ‰‰Of‰G¿   ƒEà
ë‹EØ‰EÀ‹EÜ‰E¼‹EÈ‰EÄ‰ø‹}À‰}Ø‹}¼‰}Ü‹}ÄÿEÔ‰}Èé,ÿÿÿ…Àt‹}à‹UØ‹MÜ‰‰Of‰G‹}Ğ‹E´ƒ} ·€@Óıøÿÿÿ‹|‹t‰°@Ó‹u°‰¸DÓ‹|‹t‰°HÓ‰¸LÓtM1ÀƒÉÿ‹}ò®‹Eä‰Î÷Ö·@‰ñ9Æ~RRÿ5@chü®è6ñÿÿÇ$   èjğÿÿ‹Eä‹u·PÂ@Ó‰×ó¤ƒ} t>1ÀƒÉÿ‹}ò®‹Eä‰Î÷Ö·@‰ñ9Æ~PPÿ5@ch-¯ë«‹Eä‹u·PÂ@Ó‰×ó¤ÇC    1Àºş²>;EÌ}
+…@Ó@ëñ‹EÌ‰SÁàëƒÈÿeô[^_]ÃU‰åSP‹]ƒûtprOƒû…†   Qÿ5€eh•²ÿ5@cè ğÿÿƒÄhK°hN°ÿ5@cèğÿÿXZÿ5@chM²èFğÿÿƒÄëtPÿ5€ehX¯ÿ5@cèÚïÿÿƒÄé   Qÿ5€ehå¯ÿ5@cè»ïÿÿƒÄhK°ët…ÛtjPhK°hN°ÿ5@cè—ïÿÿXZÿ5@chM²èÕïÿÿƒÄƒûuPPÿ5@chö²è»ïÿÿƒÄƒãıuSSÿ5@chE³è¡ïÿÿƒÄƒìÿuèÓîÿÿQhÇ®hN°ÿ5@cè-ïÿÿXZÿ5@chM²ë®U‰åVS‹u‹]‹£€eƒìj h`µh@µVÿuè´îÿÿƒÄ ƒøÿ„Ï  ƒøf„  ƒ   ƒøM„)  5ƒø„ã  H…}  ÇÑ   ë¤ƒø„-  ƒøH„  éZ  ƒøU„  ƒøO„Ï  ƒøS„Â   é8  ƒøa„å  ƒød…&  ¡`c£ÑéJÿÿÿƒør„  5ƒøi„"  ƒøh…ø  PPSj é  ƒøm„Œ  ƒøo„  é×  ƒøu„ü   ƒøs„Ó   ƒøt„&  éµ  ƒøv„‰  ƒøz…£  ÇÑ@   Ç Ñ    é½şÿÿÇ,Ñ   é®şÿÿPj j ÿ5`cèzíÿÿƒÄ£ ÑPÿƒú>†ŠşÿÿPÿ5€ehl³ë3Pj j ÿ5`cèHíÿÿƒÄ£ÑPÿúÿ   †UşÿÿPÿ5€eh³ÿ5@cèJíÿÿÇ$@   èÎìÿÿÇÑ   é#şÿÿÇÑ   éşÿÿÇÑ    éşÿÿÇÑ   éöıÿÿ…ÛuPÿ5€ehÏ³ÿ5@cèçìÿÿƒÄë¡`c£ÑéÇıÿÿPj j ÿ5`cè“ìÿÿƒÄ£$ÑéªıÿÿÇÑW¯é›ıÿÿ¡`c£(ÑéŒıÿÿÇ0Ñ   é}ıÿÿÇ4Ñ   énıÿÿƒûtVVëP¡`c£ ÑéVıÿÿQÿ5€eh´ÿ5@cèKìÿÿÇ$    éüşÿÿÿ5Hcÿ5€ehF´ÿ5@cè#ìÿÿXZSj@èÊûÿÿƒû¡Dctrƒûu-P‹†‰Dc£ Ñëƒ=Ñ uP‹†‰Dc£Ñ¡Dc‹†…Òtƒûu@‰8Ñ£Dc¡Dcƒ<† …:ÿÿÿeø[^]ÃU‰åWƒ=Ñ Stƒìh eèå  ƒÄ‹Ñ…Òu1Ûë:1ÀƒÉÿ‰×ò®÷ÑIPRQjèµ   ƒÄ…ÀtßPƒËÿÿ5€eh_´ÿ5@cèEëÿÿƒÄ‹(Ñ…Òt:‰×1ÀƒÉÿò®÷ÑIWRQjèq   ƒÄ…ÀtPƒËÿÿ5€eh‹´ÿ5@cèëÿÿƒÄeø‰Ø[_]ÃUºg£‰åWV‰ÆÇ ¥/-Z¸   +ƒÀ=ü  uó†   ‰VÇ†ü  d¿(İ¹€   ‰Çó¥^_]ÃU‰åWVSì  ‹EH=ş   vè¥êÿÿÇ    éƒ   }ÿ   woèıÿÿ¾¨e¹}   ‰ßó¥ºô  ¶¶CƒÀ„Ét89Mu$9Ğs/Q‰Ñ)ÁØQPS‰•äıÿÿè¬èÿÿƒÄ‹•äıÿÿëÉ9Ğw)ÂÃƒúw¼ëjƒ} t:‹EƒÀ9ĞvèêÿÿÇ    ƒÈÿëRŠEŠMˆCˆK‰Ç‹u‹Mó¤+U‰ûƒê1À‰Ñ‰ßµèıÿÿóª¸¨e¹}   ‰Ç¸ eó¥èÇşÿÿ1Àëƒ} tĞëeô[^_]ÃU1À‰åWS¹}   ‹UZ‰ßó«‰Ğ[_]é“şÿÿU‰åWV‹E8¥/-Zu:¸ü  d¿(İu.1Éº   ƒÂúü  uòùg£u   ¹€   ‰×‰ÆëF¸   ¥/-Zu@¸ü  d¿(İu4°   1Éº   Œ   ƒÂúü  uîùg£u¹€   ‰Çó¥1Àë
PèDÿÿÿXƒÈÿeø^_]ÃU‰åWVSƒì(j@è1èÿÿ‰ÃƒÄ1À…Û„‚  ‹EÇC<    ‰‹E‰CPj j Sè™  ƒÄ…À„L  fx …@  ¶pÇEä    ¿   ŠMä‰úÓâ¶Ê9ñtÿEäƒ}ä	uéé  ·p‹}ä‰S‰{…öu‹p ‰uØÇEÜ    ‹UØ‹MÜ·x‰S4‰K8·P1É‰S‰K ‰}à…ÿu‹x$‰}à¶p¯uà1ÿò·pù‰S$Áæ‰K(Æÿ  Áş	‰÷ÁÿÖÏ‰s,‰{09}Ü‚‘   w	9uØ††   ‹UØ‹MÜ)òù‰Ö‰ÏŠMä­şÓïöÁ t‰şVşô  ‰Sw‰ÑÇC    ÑùÊë%şôÿ  wÇC   Òëşôÿÿw1ÁâÇC   Âÿ  Áê	9Uàrƒ{u‹@,‰CëÇC    ‰ØëƒìSèÕåÿÿƒÄ1Àeô[^_]ÃU‰åSƒì‹]Sèî   ‰]ƒÄ‹]üÉé©åÿÿU‰åWVSƒì$ÿu‹u‹}Vè«  ‰Uä‰Eà‹EäƒÄEà„¥   ƒ}äÿuƒ}àÿuƒÈÿé–   QÿuäÿuàVè¿   ƒÄ‰Ã…Àtâ1Ò‰UÜRjWSèsåÿÿƒÄ‹UÜ…Àu=ƒ} t"‹M‰ŞƒÁ‰Ï¹   ó¥‹M‹uà‹}ä‰1‰y‰Qƒ{ t9·S·CÁâĞë*€; t ƒÂ ƒÃ ú   u™PÿuäÿuàVèD  éFÿÿÿ¸şÿÿÿeô[^_]ÃU‰åSP‹U‹B<ÇB<    …Àtƒì‹XPè¨äÿÿƒÄ‰Øëé‹]üÉÃU‰åWVSƒì‹]‹u‹}‹C<…Àt9xu90uƒÀé„   ‹@ëæƒìh  è0åÿÿƒÄ‰Â…Àu ƒìSè„ÿÿÿÇ$  èåÿÿ‰ÂƒÄ1À…ÒtIƒìJ‰Uà‰MäWVh   QÿsÿƒÄ ‹Mä=   ‹UàtƒìRèäÿÿƒÄ1Àë‹C<‰2‰B‰z‰S<‰Èeô[^_]ÃU‰åWVS‹M‹]…Éu‹K…Éu‹C$‹S(ë*ƒÈÿƒù‰Â~ 9K~Aş‹K™¥ÂÓàöÁ t‰Â1ÀC,S0[^_]ÃU‰åWVSƒì‹E‹U‰Eä‹E‹Mä‹Y0‹I,9Ór>w9Áv8‹}ä;W(w‚¤  ;G$‚›  ƒÀƒÒ 9Ó‡’  r9Á‡ˆ  1À1Òé  ‰Æ‰×)Îß‰uØ‹uä‹]Ø÷Ó‹v‰}ÜNÿ…ÙtƒÀƒÒ éT  ‹Eä‹UÜ‹H‹EØ­ĞÓêöÁ t‰ĞX‹Eä;X(  ‹@ƒø„˜   rƒø„À   é  ‰ß‹MäÑÿVß1Ò‰øÁè	AQ RPQèşÿÿƒÄ…À„â   ‰úGâÿ  ‹uäŠQˆEØ‰øÁè	1ÒFV RPVèÜıÿÿƒÄ…À„¯   çÿ  ¶MØ¶8Áâ	Ê‰Ğ%ÿ  €ãt‰ĞÁø=÷  ëiÛ‹uä‰ØRÁè	1ÒFV RPVè‹ıÿÿƒÄ…Àtbãÿ  ·=÷ÿ  ë6Áã‹uäP‰ØÁè	1ÒFV RPVèWıÿÿƒÄ…Àt.ãÿ  ‹%ÿÿÿ=÷ÿÿ’şÿÿ‰E‹Eä‰Eeô[^_]éØıÿÿƒÈÿ‰Âeô[^_]Ãƒì<‰\$,‹\$D‹T$L‰t$0‹L$@‰|$4‹t$H…Û‰l$8‰Ğˆã   ‰L$1ÿ‰\$…À‰ñ‰Óˆµ   ‹D$‰Í‹T$‰Æ‰D$‰Ğ‰T$‰Ú‰Ë…Ò‹L$u9Å‰Âve‰ğ1Û÷õ‰Áëv ‹D$9Âv01Û1É…ÿ‰È‰Út÷ØƒÒ ÷Ú‹\$,‹t$0‹|$4‹l$8ƒÄ<Ã‰ö¼'    ½Úƒóux9Âr1É;l$wÀ¹   ë¹t& …íu¸   1Ò÷õ‰Ã‹t$1Ò‰ğ÷ó‰Æ‰È÷ó‰ó‰Áëv ÷Ù÷×ƒÓ ÷Ûé=ÿÿÿv ¼'    ÷Ù¿ÿÿÿÿƒÓ ÷Û‰L$‰\$éÿÿÿ´&    ¸    ˆÙ)Ø‰îÓâˆÁÓî‰ñ	Ñ‹T$‰L$ˆÙÓåˆÁ‰l$‰ÖÓîˆÙ‰õ‰Ö‹T$ÓæˆÁÓê	Ö‰ê‰ğ÷t$‰Õ‰Æ÷d$9Õ‰T$r‹T$ˆÙÓâ9Âs;l$t	‰ñ1ÛéäşÿÿNÿ1ÛéÚşÿÿfffUWVSè÷çÿÿÃ×&  ƒì,‹l$@‹|$Dèqßÿÿƒ ÿÿÿ“ ÿÿÿ)ÂÁú‰T$t'1ö´&    ‹D$H‰|$‰,$‰D$ÿ”³ ÿÿÿF;t$uãƒÄ,[^_]Ãt& ¼'    ÃfffffffSƒì‹D$$èsçÿÿÃS&  Ç$   ‰D$‹D$ ‰D$èÕßÿÿƒÄ[Ã¡ Ïƒøÿt%U‰åS» Ïƒìv ¼'    ƒëÿĞ‹ƒøÿuôX[]ÃSƒìèçÿÿÃ÷%  èŒçÿÿƒÄ[Ã            %s: %s: %s
 short read short write /tmp At least one specified option not yet implemented for this installer.
 TMPDIR %s: not a block device or regular file (use -f to override)
 %s//syslinux-mtools-XXXXXX w MTOOLS_SKIP_CHECK=1
MTOOLS_FAT_COMPATIBILITY=1
drive s:
  file="/proc/%lu/fd/%d"
  offset=%llu
 MTOOLSRC mattrib -h -r -s s:/ldlinux.sys 2>/dev/null mcopy -D o -D O -o - s:/ldlinux.sys failed to create ldlinux.sys 's:/ ldlinux.sys' mattrib -h -r -s %s 2>/dev/null mmove -D o -D O s:/ldlinux.sys %s %s: warning: unable to move ldlinux.sys
 mattrib +r +h +s s:/ldlinux.sys mattrib +r +h +s %s %s: warning: failed to set system bit on ldlinux.sys
 LDLINUX SYS invalid media signature (not an FAT/NTFS volume?) unsupported sectors size impossible sector size impossible cluster size on an FAT volume missing FAT32 signature impossibly large number of clusters on an FAT volume less than 65525 clusters but claims FAT32 less than 4084 clusters but claims FAT16 more than 4084 clusters but claims FAT12 zero FAT sectors (FAT12/16) zero FAT sectors negative number of data sectors on an FAT volume unknown OEM name but claims NTFS MSWIN4.0 MSWIN4.1 FAT12    FAT16    FAT32    FAT      NTFS     Insufficient extent space, build error!
 Subdirectory path too long... aborting install!
 Subvol name too long... aborting install!
 Usage: %s [options] device
  --offset     -t  Offset of the file system on the device 
  --directory  -d  Directory for installation target
 Usage: %s [options] directory
  --device         Force use of a specific block device (experts only)
 -o   --install    -i  Install over the current bootsector
  --update     -U  Update a previous installation
  --zip        -z  Force zipdrive geometry (-H 64 -S 32)
  --sectors=#  -S  Force the number of sectors per track
  --heads=#    -H  Force number of heads
  --stupid     -s  Slow, safe and stupid mode
  --raid       -r  Fall back to the next device on boot failure
  --once=...   %s  Execute a command once upon boot
  --clear-once -O  Clear the boot-once command
  --reset-adv      Reset auxilliary data
   --menu-save= -M  Set the label to select as default on the next boot
 Usage: %s [options] <drive>: [bootsecfile]
  --directory  -d  Directory for installation target
   --mbr        -m  Install an MBR
  --active     -a  Mark partition as active
   --force      -f  Ignore precautions
 %s: invalid number of sectors: %u (must be 1-63)
 %s: invalid number of heads: %u (must be 1-256)
 %s: -o will change meaning in a future version, use -t or --offset
 %s 4.07  Copyright 1994-2013 H. Peter Anvin et al
 %s: Unknown option: -%c
 %s: not enough space for boot-once command
 %s: not enough space for menu-save label
 force install directory offset update zipdrive stupid heads raid-mode version help clear-once reset-adv menu-save mbr active device        t:fid:UuzsS:H:rvho:OM:ma        µ´        f   »´        i   Ã´       d   Í´       t   Ô´        U   Û´        z   :®       S   ä´        s   ë´       H   ñ´        r   û´        v   µ        h   µ          µ        O   µ           µ       M   'µ        m   +µ        a   2µ                          cñğQ   cñğQ   ;è      0Òÿÿ  €Ôÿÿä  zÛÿÿ(  ¥ÛÿÿD  àÛÿÿ`  _ÜÿÿŒ  “Üÿÿ¸  İÿÿ(  qİÿÿP  “àÿÿ€  ‘ãÿÿ°  ÂäÿÿÌ  8èÿÿø  ëèÿÿ   /éÿÿH  8êÿÿt  Xêÿÿœ  ÿêÿÿÄ  ¨ìÿÿô  Çìÿÿ  ¦íÿÿD  Ôíÿÿh  Šîÿÿ”  ØîÿÿÀ  Àğÿÿü  pòÿÿ(  àòÿÿd  ğòÿÿx         zR |ˆ         $Ñÿÿ@   FJtx ?;*2$"   @   JÚÿÿ+    A…B      \   YÚÿÿ;    A…B   (   x   xÚÿÿ    A…BF‡†ƒrÃAÆAÇAÅ(   ¤   ËÚÿÿ4    A…BC‡†ƒcÃDÆAÇAÅ (   Ğ   ÓÚÿÿ    A…BF‡†ƒrÃAÆAÇAÅ@   ü   ”ÒÿÿË   D Gu Fupu|uxut°Á CÃAÆAÇAÅC $   @  âÚÿÿ_    A…BB‡†WÆAÇAÅ,   h  Ûÿÿ"   A…BF‡†ƒÃAÆAÇAÅ   ,   ˜  Şÿÿş   A…BF‡†ƒñÃAÆAÇAÅ      È  Ùàÿÿ1   A…BBƒ(   ä  îáÿÿv   A…BB†ƒnÃAÆAÅ   $     8åÿÿ³    A…BI‡ƒ¤ÃAÇAÅ$   8  ÃåÿÿD    A…GB‡†wÆAÇAÅ (   `  ßåÿÿ	   A…BI‡†ƒùÃAÆAÇAÅ$   Œ  ¼æÿÿ     A…DB‡ƒRÃAÇAÅ $   ´  ´æÿÿ§    A…BB‡†ŸÆAÇAÅ,   Ü  3çÿÿ©   A…BF‡†ƒœÃAÆAÇAÅ         ¬èÿÿ    A…BDƒSÅÃ  (   0  §èÿÿß    A…BF‡†ƒÒÃAÆAÇAÅ    \  Zéÿÿ.    A…BBƒhÅÃ  (   €  déÿÿ¶    A…BF‡†ƒ©ÃAÆAÇAÅ(   ¬  îéÿÿN    A…BC‡†ƒDÃAÆAÇAÅ8   Ø  êÿÿç   A…BF‡†ƒÉ
ÃAÆAÇAÅEIÃAÆAÇAÅ (     ¼ëÿÿª   C@DƒT†‡J…
ÅÇÆÃJ  8   @  @íÿÿe    A…A‡A†AƒN@NAÃAÆAÇAÅ   |  tíÿÿ            píÿÿ0    AƒC jAÃ                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        ÿÿÿÿ    ÿÿÿÿ                 °ˆ    ª   ˆ   l…   Ì‚
   m                   Ğ              ˜‡   p‡   (         şÿÿo0‡ÿÿÿo   ğÿÿoÚ†                                                    4Ï        öˆ‰‰&‰6‰F‰V‰f‰v‰†‰–‰¦‰¶‰Æ‰Ö‰æ‰ö‰ŠŠ&Š6ŠFŠVŠfŠvŠ†Š–Š¦Š¶ŠÆŠÖŠæŠöŠ‹‹                                        filesystem type "????????" not supported                                                ÿÿÿÿ                                    ëXSYSLINUX                                                                               úü1ÉÑ¼v{RWVÁ±&¿x{ó¥Ù»x ´7 V Òx1À±‰?‰Gód¥Š|ˆMøPPPPÍëb‹Uª‹u¨ÁîòƒúOv1ú²s+öE´u%8M¸t f=!GPTu€}¸íu
fÿuìfÿuèëQQfÿu¼ëQQfÿ6|´èé r äuÁêB‰|ƒá?‰|û»ªU´AèË rûUªu
öÁtÆF} f¸ï¾­ŞfºÎúíş» €è f>€¡óBoutéøf`{fd{¹ ë+fRfPSjj‰æf`´Bèw fadrÃf`1Àèh faâÚÆF}+f`f·6|f·>|f÷ö1É‡Êf÷÷f=ÿ  wÀäAáˆÅˆÖ¸è/ farÃâÉ1öÖ¼h{Şfx ¾Ú}¬ Àt	´» Íëò1ÀÍÍôëıŠt{ÍÃBoot error
                  ş²>7Uª
SYSLINUX 4.07  
    ş²>¡óBo             ¦0ê5€  û¾ €èˆ¾ €‹|ÁéfºıMÁf­fÂâùf‰(€f·Ş¾æ€>F} u¾êÆõ€ ‰6 0èOSf6î‹ €Iã*f‹f‹Tf·l)éfSfÁëÃ1ÛèK f[¯.|fëƒÆ
ëÔ^f·|Áèf‹$€f)Áf¡(€fƒÆuŒÚÂ ÚfIuìÙf!À„‘¾×èß éÁüf`f`{fd{ëQUè¿ f·ı¹ fRfPSWj‰æf`´Bè»üfadr]føfƒÒ )ı¯>|û!íuÃfaÃf`1Àè”üfaâÀÆõ€Q]fRfPUSf·6|f·>|f÷ö1É‡Êf÷÷f=ÿ  ‡<üèI )Î9õv‰õÀäAáˆÅˆÖ•´½ f`èDüfarf¶È¯|[Ã]fXfZfÈ)ÍufaÃMuÙ•Ñ.,€uÛéğû;.,€v‹.,€Ãf`¬ Àt	´» ÍëòfaÃ Load error -  CHS EDD                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   1ÀÀ¾¦³èJø¾Ó·èDøf1À¾|¿8¹ ­Nf«0äf«âöè—fh°¬  èf=Üu  …ıóèÌ!èè0	èì´Í¢¤8¨u3Ífº_4 fÁê
9Ğs#¾¼²±
Röñ d]˜öñD[Xöñ d$˜öñD"èÑ÷é³óf`f¸ğh ¶t{f‹`{f‹d{‹6|‹>|f·.,€fhx è’fa¿·}°éª¸ï˜)ø«fhR è{tè~è¦²èHã¿ Áó¤1Àª1ÉèarèíéĞö¤8[uƒ>ØR „ƒ>äR‡„ƒ>ÚR …{¾ä³è_!Æ¥8 ¿ Á´Ít´Íëôf¡ÌRf£œ8f¡ÈRf£˜8èÕfƒ&˜8  À„ã <tA< rwÿ Átáö¥8…¢ ÿÿÈsÒªèÒ ëÌ<„><	t8<t-<t<„Ü <t<u¬ÿ Át¦O¾ë³èÚ ëèÈ édÿèé^ÿÆ¥8ëëƒ>ÜR uäW‰ùé Áè§ f‹6$¶f;68<v2Qf¿Ñ  fhW èh)ÏYVƒù tWQ¾ Áó&¦Y_u
° èG ‰şèy ^ëÇèf ër0äˆ&¥8<0rt <9v<ar<c‡{ÿ,Wë$°
ë ,1ë†Ä<Dw,;‚cÿë<…‚[ÿ<†‡Uÿ,{WÁà<=—€= t2èFt-è èTëW¾—³è ‹6 0è ¾Ó·èÿ¾ä³èù_WÆ ¾ Áèî_é¯şƒ>äR u¾²³èİƒ>ÚR …—ñécş¾É¿ Á¹ óf¥ëè³ÿ ÁtĞ0Àª¾ Á¿<IVfh‘ èw^¬< wû Àt¬< v÷N‰6¢8¡àR!Àuˆf‹6$¶f;68<v_f¿Ñ  fhW è?)ÏV¾ Á¬< v®tø^ëÙ€= uø^h ¿ ø¾Ó‹Óó¤&ˆ‰>ÖR¿<IW¾Ò¹ ó¤_1Û Ó¢¦8<ÿ¡Ò„së)ƒ>ŞR tiVW¿ Ç¾Û¿ ø‹ĞRó¤&ˆ‰>ÖR_^ˆ¦8Æ<J ¿<I€= v:0À¹û ò®uO‰> 8»È¹S¿<Ifh: è›[…­ f‹‹6 8f‰ÆD ƒÃûÜ¹v×‹ÔR!Éu¾´è¡¾<Iè›¾z¶éa¾ë¿ ÁVWQQWó¦_[tİ÷Ûÿ¿şÈÆE 1ıó¤üY_^ó¤é²ş¾7´é/èÖèıÿ6¬·è`u+èX;¬·tífÿ˜8tfÿœ8ußYè´¾ã¿ Á‹ÒRó¤éfşYèeèÃ‹6”8f¡8f`1À£Ì8¢Ï8f¡8<f£¨8faWP¿<I0À¹ ò®uOf‹MüX_¶>¦8ÿÿ¥\´fÉ    fù.com„cfù.cbt„Xfù.c32„•fù.bss„/	fù.bin„ 	fÁéfù.bs „	fÁéù.0„	ë Vèßfh4 èM^è­
èÁéÊû¾ï³èméüûVh è
¹ €1Û^fh è#ù ‚âş&>şUª…×şV‹>ÖR¾Ø´¹ ó¤¾<IèÄ&ÆEÿ è‹6¢8èµ¿ ø&ŠG Àt~< vôO¾ã´¶ãWFó¦u&‹Eÿ<=t€ü wXÿ&ŠG< wøëÏ_ÎFFëÔ&‹Eÿ»ÿÿ==ntK==etK==at»==ctèÏr&‰úÃèÄrf‰¨8ÃÆÏ8 Ã‰ø&€= w1À£Ì8Ãï ø‰>Ä8fÇ¬8ÿÿÿ7&f>HdrS…&¡£Ê8= ‚=r&Ç$ôõ&€€=r	&f¡,f£¬8&Æ1f1À&f£& 
Ï8&¢¢Î8¾p´è™¾<Iè“&¶ñ!Àu°@£È8è²f·6È8Áæ	f¹ €  f)ñfÆ   f¿   èÃ^!öt»Œ˜fƒÈÿº èÊf‰>¸8¸ À¾z´è<W‹>È8Áç	f1À¹ ø)ùÁéóf«_f¡¬8f;¨8wf£¨8f1À9Ì8tèJèA¾|´è¸ Àà&ƒ>ü u&Çü ‹Ê8öÎ8túrdfÇ( ø Çt‘ô÷dÇ$ôõëT¾ ø¿ ˜dÇ  ?£d‰>" Çt‘ô—¸ÿ úrdÇ$ô•vdfÇ( ˜	 ¸ÿ‹Ä89Áv‰Áód¤ª‰>Æ8ú r&‰>¿ 1ÉŒÃãfº   öÎ8u"f¸  	 f«f¸   f«f·Æ8f«Afº   » f‰Ğf«f¸   f«f÷Øf¸8f«Aƒ>Ì8 tdf¡f«f¡¼8f«df¡f«Afhn‘  QöÏ8 „“é“úŒØĞ¼ô÷ÀàèƒÀ Pj Ë1À9Ì8t¾…´é!¢Î8£Ê8é!ş¸ Ø.f‰>¼8.f‰>À8.‹6Ì8‰ó¬<,t< vëõPVÆDÿ ‰ŞW¿<Kfh‘ èà_è/ ^XˆDÿ<,tÑ.f‹À8.f+¼8f‰.f¡¨8% ğf)Ğ% ğf£ÃŒÈØÀfW¿<Kfh: è—f_t%V¾n´è0 ¾<Kè* ¾y´è$ ^º »Œ˜è˜f‰À8Ã¾·´è˜¾<Kè’¾z¶éXöÏ8 „ƒÃfho èI¾ÑµèséøVèÅèh ¹ Á1ÿ¹@ f1Àóf«&Ç  Í ÍÁà&£ ¾ ø¹} ¿ ° ª&¬ Àtªâ÷°ª‰ø,‚&¢€ ^» ¹ ÿfh èéfùşş  wŒÀØĞ1äj ê  ¿P9¹  Qf¸j ëf«şÄâúOÆEÿé¸f“)ø«Y¾€ »µ¿Ğ8f¥f·CCf‰DüâòÃ`¾Ğ8¿€ ¹  óf¥aÃû ¨f`üŒÍİÅ‰åèd¹
 ¾Dµ¬:F­àùøÿĞ‰å’F,fa©¡Ï‹Ffÿv(j!Zf_¹°µhs“ë$’è‚° è3’è†° è*f‰øèˆèKéçöúhxŠ1É[1öŞÆf²& °fÇ·  ûüfhg èşèéã¾<Iè#‰Îèÿãèèe èèÙøÃŠFèÑøÃŠFèÊøÃèJ øÃF&‹v&¬<$tè³ëõøÃ€>­µ uèæ”ÀşÈˆFøÃfÇF  SYfÇF  SLfÇF  INfÇF  UXÃ€>­µ uèç Àuˆ&¬µş­µˆFÃ ¬µş­µëóûüè9ÏûüèLÏû ¨f`üŒÍİÅ‰åè+ƒø%r1À“Ûÿ—bµéÆşùÃÇF% ÇFÇF1 ŒNŒ^$ÇF™³ÇF Ô·øÃ^$‹vè0øÃ^$‹v¿ Áè¹h/ŒéËşhü‹éÅşèUøÃF$‹vfhğ èÒf‰F‰N‰vÃF$‹^‹v‹Nfh° è²s1ö‰vf‰NÃ‹vfho èšøÃÆF1 ¾RˆF t{ˆFŒN"ÇFp{ŒN ÇF `{ŒN$ÇFx{øÃ¡€¶‰F¡‚¶‰F¡„¶àŠ&†¶ÀìöÄRu€Ì€‰FøÃf¡h{f£x èdøÃŒN$ÇFÔ9øÃŒN$ÇF  ÇF  øÃèşøÃ‹Fé˜ŒN$ÇF¯µÇF øÃŠF<‡‚ ¢¦8^$‹v¿Ñèµ^&‹v¿<Ifh‘ èÚfh: èĞ„ ş‰6”8f£8è ıº Â¾Ñ¿ øèy&ÇEÿ  ‰>ÖRÇ¢8®µé­÷‹Fƒøw¢t·‹N‹V‰LL‰NL¨uèløÃùÃ b· Àt `·ÇF$ 0ÇF  ˆFÃfƒ~  uf‹Ff‹VF$‹^‹nèyêøÃùÃŒ^$ÇF¼ÇFôÃƒ~ uÇF ÇF ŒN$ÇF<<ÃùÃŒN$ÇF¼°øÃÇF•ÃèÀşf‹~ f‹vf‹NéVfPè{ ¸ à¾ ø¿ Á‹ÖRA)ñód¤¾<I¿ Àè›è üf¿   fX^1Ò»”˜èâf¾   f¿   f¹   è´f> ¸şLÍu€>!uf¡8<1Àf£·f»   é«¾<Iè°¾ìµèªé9ó¸ À‹>ÖRè ‹6¢8è*O‰>ÖR&Æ ÃÃj ëj3f¿   f‰>f¸  
 1Ò»”˜èZfï   f‰>fÿ „	 ‡ï f¸ |  f£ f1ÉYf¾|  f¿  èfPf1Òf1öf¡h{f£x Št{¾x{¿îW¹ 1Àó¥^1Ûf¡ ff·fÁá
f)Áf£fƒÿf‰jè'èÚ 1ÀØÀ¿x{W¹ ó«_&f‰U&f‰u&‰]¡p{‹r{&‰E&‰]XWf»   køWßf SPf«1Àf«f«_¾º¹	 óf¥f1ÉYƒÁ	SSfSú	Sf‹&Sf¿   f‰şéNè3¾0¶ë&V¾z´èÇù^èïèVt`è†<t<taÃ¾l¶»xŠë»Ñ˜1ÀØÀf²& °fÇ·  ûüèÿã‹ÔR!É…vôéšñf`1À1ÒÍè3úè¡faé!¾¸èï€>Ë}t
è%è$ÍëşèÍëşfh: è	tS‹x¶ƒëûä:r‰x¶‰71À‰GˆG@[Ãfho èt	1À[ÃSVW‹>x¶¶]!Ûu¾ Æƒmr‹u&ŠF‰uø_^[ÃKŠAˆ]ëñf`‰ûëä:Áã‰]‹5!ö‰ut¹ fh è	‰M‰5ãfaë³fa0Àùë½Pè“ÿrªâøXÃSV‹x¶‹7fho èëƒÃ‰x¶^[ÃWS‹>x¶¶]ˆACˆ][_ÃèZÿr<t	<
t	< vïÃ8ÀùÃÿÃ¿Ô:ÿã:sWè7ÿ_rª<-sîè»ÿÆ ¾Ô:fPfQUf1Àf‰Ãf‰Ù1í¬<-uƒõëö<0rSt<9wM±
ë¬<0r% <xt<7w:±ë°0±è@ r8Ès
f¯ÙfÃ¬ëíN¬ <kt"<mt<gtN!ítf÷Ûø]fYfXÃùë÷fÁã
fÁã
fÁã
ëá<0r<9w,0Ã <ar<fw,WÃùÃè*ÿ²t+r&èÿRWèyş_Zr< v1Òªëî<
t<t Òuâ° Bëìøëùœ Òu° ªÃ‡÷èÿ‡÷Ã¹ ¿ è¡şrè3şs¾ ¿<<¹@ óf¥è–şÃÆê;Æë;è`èşr<t¶t·€áAÿä;ëèémş<tg<tZ<
tf<„• <tM<„<„Ï s<ƒ+è/„ë;t/öÄRt(Šê;Š>b´	¹ Í æ;@:è;w%¢æ;Š>b‹æ;´ÍÃ¸1ÛÍÃÇä;œÃ¾z¶è„ë;täÆæ;  ç;@:é;w¢ç;ëÄ1É‹è;ˆ6ç;Š>ÆR¸Íë¯¾}¶èä „ë;t¯1É‰æ;‹è;Š>ê;¸ ÍëèŠşr/Àà„ë;t¢ê;Çä;-œÃèrşr„ë;tê;ëÇä;Uœ¿ŒLë!Æê;Çä;M›Ã<
t< v‹>ŠLÿMsˆG‰>ŠLÃè¶
ë‹6ŠLÆ ¾ŒL¿Mfh‘ è,è‚üt¿è+	`Š>b´Í‰æ;aë¬$¢ë;ë¥öë;t-fœf`‹€¶!ÛtPŠ&…¶Wì¨ tøBì à8àuğ‡ÓXîæ€æ€fafÃöë;t
¬ ÀtèÃÿëöÃf`´Íu*‹€¶!Òt"¡4<ú;2<uƒÂì¨tBŠ&†¶ì à8à•ÀşÈûfaÃûèm´ÍuD‹€¶!Ûtï¡4<ú;2<uWì¨tÜBŠ&†¶ì à8àuĞ0ä‰Úìûë(û“¸ 2ØŠCãÿ‰4<ë´Í<àu0À Àt»<<×éş
.fÿ6ğ;ëx.fÿ6ô;ëp.fÿ6ø;ëh.fÿ6ü;ë`.fÿ6 <ëX.fÿ6<ëP.fÿ6<ëH.fÿ6<ë@.fÿ6<ë8.fÿ6<ë0.fÿ6<ë(.fÿ6<ë .fÿ6 <ë.fÿ6$<ë.fÿ6(<ë.fÿ6,<ë œPR.‹€¶ƒÂì¨uZXËW¸ 2À.‹>2<.‹€¶ìª.Š&†¶ƒÂìP à8àuçÿ.;>4<t.‰>2<X¨uÔ_ëÀf`èµ ¾  ¿ğ;¹ óf¥¾À¹ óf¥¿  ¹ f¸ˆ  f«ƒÀâù¿À¹ f«ƒÀâù‹€¶‰0<W°îæ€æ€W°îæ€æ€ä¡ˆÄä!£6<æ€æ€1Àæ!æ¡faÃf`1ÀØÀ‹0<!Ût7W°îæ€æ€W1Àîæ€æ€¡6<æ!ˆàæ¡¾ğ;¿  ¹ óf¥¿À¹ óf¥1À£0<faÃè¯ÿf`¸ 2Àf1À.f£2<¹ 1ÿóf«faÃèFf1À¾ä¹¿ÄR¹
 óf¥¿<<0ÀşÅªşÀâûf¡$¶f£8<Ã;äR‚L£äR¿ÉèSûÆEÿ Ã¿ãèHûï	ã‰>ÒRÃ¿ëè9ûïë‰>ÔRÃ€>èR w¿Ûè#ûïÛ‰>ĞRÃ¿ÓèûïÓƒÿu	€>Ó-u1ÿ‰>ÓÃè@ú€>èR t	‰ÒÆÓÿÃ€>èR t¢ÓèÒ¿Òfh‘ èÊÃPèú^rf¸«*Òf÷ãfÓf‰ÃPèúù^r‰ÃPè ¿<Jfh‘ è˜fh: èuXÃPèƒ¿<Jfh‘ è{èÑøuXÃÿâRÃè¸ù‚Ô Sf1Àf£„¶èùr1èwùè¡ùr)fSèùrèhùè’ùs1Û€çÀçˆ>†¶ˆßãğ‰„¶f[ëf»€%  _fƒûK‚‡ f¸ Â f™f÷ó£‚¶PƒÿwÑç‹½ ‰>€¶èşU°ƒîæ€æ€X‰úîæ€æ€Bˆàîæ€æ€°BBîæ€æ€ì<u>J°îæ€æ€ì<Às1Àîæ€æ€BB „¶îæ€æ€¨tèOı€>¬¶ tÆ¬¶ ¾—³èÊû¾Ó·èÄûÃÇ€¶  ÃPè… _fh‘ èÃè› Æ<K ¿Ñ¹1Àó«èe ¿Ñ¹ÿ ¬< vªâøÆèR¾Ñ¿Òfh‘ èG¾Û¿Ó‹ĞR‰Óó¤Ãè/ è`
éP
è è# r f­f%ßßßßf=ENDTuëf­f%ßßß f=EXT uÛÃ¿ WèùÆ ^Ã¿Ñ1À¹
óªèn sûèê÷ÿâRuò€>èR tQ¿Ó>Ó€><K t¾ú´¹ ó¤¾<Kè„&ÆEÿ ‰ø-Ó£Ó¹ )Á1Àóªf¾Ñ  f‹>8<f¹
  fh€ è f‰>8<Ã¾ˆ¶è±	Ãès è­÷tlrù<#tò¿ ª f¶ØèõörW< vª fÁÃ0Ãëìèp÷1Àªè~÷t=r%èc÷¾H¸¹0 f­f9Ãt&f­âõ¾­¶è]	¾ èW	èG	ë¢¾Õ¶èL	¾ èF	è6	ë”­ÿøÃùÃ<
tè“ös÷Ãfœf` ¨‰åŒÈf»õ¬  Øë©¡fafÂ úf1ÀØŒĞ‰&8£
8f·ìfÁàfÅüèd Æm°‰`°· À"Àê­  ¸ ÀØĞàè°1Ò À$ş"Àê6£  .²&8f·äÚÂâêÿãœ.gÿµ    f»A­  é~ÿf`.Æ@Lÿès un.ÿ&·.Ç·o£¸$œÍè[ uV²è… uO.Ç·‚£°Ñædès °ßæ`èl °ÿædèe Q1Éè0 u*âùY.Ç·°£ä’$şæ’Q1Éè uâùY.ş@Lu¾·éÛôYfaÃQfP¹ÿÿÁ.f¡<L¹  ëfAê
C.f£<Læ€æ€&f;LLáéfXYÃ0ÒèÌÿt Òuæ€æ€äd¨tæ€æ€ä`ëå¨uáæ€æ€Ãf1ÿ»0¿0Sf¸j ëz¹ Q¹  ‰?ÇG  fÇG   ƒÃf«f  üâäƒÇÆEûéfº4­  f)úf‰Uüf   €YâÃÃ‰àƒÀ,£DL©¡fafË.‹&DLfœf` ¨f»  é0şfË.‹&DLf‰Æf»6 éşgãfh¯  èëıfÏfÎÃ»Æ¯éşfUf‹.¨8fhx èÎıf]pÃ¾1·é¿óéÄô¿ ¹ è°ôrò¡ =6uê <wã1ÛŠ>€ÿrØ€ÿ wÓ¿ ‰Ùè‡ôrÉèô¾ ˆ>`·¹ 0Á¿  ‰ÙÁéóf¥Æb·öt·ütèÓöb·tH½ 0Å½  Š>`·0Ûöt·t 1Éˆù¡NLöñˆÂH¢é;¸!Í¡LLÁèH¢è;Ã¹ 1Ò¸Í0Û¸Í` „ Àu°¢é;´ÍşÌˆ&è;aÃèhèu¹8 ¿PLèxóªâúr|f>PL=óuqºXL¸1Û¹ Í¡VL‹`·ĞHöò1Ò:é;r é;şÈˆÆ´1ÛÍ‹VLÇˆL  Q¿NWW¹  f1Àóf«_‹TLè% ^¿`QW½€èl ^¿  Ç‹>ˆLè~ ƒˆLPYâÇéhó1Òè4 8ĞtªˆÂIuóÃ1Ûè$ ÃtQ‰ÙˆĞóªY)Ùwİëèè ˆÃè
 ÀàÃƒÃëàöÆt€æˆğÃè­òˆÆÀî€Î$Ã1ÉAVU» ¬ÒèĞÒKuøˆGƒíwí]^€ùvãÃºÄ°îBHîW¹ óf¥_À<vñÃ t·<t@¨t
¸O» Íë¸ 1ÛÍ€ë€ûw%¸ Íºc·¸ÍÆt·fÇLL€àè+şÆÆR 1ÀÃf`ŒÈØÀ t· Àt¨t¸O» Í¸ ÍÆt· ÆÆRèôıfaÃf`°_ëf`° €>t·u
´	» ¹ ÍfaÃfœf`fÇ¸R  ğÿfÇ´R   ¿ R1À¹
 ó«f1Ûëf!Ût}f¸ è  fºPAMSf1É±¿ RÍsf!Ûu`ëuf=PAMSumƒùrhfƒ>¤R wÇf¡ Rfƒ>°Rtf=   r³f;¸Rs¬f£¸Rë¦f;´RwŸf¨Rrfƒ>¬R tfƒÈÿf;´Rv…f£´Réoÿf¡´Rf;¸Rvf¡¸Rf=   w8¸èÍr= <wr‰ØfÁàf   ë´ˆÍ= 8v¸ 8f%ÿÿ  fÁà
f   f£$¶fafÃP¬ª ÀuúXÃfP.f¡¬·.f£x·fXûÃfPŒÈØÀœXöÄu%VQ¾~·è7‰æƒÆ
¹ 6­èJIt° èëëñèY^ûf¡¬·f+x·fƒør	fhO èÒùfXÃ€>¨·ÿ…†ƒ>"€r&f¡`{f‹d{f˜·fœ·f ·f¤· t{¢¨·éY€>¨·ÿt¾ ¼è9 t,¾ ¾è1 t%¿ ¼f¸¥/-Zf«f¸g£f«f1À¹} óf«f¸d¿(İf«Ã¿ ¼¹€ óf¥ÃVf­f=¥/-Zuf1Ò¹~ f­fÂâùfúg£uf­f=d¿(İ^ÃP¾¼1À¬8Ğt Àt¬Æşü½rîë
¬‰Áğ=ü½v1ÉXÃPVW íuYQ¾¼1À¬8Ğt Àt#¬Æşü½rîë¬|şWÆ¹ü½)ñró¤ˆ%^ë×^ëNY‰÷ãÎşú½s‰ŞˆĞªˆÈªód¤¹ü½)ù1Àóªø_^XÃùëùf`¾¼¹} f1Òf­fÂâùf¸g£f)Ğ|¾ ¼f‰D¹€ óf¥faÃfPf¡˜·fœ·tf¡ ·f¤·t€>¨·ÿtè°ÿ´è øfXÃùfXÃP´è èşXÃˆ&¼Rf`»ªU´AŠ¨·Í¾ûªrûUªuöÁt¾Ëªf¡˜·f‹œ·» ¼è f¡ ·f‹¤·» ¾è faÃVÿæ¹ fRfPSjj‰æf`Š¨·¸ @
&¼RÍfadr^ÃâÖù^ÃfRfPUf!ÒusŠ¨· Òy´Ír äuÁêBf·úƒá?f·ñë:t{uJf·6|f·>|f1Òf÷ö1É‡Êf÷÷f=ÿ  w)ÀäAáˆÅˆÖŠ¨·°Š&¼R½ f`Ífar]fXfZ^ÃMuîùëóf¡p f£««fÇp –«  Ãf¡««f£p Ã.fÿ¬·.´·èì.fƒ°·6ê    èşğfœ.öt·tèiû.öÄRtf`´³.Š>bÍfafÃP°èĞÿ°
èËÿXÃfœf`¬ Àtè½ÿëöfafÃfœf`fÁÀ¹ ëfœf`fÁÀ¹ ëfœf`¹ fÁÀfP$<
s0ë7è€ÿfXâçfafÃèíú1ÒÚÂf²& °fÇ·  ûüâê¾¶·èŠÿèìƒøÿt9ˆÂ0öR1ÀÍ¸¹ » ½ `ÍasMu÷é$ÑZú¾ ¿ |¹ óf¥Ñ¼ |ê |  ÍéÑ              j Th   ÿ5“³  h0º  è€   ƒÄE$1À¿ v ¹ù  ó«¿8  ¹­  ó«¿0º  ¹‹  ó«ÃöE)tûÿU.f»Î¢ë 1Ààè Ğ°(ÀØĞ° Ø‹%·  ‰èÿãúü‰%·  ê£   `¶t$ »J£  ëäaƒÄÏfUWVSQRƒìü‹t$(‹|$0½   1À1Û¬<v,ë"ÿ   ŠFÛtôDëfŠF<sAÀtæƒÀ‰Á1èÁé!è‹ƒÆ‰ƒÇIuó)Æ)ÇŠF<sÁèŠ—ÿ÷ÿÿ˜F)Â‹
‰ïën<@r4‰ÁÁèWÿƒàŠÁéØF)ÂƒÁ9ès5ëmÿ   ŠFÛtôL$1Àë< rtƒàtçHf‹WÿÁèƒÆ)Â9èr:DıÁé‹ƒÂ‰ƒÇIuó‰Ç1ÛŠFş!è„?ÿÿÿ‹Æ‰ÇŠFéwÿÿÿ´&    ‡Ö)éó¤‰ÖëÔÁÿ   ŠFÛtóLëv <r,‰ÁƒàÁàƒátßƒÁf‹ƒÆ— ÀÿÿÁèt+)Âézÿÿÿt& ÁèŠWÿ˜F)ÂŠˆŠZˆ_ƒÇénÿÿÿƒù•À‹T$(T$,9Öw&r+|$0‹T$4‰:÷ØƒÄZY[^_]Ã¸   ëã¸   ëÜ¸   ëÕ         SRPƒşÿt~9şr.‰úÑês¤IˆÈƒùrÑêsf¥ƒéˆÈÁéó¥¨tf¥¨t¤XZ[ÃDÿ9ÇwÊı|ÿ‰Æ‰úÑêr¤INOˆÈƒùr"Ñêrf¥ƒéƒîƒïˆÈÁéó¥ƒÆƒÇ¨tf¥FG¨t¤üë°1À‰úÑêsªIˆËƒùrÑêsf«ƒéˆËÁéó«öÃtf«öÃtªë€ú‰ûTƒâğè;ÿÿÿ¾¯  ‰×)ò¹b   ‚í¯  ó¥ÿà¢±  Â`°  ‰R‹;‹s‹KƒÃãèÿşÿÿëìZ0Q!ötÿç‰øf‰Bf‰BÁèˆBˆbˆBˆb À$şfº ÚÂâêÒê                  / `°    g € ‰  ÿÿ   ›  ÿÿ   “  ÿÿ   ›Ï ÿÿ   “Ï ÿÿ              `{    ˜7¼0 ¼1 îÀ  Ê—3                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                It appears your computer has only 000K of low ("DOS") RAM.
This version of Syslinux needs 000K to boot.  If you get this
message in error, hold down the Ctrl key whilebooting, and I
will take your word for it.
 XT  
SYSLINUX 4.07 2013-07-25 No DEFAULT or UI configuration directive found!
 boot:    Invalid image type for this media type!
 Could not find kernel image:  
Invalid or corrupt kernel image.
 |_—c—_—sv’¾–\
Loading  .. ready.
 Cannot load a ramdisk with an old kernel image.
 
Could not find ramdisk image:  BOOT_IMAGE=vga=mem=2quiet=initrd=C ‘“+“d”\9`9d9h9l9X”^”x9|9€9^“ˆ9^“9”9˜9^“ 9¤9¨9¬9°9´9¸9¼9À9Ä9È9Ì9 ‘“Ê“Ø“à“è“	í“ ”0”L‘“ÿ_“Š”Œ”­”¸”Ê”Ğ”Õ”ï”•Š”•H•o•Š”|•†•Š”Š”Š”••š• •¯•–<–T–Š”Š”s–Iª–œ–Š”Š”Š”¦–¬–   : attempted DOS system call INT  COMBOOT image too large.
 : not a COM32R image
      	       E          ?  Ñ          i Too large for a bootstrap (need LINUX instead of KERNEL?)
  aborted.
 ä;
         Out of memory parsing config file
 Unknown keyword in configuration file:  Missing parameter in configuration file. Keyword:    ÿ0  o£
A20 gate not responding!
 
Not enough memory to load specified image.
    	
           ERROR: idle with IF=0
                   ÿÿ            Booting from local disk...
  Copyright (C) 1994-2013 H. Peter Anvin et al
 
Boot failed: please change disks and press a key to continue.
    µ7   ²¡t›;   ‰¡ÿØšB + ¤™9Å  ŒŸ$^ÕÔ<K)¡íYQÌ XŸÉ   XŸ@¼	Õ%›+ ´±2 ö¤+ õ¦ŞR P¸Ğ›+ Ì´hĞ  ÓŸØ6õ ÓŸ”±0  ÓŸ†  ÓŸeÏ  ÓŸœ§N ÓŸŒ±à ÓŸR2 ÓŸG•ÆÀ ÓŸÌñ  8¡t:çØR YÀ   €¡L¨hà  G ı1ØÄR É2ãÔÈRíŸ©ĞQïÌRíŸ¹^ãÔ  nŸ‰Åh  }ŸİHàR 	 ÚR æ6:ÜR ô‰ÅÚ|· §]ÍæR ñ  <=)¡ò  <>)¡ó  <?)¡ô  <@)¡õ  <A)¡ö  <B)¡÷  <C)¡ø  <D)¡ù  <E)¡ <F)¡ğ  <F)¡ <G)¡ <H)¡ôŞğ  ¿Ÿ.cbt.bss.bs .com.c32                         ø                 "ÀêS  ¸  Ğf¼    ©¡fafê      $hi h À  ÿ5$¶  hÑ ]?s   Ñ E™Á j	ûèÊÿ f»‘“éæ¬ğÿ‹D$ë¶[ ‹…    œSUVWÿ5DL  üg·>8T 
8ƒï6gf‰X Áãß‹t$ 1É±ó¥«¸“¤  «‹Gô%×  ‰Gôf«f»€¤é‡XI6€
8‹|$$ÁàÆ!ÿu‰÷·gƒ6x_^][Ã*ş‹L*`DL)Ïƒçüƒï*8D$%D$	$®ˆL ‰ÈÁéó¥‰Áƒáó¤f»«¤éï«ğÿ‰ğ¨
[]^_Ã¡¬·  £xP ª+lƒøv ¡ì‹ …Àufƒ=|P  tëÿĞ…ÀtîÃóÃôÃUWVSƒì‹P‰TL(P‹p ÇD$j)é”P L Š	ˆL$‰4$şÿ  vÇ$b¹@ ëA;$rƒùvë5Š\$‹l$8\ tåëéƒÿvJP
1ÿŠL$ˆJÿG‰ûGˆ]|\6 NJë2ƒùawzÿi~‰ëˆZÿëPş© àÿÿf‰jşWÿx
ˆ_ÿT)ÎƒÏÿ…ö…aÿÿÿÆBÿ x‰hJ‰PƒÄ[^_]˜R‹XCëp€n €vë*‰ı÷İŠL;şˆ*Oëœ	,9‰é„Éuã¶T‰ó)ËÊë=kßw
Œy‚ësş“éàOÁá[% 
<^ÿŠNÿ1öëˆ2F9şuøòsÿŠKÿI&\
	‚‰p‰Ñ+H‰H AXšf'X; )Öë	B9Êsˆ\ÿŠ„ÛuğzÆm‰Ğ	
ÃX‰Ç‹@@6;ƒ uƒÈÿë2‰Ó‰ÎèP#ÿƒøÿtíh•pXñ‰Â‰Øè¤SÿwÕ–RZYIÀX" ‰Ç‰Í¡w ‹‹Y…ÛtU‰Ñ‰úÿÓ‰Ã]ëQ‰ĞèHGËÿ…ÀxC%ÿÿ@FpÿköÆğHIK	ö‹F	é
è`R‰ÃQK é1Ò‰øè#•_¨èT‰Øœ
·PÁâ·HÊW ÁáP@È¹_{ ébSSìn‹”‹J …Ét{ÿÑé\a è„ OYˆ—PíX&Û&ÃÏÛ‹C€x5QÔ\iu%k¼@ è˜DFÿ@…o‰B ]¬Té¹W
 ‰â
şÿH t€|ÿ/tÆ/@=ov¸x @ H›ƒÀ$DßW  1ÀÄl[Ãè×rx" HkÀÕÀVRƒzWè0N1Àq(Y ‹á=4^òº	ÇÑFç¸kÃè«  %‡'º<I¸Ô9U#Jº Ÿ@rBŠ„Àt< võ‰àè@Y œ\¸l½~$j‹x|$V1x\ ‹h÷×‹@!ÇUCf] 'ù‰Nƒëä„T•‹0‹Vc|÷ÒW é˜`Fè9DE‚x]]§l	1Éº¸ èAK\QA$A+¿x F
) ‘T  ‰<$9Çv‰$‹>‹$D$‹NÓèT$#R‰Á‰êHÿWZ‹¶ı)X	Iw#ÉjèÑOfÇCM¾Š•ƒ@ …]\MLv¾ !ïIMù@XèèNVX% kï‰{‹C(%*÷ÿÿ	ğ‰C(ƒÄ$YLw˜^1Àë%‰Öî@èy@9ğsé¯KƒÂ$NK…V­`Ãl‰ÖAXè*``CDT‰pÇ@`ÁëIs@TXèëjèäy ó@uÿKtßDA‹g‹OcR¹h1HØ[é’U  X´Y ÿP$1ÉCh—^sèMKEX¹@t3S(âÊ‰	[	€	ÿQ9ªéÕT&XF@]  pMCö2N,w‹8Y=Kå·SQÂD$P‰ğG5‰ÇYª uUƒ6P	¨3‰{ Zx“h¶h4[‹:Y
 ÇÓøAKÊ]¬Q\A¥X(†Ôş)…^ÇS‰Æ
faŸK,ç‹8©Ø* a‰‹	^øYÿ¨ƒìPàp‹$ƒ: tƒÂ‰$úpL[uêéEtÊÿƒ<$ „F`šB‹	…u|U|NÿÑS[ƒxU
Véì_Aè2^PLãW„ôø“p ÿFpİZo|Y‰İ€} /Eu	‰Ã½¸uOº/r¥TIÃ}mÆC; uëCŠ</tù„À•À¶À÷Ø!ÃzuV%|ı 9ÙZé@hŒC º¼p»èèâS–¯„'aa»¡É€u‹n…í„_ÿEI
)H
‰îéö ã‰òÿQ,W\eD€ê©Ü
ÏtNÈğüCğé©n±wJ"]DG‹Gƒø
…™dwF]8D4şR  DÌ,ƒz0 tkÿL$te=TŠ ^èàBÛ‰ÆUS±(PøÿU0…À~:F$Æ;ë/H	‰ÚèÈR‡œè`@Ï‹_ÿCQSsß‰t!Ï!õëiRBfCè;\1ÿëH
ƒøtLëê…Û…ZRG‰÷™×ÿt&A>‰|Ç@h¨‰ÇïxHÁÿiÿ«ªªªW·ÒëVèL
PHë	‰İ‰şéh	ĞƒÄ˜šp@¼lĞèeınÖy¯^ÇC$xƒK(@ë%f‰C3!@T@‰C$ƒc(¿[ÃÊğ‰ÓTîàèæû[àèš
x>
ØáˆIkÉÁÏÉ‹QqÙCšÈèaHkî‹R‹Z ‰êUàãèlÎ„ux¶ ü‘]!Ÿ#Ââ¯JkÒÂÍÒYşĞ‹IK$ViRS tüeÍÀ'»éÅúwéàH¬xŠPˆ½ŠPY 	Gl‹x!-,fAÙ

hPK‹Xbîzş4KG/1É#Ä1dtëc£Iö3)ÇLb ë/
÷u% *Qˆ	ö•Â}$U·D$PWV‹D$èOU Ás‰q¸v‹t ‰$ÿR‰ÂƒÃLb\…yM‹…Àu—ëZëşƒx NÃ6FHj„P(…Òt”ÿÒ£,x @£0^ ¡S f£¾RX¡ ‰ÀJë" )x_a¡`Dªë³h¾fÄ+C^ë™&-Ç„L™™Ç€'% |'% x'% tT n…Ç}…¤E• '% œ'% ˜'% ”U …'î y(E @„/·\eÁà
-`0 ƒàğƒÈ£dI¸~éÊL¬:!3‰òƒâÕv‹H"0‹y‰ıƒåMu(| ğ‰,$Í9èuƒæğ‹Lõƒç	ı‰i‰Q‰JLY	ë!ƒæüƒÎ‰pÇŠ:‹K	‚H	 XZe‹@A‹J‰ËƒãKu:‹X‰ŞH	 
<09×u+ƒáğñƒã	Ù‰H‹J‹Z‰Y]JW‰H$R<B[-\Uƒèé7PS!2 ‹PÑƒáQÍrƒâ4‹Së,TxÑ9òr‰@RH@	ZV‰BN	éõX„
9Èr	‹R9ÚuĞëÚ#t!1Û‰ŞÁæÆ"FLVu
ƒ8uèÁLP9ğuéCƒûuÓOÁâ	Âxy¾™â,ÀP/^ë~!²"‰õL) 9ÅroP 9ÕrI‹{ƒæD')Å	î‰rÇ–'sW	Æ‰O‰Z	*z?WPƒ!‰%	-mPW ëP/ˆK‹S¶‹SZë‹[9Ó…zS%1Àë"ì,(€Ö1ÒéB\°×~Ié3y'9 $ßQjwÁ¿ş|u €û\t€û/uŠU S€ú  /tˆAEOwŠ]ÿ€û wÕ19Áuë‰Ñë ‰Ş)Î€yÿ/uQÿ9ÂuëWÒëÆAHM÷X¬µ‹XK‹@[éC'¬
"P(‹xO€±
4ƒøtvƒø„† ’í…ŸdÄ	ÕÑíÕ‹K‰èÓèÃTÿ†Ç!ı!ø "x>Aà›H9ıu"¶<(ÔƒÂƒÑ")N¶HgÇëA®<Àø%MÃæ
C‰øÁèë<!×LÓê1ÉMKl·8ë#•)q .Q‹%ltÈèX­NÕ‹"ù"â ‹N$‰L$Óí‹N(‹F‹Vt¦MªY:¸x1ÓàDÿDD$9ÅƒS‹Cd
hŠ@	­ĞÓêöÁ t‰Ğ¸!20Cl
p9ìw-;Tr'w;G
r+U D0Ô xë
‹{X lhGş;FrHNìÓàóét[O
sÿMóúB´è€÷ÇëÑ½pr
ÓåO¥Â­Â>UT‰CH‰SL‰kTYQÅGG9ø”
‰ÇF‹TH$rßiâ‰SdÇChôèRÓà(El	pt[GêƒÄª,‰å%â6EğŸVJ‹s1{Pc@à‰UèÇEìt	 9}ìwr9òsA…ÿ…€t +ğÒ!Ğëx‹Eè‹Uì)ğú‰EĞ‰UÔƒÀƒÒ ‰Eè‰Uì‹C,™‰EØ‰UÜ‹Uè#S,‹Eì#EÜ	ÂtB	ë=Ğ‹UÔŠMà-„P‹Eğè'
@N1ÀL%Mğ;Ks‰È_ÓàÒ&5%44R¹
_è£HV2VÅ
#.3è“¹d]NšH«fì4^x‰ÅAHL‹]@D¼uÓî‹Kdƒ{h u9Îs]=\2`«ëlp•2Erëè·†;‰ĞLëA9ñrç‰sõ0‰
‰CpY4Xª#È8‰òÓâZÿ#]•RiW‰Á#~9Ã?B<`úRÓæ!W()\ Á| Æ" R #ÿQ !½9éhIŠ„ÀuJ:édB”<åú—tW€ú…æHˆÃ¨@ŠWt%T#ƒã?€û‡rS¹
t›„$*Wè¥G^–:S…SA:W…IDK¶ÃkÀ”xúèŠMˆ&„!I*+P!©3%ÜEPf‹
ƒÂt¶Ù44xWf9„
uŠVëf9Œpl[f‰ ˆVˆ@ëBúDö uİƒÎÿëf?ª!«>%÷Ò@×Fÿ={¬†`°s €â"œa|Z$t+ 1ÀˆÁĞé¶ÀÁàÈBƒúuëY#Iå ¬0Òë~ 1Ò	€ù töGtŠ‰pkR@Tuâ€ t'Æ .@º`)± ,± ÆLJ‰Æ!=Ny6f6 ë¨8	ÿL$ƒÇ ƒE ƒ\:!ù@8tå^NSlFJèh"@0ÑƒCdƒSh ºv	Â,x(Ó‰ÂXDè=E.Ç„F@‰Áƒé]¹€¡d$ëNÿWÁâ·G	r‰øE|O‰BA§BAFƒ€ú
ôƒâM½f‰P
pÀoèOEPŠH"LJlf&Î0¹‹äèkï" -uhÛ~hëR è,"IP ‹K‹Q ‹I‰HXƒÉÿ˜u¿â!¥PHUğ"è-IøH:Xp\‰X`Ç@…uÃ±t(@Aoµ*‹BW‹Z`J­èWlÀ¹ˆ÷ñƒøî#šN@ˆ		¬UH €8.u%‰ÂŠ@„Àt
<.u€z utNU$!Õ5L	)ğëOQx1!2;AhõS  v<.5ëÆD @ƒø~õ¸l@
ëÙŠ’pj €úåuK²ØD
~¾ëû
~õj Š@R1yw­t|Ò˜0‰ÙèÉ;VM¹7Ø7p é-S€~à!=?DŠFë<]zÌnÈVàEz^
8
‡…ôH¨@t*ŠVíˆT$ƒà?UL_Ö ¹´}D$ èºëD8Fí…¹t	I	JAÂo}T$ C}Úè¡!™3€xTt1é›_f‹
\J"ÄC/¶9Açÿw;œ?zxt…nGëeM\)h	…ÒuÅ€9 ë	f‹ŸAuFNñ¿këE¨	Ø7!);(Õ/Ôë¹j¨Úuá:L!‘+A(\@kƒÆ ^à%YNÅ¥f!Æ?ùPjFG‰Ób	ÚDØRéÁ\	ÄXR§ì/h6MXOR ‹S¯P
—·S¨i KÊ‰PX…Ò‹Uu‹r ‹R\•[öU[Mq·ñt[Uë[ÁáUs 
ñ‰Î‰ÏÁÿ	ùu‹r‹zëƒÆşƒ×ÿ‹J÷Óæ´à ÷1örz‰pl‰xp‰p\‰x`ŠS-”!ş*ëhrdd‹réÊü$7*ìtf"¶_‹Fp‰OOºˆKâ‰W‰Wj jL q•,!™JS!JRfM'*RM©‰©,IJ¸8béìôU(ÆŠ$qê$E5E,S ‰G"I:2|,ME-@d•·l$/f…íu‹l$<i*IA]%ĞW|Å‰‰V"#<,¯d5MV™YıA|tJN¨‰VN\$-!"G¹ K	™÷ù†RO`i
Óø‰F ‰$‰ÁÁù išR]&µ+VN| )½Ø‰^$‹WÚ‰V(Pÿ‰V,L	!J'F0‡1Ò+BˆÙ-)Å=ô  w	ÇF4bë]ÿÜ™[M@M1 Xÿv½x PD¨€tƒàš™Yø UH!æ#ˆÙLÁ1Û$\HN‰^‰n‹W‹Gè~RG#G'Äë@Ç¼!âN¼°!}2ĞA¸véuÖ&Ğ#¹ô‡éŸf`, ËƒèŸ!	"º"şe€;ğ‰Ø!Rèï?oAÿ/H&	uºàr URSh]i@ ²ÿHP@%aYIL$aÚåÿ"«)@t,fO:LO;Ê¸!‹,è3ö0@u"ÖMJæ#õ5Ã‹.!êO…d"EjÇQ!këç„x%ßk‹PYÉ&ğKĞééÿÿ\%LU‰~Õ!&!P^	(‹\$$ë5¾Eş!ïV¯Å|ÉˆA ÿÑƒø }^ëu
G,‰1@‰÷9û|Ç#Œ1'ÌL!ÕkX'Hò9Ówr9ÁwE!¯,ÁsRë	€qt['´- <‰E¸‰U¼‰EÔ‰UØEĞPÿ5t‡@qhn MÔºrY¡lNè3n Ä\i	ÿEĞëƒ}Ğ uD
‰Âë@‹MĞIÁáh $‹‹Q‰EÀ‰UÄ‰Æ‰×qy9}¼wÒr9u¸sË‹E¸‹U¼+EÀUÄAQeôŸ¹œc@é¢=&'9‰ÃbD‹ ™ík!D‰÷[–‹EX\WV\iè/I  ZY1ö#XItƒ{ uE#¤+!‰J ¯Øèã1a‘]Tµ7‹C‹P\‹@XQ1"Dó„Ût!‰ËÁûSQèŞHb
)Ç]!Où#šSÕ<Uøè.{W‰Ã#Q"/!ˆHDxNf¸  èJğÿÿ£m¹hô!W.Şó¥!=I‡$'Hë|zR+¶‰Ù“-èËıß,tX¡y=`uhdS\èb0" K?‰Â‰ÇÁçë÷î€ó¥J‰ïhÜoà9Ê‹5bâ·!¦Cò¥×f@£i
[€\]±x
V
‹TD÷wCrH9Ëw=Er<#| ŠZ8Xw2r-‹H	‹X‹B	‹RCKrILGrKLë!I2
Y€É…È%`b+r$MÍ*1ü ­@['Ö‹ "ŒSX¨M1,l²LedCU·‘uA=l `@70èG  ]Z‰Å/a !˜QY[‰Ñ‰Â‹è×2œ÷@‹$)ëQÎ0[
;…,vIC,i(‰Ù!Z&Ø:aS)EGŞLxQ·(N
0^
uuº+D*«~ìLBHXÖ‰Ï‹¬$(qĞ
eè{LãdÂ_Ch[YßeMl ]– #.UışŒAYßtYß¿nqÔ|!ÒLèe"RP‹dbOĞƒÀe!š;RP!Ù3…»ØèÃD¶„$„c”$€d@T…@‰tÅ ‰|ÅLŸQRÿt…`h¢ GvŒ$DJº!X!6•~PCûm E#d	¶T$t;D•`~H”/í‰OkÀ!†oŒŠ[ Uÿ´²Øè"ÖN‰ÃDéæyØ ùR‹„›¶””_@‰u
}Y#
ÿu,í)î‡úl=ö‰E]Th4Ğ½w°eAw¹p	ó¤Å#Bf°zH1ÿ-LëWV‹@1Ò¬d¶Eå#‰ê™M¯w‰ØÈÃ¹@Ä˜@!JyNrÀn	AUWtW!*.l!8$D?H$8GDÅ!ùeéMWAÛL8W'‹<T ERœRZYGhzOƒëSŠ2"\x#ß_Œ$Õk´$Ö{ ¼$Ú{ „$æ¹Aêœ)H "#„$îµòY €	
Òpthœbñ+HhP¼# I^P YËyä!ˆ)Má(DÚ,ƒÆzƒ×a¹€ø Æ×‹CDÿŠ$Óèë3YZ!ö.ƒÀHÒfl(Ü&XH@-6#CT9‰úèOùÿÿ1p #XJsX‰{\"Ù)Äø-gy@»|ˆ…ÿt"‹q`F9ş}‰q`QR‹‹Iè_@p^_0Ûë$$‡xE¤Îˆ ‹L@…Ét1‹T`B9Ê|Cƒûuéë ‰@ÇD\x‹Ş‹LŞVWèJ	XZYó„ìû–ì°m>Æ!¡/("TPU-UÜ=T‹F”QQÅ>F>÷øe>|
W+ÇèèªIrYu×UV”o8øèšXCYÏNM/fFE­eZ‰C!_TŒ$ÈrA"¼j!m
RCIËneÿ5Nl·„ŒÆD %gNÄ°,	¼xM–×]YîN&ğ,] ŒTíQS3NV
yU*j~èäF[Z|V1ÛéÂ½RÉ¡RIí©µÖú"z=˜ß$@tÎ‰xn‰Ctz % ğ  Áè‰Cƒàıƒøuvml.L^£÷\0.Xú¬h…pÿ…Î©aÒ©aÍvuH"!$¯zT~Qj±t\ÿğú‰CX‰S\a~¼õ%º`ö1ÉéÆL˜(Ã€=¼{„XXF¤'9œ&ğ‰'9tYAğ	}öh)¹A™”xA!m\ùÁ€!…7úA D‚ÄCC†è~P0m±³$"Øyƒéº|D¥{Éèå4$ñ{¨oL$M«E	¶#´rt²ëy)Q Ø³hûfƒ×'!*"é‹Ñ„pI(ÿp| Ñ+UP-òŞø-e-iY £n3‰l3Y[ëJ*"µ÷‚„oBë€È]Y¡­EGRéu´+]é",—'$Ãö|UD;\i3Ğ‹3ƒ=ÌX!Ÿ4ƒ=È@vhrJô&!˜ j
 ,©ä1©4V=õ(µ˜•œ¶ğ÷l„I´êâö‘)*N Îö¸bÑé¥c½¥Á¥EUÍµÑ´e‹ Uı¶”"u!(U©,	µ,U0#İB;R‰ñÎ;Åú©Y_%éhÿ)e âÅ?…)Ğ„)„‚#:dpÁ"-S\è§óÿÿ‹ƒÁWV`â!Õ|>\ZÀÆDH2\ ,b$DZ'°\#šF´æ$Ä+#'51Û¾TóTmhëkË¾ @po,†B;=xr‡³N;5{
ƒ§L!v-+|öY)m¨õŠô=*S†…dÃ|$Muu9t$Iuo’º8P?H$YèÇ1wcuX¹p<A9U	!C…èÉ!".ë	8¡7t‘!W˜er- ‘!\*9T$av"¹`W¸@Zè–H]aE‰e%ì'AË£'„+|!)µi !´ !ÁD8!bjÊ¾ˆ¡!´l ƒâ÷Úâx;ö‚1êNuì‰xóAùdTuÕ‹O‰K'kESÇ ]{TÇC"­ˆºnèÓPZY:wT“(¶¸€fØ0”z1öëY¾qO(·†¨X HÁàta‹‚tW‹’xT È‹G‹Wl·#>G;?U#ò]GCGUU!„ÈòAKò	gàq5UkHŠZ Õú€E%Eh )”¬è"½U`}+øBnŞ/j­ºş|‚Š1Ó‰ß$ PÁê3½”#!Msäp-^ñ(°+šCôAÔ^A!Yf­¬§h¨IòT–$œK'p'Í¡0#ğo	T$D‹Zƒãğ‰ZG‹>489Îw€> uƒË^é9D4…ÿuƒË[Šˆ!´ˆL$Àèˆ
z<²N€ù@"]!áb‰!úeóW ,1Û-ëI"&¶"‰I!Ü "0•¤ıÁç‰|Dl$(<1Ï‰|$‰ıÁıF dLTÛ!3(rîKŠP!ö¯‰ø!1gª!=9‹"µGJsZ#aJ"²¢ğh€8 x1É1Ûë"µ6ËNF'‰İ(ÕMA|5"»µ	ù[	NŠC	<0ŒÌJZ‰J"ï|Ş	ÎP"JëU ˆ"é._kK'åp0)¹Ye "Xv!ƒL^PHX €{t ue‹“©‹{É‰$#N‹N$oH‹#	s,tI!/”v‰^C"P%twCTéİzkx!ÿGƒ»t!ÉWº|ƒ‚®T "™Æ~Exc‹N)‹E‹U?Íƒn‰“{
‹N%,Ğ øI
u
},hY;$F.ƒÆM×ÿ«şÓï¦ş1osT‹fvCxF\MŞE\-€	&„RSH‰KL'ı)ı,#ër(‰ËE	L!˜3!É?U!!ˆ)_-ŠM"ÔtZ”!€DL“Ü…	ƒ|$D w9\$@v#ípË%0b\$H‹‹Kè9#%¸Ÿá‰ø	ğu-LjT‹‹VŠ-Äz&÷<è!7!e"_"èI&ˆ9#Hxğ’L$D9Êr6wd@9Ğr,3Q@P(èñ*  \$Dñû‰$‰h`!"2éÛ$u:@l|ğšE$ Ä%…&ëß4"Op
@
Af j_è˜`"¸5!=%)PøL$òùàRlBU_T$xQ9ÑrYXÉ]59!ÂN'L%„bK%è"§$„»\ ÈYZ$‹q}tW|$.Ä„`Q€«GA¨;H!6G
;R&rh6GL‰! ›X4P tÈXP‰3‰{U-Dl óè«4"\Ek4h"…,)0"Şh‰ÅxÚ*Å_$&Ä_i<H"å_"Hh"¹€L”I%©%I©&IÑ'MÍ*M÷PHI4H"Ö©éÇP ­İG¤ûè…)‰İ"=bMÓ¾\$T„Ûy&ë½Pı]œtØé£N÷Û!¦yëˆ¡!½À½ÛÃˆT$$P}óÓã‰]¸;bíHÜ$¤g[
¸YC
è¼4‚H‰ ñtšHú‰x%}‰x)Jÿ‰H-"¼fâ‰P1yrz‰ó]uV
Ø™`A!³•‰QIX~ˆHL«L
½Éù‰MÓæ‰u|[hE!"–‰XA¡%IX‹s4|$H-d@-A -g0‰x`m"	pÁM šÁXDI
<I
@,pr+@K  wrƒşôw–p!ëoÇ@Qíÿ	!xd
Æ@5Æ@6 Ç@77RòUn\{‚ë#¹3pú3¾'$ù25F_éP #â:)(% ,‹
ùINDXtùFILEu,·ZÓf‹;f‹r‹L
ş1ÒNëBf99uf‹,Sf‰)f9Öuì)‰DDŠP\Uu#??‹Hi€œÍ!åœ|Q €5L~½ù‹X)",Ú#´OAybA³2“‰ù!XeJr‰Ç!ƒeï‰øHnNAQ"Á`<A
@!èSÕˆÙ¥ıÓç±*ı!Á-N_4ïÓí ï1í+AyDúM
!ıyv},M}0‘·FP‹ øê&X0R'<PNo8RF4PR 0PEyl Y(#lğè !_&ƒÄC`hƒbâ%å°&ìÿ]÷#'vFBÄè¶8•,`‚	9P,uƒ|$ tr[
‰9!"¢ëjI4U8j‹~û!Ò]9Ø}LEŸ\
r*!~Xúr"E˜,Ø–ˆ"€!	ƒÇƒÕ +8héUFÿl”lhŸ_ 0é#)—$/D)q)ÓE3*ıh5ı7Ptqoñ
)‡½ÈèzB‰Å(	ğB‰ñAs\—CrÓèU7O(õ8Y	<"äWs¥Ş
¹5Ş!I¾O_7óÓî¡ó	Í+Yj"²($Y7wy(ìx-XØòY
 L"!{8z74R„7Q ,y7 l #uhê!fHcøñ7²7%#+kÖ!,:I7j7G
èÕ!.} œ6y5¸5‰‰qëgE0XWF4‹Lğ™9Ñ&DDr.w94$r'U(Ä5”bƒÃjÖ ì#°¢x'±ˆQG-,émè+@'´PmÓ¶zPèû  $H/9øuJ1É€{QHÑë8·|KR¾9×u3"/îë(ŒW¿ƒúwƒÇ zj	ızÂ E	gØ°%èØ(à™p‰U ‰Ï…Ét‰ÃBu™é`Tˆ!«ŠøD£ƒúÿ„@Jƒú m
;U ué>|ÙÆ@ëß‰e‹K1#E¤¨‹ƒÀƒàü)Ä‰eœÇEĞ†%EÔz €~!ñÛ)Nñ"pÑ	ğë‹U 9„š|QÑ9Árëh¤H8!¡/FğŒ%¬€EØèv"q	´p	·F {ˆ‹U]„TP‹MŒU´‹EˆèVóÿÿ"ÛMh¹tA  ^1ÿéb#Ä% 	ğ¨töEğtÊë”¨u¨tğ‹Eà‹Uä$'oÇE¬µ°y é#>YEÀ	Ä	”	˜¬°U˜ "‚mH)¬, &@%"+ú`‰ĞÁú‰EÈ‰UÌÇE¸©¼x UÀRE¸
·EÈ!µ_¨	 ¤3„œ!Â8‡õí[
[é-|}Mœ‹F0Èë†(t\'õï
!”‹,`%‹¦™RPU3‹hèï!§[YY1U°H;Uì‚W
‡å`›E¬;Eè‚FéÔ` q‹G,1Ò9Qu9ğt‹{MĞ‰ò"™Í7##ÈhËa-®!FËX‹‡…¤"ÈÁ!çÎ^ é™P &Üs$8E"hP‘9ùuëèbpÀu‰ùp
ZéPD#xYVìlLJš•¨}0"0¸N‰¸vF'Æ	¥¬a^!5.h!3AğÿS'…´şháeF^Ç‘;2!(ÿµz‹v º$UVQ[h “Qé±dNPƒ x!6Â€y!‡`Ğ!|ÁD‰G¡{1Ò€!‚¿„#8jWöBt)ÇG#/*Æ@Uı~1Ç@$VM@¹ y ëù·JÑ‰O"|ÂZP‰°şÿÿëŠ\JRˆœôSA;orì‹ Æ„— Šx €ù$t€€ù.„wu7p!‚A
J- ½nN‰…`	"jX„#Z€x[t
h÷|"ÅµŠ˜,0¾…œn• m
•e!’œ•”
T şv…ØSè»V…¼Ü.¯·AğÈ¤ip'BV‰…yë	Â•R‹f
•e‹‡èxï´{
h(sMO‹…ğDB{ö„uë!ÿ¨!TLq™½t u§ëÜÿCé^thœ8‹A‹Q;•ìt* w;…ègÇA©3AŠ3ÿA*nàfä~Ğu pdÈÚ4‹I%-N.@ /J…À…)ÄW Ç…ÈË$Ç…ÌÅ™QD„’PŸPÿµk/ÿµœ‘:˜0|_V:Sñí††ë!"à"—èÓõxj;#³(hHZ(èòW[éÃh¤©1…oƒÀ	'˜Œ• rQ
ÀC£5‰…ˆz5};—‚’a…)® A¢<JûÈrˆ½p\9Á‡dVÿdŸd5‹F-À‘L‹“Lè8'˜–CSÇCšgé9kÊƒ½h!4vd4@! Ño
…”W¶JP †ëf‹LBRˆŒff@;šrë»Æ„¹i…z <$	ÄI
<Ajû˜>"€}Ry‹‡‰èÎ#:.éœh[ˆv!}Šm•‰	G	}A!è{!JjA¿‰•ŒvÍÍ^~!øÕ‹D–]©ÆaqN!ÿkf‹@!ª’f!JÁÀb‹€ f‰B
K‰Ğ"¡¨•cè$šyzÍlëhbj:B&éOBhs^ëîí°U#åÕ‹8!IŠ^t!/%è²R‰Â!vtj!ûf‹_+Vu¨øt¨"­ì†¨ëQÁº€$Fn0ú†qu—¤è¯!uë"d\L¥Â‰èèŒF"V$N“ÜÌV$!+ÜØèĞL!ÊGĞ_)Ñ*8‚ÃÍÇ"à®$€%$²šx"hfl##<åP“fénÂuh"#,f‹B!2³ElŞ%&ôš-zIE|à@”b•”%Ó)ö@AEz]	é"$·­¾¾P€=[hè ^Çxa ¸bèQU-£¤!­,–q‘·}
0iC¸e¾él½
ŠCˆEt‹‰Ep€{L«!MÛCGØ	x!fÌéŞmSÚ"€5!½VÜ¦V9‡(ØeM L"
uExc‰4$!2,PXè"…"”pè]êÿÿ^#¸ğ#â#`@Õ4!Á§Í!½#]!¾#Å¸sèÌã
¸³zE%`ÑŠ.¹d	Ç‹4$ó¥ƒ}x uT	ë	‹|‹ ‰B£| &‰X!#G élDM—
hÅq!|uqCuE#ó®‰E$q‘Ê‘TT’ÈÊŠgëFQPM¤ğ!éÿ÷K…x^[éihå€¥²F‰Ã¬!9¼™mE~•Ä8+­+l˜‹!&! ¨ ïƒç‰şƒöÓæÓç‰u¤‰},¿*´‹s%ë ØÿV›E¸(­	öDÈÿu¸‹M¸ı4¼&… Õ#	-xuÇO‹wÎ;u¸‚"Ó
‹GÈV9Ğ‚©™V	…òu›Tf‹FT2 ‰ò‹E˜‰Mˆèé¯„Àˆ	51”FÆë±¨I×y*j(- ®¨öD!ÆX…ö„n^$€~(=a~	—÷;”)&-,'ô)&%-O!‰EŒ$$-
”U¼‹Eèèÿÿ_u0š'í,#ï,ØéˆDIIñ&è,"Ê-é,Bp uĞ‹}Ô‰uœ‰} ‹u¬‹}°uœLˆu"lN.É, -$™.È­Ì˜auĞ‰}Ô}ĞW\ä!-EÀ'%-Œ'´V$=ê-%-![CWè½îHUu´>‰â
Šâéx }´ƒÇ‰ş‹E´p;u´‚åŸWBÚ:Ò *YÄUöuu“:èòf:ufÉ9ºœ	 ¤5Š.L Ew^%ˆ.}°;}	è²bì‡~)ˆ.zâém€¸è~Ç#óòW¹@¼‡!Ø¿YBÇ€|"wµè'!CÁ‹I‹#¨s!é‹ófö™¹<Fëm	2e–ÆèÙS_ëôÇ%ÔÛ.á\páº"È«lgPØuht^™p"´eÇp¦Vöó·gh6muOXé¡”(DÇĞ‹KŠPˆQ5	 6€xu'Š@	A)P&%ĞL	ëşÈuƒ~,u
¶Ì5#ÈpÆÿÿ(&A¾%µÅ!Z+‰Yº|ùƒ¡‹†v{‹–j¦‰†Œ–"!/ëNóèJ
1öAÀ#ÒÜÃ!=3j	H	"›X‹#†àk$\§MÚ×$XŒ`M‰òÓê;ps^1ÉèÃ|£ uN#sÆ‹‰‹C‰G¶FƒÀ!n·¶V!|>!5Ìw•0!äÃTNNGç,H&\ÆDfy%Ôb)a‘ "ùgPOs@‰$9Æw\P{4 t)Ñ°Óàì9;Cu8SX‰ñVBÉ\.‰õ;4$v‹,#Ì]Ôy¤è"{)Â]¡\)îï…öuÒ(„s(XáoBÿD:!áGq:Ö‹QNgr¼hbm@qLÎ!Æ©é¬“6÷q!"Q!B†X"T%	
  ÁåÅ„‰p4!9[ğ]1A	U	ÕÂ²õ	té
¯rÆuëb¹<q8úy¼%iN	Zf!+·À"ğ"åBC G±‰C(!hB!6ı‹F!‘ğ, 0h4V(CX—
è¯#•±ÛŠºm'eú$#?MÖ‹vöƒÀ$0lKè$†ƒ1ÿà.&†˜éeT¼ÜFM¡ı#a]#8e	‰ı+n9Åv‰ÅÓoEøX ëB‹\$$[‰è+L;Âw7ƒ; u	 !ò½ë ‰C9Ruí v"İO‰hHB_Ùëy: "bãµƒOƒT@D8;~‚"œ„![‹h$àé'#`-ÕÃ#™> T%4!Écm H!)W# Ã|$8Sï…"\3$
"Ä'zÃ·t&yÃfZèMn	CÌ!-GÎuDKU^!ÉJÀ`%#€ƒÀ
T8#6€‰×Lû{ˆÁ"X€"Yß(" ˜Q$‰x·":aC!ÍÂ‰€ƒ¼$"@Ûw
fÇ„‰ IhŒ„ÒF³‹o"ÈH+p6!ÒÓ‰Fa9	"eÅX!$ìCPèak1ÒJQ#=K!	]!²Öº#….à„&üÀ|%V'Ã&¿"}suMÜ‹ü
r}èVßƒé|Mì¿ŠÄçH"ÖèÈ÷!õ(à!ræ¯  
‰Mä1ö1ÀOÿ‰MØë8ÿMğ…Òuƒ}è tn|Óç‹Eè‰8ëa¥dÓcuÜŠÓî#uØ‹°‹MàMäT	ƒùÿuÀ‰ù)ñ4°‹…( …Ò•À‰Ç”Ôë9†"¸Íè‰ë	@û9Èuíëğ‰ĞEaÀ"yè+ &€Eğ‹?‰}ìö@2„ìq4Ö!wêƒÀXR‹"NÍUğy 38
óucfƒx xtQ·X‰]Ø1ÒëkÚ‹MÜ;LsJƒúÿu
ë:B;UØ|æëğkÒ×·_‰]èÇEä‰ÑW@
UäMè‹]ğ‹èßN³ëHË1ÉëhkÙ;te
I|	ëA9Ñ|êëñh%ZèãO^éAT kÉù+1·y#¤p9şƒ.$½R!r"IÿÁÓƒ}ì t)÷‹Eì‰8`“"A@é#@’h ‹XÁû‹p‰uäƒù wSƒúwN#¨ì)Ñ•˜]ğ|X‹D“Xw	„Å…¡…"ÄE!¦í[ë_—t
‹]ì‰é£@Bó9ÊuêëíP*
ÏƒÆôƒ×ÿ‰]ÜÇEàl
ƒÿ w9Şsf-‘ˆwóuìjn`äŸJä‰Ú@eñ‰û+MÜ]àX2åûeÑEu–ŒÄ
ë(‰Î‰ß+uÜ}àmHâd9Ös~“İ
è(S—Y[ë”&*å9UÔÑp+p½ŒvñÓåMÊšÓê
C$P‘Ë¸`‰Ñ	ÁuÇCH#Æ”CLz ë-c€é!ù	‰K"¨¬p
ñÓà!ï)ø‰CT1À_%ÜÊ×*¸©}U‹‡KôëıÌ–! [ P‹Œ ºŒO~è`š‰>`!õ£lv",ŒGÚƒø
!I!a™î\Æ¥‹ ˆœX Y€Y ¸"§¹[é[!Z@ëCèÄÿÿÿ¾2óœL""WÍ‰ç$¬İÖó¥œZâ"$î\´(€åı	Ê"ù`UH©RPèË®#œ3q&H‚$Cş‰Í"<ù$~©@%ÿO‹pF”)ò!># €HPJÓê9ÕQÉÕL|!Ê†a”Ó	ÌS"¨€SD9Ğr{8sH#÷ó¥¨
‹KD49ğrYå@	dDx6_BÆ)Ö])’KD!×7‹S<Durƒøıw&©8	g<'m’S"ŞhL6!%qélúƒ{T ‹s@t09SPt	EÌ!ØÿQ8I÷To‰sPP!~ò±6|\ã!6hó¥zuD!>éCThï]F!HPÉLE(1YÈ	%9N+uLã$u"èn}D"‡loM1íZ‰îïÆXäÁ÷Xªö	u?uô1ãèÏ	_!j !p X"¯$ÿP(K‚s8CÄ	,L s@)sD)õuií;­vPWS>A"&‚@ !üe#”ƒ@’&„$-%ÑL:ÌÂf‰xSÌçÿ_êW(hs	 J$«Èoƒè'ÇtÖ÷f‰C·Ğ‰Ğ"ÛX4AJkÒ"¤FÊÇlA¸ ”4Y¯$!ã]pÇ$É¢@"Å}A!%KÎBƒÀ‰ù·{9ú|ÔvÙ‹PdL@
"´)EJ!\.”%Ğ[d!º0^Zçx!¸* 9Ku9tƒÃ@9ø|ï‹^EïE8!!6'‰Bp`@"¤&• Xs
 ^$T»ba‰Åj ècÃ9xk
0t#ü†‹S·Eè!¹÷-^ÁƒÄQ
*^›ì#ğÅ"t Š„$ÀB!‡š*‹M"ˆ{‹u ‹}$‹E#'Œ$<œ$"ÈO"÷Œ‹E!?û¤Â
|]‡"Â†r!Sƒ}x„œ#>™!`›%øßQœ¢!™ Š[ƒÀUQXZ H¸ì¼'$‹( )] Š^Ól#‘t Hy•OŸÑ$¾Æ™î!Qì!|œ!ù$ W v	Rd¿~
‹Mq‚#$#\S^ utdqf+"Íx\#¬Ä"rA9ÃS^Ã9ËW Ë9óV ó;!QT•
+ç€"
Št#MxlJ"›søè™!€!!ñˆPQIMQU™"¡¢P@	Ğ^LŠD!9‰I!Ùà"™âD e0RÿGw2¾X#"¹¶XSŸ,¸e­!Í*ö$ÄÌt[NuáÑët
d"Ş ëÎknB¸NPø£¸FL!Ğ$(#ãx´$¨pÔ¹ P"=À”bhVyşì! 8L#!eÓ -MŞ…æ]+!˜È{	tPå#©¾±PHyv‰„4$!“Ô)œŒ&Kƒ¼ˆ!JZdş…
$,¥dL)™´`N#¬…ANÔ£N‹NcN‹FiMUE0(¶t•E‹BKU‹f)¸Lş$‰ÂWS'T$6Ù)<ÔLÛ~şè9}V±N*”#ÄŒ$"èD+©	ÈMHM‹l$æ¶éÖ\LQCQCĞ'r‰ê…/¸‰ĞèDw
‰ïıÄO@
„OÙIïgHtE*@+…HdH#5X46ÉA[ƒâ#‘‡#C¬fÇx"&<N@U¥,
Ph[f£Rd¥‹§‰Tb$XT II\II0ªIÅˆIt2!‘l®|B$uœ1É”&µŸVÑëUK"­Qty÷¶M0PLHl6Ô!Lt+F V$„¿’£ûp‘Ià@e@À
9ÃuÇF(ÄT é“|ÙUøUIÌµTÌõTŒ•TvTF÷" ë['æ$UstI)ú!ù]Lh@‰V,$EĞœ¥?”˜
]UĞ½U]UĞ½U|UD"©#´ôU$”‚"¡Tœ÷vj P‰ÃÁû‹L$¯Ëhn
¯ĞÑ÷d$ÊRPSğÿV"È7(kã\‰Ç]¥€„^]~Q	xe<IL|(;ôèB¦‰øA[ QI˜›G£¼‹"£¶Å£À\ "R­y5!y´)"y`0Q:¹5ğP¢öD$Xu~4M@˜UfP„ˆrAf[ZªUN,,¯ã…²dNW‘HUª¥ PIEš€g\IXQy J
H'
Ñp,eUät¹ˆNëL\U uí·Œ	fƒøIw¹Je4Á„!ù8{ |=ÿvÀPÿŠ…ÂCh²¹ ”	[w²ë?ì1ÒæB\5¬^£°|'½À£´\ YÁp!í$t	Ìv)=ĞU ¡w#¯b&£ÄQ ¸jT„ÒVR5WIÔH!Uë!`ÀCÂ‰¸hgƒÄ\©é¶T"|ªHûQ]Q´ |n èò!F/£Ø_ÇÜW  EèdPEZ¸l|ñEFBa/O/€:/B/Z/æ#/dQã4VWP"Œí‰úÑês¤IˆÈƒùrSf¥!E4ˆ¸n¨tf¥¨t¤X_^_>WS^ˆÖ4Â6
	Ğ½ªË}«}Ë«öÃ`X DªX[_­åÆ¬s¶:FB)øu9Îuğ1À^œ!vùB9  uú)Â‰ĞÃŠ
ˆB„Ét@ëô}V- 1ÉŠˆA„Òuõ^Ãfë@@Š8ÑuõÃ1À'=1!,¤!X@ íëŠ0ˆL$¶é¶<2F)ıu	M!;Ouä‰!!’6Sè!ï1ÃŞ!\`RpP#„H*èGú Z[(ü¿hèì
u°TQ\T#ûÍt$|#ÙÎL"¶1íUk %•Ô*ˆK&ÊKé›Xƒú‡Š@!H9¼“¨èÿÿÿçDU
M ˜!É4?M N <%Üÿ$A49JsHWˆG"Ä¯"6RéDx	è <‡÷@TP‰Ù+Œƒüo
á°N­ ¨), m ¸-= Àİa)]  NƒÍŞ éÖŸ éÎŸ  éÆ é"¸"xĞ‰ù€ù	wk	1

SĞB#é"¦'<*é>QÈV/‰R÷ß€Íék.…
  #,]&Òµée,cL$ Ac éIƒ…l!±K6!+´ …ö®ˆJé)| lt:<ht+<jt<Lë<tH*F;<z÷| qu+ëx4#SôHúUéë`VéâAƒ{éØ™Êo~#ÙS‰—ş}|GÈÿ<n!¶  )<c„£H><PtR<X…ZéèT<dtk<i…
@ëa<s„`<ot<p…ò@ë%<u„³wx…	Xéq¿qIéföÍlÊQ0‹!´ò&¨ïV+¿Ü'…é@ƒ|TPt3	`ÿuëct2x t8¾ë(¿œs	ë.‹­ÇDW5ëê ¾ëİ#œ¾(ó¿
e—w¹ ¨€¡//+¡5Pƒë·*°ìë‹1É&§ë-¢ë#ŒÇüT&ˆ¾N4(9SÏs+$´¨$‰éá‹ğL$D!š=‹È!h:.‹Ü\ MPDB÷Å"îdt»,y÷"H+U AmépTœ$ìé!fÎ‰ù¯&0ëA¾0n è€N6YYIH#-GçMx Bà L8tƒÿuOA;B}xK||ŒeIt`"Ó±<÷Åf:t!íYÿû”ÀD	<Aÿ™÷|$<ÈTa4ìgWû÷Å}	ŒA,M8!d=VuBZ,toHu1Q,V~d"54,X!ù<;P'W  @!ôuñxJ	@ëä8K@ë#gT$@ ‚t*-ë$!`ŸÉ+ë	(H ´±+q&ø0@JW#$sXDÉƒá ƒÁXˆ@ƒÂHHu%xD@~ë(á BMx@Ğ@çt0!ª5T#)åHD"ìµ"}²4]7X!Ş-øQ\½~…SÏIë(B4H]8L "Í´$O	8sD°4ÆGÿ_mI`aOU`'­ |L^s,AA\l '†F‹èc^!ZYPPŠsˆGÿ! Ö3­ ;V¡Y_ô^Q`A4T#¯QLAH¸ƒáŸ;F`sXDÆ qÄD!ŸûuI
vÅ…K@_ H)ÂX%,Ìëá#95gHj„O!Ù&gõLV†k‹!W]“!|8"ĞcÉÿ‰×ò®÷ÑIYŞ~V~C ÿtûW~M wf£uEuK%ğ«0V!qÉ)"ŒÚm(L$0DYbuİ#¾#bG)ÂOëLŠU(İ@Guá$P¯„L~Ç”dxÆ B@
"êEuévéğ'©ADÊ(µ(µ•<·•D‹"ş1ˆJ&1Òê¿é¹yvof‰:Ed#¬ºj•éœ¨P‰
‰Æé'§ ‰:ÇnQè'Õ_ˆlv†"ëa#\8n!ëBp&A L’Òë3h”M&LsgGLº€ªåët—#A¦ëh®TOL‰LŸ2¾˜1L„À…Q÷ÿÿ'do‰Æ9‚(ä5ATtÆDÿ`£ƒÄh&lI!Ê$è¼HÃ€  ‰Æè©Q­Â¸`1À‰×‰ñóª¥_ÏQè‘S­M÷oM‰È‰êKÜ¨"¨z@_!ã[Çó¤Ş}fZ‘RQR!ó#P‹ƒ"mHÿA•$Sè6úL[}j ÿwÿ7èt%eø[¼mV&äfEQ!De"ÜiUô‹‰}"ˆ`h&%¸e	Âu#Í "–_éˆ|9 Uğ‹MôUğMô‹uà‹}äuà}äƒ}ô yâzëHì9	wr‹Mè9Mğw"”a}ô)uè}ìEàUä¤¬şÑï‰uğ‰}Ô	åàäX}àu°ƒ}Ü t‹uè@‹MÜ‰1‰yE0$Ü_Œ!G,è7 zû™Q¡ ½'!w‹‹UôÙ P$!rİ!JUèÄP ÊÃ Á @½£ôM ¸N |i…ô "=xi&	!¹Î m X Ø˜ )N O DM 
N´ ¡Ÿ°N .qúl®	|Qğ xê ^n!ÀşÎ+Ì!Åïr¾:,¾ B®T\,î ú'M- Ş* ı%\Nù]t¾3®²A4î ğG ”D®\<i/!cuÍL,Ì.î K N œI N ,P¼xudqxt|xI|U"¼$Ô³¨X±ÒQ 6   N	
 !"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`8|  s{|}~€šAA€EEEIII’’O™OUUY™šœŸAIOU¥¥¦§¨©ª«¬­®¯°±²³´µ¶·¸¹º»¼½¾¿ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏĞÑÒÓÔÕÖ×ØÙÚÛÜİŞßàáâãääæçèéêëìèîïğñòóôõö÷øùúûüışÿ  ü abcdefghijklmnopqrstuvwxyz¼8| œ ‡‚ƒ„…†‡ˆ‰Š‹Œ„†‚‘‘“”•–—˜”›œ›Ÿ ¡¢£¤¤ şåå?í}í1üWE ]GMGMI	]F_G !¿Q œ @                ! " # $ % & ' ( ) * + , - . / 0 1 2 3 4 5 6 7 8 9 : ;L|  u= > ? @ A B C D E F G H I J K L M N O P Q R S T U V W X Y Z [ \ ] ^ _ ` a b c d e f g h i j k l m n o p q r s t u v w x y z { | } ~  Ç ü é â ä à å ç ê ë è ï î ì Ä Å É æ Æ ô ö ò û ù ÿ Ö Ü ø £ Ø § ’á í ó ú ñ Ñ ª º ¿ #¬ ½ ¼ ¡ « ¤ ‘%’%“%%$%a%b%V%U%c%Q%W%]%\%[%%%4%,%% %<%^%_%Z%T%i%f%`%P%l%g%h%d%e%Y%X%R%S%k%j%%%ˆ%„%Œ%%€%±ß “À£Ãµ Ä¦˜©´"Æµ)"a"± e"d" #!#÷ H"° "· " ²  %   aü ü*ü ü(ıçW9É ÂM=ÀT=
Ç Ê Ë È Ï Î ÌMBåMCÆE@ÔT>Ò Û Ù xöEFØ]?ø\?‘Á Í Ó ÚU?ñ Tı‘_?³ T?
£œ¤Æ¸É”_?¦• ü(< µhÂ(L °—X8 ERROR: No configuration file found
 .. \valid¼system¹!ino  ructure Out of memory: can't allocateØPr %s
 fat_sb_info)	vX /boot/Qlu‡ext.e û.cf—%sf  t my	h&k iPEbfs: search Ven	#darr!!'„  c	'p	d,{noty#t]e.¸ compress9½ nDubvol'Åw	"ngonly support sHT+device ”
 _BHRfS_M´ MSWIN4.0á1tfs1NTFS B  ut8_* E{ whi8rCdZ f	mHche.
t<attributĞ?Qp*se_m_n()›MFTIc	d'L1T UW!  ?! $INDEX_ALLOCATION istBYlD B(idX2@*hp5QsŒLIĞQQ
XÀEIex l/İVCrVt ic. A
“rty	l	‰k..L'o!dirQt|S(El	)t*P~Kpp€'¬`gNd o`, aÌªin¡_™d_Rtupw(Cou˜ZetBS$Vˆume)!+ R v¨ˆ='¥!¸c2_g_gup_descbMnk¼ >= ƒs_cHt - *u =ãd,,€ h°
0t	z m˜‘h:Rm's€a EXT2/3/4*°Pl½,õpl^f*ÄÔ'¾thDUight¬Bgriy+ ØW CHS: ¿,%04%s^|ctxllu (%u/ˆ _-EDD9« 
 (ëll)+-¶ H¤¡ 3!ı18N •p%1NPq¬                                                                                                                                                                                                                                                                                                                                                                                          GCC: (GNU) 5.3.0                     û"               y                ,           °ˆ    ‘    ª           $    u       *’˜  0‹Ë              ½       Â“              W       C—ş              ö$       AšZ              ‘+       ›Ÿ              ¥/                   -0                   ·0       ¯¡È              57       w£ß               r;       V¤ä               #>       :¥5          $    îA       Øˆ   ª           u            û‘../sysdeps/i386/start.S /glibc-tmp-ec9b8d6964164aa7972612c322780d61/glibc-2.23/csu GNU AS 2.26 €„       F     	  V   8      +   &   :   ø   int     !      D  A   é   ‚   $ªG    p    R   }       ../sysdeps/i386/crti.S /glibc-tmp-ec9b8d6964164aa7972612c322780d61/glibc-2.23/csu GNU AS 2.26 €D   d   Æ  ã  d  @       ê   ,  Ø0   +   int 8      &   :   ø       !   ÿ  7a   †  8h   Ò  |z   z  }0   3  ~0   ø  L   ¬  €z   ~  0   Q  ‚0   M  ƒİ      ˆ  „o   ®  …7   D  ×  ‹İ   '  ™İ   p  Ÿo   È  ¬7   á  ¯İ   @  A   O  Xä   °  bï   Ê  m$  ¾	  Ä7   Ë  x˜  Ú  z   Ê  {/   f  `.e  /  0…    ´  2E   [  7¦   D  :¼   }  ;Ç   R  @   ­  A›      E…    »  GE   (Ÿ  Lä   ,À  N  4H  R  8ñ  [s  @]  \s  Hr  ]s  P]  p±   X k  	@  ‘  :h   ;  }7   "  0‘    ”	ñ  ±  	ò7    ^  	÷:  •  	ø:  ’  	ù:  Ü  	ú:  ö  	û:  ó  	ü:  é  	ı:  Ò  	ş:   
C  	 :  $
H  	:  (
   	:  ,
g  	F  0
k  	L  4
¢  	7   8
—  	7   <
  	Ò   @
Ş  	E   D
Ô  	S   F
š  	R  G
l  	b  H
  	!ä   L
´  	)  T
»  	*  X
Â  	+  \
É  	,  `
Ğ  	.%   d
o  	/7   h
à  	1h  l   	–Y  	œF  ‚  	F     	L  H  	¢7      ‘  @  b  ú       @  x  ú   ' ~    #  
p  ³  <R  Ï  0      0   k  7   §  	7     
7   ‡  e  ´  7   *  e  #  e     0   $¶  e  (¦  7   ,z  7   09  7   4  e  8 *  0   u  Ö   3     y  0   ¤  "   ë  	  Ñ  ó   die 1*’+   œÚ  msg 1e  ‘ I’]  U’i   é  7U’;   œ"  msg 7e  ‘ `’u  j’€  †’]  ’i   !  @]  ’   œÄ  fd @7   ‘ buf @  ‘$  @%         @G       B:  ‘rv C]  S   ä  D]  q   ¾’Œ  Ù’u  é’€  ñ’¤     y7   “4   œC  pp y{  ‘ buf y  ‘‘  y%   ‘Î  z†       |G  C“"  ‘ ‘ ‘‘‘‘  @  []  C“   œå  fd [7   ‘ buf [x  ‘$  [%   ±     [G  Ğ     ]e  ‘rv ^]    ä  _]  "  q“œ  Œ“u  œ“€  ¤“¤   ×  €7   0‹Ë  œ“  L  €7   ‘ ù  €“  ‘d  ‚™  €cª  ƒ7   N  st „˜  uˆ·  …7   –    †e  ¿  L  ‡:  u„·  ˆ7   ó  mtc ‰ª    mtp ‰ª  /  fs Šµ  c  s ‹†    ı  ‹»  ©  Ï  Œ»  *  ¤  h  K    7   ^    e  •  ~  7   ¨  |  7   »  i ‘7   ß  (   c	  »¤  Ï¬  è¬  û¸    !'  %
  ![  Á  uè·!Ÿ  Ò  uèW"cp  :  .  "ep  :    "sd !e  6  #™  "7   I   @   î	  -]  CÄ   :Ğ  Ôß  éÄ  ñê   Ä  ê    X%   <
  z]   Q‹ö  g‹  ~‹  Æ‹  Ø‹'  õ‹3  $ŒB  bŒ]  nŒi  Œ"  ŒQ  ÁŒ\  ÛŒÚ  äŒh  øŒx  #]  ,„  G  a›  v§  ˆ³  ”ê  ¥¾  Ê  4Ö  Eá  Qì  u÷  ƒ  §  C  Uê  ‹  «"  º$  ÚC  è/  í;   :  >   ª  $ú   ÿ †  %r  °  †  @  Ò  $ú   ÿ @  ã  $ú   ÿ &A  ªL  >   ÿ  $ú   ÿ &  î  >     ' &(  
  &ê  +  	0   (opt (‘  )_  .:  €e)§  /R  „e*—  —  d*î  î  +Q  Q  2*¶  ¶  ˜,8  "  ‡8  ,U  A  ŠU  *Š  Š  Ë*u  u  n*    l-  †     +    }*}  }  Ì*Ÿ  Ÿ  w+M  M  %+    $-Â  ¸   Â  *´  ´  4-i    ¶i  -Â  e  ÛÂ  +¿  ¿  .*    •,p  ş  np  *ö  ö  2*¿  ¿  >+b  b  í*X  X  H*­  ­  N+„  „  *"  "  h*(  (  Ô+    
1+À  À  
R+g  g  
:+6  6  
A+    
4+4  4  2*»  »  =+—  —  +*    d*X  X  Ï –   ß  Æ  ö	  d  Â“  æ  !       +   8      &   :   ø   int    D  A      t   Á  0:   
  1A   ½	  33   ‘  :%     ]   t   Ï   	k    Õ   
Ôà4  »  á†    u  â†     ã†   ‘  äœ     å4  ¢  æ¿   ü  çD   t   D  	k   
 †   U  k   ¹ Ôé  ¹  êœ    	  ë‘   ë	  ì‘   â	  íœ   	  î‘   Î	  ï‘   G
  ğ  »  ñ†   u  ò†     ó†   ‘  ôœ     õ4  #¢  ö¿   .ü  ÷  6 †     	k    †   (  k    ÔßH  A  èÖ   ñ	  øU   €
   Ï+    Ğ+   Z  Ñ¿   K	  Ò‘   Ñ  Ó†   ì  Ô‘   ¤	  Õ†   –	  Ö‘   3	  ×‘   ¾
  Ø†   u  Ù‘   Æ
  Ú‘   É  Û‘   €	  Üœ   =	  İœ    (  $Æ	  ûœ   øß  ü‘   üt	  ı‘   ş †   ;  	k    d   ¬    +   Z  ¿   K	  ‘   Ñ  †   ì  ‘   ¬
  +  Y
  ‘   ¾
  	†   d
  
‘   Ô
  ‘   ù  ‘   	  œ   o
  œ    	  œ   $û  §   (-  §   0†  §   8Y	  †   @ß
  +  A›
  †   D!	  +  E&
  §   Hğ  œ   Pü  ¬  TÆ	  œ   øß  ‘   üt	  ‘   ş †   ½  k   £ y  3   ì  "   ë  	  Ñ  ó   ·	  (†     p (     †   m	  -‘   +  p -+   1  ‘   ·
  8œ   P  p 8P   V  œ   —   Â“_   œÙ  bs  r   ¡  Q
   ]   ‘Ò“   ´  ¥  #Ù  Ì  sbs $ß    ø“%   ¥  *ê  à  sbs +ğ    H  å  H  ;  ö  ;  !
  .]     "sb .ğ   ¥  ƒ{   I  bs ƒÏ   #Q
  ƒ¹   $d  …ğ   4
  3{   Ô  bs 3Ï   #Q
  3¹   $
  5]   $d  6ß  $Ï  7,   $O  7,   $F  7,   $  8,   $«	  9]   $!  9]   %$z
  iÔ    t   ä  	k   ( &¿  ’{   !”"  œx  'bs ’Ï   ‘ Q
  ’¹   ‘$Ø	  ”†   
  •]   ÿ  d  –ß  8  $  —{   (û  x”7   ¦i  )  W   (I  ¯”2  ©'  )c  j  )Y  ~   ¯”2  *n  ‘  *y  ~  *„  §  *  Ï  *š  Y  *¥    *°  °  *»  ã  \–   ø  +Ç  ÀĞ ,Ë•  ,–  ,7–  ,U–  ,©–    -  á–X   §)2    )(     á–X   *=    ,ò–  ,—  ,—     :   ƒ  . /
  x  0,	  ,	  A ›   P  Æ  L  d  C—ş    ,  Ø0   +   8      &   :   ø   int     !   ÿ  7a   M  ƒ…      ˆ  „o   D  ¦   A     ”ñ*  ±  òZ    ^  ÷    •  ø    ’  ù    Ü  ú    ö  û    ó  ü    é  ı    Ò  ş     	C       $	H      (	       ,	g  b  0	k  h  4	¢  Z   8	—  Z   <	  z   @	Ş  >   D	Ô  L   F	š  n  G	l  ~  H	  !Œ   L	´  )   T	»  *   X	Â  +   \	É  ,   `	Ğ  .%   d	o  /Z   h	à  1„  l 
  –Y  œb  ‚  b     h  H  ¢Z    1  ­   ¦   ~  —     *  ¦   ”  —   ' š  ¦   Á  07   
  1>   ½	  30   ‘  :h     ¦   â  —    *  1À  ¤  ¯Z  
  °µ   C  ±µ  Ê  ²ª  g  ³ª  
¯  ´µ    µµ  G  ¶ª  s  ·ª      ºß  ¶  »ª   9  ¼ª    ½ª    ¾ª  ê
  ¿ª    Àª  
î  Áª  %  Ãª  /  Äª  ×  Åª   „  
É  lba ÊÀ   len Ëª   Ôàb  »  áŸ   u  âŸ    ãŸ  ‘  äµ    åb  ¢  æÒ  ü  çr   ¦   r  —   
 Ÿ  ƒ  —   ¹ Ôé5  ¹  êµ   	  ëª  ë	  ìª  â	  íµ  	  îª  Î	  ïª  G
  ğ5  »  ñŸ  u  òŸ    óŸ  ‘  ôµ    õb  #¢  öÒ  .ü  ÷E  6 Ÿ  E  —    Ÿ  V  —    Ôßv  A  è  ñ	  øƒ   €
   ÏY    ĞY   Z  ÑÒ  K	  Òª  Ñ  ÓŸ  ì  Ôª  ¤	  ÕŸ  –	  Öª  3	  ×ª  ¾
  ØŸ  u  Ùª  Æ
  Úª  É  Ûª  €	  Üµ  =	  İµ   V  $Æ	  ûµ  øß  üª  üt	  ıª  ş Ÿ  i  —    m	  -ª  ƒ  p -ƒ   ‰  ª  ·
  8µ  ¨  p 8¨   ®  µ  ptr S   Ú  img S   S  SÚ   ª    Sÿ  p SÚ  v Sª     m  p m  v mÀ   À  /  _C  p _C  v _µ   µ  6  !Ì  ex !Ì  $  !Z   ô
  "Ò  è  "Z   *  $µ  ›  %µ  é  &â  lba &â  len '0   ƒ  D™  2µ    ß  Ø  â  4  cZ   C—ş  œ5   ô
  cÒ  /  !  cZ   ‘!á  dZ   ‘!k  dZ   ‘ Ã  e”  g   ú
  e”  ‡  "   g5  ³  epa h;  ex iÌ  #wp jC  Æ  "è  kZ   Ù  "”  lµ  	  #i mZ   :	  #dw mZ   Y	  "$  mZ   x	  sbs nA  ø  o  $³  —   yÿ  %Î  Ø	  &Ã   '$  ’—X   |!	  %9  f
  &0   $$  ¨—   }C	  %9  z
  &0   $à  À—   ƒe	  %õ  
  &ì   'à  Ó—x   ˆ‹	  %õ  ¤
  %ì  ¹
   $à  İ—   ‰±	  %õ  Î
  %ì  â
   $$  ã—   Š×	  %9  ÷
  %0  
   $à  ì—   ı	  %õ    %ì  3   $³  ò—   “
  %Î  H  &Ã   $I  ˜  :  %u  Œ  %j    %_  „  %U  ­  (˜  )€  ê  )‹  O  )–  •  )¡  -  )¬  u  *·  ™+   ğ
  )¿  ·  $ÿ  ×˜   ;Í
  %  ×  %  ë   ,à  å˜   <%õ  ÿ  %ì      $ÿ  &™   J  %  *  %  >   ,à  4™   K%õ  R  %ì  e     '³  ;™¨    \  %Î  }  &Ã   'ÿ  X™À   ¡~  %  ±  &   $ÿ  o™   ¢   %  É  &   -}™M   Ï  "}  ¦Z   á  .ª™ƒ  .¶™’   -Ğ™>   ì  "}  °Z   ÿ   $$  š   ¹  %9    %0  &   ,$  .š   ¿%9  ;  %0  N    í  Z  v  /A  ªh  7   ]  0 /
  R  /(  R  /ê  ~  0   1Â  ¸  	 Â  2î  î  
 —   Ö  Æ  j  d  AšZ    ,  Ø0   +   8      &   :   ø   int     !   ÿ  7a   M  ƒ…      ˆ  „o   D  ¦   A     ”ñ*  ±  òZ    ^  ÷    •  ø    ’  ù    Ü  ú    ö  û    ó  ü    é  ı    Ò  ş     	C       $	H      (	       ,	g  b  0	k  h  4	¢  Z   8	—  Z   <	  z   @	Ş  >   D	Ô  L   F	š  n  G	l  ~  H	  !Œ   L	´  )   T	»  *   X	Â  +   \	É  ,   `	Ğ  .%   d	o  /Z   h	à  1„  l 
  –Y  œb  ‚  b     h  H  ¢Z    1  ­   ¦   ~  —     *  ¦   ”  —   ' š  ¦   Z       hé  ª  j”   ¢  mZ   
  nŸ  val oZ    ³  <ª  Ï  0      0   k  Z   §  	Z     
Z   ‡  ”  ´  Z   *  ”  #  ”     0   $¶  ”  (¦  Z   ,z  Z   09  Z   4  ”  8 \  0   Ó     Ï  ï  ä   *  0   ö  Ö   3       KAš1  œŠ  rv KZ   ‘ p  KÓ  ‘pšG  ˆšG  ššS  ¶šG  ÕšG  ùšG  ›S  %›S  ?›S  M›b  c›G   M  ‡r›v  œ<  L  ‡Z   ‘ ù  ‡<  ‘p  ‡Ó  ‘o ‰Z   c  ¯  Â½œ›n  æœy  y  FG  Rb  ©G  Íy  EG  mG  wö       ø  üZ   è³   œ—  rv şZ   ï  Ÿ„  *Ÿ  KŸG  nŸ  ŸG   A  ªh  È  9    İ  GZ     PZ   7   Ô  —   ÿ   Ã  _  	”  opt  é   Ñ¬    —    •  2  `µû  ¦   1  —    º  IB  @µ!  —  —  dÂ  ¸   Â  î  î  
'  '  ­    
»„  „  …  …  
     	  Æ  ;  d  ›Ÿ  è  ,  Ø0   +   8      &   :   ø   int     !      D  A   Š     Á  07   ½	  30   ·
  8   Â   p 8Â    È   	   T  ˆZ   û   p ˆû   
i ŠZ   ”  ‹      	7   /  _%  p _%  v _       –  )›ŸD   œÚ  ƒ  )Ú  >  i +Z   j  ”  ,   ‰    §Ÿ   /‘    ¬    Ä     ÅŸ   5·    ×    ê     ÈŸ
   6  ÿ        7   …  ;Z   ßŸ	  œ©  tag ;Z   ‘ ¢  ;%   ‘‰  ;„   ‘p =©  -  c  >%   q    ?¯  ‘à{( ?   ƒ  h  P’   Ë  Š  Q%     T ı   ûŸ  ƒ   Ô +  P e  ’   ’   À  v   ÿ „  è     œõ  ƒ  Ú  ‘ ¡+  P‘   m  œZ   ¡§   œÛ  ƒ  œÚ  h  Í   ¡)   y  İ   ª   ¡)   !æ   !ï    +¡   "İ    +¡   #æ   ¾  #ï   Ñ      $Í   R¡Ø   ¡Ñ  İ   ä  %Ø   !æ   !ï    w¡   "İ    w¡   #æ     #ï         ¤¡À   7   ì  v   ÿ &  #Û   e'3  3  .'Q  Q  2 „    ¯  Æ  ¸  d  >
  5   .   .   ÿ D  8   
     @Ñ¢  De   ¤¶+   ^   ×  F‚    ¶int {    †    ÿ  Æ  ï  d  }
  5   .   .   ÿ D  8   (     @Óê  f   ¬¶+   _     „   ¨¶int }    z   `  Æ  E  d  ¯¡È  »
  ,  Ø0   +      8      &   :   ø   int     !   D  A   ¾	  Äa      ¡   v      Á  0>   
  1E   ½	  30   ‘  :o   ;  }a   #  É   b  ¨   ó     ¨     v    >    ¨   +  v    Ú*‰  	¹  +ê    	s  ,ê   	  -ê   	  .  	  /‰  	   0‘   	ú  2™      ™  v   
 ê   ª  
v   ¿ Ú6\  	B  7   	1  8õ   	¯  9õ   	Û  :  	V  ;õ   	‡  <õ   	z  =\  	¹  @ê   	s  Aê   	  Bê   	  C  	  D‰  #	   E‘   .	ú  Gl  6    l  v    ê   }  
v   £ Ú(  Õ  3+  N  Hª   :
   j  	  j   	Z  ‘   	K	  õ   	Ñ  ê   	ì  õ   	¤	  ê   	–	   õ   	3	  !õ   	¾
  "ê   	u  #õ   	Æ
  $õ   	É  %õ   	€	  &  	=	  '   u I}  $t	  Kõ   ş ê   z  v    Ç  ª  n ß    	ƒ  ª  	‰  °   z     Á  
v   ÿ Ÿ  0   ä       T   r  @%  	#  &Ÿ   	Z  'Ô   	Ÿ  )Á  	Ì  *0   	h  +a   	•  ,†   	À  -†   fat /ß   	:  0ß   $	‰  1ß   ,end 2ß   4	Ï  4ª  < a   Ÿ  Ô   }   %   ß      +   >   À  _p  À   ê   a  .E   á  _p .á   õ   ¨  80     _p 8         ¯¡©  œ  %  Ÿ  ‘ Z  Ô   ‘fs   +  bs   U  i a   ~  Ï  ¾     ë  ¾   ½  è  ¾   Ü  .  ¾        ¾   š  kB£ç  ?¢   <Õ  ÷  A   ç  o¢   Cò  ÷  V    ¿¡O   ë¡[   K£f   ä    !  qX£   œO  "fs q  ‘  h£r  #w£f   $$  $  	Ò%®  ®  L$u  u  	ã%h  h  G 9   a  Æ  ö  d  w£ß      ,  Ø0   +   D     int A            :   ø   ¾	  &E   Á  0Œ   8   
  1>   ½	  30   ‘  :´   !   ;  }E   #  ©   *  ,   Î  !Æ      "E   4  #   Œ     7    b     ó  (     8  7    >  C     S  7    C   SØ  ª  TØ   Ü  U  æ  V  :  W  Ö  X8  ğ  Y    Z  é  [8  "  \  ¢  ]8     è  7   
 	Ç    
n Æ    ƒ    ‰     è  L   /  7   ÿ Ÿ  0   R       T   r  @%ï  #  &   Z  '»   Ÿ  )/  Ì  *0   h  +E   •  ,v   À  -v   
fat /Æ   :  0Æ   $‰  1Æ   ,
end 2Æ   4Ï  4  < E     »     %   Æ    ï  ¨  80   0  _p 80   8  a  .>   Q  _p .Q     À  v   w£ß   œ÷  fs ÷  ‘   v   ‘ª  ı  ‘1    ‘dep 
  k    E   ‰  s Æ   ñ  £  Å£  İ£&  D¤1   R    Ñ   S  g  g  :®  ®  L,	  ,	  A6  6  A ­   Ä  Æ  U  d  V¤ä   ù  ,  Ø0   +      8      &   :   ø   int     !   D  A   ¾	  Äa     ‘  :o   ;  }a   #  ˜   Ç  é   n ®    ƒ  é   ‰  ï    	¹   
      v   ÿ Ÿ  0   #       T   r  @%À  #  &Ş   Z  '£   Ÿ  )   Ì  *0   h  +a   •  ,†   À  -†   fat /®   :  0®   $‰  1®   ,end 2®   4Ï  4é   < a   Ş  £   }   %   ®    	À  h  6V¤.   œ-  fs 6-  ‘ ls 8é     N  8é   :  x¤˜   	#  ®  }   „¤¶   œ˜  fs -  ‘ n ®   ‘ls é   c  À¤¤  Ò¤ä  Ş¤¤  ¥˜   u  u  ã$  $  Ò Ç     Æ    d  :¥5    !   +   int ,  Ø,            :   ø   ¾	  &3   Á  0~   8   
  1      ½	  3,   ‘  :%   ;  }3   #  ¢   D  ó  Õ   s   å   Ã    >  ğ   s      Ã    A   Ç  7  n ¸    	ƒ  7  	‰  =   
     N  Ã   ÿ Ÿ  ,   q       T   r  @%  	#  &.   	Z  '­   	Ÿ  )N  	Ì  *,   	h  +3   	•  ,h   	À  -h   fat /¸   	:  0¸   $	‰  1¸   ,end 2¸   4	Ï  47  < 3   ,  ­   ,  :   ¸    
  a  .   O  _p .O   
Ê   ¨  8,   p  _p 8p   
å   g  ¸   :¥N   œ­  fs ­  »  ¬  h   æ   
³  q  6  -¸   ˆ¥ç  œ³  fs -³  ‘ s .¸     ¬  0h   B  q  0h   k  g  1—   Í  £  2¸   -  ‡  3¹  m  }  4—   ¡  rs 5¸   ¼  4   §   ml  D   U  4§   z…  e   u¦¿  ¨¦¿  ù¦¿  -§¿  b§v   
q  
s   ®  ®  L p      =  ğ   ../sysdeps/i386/crtn.S /glibc-tmp-ec9b8d6964164aa7972612c322780d61/glibc-2.23/csu GNU AS 2.26 € %   %  $ >  $ >  4 :;I?  & I    U%   %U   :;I  $ >  $ >      I  :;   :;I8  	& I  
 :;I8   :;  I  ! I/  &   I:;  (   .?:;'‡@—B   :;I  ‰‚ 1  .?:;'‡@—B  .?:;'I@—B   :;I  4 :;I  4 :;I  4 :;I   :;I  4 :;I  ‰‚•B1  Š‚ ‘B  4 :;I  U     !4 :;I  "4 :;I  #4 :;I  $! I/  % <  &4 :;I?<  '!   (4 :;I?<  )4 :;I?  *. ?<n:;  +. ?<n:;  ,. ?<n:;n  -. ?<n:;n   %  $ >  $ >      I  & I   :;I  I  	! I/  
&   :;   :;I8  ! I/  :;   :;I  :;   I8   :;I8  :;   :;I8   :;I8  I:;  (   .:;'I    :;I  .?:;'@—B   :;I   :;I    4 :;I  4 :;I     !.:;'I   " :;I  # :;I  $4 :;I  %  &.?:;'I@–B  ' :;I  (1XY  ) 1  *4 1  +4 1  ,‰‚ 1  -1XY  .!   /4 :;I?<  0. ?<n:;   %   :;I  $ >  $ >      I  :;   :;I8  	 :;I8  
 :;  I  ! I/  & I   :;I8  :;  ! I/  :;   :;I  :;   I8   :;I8  .:;'I    :;I  .:;'I    :;I  .:;'   4 :;I  4 :;I  
 :;    .?:;'I@—B    :;I  ! :;I  "4 :;I  #4 :;I  $1XY  % 1  & 1  '1RUXY  (  )4 1  *
 1  +U  ,1XY  -  .‰‚ 1  /4 :;I?<  0!   1. ?<n:;n  2. ?<n:;   %   :;I  $ >  $ >      I  :;   :;I8  	 :;I8  
 :;  I  ! I/  & I   :;I8  I:;  (   .?:;'‡@—B   :;I   :;I  ‰‚ 1  .?:;'@—B  4 :;I  
 :;  .?:;'I@—B  4 :;I?<  ! I/  4 :;I?  4 :;I?  . ?<n:;  . ?<n:;n  . ?<n:;   %   :;I  $ >  $ >   I  &   .:;'I    :;I  	& I  
4 :;I  4 :;I  .:;'   .:;'@—B   :;I  4 :;I  4 :;I  1XY   1  1XY  .?:;'I@—B   :;I   :;I  4 :;I    ‰‚ 1  ‰‚1  Š‚ ‘B  I  ! I/  .?:;'@—B  ‰‚•B1     !4 1  " 1  #4 1  $1RUXY  %U  &4 :;I?  '. ?<n:;   %  I  ! I/  $ >  4 :;I?  & I  $ >   %  I  ! I/  $ >  4 :;I?  4 :;I?  & I  $ >   %   :;I  $ >  $ >     I  ! I/  :;  	 :;I8  
! I/  :;   :;I  :;   :;I8   :;I8   I  I:;  (   :;  'I   I  .:;'I    :;I  .?:;'I@—B   :;I  4 :;I  4 :;I  4 :;I  
 :;  1XY   1   ‰‚ 1  !.?:;'@—B  " :;I  #‰‚ •B1  $. ?<n:;  %. ?<n:;   %   :;I  $ >  $ >  :;   :;I8  I  ! I/  	:;  
 :;I8   I  ! I/  I:;  (   'I   I     .:;'I    :;I  .?:;'I@—B   :;I   :;I  4 :;I  4 :;I  ‰‚ 1  &   . ?<n:;   %   :;I  $ >  $ >     :;   :;I8   :;I8  	 I  
I  ! I/  I:;  (   :;  'I   I  .?:;'@—B   :;I  4 :;I  4 :;I  ‰‚ 1  .?:;'I@–B  . ?<n:;   %  $ >  $ >   :;I  I  ! I/  :;   :;I8  	 :;I8  
 I  ! I/  I:;  (   :;  'I   I     .:;'I    :;I  .?:;'I@—B   :;I   :;I  & I   :;I  4 :;I  4 :;I  1XY   1  ‰‚ 1  ‰‚ •B1  . ?<n:;    U%   R    .   û      ../sysdeps/i386  start.S     û<3!4=%" YZ!"\[ #       û       init.c     i    -   û      ../sysdeps/i386  crti.S     °ˆ>"Ùg//   ‘Á    ªÑ != ø   †  û      /usr/lib/gcc/i586-slackware-linux/5.3.0/include /usr/include/bits /usr/include/sys /usr/include ../libfat ../libinstaller  syslinux.c    stddef.h   types.h   types.h   time.h   stat.h   stdint.h   stdio.h   libio.h   libfat.h   syslxopt.h   syslxfs.h   setadv.h   syslinux.h   stdlib.h   errno.h   string.h   unistd.h   <built-in>    fcntl.h   stat.h     *’1gƒ¾gX&¥“q•KuŸYt[-=u=O"¬f>×=;_X“q•KuŸYt[-=u=O  0‹€fXŸv »®   ‘ ‘	fÉ;/LXå;gK Õ£ gi½÷Y– ‘ eL’‘ t[
"ó «ø‘5Ë½;/P Ã ;w¡ t|g=‘-gó-/Ë;/uÉÊI! “k)ô[9 “ ƒ ) !$ÜÖkfY9Z ggŸ¯Xt.Y/KgKuK×ƒ–K kä<KKËK…å„ tui’É[õ Ju˜İççæ×]    y   û      ../libinstaller /usr/include  fs.c   syslxint.h   stdint.h   syslxfs.h   syslinux.h   string.h     Â“ Xg]»;/ó]u;KWgW=Lâ JnKW…KujT º®KW!~¬1ƒÊ“+vŸ­u#G1¯WˆçYWzº	f[W¯ŸuôKôW„M¡	äVŸe
È+gd¬wttuÿLVQ+g
    ï   û      ../libinstaller /usr/lib/gcc/i586-slackware-linux/5.3.0/include /usr/include/bits /usr/include  syslxmod.c   syslxint.h   stddef.h   types.h   libio.h   stdint.h   syslinux.h   stdio.h   <built-in>    stdlib.h     C—å ÛaAê ”ƒ_X'òg<<g<fbJXiV.0òP<0<P<*<JfdÁ ò®” H-£=h,ÖoXg>,„=DfÖkJSwf.(JfÖÊ J´<Ğ <°JÌ tPä1fO<1fO‚4º/Ÿ;KI/K!¼@gŸ;KI/Kç®<Ù t- Y Y s	<<â <­XÔ < Å   û   û      ../libinstaller /usr/lib/gcc/i586-slackware-linux/5.3.0/include /usr/include/bits /usr/include  syslxopt.c   stddef.h   types.h   libio.h   getopt.h   syslxopt.h   stdio.h   setadv.h   syslxcom.h   stdlib.h   <built-in>      AšË X=òmtWf
Öf Ö X "ƒNYMe¬XäXiu$>,ŸA.;KŸDX(ÖXKŸŸSŸ^ó;Y»İó;Yåi¾ŸZŸZŸ[Ÿ]Kg\Ÿ[ó;YZŸ`ŸZŸZŸZYKŸZi¼­¢0‘»æzMq#/ô™P»":‡Ÿ»":‰	 R   »   û      ../libinstaller /usr/lib/gcc/i586-slackware-linux/5.3.0/include /usr/include /usr/include/bits  setadv.c   syslxint.h   stddef.h   stdint.h   string.h   errno.h     ›Ÿ)'yXJ9.Of Y ;¤+fUÈ‘M¿­X°—:]=vM[NçM/k.tgŸXg[=;/hŸ;/?ic1»W/ZmJ‚…",LV>u/;XXp<¤;¬ƒntrÈs¬ƒ‘LgL ;    5   û      ../libinstaller  bootsect_bin.c    :    4   û      ../libinstaller  ldlinux_bin.c    A   Ó   û      ../libfat /usr/lib/gcc/i586-slackware-linux/5.3.0/include /usr/include/sys /usr/include  open.c   ulint.h   stddef.h   types.h   stdint.h   libfat.h   fat.h   libfatint.h   stdlib.h     ¯¡—‘Ë <µ.†;u/h­¯¾ Ç	ÖH;=?I@õGh»=xJf¾F\8@w@»>d>0-ugƒuK„;yh…g„²»/…t=ggI õ    ¼   û      ../libfat /usr/lib/gcc/i586-slackware-linux/5.3.0/include /usr/include  searchdir.c   stddef.h   stdint.h   libfat.h   ulint.h   fat.h   libfatint.h   string.h     w£“9i½9?’»„É;/•=g×>iè…n<‚c X    À   û      ../libfat /usr/lib/gcc/i586-slackware-linux/5.3.0/include /usr/include/sys /usr/include  cache.c   stddef.h   types.h   stdint.h   libfat.h   libfatint.h   stdlib.h     V¤6X?= v L ; = NVX“ <K‘ €^É;/K‘Ø=-N)‘x;/;>>/ "   ¦   û      ../libfat /usr/lib/gcc/i586-slackware-linux/5.3.0/include /usr/include  fatchain.c   ulint.h   stddef.h   stdint.h   libfat.h   libfatint.h     :¥fgK>K„;=- .[Ÿ	XÂ/jg¡®ª>u® ½¯0:00K®1k7AAK®xfR–qY\y0ƒFt<fMy>ƒCt?f>Z´‘sU\ U    -   û      ../sysdeps/i386  crtn.S     Øˆ'=!  ª,=! long long int short unsigned int long long unsigned int unsigned char GNU C11 5.3.0 -march=i586 -mtune=i686 -mpreferred-stack-boundary=4 -g -O3 -std=gnu11 -fgnu89-inline -fmerge-all-constants -frounding-math -ftls-model=initial-exec _IO_stdin_used short int init.c /glibc-tmp-ec9b8d6964164aa7972612c322780d61/glibc-2.23/csu sizetype __off_t pwrite64 _IO_read_ptr _chain st_ctim install_mbr __u_quad_t uint64_t _shortbuf ldlinux_cluster update_only libfat_searchdir VFAT MODE_SYSLINUX done _IO_buf_base fdopen secp errmsg BTRFS mtc_fd syslinux_adv libfat_sector_t __gid_t intptr_t st_mode mtools_conf setenv program libfat_clustertosector __mode_t set_once bufp _IO_read_end _fileno dev_fd _flags __builtin_fputs __ssize_t _IO_buf_end _cur_column syslinux_ldlinux_len __quad_t _old_offset tmpdir asprintf count syslinux_mode pread64 xpwrite st_blocks st_uid _IO_marker /tmp/syslinux-4.07/mtools ldlinux_sectors nsectors fprintf command stupid_mode sys_options ferror GNU C11 5.3.0 -mtune=pentium -march=i586 -g -Os _IO_write_ptr libfat_close _sbuf bootsecfile device directory syslinux_patch _IO_save_base __nlink_t __st_ino sectbuf _lock libfat_filesystem syslinux_reset_adv _flags2 st_size mypid perror getenv unlink fstat64 tv_nsec __dev_t tv_sec __syscall_slong_t _IO_write_end libfat_open heads _IO_lock_t _IO_FILE __blksize_t MODE_EXTLINUX stderr _pos parse_options target_file _markers __blkcnt64_t st_nlink __builtin_strcpy syslinux_make_bootsect __pid_t menu_save st_blksize timespec _vtable_offset syslinux.c exit NTFS __ino_t st_rdev usage long double libfat_xpread syslinux_ldlinux activate_partition argc __errno_location fclose open64 mkstemp64 __uid_t _next __off64_t _IO_read_base _IO_save_end st_gid __pad1 __pad2 __pad3 __pad4 __pad5 __time_t _unused2 die_err st_atim argv mkstemp status MODE_SYSLINUX_DOSWIN popen calloc st_dev libfat_nextsector _IO_backup_base sync st_mtim fstat raid_mode pclose patch_sectors fwrite secsize slash getpid force __ino64_t strerror syslinux_check_bootsect main _IO_write_base EXT2 bsUnused_6 bsTotalSectors ntfs_check_zero_fields clustersize bsMFTLogicalClustNr bs16 dsectors fatsectors bsOemName ntfs_boot_sector bsFATsecs bsJump bsMFTMirrLogicalClustNr retval check_ntfs_bootsect FATSz32 uint8_t bsHeads bsSecPerClust bsForwardPtr bsResSectors bsUnused_1 bsUnused_2 bsUnused_3 FSInfo bsUnused_5 memcmp bsSectors bsHugeSectors bsBytesPerSec bsClustPerMFTrecord get_16 bsSignature bsHiddenSecs ExtFlags bsRootDirEnts bsFATs rootdirents get_8 uint32_t bsMagic BkBootSec media_sig RootClus FSVer bs32 ../libinstaller/fs.c syslinux_bootsect uint16_t bsVolSerialNr check_fat_bootsect Reserved0 fs_type bsZeroed_1 bsZeroed_2 bsZeroed_3 fserr fat_boot_sector sectorsize bsClustPerIdxBuf bsZeroed_0 get_32 bsMedia bsSecPerTrack bsUnused_0 bsUnused_4 subvollen sectp subvol set_16 set_64 secptroffset checksum sect1ptr0 sect1ptr1 diroffset instance ../libinstaller/syslxmod.c adv_sectors epaoffset sublen syslinux_extent csum xbytes ext_patch_area dwords advptroffset subdir data_sectors raidpatch stupid nsect secptrcnt advptrs patcharea magic subvoloffset dirlen nptrs addr set_32 generate_extents maxtransfer offset_p long_only_opt ../libinstaller/syslxopt.c syslinux_setadv long_options has_arg name opt_offset short_options optarg OPT_RESET_ADV optind OPT_DEVICE OPT_ONCE modify_adv option flag optopt strtoul OPT_NONE getopt_long memmove ../libinstaller/setadv.c adv_consistent left ptag syslinux_validate_adv advbuf plen advtmp cleanup_adv syslinux_bootsect_len ../libinstaller/bootsect_bin.c syslinux_bootsect_mtime ../libinstaller/ldlinux_bin.c syslinux_ldlinux_mtime malloc read8 bpb_extflags le32_t ../libfat/open.c bpb_fsinfo read16 clustshift bsReserved1 bsBootSignature bsVolumeID barf fat_type read32 bpb_fsver bsDriveNumber libfat_sector fat16 bpb_rootclus minfatsize le16_t bsCode bsVolumeLabel nclusters FAT12 FAT16 readfunc rootdirsize rootdir bpb_fatsz32 fat32 FAT28 readptr le8_t libfat_flush free bpb_reserved bpb_bkbootsec endcluster bsFileSysType libfat_get_sector rootcluster clustsize ctime attribute caseflags atime ../libfat/searchdir.c dirclust nent clusthi clustlo libfat_direntry ctime_ms fat_dirent lsnext ../libfat/cache.c fatoffset nextcluster clustmask fsdata ../libfat/fatchain.c fatsect ’©’ ‘©’“ S        ’©’ ‘©’û’ V“W“ı’“ V“W“        ¾’Ø’ Pñ’“ P        “’©’ 0Ÿ©’ “ ‘\““ ‘\        “7“ ‘        C“\“ ‘\“¾“ S        C“\“ ‘\“®“ V“W“°“¿“ V“W“        q“‹“ P¤“·“ P        F“\“ 0Ÿ\“³“ ‘\·“Â“ ‘\        ş‹Œ PŒŒ uô¶ŒŒ PŒbŒ uô¶nŒT uô¶        û P PU_ P        İ‹æ‹ Pæ‹KŒ SnŒÖŒ SÛŒıŒ S        äŒ÷Œ P        ıŒ P3 S>• S        ª® P®¶ S»Î PÎJ S        8D PD„ V        Qt P“R“u‚ P“R“        ET uğ¶T^ s 3$uğ¶"Ÿ^l s3$uğ¶"Ÿzœ s 3$uğ¶"Ÿœ¢ t 3$uğ¶"Ÿ¢¦ t3$uğ¶"Ÿ        $3 P3T uğ¶        EP P        ET 0ŸTœ Sœ¢ t ¢¦ t        Œ´Œ P        … W        ½( uì¶HP uì¶        §± P±· p|Ÿ½ï Sï sŸ' SHP S        !' uè·Ÿ': S:H uì·ŸHx Px R“ pŸ“• R•  uğ¶ § pŸ§­ P­° pŸ°² P²¶ R¶¼ uğ¶¼Ã PÃÇ pŸÇÓ P        !5 uØWŸ56 W6H uØWŸ        :İ V        !H 1ŸH_ Qcj Qo© 0Ÿ©² Q²¼ 0Ÿ¼Ó Q            1    ‘ 1   @    P@   _    ‘            1    ‘         6   @    P@   [    ‘         ƒ   º    Pº   ¸  	 v”
ÿÿŸ  #  	 v”
ÿÿŸ        k   ~   V~     ‘         ¶   é    V        é      ‘        é      V        é      
 Ÿ             Q“S“  !   Q“S“        9  D   ‘PD  K   P“R“K  S   q ÷3÷%õ %Ÿ{     ‘P  Š  
         Š     ‘X÷3÷%‘Pö%Ÿ  ¸   v”÷:÷%‘Pö%Ÿ        +  c   ‘@c  l   Q“S“n  ¿   Q“S“        {  ¿   õ,‘O”÷:÷%÷,÷%Ÿ        c  f   Pf  i   pqŸi  ¸  	 v”
ÿÿŸ        õ      Q  ¸   v”ÿŸ          w   ‘          w   V            {    ‘ {   €    Q€   ó   ‘¨ó  ö   ‘             D   ‘ó  ö   ‘            b   ‘s  —   ‘ó  ö   ‘        <   ó   S        /   Ò   S        &   á    Pá   ó   ‘H#Ÿó  ö   Pö  ş   ‘H#Ÿ        Ò  Ù   ş²>ŸÙ  ó   R        Ò  Ù   0ŸÙ  ë   P        –   ²    W²   ó   ‘D        ¿   Æ    ‘\#”
ÿÿŸÆ   Ê    QÊ   Ë    ‘\#”
ÿÿŸÜ   ß    Qß      ‘\#”
ÿÿŸ        <   U    sŸU   [    rŸ[   e    ‘\#Ÿe   }    ‘\#Ÿ}       ‘\#Ÿ¯   õ   ‘\#
Ÿõ  b   ‘\s  ‡   ‘\#Ÿ·  Ë   ‘\#Ÿ        U   e    v         e   u    v        }       
ÍŸ        –   š    p~Ÿ        –   š    sŸ        š        2Ÿ        š        s
Ÿ            £    W            £    sŸ        ©   ¯    1Ÿ        ©   ¯    sŸ        ¯   õ   ‘\#
Ÿõ  b   ‘\s  ‡   ‘\#Ÿ·  Ë   ‘\#Ÿ        Ü   á    p}Ÿá      ‘H1Ÿ  H   q  ‘H"ŸH  Ã  	 ‘L ‘H"ŸÃ  ×  
 ‘H‘L2Ÿß  ì   q  ‘H"Ÿì  õ  	 ‘L ‘H"Ÿ        Ü      ‘¨  "   q3$v "Ÿ"  H   q3$v "ŸH  ×   ‘L#3$v "Ÿß  ì   q3$v "Ÿì  õ   ‘L#3$v "Ÿ        Ü   ß    Qß      ‘\#”
ÿÿŸ        Ü   ¦   ‘X¦  «   w
Ÿ«  ¯   ‘X#
Ÿ¯  õ   ‘X        Ü      
 €Ÿ  J   RJ  Ã   ‘¼Ã  ×   ‘L#A9$Ÿß  é   Ré  b   ‘¼s  ó   ‘¼        Ü      
 €Ÿ  ±   ‘@±  Ã   QÃ  ß   ‘¼ß  õ   ‘@        8  =   q 3$v "#“W“=  H   q 3$v "#“q 3$v "#“H  Ÿ   ‘L3$v "#“‘L3$v "#“Ÿ  ±  
 ‘¸“‘´“±  Ã   ‘L3$v "#“‘L3$v "#“        Ü     
           Ã   ‘PÃ  ß  
 ‘¸“‘´“ß  õ   ‘P        Ü      0Ÿ  ´   P´  Ã   wŸÃ  È   WÈ  õ   P        P  R   RR  Ã   ‘°        ”  ¢   ‘P        ”  ¢   ‘X        ¢  ¦   P        ¢  ¦   ‘X#Ÿ        ã  ñ   ‘P        ã  ñ   ‘X        ñ  õ   P        ñ  õ   ‘X#Ÿ        õ  b   ‘\s  ‡   ‘\#Ÿ·  Ë   ‘\#Ÿ             V“W“        ,  8   V“W“        Q  b   Qs  ‡   Q        ¤  Ë   Q        Ë  Ò   0Ÿ        Ë  Ò   sŸ        è  î   R        è  î   sŸ        [     PŸ  ï   Pù     P"  •   PÇ  Ç   P  Q   Pm  r   P™  ­   P·  Ú   PŞ  ã   Pí     P6  >   P        §  
   0Ÿ
     	ÿŸ  8   SN  Q   	ÿŸQ  W   SW  Z   P                P   @    V@   D    óPŸ               8Ÿ   *    P               g£   D    R                ¥/-ZŸ                P        $   -    R        $   -    vŸ        -   7    d¿(İ        -   7    vüŸ        t   z    ‘à{Ÿz   ã    Só   ş    sŸş      P  E   S        t       
ôŸ   ¸    R¸   Ä    ‘Ü{Ä   ã    Ró      R  8   R=  E   R           ¤    Q¤   ¥    s Ä   ã    Qó   ù    Qù   û    s =  E   Q        —   «    PÄ   Ü    PÜ   ã   
 s”ÿ#Ÿó     
 s”ÿ#Ÿ=  E   P        m  ·   ‘ ·     P     ‘      P     ‘         u     ‘              R             Q        ·  Õ   p€ŸÕ  î   V        Ü  î   R        Ü  î   Q                0Ÿ       P   ¥   S        <   ƒ   Pˆ     P“  ›   P        c   t    ‘\   “   ‘\        Œ   Ê    VÊ   “   ‘P        ¼   Ã    WÃ   “   ‘X        E  G   RX  Z   Re  r   Rr  u   r 9%Ÿu  “   R        á   ö    p”
ÿÿ5$#ÿ9&Ÿ           “    p Ÿ        À   Æ    p$Ÿ        S   Y    PY   Ò    S        \   \    R\   ˜    ‘T˜   ¢    R¢   ­    ‘T­   µ    Rµ   ¸    ‘T¸   Ì    RÌ   Ò    ‘T# Ÿ               ‘X$   ß    ‘X           !    P"   )    S)   .    P               P   )    S)   .    P        C   S    PS   X    ptŸX   i    Po   {    PŠ       P   «    R«   Ü    ‘X            I    ‘ I   J    SJ   N    ‘                 ‘   4    Q4   :    pŸ        N   “    ‘“   ¥    P“R“®   -   ‘        ô   –   S¤  ¦   S×  Ú   S        Y  [   p ÿŸ[  Œ   ‘P”ÿŸŒ     R  ¤   PĞ  ×   P     P  '   ‘        &  I   WI  O   RO  Y   wŸY     W  –  
 s 1&s "#Ÿ¦  Ì   SÚ      S        ¦  ¬   s 9%÷,÷%‘\#ö%"ŸÚ  Ş   s 9%÷,÷%‘\#ö%"Ÿ        ;  U   Pn     P¿  Ğ   Pó     P        Q   R   	 ‘\#1Ÿ        Ç   Y   ‘P¤     ‘P         ÿÿÿÿ    °ˆÎˆ ‘$‘ ªª        ¥¨ª	        *’Â“0‹û        O   R   U   [   _   e              “   –   š           C  ¦  «  Ã          ø  û  ÿ                  $          ·  Ï  Ü  î          ÿÿÿÿ    Øˆİˆªª                            T          h          ˆ          Ì‚          l…          Ú†          0‡          p‡          ˜‡     	     °ˆ     
     àˆ           ‹          0‹           ª           ª          °¶          œ·           Ï          (Ï          0Ï          4Ï          üÏ           Ğ           Ğ          @c                                                                                                                      !             ñÿ            ñÿ    Ï      !   (Ï      /   0Ï      <   0‘      >   `‘      Q    ‘      g   dc     v   hc     „    ’                  ñÿ   $Ï         H¼      «   0Ï      ·   Ğ©      Í            ñÿØ   €c     å            ñÿê   ÀĞ)     õ            ñÿ            ñÿ           ñÿ  ›ŸD                 ñÿ'           ñÿ3           ñÿ;           ñÿF           ñÿU           ñÿ             ñÿc   Ï       t  4Ï      }   Ï         °¶       £   Ğ      ¹  ©     É  C“     Ñ             ã              ÿ   ‘        Ğ         Â“_     ,  @c     >             Q             e             u  ¡§     ‹  è³     –             ¨  ˆ¥ç    º  @c      Á             Ó  r›v    á   e     î                w£ß       p§ª   Ã   ª        Dc     ,             =  „¤¶     O   ©0    W  X£     d  :¥N     {  ¨¶     ’             ¤  @Ñ     ¶  Hc     È             Ú             ì               @Ó       @µ     !             3  ,Ï     @             R  è       e             w             Œ                Ğ      «             ½             ²  ’     Ñ              à             ğ  ¤Ğ     ı                          !  $ª     0  €e     8             O  `µ@    \  U’;     d             w             ‰             ¦             ¹  V¤.     Æ  ¬¶     Û   ©e     ë  ¤¶     o   i                   ¤  û         ª     $             8  ¯¡©    D  @c      P  ßŸ	    `  0‹Ë    e  Aš1    k  *’+     o              ƒ             –  C—ş    %             ¥  „e     «  “4     ¹  @c     Å              ß   ¶     ÷  `c     	  !”"    !             å  °ˆ     
 2             C   Ñ<     G             W              init.c crtstuff.c __CTOR_LIST__ __DTOR_LIST__ __JCR_LIST__ deregister_tm_clones __do_global_dtors_aux completed.6563 dtor_idx.6565 frame_dummy __CTOR_END__ __FRAME_END__ __JCR_END__ __do_global_ctors_aux syslinux.c sectbuf.4461 fs.c fserr.2899 syslxmod.c syslxopt.c setadv.c cleanup_adv open.c searchdir.c cache.c fatchain.c bootsect_bin.c ldlinux_bin.c __init_array_end _DYNAMIC __init_array_start __GNU_EH_FRAME_HDR _GLOBAL_OFFSET_TABLE_ __libc_csu_fini xpwrite open64@@GLIBC_2.1 _ITM_deregisterTMCloneTable __x86.get_pc_thunk.bx syslinux_make_bootsect stderr@@GLIBC_2.0 memmove@@GLIBC_2.0 pwrite64@@GLIBC_2.1 free@@GLIBC_2.0 syslinux_validate_adv modify_adv ferror@@GLIBC_2.0 libfat_nextsector _edata fclose@@GLIBC_2.1 parse_options syslinux_adv memcmp@@GLIBC_2.0 libfat_searchdir __divdi3 optind@@GLIBC_2.0 popen@@GLIBC_2.1 libfat_get_sector fstat64 libfat_close libfat_clustertosector syslinux_ldlinux_mtime unlink@@GLIBC_2.0 syslinux_bootsect optopt@@GLIBC_2.0 perror@@GLIBC_2.0 fwrite@@GLIBC_2.0 __fxstat64@@GLIBC_2.2 syslinux_ldlinux short_options strcpy@@GLIBC_2.0 __DTOR_END__ getpid@@GLIBC_2.0 syslinux_reset_adv getenv@@GLIBC_2.0 mkstemp64@@GLIBC_2.2 malloc@@GLIBC_2.0 __data_start system@@GLIBC_2.0 strerror@@GLIBC_2.0 __gmon_start__ exit@@GLIBC_2.0 __dso_handle fdopen@@GLIBC_2.1 pclose@@GLIBC_2.1 _IO_stdin_used program getopt_long@@GLIBC_2.0 long_options die_err strtoul@@GLIBC_2.0 setenv@@GLIBC_2.0 __libc_start_main@@GLIBC_2.0 fprintf@@GLIBC_2.0 libfat_flush syslinux_ldlinux_len __libc_csu_init syslinux_bootsect_len __errno_location@@GLIBC_2.0 _fp_hw asprintf@@GLIBC_2.0 libfat_open __bss_start syslinux_setadv main usage die _Jv_RegisterClasses pread64@@GLIBC_2.1 syslinux_patch mypid libfat_xpread __TMC_END__ _ITM_registerTMCloneTable syslinux_bootsect_mtime optarg@@GLIBC_2.0 syslinux_check_bootsect fputs@@GLIBC_2.0 close@@GLIBC_2.0 opt sync@@GLIBC_2.0 calloc@@GLIBC_2.0  .symtab .strtab .shstrtab .interp .note.ABI-tag .hash .dynsym .dynstr .gnu.version .gnu.version_r .rel.dyn .rel.plt .init .plt.got .text .fini .rodata .eh_frame_hdr .eh_frame .ctors .dtors .jcr .dynamic .got.plt .data .bss .comment .debug_aranges .debug_info .debug_abbrev .debug_line .debug_str .debug_loc .debug_ranges                                                   TT                    #         hh                     1         ˆˆ  D               7         Ì‚Ì                 ?         l…l  m                 G   ÿÿÿo   Ú†Ú  T                T   şÿÿo   0‡0  @                c   	      p‡p  (                l   	   B   ˜‡˜                u         °ˆ°  -                  p         àˆà  @                {          ‹                     „         0‹0  Ğ                 Š          ª *                              ª *                    ˜         °¶°6  ì                  ¦         œ·œ7  °                 °          Ï ?                    ·         (Ï(?                    ¾         0Ï0?                    Ã         4Ï4?  È                         üÏü?                   Ì          Ğ @  ˜                 Õ          Ğ @   ’                  Û         @c@Ó  `                  à      0       @Ó                   é              XÓ  è                 ø              @Õ  bB                              ¢ °                              R* –                      0       è9 «                )             “J Ü                 4             pc                                9v B                               €d P
  $   F         	              Ğn i                                                                                                                                                                                                             ./.wifislax_bootloader_installer/mbr.bin                                                            0000644 0000000 0000000 00000000670 12721137577 017375  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   3ÀúØĞ¼ |‰æWÀûü¿ ¹ ó¥ê  RR´A»ªU1É0öùÍrûUªuÑés	fÇ´BëZ´Íƒá?Q¶Æ@÷áRPf1Àf™èf è!Missing operating system.
f`f1Ò» |fRfPSjj‰æf÷6ô{ÀäˆáˆÅ’ö6ø{ˆÆáA¸Šú{ÍdfaÃèÄÿ¾¾}¿¾¹  ó¥Ãf`‰å»¾¹ 1ÀSQö€t@‰ŞƒÃâóHt[y9Y[ŠG<t$<u"f‹Gf‹VfĞf!Òuf‰Âè¬ÿrè¶ÿf‹Fè ÿƒÃâÌfaÃèb Multiple active partitions.
f‹DfFf‰Dè0ÿr>ş}Uª…ÿ¼ú{Z_úÿäè Operating system load error.
^¬´Š>b³Í<
uñÍôëı                                                                                                            ./.wifislax_bootloader_installer/syslinux64.com                                                     0000644 0000000 0000000 00000341300 12721137577 020671  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   ELF          >    ğ@     @       €¹         @ 8 	 @ % "       @       @ @     @ @     ø      ø                   8      8@     8@                                          @       @     ü>      ü>                    (N      (N`     (N`     Ø•      8œ                    PN      PN`     PN`                              T      T@     T@                            Påtd   ğ8      ğ8@     ğ8@     ì       ì              Qåtd                                                  Råtd   (N      (N`     (N`     Ø      Ø             /lib64/ld-linux-x86-64.so.2          GNU                   %   ,       $                          !   +       *             (      %      &                             )       '   "                                                                                                        	                                               
               #                                        Œ                      !                     H                      %                      1                                                                                      2                      m                            ä`            ¯                      ¡                      »                      g                      n                                           `                      É                      A                      &                     “     ä`            Ó                      M                      ¨     ä`            ï                      ê                      |                      Û                      ƒ                      Y                      â                      9                      ,                                            \                      t                      „                                            Â                      p                      ø                      š      ä`             libc.so.6 strcpy exit optind perror unlink popen getpid pread64 calloc __errno_location open64 memcmp fputs fclose strtoul malloc asprintf getenv optarg stderr system optopt getopt_long pclose fwrite mkstemp64 fprintf fdopen memmove sync pwrite64 strerror __libc_start_main ferror setenv free __fxstat64 _ITM_deregisterTMCloneTable __gmon_start__ _Jv_RegisterClasses _ITM_registerTMCloneTable GLIBC_2.2.5                                                                ui	   Š      àO`                   èO`                   ğO`        $           øO`        )            ä`                   ä`                   ä`                    ä`        +           P`                    P`                   (P`                   0P`                   8P`                   @P`                   HP`                   PP`        	           XP`        
           `P`                   hP`                   pP`                   xP`                   €P`                   ˆP`                   P`                   ˜P`                    P`                   ¨P`                   °P`                   ¸P`                   ÀP`                   ÈP`                   ĞP`                   ØP`                   àP`                   èP`                    ğP`        !           øP`        "            Q`        #           Q`        %           Q`        &           Q`        '            Q`        (           (Q`        *           HƒìH‹İA  H…Àtè[  è	  è¡  HƒÄÃ            ÿ5ÒA  ÿ%ÔA  @ ÿ%ÒA  h    éàÿÿÿÿ%ÊA  h   éĞÿÿÿÿ%ÂA  h   éÀÿÿÿÿ%ºA  h   é°ÿÿÿÿ%²A  h   é ÿÿÿÿ%ªA  h   éÿÿÿÿ%¢A  h   é€ÿÿÿÿ%šA  h   épÿÿÿÿ%’A  h   é`ÿÿÿÿ%ŠA  h	   éPÿÿÿÿ%‚A  h
   é@ÿÿÿÿ%zA  h   é0ÿÿÿÿ%rA  h   é ÿÿÿÿ%jA  h   éÿÿÿÿ%bA  h   é ÿÿÿÿ%ZA  h   éğşÿÿÿ%RA  h   éàşÿÿÿ%JA  h   éĞşÿÿÿ%BA  h   éÀşÿÿÿ%:A  h   é°şÿÿÿ%2A  h   é şÿÿÿ%*A  h   éşÿÿÿ%"A  h   é€şÿÿÿ%A  h   épşÿÿÿ%A  h   é`şÿÿÿ%
A  h   éPşÿÿÿ%A  h   é@şÿÿÿ%ú@  h   é0şÿÿÿ%ò@  h   é şÿÿÿ%ê@  h   éşÿÿÿ%â@  h   é şÿÿÿ%Ú@  h   éğıÿÿÿ%Ò@  h    éàıÿÿÿ%Ê@  h!   éĞıÿÿÿ%Â@  h"   éÀıÿÿÿ%r?  f        AWAVAUATUSHì¸$  ‰|$H‰4$èşÿÿH‹4$‰ Õ  1Ò‹|$H‹H‰ˆÕ  èy  Hƒ=A   u1ö¿@   èA  Hƒ=Å@   u&ƒ=Ì@   uHƒ=Ê@   uƒ=É@   
Hƒ=ß@   tH‹5Ó  ¿L+@ èìıÿÿé†   ¿“+@ èıÿÿH‹=¦@  H…ÀH‰Å¸G+@ ¾   HDè1Àè‹şÿÿ…À‰ÃyH‹=~@  é¦   Ht$ ‰ÇèM  …Àxäƒ=z@   u9‹D$8% ğ  - `  © Ğÿÿt$H‹D@  H‹=Ò  ¾š+@ 1ÀèÑıÿÿ¿   è—şÿÿ‹)@  º   ¾@ä` ‰ßèò  1ö¿@ä` è1  H…ÀH‰Ç…Ş   H|$1ÀH‰ê¾×+@ èÔıÿÿ…Àx
H‹|$H…ÿuH‰ïèv  è9ıÿÿ…Àx?¾ò+@ ‰Çè™ıÿÿH…ÀH‰Åt+Hc"Ô  D‹«?  H‰Ç‰Ù¾ô+@ 1Àè2ıÿÿH‰ïèJüÿÿ…ÀtH‹|$ë¬H‰ïègüÿÿ…ÀuíH‹t$º   ¿T,@ è/üÿÿ…ÀtH‹=ÄÓ  èıÿÿéÿÿÿ¿`æ` èT  ¿],@ èFüÿÿ¾ò+@ ¿‰,@ èWıÿÿH…ÀI‰Äu
¿­,@ è•  D‹-*&  H‰Á¾   ¿ T` L‰êL‰íèvıÿÿI9ÅuÒL‰áº   ¾   ¿`æ` èZıÿÿH=   u³L‰çèêûÿÿ¨u§¶Ä…Àu Åÿ  ¾   E1äÁí	‰ïè'üÿÿHcó¿#@ I‰Æèf  1ÉI‰Åº±-@ 1öH‰Çè²  L‰ï‰Æè0  H…ÀE‰çtD9å~H‰ÆL‰ïK‰æèC  IÿÄëßL‰ïE1äA½ T` èd  L‹8>  ‹>  E1É‹>  D‰şL‰÷èá  ¨ÿ  Áı	D9å~,K‹æ‹>  L‰îº   ‰ßIÿÄIÅ   HÁá	HÁèV  ëÏH‹-İ=  H…í„X  H¼$°   ¾Ê,@ èzúÿÿHŒ$°   H¼$´   ¸   HÁğ  ŠU „Òtp€ú/t€ú\u…À¸   uXëG€ú't1À€ú!u;1ÀH9ÏsCHWÆ'H9Ês4HWÆG\H9Ês'HW@Šu H9Ê@ˆwsÆG'HƒÇëH9Ïs
ˆHÿÇëH‰×HÿÅë‰…ÀuÆ/HÿÇ¾Ï,@ èÓùÿÿH”$°   H¼$°  ¾Ü,@ 1ÀègûÿÿH¼$°  è
úÿÿH”$°   H¼$°  ¾ü,@ 1Àè>ûÿÿH¼$°  èáùÿÿ¨u¶Ä…ÀtH‹/Ñ  H‹=Ï  ¾-@ 1ÀèLúÿÿë&H¼$°  H”$°   ¾g-@ 1ÀèîúÿÿH¼$°  ë¿G-@ èŠùÿÿ¨u¶Ä…ÀtH‹ØĞ  H‹=±Î  ¾{-@ 1ÀèõùÿÿH‹|$èëøÿÿ‹M<  º   ‰ß¾@ä` è  ¾   ¿@ä` èş  ‹'<  º   ¾@ä` ‰ßèv  ‰ßèGùÿÿèÂùÿÿHÄ¸$  1À[]A\A]A^A_Ãf.„     @ 1íI‰Ñ^H‰âHƒäğPTIÇÀ *@ HÇÁ0*@ HÇÇ€@ èùÿÿôfD  H=ÙÍ  HÙÍ  UH)øH‰åHƒøvH‹9  H…Àt	]ÿàfD  ]Ã@ f.„     H=™Í  H5’Í  UH)şH‰åHÁşH‰ğHÁè?HÆHÑştH‹i9  H…Àt]ÿàf„     ]Ã@ f.„     €=qÍ   ubUHw7  H‹hÍ  H‰åATSHk7  L%\7  H)ÓHÁûHƒëH9Øs@ HƒÀH‰5Í  AÿÄH‹*Í  H9Øråèÿÿÿ[A\]ÆÍ  óÃ H=!7  Hƒ? ué.ÿÿÿfD  H‹±8  H…ÀtéUH‰åÿĞ]éÿÿÿH‰ùPH‹=ÅÌ  H‹ŞÎ  ¾(+@ 1Àèøÿÿ¿   èÈøÿÿSH‰ûèßöÿÿ‹8èØøÿÿH‹=‘Ì  H‹ªÎ  I‰ÀH‰Ù¾$+@ 1ÀèÈ÷ÿÿ¿   èøÿÿAVA‰şAUI‰ÍATI‰ôU1íSH‰ÓH…ÛtJL‰éH‰ÚL‰æD‰÷èøÿÿH…Àu¿0+@ ëHƒøÿuèköÿÿ‹8ƒÿtÌè_øÿÿH‰ÇèGÿÿÿIÄIÅHÅH)Ãë±[H‰è]A\A]A^ÃH¯ÊP‹ª9  HÁè|ÿÿÿZÃAVA‰şAUI‰ÍATI‰ôU1íSH‰ÓH…ÛtJL‰éH‰ÚL‰æD‰÷è÷ÿÿH…Àu¿;+@ ëHƒøÿuèåõÿÿ‹8ƒÿtÌèÙ÷ÿÿH‰ÇèÁşÿÿIÄIÅHÅH)Ãë±[H‰è]A\A]A^ÃƒşH‰øu ¾ R` ¹   HƒÀZó¤¾ZR` ¹i   H‰Çó¥Ãƒşu&f‹#9  HƒÀT¾TR` ¹ª  f‰Š9  ˆWH‰Çó¤ÃAVAUATUSŠG<ğt<÷½½-@ †f  ·G=   t* şÿÿ½.@ ú   ‡D  Pÿ…Â¸ï-@ HDèé1  ·WI‰ôH‰ûf…Òu*€ u$€ u€ ufƒ ufƒ u
ƒ  „  ¶{½.@ @¶Ç…À„ã  Hÿ…Á…Ø  ·CH…Àu‹C ·KH)ĞH…ÉH‰ÎH‰Êu‹S$D¶C½>/@ I¯ĞH)Ğ·SƒÂÁú	HcÒH)Ğˆ  H…Éu‹K$I¯È½-/@ H…É„v  H™H÷ÿH=ôÿ  I‰ÅÀ   f…ö½/@ „T  €{&)…ß   Ls6º   ¾¢/@ L‰÷èåôÿÿ…ÀuIıô  ½è.@ ³   é  º   ¾«/@ L‰÷è¸ôÿÿ…ÀuIıô  ½¿.@ †   éì   º   ¾´/@ L‰÷è‹ôÿÿ…À½•.@ „Í   º   ¾½/@ L‰÷èlôÿÿ…ÀtLH‹C6½`Q` H‰™6  é¢   H=ôÿÿ½`.@ ‘   €{B)½H.@ …‚   H{Rº   ¾´/@ è ôÿÿ…Àuk1íM…ätdAÇ$   ëZHƒÃº   ¾Æ/@ H‰ßèõóÿÿ…Àt1º   ¾/@ H‰ßèßóÿÿ…Àtº   ¾™/@ H‰ßèÉóÿÿ…À½o/@ u1íM…ätAÇ$   [H‰è]A\A]A^Ã‹[  A» T` Dÿ  AÁê	AƒÂA9òa  A;ş²>tIƒÃëñAWAVAUATUSHoHƒì(E·{L‹'IŸ T` ·sD‰¦ R` ·sIÁì …ÉD‰¦ R` t·KfÇ R` ÍÁè…ÒfAÇC
 ‰D$ABşfA‰C‹D$A‰CtfAÇC ·S
·CL‰L$L‰D$HÂ T` A9Â~H‹5ÇÇ  ¿Ï/@ èòÿÿ¿   èÓóÿÿHkÈ
H‰×1ÀEBıI‰éA¼ €  ¾ €  óª1ÀE…Àtm…ÀM‹)tExA‰şAÁæ	D‰t$A‰ÆIÎM9îu |$ÿÿ  wD‹t$Gt&ÿA1öAæ  ÿÿtH‰
f‰BHƒÂ
A‰ô¿   ëI‰ÍÆ   AÿÈIƒÁ‰øL‰éë…ÀtH‰
f‰BAÿÊA·‡ T` McÒIÁâHƒ|$ J‹TğH‰ T` J‹TøH‰T` tIH‹|$1ÀHƒÉÿò®·C÷Ñ9Á~H‹5ÇÆ  ¿ø/@ èñÿÿ¿   èÓòÿÿ·CHcÉH‹t$H T` H‰Çó¤Hƒ|$ tIH‹|$1ÀHƒÉÿò®·C÷Ñ9Á~H‹5vÆ  ¿)0@ èLñÿÿ¿   è‚òÿÿ·CHcÉH‹t$H T` H‰Çó¤AÇC    1Àºş²>9D$~+… T` HÿÀëî‹D$A‰SHƒÄ([]ÁàA\A]A^A_ÃƒÈÿÃƒşUS‰ıP‰ótorNƒş……   H‹È  H‹=çÅ  ¾‘3@ 1Àè+ñÿÿH‹=ÔÅ  ºG1@ ¾J1@ 1ÀèñÿÿH‹5¼Å  ¿I3@ è’ğÿÿërH‹ÉÇ  H‹=¢Å  ¾T0@ 1Àèæğÿÿé   H‹ªÇ  H‹=ƒÅ  ¾á0@ 1ÀèÇğÿÿºG1@ ëe…öt\H‹=eÅ  ºG1@ ¾J1@ 1Àè¤ğÿÿH‹5MÅ  ¿I3@ è#ğÿÿƒûuH‹57Å  ¿ò3@ èğÿÿƒãıuH‹5!Å  ¿A4@ è÷ïÿÿ‰ïè0ñÿÿºÃ/@ H‹=Å  ¾J1@ 1ÀèHğÿÿH‹5ñÄ  ¿I3@ ë¸ATUA‰üSH‹H‰õ‰ÓH‰ôÆ  E1À¹`6@ º@6@ H‰îD‰çèlïÿÿƒøÿ„Ü  ƒøf„  ˆ   ƒøM„.  6ƒø„å  ÿÈ…ƒ  Ç2     ë¦ƒø„5  ƒøH„  é`  ƒøU„€  ƒøO„Ò  ƒøS„Å   é>  ƒøa„í  ƒød…,  H‹Ä  H‰É1  éHÿÿÿƒør„  4ƒøi„  ƒøh…ú  ‰Ş1ÿé  ƒøm„‘  ƒøo„  éÚ  ƒøu„ú   ƒøs„Ñ   ƒøt„(  é¸  ƒøv„  ƒøz…¦  Ç#1  @   Ç1      é¼şÿÿÇN1     é­şÿÿH‹=bÃ  1Ò1öèqïÿÿ‰Á‰é0  ÿÈƒø>†ŠşÿÿH‹wÅ  ¾h4@ ë1H‹=1Ã  1Ò1öè@ïÿÿ‰Á‰¼0  ÿÈ=ÿ   †WşÿÿH‹DÅ  ¾š4@ H‹=Ã  1Àèaîÿÿ¿@   è'ïÿÿÇ…0     é$şÿÿÇz0     éşÿÿÇ0      éşÿÿÇp0     é÷ıÿÿ…ÛuH‹àÄ  H‹=¹Â  ¾Ë4@ 1ÀèıíÿÿëH‹ŒÂ  H‰50  éÄıÿÿH‹=yÂ  1Ò1öèˆîÿÿ‰:0  é©ıÿÿHÇ
0  S0@ é™ıÿÿH‹NÂ  H‰0  é†ıÿÿÇ0     éwıÿÿÇ0     éhıÿÿƒûuTH‹Â  H‰Ù/  éPıÿÿH‹=Â  H‹6Ä  ¾5@ 1ÀèZíÿÿ1ÿé÷şÿÿ‹íÁ  H‹Ä  ¾B5@ H‹=êÁ  1Àè3íÿÿ‰Ş¿@   èËûÿÿƒûHc­Á  trƒûu6PH‹DÅ ‰–Á  H‰_/  ëHƒ=M/   uPH‹DÅ ‰uÁ  H‰6/  HcgÁ  H‰ĞH‹TÕ H…ÒtƒûuÿÀH‰D/  ‰FÁ  Hc?Á  Hƒ|Å  …pÿÿÿ[]A\ÃUSQƒ=Ô.   t
¿`æ` èü  H‹É.  H…Òu1Ûë@HƒËÿ1ÀH‰×H‰Ùò®¿   H‰ÈH÷ĞH4è±   …ÀtÖH‹Ã  H‹=ôÀ  ¾[5@ 1Àè8ìÿÿH‹¡.  H…ÒtBHƒÍÿ1ÀH‰×H‰éò®¿   H‰ÈH÷ĞH4(èe   …ÀtH‹ÏÂ  H‹=¨À  ¾‡5@ 1À‰ëèêëÿÿ‰ØZ[]ÃH‰şÇ¥/-Z1Àºg£+THƒÀH=ô  uğH†   ‰VÇ†ü  d¿(İ¹€   H‰Çó¥ÃAVGÿAUATUSHì   =ş   vèwêÿÿÇ    éŠ   Hşÿ   H‰õwsA‰ş¾hæ` ¹}   H‰çI‰ÕI‰äó¥»ô  I‰àA¶A¶@HƒÀ„Òt4A9ÖuH9Øs*I4 H‰ÚL‰ÇH)Âè“ëÿÿI‰ÀëÎH9ØwH)ÃIÀHƒûw½ëhH…ít9HEH9ØvèèéÿÿÇ    ƒÈÿëQI@Eˆ0AˆhL‰îH‰éH)ëH‰ÇHƒëó¤I‰ø1ÀL‰ÇH‰Ùóª¸hæ` ¹}   L‰æH‰Çó¥¿`æ` èÃşÿÿ1ÀëH…ítÑëŸHÄ   []A\A]A^ÃHwH‰ú¹}   1ÀH‰÷ó«H‰×éşÿÿ?¥/-ZH‰øu=¿ü  d¿(İu11Ò1ÉLHƒÂHúø  uïùg£uH   ¹€   H‰ÆH‰×ëG¸   ¥/-Zu@¸ü  d¿(İu4H°   1Ò1ÉŒ  HƒÂHúø  uìùg£u¹€   H‰Çó¥1ÀÃH‰ÇèIÿÿÿƒÈÿÃATUI‰üS¿P   H‰õèíéÿÿH‰Ã1ÀH…Û„'  1öH‰ßHÇCH    L‰#H‰kè  H…À„û   fx …ï   ¶p1É¿   ‰úÓâD¶ÂA9ğtÿÁƒù	uìéË   ‰S·P‰K…Òu‹P D·HD·@H‰S@E…ÉL‰C(uD‹H$¶pA¯ñJ<·pH‰{0ÁæÆÿ  Áş	HcöHşH9òH‰s8vpH)òHÓêJúô  ‰Kw‰ÊÇC    ÑúÑë%úôÿ  wÇC   Éëúôÿÿw2ÇC   ÁáÁÿ  Áé	A9Érƒ{u‹@,‰C ëÇC     H‰Øë
H‰ßèjçÿÿ1À[]A\ÃSH‰ûèÓ   H‰ß[éQçÿÿAWAVI‰ÖAUATI‰ıUSI‰ÌAPèn  H…ÀH‰Å„“   HƒøÿuƒÈÿéŠ   H‰ÆL‰ïè°   H…ÀH‰ÃtåE1ÿº   L‰öH‰ßè×çÿÿ…Àu5M…ätIT$¹   H‰ŞH‰×ó¥I‰,$E‰|$ƒ{ t:·C·SÁàĞë+€; t!AƒÇ HƒÃ Aÿ   u¡H‰îL‰ïè  éaÿÿÿ¸şÿÿÿZ[]A\A]A^A_ÃSH‹GHHÇGH    H…ÀtH‹XH‰ÇèiæÿÿH‰Øëê[ÃH‹GHH…ÀtH90uHƒÀÃH‹@ëëAUATI‰ıUS¿  QI‰ôè‚çÿÿH…ÀH‰ÅuL‰ïè›ÿÿÿ¿  èhçÿÿH‰Å1ÀH…ít=H]I‹}L‰áº   H‰ŞAÿU =   tH‰ïèèåÿÿ1ÀëI‹EHL‰e I‰mHH‰EH‰ØZ[]A\A]Ã…öu‹w …öuH‹G0ÃHƒÈÿƒş~9w~‹OƒîHcÆHÓàHG8ÃH‹W8H9òvH;w0‚Y  HFH9Â‡H  éD  AUATUSH‰óAP‹GH)ÓPÿH‰ØH÷ĞH…Ât	HFé  ‹OHÓëƒÃ;_ş   ‹GH‰ıƒø„ˆ   rƒø„¤   éß   A‰ÜAÑüAÜD‰æÁî	Hw(è¢şÿÿH…À„¾   D‰âAÿÄH‰ïD‰æâÿ  Áî	Hu(D¶,èvşÿÿH…À„’   Aäÿ  B¶ ÁàD	è‰ÆÁøæÿ  €ãEğş÷  ëRÛ‰ŞÁî	Hw(è2şÿÿH…ÀtRãş  ·4ş÷ÿ  ë+Áã‰ŞÁî	Hw(è
şÿÿH…Àt*ãü  ‹4æÿÿÿş÷ÿÿ~1ÀëYH‰ï[]A\A]étşÿÿHƒÈÿZ[]A\A]Ã1ÀÃHƒÈÿÃf„     AWAVA‰ÿAUATL%æ#  UH-Ş#  SI‰öI‰ÕL)åHƒìHÁıèŸãÿÿH…ít 1Û„     L‰êL‰öD‰ÿAÿÜHƒÃH9ëuêHƒÄ[]A\A]A^A_Ãf.„     óÃf.„     @ H‰ò‰ş¿   é¡äÿÿH‹a#  Hƒøÿt(UH‰åSHO#  Hƒì HƒëÿĞH‹HƒøÿuñHƒÄ[]óÃ Hƒìè¯ëÿÿHƒÄÃ                            %s: %s: %s
 short read short write /tmp At least one specified option not yet implemented for this installer.
 TMPDIR %s: not a block device or regular file (use -f to override)
 %s//syslinux-mtools-XXXXXX w MTOOLS_SKIP_CHECK=1
MTOOLS_FAT_COMPATIBILITY=1
drive s:
  file="/proc/%lu/fd/%d"
  offset=%llu
 MTOOLSRC mattrib -h -r -s s:/ldlinux.sys 2>/dev/null mcopy -D o -D O -o - s:/ldlinux.sys failed to create ldlinux.sys 's:/ ldlinux.sys' mattrib -h -r -s %s 2>/dev/null mmove -D o -D O s:/ldlinux.sys %s %s: warning: unable to move ldlinux.sys
 mattrib +r +h +s s:/ldlinux.sys mattrib +r +h +s %s %s: warning: failed to set system bit on ldlinux.sys
 LDLINUX SYS invalid media signature (not an FAT/NTFS volume?) unsupported sectors size impossible sector size impossible cluster size on an FAT volume missing FAT32 signature impossibly large number of clusters on an FAT volume less than 65525 clusters but claims FAT32 less than 4084 clusters but claims FAT16 more than 4084 clusters but claims FAT12 zero FAT sectors (FAT12/16) zero FAT sectors negative number of data sectors on an FAT volume unknown OEM name but claims NTFS MSWIN4.0 MSWIN4.1 FAT12    FAT16    FAT32    FAT      NTFS     Insufficient extent space, build error!
 Subdirectory path too long... aborting install!
 Subvol name too long... aborting install!
 Usage: %s [options] device
  --offset     -t  Offset of the file system on the device 
  --directory  -d  Directory for installation target
 Usage: %s [options] directory
  --device         Force use of a specific block device (experts only)
 -o   --install    -i  Install over the current bootsector
  --update     -U  Update a previous installation
  --zip        -z  Force zipdrive geometry (-H 64 -S 32)
  --sectors=#  -S  Force the number of sectors per track
  --heads=#    -H  Force number of heads
  --stupid     -s  Slow, safe and stupid mode
  --raid       -r  Fall back to the next device on boot failure
  --once=...   %s  Execute a command once upon boot
  --clear-once -O  Clear the boot-once command
  --reset-adv      Reset auxilliary data
   --menu-save= -M  Set the label to select as default on the next boot
 Usage: %s [options] <drive>: [bootsecfile]
  --directory  -d  Directory for installation target
   --mbr        -m  Install an MBR
  --active     -a  Mark partition as active
   --force      -f  Ignore precautions
 %s: invalid number of sectors: %u (must be 1-63)
 %s: invalid number of heads: %u (must be 1-256)
 %s: -o will change meaning in a future version, use -t or --offset
 %s 4.07  Copyright 1994-2013 H. Peter Anvin et al
 %s: Unknown option: -%c
 %s: not enough space for boot-once command
 %s: not enough space for menu-save label
 force install directory offset update zipdrive stupid heads raid-mode version help clear-once reset-adv menu-save mbr active device            t:fid:UuzsS:H:rvho:OM:ma        ±5@                     f       ·5@                     i       ¿5@                    d       É5@                    t       Ğ5@                     U       ×5@                     z       6/@                    S       à5@                     s       ç5@                    H       í5@                     r       ÷5@                     v       ÿ5@                     h       
6@                           6@                     O       6@                            6@                    M       #6@                     m       '6@                     a       .6@                                                           cñğQ   cñğQ   ;ì      @Õÿÿ8  ×ÿÿ(   İÿÿ  `Şÿÿ`  ˆŞÿÿx  ÂŞÿÿ  3ßÿÿĞ  Hßÿÿè  ¹ßÿÿx  àÿÿ  ›âÿÿĞ  $åÿÿ   Fæÿÿ@  âéÿÿp  œêÿÿ˜  Ûêÿÿ°  ôëÿÿø  ìÿÿ  ¯ìÿÿ(  ıíÿÿX  îÿÿx  ÙîÿÿÀ  şîÿÿà  —ïÿÿ   Æïÿÿ8  @ñÿÿ  °ñÿÿØ  Àñÿÿğ             zR x      ğÛÿÿ*                  zR x  $       Ôÿÿ@   FJw€ ?;*3$"       D   øÜÿÿ(    D       \   İÿÿ:    Aƒ  <   t   *İÿÿq    BEE ŒD(†C0ƒS(D BBB         ´   [İÿÿ    EO <   Ì   Xİÿÿq    BEE ŒD(†C0ƒS(D BBB      L     `Õÿÿb   BBB B(ŒA0†A8ƒGğID8C0A(B BBB         \  9İÿÿT           <   t  uİÿÿ   BBB ŒA(†A0ƒ{(D BBB     L   ´  Ãßÿÿ‰   uBB B(ŒA0†A8ƒH`28AÃ0AÆ(EÌ BÍBÎBÏ      üáÿÿ"   D†AƒC   ,   $  şâÿÿœ   BŒA†D ƒ‘AB     $   T  jæÿÿº    A†AƒA ´AA   |  üæÿÿ?           D   ”  #çÿÿ   BEB ŒA(†A0ƒG°ş0A(A BBB          Ü  ôçÿÿ              ô  ÷çÿÿ            ,     èÿÿN   BŒA†D ƒCAB        <  éÿÿ    AƒL       D   \  éÿÿÊ    BBE B(ŒD0†A8ƒE@ª8A0A(B BBB   ¤  êÿÿ%    Aƒc       <   Ä  êÿÿ™    [BŒD †A(ƒF0j(AÃ AÆBÌBÍ         oêÿÿ/           T     †êÿÿq   gBŒA †A(ƒE0
(DÃ AÆBÌBÍEE(AÃ AÆBÌBÍ     D   t  ¨ëÿÿe    BBE B(ŒH0†H8ƒM@r8A0A(B BBB    ¼  Ğëÿÿ              Ô  Èëÿÿ                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           ÿÿÿÿÿÿÿÿ        ÿÿÿÿÿÿÿÿ                                      @            ø*@            x@            è@            È@     
       –                                           P`            H                           ¸
@            ø	@            À       	              şÿÿo    Ø	@     ÿÿÿo           ğÿÿo    ~	@                                                                                                                                     PN`                     F@     V@     f@     v@     †@     –@     ¦@     ¶@     Æ@     Ö@     æ@     ö@     @     @     &@     6@     F@     V@     f@     v@     †@     –@     ¦@     ¶@     Æ@     Ö@     æ@     ö@     @     @     &@     6@     F@     V@     f@                                                     filesystem type "????????" not supported                                                        ÿÿÿÿ                                                            ëXSYSLINUX                                                                               úü1ÉÑ¼v{RWVÁ±&¿x{ó¥Ù»x ´7 V Òx1À±‰?‰Gód¥Š|ˆMøPPPPÍëb‹Uª‹u¨ÁîòƒúOv1ú²s+öE´u%8M¸t f=!GPTu€}¸íu
fÿuìfÿuèëQQfÿu¼ëQQfÿ6|´èé r äuÁêB‰|ƒá?‰|û»ªU´AèË rûUªu
öÁtÆF} f¸ï¾­ŞfºÎúíş» €è f>€¡óBoutéøf`{fd{¹ ë+fRfPSjj‰æf`´Bèw fadrÃf`1Àèh faâÚÆF}+f`f·6|f·>|f÷ö1É‡Êf÷÷f=ÿ  wÀäAáˆÅˆÖ¸è/ farÃâÉ1öÖ¼h{Şfx ¾Ú}¬ Àt	´» Íëò1ÀÍÍôëıŠt{ÍÃBoot error
                  ş²>7Uª
SYSLINUX 4.07  
    ş²>¡óBo             ¦0ê5€  û¾ €èˆ¾ €‹|ÁéfºıMÁf­fÂâùf‰(€f·Ş¾æ€>F} u¾êÆõ€ ‰6 0èOSf6î‹ €Iã*f‹f‹Tf·l)éfSfÁëÃ1ÛèK f[¯.|fëƒÆ
ëÔ^f·|Áèf‹$€f)Áf¡(€fƒÆuŒÚÂ ÚfIuìÙf!À„‘¾×èß éÁüf`f`{fd{ëQUè¿ f·ı¹ fRfPSWj‰æf`´Bè»üfadr]føfƒÒ )ı¯>|û!íuÃfaÃf`1Àè”üfaâÀÆõ€Q]fRfPUSf·6|f·>|f÷ö1É‡Êf÷÷f=ÿ  ‡<üèI )Î9õv‰õÀäAáˆÅˆÖ•´½ f`èDüfarf¶È¯|[Ã]fXfZfÈ)ÍufaÃMuÙ•Ñ.,€uÛéğû;.,€v‹.,€Ãf`¬ Àt	´» ÍëòfaÃ Load error -  CHS EDD                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   1ÀÀ¾¦³èJø¾Ó·èDøf1À¾|¿8¹ ­Nf«0äf«âöè—fh°¬  èf=Üu  …ıóèÌ!èè0	èì´Í¢¤8¨u3Ífº_4 fÁê
9Ğs#¾¼²±
Röñ d]˜öñD[Xöñ d$˜öñD"èÑ÷é³óf`f¸ğh ¶t{f‹`{f‹d{‹6|‹>|f·.,€fhx è’fa¿·}°éª¸ï˜)ø«fhR è{tè~è¦²èHã¿ Áó¤1Àª1ÉèarèíéĞö¤8[uƒ>ØR „ƒ>äR‡„ƒ>ÚR …{¾ä³è_!Æ¥8 ¿ Á´Ít´Íëôf¡ÌRf£œ8f¡ÈRf£˜8èÕfƒ&˜8  À„ã <tA< rwÿ Átáö¥8…¢ ÿÿÈsÒªèÒ ëÌ<„><	t8<t-<t<„Ü <t<u¬ÿ Át¦O¾ë³èÚ ëèÈ édÿèé^ÿÆ¥8ëëƒ>ÜR uäW‰ùé Áè§ f‹6$¶f;68<v2Qf¿Ñ  fhW èh)ÏYVƒù tWQ¾ Áó&¦Y_u
° èG ‰şèy ^ëÇèf ër0äˆ&¥8<0rt <9v<ar<c‡{ÿ,Wë$°
ë ,1ë†Ä<Dw,;‚cÿë<…‚[ÿ<†‡Uÿ,{WÁà<=—€= t2èFt-è èTëW¾—³è ‹6 0è ¾Ó·èÿ¾ä³èù_WÆ ¾ Áèî_é¯şƒ>äR u¾²³èİƒ>ÚR …—ñécş¾É¿ Á¹ óf¥ëè³ÿ ÁtĞ0Àª¾ Á¿<IVfh‘ èw^¬< wû Àt¬< v÷N‰6¢8¡àR!Àuˆf‹6$¶f;68<v_f¿Ñ  fhW è?)ÏV¾ Á¬< v®tø^ëÙ€= uø^h ¿ ø¾Ó‹Óó¤&ˆ‰>ÖR¿<IW¾Ò¹ ó¤_1Û Ó¢¦8<ÿ¡Ò„së)ƒ>ŞR tiVW¿ Ç¾Û¿ ø‹ĞRó¤&ˆ‰>ÖR_^ˆ¦8Æ<J ¿<I€= v:0À¹û ò®uO‰> 8»È¹S¿<Ifh: è›[…­ f‹‹6 8f‰ÆD ƒÃûÜ¹v×‹ÔR!Éu¾´è¡¾<Iè›¾z¶éa¾ë¿ ÁVWQQWó¦_[tİ÷Ûÿ¿şÈÆE 1ıó¤üY_^ó¤é²ş¾7´é/èÖèıÿ6¬·è`u+èX;¬·tífÿ˜8tfÿœ8ußYè´¾ã¿ Á‹ÒRó¤éfşYèeèÃ‹6”8f¡8f`1À£Ì8¢Ï8f¡8<f£¨8faWP¿<I0À¹ ò®uOf‹MüX_¶>¦8ÿÿ¥\´fÉ    fù.com„cfù.cbt„Xfù.c32„•fù.bss„/	fù.bin„ 	fÁéfù.bs „	fÁéù.0„	ë Vèßfh4 èM^è­
èÁéÊû¾ï³èméüûVh è
¹ €1Û^fh è#ù ‚âş&>şUª…×şV‹>ÖR¾Ø´¹ ó¤¾<IèÄ&ÆEÿ è‹6¢8èµ¿ ø&ŠG Àt~< vôO¾ã´¶ãWFó¦u&‹Eÿ<=t€ü wXÿ&ŠG< wøëÏ_ÎFFëÔ&‹Eÿ»ÿÿ==ntK==etK==at»==ctèÏr&‰úÃèÄrf‰¨8ÃÆÏ8 Ã‰ø&€= w1À£Ì8Ãï ø‰>Ä8fÇ¬8ÿÿÿ7&f>HdrS…&¡£Ê8= ‚=r&Ç$ôõ&€€=r	&f¡,f£¬8&Æ1f1À&f£& 
Ï8&¢¢Î8¾p´è™¾<Iè“&¶ñ!Àu°@£È8è²f·6È8Áæ	f¹ €  f)ñfÆ   f¿   èÃ^!öt»Œ˜fƒÈÿº èÊf‰>¸8¸ À¾z´è<W‹>È8Áç	f1À¹ ø)ùÁéóf«_f¡¬8f;¨8wf£¨8f1À9Ì8tèJèA¾|´è¸ Àà&ƒ>ü u&Çü ‹Ê8öÎ8túrdfÇ( ø Çt‘ô÷dÇ$ôõëT¾ ø¿ ˜dÇ  ?£d‰>" Çt‘ô—¸ÿ úrdÇ$ô•vdfÇ( ˜	 ¸ÿ‹Ä89Áv‰Áód¤ª‰>Æ8ú r&‰>¿ 1ÉŒÃãfº   öÎ8u"f¸  	 f«f¸   f«f·Æ8f«Afº   » f‰Ğf«f¸   f«f÷Øf¸8f«Aƒ>Ì8 tdf¡f«f¡¼8f«df¡f«Afhn‘  QöÏ8 „“é“úŒØĞ¼ô÷ÀàèƒÀ Pj Ë1À9Ì8t¾…´é!¢Î8£Ê8é!ş¸ Ø.f‰>¼8.f‰>À8.‹6Ì8‰ó¬<,t< vëõPVÆDÿ ‰ŞW¿<Kfh‘ èà_è/ ^XˆDÿ<,tÑ.f‹À8.f+¼8f‰.f¡¨8% ğf)Ğ% ğf£ÃŒÈØÀfW¿<Kfh: è—f_t%V¾n´è0 ¾<Kè* ¾y´è$ ^º »Œ˜è˜f‰À8Ã¾·´è˜¾<Kè’¾z¶éXöÏ8 „ƒÃfho èI¾ÑµèséøVèÅèh ¹ Á1ÿ¹@ f1Àóf«&Ç  Í ÍÁà&£ ¾ ø¹} ¿ ° ª&¬ Àtªâ÷°ª‰ø,‚&¢€ ^» ¹ ÿfh èéfùşş  wŒÀØĞ1äj ê  ¿P9¹  Qf¸j ëf«şÄâúOÆEÿé¸f“)ø«Y¾€ »µ¿Ğ8f¥f·CCf‰DüâòÃ`¾Ğ8¿€ ¹  óf¥aÃû ¨f`üŒÍİÅ‰åèd¹
 ¾Dµ¬:F­àùøÿĞ‰å’F,fa©¡Ï‹Ffÿv(j!Zf_¹°µhs“ë$’è‚° è3’è†° è*f‰øèˆèKéçöúhxŠ1É[1öŞÆf²& °fÇ·  ûüfhg èşèéã¾<Iè#‰Îèÿãèèe èèÙøÃŠFèÑøÃŠFèÊøÃèJ øÃF&‹v&¬<$tè³ëõøÃ€>­µ uèæ”ÀşÈˆFøÃfÇF  SYfÇF  SLfÇF  INfÇF  UXÃ€>­µ uèç Àuˆ&¬µş­µˆFÃ ¬µş­µëóûüè9ÏûüèLÏû ¨f`üŒÍİÅ‰åè+ƒø%r1À“Ûÿ—bµéÆşùÃÇF% ÇFÇF1 ŒNŒ^$ÇF™³ÇF Ô·øÃ^$‹vè0øÃ^$‹v¿ Áè¹h/ŒéËşhü‹éÅşèUøÃF$‹vfhğ èÒf‰F‰N‰vÃF$‹^‹v‹Nfh° è²s1ö‰vf‰NÃ‹vfho èšøÃÆF1 ¾RˆF t{ˆFŒN"ÇFp{ŒN ÇF `{ŒN$ÇFx{øÃ¡€¶‰F¡‚¶‰F¡„¶àŠ&†¶ÀìöÄRu€Ì€‰FøÃf¡h{f£x èdøÃŒN$ÇFÔ9øÃŒN$ÇF  ÇF  øÃèşøÃ‹Fé˜ŒN$ÇF¯µÇF øÃŠF<‡‚ ¢¦8^$‹v¿Ñèµ^&‹v¿<Ifh‘ èÚfh: èĞ„ ş‰6”8f£8è ıº Â¾Ñ¿ øèy&ÇEÿ  ‰>ÖRÇ¢8®µé­÷‹Fƒøw¢t·‹N‹V‰LL‰NL¨uèløÃùÃ b· Àt `·ÇF$ 0ÇF  ˆFÃfƒ~  uf‹Ff‹VF$‹^‹nèyêøÃùÃŒ^$ÇF¼ÇFôÃƒ~ uÇF ÇF ŒN$ÇF<<ÃùÃŒN$ÇF¼°øÃÇF•ÃèÀşf‹~ f‹vf‹NéVfPè{ ¸ à¾ ø¿ Á‹ÖRA)ñód¤¾<I¿ Àè›è üf¿   fX^1Ò»”˜èâf¾   f¿   f¹   è´f> ¸şLÍu€>!uf¡8<1Àf£·f»   é«¾<Iè°¾ìµèªé9ó¸ À‹>ÖRè ‹6¢8è*O‰>ÖR&Æ ÃÃj ëj3f¿   f‰>f¸  
 1Ò»”˜èZfï   f‰>fÿ „	 ‡ï f¸ |  f£ f1ÉYf¾|  f¿  èfPf1Òf1öf¡h{f£x Št{¾x{¿îW¹ 1Àó¥^1Ûf¡ ff·fÁá
f)Áf£fƒÿf‰jè'èÚ 1ÀØÀ¿x{W¹ ó«_&f‰U&f‰u&‰]¡p{‹r{&‰E&‰]XWf»   køWßf SPf«1Àf«f«_¾º¹	 óf¥f1ÉYƒÁ	SSfSú	Sf‹&Sf¿   f‰şéNè3¾0¶ë&V¾z´èÇù^èïèVt`è†<t<taÃ¾l¶»xŠë»Ñ˜1ÀØÀf²& °fÇ·  ûüèÿã‹ÔR!É…vôéšñf`1À1ÒÍè3úè¡faé!¾¸èï€>Ë}t
è%è$ÍëşèÍëşfh: è	tS‹x¶ƒëûä:r‰x¶‰71À‰GˆG@[Ãfho èt	1À[ÃSVW‹>x¶¶]!Ûu¾ Æƒmr‹u&ŠF‰uø_^[ÃKŠAˆ]ëñf`‰ûëä:Áã‰]‹5!ö‰ut¹ fh è	‰M‰5ãfaë³fa0Àùë½Pè“ÿrªâøXÃSV‹x¶‹7fho èëƒÃ‰x¶^[ÃWS‹>x¶¶]ˆACˆ][_ÃèZÿr<t	<
t	< vïÃ8ÀùÃÿÃ¿Ô:ÿã:sWè7ÿ_rª<-sîè»ÿÆ ¾Ô:fPfQUf1Àf‰Ãf‰Ù1í¬<-uƒõëö<0rSt<9wM±
ë¬<0r% <xt<7w:±ë°0±è@ r8Ès
f¯ÙfÃ¬ëíN¬ <kt"<mt<gtN!ítf÷Ûø]fYfXÃùë÷fÁã
fÁã
fÁã
ëá<0r<9w,0Ã <ar<fw,WÃùÃè*ÿ²t+r&èÿRWèyş_Zr< v1Òªëî<
t<t Òuâ° Bëìøëùœ Òu° ªÃ‡÷èÿ‡÷Ã¹ ¿ è¡şrè3şs¾ ¿<<¹@ óf¥è–şÃÆê;Æë;è`èşr<t¶t·€áAÿä;ëèémş<tg<tZ<
tf<„• <tM<„<„Ï s<ƒ+è/„ë;t/öÄRt(Šê;Š>b´	¹ Í æ;@:è;w%¢æ;Š>b‹æ;´ÍÃ¸1ÛÍÃÇä;œÃ¾z¶è„ë;täÆæ;  ç;@:é;w¢ç;ëÄ1É‹è;ˆ6ç;Š>ÆR¸Íë¯¾}¶èä „ë;t¯1É‰æ;‹è;Š>ê;¸ ÍëèŠşr/Àà„ë;t¢ê;Çä;-œÃèrşr„ë;tê;ëÇä;Uœ¿ŒLë!Æê;Çä;M›Ã<
t< v‹>ŠLÿMsˆG‰>ŠLÃè¶
ë‹6ŠLÆ ¾ŒL¿Mfh‘ è,è‚üt¿è+	`Š>b´Í‰æ;aë¬$¢ë;ë¥öë;t-fœf`‹€¶!ÛtPŠ&…¶Wì¨ tøBì à8àuğ‡ÓXîæ€æ€fafÃöë;t
¬ ÀtèÃÿëöÃf`´Íu*‹€¶!Òt"¡4<ú;2<uƒÂì¨tBŠ&†¶ì à8à•ÀşÈûfaÃûèm´ÍuD‹€¶!Ûtï¡4<ú;2<uWì¨tÜBŠ&†¶ì à8àuĞ0ä‰Úìûë(û“¸ 2ØŠCãÿ‰4<ë´Í<àu0À Àt»<<×éş
.fÿ6ğ;ëx.fÿ6ô;ëp.fÿ6ø;ëh.fÿ6ü;ë`.fÿ6 <ëX.fÿ6<ëP.fÿ6<ëH.fÿ6<ë@.fÿ6<ë8.fÿ6<ë0.fÿ6<ë(.fÿ6<ë .fÿ6 <ë.fÿ6$<ë.fÿ6(<ë.fÿ6,<ë œPR.‹€¶ƒÂì¨uZXËW¸ 2À.‹>2<.‹€¶ìª.Š&†¶ƒÂìP à8àuçÿ.;>4<t.‰>2<X¨uÔ_ëÀf`èµ ¾  ¿ğ;¹ óf¥¾À¹ óf¥¿  ¹ f¸ˆ  f«ƒÀâù¿À¹ f«ƒÀâù‹€¶‰0<W°îæ€æ€W°îæ€æ€ä¡ˆÄä!£6<æ€æ€1Àæ!æ¡faÃf`1ÀØÀ‹0<!Ût7W°îæ€æ€W1Àîæ€æ€¡6<æ!ˆàæ¡¾ğ;¿  ¹ óf¥¿À¹ óf¥1À£0<faÃè¯ÿf`¸ 2Àf1À.f£2<¹ 1ÿóf«faÃèFf1À¾ä¹¿ÄR¹
 óf¥¿<<0ÀşÅªşÀâûf¡$¶f£8<Ã;äR‚L£äR¿ÉèSûÆEÿ Ã¿ãèHûï	ã‰>ÒRÃ¿ëè9ûïë‰>ÔRÃ€>èR w¿Ûè#ûïÛ‰>ĞRÃ¿ÓèûïÓƒÿu	€>Ó-u1ÿ‰>ÓÃè@ú€>èR t	‰ÒÆÓÿÃ€>èR t¢ÓèÒ¿Òfh‘ èÊÃPèú^rf¸«*Òf÷ãfÓf‰ÃPèúù^r‰ÃPè ¿<Jfh‘ è˜fh: èuXÃPèƒ¿<Jfh‘ è{èÑøuXÃÿâRÃè¸ù‚Ô Sf1Àf£„¶èùr1èwùè¡ùr)fSèùrèhùè’ùs1Û€çÀçˆ>†¶ˆßãğ‰„¶f[ëf»€%  _fƒûK‚‡ f¸ Â f™f÷ó£‚¶PƒÿwÑç‹½ ‰>€¶èşU°ƒîæ€æ€X‰úîæ€æ€Bˆàîæ€æ€°BBîæ€æ€ì<u>J°îæ€æ€ì<Às1Àîæ€æ€BB „¶îæ€æ€¨tèOı€>¬¶ tÆ¬¶ ¾—³èÊû¾Ó·èÄûÃÇ€¶  ÃPè… _fh‘ èÃè› Æ<K ¿Ñ¹1Àó«èe ¿Ñ¹ÿ ¬< vªâøÆèR¾Ñ¿Òfh‘ èG¾Û¿Ó‹ĞR‰Óó¤Ãè/ è`
éP
è è# r f­f%ßßßßf=ENDTuëf­f%ßßß f=EXT uÛÃ¿ WèùÆ ^Ã¿Ñ1À¹
óªèn sûèê÷ÿâRuò€>èR tQ¿Ó>Ó€><K t¾ú´¹ ó¤¾<Kè„&ÆEÿ ‰ø-Ó£Ó¹ )Á1Àóªf¾Ñ  f‹>8<f¹
  fh€ è f‰>8<Ã¾ˆ¶è±	Ãès è­÷tlrù<#tò¿ ª f¶ØèõörW< vª fÁÃ0Ãëìèp÷1Àªè~÷t=r%èc÷¾H¸¹0 f­f9Ãt&f­âõ¾­¶è]	¾ èW	èG	ë¢¾Õ¶èL	¾ èF	è6	ë”­ÿøÃùÃ<
tè“ös÷Ãfœf` ¨‰åŒÈf»õ¬  Øë©¡fafÂ úf1ÀØŒĞ‰&8£
8f·ìfÁàfÅüèd Æm°‰`°· À"Àê­  ¸ ÀØĞàè°1Ò À$ş"Àê6£  .²&8f·äÚÂâêÿãœ.gÿµ    f»A­  é~ÿf`.Æ@Lÿès un.ÿ&·.Ç·o£¸$œÍè[ uV²è… uO.Ç·‚£°Ñædès °ßæ`èl °ÿædèe Q1Éè0 u*âùY.Ç·°£ä’$şæ’Q1Éè uâùY.ş@Lu¾·éÛôYfaÃQfP¹ÿÿÁ.f¡<L¹  ëfAê
C.f£<Læ€æ€&f;LLáéfXYÃ0ÒèÌÿt Òuæ€æ€äd¨tæ€æ€ä`ëå¨uáæ€æ€Ãf1ÿ»0¿0Sf¸j ëz¹ Q¹  ‰?ÇG  fÇG   ƒÃf«f  üâäƒÇÆEûéfº4­  f)úf‰Uüf   €YâÃÃ‰àƒÀ,£DL©¡fafË.‹&DLfœf` ¨f»  é0şfË.‹&DLf‰Æf»6 éşgãfh¯  èëıfÏfÎÃ»Æ¯éşfUf‹.¨8fhx èÎıf]pÃ¾1·é¿óéÄô¿ ¹ è°ôrò¡ =6uê <wã1ÛŠ>€ÿrØ€ÿ wÓ¿ ‰Ùè‡ôrÉèô¾ ˆ>`·¹ 0Á¿  ‰ÙÁéóf¥Æb·öt·ütèÓöb·tH½ 0Å½  Š>`·0Ûöt·t 1Éˆù¡NLöñˆÂH¢é;¸!Í¡LLÁèH¢è;Ã¹ 1Ò¸Í0Û¸Í` „ Àu°¢é;´ÍşÌˆ&è;aÃèhèu¹8 ¿PLèxóªâúr|f>PL=óuqºXL¸1Û¹ Í¡VL‹`·ĞHöò1Ò:é;r é;şÈˆÆ´1ÛÍ‹VLÇˆL  Q¿NWW¹  f1Àóf«_‹TLè% ^¿`QW½€èl ^¿  Ç‹>ˆLè~ ƒˆLPYâÇéhó1Òè4 8ĞtªˆÂIuóÃ1Ûè$ ÃtQ‰ÙˆĞóªY)Ùwİëèè ˆÃè
 ÀàÃƒÃëàöÆt€æˆğÃè­òˆÆÀî€Î$Ã1ÉAVU» ¬ÒèĞÒKuøˆGƒíwí]^€ùvãÃºÄ°îBHîW¹ óf¥_À<vñÃ t·<t@¨t
¸O» Íë¸ 1ÛÍ€ë€ûw%¸ Íºc·¸ÍÆt·fÇLL€àè+şÆÆR 1ÀÃf`ŒÈØÀ t· Àt¨t¸O» Í¸ ÍÆt· ÆÆRèôıfaÃf`°_ëf`° €>t·u
´	» ¹ ÍfaÃfœf`fÇ¸R  ğÿfÇ´R   ¿ R1À¹
 ó«f1Ûëf!Ût}f¸ è  fºPAMSf1É±¿ RÍsf!Ûu`ëuf=PAMSumƒùrhfƒ>¤R wÇf¡ Rfƒ>°Rtf=   r³f;¸Rs¬f£¸Rë¦f;´RwŸf¨Rrfƒ>¬R tfƒÈÿf;´Rv…f£´Réoÿf¡´Rf;¸Rvf¡¸Rf=   w8¸èÍr= <wr‰ØfÁàf   ë´ˆÍ= 8v¸ 8f%ÿÿ  fÁà
f   f£$¶fafÃP¬ª ÀuúXÃfP.f¡¬·.f£x·fXûÃfPŒÈØÀœXöÄu%VQ¾~·è7‰æƒÆ
¹ 6­èJIt° èëëñèY^ûf¡¬·f+x·fƒør	fhO èÒùfXÃ€>¨·ÿ…†ƒ>"€r&f¡`{f‹d{f˜·fœ·f ·f¤· t{¢¨·éY€>¨·ÿt¾ ¼è9 t,¾ ¾è1 t%¿ ¼f¸¥/-Zf«f¸g£f«f1À¹} óf«f¸d¿(İf«Ã¿ ¼¹€ óf¥ÃVf­f=¥/-Zuf1Ò¹~ f­fÂâùfúg£uf­f=d¿(İ^ÃP¾¼1À¬8Ğt Àt¬Æşü½rîë
¬‰Áğ=ü½v1ÉXÃPVW íuYQ¾¼1À¬8Ğt Àt#¬Æşü½rîë¬|şWÆ¹ü½)ñró¤ˆ%^ë×^ëNY‰÷ãÎşú½s‰ŞˆĞªˆÈªód¤¹ü½)ù1Àóªø_^XÃùëùf`¾¼¹} f1Òf­fÂâùf¸g£f)Ğ|¾ ¼f‰D¹€ óf¥faÃfPf¡˜·fœ·tf¡ ·f¤·t€>¨·ÿtè°ÿ´è øfXÃùfXÃP´è èşXÃˆ&¼Rf`»ªU´AŠ¨·Í¾ûªrûUªuöÁt¾Ëªf¡˜·f‹œ·» ¼è f¡ ·f‹¤·» ¾è faÃVÿæ¹ fRfPSjj‰æf`Š¨·¸ @
&¼RÍfadr^ÃâÖù^ÃfRfPUf!ÒusŠ¨· Òy´Ír äuÁêBf·úƒá?f·ñë:t{uJf·6|f·>|f1Òf÷ö1É‡Êf÷÷f=ÿ  w)ÀäAáˆÅˆÖŠ¨·°Š&¼R½ f`Ífar]fXfZ^ÃMuîùëóf¡p f£««fÇp –«  Ãf¡««f£p Ã.fÿ¬·.´·èì.fƒ°·6ê    èşğfœ.öt·tèiû.öÄRtf`´³.Š>bÍfafÃP°èĞÿ°
èËÿXÃfœf`¬ Àtè½ÿëöfafÃfœf`fÁÀ¹ ëfœf`fÁÀ¹ ëfœf`¹ fÁÀfP$<
s0ë7è€ÿfXâçfafÃèíú1ÒÚÂf²& °fÇ·  ûüâê¾¶·èŠÿèìƒøÿt9ˆÂ0öR1ÀÍ¸¹ » ½ `ÍasMu÷é$ÑZú¾ ¿ |¹ óf¥Ñ¼ |ê |  ÍéÑ              j Th   ÿ5“³  h0º  è€   ƒÄE$1À¿ v ¹ù  ó«¿8  ¹­  ó«¿0º  ¹‹  ó«ÃöE)tûÿU.f»Î¢ë 1Ààè Ğ°(ÀØĞ° Ø‹%·  ‰èÿãúü‰%·  ê£   `¶t$ »J£  ëäaƒÄÏfUWVSQRƒìü‹t$(‹|$0½   1À1Û¬<v,ë"ÿ   ŠFÛtôDëfŠF<sAÀtæƒÀ‰Á1èÁé!è‹ƒÆ‰ƒÇIuó)Æ)ÇŠF<sÁèŠ—ÿ÷ÿÿ˜F)Â‹
‰ïën<@r4‰ÁÁèWÿƒàŠÁéØF)ÂƒÁ9ès5ëmÿ   ŠFÛtôL$1Àë< rtƒàtçHf‹WÿÁèƒÆ)Â9èr:DıÁé‹ƒÂ‰ƒÇIuó‰Ç1ÛŠFş!è„?ÿÿÿ‹Æ‰ÇŠFéwÿÿÿ´&    ‡Ö)éó¤‰ÖëÔÁÿ   ŠFÛtóLëv <r,‰ÁƒàÁàƒátßƒÁf‹ƒÆ— ÀÿÿÁèt+)Âézÿÿÿt& ÁèŠWÿ˜F)ÂŠˆŠZˆ_ƒÇénÿÿÿƒù•À‹T$(T$,9Öw&r+|$0‹T$4‰:÷ØƒÄZY[^_]Ã¸   ëã¸   ëÜ¸   ëÕ         SRPƒşÿt~9şr.‰úÑês¤IˆÈƒùrÑêsf¥ƒéˆÈÁéó¥¨tf¥¨t¤XZ[ÃDÿ9ÇwÊı|ÿ‰Æ‰úÑêr¤INOˆÈƒùr"Ñêrf¥ƒéƒîƒïˆÈÁéó¥ƒÆƒÇ¨tf¥FG¨t¤üë°1À‰úÑêsªIˆËƒùrÑêsf«ƒéˆËÁéó«öÃtf«öÃtªë€ú‰ûTƒâğè;ÿÿÿ¾¯  ‰×)ò¹b   ‚í¯  ó¥ÿà¢±  Â`°  ‰R‹;‹s‹KƒÃãèÿşÿÿëìZ0Q!ötÿç‰øf‰Bf‰BÁèˆBˆbˆBˆb À$şfº ÚÂâêÒê                  / `°    g € ‰  ÿÿ   ›  ÿÿ   “  ÿÿ   ›Ï ÿÿ   “Ï ÿÿ              `{    ˜7¼0 ¼1 îÀ  Ê—3                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                It appears your computer has only 000K of low ("DOS") RAM.
This version of Syslinux needs 000K to boot.  If you get this
message in error, hold down the Ctrl key whilebooting, and I
will take your word for it.
 XT  
SYSLINUX 4.07 2013-07-25 No DEFAULT or UI configuration directive found!
 boot:    Invalid image type for this media type!
 Could not find kernel image:  
Invalid or corrupt kernel image.
 |_—c—_—sv’¾–\
Loading  .. ready.
 Cannot load a ramdisk with an old kernel image.
 
Could not find ramdisk image:  BOOT_IMAGE=vga=mem=2quiet=initrd=C ‘“+“d”\9`9d9h9l9X”^”x9|9€9^“ˆ9^“9”9˜9^“ 9¤9¨9¬9°9´9¸9¼9À9Ä9È9Ì9 ‘“Ê“Ø“à“è“	í“ ”0”L‘“ÿ_“Š”Œ”­”¸”Ê”Ğ”Õ”ï”•Š”•H•o•Š”|•†•Š”Š”Š”••š• •¯•–<–T–Š”Š”s–Iª–œ–Š”Š”Š”¦–¬–   : attempted DOS system call INT  COMBOOT image too large.
 : not a COM32R image
      	       E          ?  Ñ          i Too large for a bootstrap (need LINUX instead of KERNEL?)
  aborted.
 ä;
         Out of memory parsing config file
 Unknown keyword in configuration file:  Missing parameter in configuration file. Keyword:    ÿ0  o£
A20 gate not responding!
 
Not enough memory to load specified image.
    	
           ERROR: idle with IF=0
                   ÿÿ            Booting from local disk...
  Copyright (C) 1994-2013 H. Peter Anvin et al
 
Boot failed: please change disks and press a key to continue.
    µ7   ²¡t›;   ‰¡ÿØšB + ¤™9Å  ŒŸ$^ÕÔ<K)¡íYQÌ XŸÉ   XŸ@¼	Õ%›+ ´±2 ö¤+ õ¦ŞR P¸Ğ›+ Ì´hĞ  ÓŸØ6õ ÓŸ”±0  ÓŸ†  ÓŸeÏ  ÓŸœ§N ÓŸŒ±à ÓŸR2 ÓŸG•ÆÀ ÓŸÌñ  8¡t:çØR YÀ   €¡L¨hà  G ı1ØÄR É2ãÔÈRíŸ©ĞQïÌRíŸ¹^ãÔ  nŸ‰Åh  }ŸİHàR 	 ÚR æ6:ÜR ô‰ÅÚ|· §]ÍæR ñ  <=)¡ò  <>)¡ó  <?)¡ô  <@)¡õ  <A)¡ö  <B)¡÷  <C)¡ø  <D)¡ù  <E)¡ <F)¡ğ  <F)¡ <G)¡ <H)¡ôŞğ  ¿Ÿ.cbt.bss.bs .com.c32                         ø                 "ÀêS  ¸  Ğf¼    ©¡fafê      $hi h À  ÿ5$¶  hÑ ]?s   Ñ E™Á j	ûèÊÿ f»‘“éæ¬ğÿ‹D$ë¶[ ‹…    œSUVWÿ5DL  üg·>8T 
8ƒï6gf‰X Áãß‹t$ 1É±ó¥«¸“¤  «‹Gô%×  ‰Gôf«f»€¤é‡XI6€
8‹|$$ÁàÆ!ÿu‰÷·gƒ6x_^][Ã*ş‹L*`DL)Ïƒçüƒï*8D$%D$	$®ˆL ‰ÈÁéó¥‰Áƒáó¤f»«¤éï«ğÿ‰ğ¨
[]^_Ã¡¬·  £xP ª+lƒøv ¡ì‹ …Àufƒ=|P  tëÿĞ…ÀtîÃóÃôÃUWVSƒì‹P‰TL(P‹p ÇD$j)é”P L Š	ˆL$‰4$şÿ  vÇ$b¹@ ëA;$rƒùvë5Š\$‹l$8\ tåëéƒÿvJP
1ÿŠL$ˆJÿG‰ûGˆ]|\6 NJë2ƒùawzÿi~‰ëˆZÿëPş© àÿÿf‰jşWÿx
ˆ_ÿT)ÎƒÏÿ…ö…aÿÿÿÆBÿ x‰hJ‰PƒÄ[^_]˜R‹XCëp€n €vë*‰ı÷İŠL;şˆ*Oëœ	,9‰é„Éuã¶T‰ó)ËÊë=kßw
Œy‚ësş“éàOÁá[% 
<^ÿŠNÿ1öëˆ2F9şuøòsÿŠKÿI&\
	‚‰p‰Ñ+H‰H AXšf'X; )Öë	B9Êsˆ\ÿŠ„ÛuğzÆm‰Ğ	
ÃX‰Ç‹@@6;ƒ uƒÈÿë2‰Ó‰ÎèP#ÿƒøÿtíh•pXñ‰Â‰Øè¤SÿwÕ–RZYIÀX" ‰Ç‰Í¡w ‹‹Y…ÛtU‰Ñ‰úÿÓ‰Ã]ëQ‰ĞèHGËÿ…ÀxC%ÿÿ@FpÿköÆğHIK	ö‹F	é
è`R‰ÃQK é1Ò‰øè#•_¨èT‰Øœ
·PÁâ·HÊW ÁáP@È¹_{ ébSSìn‹”‹J …Ét{ÿÑé\a è„ OYˆ—PíX&Û&ÃÏÛ‹C€x5QÔ\iu%k¼@ è˜DFÿ@…o‰B ]¬Té¹W
 ‰â
şÿH t€|ÿ/tÆ/@=ov¸x @ H›ƒÀ$DßW  1ÀÄl[Ãè×rx" HkÀÕÀVRƒzWè0N1Àq(Y ‹á=4^òº	ÇÑFç¸kÃè«  %‡'º<I¸Ô9U#Jº Ÿ@rBŠ„Àt< võ‰àè@Y œ\¸l½~$j‹x|$V1x\ ‹h÷×‹@!ÇUCf] 'ù‰Nƒëä„T•‹0‹Vc|÷ÒW é˜`Fè9DE‚x]]§l	1Éº¸ èAK\QA$A+¿x F
) ‘T  ‰<$9Çv‰$‹>‹$D$‹NÓèT$#R‰Á‰êHÿWZ‹¶ı)X	Iw#ÉjèÑOfÇCM¾Š•ƒ@ …]\MLv¾ !ïIMù@XèèNVX% kï‰{‹C(%*÷ÿÿ	ğ‰C(ƒÄ$YLw˜^1Àë%‰Öî@èy@9ğsé¯KƒÂ$NK…V­`Ãl‰ÖAXè*``CDT‰pÇ@`ÁëIs@TXèëjèäy ó@uÿKtßDA‹g‹OcR¹h1HØ[é’U  X´Y ÿP$1ÉCh—^sèMKEX¹@t3S(âÊ‰	[	€	ÿQ9ªéÕT&XF@]  pMCö2N,w‹8Y=Kå·SQÂD$P‰ğG5‰ÇYª uUƒ6P	¨3‰{ Zx“h¶h4[‹:Y
 ÇÓøAKÊ]¬Q\A¥X(†Ôş)…^ÇS‰Æ
faŸK,ç‹8©Ø* a‰‹	^øYÿ¨ƒìPàp‹$ƒ: tƒÂ‰$úpL[uêéEtÊÿƒ<$ „F`šB‹	…u|U|NÿÑS[ƒxU
Véì_Aè2^PLãW„ôø“p ÿFpİZo|Y‰İ€} /Eu	‰Ã½¸uOº/r¥TIÃ}mÆC; uëCŠ</tù„À•À¶À÷Ø!ÃzuV%|ı 9ÙZé@hŒC º¼p»èèâS–¯„'aa»¡É€u‹n…í„_ÿEI
)H
‰îéö ã‰òÿQ,W\eD€ê©Ü
ÏtNÈğüCğé©n±wJ"]DG‹Gƒø
…™dwF]8D4şR  DÌ,ƒz0 tkÿL$te=TŠ ^èàBÛ‰ÆUS±(PøÿU0…À~:F$Æ;ë/H	‰ÚèÈR‡œè`@Ï‹_ÿCQSsß‰t!Ï!õëiRBfCè;\1ÿëH
ƒøtLëê…Û…ZRG‰÷™×ÿt&A>‰|Ç@h¨‰ÇïxHÁÿiÿ«ªªªW·ÒëVèL
PHë	‰İ‰şéh	ĞƒÄ˜šp@¼lĞèeınÖy¯^ÇC$xƒK(@ë%f‰C3!@T@‰C$ƒc(¿[ÃÊğ‰ÓTîàèæû[àèš
x>
ØáˆIkÉÁÏÉ‹QqÙCšÈèaHkî‹R‹Z ‰êUàãèlÎ„ux¶ ü‘]!Ÿ#Ââ¯JkÒÂÍÒYşĞ‹IK$ViRS tüeÍÀ'»éÅúwéàH¬xŠPˆ½ŠPY 	Gl‹x!-,fAÙ

hPK‹Xbîzş4KG/1É#Ä1dtëc£Iö3)ÇLb ë/
÷u% *Qˆ	ö•Â}$U·D$PWV‹D$èOU Ás‰q¸v‹t ‰$ÿR‰ÂƒÃLb\…yM‹…Àu—ëZëşƒx NÃ6FHj„P(…Òt”ÿÒ£,x @£0^ ¡S f£¾RX¡ ‰ÀJë" )x_a¡`Dªë³h¾fÄ+C^ë™&-Ç„L™™Ç€'% |'% x'% tT n…Ç}…¤E• '% œ'% ˜'% ”U …'î y(E @„/·\eÁà
-`0 ƒàğƒÈ£dI¸~éÊL¬:!3‰òƒâÕv‹H"0‹y‰ıƒåMu(| ğ‰,$Í9èuƒæğ‹Lõƒç	ı‰i‰Q‰JLY	ë!ƒæüƒÎ‰pÇŠ:‹K	‚H	 XZe‹@A‹J‰ËƒãKu:‹X‰ŞH	 
<09×u+ƒáğñƒã	Ù‰H‹J‹Z‰Y]JW‰H$R<B[-\Uƒèé7PS!2 ‹PÑƒáQÍrƒâ4‹Së,TxÑ9òr‰@RH@	ZV‰BN	éõX„
9Èr	‹R9ÚuĞëÚ#t!1Û‰ŞÁæÆ"FLVu
ƒ8uèÁLP9ğuéCƒûuÓOÁâ	Âxy¾™â,ÀP/^ë~!²"‰õL) 9ÅroP 9ÕrI‹{ƒæD')Å	î‰rÇ–'sW	Æ‰O‰Z	*z?WPƒ!‰%	-mPW ëP/ˆK‹S¶‹SZë‹[9Ó…zS%1Àë"ì,(€Ö1ÒéB\°×~Ié3y'9 $ßQjwÁ¿ş|u €û\t€û/uŠU S€ú  /tˆAEOwŠ]ÿ€û wÕ19Áuë‰Ñë ‰Ş)Î€yÿ/uQÿ9ÂuëWÒëÆAHM÷X¬µ‹XK‹@[éC'¬
"P(‹xO€±
4ƒøtvƒø„† ’í…ŸdÄ	ÕÑíÕ‹K‰èÓèÃTÿ†Ç!ı!ø "x>Aà›H9ıu"¶<(ÔƒÂƒÑ")N¶HgÇëA®<Àø%MÃæ
C‰øÁèë<!×LÓê1ÉMKl·8ë#•)q .Q‹%ltÈèX­NÕ‹"ù"â ‹N$‰L$Óí‹N(‹F‹Vt¦MªY:¸x1ÓàDÿDD$9ÅƒS‹Cd
hŠ@	­ĞÓêöÁ t‰Ğ¸!20Cl
p9ìw-;Tr'w;G
r+U D0Ô xë
‹{X lhGş;FrHNìÓàóét[O
sÿMóúB´è€÷ÇëÑ½pr
ÓåO¥Â­Â>UT‰CH‰SL‰kTYQÅGG9ø”
‰ÇF‹TH$rßiâ‰SdÇChôèRÓà(El	pt[GêƒÄª,‰å%â6EğŸVJ‹s1{Pc@à‰UèÇEìt	 9}ìwr9òsA…ÿ…€t +ğÒ!Ğëx‹Eè‹Uì)ğú‰EĞ‰UÔƒÀƒÒ ‰Eè‰Uì‹C,™‰EØ‰UÜ‹Uè#S,‹Eì#EÜ	ÂtB	ë=Ğ‹UÔŠMà-„P‹Eğè'
@N1ÀL%Mğ;Ks‰È_ÓàÒ&5%44R¹
_è£HV2VÅ
#.3è“¹d]NšH«fì4^x‰ÅAHL‹]@D¼uÓî‹Kdƒ{h u9Îs]=\2`«ëlp•2Erëè·†;‰ĞLëA9ñrç‰sõ0‰
‰CpY4Xª#È8‰òÓâZÿ#]•RiW‰Á#~9Ã?B<`úRÓæ!W()\ Á| Æ" R #ÿQ !½9éhIŠ„ÀuJ:édB”<åú—tW€ú…æHˆÃ¨@ŠWt%T#ƒã?€û‡rS¹
t›„$*Wè¥G^–:S…SA:W…IDK¶ÃkÀ”xúèŠMˆ&„!I*+P!©3%ÜEPf‹
ƒÂt¶Ù44xWf9„
uŠVëf9Œpl[f‰ ˆVˆ@ëBúDö uİƒÎÿëf?ª!«>%÷Ò@×Fÿ={¬†`°s €â"œa|Z$t+ 1ÀˆÁĞé¶ÀÁàÈBƒúuëY#Iå ¬0Òë~ 1Ò	€ù töGtŠ‰pkR@Tuâ€ t'Æ .@º`)± ,± ÆLJ‰Æ!=Ny6f6 ë¨8	ÿL$ƒÇ ƒE ƒ\:!ù@8tå^NSlFJèh"@0ÑƒCdƒSh ºv	Â,x(Ó‰ÂXDè=E.Ç„F@‰Áƒé]¹€¡d$ëNÿWÁâ·G	r‰øE|O‰BA§BAFƒ€ú
ôƒâM½f‰P
pÀoèOEPŠH"LJlf&Î0¹‹äèkï" -uhÛ~hëR è,"IP ‹K‹Q ‹I‰HXƒÉÿ˜u¿â!¥PHUğ"è-IøH:Xp\‰X`Ç@…uÃ±t(@Aoµ*‹BW‹Z`J­èWlÀ¹ˆ÷ñƒøî#šN@ˆ		¬UH €8.u%‰ÂŠ@„Àt
<.u€z utNU$!Õ5L	)ğëOQx1!2;AhõS  v<.5ëÆD @ƒø~õ¸l@
ëÙŠ’pj €úåuK²ØD
~¾ëû
~õj Š@R1yw­t|Ò˜0‰ÙèÉ;VM¹7Ø7p é-S€~à!=?DŠFë<]zÌnÈVàEz^
8
‡…ôH¨@t*ŠVíˆT$ƒà?UL_Ö ¹´}D$ èºëD8Fí…¹t	I	JAÂo}T$ C}Úè¡!™3€xTt1é›_f‹
\J"ÄC/¶9Açÿw;œ?zxt…nGëeM\)h	…ÒuÅ€9 ë	f‹ŸAuFNñ¿këE¨	Ø7!);(Õ/Ôë¹j¨Úuá:L!‘+A(\@kƒÆ ^à%YNÅ¥f!Æ?ùPjFG‰Ób	ÚDØRéÁ\	ÄXR§ì/h6MXOR ‹S¯P
—·S¨i KÊ‰PX…Ò‹Uu‹r ‹R\•[öU[Mq·ñt[Uë[ÁáUs 
ñ‰Î‰ÏÁÿ	ùu‹r‹zëƒÆşƒ×ÿ‹J÷Óæ´à ÷1örz‰pl‰xp‰p\‰x`ŠS-”!ş*ëhrdd‹réÊü$7*ìtf"¶_‹Fp‰OOºˆKâ‰W‰Wj jL q•,!™JS!JRfM'*RM©‰©,IJ¸8béìôU(ÆŠ$qê$E5E,S ‰G"I:2|,ME-@d•·l$/f…íu‹l$<i*IA]%ĞW|Å‰‰V"#<,¯d5MV™YıA|tJN¨‰VN\$-!"G¹ K	™÷ù†RO`i
Óø‰F ‰$‰ÁÁù išR]&µ+VN| )½Ø‰^$‹WÚ‰V(Pÿ‰V,L	!J'F0‡1Ò+BˆÙ-)Å=ô  w	ÇF4bë]ÿÜ™[M@M1 Xÿv½x PD¨€tƒàš™Yø UH!æ#ˆÙLÁ1Û$\HN‰^‰n‹W‹Gè~RG#G'Äë@Ç¼!âN¼°!}2ĞA¸véuÖ&Ğ#¹ô‡éŸf`, ËƒèŸ!	"º"şe€;ğ‰Ø!Rèï?oAÿ/H&	uºàr URSh]i@ ²ÿHP@%aYIL$aÚåÿ"«)@t,fO:LO;Ê¸!‹,è3ö0@u"ÖMJæ#õ5Ã‹.!êO…d"EjÇQ!këç„x%ßk‹PYÉ&ğKĞééÿÿ\%LU‰~Õ!&!P^	(‹\$$ë5¾Eş!ïV¯Å|ÉˆA ÿÑƒø }^ëu
G,‰1@‰÷9û|Ç#Œ1'ÌL!ÕkX'Hò9Ówr9ÁwE!¯,ÁsRë	€qt['´- <‰E¸‰U¼‰EÔ‰UØEĞPÿ5t‡@qhn MÔºrY¡lNè3n Ä\i	ÿEĞëƒ}Ğ uD
‰Âë@‹MĞIÁáh $‹‹Q‰EÀ‰UÄ‰Æ‰×qy9}¼wÒr9u¸sË‹E¸‹U¼+EÀUÄAQeôŸ¹œc@é¢=&'9‰ÃbD‹ ™ík!D‰÷[–‹EX\WV\iè/I  ZY1ö#XItƒ{ uE#¤+!‰J ¯Øèã1a‘]Tµ7‹C‹P\‹@XQ1"Dó„Ût!‰ËÁûSQèŞHb
)Ç]!Où#šSÕ<Uøè.{W‰Ã#Q"/!ˆHDxNf¸  èJğÿÿ£m¹hô!W.Şó¥!=I‡$'Hë|zR+¶‰Ù“-èËıß,tX¡y=`uhdS\èb0" K?‰Â‰ÇÁçë÷î€ó¥J‰ïhÜoà9Ê‹5bâ·!¦Cò¥×f@£i
[€\]±x
V
‹TD÷wCrH9Ëw=Er<#| ŠZ8Xw2r-‹H	‹X‹B	‹RCKrILGrKLë!I2
Y€É…È%`b+r$MÍ*1ü ­@['Ö‹ "ŒSX¨M1,l²LedCU·‘uA=l `@70èG  ]Z‰Å/a !˜QY[‰Ñ‰Â‹è×2œ÷@‹$)ëQÎ0[
;…,vIC,i(‰Ù!Z&Ø:aS)EGŞLxQ·(N
0^
uuº+D*«~ìLBHXÖ‰Ï‹¬$(qĞ
eè{LãdÂ_Ch[YßeMl ]– #.UışŒAYßtYß¿nqÔ|!ÒLèe"RP‹dbOĞƒÀe!š;RP!Ù3…»ØèÃD¶„$„c”$€d@T…@‰tÅ ‰|ÅLŸQRÿt…`h¢ GvŒ$DJº!X!6•~PCûm E#d	¶T$t;D•`~H”/í‰OkÀ!†oŒŠ[ Uÿ´²Øè"ÖN‰ÃDéæyØ ùR‹„›¶””_@‰u
}Y#
ÿu,í)î‡úl=ö‰E]Th4Ğ½w°eAw¹p	ó¤Å#Bf°zH1ÿ-LëWV‹@1Ò¬d¶Eå#‰ê™M¯w‰ØÈÃ¹@Ä˜@!JyNrÀn	AUWtW!*.l!8$D?H$8GDÅ!ùeéMWAÛL8W'‹<T ERœRZYGhzOƒëSŠ2"\x#ß_Œ$Õk´$Ö{ ¼$Ú{ „$æ¹Aêœ)H "#„$îµòY €	
Òpthœbñ+HhP¼# I^P YËyä!ˆ)Má(DÚ,ƒÆzƒ×a¹€ø Æ×‹CDÿŠ$Óèë3YZ!ö.ƒÀHÒfl(Ü&XH@-6#CT9‰úèOùÿÿ1p #XJsX‰{\"Ù)Äø-gy@»|ˆ…ÿt"‹q`F9ş}‰q`QR‹‹Iè_@p^_0Ûë$$‡xE¤Îˆ ‹L@…Ét1‹T`B9Ê|Cƒûuéë ‰@ÇD\x‹Ş‹LŞVWèJ	XZYó„ìû–ì°m>Æ!¡/("TPU-UÜ=T‹F”QQÅ>F>÷øe>|
W+ÇèèªIrYu×UV”o8øèšXCYÏNM/fFE­eZ‰C!_TŒ$ÈrA"¼j!m
RCIËneÿ5Nl·„ŒÆD %gNÄ°,	¼xM–×]YîN&ğ,] ŒTíQS3NV
yU*j~èäF[Z|V1ÛéÂ½RÉ¡RIí©µÖú"z=˜ß$@tÎ‰xn‰Ctz % ğ  Áè‰Cƒàıƒøuvml.L^£÷\0.Xú¬h…pÿ…Î©aÒ©aÍvuH"!$¯zT~Qj±t\ÿğú‰CX‰S\a~¼õ%º`ö1ÉéÆL˜(Ã€=¼{„XXF¤'9œ&ğ‰'9tYAğ	}öh)¹A™”xA!m\ùÁ€!…7úA D‚ÄCC†è~P0m±³$"Øyƒéº|D¥{Éèå4$ñ{¨oL$M«E	¶#´rt²ëy)Q Ø³hûfƒ×'!*"é‹Ñ„pI(ÿp| Ñ+UP-òŞø-e-iY £n3‰l3Y[ëJ*"µ÷‚„oBë€È]Y¡­EGRéu´+]é",—'$Ãö|UD;\i3Ğ‹3ƒ=ÌX!Ÿ4ƒ=È@vhrJô&!˜ j
 ,©ä1©4V=õ(µ˜•œ¶ğ÷l„I´êâö‘)*N Îö¸bÑé¥c½¥Á¥EUÍµÑ´e‹ Uı¶”"u!(U©,	µ,U0#İB;R‰ñÎ;Åú©Y_%éhÿ)e âÅ?…)Ğ„)„‚#:dpÁ"-S\è§óÿÿ‹ƒÁWV`â!Õ|>\ZÀÆDH2\ ,b$DZ'°\#šF´æ$Ä+#'51Û¾TóTmhëkË¾ @po,†B;=xr‡³N;5{
ƒ§L!v-+|öY)m¨õŠô=*S†…dÃ|$Muu9t$Iuo’º8P?H$YèÇ1wcuX¹p<A9U	!C…èÉ!".ë	8¡7t‘!W˜er- ‘!\*9T$av"¹`W¸@Zè–H]aE‰e%ì'AË£'„+|!)µi !´ !ÁD8!bjÊ¾ˆ¡!´l ƒâ÷Úâx;ö‚1êNuì‰xóAùdTuÕ‹O‰K'kESÇ ]{TÇC"­ˆºnèÓPZY:wT“(¶¸€fØ0”z1öëY¾qO(·†¨X HÁàta‹‚tW‹’xT È‹G‹Wl·#>G;?U#ò]GCGUU!„ÈòAKò	gàq5UkHŠZ Õú€E%Eh )”¬è"½U`}+øBnŞ/j­ºş|‚Š1Ó‰ß$ PÁê3½”#!Msäp-^ñ(°+šCôAÔ^A!Yf­¬§h¨IòT–$œK'p'Í¡0#ğo	T$D‹Zƒãğ‰ZG‹>489Îw€> uƒË^é9D4…ÿuƒË[Šˆ!´ˆL$Àèˆ
z<²N€ù@"]!áb‰!úeóW ,1Û-ëI"&¶"‰I!Ü "0•¤ıÁç‰|Dl$(<1Ï‰|$‰ıÁıF dLTÛ!3(rîKŠP!ö¯‰ø!1gª!=9‹"µGJsZ#aJ"²¢ğh€8 x1É1Ûë"µ6ËNF'‰İ(ÕMA|5"»µ	ù[	NŠC	<0ŒÌJZ‰J"ï|Ş	ÎP"JëU ˆ"é._kK'åp0)¹Ye "Xv!ƒL^PHX €{t ue‹“©‹{É‰$#N‹N$oH‹#	s,tI!/”v‰^C"P%twCTéİzkx!ÿGƒ»t!ÉWº|ƒ‚®T "™Æ~Exc‹N)‹E‹U?Íƒn‰“{
‹N%,Ğ øI
u
},hY;$F.ƒÆM×ÿ«şÓï¦ş1osT‹fvCxF\MŞE\-€	&„RSH‰KL'ı)ı,#ër(‰ËE	L!˜3!É?U!!ˆ)_-ŠM"ÔtZ”!€DL“Ü…	ƒ|$D w9\$@v#ípË%0b\$H‹‹Kè9#%¸Ÿá‰ø	ğu-LjT‹‹VŠ-Äz&÷<è!7!e"_"èI&ˆ9#Hxğ’L$D9Êr6wd@9Ğr,3Q@P(èñ*  \$Dñû‰$‰h`!"2éÛ$u:@l|ğšE$ Ä%…&ëß4"Op
@
Af j_è˜`"¸5!=%)PøL$òùàRlBU_T$xQ9ÑrYXÉ]59!ÂN'L%„bK%è"§$„»\ ÈYZ$‹q}tW|$.Ä„`Q€«GA¨;H!6G
;R&rh6GL‰! ›X4P tÈXP‰3‰{U-Dl óè«4"\Ek4h"…,)0"Şh‰ÅxÚ*Å_$&Ä_i<H"å_"Hh"¹€L”I%©%I©&IÑ'MÍ*M÷PHI4H"Ö©éÇP ­İG¤ûè…)‰İ"=bMÓ¾\$T„Ûy&ë½Pı]œtØé£N÷Û!¦yëˆ¡!½À½ÛÃˆT$$P}óÓã‰]¸;bíHÜ$¤g[
¸YC
è¼4‚H‰ ñtšHú‰x%}‰x)Jÿ‰H-"¼fâ‰P1yrz‰ó]uV
Ø™`A!³•‰QIX~ˆHL«L
½Éù‰MÓæ‰u|[hE!"–‰XA¡%IX‹s4|$H-d@-A -g0‰x`m"	pÁM šÁXDI
<I
@,pr+@K  wrƒşôw–p!ëoÇ@Qíÿ	!xd
Æ@5Æ@6 Ç@77RòUn\{‚ë#¹3pú3¾'$ù25F_éP #â:)(% ,‹
ùINDXtùFILEu,·ZÓf‹;f‹r‹L
ş1ÒNëBf99uf‹,Sf‰)f9Öuì)‰DDŠP\Uu#??‹Hi€œÍ!åœ|Q €5L~½ù‹X)",Ú#´OAybA³2“‰ù!XeJr‰Ç!ƒeï‰øHnNAQ"Á`<A
@!èSÕˆÙ¥ıÓç±*ı!Á-N_4ïÓí ï1í+AyDúM
!ıyv},M}0‘·FP‹ øê&X0R'<PNo8RF4PR 0PEyl Y(#lğè !_&ƒÄC`hƒbâ%å°&ìÿ]÷#'vFBÄè¶8•,`‚	9P,uƒ|$ tr[
‰9!"¢ëjI4U8j‹~û!Ò]9Ø}LEŸ\
r*!~Xúr"E˜,Ø–ˆ"€!	ƒÇƒÕ +8héUFÿl”lhŸ_ 0é#)—$/D)q)ÓE3*ıh5ı7Ptqoñ
)‡½ÈèzB‰Å(	ğB‰ñAs\—CrÓèU7O(õ8Y	<"äWs¥Ş
¹5Ş!I¾O_7óÓî¡ó	Í+Yj"²($Y7wy(ìx-XØòY
 L"!{8z74R„7Q ,y7 l #uhê!fHcøñ7²7%#+kÖ!,:I7j7G
èÕ!.} œ6y5¸5‰‰qëgE0XWF4‹Lğ™9Ñ&DDr.w94$r'U(Ä5”bƒÃjÖ ì#°¢x'±ˆQG-,émè+@'´PmÓ¶zPèû  $H/9øuJ1É€{QHÑë8·|KR¾9×u3"/îë(ŒW¿ƒúwƒÇ zj	ızÂ E	gØ°%èØ(à™p‰U ‰Ï…Ét‰ÃBu™é`Tˆ!«ŠøD£ƒúÿ„@Jƒú m
;U ué>|ÙÆ@ëß‰e‹K1#E¤¨‹ƒÀƒàü)Ä‰eœÇEĞ†%EÔz €~!ñÛ)Nñ"pÑ	ğë‹U 9„š|QÑ9Árëh¤H8!¡/FğŒ%¬€EØèv"q	´p	·F {ˆ‹U]„TP‹MŒU´‹EˆèVóÿÿ"ÛMh¹tA  ^1ÿéb#Ä% 	ğ¨töEğtÊë”¨u¨tğ‹Eà‹Uä$'oÇE¬µ°y é#>YEÀ	Ä	”	˜¬°U˜ "‚mH)¬, &@%"+ú`‰ĞÁú‰EÈ‰UÌÇE¸©¼x UÀRE¸
·EÈ!µ_¨	 ¤3„œ!Â8‡õí[
[é-|}Mœ‹F0Èë†(t\'õï
!”‹,`%‹¦™RPU3‹hèï!§[YY1U°H;Uì‚W
‡å`›E¬;Eè‚FéÔ` q‹G,1Ò9Qu9ğt‹{MĞ‰ò"™Í7##ÈhËa-®!FËX‹‡…¤"ÈÁ!çÎ^ é™P &Üs$8E"hP‘9ùuëèbpÀu‰ùp
ZéPD#xYVìlLJš•¨}0"0¸N‰¸vF'Æ	¥¬a^!5.h!3AğÿS'…´şháeF^Ç‘;2!(ÿµz‹v º$UVQ[h “Qé±dNPƒ x!6Â€y!‡`Ğ!|ÁD‰G¡{1Ò€!‚¿„#8jWöBt)ÇG#/*Æ@Uı~1Ç@$VM@¹ y ëù·JÑ‰O"|ÂZP‰°şÿÿëŠ\JRˆœôSA;orì‹ Æ„— Šx €ù$t€€ù.„wu7p!‚A
J- ½nN‰…`	"jX„#Z€x[t
h÷|"ÅµŠ˜,0¾…œn• m
•e!’œ•”
T şv…ØSè»V…¼Ü.¯·AğÈ¤ip'BV‰…yë	Â•R‹f
•e‹‡èxï´{
h(sMO‹…ğDB{ö„uë!ÿ¨!TLq™½t u§ëÜÿCé^thœ8‹A‹Q;•ìt* w;…ègÇA©3AŠ3ÿA*nàfä~Ğu pdÈÚ4‹I%-N.@ /J…À…)ÄW Ç…ÈË$Ç…ÌÅ™QD„’PŸPÿµk/ÿµœ‘:˜0|_V:Sñí††ë!"à"—èÓõxj;#³(hHZ(èòW[éÃh¤©1…oƒÀ	'˜Œ• rQ
ÀC£5‰…ˆz5};—‚’a…)® A¢<JûÈrˆ½p\9Á‡dVÿdŸd5‹F-À‘L‹“Lè8'˜–CSÇCšgé9kÊƒ½h!4vd4@! Ño
…”W¶JP †ëf‹LBRˆŒff@;šrë»Æ„¹i…z <$	ÄI
<Ajû˜>"€}Ry‹‡‰èÎ#:.éœh[ˆv!}Šm•‰	G	}A!è{!JjA¿‰•ŒvÍÍ^~!øÕ‹D–]©ÆaqN!ÿkf‹@!ª’f!JÁÀb‹€ f‰B
K‰Ğ"¡¨•cè$šyzÍlëhbj:B&éOBhs^ëîí°U#åÕ‹8!IŠ^t!/%è²R‰Â!vtj!ûf‹_+Vu¨øt¨"­ì†¨ëQÁº€$Fn0ú†qu—¤è¯!uë"d\L¥Â‰èèŒF"V$N“ÜÌV$!+ÜØèĞL!ÊGĞ_)Ñ*8‚ÃÍÇ"à®$€%$²šx"hfl##<åP“fénÂuh"#,f‹B!2³ElŞ%&ôš-zIE|à@”b•”%Ó)ö@AEz]	é"$·­¾¾P€=[hè ^Çxa ¸bèQU-£¤!­,–q‘·}
0iC¸e¾él½
ŠCˆEt‹‰Ep€{L«!MÛCGØ	x!fÌéŞmSÚ"€5!½VÜ¦V9‡(ØeM L"
uExc‰4$!2,PXè"…"”pè]êÿÿ^#¸ğ#â#`@Õ4!Á§Í!½#]!¾#Å¸sèÌã
¸³zE%`ÑŠ.¹d	Ç‹4$ó¥ƒ}x uT	ë	‹|‹ ‰B£| &‰X!#G élDM—
hÅq!|uqCuE#ó®‰E$q‘Ê‘TT’ÈÊŠgëFQPM¤ğ!éÿ÷K…x^[éihå€¥²F‰Ã¬!9¼™mE~•Ä8+­+l˜‹!&! ¨ ïƒç‰şƒöÓæÓç‰u¤‰},¿*´‹s%ë ØÿV›E¸(­	öDÈÿu¸‹M¸ı4¼&… Õ#	-xuÇO‹wÎ;u¸‚"Ó
‹GÈV9Ğ‚©™V	…òu›Tf‹FT2 ‰ò‹E˜‰Mˆèé¯„Àˆ	51”FÆë±¨I×y*j(- ®¨öD!ÆX…ö„n^$€~(=a~	—÷;”)&-,'ô)&%-O!‰EŒ$$-
”U¼‹Eèèÿÿ_u0š'í,#ï,ØéˆDIIñ&è,"Ê-é,Bp uĞ‹}Ô‰uœ‰} ‹u¬‹}°uœLˆu"lN.É, -$™.È­Ì˜auĞ‰}Ô}ĞW\ä!-EÀ'%-Œ'´V$=ê-%-![CWè½îHUu´>‰â
Šâéx }´ƒÇ‰ş‹E´p;u´‚åŸWBÚ:Ò *YÄUöuu“:èòf:ufÉ9ºœ	 ¤5Š.L Ew^%ˆ.}°;}	è²bì‡~)ˆ.zâém€¸è~Ç#óòW¹@¼‡!Ø¿YBÇ€|"wµè'!CÁ‹I‹#¨s!é‹ófö™¹<Fëm	2e–ÆèÙS_ëôÇ%ÔÛ.á\páº"È«lgPØuht^™p"´eÇp¦Vöó·gh6muOXé¡”(DÇĞ‹KŠPˆQ5	 6€xu'Š@	A)P&%ĞL	ëşÈuƒ~,u
¶Ì5#ÈpÆÿÿ(&A¾%µÅ!Z+‰Yº|ùƒ¡‹†v{‹–j¦‰†Œ–"!/ëNóèJ
1öAÀ#ÒÜÃ!=3j	H	"›X‹#†àk$\§MÚ×$XŒ`M‰òÓê;ps^1ÉèÃ|£ uN#sÆ‹‰‹C‰G¶FƒÀ!n·¶V!|>!5Ìw•0!äÃTNNGç,H&\ÆDfy%Ôb)a‘ "ùgPOs@‰$9Æw\P{4 t)Ñ°Óàì9;Cu8SX‰ñVBÉ\.‰õ;4$v‹,#Ì]Ôy¤è"{)Â]¡\)îï…öuÒ(„s(XáoBÿD:!áGq:Ö‹QNgr¼hbm@qLÎ!Æ©é¬“6÷q!"Q!B†X"T%	
  ÁåÅ„‰p4!9[ğ]1A	U	ÕÂ²õ	té
¯rÆuëb¹<q8úy¼%iN	Zf!+·À"ğ"åBC G±‰C(!hB!6ı‹F!‘ğ, 0h4V(CX—
è¯#•±ÛŠºm'eú$#?MÖ‹vöƒÀ$0lKè$†ƒ1ÿà.&†˜éeT¼ÜFM¡ı#a]#8e	‰ı+n9Åv‰ÅÓoEøX ëB‹\$$[‰è+L;Âw7ƒ; u	 !ò½ë ‰C9Ruí v"İO‰hHB_Ùëy: "bãµƒOƒT@D8;~‚"œ„![‹h$àé'#`-ÕÃ#™> T%4!Écm H!)W# Ã|$8Sï…"\3$
"Ä'zÃ·t&yÃfZèMn	CÌ!-GÎuDKU^!ÉJÀ`%#€ƒÀ
T8#6€‰×Lû{ˆÁ"X€"Yß(" ˜Q$‰x·":aC!ÍÂ‰€ƒ¼$"@Ûw
fÇ„‰ IhŒ„ÒF³‹o"ÈH+p6!ÒÓ‰Fa9	"eÅX!$ìCPèak1ÒJQ#=K!	]!²Öº#….à„&üÀ|%V'Ã&¿"}suMÜ‹ü
r}èVßƒé|Mì¿ŠÄçH"ÖèÈ÷!õ(à!ræ¯  
‰Mä1ö1ÀOÿ‰MØë8ÿMğ…Òuƒ}è tn|Óç‹Eè‰8ëa¥dÓcuÜŠÓî#uØ‹°‹MàMäT	ƒùÿuÀ‰ù)ñ4°‹…( …Ò•À‰Ç”Ôë9†"¸Íè‰ë	@û9Èuíëğ‰ĞEaÀ"yè+ &€Eğ‹?‰}ìö@2„ìq4Ö!wêƒÀXR‹"NÍUğy 38
óucfƒx xtQ·X‰]Ø1ÒëkÚ‹MÜ;LsJƒúÿu
ë:B;UØ|æëğkÒ×·_‰]èÇEä‰ÑW@
UäMè‹]ğ‹èßN³ëHË1ÉëhkÙ;te
I|	ëA9Ñ|êëñh%ZèãO^éAT kÉù+1·y#¤p9şƒ.$½R!r"IÿÁÓƒ}ì t)÷‹Eì‰8`“"A@é#@’h ‹XÁû‹p‰uäƒù wSƒúwN#¨ì)Ñ•˜]ğ|X‹D“Xw	„Å…¡…"ÄE!¦í[ë_—t
‹]ì‰é£@Bó9ÊuêëíP*
ÏƒÆôƒ×ÿ‰]ÜÇEàl
ƒÿ w9Şsf-‘ˆwóuìjn`äŸJä‰Ú@eñ‰û+MÜ]àX2åûeÑEu–ŒÄ
ë(‰Î‰ß+uÜ}àmHâd9Ös~“İ
è(S—Y[ë”&*å9UÔÑp+p½ŒvñÓåMÊšÓê
C$P‘Ë¸`‰Ñ	ÁuÇCH#Æ”CLz ë-c€é!ù	‰K"¨¬p
ñÓà!ï)ø‰CT1À_%ÜÊ×*¸©}U‹‡KôëıÌ–! [ P‹Œ ºŒO~è`š‰>`!õ£lv",ŒGÚƒø
!I!a™î\Æ¥‹ ˆœX Y€Y ¸"§¹[é[!Z@ëCèÄÿÿÿ¾2óœL""WÍ‰ç$¬İÖó¥œZâ"$î\´(€åı	Ê"ù`UH©RPèË®#œ3q&H‚$Cş‰Í"<ù$~©@%ÿO‹pF”)ò!># €HPJÓê9ÕQÉÕL|!Ê†a”Ó	ÌS"¨€SD9Ğr{8sH#÷ó¥¨
‹KD49ğrYå@	dDx6_BÆ)Ö])’KD!×7‹S<Durƒøıw&©8	g<'m’S"ŞhL6!%qélúƒ{T ‹s@t09SPt	EÌ!ØÿQ8I÷To‰sPP!~ò±6|\ã!6hó¥zuD!>éCThï]F!HPÉLE(1YÈ	%9N+uLã$u"èn}D"‡loM1íZ‰îïÆXäÁ÷Xªö	u?uô1ãèÏ	_!j !p X"¯$ÿP(K‚s8CÄ	,L s@)sD)õuií;­vPWS>A"&‚@ !üe#”ƒ@’&„$-%ÑL:ÌÂf‰xSÌçÿ_êW(hs	 J$«Èoƒè'ÇtÖ÷f‰C·Ğ‰Ğ"ÛX4AJkÒ"¤FÊÇlA¸ ”4Y¯$!ã]pÇ$É¢@"Å}A!%KÎBƒÀ‰ù·{9ú|ÔvÙ‹PdL@
"´)EJ!\.”%Ğ[d!º0^Zçx!¸* 9Ku9tƒÃ@9ø|ï‹^EïE8!!6'‰Bp`@"¤&• Xs
 ^$T»ba‰Åj ècÃ9xk
0t#ü†‹S·Eè!¹÷-^ÁƒÄQ
*^›ì#ğÅ"t Š„$ÀB!‡š*‹M"ˆ{‹u ‹}$‹E#'Œ$<œ$"ÈO"÷Œ‹E!?û¤Â
|]‡"Â†r!Sƒ}x„œ#>™!`›%øßQœ¢!™ Š[ƒÀUQXZ H¸ì¼'$‹( )] Š^Ól#‘t Hy•OŸÑ$¾Æ™î!Qì!|œ!ù$ W v	Rd¿~
‹Mq‚#$#\S^ utdqf+"Íx\#¬Ä"rA9ÃS^Ã9ËW Ë9óV ó;!QT•
+ç€"
Št#MxlJ"›søè™!€!!ñˆPQIMQU™"¡¢P@	Ğ^LŠD!9‰I!Ùà"™âD e0RÿGw2¾X#"¹¶XSŸ,¸e­!Í*ö$ÄÌt[NuáÑët
d"Ş ëÎknB¸NPø£¸FL!Ğ$(#ãx´$¨pÔ¹ P"=À”bhVyşì! 8L#!eÓ -MŞ…æ]+!˜È{	tPå#©¾±PHyv‰„4$!“Ô)œŒ&Kƒ¼ˆ!JZdş…
$,¥dL)™´`N#¬…ANÔ£N‹NcN‹FiMUE0(¶t•E‹BKU‹f)¸Lş$‰ÂWS'T$6Ù)<ÔLÛ~şè9}V±N*”#ÄŒ$"èD+©	ÈMHM‹l$æ¶éÖ\LQCQCĞ'r‰ê…/¸‰ĞèDw
‰ïıÄO@
„OÙIïgHtE*@+…HdH#5X46ÉA[ƒâ#‘‡#C¬fÇx"&<N@U¥,
Ph[f£Rd¥‹§‰Tb$XT II\II0ªIÅˆIt2!‘l®|B$uœ1É”&µŸVÑëUK"­Qty÷¶M0PLHl6Ô!Lt+F V$„¿’£ûp‘Ià@e@À
9ÃuÇF(ÄT é“|ÙUøUIÌµTÌõTŒ•TvTF÷" ë['æ$UstI)ú!ù]Lh@‰V,$EĞœ¥?”˜
]UĞ½U]UĞ½U|UD"©#´ôU$”‚"¡Tœ÷vj P‰ÃÁû‹L$¯Ëhn
¯ĞÑ÷d$ÊRPSğÿV"È7(kã\‰Ç]¥€„^]~Q	xe<IL|(;ôèB¦‰øA[ QI˜›G£¼‹"£¶Å£À\ "R­y5!y´)"y`0Q:¹5ğP¢öD$Xu~4M@˜UfP„ˆrAf[ZªUN,,¯ã…²dNW‘HUª¥ PIEš€g\IXQy J
H'
Ñp,eUät¹ˆNëL\U uí·Œ	fƒøIw¹Je4Á„!ù8{ |=ÿvÀPÿŠ…ÂCh²¹ ”	[w²ë?ì1ÒæB\5¬^£°|'½À£´\ YÁp!í$t	Ìv)=ĞU ¡w#¯b&£ÄQ ¸jT„ÒVR5WIÔH!Uë!`ÀCÂ‰¸hgƒÄ\©é¶T"|ªHûQ]Q´ |n èò!F/£Ø_ÇÜW  EèdPEZ¸l|ñEFBa/O/€:/B/Z/æ#/dQã4VWP"Œí‰úÑês¤IˆÈƒùrSf¥!E4ˆ¸n¨tf¥¨t¤X_^_>WS^ˆÖ4Â6
	Ğ½ªË}«}Ë«öÃ`X DªX[_­åÆ¬s¶:FB)øu9Îuğ1À^œ!vùB9  uú)Â‰ĞÃŠ
ˆB„Ét@ëô}V- 1ÉŠˆA„Òuõ^Ãfë@@Š8ÑuõÃ1À'=1!,¤!X@ íëŠ0ˆL$¶é¶<2F)ıu	M!;Ouä‰!!’6Sè!ï1ÃŞ!\`RpP#„H*èGú Z[(ü¿hèì
u°TQ\T#ûÍt$|#ÙÎL"¶1íUk %•Ô*ˆK&ÊKé›Xƒú‡Š@!H9¼“¨èÿÿÿçDU
M ˜!É4?M N <%Üÿ$A49JsHWˆG"Ä¯"6RéDx	è <‡÷@TP‰Ù+Œƒüo
á°N­ ¨), m ¸-= Àİa)]  NƒÍŞ éÖŸ éÎŸ  éÆ é"¸"xĞ‰ù€ù	wk	1

SĞB#é"¦'<*é>QÈV/‰R÷ß€Íék.…
  #,]&Òµée,cL$ Ac éIƒ…l!±K6!+´ …ö®ˆJé)| lt:<ht+<jt<Lë<tH*F;<z÷| qu+ëx4#SôHúUéë`VéâAƒ{éØ™Êo~#ÙS‰—ş}|GÈÿ<n!¶  )<c„£H><PtR<X…ZéèT<dtk<i…
@ëa<s„`<ot<p…ò@ë%<u„³wx…	Xéq¿qIéföÍlÊQ0‹!´ò&¨ïV+¿Ü'…é@ƒ|TPt3	`ÿuëct2x t8¾ë(¿œs	ë.‹­ÇDW5ëê ¾ëİ#œ¾(ó¿
e—w¹ ¨€¡//+¡5Pƒë·*°ìë‹1É&§ë-¢ë#ŒÇüT&ˆ¾N4(9SÏs+$´¨$‰éá‹ğL$D!š=‹È!h:.‹Ü\ MPDB÷Å"îdt»,y÷"H+U AmépTœ$ìé!fÎ‰ù¯&0ëA¾0n è€N6YYIH#-GçMx Bà L8tƒÿuOA;B}xK||ŒeIt`"Ó±<÷Åf:t!íYÿû”ÀD	<Aÿ™÷|$<ÈTa4ìgWû÷Å}	ŒA,M8!d=VuBZ,toHu1Q,V~d"54,X!ù<;P'W  @!ôuñxJ	@ëä8K@ë#gT$@ ‚t*-ë$!`ŸÉ+ë	(H ´±+q&ø0@JW#$sXDÉƒá ƒÁXˆ@ƒÂHHu%xD@~ë(á BMx@Ğ@çt0!ª5T#)åHD"ìµ"}²4]7X!Ş-øQ\½~…SÏIë(B4H]8L "Í´$O	8sD°4ÆGÿ_mI`aOU`'­ |L^s,AA\l '†F‹èc^!ZYPPŠsˆGÿ! Ö3­ ;V¡Y_ô^Q`A4T#¯QLAH¸ƒáŸ;F`sXDÆ qÄD!ŸûuI
vÅ…K@_ H)ÂX%,Ìëá#95gHj„O!Ù&gõLV†k‹!W]“!|8"ĞcÉÿ‰×ò®÷ÑIYŞ~V~C ÿtûW~M wf£uEuK%ğ«0V!qÉ)"ŒÚm(L$0DYbuİ#¾#bG)ÂOëLŠU(İ@Guá$P¯„L~Ç”dxÆ B@
"êEuévéğ'©ADÊ(µ(µ•<·•D‹"ş1ˆJ&1Òê¿é¹yvof‰:Ed#¬ºj•éœ¨P‰
‰Æé'§ ‰:ÇnQè'Õ_ˆlv†"ëa#\8n!ëBp&A L’Òë3h”M&LsgGLº€ªåët—#A¦ëh®TOL‰LŸ2¾˜1L„À…Q÷ÿÿ'do‰Æ9‚(ä5ATtÆDÿ`£ƒÄh&lI!Ê$è¼HÃ€  ‰Æè©Q­Â¸`1À‰×‰ñóª¥_ÏQè‘S­M÷oM‰È‰êKÜ¨"¨z@_!ã[Çó¤Ş}fZ‘RQR!ó#P‹ƒ"mHÿA•$Sè6úL[}j ÿwÿ7èt%eø[¼mV&äfEQ!De"ÜiUô‹‰}"ˆ`h&%¸e	Âu#Í "–_éˆ|9 Uğ‹MôUğMô‹uà‹}äuà}äƒ}ô yâzëHì9	wr‹Mè9Mğw"”a}ô)uè}ìEàUä¤¬şÑï‰uğ‰}Ô	åàäX}àu°ƒ}Ü t‹uè@‹MÜ‰1‰yE0$Ü_Œ!G,è7 zû™Q¡ ½'!w‹‹UôÙ P$!rİ!JUèÄP ÊÃ Á @½£ôM ¸N |i…ô "=xi&	!¹Î m X Ø˜ )N O DM 
N´ ¡Ÿ°N .qúl®	|Qğ xê ^n!ÀşÎ+Ì!Åïr¾:,¾ B®T\,î ú'M- Ş* ı%\Nù]t¾3®²A4î ğG ”D®\<i/!cuÍL,Ì.î K N œI N ,P¼xudqxt|xI|U"¼$Ô³¨X±ÒQ 6   N	
 !"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`8|  s{|}~€šAA€EEEIII’’O™OUUY™šœŸAIOU¥¥¦§¨©ª«¬­®¯°±²³´µ¶·¸¹º»¼½¾¿ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏĞÑÒÓÔÕÖ×ØÙÚÛÜİŞßàáâãääæçèéêëìèîïğñòóôõö÷øùúûüışÿ  ü abcdefghijklmnopqrstuvwxyz¼8| œ ‡‚ƒ„…†‡ˆ‰Š‹Œ„†‚‘‘“”•–—˜”›œ›Ÿ ¡¢£¤¤ şåå?í}í1üWE ]GMGMI	]F_G !¿Q œ @                ! " # $ % & ' ( ) * + , - . / 0 1 2 3 4 5 6 7 8 9 : ;L|  u= > ? @ A B C D E F G H I J K L M N O P Q R S T U V W X Y Z [ \ ] ^ _ ` a b c d e f g h i j k l m n o p q r s t u v w x y z { | } ~  Ç ü é â ä à å ç ê ë è ï î ì Ä Å É æ Æ ô ö ò û ù ÿ Ö Ü ø £ Ø § ’á í ó ú ñ Ñ ª º ¿ #¬ ½ ¼ ¡ « ¤ ‘%’%“%%$%a%b%V%U%c%Q%W%]%\%[%%%4%,%% %<%^%_%Z%T%i%f%`%P%l%g%h%d%e%Y%X%R%S%k%j%%%ˆ%„%Œ%%€%±ß “À£Ãµ Ä¦˜©´"Æµ)"a"± e"d" #!#÷ H"° "· " ²  %   aü ü*ü ü(ıçW9É ÂM=ÀT=
Ç Ê Ë È Ï Î ÌMBåMCÆE@ÔT>Ò Û Ù xöEFØ]?ø\?‘Á Í Ó ÚU?ñ Tı‘_?³ T?
£œ¤Æ¸É”_?¦• ü(< µhÂ(L °—X8 ERROR: No configuration file found
 .. \valid¼system¹!ino  ructure Out of memory: can't allocateØPr %s
 fat_sb_info)	vX /boot/Qlu‡ext.e û.cf—%sf  t my	h&k iPEbfs: search Ven	#darr!!'„  c	'p	d,{noty#t]e.¸ compress9½ nDubvol'Åw	"ngonly support sHT+device ”
 _BHRfS_M´ MSWIN4.0á1tfs1NTFS B  ut8_* E{ whi8rCdZ f	mHche.
t<attributĞ?Qp*se_m_n()›MFTIc	d'L1T UW!  ?! $INDEX_ALLOCATION istBYlD B(idX2@*hp5QsŒLIĞQQ
XÀEIex l/İVCrVt ic. A
“rty	l	‰k..L'o!dirQt|S(El	)t*P~Kpp€'¬`gNd o`, aÌªin¡_™d_Rtupw(Cou˜ZetBS$Vˆume)!+ R v¨ˆ='¥!¸c2_g_gup_descbMnk¼ >= ƒs_cHt - *u =ãd,,€ h°
0t	z m˜‘h:Rm's€a EXT2/3/4*°Pl½,õpl^f*ÄÔ'¾thDUight¬Bgriy+ ØW CHS: ¿,%04%s^|ctxllu (%u/ˆ _-EDD9« 
 (ëll)+-¶ H¤¡ 3!ı18N •p%1NPq¬                                                                                                                                                                                                                                                                                                                                                                                          GCC: (GNU) 5.3.0                ,             ğ@     *                           ƒ                        <            @            ø*@                            <    w       P@     Y      €@     b                      ,    à       ©@     â                      ,    Ú       ‹@     ‰                      ,    ,       @     x                      ,    T5       Œ#@                                :                           ”:                       ,    *;       Ÿ%@     `                      ,    $B       ÿ&@     Ê                       ,    ËF       É'@     ¾                       ,    öI       ‡(@                            <    0N       @            +@                                        ğ@     @     ../sysdeps/x86_64/start.S /glibc-tmp-4da84b6e011d91753dd26471d5e4a31b/glibc-2.23/csu GNU AS 2.26 €z       g     ,   \   ø       ¾  ¹  ú      int          x   	 +@     G    r    R   ƒ       ../sysdeps/x86_64/crti.S /glibc-tmp-4da84b6e011d91753dd26471d5e4a31b/glibc-2.23/csu GNU AS 2.26 €e   d   Ş  Ë  H  p           ç   ×  Ø4   ¹  int ø       ¾  ú        }  |4   b  }P     ~P   à  4   a  P     ‚4     ƒe   p  „e   –  …;     ¿  ‹e   Ò  ™e     e   ¶  ¬e   Œ  ¯e         X¹   ˜  bÄ   ¸  mù   ¤	  Ä;   ³  xm  …  zÖ    u  {   ´    N  .<    0l    x  5   ^  =£   '  >˜   6  @w   •  A‚      C;   $è  El   (J  J®   0¨  Nã   8,  Pî   @Ù  [H  HE  \H  X;  ]H  hM  j<  x 	  L  
Ï    R    O  74     we   Í  0x  É  Ø	ñõ  Ÿ  	ò;    '  	÷  x  	ø  z  	ù  Â  	ú   ª  	û  (  	ü  0§  	ı  8À  	ş  @÷  	   H0  	  Pˆ  	  XD  	-  `4  	3  h…  	;   pB  	;   tí  	®   xÌ  	I   €¼  	W   ‚X  	9  ƒ  	I  ˆñ  	!¹   œ  	)á   ˜£  	*á    ª  	+á   ¨±  	,á   °¸  	.)   ¸W  	/;   ÀÈ  	1O  Ä ¾  	–=  	œ-  j  	-   Å  	3  %  	¢;    ü  x  	  I  
Ï     õ  	  _  
Ï    e  ö  ø  
W  —  `9  Æ  P    ¸  P   S  ;   ‹  	;   8  
;   j  L  r  ;    Ş  L  (×  L  0ò  P   8  L  @  ;   HC  ;   L!  ;   PË  L  X   P   \  ”     õ   $  P   ‹     Ñ  Ş    Û   die 1P@     (       œñ  msg 1L      n@     ~  İ  T	(+@     RóU x@     Š  U1  Ñ  7x@     :       œp  msg 7L  L   @     –  ˆ@     ¡  ¨@     ~  \  T	$+@     Rs  ²@     Š  U1  	  @2  ²@     q       œJ  fd @;   ‚   buf @á   Î   	  @)     ò  @  =  s  B  s  rv C2  ©  ¢  D2  ß  Ş@     ­  "  U~ T| Qs R}  õ@     –  @     ¡  	@     ‹     y;   #@            œÕ  pp yb  )  buf yá   b  y  y)   ›  ´  zm  Ô  ò  |  6@     p  UóUTóTQóQ  ”  [2  8@     q       œ¯  fd [;     buf [_  Y  	  [)   ’  ò  [  È  s  ]L  ş  rv ^2  4  ¢  _2  j  d@     ½  ‡  U~ T| Qs R}  {@     –  ‡@     ¡  @     ‹   ½  €;   €@     b      œ¬  4  €;   ´  á  €¬  í    ‚²  	@ä`     ˜  ƒ;   :  st „{  ‘°¶î  …;   ©  ù  †L  ò  /  ‡  ‘¨¶ä  ˆ;   N  mtc ‰Ã  q  mtp ‰Ã  à  fs ŠÎ  <  s ‹m  …  Ò  ‹Ô  »  Æ  ŒÔ  ,  b  =  b  r  ;   …  ×  L  	  b  ;   /	  d  ;   R	  i ‘;   u	  @   
  »@     ‹  Ú@     Í  F
  T1Qv R|  ö@     Í  j
  T1Q
 R|  @     Ù  U|    ô@     X      "  !8  Ú  ‘À·!ƒ  ë  ‘ÀW"cp    ¾	  "ep    ê
  "sd !L    #  ";   3   ÿ@     M       Q  $@     ~  &  T	-@      B@     å  U‘ÀWT	g-@     Q‘À·  @     ñ  x  U‘À·T	Ê,@      ­@        —  T	Ï,@      É@     å  Å  U‘ÀWT	Ü,@     Q‘À· Ö@       Ş  U‘ÀW ò@     å    U‘ÀWT	ü,@     Q‘À· ÿ@       U‘ÀW   V@     %       S  {@     ~  T	{-@       @       ½@     #  ˆ  U‘œ¶”Tw Q0 Ó@     .  ¥  U@T0 @     9  Ä  U	L+@      #@     H  ã  U	“+@      E@     T  ú  T2 c@     c    Us T‘°¶ Ÿ@     ~  9  T	š+@      ©@     Š  P  U1 À@     p  |  Us T	@ä`     Q
  Ì@     r     U	@ä`     T0 ì@     }  Í  U‘¨¶T	×+@     Qv  @     ñ  @     ‰  @     ™    T	ò+@      >@     ~  1  Uv T	ô+@     Rs  F@     ¥  I  Uv  Y@     ±  a  Uv  q@     ¼  …  U	T,@     Q1 @     È  @     Ô  š@       ¾  U	],@      ©@     ß  ê  U	‰,@     T	ò+@      )@     ë    Uv ÿÿÿÿT8 9@     ÷  8  U	#@     Ts  $ & M@       i  U} T| Q	±-@     R|  W@         U}  s@       ™  U}  ‰@     #  ª@     .  Ê  U~ T Y|  â@     Õ  ğ  Us T}€|Q
  V@       …@     9  œ@     p  6  Us T	@ä`     Q
  «@     E  Z  U	@ä`     T3 Â@     Õ  †  Us T	@ä`     Q
  É@     P    Us  Î@     \     	B   Ã  $Ï   ÿ m  %  É  m  	  ë  $Ï   ÿ 	  ü  $Ï   ÿ &  ª3  	B     $Ï   ÿ &ë    	B   .  ' &  #  &Ø  D  P   (opt (x  )B  .  	@æ`     )R  /'  	Hæ`     *{  {  d*Ö  Ö  +9  9  2*œ  œ  ˜,$  
  ‡$  ,  •  Š  *r  r  Ë*]  ]  n*    l-q  g   q  +q  q  }*(  (  Ì*‡  ‡  w+*  *  %+ğ  ğ  $-°  ¦   °  *_  _  4-Q  ³  ¶Q  -m  M  Ûm  +¥  ¥  .*      •,X  æ  nX  *Ë  Ë  2*£  £  >+J  J  í*;  ;  H*X  X  N+/  /  *
  
  h*    Ô+¬  ¬  
1+~  ~  
R+J  J  
:+    
A+¸  ¸  
4+è  è  2*f  f  =+    +*¿  ¿  d*@  @  Ï ö	   Ú  Ş  Ü	  H  ©@     â      å  ¹  ø       ¾  ú      int       {   n   §  04   
  1;   £	  3B   O  7-     ö  W   ´  n   ×   	e    İ   
Ôà<  ¡  á€    [  â€   g  ã€   w  ä–   é  å<  ˆ  æÇ   â  çL   n   L  	e   
 €   ]  e   ¹ Ôé  Ÿ  ê–    s	  ë‹   Ñ	  ì‹   È	  í–    	  î‹   ´	  ï‹   -
  ğ  ¡  ñ€   [  ò€   g  ó€   w  ô–   é  õ<  #ˆ  öÇ   .â  ÷  6 €     	e    €   0  e    ÔßP  '  èŞ   ×	  ø]   f
   Ï3  e  Ğ3   @  ÑÇ   1	  Ò‹   ·  Ó€   Ò  Ô‹   Š	  Õ€   |	  Ö‹   	  ×‹   ¤
  Ø€   [  Ù‹   ¬
  Ú‹   ¯  Û‹   f	  Ü–   #	  İ–    0  $¬	  û–   øÅ  ü‹   üZ	  ı‹   ş €   C  	e    J   ´  e  3   @  Ç   1	  ‹   ·  €   Ò  ‹   ’
  3  ?
  ‹   ¤
  	€   J
  
‹   º
  ‹   ß  ‹   ê  –   U
  –    õ  –   $á  ¡   (  ¡   0l  ¡   8?	  €   @Å
  3  A
  €   D	  3  E
  ¡   HÖ  –   Pâ  ´  T¬	  –   øÅ  ‹   üZ	  ‹   ş €   Å  e   £ $  B   ô     Ñ  Ş    Û   	  (€     p (     €   S	  -‹   3  p -3   9  ‹   
  8–   X  p 8X   ^  –      ©@     T       œú  bs  l   Ë  7
   W   k  ±@            Í    #ú  Í  sbs $     Ö@     '         *    sbs +    P    P  C    C  !ğ  .W   9  "sb .   ‹  ƒu   j  bs ƒ×   #7
  ƒº   $  …   
  3u   õ  bs 3×   #7
  3º   $v
  5W   $  6   $Æ  7¬   $5  7¬   $,  7¬   $ö  8¬   $‘	  9W   $  9W   %$`
  iõ    n     	e   ( &¥  ’u   ı@           œØ	  bs ’×   g  7
  ’º   Û  $¾	  ”€   v
  •W   M    –   á  $„  —u   '  N@     =       ¦œ  (-  U   'j  ‹@     š      ©	  („  x  (z  ®   ‹@     š      )  Ñ  )š  ®  )¥  ÷  )°    )»  à  )Æ  .  )Ñ  Y  )Ü  â  È@            G  *è  	`Q`      +K@     î	  q  ,U~ ,T	¢/@     ,Q8 +x@     î	  ›  ,U~ ,T	«/@     ,Q8 +¥@     î	  Å  ,U~ ,T	´/@     ,Q8 +Ä@     î	  ï  ,U~ ,T	½/@     ,Q8 -@     î	  ,UsÒ ,T	´/@     ,Q8   .9  %@     Z       §(S  ~  (I  ´   %@     Z       )^  ´  +;@     î	  …	  ,Us ,T	Æ/@     ,Q8 +Q@     î	  ¯	  ,Us ,T	/@     ,Q8 -g@     î	  ,Us ,T	™/@     ,Q8    4   ã	  / 0ñ	  Ø	  1	  	  A ¿   U  Ş  2  H  ‹@     ‰      	  ×  Ø8   ¹  ø       ¾  ú      int     ƒi   p  „i     •     É  Øñ  Ÿ  òb    '  ÷   x  ø   z  ù   Â  ú    ª  û   (  ü   0§  ı   8À  ş   @	÷      H	0     P	ˆ     X	D  Q  `	4  W  h	…  b   p	B  b   t	í  p   x	Ì  F   €	¼  T   ‚	X  ]  ƒ	  m  ˆ	ñ  !{   	œ  )   ˜	£  *    	ª  +   ¨	±  ,   °	¸  .-   ¸	W  /b   À	È  1s  Ä 
¾  –=  œQ  j  Q   Å  W  %  ¢b       œ   •   m  †       •   ƒ  †    ‰  •   §  0?   
  1F   £	  3M   O  78     ö  ´  •   ß  †    ÿ  1¯  Š  ¯W  ğ  °¤   )  ±¤  Á  ²™  M  ³™  
•  ´¤    µ¤  -  ¶™  Y  ·™   †  ºÜ  œ  »™     ¼™    ½™  ö  ¾™  Ğ
  ¿™  õ
  À™  
Ô  Á™    Ã™    Ä™  °  Å™   j  
É  lba Ê¯   len Ë™   Ôà_  ¡  á   [  â  g  ã  w  ä¤  é  å_  ˆ  æÏ  â  ço   •   o  †   
   €  †   ¹ Ôé2  Ÿ  ê¤   s	  ë™  Ñ	  ì™  È	  í¤   	  î™  ´	  ï™  -
  ğ2  ¡  ñ  [  ò  g  ó  w  ô¤  é  õ_  #ˆ  öÏ  .â  ÷B  6   B  †      S  †    Ôßs  '  è  ×	  ø€   f
   ÏV  e  ĞV   @  ÑÏ  1	  Ò™  ·  Ó  Ò  Ô™  Š	  Õ  |	  Ö™  	  ×™  ¤
  Ø  [  Ù™  ¬
  Ú™  ¯  Û™  f	  Ü¤  #	  İ¤   S  $¬	  û¤  øÅ  ü™  üZ	  ı™  ş   f  †    S	  -™  €  p -€   †  ™  
  8¤  ¥  p 8¥   «  ¤  ptr S   ×  img S   9  S×   ™  ç
  Sü  p S×  v S™   î
  m  p m  v m¯   ¯    _@  p _@  v _¤   ¤    !É  ex !É  
  !b   Ú
  "Ï  Î  "b     $¤  ƒ  %¤  Ï  &ß  lba &ß  len 'M   k  D  2¤    Ü  Õ  ß  è  cb   ‹@     ‰      œY   Ú
  cÏ  ÿ   r  cb   `   º  db   ¬   S  db   ø   ©  eƒ  D   à
  eƒ  ·  !æ  gY  *  epa h_  ex iÉ  "wp j@  †  !Î  kb   â  !z  l¤  @  "i mb   {  "dw mb   Ú  !
  mb     sbs ne  Ş  o  #°  Ğ@         y	  $Ë  o  %À   &!  ß@            |5	  $6  %  %-   #!  ê@     Ğ   }[	  $6  H  %-   &İ  ı@            ƒ…	  $ò  „  %é   &İ  @            ‰«	  %ò  %é   &İ  @     	       ˆÙ	  $ò  ª  $é  Ï   &!  #@            Š
  $6  ô  $-     &İ  -@            5
  $ò  >  $é  b   &°  4@            “_
  $Ë  ‡  %À   #F  m@          $r  é  $g    $\  j  $R  •  '   (}  à  (ˆ  ,  (“  x  (  ›  (©  ø  )´  ê@     *0  D  (¼  U  &ü  Ò@            ;  $  ¢  $  Å   +İ  Õ@            <$ò  è  $é      &ü  @            Jr  $  0  $  S   +İ  @            K$ò  v  $é  ™     &°  @             È  $Ë  ¾  %À   &ü  &@            ¡ò  $    %   &ü  2@            ¢  $  .  %   ,;@     I       s  !c  ¦b   Q  -c@     §  _  .U	ø/@      /m@     ¶  .U1  ,Œ@     I       Ê  !c  °b   ‡  -´@     §  ¶  .U	)0@      /¾@     ¶  .U1  &!  Õ@            ¹ø  $6  ½  $-  á   &!  ú@            ¿&  $6    $-  )   -c@     §  E  .U	Ï/@      /m@     ¶  .U1  ê  W  s  0  ªW  ?     1 0ñ	  v  0  v  0Ø  ¢  M   2°  ¦  	 °  3Ö  Ö  
 ³   ã  Ş  P  H  @     x        ×  Ø8   ¹  ø       ¾  ú      int     ƒi   p  „i     •     É  Øñ  Ÿ  òb    '  ÷   x  ø   z  ù   Â  ú    ª  û   (  ü   0§  ı   8À  ş   @	÷      H	0     P	ˆ     X	D  Q  `	4  W  h	…  b   p	B  b   t	í  p   x	Ì  F   €	¼  T   ‚	X  ]  ƒ	  m  ˆ	ñ  !{   	œ  )   ˜	£  *    	ª  +   ¨	±  ,   °	¸  .-   ¸	W  /b   À	È  1s  Ä 
¾  –=  œQ  j  Q   Å  W  %  ¢b       œ   •   m  †       •   ƒ  †    ‰  •   b     ´  ö  é   hæ    jƒ   ˆ  mb   ğ  n  val ob    —  `§  Æ  M    ¸  M   S  b   ‹  	b   8  
b   j  ƒ  r  b    Ş  ƒ  (×  ƒ  0ò  M   8  ƒ  @  b   HC  b   L!  b   PË  ƒ  X B  M   Ğ     µ  Õ  Ê     M   ó  ”     õ   ğ  K@     "      œ€  rv Kb   N  X  KĞ  ö  E@     c  L  T	‘3@      ]@     c  x  T	J1@     Q	G1@      n@     o  —  U	I3@      Š@     c  ¶  T	T0@      ©@     c  Õ  T	á0@      Ì@     c    T	J1@     Q	G1@      İ@     o     U	I3@      ó@     o  	@     o  L  U	A4@      @     ~  d  Uv  (@     c  T	J1@       *  ‡6@     œ      œü  4  ‡b   U   á  ‡ü  ¡   X  ‡Ğ  í   o ‰b   9!  •  Âˆ!@     d@     Š  #  U| Tv Q	@6@     R	`6@     X0 ¯ @     •  ?  T0Q0 à @     •  [  T0Q0 !@     c  !@     ~  s!@     c  ”  T	Ë4@      ˜!@     •  °  T0Q0 "@     c  Ï  T	5@      ="@     c  î  T	B5@      I"@     ó      Ş  üb   Ò"@     º       œ§  rv şb   "  è"@        #@     «  U  U1 8#@     c  t  T	[5@      f#@     «  ‹  U2 †#@     c  T	‡5@         ªW  ®  9   Ã  Gb   õ  Pb   ?   ä  †   ÿ ë  Ó  B  	ƒ  opt  æ  	 Q`     ©    †    {  24  	`6@       •   I  †       I^  	@6@     9   {  {  d!°  ¦   °   Ö  Ö  
"    ­"ü  ü  
»"/  /  "k  k  
 ¨   Ñ	  Ş  !  H  Œ#@           á  ×  Ø8   ¹  ø       ¾  ú      int         ´  ’   ö  §  0?   £	  3M   
  8¥   Ê   p 8Ê    Ğ   	¥   :  ˆb     p ˆ  
i Šb   z  ‹¥    	  	?     _-  p _-  v _¥    ¥   |  )Œ#@     ?       œ  i  )  d"  i +b   °"  z  ,¥   ş"    #@            /©  #  9#    a#     ³#@            5×  #  „#    §#     ¶#@     
       6#  Ì#    ô#    ?   k  ;b   Ë#@           œø  tag ;b   $  M  ;-   ¸$  o  ;Œ   V%  p =ø  ô%  I  >-   &  u  ?ş  ‘Ğ{ $@     =       Â  N  Pš   ı&  p  Q-   m'  M$@     •   é#@        x$@        É$@     3  U	`æ`       š   š     p   ÿ /  ä$@            œQ  i    î'  ÿ$@     3  UóU  S  œb   ÿ$@             œo  i  œ  :(  Õ   ÿ$@     `  í  å   ¯(   `  !î   !÷   "%@            #å   "%@            $î   Ò(  $÷   )      Õ   G%@       ¡Y  å   /)     !î   !÷   "j%@            #å   "j%@            $î   h)  $÷   ¢)      ›%@       UóU  ?   €  p   ÿ %ë  #o  	`æ`     &    .&9  9  2     Ñ  Ş    H  ;
  5   .   .   ÿ   ø   ñ	     	 R`     ˆ  Dm   	ä8@     ¾  f   ½  F   	à8@     int ‡    ’    !  Ş  Õ  H  z
  5   .   .   ÿ   ø        	 T`     Ø  n   	ì8@     ¾  g   ó     	è8@     int ‰    ö   ‚  Ş  +  H  Ÿ%@     `      ¸
  ×  Ø8   ¹  int ø       ¾  ú              ¤	  Ä?   ´  y   ©   p    ö  §  0F   
  1M   £	  3T   O  78     wi   ø  Ñ   H  °   Ù    °     p    $  #  °   3  p    Ú*‘  	Ÿ  +ò    	Y  ,ò   	e  -ò   	u  .  	ç  /‘  	†  0™   	à  2¡   y   ¡  p   
 ò   ²  
p   ¿ Ú6d  	(  7   	  8ı   	•  9ı   	Á  :  	<  ;ı   	m  <ı   	`  =d  	Ÿ  @ò   	Y  Aò   	e  Bò   	u  C  	ç  D‘  #	†  E™   .	à  Gt  6 y   t  p    ò   …  
p   £ Ú(¥  »  33  4  H²    
   r  	e  r   	@  ™   	1	  ı   	·  ò   	Ò  ı   	Š	  ò   	|	   ı   		  !ı   	¤
  "ò   	[  #ı   	¬
  $ı   	¯  %ı   	f	  &  	#	  '   u I…  $Z	  Kı   ş ò   ‚  p    ­  ²  n ç    	k  ²  	o  ¸   ‚  y   É  
p   ÿ …  T   ì  ÿ     :     P%‰  	  &§   	@  'Ü   	…  )É  	²  *T   	N  +?   	{  ,‡   	¦  -‡    fat /ç   (	   0ç   0	o  1ç   8end 2ç   @	Æ  4²  H ?   §  Ü   w   -   ç    ‰     F   È  _p  È   ò   G  .M   é  _p .é   ı     8T   
  _p 8
     ¬  f  Ÿ%@     N      œf    §  Å)  @  Ü   *  fs f  ]*  bs l  §*  i ?   ğ*  Æ  Æ   '+  Ñ  Æ   J+  Î  Æ   m+    Æ   à+  õ   Æ   ,  €  kŞ&@     ï  !&@            <÷  ÿ  ¤,   ï  ;&@            C  ÿ  É,   ³%@     Ë  4   UP Ú%@     ×  Q   Us  T0 !æ&@     â   Us   ì  ¥  "¸  qí&@            œË  #fs qf  î,  ö&@     î  µ   Us  $ÿ&@     â   UóU  %
  
  	Ò&”  ”  L%[  [  	ã&N  N  G £     Ş  Ü  H  ÿ&@     Ê         ×  Ø8   ¹        int       ö  ú      ¤	  &M   §  0”   ø   
  1F   £	  3±   ¾  O  78     w[   ø  ¸     0 
  ´  !Î    ò  "M     #
   ”     ?    H  ‰   Ù  0  ‰   @  ?    $  K  ‰   [  ?    )   Sà    Tà   Â  U  Ì  V     W  ¼  X@  Ö  Y%     Z%  Ï  [@    \%  M  ]@     ğ  ?   
 	­     
n Î    k     o  &   ğ  T   7  ?   ÿ …  ±   Z  ÿ     :     P%÷    &   @  'Ã   …  )7  ²  *±   N  +M   {  ,~   ¦  -~    
fat /Î   (   0Î   0o  1Î   8
end 2Î   @Æ  4   H M     Ã     -   Î    ÷    8±   8  _p 88   @  G  .F   Y  _p .Y   %  ~  ~   ÿ&@     Ê       œa  fs a  M-  ò  ~   ™-    g  Ò-    n  .  dep t  j.  û  M    .  s Î   ë.  '@     z    U} TóT >'@     …  #  U} Tv  Y'@       F  Us T~ Q; ³'@     ›  U} Tv   Z  m  Ù   [  J  J  :”  ”  L	  	  A    A '     Ş  ;  H  É'@     ¾         ×  Ø8   ¹  int ø       ¾  ú              ¤	  Ä?   ´  ö  O  78     wi   ø      ­  ñ   n ¶    k  ñ   o  ÷    	Á   
y     p   ÿ …  T   +  ÿ     :     P%È    &æ   @  '«   …  )  ²  *T   N  +?   {  ,‡   ¦  -‡    fat /¶   (   0¶   0o  1¶   8end 2¶   @Æ  4ñ   H ?   æ  «   w   -   ¶    	È  N  6É'@     %       œB  fs 6B  G/  ls 8ñ   €/  4  8ñ   É/  ç'@        	+  ”  w   î'@     ™       œ  fs B  0  n ¶   ^0  ls ñ   ª0  (@       «  U
 .(@     ì  Ã  U}  8(@       Ü  U
 Y(@     ı  Ts Q
 R|  h(@       Uv   [  [  ã
  
  Ò 6   z  Ş  t  H  ‡(@            ,    ×  Ø?   ¹  int   ö  ú      ¤	  &F   §  0   ø   
  1‘       £	  3£   ¾  O  7?     w-   ø  ª     Ù  İ   t   í   Ë    $  ø   t     Ë      ­  ?  n À    	k  ?  	o  E   
    V  Ë   ÿ …  £   y  ÿ     :     P%  	  &6   	@  'µ   	…  )V  	²  *£   	N  +F   	{  ,i   	¦  -i    fat /À   (	   0À   0	o  1À   8end 2À   @	Æ  4?  H F   4  µ   4  4   À    
  G  .‘   W  _p .W   
Ò     8£   x  _p 8x   
í   J  À   ‡(@     /       œ»  fs »  Uj  i   A1   
Á  y    -À   ¶(@     q      œ"  fs -"  Œ1  s .À   J2  j  0i   K3  W  0i   ”3  M  1˜   4  ‰  2À   Ğ4  m  3(  5  c  4˜   ë5  rs 5À   -6  <  Á)@            m‹  L   ]  é)@            z¬  m   L)@     .  Ä  Uv  x)@     .  Ü  Uv  ¼)@     .  ô  Uv  ä)@     .    Uv  *@     ~  UóU  
y  
t    ”  ”  L r    "  f  À  ../sysdeps/x86_64/crtn.S /glibc-tmp-4da84b6e011d91753dd26471d5e4a31b/glibc-2.23/csu GNU AS 2.26 € %   %  $ >  $ >  4 :;I?  & I    U%   %U   :;I  $ >  $ >      I  :;   :;I8  	I  
! I/  & I   :;I8   :;  &   I:;  (   .?:;'‡@—B   :;I  ‰‚1  Š‚ ‘B  ‰‚1  .?:;'‡@—B  ‰‚ 1  .?:;'I@—B   :;I  4 :;I  4 :;I  4 :;I  4 :;I  4 :;I  U     !4 :;I  "4 :;I  #4 :;I  $! I/  % <  &4 :;I?<  '!   (4 :;I?<  )4 :;I?  *. ?<n:;  +. ?<n:;  ,. ?<n:;n  -. ?<n:;n   %  $ >  $ >      I  & I   :;I  I  	! I/  
&   :;   :;I8  ! I/  :;   :;I  :;   I8   :;I8  :;   :;I8   :;I8  I:;  (   .:;'I    :;I  .?:;'@—B   :;I   :;I    4 :;I  4 :;I     !.:;'I   " :;I  # :;I  $4 :;I  %  &.?:;'I@—B  '1XY  ( 1  )4 1  *4 1  +‰‚1  ,Š‚ ‘B  -‰‚1  .1XY  /!   04 :;I?<  1. ?<n:;   %   :;I  $ >  $ >      I  :;   :;I8  	 :;I8  
 :;  I  ! I/  & I   :;I8  :;  ! I/  :;   :;I  :;   I8   :;I8  .:;'I    :;I  .:;'I    :;I  .:;'   4 :;I  4 :;I  
 :;    .?:;'I@—B    :;I  !4 :;I  "4 :;I  #1RUXY  $ 1  % 1  &1XY  'U  (4 1  )
 1  *U  +1XY  ,  -‰‚1  .Š‚ ‘B  /‰‚1  04 :;I?<  1!   2. ?<n:;n  3. ?<n:;   %   :;I  $ >  $ >      I  :;   :;I8  	 :;I8  
 :;  I  ! I/  & I   :;I8  I:;  (   .?:;'‡@—B   :;I   :;I  ‰‚1  Š‚ ‘B  ‰‚ 1  ‰‚1  .?:;'@—B  4 :;I  
 :;  .?:;'I@—B  4 :;I?<  ! I/  4 :;I?  4 :;I?   . ?<n:;  !. ?<n:;n  ". ?<n:;   %   :;I  $ >  $ >   I  &   .:;'I    :;I  	& I  
4 :;I  4 :;I  .:;'   .:;'@—B   :;I  4 :;I  4 :;I  1XY   1  1XY  .?:;'I@—B   :;I  4 :;I    ‰‚ 1  ‰‚1  Š‚ ‘B  I  ! I/  .?:;'@—B  ‰‚•B1  1RUXY   U  !4 1  "  # 1  $4 1  %4 :;I?  &. ?<n:;   %  I  ! I/  $ >  4 :;I?  & I  $ >   %  I  ! I/  $ >  4 :;I?  4 :;I?  & I  $ >   %   :;I  $ >  $ >     I  ! I/  :;  	 :;I8  
! I/  :;   :;I  :;   :;I8   :;I8   I  I:;  (   :;  'I   I  .:;'I    :;I  .?:;'I@—B   :;I  4 :;I  4 :;I  
 :;  1XY   1  ‰‚1   Š‚ ‘B  !‰‚1  ".?:;'@—B  # :;I  $‰‚•B1  %. ?<n:;  &. ?<n:;   %   :;I  $ >  $ >  :;   :;I8  I  ! I/  	:;  
 :;I8   I  ! I/  I:;  (   'I   I     .:;'I    :;I  .?:;'I@—B   :;I   :;I  4 :;I  4 :;I  ‰‚1  Š‚ ‘B  ‰‚1  &   . ?<n:;   %   :;I  $ >  $ >     :;   :;I8   :;I8  	 I  
I  ! I/  I:;  (   :;  'I   I  .?:;'@—B   :;I  4 :;I  4 :;I  ‰‚ 1  .?:;'I@—B  ‰‚1  Š‚ ‘B  ‰‚  ‰‚1  . ?<n:;   %  $ >   :;I  $ >  I  ! I/  :;   :;I8  	 :;I8  
 I  ! I/  I:;  (   :;  'I   I     .:;'I    :;I  .?:;'I@—B   :;I   :;I  & I   :;I  4 :;I  4 :;I  1XY   1  ‰‚1  Š‚ ‘B  ‰‚•B1   . ?<n:;    U%   X    0   û      ../sysdeps/x86_64  start.S     	ğ@     >.B#>M$ uvx[ #       û       init.c     `    /   û      ../sysdeps/x86_64  crti.S     	 @     ?Lu=/  	ø*@     Ï  ú   Š  û      /usr/lib64/gcc/x86_64-slackware-linux/5.3.0/include /usr/include/bits /usr/include/sys /usr/include ../libfat ../libinstaller  syslinux.c    stddef.h   types.h   types.h   time.h   stat.h   stdint.h   stdio.h   libio.h   libfat.h   syslxopt.h   syslxfs.h   setadv.h   syslinux.h   stdlib.h   errno.h   string.h   unistd.h   <built-in>    fcntl.h   stat.h     	P@     1K‘¢ =X'¥õ+ AYYugt[Ë===]"ºH"×^.õ+ AYYugt[Ë===]  	€@     €‚YIid ZŸ¼  Ÿ Ÿ	Xtt9?XtXJu-// ¹÷ K“¡kå;m u WZ„Y J?
Ö» sÀu¡¡å;=4 ™ Õ[e…‚ J|g^y<=u=Y-=çŸËdL Dx[ô “ Y,øşX ltuŸ¯Xt.Y/YuYƒYƒ;K/¤Y kXKg¡­Ë­Ê Ju±­¡¡ Ju˜¥içhu]     y   û      ../libinstaller /usr/include  fs.c   syslxint.h   stdint.h   syslxfs.h   syslinux.h   string.h     	©@      ;=3ŸI/ó]uÕ»ä f´gWiKujT º >òŸW!~¬VK1K¼?×_zXwÊ–…KWz	Xwf	<h=WiŸ‘uW®YuW®=Wh[KW¾fuXmLVg-
J+Y	‘L0V5+Y‚    ó   û      ../libinstaller /usr/lib64/gcc/x86_64-slackware-linux/5.3.0/include /usr/include/bits /usr/include  syslxmod.c   syslxint.h   stddef.h   types.h   libio.h   stdint.h   syslinux.h   stdio.h   <built-in>    stdlib.h     	‹@     å ¤ ”‘pfhJoJ'XY<t.b.tV.0ÈBJ.0tPJ*‚J.rÁ ‚Z“ñ Œta`,2[,>/æ=+f<fJM>rt<gÙ(Jf<Ê J´<Ì ‚xbPX1tOX4t/ÉI/K jƒÉI/K ®fÙ ‚- Y gÂJã Je=¬ Ê   ÿ   û      ../libinstaller /usr/lib64/gcc/x86_64-slackware-linux/5.3.0/include /usr/include/bits /usr/include  syslxopt.c   stddef.h   types.h   libio.h   getopt.h   syslxopt.h   stdio.h   setadv.h   syslxcom.h   stdlib.h   <built-in>      	@     Ë ;X/È—tW.
Ö ¬ t YYettÖw9[uô>-ŸA.;K×DX(ÖXKŸŸSŸ^u­İuÉ“¢ŸZŸZŸ[Ÿ]K‘2×[YZ­`×ZŸZŸZZ×Z“vå¾1K0ŸN„å0^?‘ µP&•»&L,_ V   ¿   û      ../libinstaller /usr/lib64/gcc/x86_64-slackware-linux/5.3.0/include /usr/include /usr/include/bits  setadv.c   syslxint.h   stddef.h   stdint.h   string.h   errno.h     	Œ#@     )9<N‚ Z ˆ+tUÈ°37ÍuX°ëHY@K’M[\i[=k<‚Y‘Xg\I=Lg;=I\¡! mJtõH>»‚pfp<&ƒn<tr¬«ƒŸhY> ;    5   û      ../libinstaller  bootsect_bin.c    :    4   û      ../libinstaller  ldlinux_bin.c    G   ×   û      ../libfat /usr/lib64/gcc/x86_64-slackware-linux/5.3.0/include /usr/include/sys /usr/include  open.c   ulint.h   stddef.h   types.h   stdint.h   libfat.h   fat.h   libfatint.h   stdlib.h     	Ÿ%@     {yXCÌ ‚µ.—Tƒ=LY“¾ sÀ?H?ICWVN:Lx.J¾FN#9M2g>d>0-ugƒuKƒu@h…g„Àƒ/[ =Y= û    À   û      ../libfat /usr/lib64/gcc/x86_64-slackware-linux/5.3.0/include /usr/include  searchdir.c   stddef.h   stdint.h   libfat.h   ulint.h   fat.h   libfatint.h   string.h     	ÿ&@     M[9?hg„­;=]=Y!KZiè“nJcòX &   Ä   û      ../libfat /usr/lib64/gcc/x86_64-slackware-linux/5.3.0/include /usr/include/sys /usr/include  cache.c   stddef.h   types.h   stdint.h   libfat.h   libfatint.h   stdlib.h     	É'@     6#K „ Y K €\V. JYYJ f c	wX	JY;=/ƒË-\ÊƒNILIM= 6   ª   û      ../libfat /usr/lib64/gcc/x86_64-slackware-linux/5.3.0/include /usr/include  fatchain.c   ulint.h   stddef.h   stdint.h   libfat.h   libfatint.h     	‡(@     K>KZI X[ó	 ‘ÛrÖfo<.:>×’’“Ù’å’?>ako]Y’&,>dj‡0×FX<fM‡>×CX?f>h@‚É J=eUN·‚É .³ Í J ]    /   û      ../sysdeps/x86_64  crtn.S     	@     'K  	+@     +K short unsigned int short int _IO_stdin_used /glibc-tmp-4da84b6e011d91753dd26471d5e4a31b/glibc-2.23/csu GNU C11 5.3.0 -mtune=generic -march=x86-64 -g -O3 -std=gnu11 -fgnu89-inline -fPIC -fmerge-all-constants -frounding-math -ftls-model=initial-exec unsigned char sizetype init.c __off_t pwrite64 _IO_read_ptr _chain st_ctim install_mbr uint64_t _shortbuf ldlinux_cluster update_only libfat_searchdir VFAT MODE_SYSLINUX done _IO_buf_base long long unsigned int fdopen secp errmsg BTRFS mtc_fd syslinux_adv libfat_sector_t __gid_t intptr_t long long int st_mode mtools_conf setenv program libfat_clustertosector __mode_t set_once bufp _IO_read_end _fileno __blkcnt_t dev_fd _flags __builtin_fputs __ssize_t _IO_buf_end _cur_column syslinux_ldlinux_len _old_offset tmpdir asprintf count syslinux_mode __pad0 pread64 st_blocks st_uid _IO_marker /tmp/syslinux-4.07/mtools ldlinux_sectors nsectors fprintf command stupid_mode sys_options ferror _IO_write_ptr libfat_close _sbuf bootsecfile device directory syslinux_patch _IO_save_base __nlink_t sectbuf _lock libfat_filesystem syslinux_reset_adv _flags2 st_size mypid perror getenv unlink fstat64 tv_nsec __dev_t tv_sec __syscall_slong_t _IO_write_end libfat_open heads _IO_lock_t _IO_FILE __blksize_t GNU C11 5.3.0 -mtune=generic -march=x86-64 -g -Os MODE_EXTLINUX stderr _pos parse_options target_file _markers __glibc_reserved st_nlink __builtin_strcpy st_ino syslinux_make_bootsect __pid_t menu_save st_blksize timespec _vtable_offset syslinux.c exit NTFS __ino_t st_rdev usage long double libfat_xpread syslinux_ldlinux activate_partition argc __errno_location fclose open64 mkstemp64 __uid_t _next __off64_t _IO_read_base _IO_save_end st_gid __pad1 __pad2 __pad3 __pad4 __pad5 __time_t _unused2 die_err st_atim argv mkstemp status MODE_SYSLINUX_DOSWIN popen calloc st_dev libfat_nextsector _IO_backup_base sync st_mtim fstat raid_mode pclose patch_sectors fwrite secsize slash getpid force xpwrite strerror syslinux_check_bootsect main _IO_write_base EXT2 bsUnused_6 bsTotalSectors ntfs_check_zero_fields clustersize bsMFTLogicalClustNr bs16 dsectors fatsectors bsOemName ntfs_boot_sector bsFATsecs bsJump bsMFTMirrLogicalClustNr retval check_ntfs_bootsect FATSz32 uint8_t bsHeads bsSecPerClust bsForwardPtr bsResSectors bsUnused_1 bsUnused_2 bsUnused_3 FSInfo bsUnused_5 memcmp bsSectors bsHugeSectors bsBytesPerSec bsClustPerMFTrecord get_16 bsSignature bsHiddenSecs ExtFlags bsRootDirEnts bsFATs rootdirents get_8 uint32_t bsMagic BkBootSec media_sig RootClus FSVer bs32 ../libinstaller/fs.c syslinux_bootsect uint16_t bsVolSerialNr check_fat_bootsect Reserved0 fs_type bsZeroed_1 bsZeroed_2 bsZeroed_3 fserr fat_boot_sector sectorsize bsClustPerIdxBuf bsZeroed_0 get_32 bsMedia bsSecPerTrack bsUnused_0 bsUnused_4 subvollen sectp subvol set_16 set_64 secptroffset checksum sect1ptr0 sect1ptr1 diroffset instance ../libinstaller/syslxmod.c adv_sectors epaoffset sublen syslinux_extent csum xbytes ext_patch_area dwords advptroffset subdir raidpatch stupid data_sectors nsect secptrcnt advptrs patcharea magic subvoloffset dirlen nptrs addr set_32 generate_extents maxtransfer offset_p long_only_opt ../libinstaller/syslxopt.c syslinux_setadv long_options has_arg name opt_offset short_options optarg OPT_RESET_ADV optind OPT_DEVICE OPT_ONCE modify_adv option flag optopt strtoul OPT_NONE getopt_long memmove ../libinstaller/setadv.c adv_consistent left ptag syslinux_validate_adv advbuf plen advtmp cleanup_adv syslinux_bootsect_len ../libinstaller/bootsect_bin.c syslinux_bootsect_mtime ../libinstaller/ldlinux_bin.c syslinux_ldlinux_mtime malloc read8 bpb_extflags le32_t ../libfat/open.c bpb_fsinfo read16 clustshift bsReserved1 bsBootSignature bsVolumeID barf fat_type read32 bpb_fsver bsDriveNumber libfat_sector fat16 bpb_rootclus minfatsize le16_t bsCode bsVolumeLabel nclusters FAT12 FAT16 readfunc rootdirsize rootdir bpb_fatsz32 fat32 FAT28 readptr le8_t libfat_flush free bpb_reserved bpb_bkbootsec endcluster bsFileSysType libfat_get_sector rootcluster clustsize ctime attribute caseflags atime ../libfat/searchdir.c dirclust nent clusthi clustlo libfat_direntry ctime_ms fat_dirent lsnext ../libfat/cache.c fatoffset nextcluster clustmask fsdata ../libfat/fatchain.c fatsect P@     [@      U[@     m@      Rm@     x@      óUŸ                x@     €@      U€@     ²@      S                ²@     È@      UÈ@     "@      ^"@     #@      óUŸ                ²@     È@      TÈ@     #@      óTŸ                ²@     È@      QÈ@     @      S                ²@     È@      RÈ@      @      ]                Á@     È@      TÈ@     @      \                Ş@     ô@      P	@     @      P                Á@     È@      0ŸÈ@     @      V@     #@      P                #@     5@      U5@     8@      óUŸ                #@     5@      T5@     8@      óTŸ                #@     5@      Q5@     8@      óQŸ                #@     '@      R'@     8@      óRŸ                8@     N@      UN@     ¨@      ^¨@     ©@      óUŸ                8@     N@      TN@     ©@      óTŸ                8@     N@      QN@     @      S                8@     N@      RN@     ¦@      ]                G@     N@      TN@     ¤@      \                d@     z@      P@     @      P                G@     N@      0ŸN@     ¢@      V¢@     ©@      P                €@     @      U@     â@      ‘œ¶                €@     @      T@     Õ@      w Õ@     â@      ‘¶                I@     K@      PK@     W@      SW@     b@      Pb@     Ÿ@      S©@     Ø@      S                @     @      Pÿ@     @      PV@     ]@      P                0@     5@      P5@     Ÿ@      V©@     ı@      V@     @      V                @     @      P                @     9@      P9@     =@      U=@     J@      VQ@     ±@      V»@     Õ@      V                ¯@     ±@      P±@     ¶@      \»@     Ù@      PÙ@     @      \                >@     L@      PL@     „@      ]„@     ˆ@      U                W@     r@      Ps@     ˆ@      P                M@     W@      ^]@     d@      | 3$~ "Ÿd@     v@      |3$~ "Ÿv@     ~@      | 3$~ "Ÿ                4@     8@      P8@     ß@      ^                M@     V@      P                M@     W@      0Ÿ]@     n@      \n@     v@      |Ÿv@     x@      Ÿx@     ~@      \~@     á@      _                Ì@     ß@      P                "@     °@      V                ³@     ë@      V                ª@     ³@      P³@     Ï@      \ä@     Û@      \                ô@     ü@      ‘À·Ÿü@     @      U@     @      ‘À·Ÿ@     @      ‘Ä·Ÿ@     U@      UU@     {@      Q{@     ƒ@      uŸƒ@     Š@      UŠ@     @      uŸ@     ‘@      U‘@     ”@      Q”@     @      U@     £@      uŸ£@     ¬@      U                ô@     L@      ‘°WŸ                @     L@      V                ô@     "@      1Ÿ"@     :@      P>@     E@      PJ@     …@      0Ÿ…@     ‘@      P‘@     ”@      0Ÿ”@     ¬@      P                                U       %        uuŸ%       (        p¦Ÿ(       8        P8       Q        UQ       S        p¬ŸS       T        óUŸ                                T       (        óTŸ(       =        T=       T        óTŸ                               U       %        uuŸ%       (        p¦Ÿ                -       8        P8       Q        UQ       S        p¬Ÿ                T       ´        U´       €       S€             U      Ö       s}ŸÖ      â       óUŸ                T              T      |       \|      Š       TŠ      Ö       \Ö      â       óTŸ                t       œ        Pœ       ¥        qŸ¥       ë        Pë       ¡      	 s”
ÿÿŸ4      f      	 s”
ÿÿŸ|      ‘       P                T       ´        U´       €       S€             U      Ö       s}ŸÖ      â       óUŸ                ¯       Ş        S                Ş              T      |       \                Ş       |       S                Ş       |       
 Ÿ                             P                             R      $       Q$      -       x q Ÿ-      4       QF      K       RK      N       0ŸN      R       x r ŸR      ¡       R4      f       R                      =       P=      @       p q Ÿ@      e       P                F      e      	 p u ÿŸ                0      4      	 s”
ÿÿŸ4      7       Q7      :       qqŸ:      ¡      	 s”
ÿÿŸ4      f      	 s”
ÿÿŸ                ë              P             rŸ             u ÿŸ      ¡       s”ÿŸ4      X       u ÿŸX      f       s”ÿŸ                |      Š       TŠ      Ö       \                |      €       S€             U      Ö       s}Ÿ                        p        Up       y       Vy      …       óU#Ÿ…      ‰       U                        X        TX       …       óTŸ…      ‰       T                        ­        Q­       …       óQŸ…      ‰       Q                        v        Rv       …       óRŸ…      ‰       R                        ×        X×       â        ‘¨â       ï        Xï       ½       ‘¨…      ‰       X                        ×        Y×       â        ‘°â       ò        Yò              ‘°…      ‰       Y                3       ×        [â       ×       [â      (       [3      …       [                $       ×        [â       ×       [â      (       [3      R       [                       ×        Zâ              Z             zŸ…      ‰       Z                R      Y       ş²>ŸY      …       Q                R      Y       0ŸY      f       Pf      i       pŸk      o       P                       “        P“       …       ‘¸                Â       ×        p 
ÿÿŸâ       ë        p 
ÿÿŸë             	 s”
ÿÿŸ                3       T        {ŸT       _        sŸ_       r        sŸr               sŸ»       ~       s
Ÿ~      â       Sâ      ù       sŸ3      J       sŸ                T       _        \                _       g        |  %Ÿg       p        u                r               
ÍŸ                       ˜        z~Ÿ                       ˜        {Ÿ                ˜                ‘¸                ˜                {Ÿ                ¢       ©        1Ÿ                ¢       ©        {Ÿ                »       ~       s
Ÿ~      â       Sâ      ù       sŸ3      J       sŸ                ï       ~       X                ï              V             Y      l       yŸl      ~       Y                ï             	 s”
ÿÿŸ                ï       N       QN      R       q
ŸR      ~       Q                ï              
 €Ÿ      Î       Tâ      î       T                ï              
 €Ÿ      U       \\      ~       \                      _       ]                ï              0Ÿ      _       R_      s       ]s      ~       R                ï              0Ÿ      _       P_      s       Us      ~       P                             ^      R       ‘¼\      _       ‘¼                G      J       R                G      J       Q                J      N       P                J      N       qŸ                w      z       R                w      z       Q                z      ~       P                z      ~       qŸ                ~      â       Sâ      ù       sŸ3      J       sŸ                ›      ¢       Q                §      ®       Q                Ã      ×       Râ      ù       R                      (       R3      J       R                J      R       0Ÿ                J      R       {Ÿ                k      s       Q                k      s       {Ÿ                        %        U%       \        V\       j        Uj       {        V{       ‰        U‰       œ        Vœ       §        U§       "       V                        *        T*       â        Sâ       ü        óTŸü       "       S                "      8       U8      ½       \½      ¾       óUŸ                "      8       T8      »       V»      ¾       óTŸ                "      8       Q8      º       Sº      ¾       óQŸ                P      €       P’      ä       Pğ      š       P¼      Ë       P      Z       Pa      h       P      ¦       P²      Ü       Pè      ı       P5      ?       P                ¾      $       0Ÿ$      m       Sr      v       Sv      x       P                        <        U<       >        T>       ?        óUŸ                	               8Ÿ               pŸ               pŸ                	               g£       ?        Q                        	        ¥/-ZŸ                        	        U                        *        Q                        *        uŸ                *       4        d¿(İ                *       4        uüŸ                ?       \        U\       h        óUŸh       „        U„       ç        ^ç       ÷        óUŸ÷       H       ^H      X       óUŸ                ?       \        T\       h        óTŸh       |        T|       ò        Vò       ÷        óTŸ÷       H       VH      X       óTŸ                ?       \        Q\       h        óQŸh       ”        Q”       ç        ]ç       ÷        óQŸ÷       H       ]H      X       óQŸ                ‡       ”        W”       À        XÄ       Æ        PÆ       ç        X÷       û        xŸû              P      <       XA      H       X                ‡       ”        
ôŸ”       ç        S÷              S      H       S                ˜       ¶        Q¶       À        x Æ       ç        Q÷       <       QA      H       Q                ¡       À        PÆ       â        Pâ       ç       
 x”ÿ#Ÿ÷             
 x”ÿ#ŸA      H       P                X      i       Ui      r       Qr      s       óUŸ                s      ¹       U¹             P             óUŸ             P             óUŸ                s      Ÿ       U                      ’       qŸ’      –       qŸ                      Ÿ       R                »      Ú       p€ŸÚ      ò       T                Ş      å       qŸå      é       qŸ                Ş      ò       R                                U       M       \M      N       óUŸ                                T       K       VK      N       óTŸ                                0Ÿ               P       J       S                ;       .       P3      :       P?      F       P                [       Ø        RØ       ?       s                ~       Ò        Q                š       ?       Y                ğ       ò        R             R             R              r 9%Ÿ       ?       R                ´       Í        p”
ÿÿ5$#ÿ9&Ÿ                Õ       å        Qå       î        q~Ÿî       ğ        r~Ÿğ       ò        s”2Ÿò              Q      ?       s”2Ÿ                ‚       …        p Ÿ                œ                p$Ÿ                N      V       UV      [       S[      _       U_      `       óUŸ                                U       Å        ]Å       Ê        óUŸ                                T       Ê        óTŸ                                Q       Ç        ^Ç       Ê        óQŸ                                R       Ã        \Ã       Ê        óRŸ                E       J        PJ       ¹        S                J       œ        _œ                `Ÿ        ¹        _                        ,        P,       4        V4       >        P>       Á        V                                U       %        óUŸ                               P       #        S#       %        P                               P       #        S#       %        P                %       L        UL       ½        ]½       ¾        óUŸ                %       T        TT       »        \»       ¾        óTŸ                )       7        P7       8        ppŸ8       T        P[       d        Pd       r        Vr       t        Pt       ¹        V                                T       $        T$       .        tŸ                /       Ä        UÄ       %       V%      4       U4      L       VL      \       U\      ƒ       Vƒ      ‹       U‹      ˜       óUŸ˜              U                /       B        TB       F        tŸF       T        PT       ¹        T¹       %       óTŸ%      )       T)      L       óTŸL      Q       TQ      —       óTŸ˜      š       Pš      ›       tŸ›              T                …              S%      '       SL      O       S                ì              } ÿŸ             P             T      %       TD      L       Tk      ‹       T                ¶       Ô        \Ô       à        Qà       ã        tŸã       ì        |Ÿì              \            
 s 1&s "#Ÿ'      @       SO      h       S                ¶       À        | 9%ÿÿÿÿu("ŸÀ       Ä        Tì       ğ        T'      0       s 9%ÿÿÿÿu("Ÿ0      4       TO      X       s 9%ÿÿÿÿu("ŸX      \       T                Å       ğ        Pñ              P5      L       P]      w       P                /       V        u”1Ÿ˜              u”1Ÿ                e       ‚        S‚       ‘        p  Ÿ                        ÿÿÿÿÿÿÿÿ         @     @     ø*@     ü*@                     ©@     ¬@     ¯@     @                     P@     ©@     €@     â@                     E       J       M       T                       _       g       i       p                       â       ë       ò       ~                            R      \      _                      s      y      |      Ÿ                      »      Ó      Ş      ò                      ÿÿÿÿÿÿÿÿ        @     $@     +@     +@                                                   8@                   T@                   x@                   È@                   è@                   ~	@                   Ø	@                   ø	@                  	 ¸
@                  
  @                   0@                   p@                   €@                   ø*@                    +@                   ğ8@                   à9@                   (N`                   8N`                   HN`                   PN`                   àO`                    P`                   @Q`                    ä`                                                                                                                                                                             !                     ñÿ                    ñÿ                     (N`             !     8N`             /     HN`             <      @             >     `@             Q     °@             g     (ä`            v     0ä`            „      @                 ñÿ                     0N`                  ø>@             «     HN`             ·     À*@             Í    ñÿ                Ø     @ä`            å    ñÿ                ê     `Q`     )       õ    ñÿ                    ñÿ                   ñÿ                    Œ#@     ?           ñÿ                '   ñÿ                3   ñÿ                ;   ñÿ                F   ñÿ                U   ñÿ                     ñÿ                c     (N`             t    PN`             }     (N`                  ğ8@             £     P`             ¹     *@            É                     İ    8@     q       å                     ÷                                          )                      ”     @Q`             E                     Y    ©@     T       p                     „    ÿ$@             š    Ò"@     º       ¥                     ¹                     Í    ¶(@     q      ß     ä`             æ    6@     œ      ô    `æ`                                     ÿ&@     Ê       &     ä`            Ã    ø*@             :                     S    î'@     ™       e                     y   °*@                í&@                ‡(@     /       ¥    è8@            ¼                     Ğ     R`            â                     õ     T`                @6@                                    @N`             !                     @                     T                     k    ä$@            ~                     ’    @Q`             Ÿ                     ·    ä`            Ë    ²@     q       Ë                     à                      ï   HQ`             ü     +@                @æ`                `6@     €           x@     :       (    ä`            <                     R    É'@     %       _    ì8@            t                     †    0*@     e       –                     ª    ä8@            o    `ê`             ˜    ğ@     *       À    Ÿ%@     N      Ì                     à     ä`             ì                         Ë#@               €@     b          @     "                           1                     F                     [                     n    P@     (       r                     †                      š    ‹@     ‰      ©                     ¾    Hæ`            Ä    #@            í                     Ò                     ä                     ø    ä`                                       à8@            6                     L    ı@              
  @             d     Q`     `       h     ä`             init.c crtstuff.c __CTOR_LIST__ __DTOR_LIST__ __JCR_LIST__ deregister_tm_clones __do_global_dtors_aux completed.6948 dtor_idx.6950 frame_dummy __CTOR_END__ __FRAME_END__ __JCR_END__ __do_global_ctors_aux syslinux.c sectbuf.4815 fs.c fserr.3249 syslxmod.c syslxopt.c setadv.c cleanup_adv open.c searchdir.c cache.c fatchain.c bootsect_bin.c ldlinux_bin.c __init_array_end _DYNAMIC __init_array_start __GNU_EH_FRAME_HDR _GLOBAL_OFFSET_TABLE_ __libc_csu_fini getenv@@GLIBC_2.2.5 xpwrite free@@GLIBC_2.2.5 __errno_location@@GLIBC_2.2.5 unlink@@GLIBC_2.2.5 _ITM_deregisterTMCloneTable strcpy@@GLIBC_2.2.5 syslinux_make_bootsect ferror@@GLIBC_2.2.5 syslinux_validate_adv modify_adv setenv@@GLIBC_2.2.5 getpid@@GLIBC_2.2.5 libfat_nextsector _edata parse_options syslinux_adv fclose@@GLIBC_2.2.5 libfat_searchdir optind@@GLIBC_2.2.5 getopt_long@@GLIBC_2.2.5 libfat_get_sector system@@GLIBC_2.2.5 fstat64 libfat_close libfat_clustertosector syslinux_ldlinux_mtime pclose@@GLIBC_2.2.5 syslinux_bootsect fputs@@GLIBC_2.2.5 syslinux_ldlinux short_options __DTOR_END__ __libc_start_main@@GLIBC_2.2.5 memcmp@@GLIBC_2.2.5 mkstemp64@@GLIBC_2.2.5 syslinux_reset_adv calloc@@GLIBC_2.2.5 __data_start __fxstat64@@GLIBC_2.2.5 optarg@@GLIBC_2.2.5 fprintf@@GLIBC_2.2.5 __gmon_start__ __dso_handle _IO_stdin_used program long_options die_err optopt@@GLIBC_2.2.5 pwrite64@@GLIBC_2.2.5 libfat_flush syslinux_ldlinux_len sync@@GLIBC_2.2.5 __libc_csu_init malloc@@GLIBC_2.2.5 syslinux_bootsect_len libfat_open fdopen@@GLIBC_2.2.5 __bss_start asprintf@@GLIBC_2.2.5 syslinux_setadv main usage open64@@GLIBC_2.2.5 memmove@@GLIBC_2.2.5 pread64@@GLIBC_2.2.5 popen@@GLIBC_2.2.5 die perror@@GLIBC_2.2.5 _Jv_RegisterClasses syslinux_patch strtoul@@GLIBC_2.2.5 mypid libfat_xpread exit@@GLIBC_2.2.5 fwrite@@GLIBC_2.2.5 __TMC_END__ _ITM_registerTMCloneTable syslinux_bootsect_mtime strerror@@GLIBC_2.2.5 syslinux_check_bootsect opt stderr@@GLIBC_2.2.5  .symtab .strtab .shstrtab .interp .note.ABI-tag .hash .dynsym .dynstr .gnu.version .gnu.version_r .rela.dyn .rela.plt .init .plt.got .text .fini .rodata .eh_frame_hdr .eh_frame .ctors .dtors .jcr .dynamic .got.plt .data .bss .comment .debug_aranges .debug_info .debug_abbrev .debug_line .debug_str .debug_loc .debug_ranges                                                                              8@     8                                    #             T@     T                                     1             x@     x      L                           7             È@     È                                 ?             è@     è      –                             G   ÿÿÿo       ~	@     ~	      X                            T   şÿÿo       Ø	@     Ø	                                   c             ø	@     ø	      À                            m      B       ¸
@     ¸
      H                          w              @            $                              r             0@     0      @                            }             p@     p                                    †             €@     €      w                             Œ             ø*@     ø*                                    ’              +@      +      Ğ                              š             ğ8@     ğ8      ì                              ¨             à9@     à9                                   ²             (N`     (N                                    ¹             8N`     8N                                    À             HN`     HN                                    Å             PN`     PN                                              àO`     àO                                    Î              P`      P      0                            ×             @Q`     @Q      À’                              İ              ä`      ä      `                              â      0                ä                                   ë                       ä      Ğ                             ú                      ğæ      ¦N                                                  –5     4                                                  ÊH     Ç                                   0               ‘X     ‘                            +                     "i     f6                             6                     Ÿ                                                         <¸     D                                                   ¡     0      $   F                 	                      À°     |                                                                                                                                                                                                                                                                                                                                                             ./.wifislax_bootloader_installer/lilo32.com                                                         0000644 0000000 0000000 00000267440 11651254716 017735  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   ELF              wÁ 4           4    (             À  À ün ün          D  DèDè              aœƒæUPX!Ú    ˆö ˆö Ô   y      ?dùELF   ğ€ÿ·Øİ4ô   (   {ş¹d-#¬j Ÿ·ÇÚ doÿ„`?Øò  àèQåtd  ÀÌò R?ì_îœœ[€e? €É (      @ÿØi Í* I ûşÿU‰åSè  <Ã 
ŸÇ,[]ÃÚÿÿÿ1í^‰áƒäğPTRh$HhÔ€QVh9†ÿÿûï#”œô‹$ÃCƒì€=€ƒ uJ¸p»ÿw·ÿ,-lÁøXÿëB‰„ÿû»Ç¾•‹9Úrm6 …Àt>şû¿}h¨êè˜~û÷ƒÄÆK‹]üÉmûßö^™ªZÂr~¥¸
“3÷¿ 6Rj hˆ(;\ß;ìîƒ=td t&]ÿÛıï¹ĞP¯‰Ãj/PÇo(÷İo&ªPSh@éÿ50âãmaİíLì¥qúƒ1<9’³ÈIì {BI]-L g S.»éò y„,J_J!È–Ò!9ü'KvaÂîj	 ·Œnß¸ğ¿ÒG·Á-XŞ¼à³\~ ™@t<PÿeÿÆ¡ƒèP÷Ğ‰ÂÁê>·ıÿ†à†òYY·ÒÁà	ÂIOwq¼€læ>W\`\$y\`W²9€`,d,r‘ä`,d,_Èæ dPhPdÈErPhPg ›pztzpz ÉAtzoy€lhvlvhv€\$lvwä²9lxpxlxr‘pxûÏğˆJüÇ$œLİ6½Ó¤“jh³>Ùî‡j$jÉLHhÿööa·BhñZYj3jOvk7=jM/,h ]Ë—j6œpı›nàL$GÿqüWVSQì4ı´Ü¾'‹1‹YàÄ€£>Ç$ö*7×w9	Œ½	k;É,âÿ ìjo¿‹‰…øíhT½ÉlØo÷
ÿ†Hë	‘œı†÷L“ MşN‰µîûç¯B$Ø‰Ç…ôUk’I&Ù	ğÜì¹dà1öî ›d’É	è=¾uA&ü—éw¤‹•øîwÿŠJ‰•ŠAˆ…ä!¾ĞPPsw›[ß¡±Ø‰ÔÑ?26²nL‹‹tFQ×^»Á€y#tF,Sş66øë|{wSI­ƒ½³ÿ f‹?VadgûÙğKëMSSqµkÙlìleb>8ÆÚÈØ…m…F•İoÄ~1ÒŠÇÅA<9‡è>;³uÿ¶Àÿ$…p]_ğ$ÿ>{0'tûS¢©—øİg„N_‹Gg8-<ÙbgÿÚ?Xù5ÜJ´ŸWö	 >÷BÓá[Á'¢ÆÀ6Q7ÁMT?JüÌvëÕ¬ˆë$[ók~NÉM¹	–¯'HÙ+· % ƒVS²5»"›qŒJ$Ù~·=DëØ(Ì{´ùWÏ7ÛFëæ6ŸzOyè€9}öMÎìzjŠTëƒ‚Œ=œ;<TR’95#d;˜š@Hk—ğxj=Rö‰Û6Û>ŒhtÆ*@uËÜİP4	Ò.h×Ñ7l„Æt8šuqÛó†Le?QQhå-ìd»ÂŞhæ°-¿,-ö<R80íñ¤?‹P[€x½ÑæÓÖ	ûä?µü˜t>
­u¢H.œæÁƒÇF‰Sú#µÿëË…öuƒÉ3G1Àò®÷ÑíïèAQJœz‰Æë@ƒÃ/dÿv³n)‰÷%‰Ê÷Ò6Ë×è¿4WW
R7S_wÙÀöXh¼ÉkVkn,ÿµ&!¸	³µ÷Úïlİ…¨3¹ü¿“/ÈÿMùäi wKÃ›5Û#H`|í 'WlPÃˆurd‰æV¶g“d.n(AFûÿì`¿$u';t7Š€ù/~Ğ¶³·94ëKĞ,Ü44™CP›Ò£âdéöîíë¡	yAgš=@Z”ŠG†Á¡ÀGâŠNsnr!4åZß³Â¡+EPí‚œ¤IN9Wd²Ü	ŞÿŠ!%! 0Y|ù:Êğë> qÖ!ƒì(ğèØ­Ùc¸‚ë?ôò!4‚D{–ëK‰¯"İv¸FÅ,˜2‡¬éé *+œ0¦Ù_€: W‰F÷³† 10Jd£Tà_u»']½%8y#@ĞfÍ.vZÿ07tÄP$“ï	¥ÍøxPl°ÖÙ7ì6%U›Ÿy ™z(ñ“_Û!ø˜vXmØ•ÄX·¿‚ ÔJ‡Ø$•àph üG6­•ÀH~¢lÛs!GğíıVéÿ6 èĞŠB„ÛuW]DêräéûlËâh’NÓ"t‹Ç¥á§@üëÏh´tdØÀ+Rt"Ïzö†|3ĞL~WV8İ³PDPPqíİ1ş~2=½ úªÛşÈ†W<èu…$ûPÛÀ6s¢úIq:1j&''»
gˆ’{3á	‡
K¸ğÁİëP¡eó…Â&¡M{
œg\ş¾PKà¡&é-¬Ä™xYøøë1ÿHHÿ5ÂÙQµ+‡ÄÒÖ¥…ÿ?€+ÂX!ÙQó+ôÕÄ{/yRRåÌV·iàÎbá1Û€xLîBğß¼‰Ãz#<°0×²u4„÷)ö}µ£
,í³eå~õdÉ€¼uÔ\h³µ ÿV±@òtÜÈ:+·1„~Ö06áö­qâ×}ú €uB†9ìs8ÿP0òš’Öø¨tQ’nÃØÒ/öH$•£(:BÂÖVVQc¬á`ìw{$y9Ú<%µOò!ÎXB Õ‰sÓAò±¤a9ytt ÁM£…„•> ^_šÑ}°[.hN£ÆX½Í„-–S8‹Ç(}oĞˆøNĞUQG¶ ‡DnH¶¶ß&Ş¸hç¸^…Òÿ¸„­ğQ˜ˆ=é½$[¡8\	0éà]u´8ÕYÛL$2ëHîµwÓ”ğ5%q„eÃ¾“œcB;ÀÆˆXc0µ†£Ğğh¡E~–]#}âAPGş±ì›#O˜ÿMÆÊĞb­tpu“Xv;à"WØ“&³QÜY  WØ#ÇÈüG.x858ÜÂ¸ÉR5°äss¤üN¸'@1Z_áSÛ]ÈÒBµ¾ Ó…Æ²rEˆ+Y¶fšPN ÙÇc_PÂƒ0²ğ
éD>Muâ3F¶	8,ˆ~#×ÌP\ùßZ[BG?ˆRr°Â#ã”ğèN³§áÁa10š %t‡)¾¤=gk‹oöSbVx(œ] `7ğ¨5›¦«Ê+úS;\=ãÀút.XS×ÙQ:ôìC¦'Rjwl„_5:@Y2Ë¾Õ:@ E°g‡aø eXWØUæÊjíerÓÈ…ŒşÃ¥!SˆrµO	oÚ~)“Áïƒç‹Áîá‘ÚƒæD„u;út38½&üüÈOnS­Sá‰ËŠ3‰1ßûßZH†nŞU®µ ü¿>ØV¢§ˆ½útw·ÖïbŠ…<ë6 …!
ƒÀcİ¾ñë<éŸ¿Fë­Ö6ø0	4º˜)Â?•€ívñ8ëPRmìT›“Á±1úS1,üEä·¶DP&äY^ËTş““ (T·EÆiÀ•7·»ÒŸ¾ ™÷şL¿îC¶ß
 
ÿR99‹EÄwr„
…fì#`Tì[¶!HÀGBR;|ù5äz/döEÏ [É5a¡4¦Ë¦y¥q½VVÁ¢Û  Ã<ÚrÁûîTg	U÷fî%¸,'EPBHn­9e1U;d±¿" x0êP"°oölE u"«†"ì.®¿UÄ"äd3Ùä‹@ÛUéò„<ŠED„ÀKV·B¸-<K5Väì…%s}È (_HIìš8 ŸÅ†ûnÓÈu
°|*PV£ënKââŸP`µIÆòôtTÊ£(`Î-p"©/›KµCœòxşWÙ!¿eB!W\rX;u¢Më‰-—MôÇöMÃoGú€~ÓL™¼F¿Ì˜8eìCCÄ4¿e¹È·	ğ¹º+ºØ	'™—˜¸»É“õü_¢–WQRk6uYÃ)¶ \8 $¶sFÖâàwÛÿ`ti1Éƒú`uN~ŠVˆûÕl¯Šº(¨ }¶ÿı—:ÁáçÆ<9Áç1¸œı+ÏWR%!6ÃK.8Wë7"@º¯îaŸL,«ÔÕ_ğBì7&f‹Nf‰h1ù÷Çİ’Oc!nW,È!‹f>2öy¤‰øÍ=ÉÃxÎÄ¸çKŒ'Ÿpb'ÔWúWêÏx²…!Xé!X9ò;`!ËÅC EXh…—<JX‰ú{ÒÙ~Dg
OíÂ°§9fXBŒ2gí>ëFıt şt™#_Ï÷|/›	¢­«dkæXŸ~¯“Ö›m¼3×é¶„Xo÷…¬óH¿ÉJÆY
ç ÆnÉp-Yk…ŠøÿmÚ@‹‹P‰$Š@ˆD$“M}ÑQ‡^3ù‘8ÒYYl‘QjğdĞôrY[‹6IB‹!œQEgK‘Ô•R× ±@›Y=RdV’CÖ¾$ìYl‡]RÖüû_ÕslÙÓZçdJQ½W-Z¯Ş €#éfWé8äh[Z$éZp–f,Ğ…òŒŒß‹ã…PbBÇZj‰P1‡XWX9R…}ØÂ¹!ë#Àtö	×CRn¼Ô*2H×ıÁ¾…)P('öû&h°ôCQ> yÙWQDt5Àe=äZé)½2OúÏàÇ<8W2=ëP÷í…€3u2<.ŠG_ã‘[\[µ[ÕŞK»ëQÂ˜Ú¥dõ7„¬;Ø–å7L¬£ë.µ¦?]kW¬Â¾;…ÜegUÃ:ªtiw„‹šŠ;Æëù[ŒüŠ—ÿ…ôÆ6ÿ`>ÁŸ8d‹ÿhÃT§)làƒTÉâF9Ãuøó~' ë'_À€d|[^s,²h\øg´; /Q¹>(8ÛAˆXÊvQ0±r3Ã"\%rGqnu	™E,â–lá>57\É&rTƒÏÿâG<W 2`
ÙÜ‰Ç$BÉM8lVà5°7G7!`®ÆïÏWVŸ(²YXºR¼!3Ë†Q+„xªÊÿ;Ws4´"ÑòºÙTß …Ût0W¬Á¬ßİòšÈ<Âs% Øå	´È‘
´Ãkd€\·26}%£:pßf¢İ¤-4Ê†ÜˆA˜—‹
Ş#³ÁìIÑv³uX)	İ’ƒúº\çùiÃ´¤WMëˆ¿æIÿZğ®ËK¶İë+©÷\@ÏÈı¯Œ¡L¿B”ÄÃàv
SS‰7]gI]1#Ü€*_•ËN6MZ]h"ô7¾ÏeğYá_ÉaüÃhOÁ „Yà·?ÚLGÒ~BjhX^¿şU¨¹¡À‰×ó«‹Ò_ğ÷1ÛºÅ‹bnªßÕ…çá‹<…´|¨ÿßøß'Óç	û@9ğ|à™}¨£ós‹·‹ChoµU#Â‰­á£,+ºK}Éx^Fƒş™ÂÉ–—½aSh–^Ù‰Øô¿ÀûØÃÂMÀ'Ğ«ÛƒàèÚš®hm²1îšÓ.½§Xë¿ÌBu µ!kÿf6Õªû<_‹¸¯‡øÈ5Ú_O	t¸Ä†Üât³ªÎ­ÁµQPÿ4µ,„;(ĞöháF_;V|î/G·£öÂãÜ%7é2Û€&o7Æ.U5Œ%¯ô^ä…Øh»ïÈÿFt´ğkVâuäPI…“§n6£²õ¸_u)ÙÍNR·° _Ø×›ÛŒ¥$‘'cƒ%ãû¨´äUr0T_ĞZ©£Ntù<˜¶7Ê.-œ†’"‘yˆ‡C¡3ÃÜ–Â°]5˜†¶!öÁJ'U¤^ø×ãîO&‹µ"€<•ÅfI ßÅå¤ƒÔ¦;ÈÂ"P-• …w¦°vÄàˆ‹
 Ù¡á_`2ËŞ*a`#Î<!Kg†%ì±ö-E'µ«öÇ•ı9âR<€°ÿuS†–Â „ç—CM–â"ç3˜ú*¹×_jorÔTØR ‰R\FÚ_ FÚbI/cö0&Ÿ·dGíz™}ÒB}ôÁúéÛ`÷Ğ!ØÄgÑ=Â)À!Ğèß)H	õ?‰ÁÁùÿ-h]¥È%ÕÏŞ‰Ï¬şÁ°cGğïæ°	ğtäòÀ.¯QSdRRaò l!BØ•'aÀöFìôñ¸Â\å£­sÔ+_†uô
F¹EŸğşÍŒÖÈ%î<$¦á8g±Roërv¼_W•Z™µ7hiŒÜßaƒ•‹Œ,ËBÊéâĞ’M¼	t-ÑNaOŸ.Ú…Ò73„—ŠãûƒX ¡‹€8/u€xMbo%½z¦g›½PjÕŒ²;&gøÑWWÃ1qÈ÷Eôè$œ/Y4…yWöhpÉ-5QQ”»³Ts®ÚÍy`ò{ZÍ&b#)Æ­L¿£@vEÜ´¬pòû	€R9tu3pHz}»tuàÜh>bí}Ü¼¤âT/àYws!†Œ~Hÿ²Év	Hn¢¥næÈ²ÌPLHÿ]GÈÃb¹*%hZSáJÊÙ æÃ6ì_½/Zë
Jš"X0FÁãÏšíğPÆ*XÅ&cƒÆ d†í,Ö&,‹#ZøêbÉèWcóµ‰$•`X!ÏOâ©fğÕºRtLqYÕ5AV3ë¤[Ö…“,e‹¬œÏÒ1âu
~ëºdçØgû'	Gš‘å âÿ †f#È!”h—ÛÿK²Ğ€Î	0ÀÁà	ÂTœ…¡ğ±ûv!£¨*ë‹@Œ95¹m|õF@¨ƒRì|?Øpñ—Ÿ³OÑÉÁáÊ‰Ç@ïßS‰P£D,,,h„€¸|#ˆrd`¯%> cÀ±?à«R¬Ü9s2’"Ÿ(Ñè¬dC¬2d56=ùQg•—Dã…¤›äÌ	 $¾+d/T/Ò‰]ÈJÈ7ÜEÈÙ	¤­$T¦xdˆ(¼n<MĞÅÌ%zeáï…_Ê0ÒÁâĞá\	È£sd³œĞÙR™daÓ»¡ÿ¸Ø]j}È¹ë1QhÛ•(ÛŠtcRîEØ‚ lXÓo„êK?[‹øÜ ËÑŸ5kvu{[ÑPƒW•Ë
s‚Ğ¬¿ö…ÙP,©he¹(lğ'ñÙ'­+[á ñœ”SKW–˜ Rxê…‡¨ £°Û½v‡6+2ñØ±*‹L•¤o—ÌGŒ±èí$úÖí"<Q­'k C>~Ï¡MtòÙ;#lU¤‡J!Õë&Õ"Â‰ç7Ÿ<‚	şæü½R#-	;;}¥¸Ã^ŒK£ı¤“1Î^qöÓHâJB Î ¼!Ö-Ê‰phP4Ãg*XÈŸ¼Ş}NúÖäÆ…' XZjÅ$vÁÜc”+bğ0”X+P(næ”‘“óá´¡…~ÿ¼_¼àC;z-Rª;Ÿ}fîb²{ÄÄõ
¤„g>DT&…•Gtäğ×3 Ævë¡i²5á*ae˜;ûæ=1•èwdÛè ^ QQ^lÀÿEÂ[ø".¶òÑ s‡)|6%Ÿˆu?uÃ8¬á(R(X*-2dŸug	<„?º0JToÔlkM2ä2ÏCˆÖÿ¾öP uö'jä—ˆî°/ÆPFQÉâ©LºÓèWëC…àa4*dk+L"òAhe1a‡$n#{eaRg#Æ˜‰0W¯JßK¡Ï‰4³ø êësD
©º	#K;$½9÷"gGuM7<0%êèH‰Ñ‹9ˆ;£Ø9Ğ7¸›'Y&ˆÈ½	G9v¬;(|…U‹;ÃÇ½uWÎâë‹=2›ıª=#‰ªKG‰î/@ö€>'¡x€œùŒó™;tá¬øNƒx y	“\f äbÓvÁ¬P€ƒúv“f
pæ|ô$H²Bfu"ÅIè€
vvf:g5–Z¥•“,ŠÅ¨¤İK‚ ñ‹uÓ‰öîıµ÷¬ÇEä“4ƒ‹Bqƒx¡FÿM }èqı9E8Wg¶ÿÛC}´sŠJˆMãƒápâB]¶%ÉÁá¨Ô6÷ÿÿ‹
ë31É¨ t¨@tŠEá¢ d"œ½+ñë	B	Áô’kƒU_‰·öö(#‰KŠVˆK>bàâÛÿ…ˆÃë‹‰ŠBgFƒÆÑj?p·„¯ÿ¾·Ø¯iêõ…Ç¸t*Oxì·Û q³¹~vc„‘ß;¹
÷óª‹	Ñ@ ³°Á×øPq´¢=O³x~QÂîdc=`Ht$:™{2~œ	 8 Ñ./	RgÜRf.¹E®İ’Ea ìídPe÷ÓSöŒŒByo™³¸ÜÀÀì<Z#èı¹€jB0Œx¦£ı¦7g³ö÷Öƒî€døÂÃ‹üë¯[@;äÁ“[¼>ÛuóÉàı¿ƒt“ÍèØ	äéºwJ'ŠS H Ü1/ÀÃ…Æá¿z6ÕÒöÂìRû¿ m9`€â@u	9×}{éÆ€`¿éSö…a›mã>$%xu
!¢Ûíëq»ëmC—[G£$ıÙbK¤y!B±9JoĞ9U~Àë°“úm´Öáû;%9ÁDW¶×B2.¸§ÎşÍ9Ñt.úS+ıJcÁt\ıÁúe›»½Áø9ÂÊŠCAiò_K·ß@ˆ‹CìPPP3ÜF=Ô,š4×ëØ‹‰SWÛ…*à0Ú9aG5ïÛ(ZŠoR½.
H¬?W¦¾éhÄgrF›°´E-èÅ)Y§à1öğı68 è}…Ä‰K°«‚8ê8r°´QÚË‰ĞeÅø½
,œÛt‰M~SÒÕÉH·PÈ
’lgh,µöUŠ<W¾"€Ë
~C¹!h	¹‚¡DÔì ½Zé(änäPh/mâj”@(. %h„¡P ²Pÿ¸Ÿô£¾4ÆF
ŞvIò¸ß¤{VP[H¶3ÓE…Òá 5‹½)9>Õ6 g0ğËº³vPû+¨Ã†0¡È•t°Ğ0ƒMö1híàwˆeï\7¥O/S„!+”†A‹É¨ÀRåw]¦îH}KSé˜¹)ÂÃ‹+‰d˜"õ†']jŸ#ÀË½Ç@Ì(°/i‰ï¨ŞG¡‹S£yÖFI+‡¬9ˆı:]Áã	¡XtãëMuÄìífÑÜ'5ë&ÍDÁŒPÚ‘¡ïa-ÖFÃÿ;w*Ì‘u|®Õ&ùASÿJhS®› £2÷·¤"ëo¶'Zïoûe~»`vcvøÙó¤‰½ªPf¹ Aã)ÙB›ãlR]‰š­çApÖ°bhÄ¶…s)eÿ}o¬r¼è‹÷Bï>C§7*¯b%¹ƒŸğbç™÷ùP9à©„	û˜/¸j–•šà	PG7h›p4°›hDR1ÍÅ <)aPª!c““E;\ìË°Ğ±ß=ÕÁ)Á·[³coªW<İ‚ÂÃgdæÁFçšíVÿ’8²’ÓÆ+*É1;&ÓªvÈ$şS]óSœie›1)éÕŒø¦`‹uUãùaYCDV’‡9ğtBÂÒ&i $2f"àe7ÇÒ¦Ù+…`ÜBÍ„.øÄ€h}²S/ê} ¬‰ƒ’Â©^E„e,¼ÂbR$V½›’†‘$¾I¾º²ø1ÛQÅ
šHïF®ÿã0Cƒû€Æ.œáëÑPÚ…ZrC7WW¾d•ÌnŠ×-ğêxié=éV-¼4i6Ô²K	u„zÒ°³ÿ¿º7Yán0G„Sh€şVBqòóC~àÙŞĞkPµ×Z„t÷f¼ámkŠSğ`7£•0¡ş
‰ˆ|‰ÄYYUô#álYë³İØ*ÛRà¬hÿù…%ş¡™;U”`;9Î¢tŞ‘›#œé!j®P“–\Xİ„`±‹ShMàïhŸj?]èGƒÿu¯W­EêUÉàZp)£a3¶BP]ŠoÉÿÓŸ±†7ĞIùıˆv¯,S)F‚×VÃI„ÅP®-½ŒÁQîPéˆ@T¼AtRÆäù±EHçVh-ı7°„§BŠ<¤ùçëŞ`!iRGŠ€®õ(Æœ¡7ªÉhkÁ6qaÅÎgù¬ò%$êĞù‚‹	[ã?tAƒùu½¦¼1&`çâ@‹èX R&&Û£uÃ6€8 ûº…[ÿ÷Øf%òôfæPGSBS½›x%öN~–j$j†W†dÏ"‰ÂlM’ñÀ=9Ê¹ÕdÁlJôOÀ0† c‹o¦¦M/t Zë9ZûÏKÀ4Fu¸@9Ğ|ë9
B@İµ.Æ®‚¯pvUükº MB=»"€£şŠ >÷ĞËIê eCÔë¨ÍA[~{ïÀ½œ-§Ò;‡èW®í¤;_IC÷Â-_,Å¾li(ë‚Şs¡ÛÿXq£ş—uÅæ£àCˆ" /ktslÅ6"ÜÀ\€Pn4jT&ù:kí­PAZvªêuG¾]ÔÕâh`DÚšÆÌŞ^xÿs©°e¢D|ë¾]•h—9 ß£Ô¢ÈÀ[‡X²–¤ÇÔÀO’ƒN~qy´/H‚o¹:j,8a|7Ù8çå ƒE'İ¾âø“	RÀËKY:İPPyYlWæ˜şuaËQQ;lf;æf-¢Kñw`ÁHFš0]lä™aDô0r}»rhƒ9ªØ£Ò¼0öÏ‰İW/0ş@È (¤l”–‘jup;‹;zÍ
{  \ëuºéVù6{EC?Ï{|İRûF°Øşˆ¡|4RşÍEˆsIeRu@q­ÂöÍ@˜
‹R	9„mÃ-ƒ»Ær'h6m+¹ÜHbS4vQÏÉ–ƒüRm¶DRRm!f. $63dG5IˆmEâ9uçPP¡.äŞY$ÌÂt-µ%8BGJÓäIÍºç_–(‹K,‘pÿt‹~İD-ğ…‹•/Å²uIĞê€‰Uë­„ä€çRù¨:uˆoÉ¶J"p:Ü‰Mà_ĞÖM*ØØD°Äª1šì;†œm¢›C0ÔÂ•­aØØ¢*SAöŒx‰‰ÑŒ€oı¨Ûu1‰²ucúä¯½í¶Ê€È Áø,Ìš;mô”ĞGÔª’ÈZâ	›öË¨ı$æ—‘é{}È÷I…KùNë"‹½j®-´eD `Ô±v€×“ ‹cîn+X ö‹™cêxX¼ ƒÀ@õ±½$êß–Ø¢6E	ÈˆF°n¥ø'‰øÁèéˆË·ìøŞ °¸Y¼É~= bí¶@€~3§O½¡=2~#¡ø;Phàm42•í$Ğn<ÿ*ûƒ`·p½Onû[6–Ap*¸T˜¼¸£#´,PÎÑˆG1ò‹n=@Û»cÎÆÆ² Äì&[LéŒ93h²nïı7¶{Bˆ‰ÇˆV<+#ÍV¸ğ†=Õ7Š9Ç|!İ¨>S«	o"µ¢0 l€Ö¥ª=o%ÛF„v‰úiU_àsdÅn§Às¤•0€YÂ''‹Ø¤
”
X¸„à©Z¸V˜:äq¡›Èn
Å®Ád²[²MX•j7{§ëví¶Oµu_Sn´Y:Á°`tX[°
fdi´8`dÏ–JÌ‚ËŸ`BéâEbXáËÒUGM]€0ÛÖÍÀï	ÓJØtõwoê³r.TËÖ`cM±o
sXÁÈ;léN3µ"¶’7ƒxZYh¾|-éJ9Ä*ÎŞ°b	èin+‹ÖŸSKô‰Ï	ê° >Á×UwQ”)zñŠ—Û	­j)ZIm9‚Ç~Æİ2JÍˆ‡ øËËÛt-t(?t#²+T&p¬"†5^YA¤ê]ƒ½ó‘ÖÀQ±r¿ú8[ÎxŠ	|+ÔJµ(‚@*÷Ù\ ë4ù’ÅWKx©¸d»HY|—±ÜÆQB[ë`IÎf–W¥…gk=Ø˜uƒ.$#¼^’Ò*š+5¬jËØêxŸ œ†úÎÊëAĞà‹;;L q«z¿ë‹R¿æ‰K‰&Ğ/n&0ğs¡%İZ 0%q‡,›fKKKY[‘äNHvØŒœ¢ï2Ìˆ¨5s¹¦úæõHó¥Ç@P|CÓ0S^c½x I¥†“.ä¹„D-rÚ´Ä	‹VÁO‰×²éÛIu™‹!Á!×T	Ïä{2zHqœ°‰îDsMCDk)†b	Äg…‚Ë¡ÒñR\5Úà3'Ğë[;5?‚æH$qq—ˆuéÂ@Â‰S]@=à L¢48ŠèÎV \:Ê¡´ûm!?mu@ôOİ²w¬|7h–ç;7Û)ø¬P;)°Ã©º¡s7Pj
Snl/ÆäÅ#÷sŒ@£ZrDÿö	>ÁÂ/‰ß.9Êc}á€5±ÇùPGA¶MÓPD¦Œ/Ëc@0Ôu	ÇG!¥âqë!–4Ğ½Fß¾ÄSİ¤ã¼üÎ†ºÁGT=Êƒ½«‡ÁèvÕwÚ5€nô?\>CéşYne›¹_ôšóO60SäS°I8etâÕI˜dFıÃB26öQ0µ’SVVèğÿ$ÆEÃ&jhr¿îGŸŒ@ÏëgVh:`°WûòXµ¥L€É`-léä¤`Cğp-4âmbW±™rn.¼½ß$@£LvA½aƒmõŸ†Ä¢Wù2Ş$xPœô„5Ä±˜Œu ±Øa~³@u‹*REb V%Ñ€Á¡â3RÀ¶¶"¯Ô$PØ
txjëøçõD<XãHuİ1¬ÀE”r#-tyÒ»zM*0Yù4}xÿCƒ„ìe„ÆFûëB6
1.‹È%l±‰†€ÌÍòœÉP5s${Q~‰è‰Ø¬`XÄ
ì×< l”&Ç4ˆ‰½H|êGO‡øõ…LÈµL\2ròæHL%l¥ÖH&Æ1ìHPV®rÔëìêğy˜rF- ÁB{WbÍtğ™Tá,kàk““5ıø‹Åâ, ƒş¦T)–Ï6²’U
ÉËåCŒW ‡rÈ!"$,,|Y~5V\07Uîa‡²89<wûÎ?5AG†‡rØH#WXG[vØ!]td,ewÈa‡hop,ªğ¿r…é¨ãï°Ñ]WtR“%âeÄÙ.Y˜H"-P³õ.JÄ‡õÍ*eÁÅ²lĞÈ}°`à7hWb!ktÙhG:Q8HLN"n,‰ùWÊ3Ğ7„À˜ÅÈ&M,à˜•k…vIV²J°¯s[â€áàõpJV8ÒBK„/Vä° ü©Hsq.BQ“@.BR!Cv
xnmŞŒDÂ[¬Ø°!s‹fYö/tğUSLàh–USÀqîèèÔ7tëbŠ†CÊéI/ÕuBM<?¦<“T|ì<v7øë†øv=îx2wa_Ã¾×{j›ë@F`¬‰d`’#cÕu2È‘@E¼uMfÜdd@à,uGµğ[¹á$Pç÷ qT*½Pº`	—f¯„Ô\¶"ØàäÇ‡R µ¸±S5ò'Ü`
õ\Ô–‹+Œ$ÜÚ‘'ÆJuY¨ÆGs0/è#x4X‰ñÄlO A»uu2o´±ı¸‰u¼	ÀÂİmr´1ÿS‰{4ì¹[W¾üa²àBF…m•ÌS2øşD?ZñlS×ZòÅKô$'	ÂõxÔ3¶wåM´QU@¯MKbÖ ƒªİ–:İ±‹y61‚R‹pË+>.Ô‹xM?1$A"räŸ çh&âë×òBtÄİTÇÔÄ3òÈYw~·ÉXØV¼RFŒµÏ¥‹i”È0—òX\\ç	«‰\”XíXĞØÈPHã](&c’ h’Õ{‚£ø…¡D
› ®¬8 |™ïÃ¾:";µ6´Š°¡‰«Õ®u]¤ Áæ]4c@íÆQ Ö0†P&Y,è¾S¢Úƒq}‰Õ¿ş¤EÇë97	^‹“–º­­êñ^ TW²VI!ğÈØ³F=$3ÑÇ¥.{¨]‹ñRÁTcozùä£º}ØĞîƒ<3@Pl*F¦àUgË¶!A ÖoÙîÅ.\wOu+£2ÒP%üÁÎRõu`Q]S¡R¹VôàW3NÆŸ¶ƒââøÎXŠÍõ9Â|&ë; -a(x‰²VtIŠK2üu¹H¶%ê‹Wƒúÿ¢	ì¡x 
u_´UG2­;lX«íûq ÖÚ,ùCç&¸9#´^+W«U¢É$v†úÔA3T{ KğAè¶ÚÁél,TeF ^ã~o†~vŠ?W…xh´vÛßÚÉ‘@~Pj@+	·ÄwhAfÅ²w(‰K+\ñÖÏ¾ÈH)üötcE*o•3xí¬Å<0÷`{­Å#µ Ü–äxÈOÛ²‘G<¡"‰ÚµFıK$…Éur7^•:¶?Š‘¡õë#iôÆÁ¢=[ÓçH#ƒoÉ[pŠeû“„qˆEƒ–eY–„…†@,Z‡µ8Ü_Ğ.’}¤_ uÇ^ĞˆSšÊMã–şÁë`™ç	RQWS|M`‹t>,/ÛßXƒ8Eãu6„äu.…Ëò²¼åu&†æu‡çV¨
a`zÓ­ß:@÷ĞÁèñFÙ´p 7"Ñ¿½Æ|ŒHtTH=à`yBC\kVP!^¬‰Û%@…@Æ€â=5æ~ScU°´lßâMÄë ¤ (Z!±², «	Hô¬Ïë/gV¡yµ‰P®”nØdCvs(–6¶E(b’~G]‘Fà$  µRÆ#h_Õ ~'j:ƒo(Ù³½à$ÿß§b‹5É§@ª	å®À¹¼,ê2€	ÁUŒl•‡åP¸œw	š†wÚĞ íëÛ¬$tEŒFu¡#äCtS,I± ÂPUœ`î,ˆ¸e+!Ğ! cŠ!cÔófÌÂ6*¡íözD†>‚<œ&(Ñ_©__6„:ÖıxQ`Û´. ‡†üÅ3ŸÃëZ9t6‹[£z·Qmò:ct‹;x>jRæØ”#E>»l?•Ç‹‹t	,Øë$CD<f00áA~B7Ä¾s¨Mî‰ŞÁşQ*±<ÚCxÛĞ…„‰ä}ä#àãÙ>aÆ«Ø0c‘ed9äíC–%!rk"†Y>ä$0rT7Mzy{8rF9vh<r<õo?ËÛvrAr2WXr([vJ////]tYdrevOhrnn/ovENptrt;¡
Çgö×p+%ş	ò\ÂÊÎ*ŒGªc ›²A¡±=@…D³?´kb2ûnS»Z+óÿùéê9¤\Ô}¾@¬WfW<‚Æñ ¬¶Æ¶Q`”à°‹Z´mSáüf‰Aâ˜÷Ò!ÚJ£[/Îw/R!Ãw<qµ,:VX¤ÕGˆmÃ‰4$Ä¾àp0±1Äà=
Î¥+R%àv£ vT
¸1»O ‰ØR¢8ySF|YUŞ!ó6œ&š«EK«İKD*JtBÛtC-ÔŠ=>S°ğ.±w,ŠC:Ì^ˆş!¾Ò¡€õ¿š…nTÛP½Í·À=š)¶ÔÊpó§Ç	´š\nÑ†‚yğ	[vrujÿVE;P™ñ¢·»Ñ],†	õ¸‰9ëë4÷‘£hÒß×CËL¹ß	"ıWqì‡a_TÎÌE|ßfÂ3´D<n"7ÕÄèÇƒ„PW€XŞ‡Í‚{¢rQJ§¤ôƒ§â‰Ğ}°3a´6»eñàyPÿHPàN N„pZ,‰ã¡ sk›‘'z5†÷’#UI•#,zAGQ…şW rYàÙ@²YÁi%ÅoYª*1[!ŞîÜSoeºf¾æUª!†lpË§z¬«"K³}gËŠZÀ»gm‰†;7DL?$)yr’XZ$ıKÿÑh1ƒÎÿëT!Õ¬!À„7j<¨°‰_²ÑÆp0P{F€ß¸T¼vïvèxˆg[{şK¡H;è±»mÀ£ø~2h}IÕ³¯EØåg-¿ÖÀWÍ9gôá°6½8o]}ŞW­İ{è¢xKX×õoå–ÁN	×f‹f‰Hp	¸èïğfÇT¶
PşOwß Å¥ï5V32Tdó›#A;zdó½Ğ±w|±€‹µ¥‹x÷W‹‰µtş 
Éìmæ[|è¾té;Ï!?Œ5¤×Èı´5¡ˆ…˜¡
— a6n èiñ%õ‰ş'|ßiûR
é$Ê‹oÆ<ËqöâSI|P»É“‹$âVœSx–Ju2WÔ3˜V!ØËÃ@t5°#ü×…[’ƒÀ1É•>Ï õ7`ŠL„Étğåíÿ^";5ét€ùt5t0ĞUbût+ÆD"b™OäG¬FC|5Ñ®¡ €2'‹ıŒuª‹[-p‹º!ß1fV'ÀhÊŠƒ½ÁıBğÔˆÈˆ•”
Ro•0/ã$|I¾T·×hÄN2L‰º¼÷¨vQkLãmÂıt·…–Nèû±êC¹2ë¤±‚‰Ö[¼8c‹%Æù\	şM~^ˆu‡àĞÓãB[W<VÃzTÌÇË» ÄÙ8-Æy*lq`ì˜'G‹
¢±ï÷|Ş7FCà]×~õT~– À9àZC…°VıG-h5zãÑĞ€tBÍiqÃ„ÂV­<Ö4hÊ|’wğ¨AZŒ$0ô)"&öIÇj¡òtbÔ|Úä’`pll²¼clÇŸÉÙ€õBVsW !_ÉÆQQWâğ3h¨l²‹Ö[¡¦¶ZàÁÔËĞ"l,Ï5ÎŒç5 "`;}Ğ:":¸Q²}ÏbÃÔî9ßÓ'Í(‚Á-d,}¨«ôfó£úu|À!kwWGY}£E`lã]ÔÉœo@%	¡°Z[Q„j(9Q+Ğã}æz…€5pQb€_ÿµ‰}‚-2]MRÅÇÁ)¬şU¤û®ÃG‰<¹wˆø×*)ØyIO÷!ÖÀp”+;YAÀëu>/€†[_j<ÇI6„ä(é¼!ŒA~ø©R~:ƒ`”û*ƒ‰ƒàJ¾9)éÓHP'8†,Â2$PPÓ(×ñ„ı™8‰
¸şÂbĞWÄÂXYhH…¹ä³°ıº	b‡Ë‹ûpÈWb™9S¸)˜%î,X¯Ÿp&VŠE©¿¡´D¿T…_mc0ì¸Oš0u¾‹PÌEºÉ·şVL¾mvfƒK2¦…´`ÎNŠı’
 Ä!'‡QÿQ¼-ÙLâ}?~~?0ülÕ~en¹P¡tXƒ /h¹PlAh•ZYGpä[5â}D½všÉhˆ- Ô—ê¿p¸d 1:~?ˆ¢~ìù\‹UÌ÷Â^tmØ­BItÒ­ànÊ )úkúOŒ´¦èB'+CÆáÄHV1‹§ÙbåºøºM+ĞVRråxzö0®~ÓJú+%¼(E°3öqûØ†«.’Æbª~Q,ˆqBYZ`w„XlŒ‰C[8”ğ3ŒRš^X3C(/H}Éş†%—V!~zV0Öİ#P{e%uWB£©Tøëc<>°ä?àVè '2t!²+2)E†íˆğ0ë¬ÈJò£]Ş/…iHĞ°ÿ †LbY•”ŒÙjhXÀæ£{h€Hƒi)¾ïQ’ ¡H3Ï¶ä7p,€C¤tGñÀ;¾İNƒ<µx<sí/ÀõŒ#ÿ4Ä‹ÃÙ\õƒfFMJFüÄC°ó~ÙoRÓ	Ù8C@i/Ê$|2Lí‰Ø"Êmt×|´|B¾Œà[ÿ6)9~Op¾…_Wª^1v†]åÖé	£z+{h}€¾$ø,¢Ş‰$ˆµßv‰G¡b‰Fk¹$0‡K¾ŸJ"ÜÔ¾™Š¢>õ—2}äV3W´d'JÄ€Z%PTºà
äÈ¦‹A¼×à•êJ˜¿`š~Ä“ØƒÈëo¥GaMŠ€úNt6nt1Z¶,YØyÂI®¡©¾À!#¯ßò$ès„¢„¯é¸‹#ûŸàİ,¿©‚hÿUÔöB=t÷‹‹€]Ørã[ÉJ ÿF|™[YV7Ó¬ÙÁëÔ·x›ä‹0ÉæÑB€>«ñQ?¸EgŸQJÔM¥€o@[B&¢µ¯„©“O$sV",nE¼V&åÔ%PI ëá	qaş¸‡•uJ—¥ßß)<¬£Y^œâDG†%4+¬Ã^-'j A€#mNV„~*€=ô©X0y…aFë6Cô1M>8¸v»‰G¹¤#»ï*Ç¡ZëˆK½Pñ¡	\àÿˆ03¾GƒèaîäÏÌöĞ®‰æÅàFÕš"t™8*Ş±»tO‹$Ñø’Şl›çRëşìïµèßG}À#DÅ-ânŒ–‚î¹Tt,·‚ÉJÀR &+LnÈkÌ§~ÁãÕˆ¾¾Ü*(¼†Uèïÿ^ é£r‰ò	Ú8¶ûf²ÌCN‹uĞ$U±­}ølï»aŠeg¿b»µĞfÆ00Û¯ø`¸E	Ãìd{oc½Œ  …ï([ğÀ,XÁÛ¡L î¹N‡ãZÄ‚³­²­Fö±ïuÎOÀ‘Üºƒ<…±vë…­WË­{…~r:ïFÿ£¤tó3üè¸ cRº.Ã.älë<Eæg/Q{[hNuÈZY[ÂÑWìD`†4Y[ik¶µ÷r[_{EäXh„Xhy@9h–9hŸpH·ä8h¨±»<„ƒS½7º`ºÊNº%`+,ÁRÇ«Ó¬‚R«yËáAœKĞbîZaÅ2bùhºÀ>OvÉºj"hÃš·äy"hÌ!hÕCÖ`HŞo—ôÅr‚ç‚“ …‘ÁJ¹Cñ—ü’wth ƒh	ƒqÈ¶ähƒ‰Î+#ˆ” ˜’(§¾œêHNÑfWñpwİz‹‰uY­01€¾Ëƒl}j•}Ï@ø**5>®S€=»+qˆxeö)@;ÈrW'€ïS éLôÀ5Q?øl¤uN|üh„ûÌÖè#½?/%Rv.dh_Q² {DC¨Z¢h.´ú»Z©ÁuØtb@â-Tp,ªlQ»Ì	°‹t`hÿ¦½&ò®ƒùúŠFûH¯µúë;€z¤k³²¡»CRë*ÇÊœ`ƒ5 ë't.Œpû,Y_Vi{'
Vk[¢«š8r]u‡»&1Ì„úÎï’[tƒsmƒéÕ7ğ¡¼ã1Ò·ñ°#¾˜;4•Ä"%Bq/iøò=ş FˆÉ‰ì}¿…@£/é`üQ@7»Sah’jÂà¤‰¤2-XU°ªĞÇz%Lª®†³GXÕkëÇƒ¦ecWÁà’ÉPR‚VÃSöÕÀëPDRCFÚËéÂ0hQ rôj1c}Åiö“4Ù€a‚Ã…ëˆ÷ª‘¨M MØõ<M1’ÑŒ™i…FõÆ6¬‹5é
˜J>S]K¨PíIğÿs\ªë{`ô[¢©4Ú$åB¢Úõ‚\ĞğìKŒX7Ÿ\qè+ ¦ éÓÅˆR ø¥dÔWËûeº„<à	Ğ³#EŒ?8HÃ•¯u3!LÕ{<²ÙşU$>Æ /@	d3ˆ€2*PmP^ÁïˆÛ)$§™‰²Æ1¢LÆ‘Ÿ'ìŠ¥Ã|Â"œ¢¯§;‰ü˜QÀz¡/MQÇän¯X7Í9¹ãî~¯ÂóZkó¥m‹AüµKˆ ßi9A(O~[;³3?hQ$ëm?p
x{€y.t.ë– lÔBäR‡l^!zÀ{tLV7èÀlÃ|t52%Le¨÷ÍãÕ'ì€]˜˜H‹6ªİÜäëOW„7>´XÑÉÆ™2@<x´€Œ_~¡-z2p•"^ç7‚OÄ*Œÿ/ødS…‹ä }ğ©ë•#$‹b|>V¹VhKåë$9pY*´¶ÛìŒû3‚'ÇC`ƒ‹@ÌWFÔ®Ø‚ÖeÕÎVŸ„&ÇŒfÈWâ5]MWæ
]‚ı‰Á}´¬X‘`À€ë"øˆè„3•†%¢Es‰W
G:«YXXı¿eÌPxBƒú3uÌÔrõ%‡j€a$ g·„X XaĞ4Z ‘‹„òWËéF‘Ê!Œ„©ñz		C7y¹"XlÔò>HÁ1 ‡ëJ;!x¾,%x Ø90‹Æ²„ˆ0„¡0°BÈêutÃhµ¿Š(,"<Zî•OĞ]‰€s;€- jV°…HA”Ã|g©‰ıÇÕ€Q±ÅWE¢&QpSÒïº F«
DKëYƒ½‚]£z4Zà= Wrûqò¢,
„ıÙLÈP#1à÷ø5~f…15ß§Ù]*ƒ¥À—SXÚuÍ y¤Ñ<Q°ñ ËoÂ´UÕÆÂ:_ f%¶ Æ)RØˆˆíKmÎ9Ñu…Í±[8èÍfÇ  :öĞ"6 …Mft08Ø±u	'ÏÉWä#à<VuP$fÑ£|ØTÏŠ·*´…‚C¬b¤ÔÈ„? Yï|‹ngl]h¬Å•0¸ÆïÙÈˆ…DÇ(¹P÷•ìòÀÓØDzT±4 G¬$*#‡S¬ÉæuØ…¬ÛË‚e•+Øª™ä3Ñò	ÌØ`Œà70‹ñÑlØ°s9GÁ‰WpÀâvo]•,¸4äRï‹ Ú`©é
à6+	eÿU)[ö$š=;EàuBTëó BSh†‡…RÛ…jˆ@v(Ä6V¼o¥v û °Á$ Mƒúwí¹%Dİ<‡†„&”£ fv‡}ÑyÓ9|W}àˆ…1Å»š·•8<!‹$½·¾öJ uğÜ‹Ü/[CÕEŠü	 ÒQ t·p3ÁêÆÜíjšò¾•$¢*ï‰}8ÌUñ2¹>Ç %ˆ—pdev/ºPÛ0@¤Üfø†Á¡.@÷¶ÀÁ¢hgÀ	ÇÁ…  cÇ®°ş9s#3ª´şA­´pa%‡»j£scYÑPş!F°‡¾Üe†Ø§Y~¸¬»ƒs$º‡m~'!=2!/èî™~~h`ˆ^öw|ÿeëQ¾ˆP†Ù˜LaÕlöş&«Ø!e¯ì‰úzÌRzƒ‚QV½¨òÜ(–ûÛ¤Ääòˆ|ş!ûY^U‹Q—š5‡úÖ!ÿ"oO69uwxé±,0'…[ùfgP®‰F¨vdŠÿÆãé/½p Î û/ÕWÿ‚kÈ,;œğ6X uÅx	…[”hKõŠ®eä¼×Ì²+Ë°‚2Üu86ŠFñ?~£”Y—…-çql÷WµSìıĞ÷Ø!‹'‰¸äØ&â}_O¼ã•Ş+¼C{V""ßË‚UĞòÔG„Hñ·1cM±Éz•;/p &/„Ã€Ìö*ö@ëW#Ö&Ztòë0™`¦ ÏXru ûûÏÂkÿ,‰œ=ğ¥„=ô¿Ü€N@á”“TšuA–¤H!ì·×fÃ ¿3aÉ¥?Šğş¡ğPïğ…‰ì‹H¬:€îkú,J õA×¹oëwf‰ŒuoÿÛèá à°£Ïs;Bé€kûÿÿûØ,œ$ëH‹3ƒë,9ÎuöQkÀ,ÿ´•œÀO÷kÒ	h4ŠşVüÓànLë!AÿÆ¦{îhµ'hëÖ\Éh,¡M”ìı4‚ƒ"8I€S¯Zı0Æz”Lä]jpS‹PpxÛáSßÉâ7œ{ö ùt6_ŒkÚ.û}Ïø—‹"9xÿhßxƒHäAƒİlßİ—g|àëÜƒŒ-!ÌeŠ÷ÌwG‰ O1ÚwLúªüöîÖ@¨m:OŠƒèø=„n‹Ï=Æ—À0²ğ:ø7=«ƒ¼€¾Kb¡œÁÉà>„€šUÈ’+âÇ>V+íöëÿ3a…şJÃdè÷
úFƒÃ,ÜÂ|ß1 Ã$QøØhÕ‹K=¥tû¢kÓÔtuÿ	€İµ”ºU‹;H,~«Õoé$p·½‰Ñß
X«³mø$	$wœ©a];ˆuÊKƒ­I–¸AË”Ğé}ö’äÇ|ëk6ÒHôy‹„Áè‹=zÉº±`…/ÁÑ ]TÛä`ò2ª)(…‹ıõ©šµ³ ğã‹’íğş&Á;P‘…?4¼k\ç½k47kWfá³ÂÈ…Ö† v×nkÙ‰‹ƒêì'5ÈQL8E‰6fNÑ…QjÌVfîXêD]Q¢Ì‡|ÿƒĞYw½ ¾QÏ^!¸X.lHhHËør£¥ÿV6CÙYŠ–Ä¸¸6¼T4_v‹U¼6øsŠ¬MÀ0É¢ÀW
²`ÄÄ¢4ñç‹•¤ÂÉ‰²¿íÈ‰‰ÁÈ B)‹÷F¶°´[\ª¡âÀ	ÑğşìLB8…u9-¾¿¢»që¶G;½ñm¤I‚½‘ë
=_%" `•RbÀ„Aõ_±H­¹€ş 1ŒF© BuÒÖíhä]¥ÇøH´´kóY$€íÀ¼5`:GGt=‹”5±œ ““Ík¥Œ±ÇFdRŒmU?zÁäa³øÇBÿ‘€Œ¸`î¼ÿ2;äéN*ğ¶‹'?ZÛ¹CÍ¢Õ‘Åµg:-,ı-B²Ôá¹ÜTàL±|è˜"<ÂƒœÀ)KC;8lª·Œ¡%äR1Ù»;=”¢a;™G* 7<ıŒµtXálCøÙE‹öÂnÔ­ÅHLÅôº5/4"™÷€âç×ê=ê‹sEPäâP¥LJ‰ğºîR&#şSGr¡n^R´D²²‘´‚z—ü}é?ÆA'35NkÆ5«C¼mÁĞ	+óÜa‘™Vô§K-;`‘y‹SIÖÆ¿Àô!Á€át%ü‹ÅL@,Á§Ï
å:ÍŞÎ¾×
¨	‰ò¡1jüjg¥‹Œ@ÙÒ™ÌöQYÌ16bßú‹-_j˜àbœÄ·9ÀR?ÄÔ´âNÅ,°Q…³ Üö¡–˜¼%_¿³0œØÙ ‡jAr¶„d‹7Õ»Ø½aµiz“Ùƒùe¨ñ‡¯“‹¹ù´S£˜1ã‘\,İ\Ò!våSË‚À-„:T¸}çÎƒ’şÃoVx#;½É‡à õªnD;±âßYŒú‰µ&ë9ğ	'4Ë—º9FMxšŞ“×BƒÆ/ØÛy~©Kx"=y‰SkB‡=¿R=ğb”º6ÂIè<â	•’/ANVV”Ş^˜Ş÷»ë3‹¿ô-	ÿ~(H"‰ùEûÉCÔËr‰Æº œ$‰BÙÀâ/ìò|ÉdÃ[È¸È^Ê-âí;©”Ëƒ{bëMÓ‹ĞÛgZørôu5ùtF‚Pû<‡CoĞÃ :QIèhÜ¡=`ZëÇl{ü8 6FSì2§+¦9C­İ¸Am;üÕ‰Bà#héÈg‚öAÛU	ìëNK¡¨‡İ¼Iä•Rjğ^¼höTk &Ó´|1Œ¤ÃJø4ãÚ×H“¨[r—õ²H2¢Å œ]¦Ã-,3êğ¹m—øKâÂRƒè€…ÒÑ qof–C5l}tp€X&Í‡¢˜l¸pHWR4‡Ôıj@úG+‡$g¢% ›şR³ÖáÿÓe˜pƒç!Ãƒ<½UO²;—ìxâVje6’OÕü&«˜±ílQ=@¯‹G•Àµ˜1:z™’%âA§üüšlÔ;)Æ–%şö››äM1š˜}RLæ^5AnˆŞªÎ\úhJ„èƒÊÀ–ÿàŠKĞt¤ã¶âı¿ñ–a‰‚Tä ›¡xşxş„›+f£T³‘ˆp)Î¼uö(š+?‘q’='P@…P<r-©9?ac¤õ}9ìƒh¤Eu#ƒ&}#=94eu¯8Æß†¢øuÎ‰!‰4€cÇ‹9Ø•RôaÅ$lëI÷à’‚ä ©é ¿¼şY^Kÿ:RAì4GÜÏ$ºñpÀä‘&Àº lÃ€Ö6’pzqkªw½ƒËÿ %)ö	à}?vPÕ•”¡Â¼°#P§SEJ|‰±}Z;X{ô[ŞtüR;P7YÁX[/N¿Õ]J÷Ğë,Jt+mÑwuÖÓşZhê›ï1şqæi5´¢_¯Ñà1øBóB[(6«	Ë[mHo8‰ZÜP_E3U´¯ü­`Šı\#ã˜Ã ût‚0á4½4 û ñ•ùÆ« (]lYÈAõ²Úÿü!T=ƒôm©j›<9XZ`’Š¼'ƒ¾uùTà¡	á~®xH®‹Ps	Æ
¨•ÚB‰))Vªø!}l ëåÀ{ufOƒq”rYXjRRƒÈKQQ¡¨£˜%ıl'n®®˜¸rw‚·ûn@¸…Gh’ˆZ‘ûâ¸	êª6zŒµ{ˆß1º²€xšxCÖyÉ`»”M$P%Wt1d+QiÊAa¿6{9÷tAjûÿ
âf‹[
fû¯ ­­İ‚Ün70×RÛSC“ Ó%¬t{šˆôsŒ¸Uô¾@È9Šà3€úH//oMt#St!Tt-///htmtstt©±­.¶ë	8<
êØ-UEvÇAtGÙcWql.ˆG6_3.Œ‘
ZÌÍVÕJ´%0€t|Lü&{œ	I-&~ü \+…&¥°BÏXuö(^rŸïª‰Ğ‚Qá é_H» Â=dÙnHî¡hO·¢‘%‚q~Š€u)}€“·PSRHp(¥`ah‹ZÔœĞ‚°t? #•»¸Á!NKş~IôÏ“95Ô›WW$y
*Vİ=³+€C3hÿ[V8äì‹Áù õ‹ŸœĞô½Pò<òT`d`®êŠZù2«;©^{-9#Y:võ+j¶ûuhó…ëi‚KT8CãWÓÙÅëv##Ü	¡Ì£íé$D¹äXŒ¡Î ÅbÕœ*@‹ æL  NiÊ@mGI?Êx€g(!	m«ÄX'&ˆ¹P{@Á¥“}ÀW+=BäzÀ£¸¬BÍ¡<‰:ã&+¨a¿å!fwé)”WWÂ„–Ñ6”i„U¯¹ú`åª)JÙ)¹GaôĞ(6R±,à·ır¿p¾G¹€é©~Eì4²Í£ b‰ÊÄ<ÙâØŒO	~Z¬$‚àAQZ1aÇIÍEhRµHÅâY_‹”6ò@R€ ‰@™‚ ]ÕH*wë÷=nº~«êtKËÛÚ¤+ùÀ\+W¸ObÙ€€†,ÈaûµÇşQ/v<ËK\RRõÎÅ‚6KP:%•hD’–ïP€ÁY9‚£,B‚(X€Tc½Eğ\Æ s"Ú;„Ã6Ö¬tÒR5•'IDâ£•TÍ8 è<Fô’iŞš£±QQvo²Æ2vl‘¹²YÔ­‘¼ Ù’W^ÍD¶}aVMÖ›Ô%X<a2Ù;bHC>[œo²‚ç.ˆ×a,{¡eYúÂ%#Ùô]­Åx †ÚÕ‘oé%E‰ßG¡jñ^‘kéGàt’ª:
^–ÌzğA›;Í7º-ñK%:TÛÂ6öÅ@R7ß/of…Éy7 ë@0¶•Äï|áS–g\u/'@·€å#¹‘t®ØQ5hî„ä¬ŠÓ’ ¼RˆÒ°™Î.‚[ÁÙf7¬zO~ß‰~’ÔnÚ”ÄkzŸˆ÷t0&xqèX@/hRÀ_µn`d­_X°oBµä«ÓZ´Ş¢šœ tø(Êvß—‚_>@Šôë»J(t'kÇ—PõÄ6pPä×[Aƒuâ¼jÊ‚vF;5\| mÂ´Æ‰Ó‰MÜ)ñå@
¾? Plo !ë‰ót™
h“·G– s]×-–u_¡œñ]LçØûĞ¸?—Ùò#¸1w²m—ì8üõâê¡yYkğ6ÆøŞ·8ãºëxkÂàà– :=S;éÍAQˆ!éF¢ß ­¥fö@3t´}ÛCØ"öF4€;ŠöŠà“Ÿıu%ãv,Ê¾;NÎ›<xf;<HâH?àuR£Â— ¥Ğ7÷6;j~€# FxÖJÅ#iyu^Bğ
øÃ«ë;èz‡GÕ=–íÃnMhâg¡49|ª`Ÿ¢	˜E¿ÿ]!@£5kUä6ºı¹6"ìŞuÜó¤î‚ñ
Ø²*Œu›V€à0V+¨ÚX…ŠW €{¬Ìp€dôÄ$¬Ö2²mk‘6;ˆ@Ë•u'Ö°	şyš°ô;V®¯FıŒøâ…zŒã?Sè$Q/˜’M Ë
_Í¸öBQDuÃ2l A‰Î¨T•ÇŒùB¤Ô]¨%V˜È”À9OY=A¨¥ÈÀDÂÂÚ'C¤¢Ì\*†k“İ‰øş5cÌ­Ê37ø°ÇpĞT!BXÑµ\AŸGv"pœ#(™£‚BØQòb˜ ¹©_ <éP(iĞh± L/G_vk‹º.ö€£/u$öLxkÃà’	lÆ,@@Fš)9Ê¢ >ªQjvöd¾$y
DÎi·äk:NÒAt:JHP64ó€S É%(˜Íˆ£Mh›€…IWÑ-P­ót.0ÂqÙH¬Ú~ ½O,H¬PÅ‰€ ÿŸÓ5KÂ€SSa€e,z£AâÔIq=ÊÉ˜$Ù·Ò˜m@’ÙàEŞ«\ŒÁXP¯â~x5ˆÂÄœ§‰z rqÿKóRC?iÆ NKê÷!Ö·%şg;×
ëIZ*n[‰Hª/‰ X_–ÆŞ_V$—1HŒ¤D>4%a6&áW^$9Æ Ûw™5™Eìªqó/W?áo–Z’`ë6‹F9Ç”	Ñ]]0(ÿv? Ú ~‰~oj±ôÆkä·ê¬d‹v0é¢ºøÆh WªHIÊ`T¹Xë‰F/iJãVà$F]·)™(A~të!e M™à ªœuû†_2Yê_XCá~ÇZYd†-k²Ã¥ÌK²aÏ(½¦îdß¥(SÖï5IÑ™AcFó€®|8°‡ô­±*´}r@€xŸ™Û
jä¢[_Ãj`†Å<VQá½À¤à"…	.Â9XÿÆGÿ !€ÃœY@g9CfT<¸!¿(` ƒiıB}Ò—™ìDÑ _ÜP2QîX>»?ş÷µh€¡äÀr°2­(ôˆXuRU|Å„W!{VdB8a¯¬Á[Í/¨°ˆô²‡†Eß”$zÁ©®­©:Ş¶¡qëy¢'°„P“ú™D#5
ş
K&›Š_'	š§€®/ğŠ‘~³hkËwaFñşãÕƒ5¶‹[€±„(S‡ç^B¨LÁ‡o”à‘³xB–‚PŠy¹:½hdzÄf|G¶ƒøl
££6ø=â=ó¯Æ>K˜¯#$Pp-ep÷gM""ğf£D
¸È“… KÕxâÂÁÛ™à¸pšè±@ñ ‡ªøy™…fĞ>Zu8˜y3Œ<t`nİìF×v¬<Ã|¬ù&0k\²¦ˆx±üV(,é ¼‹^.Ò‚RçfSPR6øEÄbj°ä…pEu{îú…¶tŒúİ““¼šºşÉ)Úâğÿl¥¨èïØ:@{„û§ÿşm ²úÆ…ëBşœİlîˆ…é	êëé|½ıf‰€¼ëßö¯-Ü¶N%D'¸a¼ÿuÁúf”#O{ÉôEšë›Œ(I–GLûD’gfšÜ ([ ¿ş© Ğ@Ä„Ìµl” {FÖ:@\©GD‚µŞdØ¶zEÃHE&0>/¹T6oo¶š°6:u€ë„QVCrÂ¢‡Ü›/O‚ï¼°6v¸@!]c9ÇH@Œ>­õäÙ×EÜØ1àf;ä°A®ä0_P1ä¬!hì%îJXòıšk?VT>¡Œ[øèp?qæFûC¡
TæñVÆ§g®Ë³ãHVe‹¸fTäÁıØ¶¿‡ n»£€xE#x­ß#h	Ğ3Xk®¨mt5N_pE¤-=9ƒF,ã›§®_FHµxà´ˆa*"Åïğ¢ÇÇ§‹=°Á1Ã)ÃPÍf‹æ‚M`5‹Ã4‚ u½‹ Ä“XèŠ„bµĞ?›²Jë,¾ÉlkûÏöDJÏ,ê*#US	Q°)ÕûÆ¯÷é2ñ%([ºÁ¤ÿâîí.øÇë8‹APtpuR¯¡Å‰È§ÍÎFkÛdoŒGëOğ)So·ú‰Ï;{ä}Ã³ÀGÚä2X-0ò¶Poë Tj ±Ò‹“/ÔrQu	RhL›„rkdkQK(_+`_'Í¥éxT"8¶Agğ¾!ÜW…{p? ¿C:PŒ†ªÑvoË3Ck´`´4sÅ‘°´ıGv—²¯6Â53<YXRŒ•º>Wo@ƒ\r@	tA²<kB@f,«DË=2!¸{û]ğm?‹C2¹f™f÷ù˜`€w¹A‘b oÕ2_)0¾ Ïş0¦n ÙÆ©44«tÏÜağPK¿%)$\»ms8{6•ÀØÛØY’¹ÁUWºLÛ@µ]6(8•‹sVÖ^ƒàfÍõÏ­Td[<PˆYíaÿökÎñƒÁP¿ÿ˜NÓµ(ÄşøÁj(öØ#êÆ–PºÜ-v+8GK6à¦bwwdÛP6ÁàÄS0¡Û} İ=à!2k‰¥îH;8"Á’¶=÷=€Î.…›ãÇÊHŞ(­_Â©ØË¹#ë„ VüÄæºeluCNUL:Ì	Ï¿&ë¦\c Y–NLN®@–®LL†À®oşïÂFæ	˜3 İC€H¢áH$ÈÈZYFJ5dQpWÆ´°€h]k|Õ_„»`,FÓ´
~ÇªÌrx\½møñ6F°›1€İâAMË|ºÍ»dPÊÁ"øı/£8*!@d„ïûuÓµ9ûÚ¯Uu(2 õ½c	85¡)úĞk+¸'º«Å›ğ¶½Åº^œ	H|ºªbÙíÊ³bœ<ÀŠ`Ô)$6SƒlÉ`	hºÃ
à¹@å/©bÿCx*ò€µü Ìœ*ŠZ ı¥`R^îñÔÉ'êœu¨ b°°?pQ_d:Ã§¿^ìU¸[^´ähSë1fVr[X«#_Zâ³7SRÆ:_Ìåñ>¶y‹WnE¯\I¹(ùŞîKÎ7¸UN½dU‘Áav ææ`,¸\‚fT1Ix¾Õl²0/w‰f@¡˜ëSÑh?Õ’n¿Ã+5£”g+óH¿¬ŞÕFTÍc—ˆ/‚o²l™LILO¬‚'#~%¹€¾9¹P	Áâ©¥²%C#Ïhw£T]<Î±º Û9‰×Z3áÌ^,«*€ êb/NĞ†¡(àC!;/u#³¢Mjº.¡€äµƒgÅ²/Û@/aûüµ
à y2¡ƒD©)…{d¡w¡(g…/F‡0^VjòØHö×œ1~h0å<‚Q*ÒïEá‘v%»…XEÙ¤Œoh¬’cÁ!9‘š(’PéAq°”Ã_X7dì•ÁÛtm¯DĞ2š\td‘Ò|*z¨YJU!÷æALöU"+ÁÉ 'İ¯À¨Ø·Œc(À«ÆvƒI%zªt—İBâhŸà$ÑHó€	%Šƒ-,Ø«Œ"„oÌw¸‡¨5ÕV¦`æØUª¿íj’cÍ°ÚO';°j´¨!E0àIó¿×3Ôİ(2U;¾P¼§aoç¸´h#ß/oŸ¸ô}°(u}´fu_¸à´Äí5V4U¼ˆÂ†m´²DÈA²à7Ù•OŸx¸ÈªK~¼O·ÄoŸOŠš½é@ûŸ OX	ì À^Õ¾°9÷=¬)¢,o ‰øqè‡3G—‘%ÉŸQ˜BH‚x87µ#Ä^;\zhF5’Ãz¡:2ºCÒÜ `%[; P–êJ –Zê= ¯Ë\ i„š²ÀæÀgHè$vEK•îlr PŒàAEÈÇ/° .ò¥ ÀÃ2B«ÿxL¬PtDŠu¶ª~p¥ì€W_¢Õ)ïîş;º(Ğ@¢nFÆo£ŠF³¸ô±„^ÂÖ<,Y»<yÈo³ÁFàëk¡„Q?BË€;™@²A¯‰€Åµ-ók÷ØK÷qdl‹‹u½,´TştÈ3º€‰ĞÑøÅÿşRÁ	÷äƒÊˆt>f¬0ØŠŸ¶wâˆŠØe±ˆRèŠjï°1IW-)Uİ¨í¤°Qâá4º®!ÑŸ>ˆê½_üt:@É€ú­ñ°3f=<71Æg7Šş)É-€~È<„š¡I~¶d£"P…¡±ØÀ/UÒ‰ÉIÈ¡fè@Å}4R-Ş‰	Ø”-Ğ	6u¡UÁ Èçt¢„&Ø¹“	Ås-bfÜäÈ½C¢mD<^ğNÌ¢ `[ QQv°Ä6¡f	Ö\pƒ‘’İ¶\Ä=3iü ¹Š0ÎŸù°|‰ÿj¢¸–‘ïö÷r¬65Á†ë@‰Ï™ìÓJp¼ =şHÃvğ>ºş‰#±ê¢èÆÙB¶áˆ€ÂŸˆ@…uòëeÚ ¤ŠÖh5([bPÆHHP§óXÃ,¸ èöuˆ¹
¾nu~°£¡ÆàC´ä$N"£­MO-ÄÆÒ+˜2‰ˆŞ-!ZïTºw?nd·—+2PPGz±-/øvë
m£Ã¾ gMˆ­Š–ŠP NvöB—C5ˆ(ø5ÙÊ×I¨o…h@l]MU~‹Jàˆ†t„!h+/D
‚vÒ×øÅVÊ JÔÿÙÜ×ÚCuíÍıŠˆĞNLpÀêTûÙŞĞ¢ v
 ¢vwwvP9¡wMENUtAºÏñPvuMKâgth¤ŒÎRÂ„¤ÇtaÃ]FĞ’¤c%Ú€İÕvo%h‡!VØûà6yk£ä¿	4Lr[±2´x±9¹2ëzõL9¥Ìñ‰<§¶É’/oqnî¿¦¤A£4—]TäÎõ sÜzå8ÉWWµ4È°¦º¥¸ À1‚
€èA‹•ô†Œ$	ÁaJ'3ë¾}|Gk¼¿òƒú†Â†øÁû‚ÜVá>—¾‡;@°Åòß‰ñÎJ8¶âô¥$ JğÑLÀÖ”¿b-ŠcÍ„àu-Î8¥Ù­B<Á•u^/s	’% 9R M¥Ë2ÄÊ\®l¦x§›ÀT„{²°	hæ˜Œ¬Â€sCB.TÕ,Q,Qˆ¦{Ë~{ƒVÅ©€Ë=û¹
Yê“€LQp–8ÈIv÷vÛj}ÅÛ6”bNë3üü²Rjhªëu.mÈ6,H±—Úf!ds¡ëwü:ÿ‚&¸À/¨ÇëBD¡OèCPÒ·¥vA)!yœÙ¥€&Œ¶Vİ„À,x‹<!9|¦‘ô³°q/²_°Š±]_XZ á…œ"¦.¦×ŠÈæ.¦t}ZÈ†yØ2¦lGÃ-TC4\XµÌ ¶k$ThëÅ/r€uËş,j9Kıº	´„)œwZ•ÌRÂ–­4Ú L.›ÇÂ‰ñZóuÀ^ù8±‰z¥AÍc  ¸Éğ¶¼ÉMË“W%t,yV°k]èa¦«@:7?í•
v(ºV½€ã‹§ĞÆ(àş¼€#H'¦úI\CÒÆ†tæ°C&'ŒŞFÒ`Cxÿ Ãh7ÿÆ@¯(–l¿‚@¦œ·½„Ã'%vZè€ £å¿ 8Dv²â=Ş4‹t…õv;ts=©Š@4Ğ	VXŒ(G¾îÖn#x‹7Û¶r«#ë¹ |«ke›‹÷¦àFqeô§ô0ûÙ+ä÷¦t%/;	Ç™§–h<$Lan o„<C&°ç†‘y$o›’vCËWÖu$Æ;œQQI’òaC% GcÈ^ pPPµĞÎÄÙVæ¦B…lŒ½ 7{¿F`İa÷t$Õ¬–²l›1É‰úæJ5÷Óú¤f‘ ƒUü.Nµï§lÒ©CñHÿ4—EúÆºs0ı‹
B9úÑ.,çÜ	WĞ+(Éxú¿ Ân€ Ÿ¨… 
ëfK¡$¢[dÆ2%ÃHE¦cb
»ä¨>A€ÆŒv£‡(Z+»Ëxö\eJ¨RØ’[@6@„İrv€{y#‡Ãı4`ë£-ùÔhat(˜(I 	 '(£¨†]$ˆ&–Ùp%/¨Ù¨¦Ö …ä5¤°ä5ÄóY­šê So¨“\õ!cğïƒÈ@28Baíòôht0"n»:ı¬‹ Yb±Ğ;¿C‰¶ˆ’A…j87«C¦ş º’ -XÑÉºÃ…‰)LlC¶Yš	HğÙˆŸß¼¸Í£—ÍÄ®´Ğv6²ÈÊÜªXY|…‹’Ùt$MÉğë‹’>°)j£/}²>Ñ€ld†¢øP=G§|ş60ŸİÜLhÈœl@È¼áWÀbÃ¯WÕ[Æz~ÈêÊbÎz~ÈqäË‚šÂPµ`RRÈ	PP0…P¼e}ËşJôY[PÈ(su^ì.fQ<nüMôÉ¸îÂYÑ£}ÇÈs|åIÙnÛ‘"6”¢#DlÎªL!|UÂ^ø¹åÆ,¿ü˜Õ‚¸	 ç›(øÁhî„®6†«º‘ V½^š©8©â'©,:ì›+¢%í] S1¬"–ÑÇ0€¥^Æ©‚ÒµòÖo¾)¨uldÛ(;~#ó@ ¤€<=©if·!©’²DP‹&1„l²Q={Q¢äûjp8N¨H}Í  şqo2D4"’8]¬àÌÜ_óH C Ÿv“(HæO0êBÅx<J´êµØ©©RëG
v¬©$ëS^u›µ!L“!—ŞJpî!öE°$tPŠŞ@¬L¡GTH!Å@à£j>t)?( /ÏËÖ¾ùÏG$(xH³ÿ«Şşm[µëƒÃ‹;u»0'G6„ø=bC.ær;$OaSSªÈÌ¢.ß{gr34£g=ªÎÉÉJ@0¼¢<ck[1ÈR4Ûò–lyn¯€s4Xuuf©ƒº¨,C&r³ØXbtTëÃß°'ªë,¦LcH`UËƒøµÛÉ˜À Ô„€™@‚Ş4¡û2ŸK.#¤½ª —xPÈö¡”Ù£Íœ”Üßw‚Ûı‹˜ÒnŠ„ƒÅZ‰}xœ¹Ü}§z›‹JJ¶A‰Jè	D,]jûQV
e)øÓAòY8\uX½Ú‰j»®„±Yüá>¹KØ¸\DÉs]‘}#…Ò{%İ…Y`ò#èüˆ….ğ¾í	é½‰)ø 3›!ìçf@)ä:$~ç³Ù(àªàûØåë[yŞ"õ }º­÷u	€½‚sX©'›·ßÑcB€âä _t¾B‰¶(µ-1Gè|\´áÈ«ˆCGMÚì'¸B>'SĞ‡â”ä¬£˜á/«ôÀ¨kÙo”æ‰,}ö1ó—l–Ş|ÿ¤7  bøíİŸ…Â
Ş†ëà
uáëÙ‚G;ü#t	ëZ@ı4ã„$<í{#Û}K:ë
]«‡Ü*	vdj=(@Ş;P£Ù"öÒÁvîÔ	X‰ßİ•²pË¢ÿ¿E«22ë˜Ğ/1WCèa)çn¦\t#s3!ÏûZ«ääÚ3	ß/–*öñîb†‚]¸@õß£¸ P÷!ä»\wTœĞß1€?¶=ş½ÜãìÈ&£ƒ“«t9@”â?á9Â˜²ë² <ßöˆÂˆC1^«ìa÷=­ç
St[1»'[x«RÁˆÄc…ŸİÆë5;äëöá#¸½‰Ú+•ˆúÇËxİ±ñƒŠ?¸%Q|*ÜQëëBE2ˆ†Î‘qŒâ»ôß‹{Vßµ=QëWà1@G{à=µ6Ô7!¬ç*0±Ú;åÙhqbÙ¬y™Ò™~© 9Cuy5*È¹ë+f_DÀì×ƒğªHV*q:(}ià‘ m˜üš«bÚ.tE¼µg'î ©‰S ÎöÿĞë„ú†mcl3¦¸ˆw7;ä£ˆS‰5Œ®ˆRe¸ïòôÊíˆ¶Û‹=,Âî%K¼ˆà†ƒÜL©=©®àıñ=€RÕ0TÃ­2-*e¥hV.91;ûn·Ëät™ó?_ÇGŸ¡%J¬¸kW„b ¦`òËÈWShv¬Pt#ê‰ùÔê‘Ş‘º9•&?®}FP	ääu°ÀîÂÒë¿ÇLGjÜ‹UTØ±ÙÂ<uğ˜’
^²ØSßÈÌ,ŒnWw˜ Ó%LAåò½8;@í‹M„í…Hr#E°T°5‹w
]9múád˜9„²hÂU uB"H¡^,uØÂ£œ=Ízx3¤SºPïªŠÆœNRĞ{ÑfçST¬O¿ qÃ^¢å%Lø¬ …(ÿ4-*wS[A6‡	­@8wMHh
}ëß‹å‰€½:ù‰€æHÿ6¨"ß‹•‹n—í	QRıøNWWZháY3Ú$ˆÀ¾$U­aTâ€‰àEÆÛŞpác}?[€}ÃÕ4c·ÄëRÆ–œPÛS[aÙJC}€5È“@®W-ìU­!¬C¾`UƒKn@º"CVs¸+A;‰ÏˆPÒ³HA‡DÀ»+ŠíSçä9ƒ„ÇÛˆx]¸Ğ´µ´¼şŠ€ùMt…¯ğ{Qj:uzÆ¾Ñ‹IUëª°…¨K*bªtÁV©g­QK
Qƒî}Ö}}¹!Eu½ÔQ5VÒ„ÁñüÚğ	Ñ ã³< T% šQ€^yˆ/8Ñ Û‘–åµÇØ#ñ^•ôş’å‚‹’ûïŒ‰È÷æİÅº‚6%^ß"öèƒwÿ9y>œµÎ9ÄÒéäJnRU€Rì
¹9PMæQ)ğ…?ŠE”<[<Z<…t÷B‹€”Ÿ8˜‰µ½†Ÿ…n$~:08éÁğ
Då9`F…V,B„Ã;lá¡•å‰QÁ
Yÿ0!ÏÑ¤B·U¬½öäoUgÆFYL"¾PÇ~ É è†rH*bG„|à>(=ÖB¸*j'uŒjÕxŸ-vjXl2<‚€÷vÄXhEVGĞ,[a»‚,ˆJIñ
‘r1Á-àQÍ\®–¨×ÈÈ†§$ØÍuWjÙá°oŒÜZx´bWV™£!ñ‰nğ
àĞ!øÜ9ÎÔ³½m,€¬>Ñ²2‹<,b‘Gæ–RVDMùB¨Ca?’"¢=„¢ÿj¡•FÁR´'KÂA}Qx¾(ÃÙÑÑ,¢ËŠ)7™=çB­fÈ˜‹ŒVPGƒH‚@çäLÿF­@kJŠd9¿b3ªáS>{#[¥i$Hæ`³E±VMxQîÏÉ<N"È!„eÊ¸®p"³@Qh7d(9=`MèSŒ*œÄ®¹EJ¿'Ë®) EØÑ„!(e€³pf?è):
Úù¸ ¸Í‚3õáÄDÏ 7+jqChŠB/|T\Clÿ?µzC¶&|âU¯aÕì`~^jzĞ L¹²(Pn¼ÑN¥€&¯êÑÇâêZtzv¹-ŞÜ^N¯H?6*Èx3ùUœ'((ù#âzêi‰¶¦÷ëz;JÇHü€çµ¿s8Fütnˆ•†m4*Š<qÉéLô´İ´è˜A Wm <İ:„å€¯&Š",“ E©H~{z#’QÃÿªÅYhQu@‚`éàĞ±F‘Ìt"Ğ&ˆ•¥•£¯îäUÛÌ¯[ùmÔéD¶Öä¬*ĞN'â7i_P90MùêŠèa˜‹ĞÕ'ªw¢Ú*İ×ÆêÇƒ¿9m~©JÈƒğˆOAXû¹‰ğ¡l‰GuD„€XcîX/º»Åqê@~€¿uº°ä9g'y-29ç@<Q´GæHšô°è£°®âDoX™Ü /#h”yOX6[ u<ˆ2øVˆÓ‰Î„¸ü	€.ò Ş hN°Ñ@ğ~*vúÄí-µtÂ²òÃbSîçæs°Ñ›´¡Kµmİ¢—.ÊÛ¢oKoàuä‰Ø¡Šî²µğ	Èú QÀ+tÍ
Zªü¼°ã¿¿-ÒÔ Äëc‹;UÄuu©X‰èQnu`{³®°;·Â)Øi9Æ¢Şu2‰»ÔhÕ~"SS2o°1"GR<è®ñŞşÇHC;]Ü|˜Ü@£µD”€–(ƒÀ%„$}w"‡†àÊË-±Í/r`áŠ£´¨Ãˆ»€ÉRÉÈX±d"£SA<›‹L6A$3„!ğdw‚$W•ÔOj¶?%¼!ÆtC *tlMPB~¢•äÑF±#R.Buj$ãé1ÁHÙ †lwH OqH(nït[ğ‘w1öÆNCŠ.]_SÇ5*´ÇôUŠà#h6ÁRU‰aÅ[®V×Äï›t$Ë‰¬R!#Z"eÁe"X¥ÆvPàw³ÌP+=Ê* }»±t
—_Oët¿]Ó	MŠ•üƒÂÒ;r	vã°Sì5ï¬ìbHA,(ğb/Û4.l¶ÄàÉ4í1F@ÎV³®ÆÂ&°'Y’†½ª½|Ãx`^ØÃ]¹gÕ®€GïB¨!ÖhĞĞ>4ìĞ¤z$Y[ ek¦ûÅ"2ÇíX•6Ôb[Fğ	/MUÂªß&éB”ñÑ‰Ùë8]2Òçò“Ğ0ôô!k@:ˆÇ:kpl8Ó9Ñ€W 	6' .Œ8üd[‘<)> n™›èT°2œl&¼RÍ@#Y°;²Î™€J€šı(™Â‚c”Måö°.å…$é$ôHÀ†tô)²%g±`©Dµ€Œ½MgµÑPòl8VV'X:HVòÉ58ÑhjE•<WŞd•'÷D‹kY@¶JĞ6JÍZÙ7V8…ĞzA#î›óbÙ]Š½}+!éj¹'Á#â"UõPŞ =ÂÈ²ÏB	^2õ pWû¨€)¾í!XÉâ·œu¾DÔ„üşƒè0‰oæg%9	”³2¶…C	´0[üR`ÎŠ
‰øÂ8¤¨·ÆHGt	-üj}ïëF!•&uÛ€oêIò¾ÏŸ ÉwçH~Š„5:O7{ÀiRGGF÷•R]*^ŠØ‚³ÅXŠÅ¶Q9a@°l9zÅ(·ÈWµpr¶»ò†b‡.ÿ3Ñ«ÚŒ¸ó³<1ãVtXP;öJMpY¬‰
‡ÜH@ÕîrP¹Dî  ĞNiXü	ûå¿l{¡=ğÿ#0ÔîÿA!¸v@8îhI¡#]+&æÈµS­ˆ”\¢1ÛMh3ŠÀü–ÎU@nVÒ=5ÉRA÷äÆ$ ƒPîFSb@Æˆ/uQåVToTLm³<}ÆWª54gumUò§ZŸƒ ‚I*"—ÇVP’gŒÉu³ÑHVì‘ƒÕR‹³û¿}q%gDsÀÊÖV2BP5E¶€ğ!^h©HuL†€?äMŒ‹¯Q`ÓŒúú…¦â-#Ş‡‹x{O¨Û÷7I9ÈuÒ‹KKä¼îcP7Œ	¬÷ úkµCò46"B?÷âu„Rá[ñµ \Qò+û¿RWX#ŠOûÙ÷a)Š…\KZe(˜Š}*vÿµ}®B5k‘ºÒ9Å~|ŠÁö”•Qõş+( ~M€½ğƒª½lá”Ñ±˜Å?9A)è	6àŞ§xBi€6@~Á†é¹!Ëº(ğwSÑ‡…=ƒ“*=ÖUÄó#=ms·¶¾€=…mÁº‚ŒĞa¼m½@úïƒúD1t,¼¼¼¼t't"ttW Û·
:Ï3Û¡T×—ëóİĞîC>uE<ºê¦±‰¢¶u[´\€E–Út{-‚:şÜx¨n­Š@L¸ÇZwPáëÛ”‰¿Y‚±¨@¿ÓˆÈÀè›­v8"¡0«óºœ¯ÏçX{¬"ME‹€÷fûDÿ;xPwƒQ"øXSÓº,ÆTÀ¿ˆº)U]º7`n¿Æ	tèHÆS´1Ëò´V”d¸îâ‹íĞu08Àê"ºîÉ”B©PBU7Iè´†Ç\DÏ,Uèä³Œö-|{©ß1Ò÷u×Œèlliu9Z‹%~Ã#œï ˆGˆWBÍÅS˜1²üµlÍºß±*—¸Áã©rDt|å¶52JMB5XGÄu»ì É±^FµìPDU-Ã’Õtğ©µˆ] <„bÖµ%ã À@îÀd…’ËÓÇ3ÂÀ² Ã;Î{7æ¦}	Ì
\²Àõ½_W-z„ëf!°Ë€ºøµŠWÀX	Lv¶åB&»ƒÙõµS V±/ŞCQ?õ}¼†™p¤œ}f.Á•E¶ [‰ÓA@‚0ğ[|¢)Îê@µŒVåm Z Åíë+{Oµ„<iGÇÓ2ğğ)øP”/ü RQÑ)'˜¯MèÓ$€±^şA—0ÊuÙ(¸Ö9FÕÍ†ë%VµèäH,dVš¶X	
bÚşÍ¢³¨¿—f5½ëC4š)ş#·P+÷X²Ìº³8‰)¢Óûí…éJ’[,¹¶%º½oĞÜ`%5ıığ-<÷v h¨3&ó³}³ı›u(øH<w
õš–Ù‰9öÙE ÂâƒÉ:6şS3QV >ámöÄôüÌRP 3­À}ØØ#Æöj°W´¤èhñ¶!² xHºüëáù[ø²ëB	¿¹¨–U…€$¿øWh·bF$![Oİ€¤*è©Š%CãG ÑEKš£´PÙ4„ˆ`o·½Ö-ãDŞ"£C×£À€€zğëF¬$’K²èè@Ï{À*Íèˆ´ ¡¼ÖA¯ø*FP¬HÄ¯€¡;·d;T\Hk‹·UìÀViS¼g7"Y‹İjrZä+û’YÈjk)Ìja6Z¯Ğjã:ØAÄÀ>u-ç)eÙ>¢å#ÈÖªĞìÔğT”Û“²éĞ3U´‡ŒFèEÔ~(¾é  Y[ÎøƒÛÿHµ‰\áöJ ¡ë‚uä¬ˆ‘mÔo¸ê¨xÀ;£ÉaQíHÜvgùdLj™SPhSNE,†GÙ'Š&!Ú‹8Ğ€1x æQÉ&D¨u¸dp·5ğ¿:T, ¬	;@§S” `z/¸íêEØäÇ	~a4+2úøV´’WZ¦ÌD(Bº!UİÛê#’¨ŞÈU¨S4‡Æ€lÁ¼¼ÚB\¦ó8R£~8W©<tZ*~áÔ@tÉ˜ù9×à… à,—vÌ4ØĞN˜*Jz5ÇÀÀu.¢·DSMc™@×Ô}C5‰¥q÷ –°|Sg»ì‡éˆÀääÂäé’&ËÁ¡Œ^’jÄ"§¤‚„•(<Á‡5•y»@ÇD,¥ôT¸ÛœlŒ€·íäœÃ (D<x¦ŠB°°ÈÍÎr¬B UGŒP$À½I«ªĞ–€|
´¨Bp<tsğF&ÜÁ
t’ë.}vC>Æz³ØöPQÈ/ÒF'øä‹É?¸=ìkZµG,ë¯‚nWCzWğ^Póóé’‚1.à3tûõRA{MÀv¾U
@,ù„™»– ô2f\vÊQ&rM?à­]Aa	& BE«ê3UúEìP
´ˆúá?UaÛRû	R%ÀÅ	ÿ‚+~Æ¶I¸ÌE.Rd@&é,¬(SíŠ¨)fªÆEõ*ëƒRbÕÈãõ‰ú­z" —T.ŠÅÀ­Aû»(ˆM§ŠM—86ÿo Û§
ÁPôHë@‹ÅK5¸¼šÇøì…ï½Ã~¯õR-ã’ˆ 9Y€	âù!hëA!VàŸìi{€è ä¿‹g(\÷Ø‹½(:RŸQx€,Ì€´”É…Ax¸W¥Š€4¬3‚ï´:'‰çTŸÚ§‰à‡JûjÀßRr½I	D?(j¯Ø~ë?ÍÕ¬U˜ yI/ª7’¥ÎØésS‹F€ªÔŠyz2 êA¸zöO@KBÚët‹„İóŒ5×=”İäCRXÖA]AàµàÃËßÍµ‹½ÔÿÁÿşæU6y ¶À‹Ä(@Ä¿ÈÀÆ×ÈBá¶	.	V7§·Iı;ó|„”<Èd(°¸eÆõ¥Ø6Ó¼ç(•?€I°ÉÇ®F;@Æ¸hĞPĞW ÿS¾%éÍ[¸hÓkCÑè¹4ıÑ>±»èõ/»ÿßÂó¤
A=?B wí=çv,A°ôb Œ¿q)¢‹!÷™ØAD[5/õÜpwMëSz¹ºÛû“» Êš;¹C0ë:ñ¶ÛŠ9ƒròQRln0æ‹[Ö}'¹¯3İìî¿‰ñ¾4zö±­6şë'G€?¶úbÈ4Šˆ5ÛUÄ5*W1‰³†,-JÒ0U°Ÿ6h0ö:l'D>¹Z„ˆ5à,´§¡DLÛ‰
Âê¦hş‰Ä¢„<ÕbxüœWº¨/Y·¤\“pz.€ôW—$å&7]Q&P`¶@ç”yØ ıu$CÃ–˜Aø è¡ ¯sf†<ƒ¹Á!©î6C"#zÂÈsX»úz	( €W`×¶½DŸ~;,EV4ô0äğ³¹å¶Ô7¹.	Ù6ºM2 %<h šå¯6tZ(>êN~éŞ÷¹L 5}£C0Áû%JŠG4½Ëö~H‰K$¹¢Ù{¡QÀ£S¢j	Q‘ğnÉ…A¢kBPŒ$‚ŸXÁ~NEõş¿¡|f‹PˆĞˆTğf»çˆÑU<şuQtƒ/Í<v&›ë€Ù­h"ûwP’¨zq!¬€ŠÑÍÃişö¶‡ÌÙk›9Ú}Aºzs#
œš[¹·[šK‹¹†	¹­ ·QN‚’0Ú
ŸQµ‰hÇ)^ıæÎÛeá·@°,¸%&yé(Åv9ÆsŠòk(„«şğ”eëjş©p›®s¡*ÂæÍífÄM†Bb'lŞY)Ú€E($Tå úÙ‡~€›ß c	‰ÚˆÌˆ5xF&kØßšPK¢Ğƒşv±/Tÿ
B‰µÈnöB*÷(xbÇˆCˆWDßb<\·B|¨Şn·JÈ‰)€z…+
Ñ‹B¨M9x/D@éiÄp@àŠ^ÅùJA bÃ…ë‰KÛzk-xéƒÀÁáıB­mtı	¥‹
#«mo è¯–È;vƒĞÖX
†ECæršÏ5·BÃ;Âi şöD6àÂç,ÁlLF»w-æ]y;ÚØ¿´@¬çê[¢+“õã_¶í‹Aú¨ÔfzUª*j·/]}ŠBöÂ[aKÕÌ`ø¡QÔQW »sáµæ	AG€PÍ·Ù 	„¹cÛ£/É;Gu‘¨› kR¨™k0(	L¦j€øö†°¸w’&Åêº“YQ 
'àƒF.(˜Ş¬ØµN»¹T»[O¬ İvWœ/€C‹½@€x0“´†­9«º”ûQ’|9ĞÕà¨Ù£‘#Tœh«–Ç†´ »Ç~C@¶ÒÆXÁ¨j&)ôx²˜BŒ¼›GŠy¼·’cÃ1f@¼¨ŠôÙ·ë¤­JUÊ8_…¥CÄPÏP´y}¶BcØ(uEû¢…¨"‡ªß“€xF<–+X m¼ãS©ˆ¦ÑçİQê¡f‚<ÿEÀC©`áï÷u£ƒmÄ€ÄĞšÄM1¡#{ëŠ•8åÙvuòÖbnRŒgbld€}Eë\ŒV £ ûò«-²¼¾I½g;+š„»ÿì± ØèD€ÿGğ[AS‰¼ŒıÂZ(ÜeSWr#_Àƒ@Ô.™U„‰05"hA
Ùtˆ~…d	oÁv‹}€;KŒí!ÂAâØß;P|ë‹!Ö£Â5À¡¹¬ø €ùØ˜¶B)ôåÉC+¸CCø¢¾NÜŸB¸L§¸á'\BU…-"æ=	x ®}„­½°K‚ø­qpQ6Ä`„R¾!pX€¦Ë* û»¡›h(¾R¸)ğPM=3¾†‰ãÅÃ–€
	AëDü pG²‹ Qlx ú¿ø4)ÇR‘úK«ß· €|5Øë¢Ûs 6¾¿;+|j_ä¨± 6–uâ¥†Ìğ”ªê
;Úİ¢¸BvXà¾ü|
1~ÂøÑŠhXé eKådĞ¿>EĞ†©
7òpÕ>c’€t¿€ÎòRå™Ä‰ø,ÙJ¥5g¨eyÌuÈm>$¶Š9GÇ~ÆVD#6"‡€¢Í—²!èŞé®µÿµ¢F+.§-Hğ&·Î’¼ tV‹ªJÄØB‘“º_]PâÈ\¶=ˆÍN‹¿QjLAp	ÀVg¿›âdBº·zZL¾¾€‡è™ÚĞW„Ğ3–„ÿ±çVò  ½¾,hÙMh!À½[áExP¹ £Ã–<,`J6±*ØŸULçZPÀI!›–¤ pµ<U"ÁZ9ˆb-à°5vØ@Äáºuš[‘' u0óÿElÑTcò!P;, ƒÁx*IAA-™§›õ>¦‘/vÆÜ‹&ğğÑ2Å‹{ ô9Ã±ÄÍ—Ü+˜˜·2±Ì¼¹N¢—uÓ8V©$ŸOâªëu}ÕÀ9€,ËÁJ­ñMÈ8£,¿!äÈ/$…~€ˆ,ÔÌ0¹9ßSäÁE[dú#h,üÇşÄº@´øsõÊ¸¡hNf‰—3ë«‘ä©¥äšÀ(ì*õ©™ @¢é‰Áğ µ,ëééë‰A>“+Á»Ì'DD[áÙi´Q*È-Gm¢`ÁzMôê
éN —¢jA“Á—4—æ–ÁœÁ V!+¨ÁLè ´ÀDjvàÔÍöø<ÇMÛK€6‡ıF®wƒãâë–u…‹¦^çLL,G(òÖ!!áÜ°€‹…ˆ`Àş@k±eÕ}Uï9Â£É5êögq.%Ñö¨øÌö˜`’‘4Â¡ v¡Ä.eD‘ë
H	p‰5P×€›ù@@£Lİui
¼ï,Á+¾]¾Š¬à,8OKktæ@&d^C ³5
b4¬,‡’{¿f£@e5Z›µø60uL?%œ¿Ğ
jŸö÷·@Óø"à­§%ïHÜw,’}³ÎlÆb¡^«MvãÑ	yC¾¼×†	8Á¸™°F½ ‹rŠjx ×DVèW‹¹Ê8ÇÖ·c’).x4ÏÌç€»!C½% î€VbhÉ…ñÎ(\àŸ	ƒ;Ou;SVjÀŠàù·Åeu9àuÏàénµU=¢ën³Æ÷¨¾	¤òXE¼ÿz’Ù"˜hißL¸HDh¡Âù«è0Ë1Û
îí¶¡¿)z’{“§ë„!4¤—
¥ë‰× q
$—l…wåÿ4…œ™b×‡£¶w~ËÁæa‰J	åëXvK>4…[Ã~FaO5y"ÏA „ö<t%_tÉD'r}Ã,<(ÀıƒÖ¨t/º›"½ñŞ]º¬lºÈÃ p#v»JìÙÃ>´ä„P‰ËõÃ~˜®‹Üb¥yqˆï4°SÚ`Bˆá£<ÂQ8·“ëˆİ”ë 9Àõ‰ÄA^H1=`0€„@HR,ùÃ&Ä
ªIÉ;åÍö#Eg	‰«Íï–7Ë›”şÜº˜˜vT2œ(UoğáÒÃ‡d%M ÒBQ¢l‹''[Ã8›3L ßj¶7ÁÈ‰	XBwPuÔ¡ı•¾ ŒŸè1‹=”Tïù˜5s™ÿ×Ø‚­}3‰ÓÁË´¾¹ø™y‚Z÷Ó!Ënû—Š!ş	ó]ğ)ì´5h#Î@ƒo/5lÎIu6ë‰ùğ}kî[0Uìë´
uìøí/ŸTòÁÊŒ¡ëÙn ğ1Ú1ú@l¥ Æ"ìkom»@ÊFó:E(uÈY7¾ùddu<ñÁÉÜ¼‚ß¾!Ù	Ñ#M"ß!×	ù\×Zë‡M‹"Au¨æ(ÚB<Tµ-†:µ7ÙZkBN^¿½Û\ûŞ`ğáÖÁbÊpä1Ë1ÓÀİŞóÖ6ÁÎJ³Ó6¶¶ĞJ8Ã8]P#Ï‡À=<5'‰B»Áè"lÕ¨
z|ÍEPÛg¯8× ZãÿÁë	Ù‰bS±Ô[‡“Éˆó»P1ş‰ØĞsÿ	ß&êıë%‚9pK•á&cÿšøßö†ûW\À¹)Ñ9Ë}Ğ5l	3÷ dÕÓX1Tí÷Ûˆt» Æ€€@ù¨³Bï8
øHÁ,¶)skôspáô½¹‚ßĞó«oØ°v¹8,¸8)c×hª€rÌ%€…öÊ…ÅÛv7p£”Z[‘éN¢ëgv‰ĞQºĞ˜X¡MÅ$’Û¿Èˆ·BQ~|ÇÔí]ˆ¸0Æ*-‹0ºÅÆ‚İğ2ğF+–• İ3† |$ÅHD,‰rJ@”#àµøø–# ÒüˆCS!\È€ü
2FÀûu»Æ„M‘ø×,…tÑŸA»Z¯PÓï¿Fº‡5‘ä³YXÿÏQÀÇ(¶X®ÅE;sÛH8N,ÈXZæ¶äH8­È(;º@P¿
+Éh|ŸÜÈYÏrû-å«&ÒRGÉA*Ov÷s{hgëP*ÿ°É¢[áuÉË{5KQ4˜Şáô!¨eÃ’ÏSSöÈ –µŠ*»öNºF1±$"Ô'İ³Ï&¸„3!|*(»5',‰¸‘!7#TH0I4 x&ää¤såU0.2[l3©:4,@&?e4?Hòœ6«V¾É±$ˆ%½¢•Jv[1ğŞºÜ¶ÔJMØRÜ9Èõ¶Ñt„É¸9ĞU¥Š·õ­€;ÓÀ‹DdHS]Ü×ÉˆäÑïh“u¸yƒ}¸¥‘fk!¼P‚¢E¹+Ú™o»ÛúD¡Ô¾¯HPuIvLÛÉ ƒ.ÃÇŠØÄ_¯.•bdû0€€±’k,ÔBëT–mx-º
N6h7ğ[¯¿0ë9QÿàPWTÕP'à¼×®ƒú½ãÆ;rsWğ. !ı@f‰4Xo¤zBK„¯]Ëœ‰Ay½Ä_8ˆúÜ)Q#¶ãÊª;ÌÌÕMÔ+Xê—ªzÿƒçGÏ—jƒOTIƒááÁÓ+EÖÖ°@ÏECĞ¯2Uk«¢Ôv³B°Nu§&µ\h¿a‚ĞĞ€š “|¡~*ÌhÊ0ó…®¢+ 3ëpPh"Èä”ä}Aı t	"¡Y /i<a@>¸B2+Ê¢íä$Nz9l[ş;„~.0"433U›’ W´]ªØ8NFÔÈ5xF„jB ä*ùÇ,ccm£Í(6‹Áè–3ÛâàĞº–-lKV)0¡ÕwĞ¾ëŸBô"ÇøÄ"hfñ&Â!¦NìcX~*QP‹±—f‚uMÈ÷ë·tÿ5ëûØa…–õ‹&‰F‹³«¸5|W
½w uWöc²ğ{´í Ræ·t'k›bEI"h¨ú‘ùnf˜à¾äh¹P“%c²lÉÆ_XYØAˆÎz7Ÿ	×ì¬ªÈ§&;ÛKŒ,RdÜP;ä0v¢·Ò8Ô4I#xÇ~)ş')L°Óf:BMOQdÂ"D‹*…KĞíf)æf~uj0ÉØI¶
$Ú‰Á&
£nDª@EÜâK*›Şû÷fÒq¹lMâKd¸íwÛ6à$ ƒ‹B+B
ø*WõÇ(«¸5Xšu'åt(@&nra&i`Ã¯êæ‰v¾\”¹Ól)ó¥ÙKCÛ«ĞÈ»ãïoIÿz &¨£_;U · e.ø»Óº<C=8ÛRmı0ˆYc›pªÔtr,P5½((Më4·íİZ¹Ì…fyÑ9Îudÿö„VOuf°Ô}æ0u`SjÙ .àÔ.uCpCq{ĞE‰¶ÀQD)d@Q!KXèzDšìÆ§£h®ıA=š†zW£:;†G[÷ÙÉ¨'_ZSPGZYïTèq£c½¿8À#RSËĞå%€IÊ'QëjU’I¶A(Øäd,ùÒaÊù§¢ÒyCÔ è S­"’À|^¦ü%Ûªhš–IKëş*wHÿ$,cP­Í-@}-W&¶pQç°Ï´¯ÂÄšA+ÈğÊt‡FÉ™&·…¦RœšË$“GÆùë3Q#â‘VôøA1hb~äôñ“€œ[@1¸r¼ba„W6ÎVkµ]NxƒÊ5ˆuJ&Wxg"˜Q %Ş¥MGYtì¾	œˆJËfÀ/şt¯Øã²ª†ƒT ¢ÔÛl]@,sGhLÁ+ÔæQëyĞU|ZR¿"-ÌÁ<4­t\ áSÍUÀ’	Ë<°Av˜Æ*WW–ˆH²’.öG©Ë¼„Š÷€\?•Ë– &xü/¼ÏŞtîÂ¿¿2›„ €>/Æ@K¨
[Ê!¨…ø•#İ¢—àDéUĞ)YbÒR_2V%öûfÉÆB/^yZ „4Â}¥oÙdXrÕE–¶aTBX€V¦¡_XV.,¨]É¹Å`éC.¨cŸìÎË¸Ô˜	+&ŒTÄÃ05øæ úDIôË¢)W¦%Ì -ò¢èçPäŸä„m±pY[µ4XZÀINÈh¦^_¸ÌÑ½‹Óc&[é‰ûÊˆ—‘6pÚ«&·)	Ì©•'>~1¡¤]äÇÙË¾]!È/Ì8"“*Æ®V=ÌñÙ(	Å¦†PO÷¡»Ct-L/b	Q5Å×|š¦T0|W5ô‚6Ò1Êó•%ìŞ,ÉsnxÌC`c$«°¤e)Â˜Ã—™Nİ|BtHtŒ«KÔO09ë!ÊCºÛıì{÷¸­Bë
º(¹N"ôë&a=ß“wº.&Èã6"Ä,ƒPl~/G…ÿê.|5Ö°IˆcÓ²kÿš»DtPG0Gëj°KûEµ0WÙ‘ÍHò|*£¹ß:Áw¹" _<,$O/3ºù
C¾8890V1ä9I Àç{¹Z–¼¡¼/gc½ágÍN~D ãvÍLrOÒ†Í£Íû¾7$c¡1;…;¼0qxt§JŸú‚ÛpŸB1£	Ãxñ„›âfäwëú«Í@x÷‡xf-àDy÷ëQ&y&g6±4¼âİÃ&0st+Euë~Û—Rx÷f£,ëI‰„S4oM°^ïÈ0¸Ægœ™2Äh[Şà!àŠ"Y^Íªx`?K@° vdeÍwÁäçéÍ÷Wº÷øxVhÎ3Tõhª¹¡Cøí±¶.?¨€6íx	ÚcøòÑRÛàª$UÖe	ˆc?6¡E¨+(˜ƒ=ÆT¹*¡wBAÜ¾¢VIu¶ üuMŸWÖÔVQ±%ë àÔ)†x,—="Nœ$ü–Ü>6;tW˜4k?T´"æC; «¢›C ,@†PÀÔj,CÑÌC ’ÉOR;û‚,OWW;[;O%éQµ([›M¶c*¶(f¶—PPWW¡GÉd†¤NV
K:*8<S¾(ˆ˜SAÎÚ“t0‹=bÿyv.|Ùl›Lş5.!Â/D²f÷Ç ÛË’K¡ÿñ6id¡UáÜãËr iF¸0 .€œ°-z2.¬ *¸€&¨¤Îth‚(	(ÉÎDÀ&T$Â´²!?C·Î&¸â0;`J112¢ILY-Ø#œMšöé’T,­ó^é¤d p,/£»°3Ä…2gø°Ó%@©’¾1l’ ˜ºäa/øÁÿŞG'4„#à4˜/}‹ge‚ÈXwÆ&›á Vn¡è¨hUƒ@ĞŒÏ‡
‚dLš„`	ƒÏŠFÀkAŠ ôNo
.IÑ‰‚‹&¿jøë7Ç3aPìûBWu‰¤3Sà¶ŠSq{È »ÁÛuÅïµÏpFj^Z%ˆ,ªÍ¢F½d‘û^øğÓÄ¶[ÃfGè‹T$£¶áßL$‡Ó¸!]Í€Ù#ì¨`=1v;÷¶µ‡àŞ‰0Z@W?%ÊÓö&|ù	{ìû¸<[‰Ç;ß‰8ƒÏdó’eø_82êF¤¹=n®iBªri®’”VDf9²áæ/6FPÑ’lë6õW_ét$\QÎ>6'á°EDF‡9>dB6ŞEdj~šo?~|$ $×m­¶ø$İO(ãœ©É6(å/T õQ‚ÍvšĞLE48‰Û­j /ú½$‰uwßÜl[0‹$4‰îx<Oƒ¼hÃ¸ŒÅİ‰(VúàƒÍÿQ‰è™ë›¼Rtúİ]{Îî!Ÿ:JËÒDn•<t'§¾îÚÓ|AŒt9E·3¢¸àF2‰úb!¨¨s&‡±Ò
ÍÎ…r©¨WVñK6<ót)DöÁ@uºAxV}å(‰äÛ]ĞYWŠ]÷\Wÿ²hA<Ch8D"ÃÀ¸’Í;f¶Cÿ4€E®;CUÙüX€¯;î.C$­’	&G•LÈæ<.îBjb›f[W†–¸$Mdl’ÃK	X/WÂe5ÿBG@š-;ò*lì
dz=ÿA;l¹
j²AªÈ•©àSW7j`Ûû-nB‰ÇF@UGÛJĞÿX‹W\‰FX‰V\*eY–emÛT–UG  7eY–“$,0,0“e[–4488<–eÙ¶@@HHPP Vºt^‘X×¹Î]…m†
‡ÈY×9š‰|g¤©,0‰ š™‘Í‚(0|–ÙpÀï>ÀU\@Ù‚# p}?İx¨5Ç ÈM·*P9³°íZ36°“Ü E{@s®5m5 òì‡:X,$Ëzç4«ø
n6gƒt?DØ?8ğQŠÿ´$L¨)8Å¸«Ôæ•1õbPUnÅI¨xËjˆı—Ä,ÀãèOW@5U‰>ëu‘‚x¯0&¥"
œlNFÅeèZ¾DkE¨ı|wÇ	°á ±Æv›}ø–šé {ÃÌÚm@¦ÚÑ‹aPE¤³P/¾lã‹L=/GÜ†°ƒ³Õ>Äwo^$„LPoËØn76;w#w¶û|ˆW™8p&‰ …'ãÇGBÆwDVY´ÖØ
‹Z©[ÖmPÅ¹–_”7ÿEà èÕYÁGä­µáE¤—@ü_¤	Ÿ¾«øk6A0³äÚ²Ä;X,A(Vc^i6ñ] 4cè=lP)·³”è_*à3”N˜Eö9yB$ÅƒÌãg7ÍP<sØXZ}³ÈÂa½`,sVµi¨t‰ÁÇ-8h·>Ömª/íÿÂßu%ÿŠBĞ<	ï¾ÂxĞAmí_á¶1´k×
Æğnwß¶œ2‹*#9Çr<Éë~ü—ƒ¯Å,8€9:ŞAJ›‹ïNşÊ­‹/ıÈ/É‡À„Ù/»3Šé<Ç„$¬  -³-¤øp„³²‡¬¶ƒÇc\âÕ¦è—t»1xF¿Dl
g{U/TõeÖ|t—)Çu‚Şà†çü$9Æo€~ÿQ´·éÆFUcĞŒYxÇ¹¢m Çu/pëĞ-9ïm0p³}± š­0x™P¡)5Ï©E8@ß­p:u•œ»5W~Ã€P„®	UjDVW-Ò)Ğì {°ı€`€><tÆİ~KT«F>kºã{x‰÷àˆMÂŞŞğşLçEGŠSÉ~'“Ñ‹EÜPĞƒ„·P†"Ø½
Ú€|AtŞQt¿ıÎ€ù+tÉ-tÄÆEcşºgí8;"Šc8ø…İğÛ&&<-ˆe»/"ƒµo¨ûv¬$¨Ÿ+‰şë*± ÂGí>@”ßÍ
bœ?ßX?-u÷±İ±œkT¼‹„rmÃZ±hV:€	Ú£˜ş†ûÚ[‘ÛğE¼ECR3¼0,l‡$y‰w"iìÌV22 ,oŸºŠN„åMuà^ 'W¦7äÙJmN%ß‹LÙrv¿ğ/Thjf[Áf‰BZt‚VÕóÈôÍ}kÒ
%ĞFOE´Š6ı	ŠA3vç™˜5&@°´/45A1Ñ)Á;Á‡ƒªÄaŠÒùqa¶8ÄØíäÎÔ£¢m55OØÕ0ÜˆÇ2 ô/uK ~rŠw@lÿÌv5Æ¿èDdlWÍÓA°6pPNDm˜Íô‹“¨†ÜwGíFÀûß€»ôÍl( xík6‹1¹'¤ÅºÄ¼BDb @`µ‚u=Ì_Ïf×$1L FTºè&éÈ8k(hßp‰—¸¸€:˜+8`‹úÚ0PÿÅö¹ù›oØæ­ğƒ[e0HWÿüºQŞTøl(]Ğ -ut‰o´*H7.nI°€s‚^Rû~QQ„©tL¯€'Uç·Aœ<ñÈow8JÂ|.œ%¼€,‰“R³–
ûUåBÃ1ë»·J¹·dP(“¼û5—I,Ñh€y(AocıIì:‰|ju¡æ¢­–)Bÿ€âcXB¾ïşŠlU€¶rìz¨ûá'ÊÈŠ*ºdğÈ‰× gÌP@yPÔ‚,-®ğ9”wŞD€­"Z/{wVĞ4,IºE4°÷å°TÕı)ÆºÇØúL0¸]‰tÓ5u¤ÉK8–(%v7âf1
nÉfU·´D!ø‡ù$½î¯ı;ÅHĞÿ4écxÉ¿{‹n±Å#ª³oz”A™kÈ)Ñ1Í[cb~ë„B)Yw©ˆÂÕRz GÁ-üfM~f Èæõv/vÈº ¼)Î×±İ~xƒê^F
ô,;*t®Ä[|è…G(ÃÆ­ÉFèf®ÛîVnÎ9TuGi@€QÿÏmİE9|ÿã0¾a[
zùÈ$tÁq‰tçtë} diâHfFc›dL‹‘†,ÿI5ü]”;*»E ’KèBLU("Ÿö@uüu‰¨i'?'/d
Ç4™à%$ÿĞ¨wF/G%ÆQyølSôB6ßU“ˆûg/–
‚bf€»ğ' `¨0SÍ}ËM¤œG+tÁ£±|!Qf·ì;dbƒ¸‰ _Ålš5rh0‹<>pÿjwv½5OĞ^¨Àd‚ëJ`±V#NP³X­5¡tkÎå²ìJ½_4óª~€8e“4Ê‰Ö07ƒ6.XáPôlgO¨à0İËê`7[ÃGKJá[>ƒŒ0uoH…íÃVJ.Prdƒ€¯§<lÚ
TE‡W ÜäÁ5>Og!^I^KFvôœ˜c„3 Ô¬œğTÁZ½u6ÙzMÛä…tœtK80£4—¥ÙQß¬s ¿m…ıÖ	v‰ê8\€[ÛÈAëSï%ƒ ê^Pw'[ÕgW2S6Æ—¶v"¨Ê¨b+ƒ<j´”Ş%JÛWîWmÄ<ÿ%ñ[c‡8—'ûëv$CÂ2™1èQÙlºàLÅW2²0Æé=K(ïŒ:CYTà("(0Øi,,ÖˆÌ€A´  àpM,S¡G[˜ÃĞóPtpf”0Û AºÓÔ@ĞDHdLP şòu´;n8Ğ \Ÿnd½òtRïÁ‡f@µ÷ÖÉîm€ éî‰g7º]×p(
,0q¹8¦a1Z´’DDãdëVöÀ£ñrŞÿ—Æ¹® Æ^g€‡A6¿ÛN ü0{^µl‰R9îgÀ7Zrıv1M#TéŞ —rPäÇ)'6T@­ íUW0®IT¿X“OíJ4Ñ‚­5êgÄÒ"9¸6ÛW]`Ü\@ ÆGÊUd’
œÎo‡,ÖB&,§ÿ‚¦i/;L1¦Æ‹.èu•J7DTÃTÌƒtÜ.yƒyÜsØAÔt·­AÒgyy~¢j%¨E·xk7©A‚+A·,Û‹í@ Rx"}ê×XÑ@£Tí+Íş(ê\r469y[¾ ã1ù÷İEyE*ƒâK*šç°%»,Ü@€Òğp»T·lQ©_‚	rtC<wŞšïÎÍ>:<a
/ÆûÒ‹eÈÎöE 	º;˜5d1íécx¢OB3bt¾ ŞšÃP
x+öÈëÖßXpµĞë€úx'ÎŒTÄ6î2E€ÉC|dë˜*^jÇ3˜ñcş@Lı¢ê¦K x¾‰E7(º¦iSBÜ!Ğb¡cP÷£xWŠ)Å…Ætá„è(|úXX`–(yÏµWØ<	ş½V! =`€P W„n‰æÌe1ˆ-eš 7vØàœğ˜a«¶ßæ „uEÆÏ 58OŸÿñ`¶}ÜD&Ü•3¢JË>.ñ„²ElíVM t@5-ëÄ U–í¡ÿZ— kışEıªÕA‘edÙ(,bl…G–0P4ÆEÜC@İÙàÑÈ]HÍté¬…ÅxW3ğ–ZB¶#%ì†ß#!Í]´Z4”^(*Y^RqÀ96RCZèƒÈÇXÄí¥,ç7	7/R€œ,E¨³j÷K-,º<+¦£Â«Q×ı2dkeÃ\1Ç&F±	Át(äíÁæ÷cˆsØâ‰¸wøg‹M$jXbç\`@ %"ÊfSş+ØC¶1“Xø]´°¶*=0H€LÄ‡‚C>¦ÔhE¶0F Ôö¾­ÑíÇFH©*ÖÕ‹o@v$¨¿J!ÍO.öV6ÚQá‹Võ´ÂtF£St>zIä:;ÎÛOSÖE'ËkF+tÂ›–¾Ï…Êu;€bu	ÈXµ»¨¥0dÛ@B4$¨€nc’ãÈ"&¿Ğµê&Œ•jí{fVàŸ>Wµ_V~:£Ûv‚C+9ZqâÔ)‡Ä’ÁY)Ÿ=%k"è¥µ6/¨' ãx¦3:”sm@h`çdG=`;\là%pËTì0*‹0ßà¢|çÀtöDhÂÉà¥ äÜI|ZqWkÑ „ÎÆïÑBãMnÅ‰Ïˆ¨7Î¯İ5±$N 0RU84MõWÔ¤„kç)÷ï[(H=y„½ˆ‚­´[éÙbn¨ÅF„¢ĞRÑ(ßÚ€ú" U|‰Ç9å6€ğ°î!ôÍJ¸Q:h?mÇğ9IÑVõ„V)8°…Ù<ó(Vœ*Nš­ë,\«7˜Íè 2†Ùv(êâ\sRˆ”3`M(è0Ç%s±Ø{P¯LüLMŠWà I4ÿB…)½K%uõ9Öt*°ç›ı‰÷)×…ÿ¸7”R¸ˆm;ğ9øãqšÆŞà÷ˆ_Vš~%kÀ-„h…x6	?CÃhà˜^‘õ,Qâ]@³&VvFüm«N0p~kÅ$÷šÚôuK<Ø‰”„\A¢»qƒÂ |ñ@gºÚ*…'Æ³um8%|ğ‹ihŒh v¦¤ğ`ÖŞõ¥=Y~¾¼ˆzƒÿ
tC]Í%‚W °0‰­»Š`à 
öƒæÿoA¢ôÆ,€âŒG;wÚ³µh/7ï¯)¶ğI
÷ßwE¼)Nx† ëß;
ÀŠìb‹”$¹In?ªj?Gë	¬¬D_+Dì¹¦Lñ•á
wäñ&8¨Ÿ@v35Zò¥”x¾EvR©SœâäÒYîúªwtŒ$ÜÔ½‹Èéyß$¶ÜG´¸òö6<öBå="wÇõŒ™ ·K	¬ı7.9úw€} 0¹:;,DŒ‘1nì¦~û@¥¿­m0ü|«pbxZäw<vÿn³1
M†‰Ö)ş[ ìI<1"%¾ÁsÛ*´İWWSÜÑÊ–Ö¬P0Û<$s@'ux¬§|Q§cdáÅÕô^p˜8Ø`‡Ou[&Ü“fyZè÷ÀkE]ƒÉŠÁ
eÓOÃypQRR¯ ¼
MŠULuİ¡ÃäÙ‹½V5[ıt4tÿ2•èUáò;xÆ„Ü1¬k-{wq˜¸*©‘ rA	ÇdmHÑÖ4FvÑ+[,tÏˆPd‡Â,İÍ)àAx."cu$º.Äl&ğäRqˆÑ‘sLK%"oy“X‚êtÀéşÕ;§2P)Êá`¹L£ùƒÿ”“ŒAH¥)	«ùDdı.q£A
.ƒë·ĞØMû¿«vÖ£ôGWe7@tàI@© ¡îÌŠ 'Ğw
Æ¢#^ts)¡&X¢×‚k€ëcØÖ
Î#Ò
¦p¹"º pØ¬.yË -7“kû˜Œ„ÙcÁ‹}ˆKñº0>õäkÈ àğƒ¼…,P˜ÂNu0ÉUëc‘ëRx¥‡	ÿ|v‚qºÃmR€?äÂ&Ô¼¦bV…uo°H4)Ç‚ªï
<8uÔ”VŸÓA¬Dİ˜„û0Ä|/Ìm9çt|Oh¼´ÁÁ XÿNë>ÕÂ½.(ºz®z)z)§Juôšn°À‹'´(ú&@S‹·¡%t4ª× Ğ0Ş¹hgÕM†ØING±ø0o¼#„B¿ıFL‹~Í~'‰~¥ 0;'[RTs" ?XmmàfWüqyPõı¡2r^y.€ÛÑ¥¾ˆALP²QLÔAPS-m|Û†‚[s…¹(yi‹
¸)ˆ}R~P¶?ğKë+=¯tB~@*€‡n	=Ç2¡K­İ¼B>FR)­™kØ=½Á-3öİëĞÛ>ş‘­"/!ÆG;y|ˆoÀap±°$kÀ_À.0ô®%îj…$1%÷Ø‡Ãßî"ƒIaşÇAÿ.·ªŸ±^ZÂ ¥jo“×æêiÉÑÚ0t‚
è]jvwì	ÒÑúú)Ş%”|Bä+Ï-H ptßãœTXu@ñ1×W£ Øjåîp¼ããƒëQ‰V}`¤G#`_øºo½ ;Uª¿
üˆD<4ôb¢íÁ}ë;Ğcòë*–à«vÉ8Cú¢S5Ä¯háÃú€:*t^×Ÿ[W¢üTz9Êµ­x‹hŒ¤ßÄ-şşrkÆ
<-Õ mĞ·ˆı@¸ÍszÈ"göHÔüÅoIÕ€zÿ%Õ`=€$E×wQI~,W¨ pßmïáÙxF 9Î~ÇºÓ™î’ ‰&(~ØÛ¿=mtOé09×vİ©0tØ'ÿjXxë7¢âˆ¹&ŠB8Ëö ëG	ÍëéÏ Ñ_‚àáëë»à
Ñd!Å€XËµg‘_KÔïa/Š&üt€?$-»
İ"tG‘p2=¾W+¾Rê¾Ô3-è7.uG¸Î`ï0é\îï‚Ù!:ñ^ñB—¦zoƒ‘p¡Öû‰ÈH
©”	G¸Dr	ëÌ6ÁX!?ÍZ3¤7dÍ°~÷ÆVíÁ¸Ağé‰H -²ñšÃB}9Áø¢Äó²{#»„S´		ğ”S¤Ö`öA!\[“Ùtö6œ4‹ŒHA.$C&Ç()BÖ‚o[ÛÀğ¹0ƒåû™KßÑJ
	õ‰iBw¨»ğGrmu NÌßc¤]ØB ¸°0$%¯:®3VkPPš"DıÈ™&N œP L…b1Ò‘ )Ü–DŒ#ë¹£.gPbÇØíĞC³Ã”pØÑUu#¦
$êz-txƒèƒ~§×P ,M…‹ø×ş("‹l„TÏ–e+˜>ä‘ı2Béé¿é9ètéTufö±9Æq6LvŞfôMŠ(ÿEË»]¡ÀŸ}2Ìb¾Tr?Æ@&P2™ª_¼tÁà1dPÓ(IpI  Ÿ¦ô0õ€y)N‰ëº–hÕÙ|cŞ½v ÕùŞÁ#„uBA3ØçE|´|9„Sc`ct‰4mú“eÙ '48“““<@D$'Ms¡PXº&sÈh@80(54À¬ÏŠ¥¼³°¨,"‰0›§|¯¦Œ“I`„Ã7dY4$—$øR7)„7ıfla…«cˆÄK@”ŠQ;»R…À6tIo<$ä$Hy’k­!†jÒlÆ‚e¼h	Úíöı¬‹~0@ï]D¶jjM“	sn!:f=dŞ’‚KˆQOÙl” |“{Ô@rQR’¤@nÁ‹k|DÈæ ïf,ò½ÚmèkdÔSÿ›ud„x"slˆª‘…>òaW$4œjUT|Qò”MH|ARRq‚KgF #Œÿƒ4-@x„lu8Ío”ˆ¥ „YC³ÙŒ¦$h;á»)¡Î TWâñÔhÂƒ¶HÇ >òi2ƒ8oHÙºQ;ì©¨ç´Ş9‹r Pü·%0€$0j#xg]
&‰0š‰w ¢Úª< >R@”àòû€Ù@jpƒõÁŞ)U™¤J‰K80“û>ˆiÿ\0;³xgM<ğu	¥
£q¢#Eej_k’€ŸI43Ñ?|E W(ú»’2énPöE @tzÃA$ñ{§u'²bußf‹®¨‚¿5f5@©@k ±IöUßÏ^ mİˆûe ¿¥Ë]‘Ğ‹m ½€èãÍ’®ƒ~ÊRV@•:N6I2†fjšÅl‚ C; A][6‚aKµ%9¹sVµ½mñk­(ÑöÂ¥h‹oEĞŠT–8íÿ‚šU4ó×DôßİşëxU9FuHƒ~ş»gÉë_€æ½DˆÚ2Ùƒ•è­­+t%ÊÍ¥6ç¶“x.LT±Q€-¦@P”¢ü&£¨€šQl];ÊíĞU¨TÉıÍ/z¡wîëD±«øeƒB8BŠˆù½@õhL>_
ë$b0é$D7şĞ,›†ö ñëğFÛˆİ
ÍOu¹%(B„úÆ vWD.—-kñ+­Ôê9BS P9Y´B‘û5¿@¤áÄ‡$ÑáÇûUúˆêtl×‰Â$##M@#<uwabÁDm+ÛëmD¯@îÂ¢BñdMa{‰ a\t5÷á!£•ô@ ÿNe!,@c"41k½ 2üff(§1ÇA‡DiW'ÆÂ~Îú?mĞ<wI¼ùƒÿ«Ü†W™¡áô<ÆDîR8t4Q@9FíÅw¥±Å'êë"EÙ– yÜ,ºPŸu]P6¨f)
A{ŠÒò®DnOO\=,xÇÄÁÁÊ´tëó¥f^+Bf>ïH n3*ís»k‰:÷ë›ÿıİoXlü'o{óª/C;UØRñöc…O¬ª\ú_Õıco«ˆÄ¬8àt	÷¶™ãH¶ğHî?X|4¢+]¬®pøX.áFA¾£ˆ0Ùé"Zïeqº‰È2Ø¿dOÏAItWõ¬{¦K.*	_¦î,v÷IŞb·»‚·\BëL@J")Èˆ½{CB1É/àµÖ]*ÇNÿDô/?ÈUƒ#Ã¢¿4ºtá…FA9Ğî¡õtô)ĞÂò8h6}ºHLLaPwFr2şå*ç(.ŞÀr;AF¸kU"T¸G÷ÆAå‚.ÆŞ¼ã×Ï p}ŠPÁíW½€t1r)9ºÚú‹‹¿‰İÂƒé¹ÛjÛÕîÅ²[0‰Ç#¶úeEë1‹Òïí/b•>ƒÁÆMÒ¡ö†9×u]‹y¼ü¶*Ä‘€`qıóK¸R½µå!y4ÛûQQ0é,Gº‚»9uX4ƒío£l…‘[à£X;Ûqõ:TÂ2m·êœ,ÁÄº]¼í“)‰Êºó``üàPr>Ã¶EÑzYİ»A]$x 8êç)¦À}V›o=×uïÿy:‹JíB ¿‹.•ëI›š{?LS¿`Öu,a%5Q;:(ŠZÓè@ø«=PŞ
Óà	s9h^³¯ÂXÆVr<˜ƒÆ1ï>0Ç9ï>WĞ]«êë*uqnC&kŠ;('$á"
®;Ÿ2²÷šh[Ôb-$™#ßÉ^²‡”‰9,…ê¶"(A¯Ól²ï¼Ğ¹qƒÂ—¿ôØ0ç	ø”Ï]Mô 	iáL«5cG,ePüÁ™  m´´d1ãd˜–u’Éèkã´ç¢8»¨XŒó8ÈõÔBŠ
œõë3LªK¾GÆÀ3lø3^„¡ÜöXbÙs=NF#nsrA;uï?Eİ\@RmiVÈÇÎ(à`·¨Fõë+
ëİn£hÿl`7t_nSì uæuñ­QÄk÷Ey1A³Pµrf›nëL÷1)GWUuáL»hjAÇDmÍu7Èp×R‹&&Z×a="÷ÑNlËˆšƒDslCñÜ"¾Lxº¤`ô½Ô|w&»,×áj†€?ƒÙ G…>
ƒêCP*Â¯jöT´^ìg–xò]ù:j7PÅ”†=Ä½Ï¤dfPW	hº÷KÅR;çv Èí½"Å¾jàÀš±pD:xß”tÆD0ÿHÁ›Q,EœRèüË‡ÙìÜÊÇt@Ü
_¡Àa#»to(±9ñn¿Gpñ¿GB	€9ÑëßNó]RTGˆ”´Å:ÃU©Şİ.+zLñäUV_äˆ¡<E&~Ó<ÎNj2³ŒàØJ„s¸`T'Íù#p#{º¼«…6ÀTŒµ±RÁDÂ
µ¡ûOÃØ}TTß‹:æ°dÃ`Vµs\h±!š8HüPhÇ
àÇ‰–9t_ñu¸C‹ñ3FÚ2[#F	DŠÑ-mÆˆFÇ@)hn@¼FPh¾H,‡ÚP"ø4@D©2W(ÿò¥púúv¸_Ã½ÀH,ŞÄÓê»B‚ Ãİ«‘Íæ@v	Tv%K°dÔè8×À >ÿßv!h§jÑz}íGvÙ+uZ(ÌÎø±ğlğlà¬2ÃÕàyp‚õÏ-
ïº	jwÑEÍtãèKQüy>C&ŞÈüëCü8[}ĞŞA!İ+$‰¬ ½+>À4/LĞø4À©ıÚ‚Êwæ8‰ûÔºÏL2ÊŠ‰HrªfïÜ@¤ÔBƒæ/{Ë^¤ğN”Ev»ÁQ¯o_åüƒğ­¨&;~0ĞÀ+KÓÅ×ÛBû}ËJhQ;\‰cß?T}²ı/‹Ww«7¸Q[µl*|î_w–İ{Åë8ğ†DÆpt5 ÏZ÷[p+µOx!rsèÑ¶ˆMtÈ7vWîÚ¶râ~DÁıYÁ¡`¥=3…{Ó„ª4síEV¢m‰S>Pƒè"WxV*¢+Ñü©‡}†wÓvŞTñø?ôÖ68ën‹ğæü;ÍHr-ŞÚPšu93·íù´†Œ¥+9ï¡Ù[ñ†ÆsP¶§ú0ôVVkïÁ­uƒWÔXjDnøĞ‘Ü: ´xËÑQ|¡	ˆAĞ:È,‰Íõw+-á”¨ËƒáØDÁ'@9×wÉ0EŞC£uq5‹‹1ˆBÇÙ(©0å. »5A,2 o,›ÆOç…×µ¸±–Nñu4Ã\ÙYÂh‰_ø"o- <n‰×Øl|¶‹1FÛpwDÉv¸ë>ìÛ=æì`c	RP0ëDì7Ae~»±‰G·vw,oáün°bváÔ“rcFnáİW,8ğ+Lò.ñZ´	_<™—\cKí°öÚ!Ñ«[Ğ«^2şP*á@[hJuİ7û;·L6>z»‹‡P;(\8ß‡T-2
„íphÆğÇ:" ĞÜ*Z>—¨ Ø¼K­»‰ÒCá¸ªÈ¯½›‹¥Z£(ÇµJÁ¡£ˆT
ı–‚v@‰‚}‚Xm¶Xk~ædğşL3²dpv‚hoìîü­‚t™yh‰é
		rœ-4=İ¡JNñRHâ/şÜ\ö€`t)Ê÷Ö‰|ÛD"‡:±!Ç~:$è H,¿û-¸‚_V«]ö…?ìˆ8‘Ç#]Šr)2¿ü„­DQ|6}ÏRRmÉ!‡WÆ*ØßÚ8ƒ¥PşƒşTïØû’µÌ¸ï[·ñBïƒúèÊ¨Pˆœ™‹ß[‹z5s	uû%,vş‰½i|l&~ÛF5)N…f‰ò¡
7ğui-
Ê£c?Ğ,t <>«AX‚ª(_Ê/—°¢#€2Â°Xœ… pë:Z; 6Šî Ótl¶ğn]/)‘øAêŞ›Q'P'÷h,)ê{EK$ºÎ8;ÎXın”&lŒÊ'É‡ÚÁéÌœv-W½İAz·D=Ç‡\!â8‰TÀ˜l~Å‰³¬†hcM~“†l†dt–
¼ –ÏO|Òx;BrzÆ‰VÒÀ€ŒGùhë€Ü+ ûmQ³´›ƒV0Q?fjÅrh$j9cğ[*ë”D¶]ÍÛşáë0%$nÎëšƒ8$r8<~@Ï0t×¯`¡‘ùL“SÕñ”Ä·¡õ9Átó~ïV„rd-½Á]ıs‹@ü¨ulgPüªĞh–™"ÁQRå	MÇµ‚y|r²m¯4v!²|r²v@¢s ã,FèYŠÿ D#Da ·÷WE»`Àï‚Ryu‡#€L*U^€	4(‚UCd@v`pµq@ƒï Wh-úD+LÉ±JÒ7 Ÿh9Èµ€ñ4ç ;u,u8}Â”øÂ•E˜Á¼æèVşTZL KÑ4ERñSHbû±¿†@‹VfşöDí-F×Âa•ß3rgÉÚN…v9qüp`ØE(O;€õ!—t~Âù….µø‚<hM³9õ'“f¥`—5³ê²áˆ¬ùVš{H}:HRÚëGª—2á–[Ó>*Ím´F).eyY–vºFY– „e[  ®uàL¿~|‚7Ş‰Ñ‘?Üµ|ˆà	h–p]ç0t\/Á`}:‰Ê[d½v%Ü"ş/lî3¹­ÒXDá³I5‡å*À<\HpÀÁõ´åuC°+),
E‰î+¨:rtô+@.6”;a P^ƒÁ$yœdRÕl¬KìFƒÎPr=b ƒuÖ‹‰‘p¯cÏp‹h«%SgeRÂÏÊ}s?Â®ÈKw"Q›VPqHÂZM¥ä¤èÃ³T@M(öâçßeeyàŠ\)RzçÕ®—¢ú(D
ï`ÈplKEÛñÚ]†X#ø	±»èB,šÅuA÷ŞVBKR O$x¿­"‰é)§Ø)õŠº¼ÑçÏƒÏx¶$@C‚BL ª±ï0S´Ñ}Sé×CıêâÅBÎ®4Löª8åJÊ.éSàj{³DªşÚÔ…ÉÅ„ ùd"0p‹Ğ`NK[5ÿÅ7ş¥)bS,Q†á(sºm†¡ÈÃ«x;Pû/¹`§uC9ıu>l‹Go£WâzmÚˆÇößƒ;p,tS¬¶Ôå´!q=zÉiZ÷xB¦ö(›BP&«îĞ«S¨G¸àNÀ£ëƒnÉnË úH,j3…ûoƒS ×]¶Ã/w~ƒê1ƒ?!4Ñn"Ú¢@G@_~ìÈöı:Ç€r 	Tƒ4#ÍLDƒ¦˜‹ˆ–PÜC!RÅÈHvrì6N›’0P²\ ÎÂ$¹ (ÎËI&„»aú p(ƒÇÁ†QW“M®$‹Öİéo\Æwƒ‰Áîf¼kXx·‹BvA3üì†@€âÚâáy† "ı1¸á1«öA,'‹mŒğÚl•)è‹hÌM[øêóHCğU"jp°˜p$ËÁ;zddá°ÍXáÑWX6ÕBjıè&iÑhÍM0ÁñÖÄ×b›œÜğæ1(”}²J,ş1üÑ12Z”0=`ç%—mm¶8>Dr/µH@¿ `ë*Ğë_—[P6)‡gğõF¹)ÑQŸ°Eß‚ X½aæ•¥»øCw…sT”l}7-º ¯éko €7ÍW7™ƒƒt‚t(â,‘ÙBÕgÿgÇ„„”  HyòÅ¢n‡î*W'4ÀÄ.xóÕ¡$ˆ€»Ààƒ|x­-àÆ³\VH<éŠRÀ<»Ÿ-ŒŠ,<ëX6Rh‹C<ŠŒ˜Ë¶$	ØÅRv„á›õX,^©}/Œ4·[ˆÆ6–·)`Ù³RĞú<²[ô£}ótòu˜Äôëı@]^F“‡¸d÷ÚˆĞİ¤²: '#,ë!—õZÅï°ÀÇ.€8%@U´Ró›Ù¸g“Qn_ˆ(»g;Â$'nõöCÀY0ŒÎYAšª^‚P³¤ÁŠGÙ,’æù&MW9F•5t°`ÍJXÒ‰œãC5FzÛîŠYù`Ù;ƒ$Ä(€4Ïì0\æRvælOm<µ–Q•ÎlY³ÓweY*Ùœ‰RÊõÌfËŠ° SÂ4ÛïU¨t^¦ ºNhİ &	Ç°( ÅC.)ĞÕ
 lw€*¼ºMü½ş=À·Øˆhw¢Œ“ â¹à½-TN)„“Œ	§p®©AVï.)²¹‡aù`Û ê—‰³Q ä(%T‡7Uú—Ş’c,ƒ~fimNÆA@ÃÔÇÈ%Õ/ğ <lèë5‹‹A­ÚÖ×ÈnrwênIÑè·•9êø]´¶‹¹çúë9èrT× ¥FxÉhK¢Ú•+Øvÿzêv”Uà°-Íi¯4‹àr½ko0 .c¹ó
×A·7•¦iÒ§AiÀß·p‹yÂ¦ƒg¶).”íEÈ|ÌD|[‚‚†¼‰wkĞ
Ó1ÖëîWİY]Nyğ=\NXÔ×‹XÄóÚrĞSˆ(ÓÊ¨5š„ö èĞd±øw	oëh…d½@¨?l…³ ‹”³†Bu©|UûñqGµ™$‡‡}UéÅ!Ò4$u6J-ÑÆpø4”†Ağo$´N„€¿÷Kx¨²oB¾ÈŒ@ óµÂl^ŒLĞò`bGß“ª(P®ôÆÖ¨Ô-¢ö]è{(ØÚ+¤-!
øØRotF÷ÇïìÛe‚(Íë,ï
€>0Ş}Fƒï® <xè·vëõ.Ñçÿ~¿¼} (GşS"weÚVt˜jÜî]}[€”õ8HĞ€f°µ.|@`Æ±(.©”\ıŒ9ø}3Fé\Ã·K®:¶vŠP ŒÔf&"¸ĞŞmŸ×0Âë®U÷¦šË•‰(€|À¼öÛYÅî×,9òv@ãí™XL$÷Ú¼@HBqW˜‘ß,¤Wxñ®šğª@fU×r¯$\ï#}ïğ\\-÷¼®ğ°Hau;	
À?–ß0u)ƒl1ŠÔnqhÑLÑdr›ËF‰jiáµsHéÛ@†Rş{}ƒ:œ__õ;½Ÿv]náˆĞ…°ƒèWè;z»ÂyŠ‡’¤ïG"w@]™ÀAdêU=Œ¼9 QÃòñá	`¡n÷dÆ’C¶]w˜s!Cë„ZDàT÷,Et¬"p/ø©L´Ù^Ï[Ê ±ßîé÷æXí¾TXñòLúú— wÏtm»ë¤÷?æ6N‰#ê´s kTc_Û%oL #zqÓNÇHˆ'/XD&:ŞYD‰3#gcâëÎÿ¿—ëE¿c
Ü]L!9zrw"Ş°€í†vi—?tÍv+÷\˜ƒ ˆÈ$PÀ,œ¼¼×ï ä‹mA·@àë‰sVŒU€ÂQ½Ù'ºX¼•ÃhÎ<»xu¼§î B€¡w RƒÈŞyÃ”›” [Ïæ«qî´P·0Ç :´Åƒ"
™è²Ç:‹,t à~f ˜æ ù¨Ùd0° O€ZAmÕPR%D´hÌ%Z*-"“{ 8²W~¿“Zk?s;l;(t¾"¢füi¢ˆP§xÖ'»g_4¶„ŒhDÌ )¨àº^¡/’ªÎ	ûGì¿ß’JH€¼

u?Æ„	!˜<ËS&'ªÆª–GwVÅÂWŒW–rI[6
†ÉvéTRÕÉ›³%î‹1ÄÃ1ÔçåI{’9ãì =•À›4¼ƒÀØÿàƒƒEØ“†n*f¦~Y¸BNfš*	µ-šÌ
vÀÎA›'É&yæ÷;è@	€òôcù†µ=E~ÿÿñQjyü	ÇÊ0˜ø‹ë8¸‘.ÿı^¸W¸°P¸‘¼ÚµIJhëBø;¸~1Rõ4Z-’(¸Êó÷æj!¸ ¸cÚ£ÊÖ•C¡$€á`l¿€ø¸<“–†ë$pÖ-€wÉÖşK·hìÿ”N@uó@Ø$ÙJçá  Ü–0Q.öÃ•«(Ó|Nå7fR€¡¨Q<qC@@u"ƒåğ¢‚€9ƒÔ£wƒ¨”l¹›(ôêB»àe–_‘Šík¤uèFÅ»—»¼ =Ïêù÷~ì KF ›ğlº 
·«)a3…òd{@¸Ä€œrRdWRtÿŒòD0r”êx¨ÉV¢“¸=˜Sáõ„$´ü¤cû»íT…>³¤";E·°°E x½ À·§#‹8@uø%pqã+"Û¥V%Ä•”Û.Ñhƒ>Aà:7‚îûèÅ”ËH
fN§kÛÁèm£uøÚSœ0Qÿ(Ú©Ì±o/\šôìİ:¢p¹@”xu[óÁ€;ˆËÜ…Óº)ÅÀİº2`‘T† Ùô÷dƒuËPt€¶*‡üq(zÍ‡#˜Š¯ï‚ih¨Up25°ÇGm»ŒGKÊ™ok# F9şo¼Ğ«ì9Ü›…	1/X#ô ÁäƒlÜ¨èù÷=ÏRœ¤U4‘¨TÌ`˜ˆ£û¡âÒ¸­'X¸w(¸,W+–¹[:xÿè¸´¼$8fkPƒ	SCá” ­fUrFˆğÚºÖ‹†ğpèñ•(VDÌE»™Í@İØŒÛ“*Ó œrXVt]?b	O”]³®Ac1Å¿<–T¢˜zà54ûl€1P‡˜™âÙ„‡Ò½®‡s	 ş€Wà@DvámDA¤ÛwZYªXâ9Ä ÓdUüĞtÅpÃÛ!yè—ÏPMç ƒ&€›AôfåØ@¯Aš8ë"Ü*éªå7‚òò0€·˜6ææ ¹Èİ·’*NóM„˜€ÄÚ®Ò¶JGÌPI.ä;ì{—Àëák™ÿ5JNĞ
 :À•›íRxRp@ë™¨Í~J¢tGëAâı­Õ½	ŠFˆF
°Õ4
&‰1¾RÄì¿ØŸPVVÆ“ˆOìr»0ÍæÛ³¶fåEàµPåO)Ä®"œ+4ºd„·}uÁ‹UÜEìUªšœÉ™Û®¨U(Ğ}ì»W)hQçuØíŒQ EäŸš®ğVİÂˆH×İ¶_Qr9v(Ôƒ"­œí B­;Fh8aÀul^ëa‹…*Z!*[§9ª‰JŠçBƒGìO¥!ÏG,[„w}Ü€Øì.tf‚+E0¤€8O$ªxàHYjj°ğ IL|¤øbóZûšşä$<€–¹Êwïi63›2êãÉ’§¹f¶È6ÿ¥.•YÁ‡‹O°Ò‰‹Ô_¸» /=›ºËbã fl2¿?ú¹"Nœ:N©¤ÙÓââÇŸH¦é1l°ãê:Ì„£Œ\¶JëÿœâÑ„[A—5vœÿâ-(SÅ§ÿõĞgĞáÒ»â80¸ÅVï#…k >ØuÆëewPn8P"yÃÙÀ+Œá]¢Ä…É	[vïD4$['R»«„¯9!ºvâÿìPöš<r×*½âé‹ ls¨-òeè¨è$Š'—EQFqi[RÛ@{Ç†yiªwRÜ¨~µñXOêMmÂú'bPğæ@^O¾qü¿‰€iÂ0ˆ‰ÂI€9?téB¡¢Tœ~Q{{ûíTùúcv
Æ?ÆFë¿0-¾WË4Q[y«âÿAşNş€yş0tÆ0uÙbk T÷{ç¢L³yŸàD5”KÑ…QG#€­[AÂî?§‹ªX*h6Ên:š)XBáúíu"B…o+ôOø´0v¥(‰Å¥JDÃô­hëèÎMf A’Q¥ZGÜË½Ào±ù<7‰×m£	5/k¢Z¹¥{,…«²@½&ƒzü§ñÕ-âî¾mj2Fø»Åş[ìFükÀB"-+Zs­‰ÒV7F³(ZVu|Š',Škuf¹‹d-ú»èü2Û›gBFüÇFÆ­Š¿u½ ÿ/üï)òGlŠ¶ñ9òê‰Pülx/üC@$Gl%è@áˆ(ıÁ`Eo,o »j.~g1É‹LĞ	I$}ÍÔâ‰DjÔ<µ@2K ãb$ ]×(ì%)ª&,fÃ¡S èã4Şº {sNã;®&zêƒ%1í‚V­`AfTG¯@]³1±8sÆ"Jh¾8‰ñëÅA/ĞÛwËˆª£D/PÕ¤êI“±½Cµ°(•hCtëh~T¡ÿİ <Ş¨šê0ƒf t}â@ZğÍ’¢}(Jƒe^ÄB}‹duó2çÅ¤Ş
ŒpñĞæÄ
"RRø@mG@C~ü êmõ•-T@>Ô«ºä)Î;EÍ#cUœEÍUÂoø'²GˆT>şU8u¥‰/,DıUoÿÆÕ*â. ËâÀ3ÿ¢ÜH†dƒ¯lR²@h8(Ş‚è©Ï3Ò¥±"›£ÔäüÈcoİİ8+f	4tàˆØº3<%,¤FĞ…+¦'€qÆt`‡H²xª ğtK¾DíµVA¾øf˜íB˜t\¿K-!T8cÓo[k–€j<‰\Ú²l9¡YA«_ÖèÁ¬öÛ\ğÂ:Ğy¾‡­(“0*b´Q†,¥@;WvPæ]9ğÌ 8ÁvØş‘˜›‚â´Â¦Fƒş¾ç‚°B|B›^E£ éW,-7h]mÊÇëĞxXµ—~à¶ù)`w-ŠE <
ºĞ¨h}E5
B….t#5t·ëçíÜÛ+-)Ö)j 8Q/ ‡^èĞˆ¥q¥[ÛİşÈuu_‰4Nş©z¦6 -²,(]C¥iÖàÖwv˜}â/Â¹]Kı¥lQĞ`•¾ aFupê`a<Sp‰î)ğ‰ËQAkn7´ zûÀ`Y9ğr)Ç)TÈ
o*;UöJEL¥ĞU!AÄê˜ÂBpÑ+ÅÜ	-L1¨m"@Â/!â6Ó¥ªrÙ Tœ!„ˆÈÔ@l´·ZtA:,šª†ª4}(Ñ?°ã‰(Àæ–ª'QÚuÁ¡ü3"ÃÀÂF‹êN@ıìß#¢T¹¹Ã
:ñÑ…”‰ÿ­í x"öÆu"‹İé^í€l4Ü­AVÃ!2`·!P4 Ã'¾,Ê=È	˜™XWØÁ GD¾ù*Ïıˆëş'-0|îë8à€a¼—ç:Å¦SäyKO/ôÿy%ƒ× 7ƒ7	Ã Æ_†"€BÜ[ØE(9êi@'°ñ"]ş•¶ í	11)$K<Æ:AÈ
Ç*÷­ŠV–¼	Úo'Ájˆ¦Á%Á K¸è#¾ø¢(p‰z ˆ 	òJw õ¢²½@Á’^-7qÙì˜ §ËQ×Û¬Í‡‚ Øşl+P”:ŠJˆn9qY€´âeˆØƒ5ø €úakp§:(\È º÷êG Ğ+ò#ŒUAHƒ™ş+şÎ¢n° óãxŞÛoİàßàz.İØ {<©¾¤(ÙÉİáŸm³½uNzL¨Øñ¬ËÚ‚ÃšévW-uOìû	 $³Ÿ',ÈªKİÙ^Ïö±İC
Ùàd°É„öÖfw&yIzG™.'Ï.f bppt]á…:Y9`­¾0tÍßÀ
ŠV»-jZCd|t®V<ê™Íl`´¸²¤{¿®³ì¸¶‡Aw:;¼Î‘AF¬
ŒéGü·ÂôSÙÂÙÊºÖı7P¹˜JİãökÂÛ,0ØËQ[û»İâ)İÛ÷)ƒjñ ûJ?ÛìrİÚL}ë Ñùë¬Cõg­*Û.Şùc¦‹%ĞÆU‰ÀÂÙ#V]¶ßJpV€ÌáTÙÀÙlßÃT]«@V|øŞ úFşRPß,·ŞénSƒH<öF§ŠF/™\djN#ò,	ØÁÒ;æ|Ül4¡» |©…Ø•¬ë»5bÁÎ%9 gõİQgOëf¢Û£şëu©4²o]?} ëj0ÀĞ"\Ä #3vL¶¡<'Ä ïô¬äšÅ0yÊ|U VuªŸµ€¨Á:BÁOm¸P¬ÑèŞÜ¨…‚Y“$èIm«·Zã«Š<Šõ ÷²½Ğ/wçŠ¥^*m
#+çc<9~%ÚI¥ê‚ƒ4>Ì‘!¢JûFm.kTÿ9ÁvÁdßt/&¼ÇräE‹Ø¢EA`úÂ¶<Æ ƒıü|9õ÷`!¡ï
CfëJ£ÔgÇ²ÏXˆJ~¼éäãJÆ0ó°³‡î
xöÜèˆ/NÃD#÷ŞE»¹+üxf4|p
Ÿ-XŠ±„Ñ|ğ¢±Ú­€uî€%ËTâ-µˆ¿Jõ3cÕ½q0Œ8Ã2g¦*”zboz·$b	hë‰ŒTÖ²;§D)ÊRşö@‹ĞÕça1ôBÀ_atoÇÅéŒÔFønĞ@Œ¹/œÆAtŠÈM³YkäŠ0{f8nßP«€kuY(ÕêWŠuôûKÑlhR$~/
.aP9‘£[@„[0Š”ÿº:ÑÄ±S¨•“_x‡—x	‰ê·;_4|»÷Ú
-|ñe	Ú×ØŒ½GIpš#ÁG»M,t.ÕãÑßŠ9ˆA;Øİ(AşŠiˆQşÏn‘áÚ4{‹(zƒFùïğróµ	l^Vd  €¼ø—t4lhòl€]´ñ:F ËÏ$ÿA¶ñ~È›0Ó…GñŞ¾vPÆ@ ƒÁ:/Øª@*_¼-M3C$‰ÒğhsäÁıƒ@ƒz0uŸ]WT™3
hÖv”
dÿt¶"B£›+^—MuÑ­qi‹\Ù’ÙÄ 82‹¯b#Àõÿ
HğĞ7İ-h
	€H<v5Õ§Ù¿ıĞ)R-n|ˆyû³hŒz#POĞXj°¢y'ş·ÙÃß· ÿı~µ ñ`f¿E‹UáJŸZú2 ¹vÆFÅn¼¨1/ğıyù¯µgÏ âKj$‰!»
¶ÈşNè‹³7Ë*AáP¡ 	 gK3äÎ5ÔHUˆ+ ¹t¤¶¬“z7Ô'Û›³`°Š@ˆÀØVÄÌpRvØaºÉPv±+Ì‹õµãÆ0&Nº÷gQ€¤$±ÓL#Dé
¨=Š`£/U‘ÂöAß4İŸ!	uöN&HU+âYH±›È`…ÿ>µ¼F€>%C„:‰‰ ˜/)·•Ûc¶7ì“æ»tjƒ	0âàX0É@‚rÔ‰Æ^çÚgÙëD-(Ë˜¡%”Á3ÌV$'7›½ÁÊ‹"O9ú½§µ- Óø*/c„oD¢¼}WBxĞêtH˜-fÌ}€Ö)"Pà~Ep±RµÖ,;˜îN¨7áNñœ„#vÁ†u)3ó7İ{Ô	ö™ĞADhË¨0Ê$§á æ1WWG A¢O¹TK{-ôÌY‰05Ø†‚åì÷´Nq&Ú xu	uU¤
=á‹¬[øT0~nu&€Ï—üˆ”Ap!6Åb,yĞFÕšî«´RR#Û"BU=À'9äŒ¤ ´îøN	pt¾R_^t±YléCbŠA&gš1ìÒ’%/¨öFù(L&Jüeà]uGŠIië<ìªğš<-u%Ëo\ˆ!<]æ8FÿsôíÙ¢B);ğfÀô|ğ‰Î ¾TÂ­^,u½ùtyš‹	gç&,"	°ÃÖ³E7ù ÍÙyÃP»„Û²¶½¥ÆGH@;œÍ0‚à%!HW´ëD &l	èë¦Iz‰d‹§d¼ñ‡=\	÷¼Ru xØ<‡¿:ã[ÒÔ}L¯ ¸ÕUCÈìxİ~´:ÃÙHÑô6sà©#p<\pÇYŒìj‰pl
öaVpÁëIÛî0«
oèë-$éPö–&´C¾ë(tt€0tèEB 4?³;ÑBÆ,ÊófwàXN~FÒézTûöˆ/°xÜfûçb·¨t¢´ŞOt¨7M@Oà ö„ŒtJa6ÁAô“X>¹s²KØ¤gûuÀúƒ¬m<ë#^ûëŠÇ±åæŠÁt y‚‚\b—ì©^q0)pb·(—K5¶±kÈÔ,k€Ö>#SÆBïßjƒ¯İ÷<¸AÕm(ênos;·B0-4¸8.‚d&Io¿øÿNÙ~ ÷Nô	×è,€'İÆÿV¢Ô{Vju²Po-ê¥ëYÿFı3t¨à—ÿBŠn¿%¨Œ×
“‹BÃeïÄÿJ'”8Ğ·ÿôÕ@ÕfåŸŸ áhŒ²	%t÷ßníëPıËÌÌ"kÍ
ÔPõƒlĞ@)~ŒP,aZÛø(´…¾ãl¹>HĞÅ@@hşğš+â¸à/QÅ‡¢¹»*¹ÁV0ŠÿÚ8CNEëáú…	söâöFEG+Ø6ÇâDİ)E°eK_\Ÿ»ßF‚A:ëYş„Ek ˆÿä‡†F(@÷Ø]YùÁkÁ¾Ò>`Ÿ-7Ğ‰N@ÃÙ“.‰â²íš‹N•t¥U$Š×âñvé9jØTV F›{QË	D±<Û8?@F »ÙŞ‹ï9óWëG+(º‰b×‹n8êµÛfu¤¶ã	Â'lÕ½T›„{`	÷ Â¢øD³ù~å`¶Á#«<£+	kC™——#[Á·Ü¹c¹Å9ŞY=ô˜ğ ¿)w*”ooòHug³—$f¹Àğ¢À2¸ºzØ[ôZ°)‹3ŠÀƒmf¾1ÇZ€xDöÁî¾8ÿ@4˜p	NöEâp,º-`‹Eø\í :Š¦«Bô-ê’m&*£-.>CĞoTïu}ƒ{ƒ‘NXkKÈ !xÂÆŸXXÃG¾!Æ~¹%‚…óxMÆADl“m;ĞÇ;0î›z'‡”Âè<Š& kU‚ĞL:ëx_))Ù<
|\£Ğ«æö[XÄèØÀoîGnwé‚Ta),Î‰Û»(xƒú@”G’°((NF·4I<‹MòH}M¸Â·¾QĞ„²ûAùo¬x`»ĞĞ't¯%‘A2‰1Úyx×šz--ÕÅ«.SµÒV°#=4× G°eĞÁpô-Ğ—QR„ÒXÖTĞ‚ À‹u<ª`_ñ¹u0­Âì‘V}4f8µÏÆënOÀ;*¢ŒğÀ^˜ë}Føë¾ÚF	[q0V^€`šLêüQ2•ğÎFÉ±Ë	½&…½ğ !‹UÖQî=‘in ªåF.”ˆê…ÜˆG}p…u(Y¢lòØÁ»ÔÒÊGÍfÛ¹¸ëÔÃ`½³@ŠZì™9Zé€.ÖQ3Ì'
IÍe¡³I@mÎHàG=utE)Ám3§3ÛX\`«¾ˆ¥<ÀàöwFĞ#	9>€Nàˆn\MÀVŒ-»e]³¼ÜR,À¸Ô¥èt2@8£Vâ…â,Û8™›Æeİ0…+ØÙ2,ä6VÉÃÔ ÙL¸íëHl"wÄÜF1° £@, 	p„ˆƒª^†È#dY#ìè ğëHÉ8ø¿ş†¢¨uê‰Á¿À©Èï ~«ˆj	ÇëLˆğKW3ÿşş~|-¨1t0­EcGQæ“å“t5B°¹ày“!ŠõÈëâ¿©8Xww¯	tXq‘êñ!§<ñÏFÿ¿¿ÑT"KkXè.ê‹½"h¿TXÅ·ƒ©¿òr¸OÀ(¿)Ò•¢Ç°¤ 2ÑÓŞD† pó.D½P°gRäEP‚tgÊ53²Q°«‡W9\Ãû=2Ælÿ~ubw&o(AP,ÑbÉj0.á€*ˆ…M5jŒbÊ@¹ğpA4½%,d‚×Ñß•ƒæ09ğÉeLˆÖAƒëY´ ÃÅ”jÔA‡>ÚÈªDğVOI¢Áî(Î¢ ¼y‹ÜX m/²h^#û€|æŸ'ÊÁê	–1höÇxÓÀ!ÙlNC\ÀÄX¾p+2EÍjuOOQu8ò›½ç	2ó@	eÂBõ@H`#
°ù(€£Hú„
uš\qézÙƒ.ÆGpßd+@(Ğ”bAŠeïµˆEènø!jÕ;:X·Ø †àÚh	(ª&^ 2"G”k,”ãîĞgÔ~)j÷PÛ$Ù6[¾§ØÊŞÁØèt«LûofZüöBÕf…Nu­<.ş¶ÜfF‚ÚVˆnû¡‘Âbİu|…tĞİÙHzÃ|"w1ÿZÁ n¡9E~áı¬tuu)è¢WÚ<$÷¶•Îm8@äào„;œÔÀ-¶EşB.¶µn²kœAâTC°ï…iPî9Ht£4-ÖªÄn§`¢ÛEº‹ƒpë~Ãx@·Öİ>ëÂx”[)ñØ v¶°x®·Ûx‹{ma˜êZşiÂ°àš:a§ÁĞŞj~h’ÈXWœ Å	M“ªÁG‰–è–*·|	l5k
A‡~CDĞu“ˆÜÊAÛ}ûuÓ9úü‰Ö¯$xQG¨	'İÚn¨!À®x)÷Øœ‹(–á¨ËÉ4ıí­(Üù°ÜÉÑøØÈŠçÀ‡Œ:UPzÛ¢KŠJb¡Û¦;Ğ¹jæt™VC––Ì2W\“ì'6ÄD|õÕwuä‰pö…L ÎèM	ÊQ  ;‘Ë3€/ÃÚB»¨ıë?H‰ƒ‡½¶ÄFÈõ¼ú€›*XR#ëğ‚×QQpVp& Ùë2}]ì	ñ‹=„·³N/àAÜT™İCªÎÄNsÎº)¤ê=Î}$ÆŞ“‚S@ }:PPdOM÷‚P`ƒà0‚ŒuØÆwìë7‰ÃƒƒFœ6{Eæ´D‘S4ÏíÁæç³@÷ÇA”Àª Ğöé¯Å
»HŸĞÚM(
ZPğÍá	Ò[[Å6æâÄ“¹º-€‰Ù‰óJd¶…Ëo52‡ÚRLótnmBy£PqÚ÷Ú¸7ŠÉ†tgk~¹(,ÅÒÈ\×J¹%PLšİÛÆ
| LÕ™$/¡“ªd¨f²V¦\ÿ”  K&7t¢9½Ó,‘!X (£«WÁˆ>ÌÓ6]†1ÒIÁ*
ÿ ÌØsÆ¸Á08ÎÍ= wƒ ™å	h0·ƒÉ±‰A»CÉò<·ÎÎñ5 
ÉA ş¾ÈGª·XŒ«h5ê»dNq[E)fUÊUÜôX[€ZGù’OÇ· [8ÿÿÿ) usage: %s [ -C config_°ÿ¶ole ]qm mapØÚ÷İv N |. 
¿[`·?7s>b boot}gƒü_deviccgClrÖ=öLD12sF6ií•loader…d ûB¶ìlay;—#tëf·6œäve; SíÚe=pP ƒ½µ·x$ÇnorÆrì7ØÈ riŒw"w+ıš‡e£³LRwîŸJØRd7-I nameÀFÙòoptisgà	Á}İ>uU{Â[÷aB-H	 iUtalmí¶JlCto aciB ²¿P»ásc"íAID-1)2×º¶{A /F/X UNK?~;váque/7at9a pard²×¯6Mmb
É»r—ex”}¶ÏĞà§ Lcv…Â“;T hß”ªliZìV^dd[5{n2ÙÏXHDd†Öpmp-#A*­•›qV¿¿µ.¾V.¸sænf‡'
È Û_1=0x%x23 ƒ2BCM-ÿ·ÉN`
CFLAGS = Orÿÿ×iWŞ-DHAS_VERSION_HKß(R2bb920ú0ÿ`{8_BDATADSECS=3íû`EVMS
IGNOR+ƒmPEL	şì¿KEYBOARDmE_SHOTÛ°·ÁP4S16mDI[ûdoCRFSWRIT/BØíö°LZSO¦_C¼IN?Ù,ÃIRTUAL öxMDP/¿²A[¼ğÖÑ/  W±houJ …BÓ‚-pu*~­…gÑb€%d.%<]öK¾eHeòsTZj7–clu	,fy¶ğØ¬F$'MaxÙub¶j· DYuˆ½AX%GESŒŒ¼]ãc=, sil7;›fd»‹µB>ÃSCRCy³BÃØ _•T~X§­öî/etc/Æ .Œm—j¦  •?syµ)û­À‡purYAbBCdC…ûR›ImMPØSTxZ cF±šÿLpqtVXz ¯D ÍÛç¤  …-bX°YË Ší[ƒ#µRb:kup ´™ş¥w|n raid-a-»ÔZøR b_sØcse¶ÆmdTRO¹pPğÚ&©º«s€hÛÆ>p ° a¹´ô„aÇno¸­É£twy3
/›{1î)Nawd -·âÜ$RZnj%Åmod09PkÍ]Ú…-11S5dzÁåZ8Kpo* CÒí¶]¶yrìh/(CV19+¶·Çİ-8 W"vAlmKbÖJ›Ùg!uøvo»	¬µL<;9g07¶±û Johnff„n52šŸ 0511a¯µ­ÑênyiŸ÷8B[ºs˜e83Th¯…†Mgnmv”©isŞñŸB>UQK¥VzLY ˜:•Nk]¬ÀTYò/fñA¹n†msŠt³
dŞš¡´{b'–ïÁ±TnCe PLÚ ÛF‰[(34u	)Ám†.ğtfDcÆ¼fr[Ko2,F4­]ú COPY·G,ŒoØk¼pa¡t‰l~Ø. Segô ÖÛ#17:ü:34éGÁ8dËBÒ·m Rpnogk²´ßlOL¥»Äwf 'á',lúØlrL'îy´so|ŞcifR{u—ebdËía mÖn:f×›‘Zisô˜t@ıØ®.¦f¡nsVs­ñJ°J÷mVR»°G²wò)13Í â.#’¡£ÌÊcÖB¤ÁĞØJ&j H¼!ëj­´c ÑN}cy¤¾µìÎÓOMETh´-CÒåb8µş+ÙÙLBA328›»m­p±I0'Š' ½R{¹Ë‚ÃìÔ2‰¹"<š:˜L…zSBÄ¬ÅœkAvPh9íe+İ†00/24ÙÖÜ°G³ÓkZĞQ
l810#¶m·FyÉJm.;O;lF32DK¦›é2Fn÷¢bjæŠ°°Fæâ`4Ñâ±méED'6Ø%BSÕ©$Áá¾N;O©ñ±p;=s y• ía¼{ïqáNUû6ñ|m„/±/" YyTtB#¿ˆNnFf0)Œw£@ƒÃ€@ÌÆ\;p9 ‚%•9h3Àš½Bñ†q¸%mdÌ4iX£lÜeZD­uÛR†k<vŞzì›KX¬sÛ0\d#d¥Øá7û#[Øcy]` Á8Q*k§ÖQ¨$W	;æe‡-’«eûÊPr‹¯fİ‡šéŠÛAœrÒ9æ-#.6°Ö6gUÂ('G›ÁIH[Ešhn·µG8‚lttfŠÔhDL<7ì@lš±ù7^7&NoÜ6ZEâP„QXÕÊ2ki@ÂÑ¾]>u ƒn·$=vÒkPC/5µ
 =ah4ĞÃ'sc¯©®èüat*´çe7ìsµ$©E|†!»ø§ TbÌÈu'B!»®I-´{(%AjéÖH`¶Øo-Zn¬opsYe2vÙjg'[5L¯F L¿©Aáı(>15M)ßÓ«“ë$u KËãNƒ	t†O{¡n-AZcÆ ıa
Á–hœ‘6QL˜±—BJ0â[l^Ùø´p á¾Sf˜÷1ƒ·êc´dK³a°„%J'8`BqqyDşÙ%iÃrF%&th%’ğNœ†Í¶ñm™Nv˜«M3phh))jŒÙ…nŞfkltfvŒ°Ç ¯¬-ls""Aõn´Ô©cÎçaXĞÃ5Ñm”ï½-eØŞ©•ÅN<Iì£8¼.x,%">Ï@Œ.h´èf…t! Vù…„ç™fûUŞ°Ç© áq$«F÷ÛKŞ8R<\ûL ¾“¦i¿ «Ó5P ñ‚2Nš‘7»fòn'|qºf,¤Ä?LkàÚÌ=¾|Oa#˜
<ŠŠxz6÷GA¿kfoÆÖ¥!n(¬¤ÊÕBÂ%“ ®¥ºQM¸EX
N ~hx©D	SK ï(`4x);½IÍUöS ½hë "È"hiHnf¢±K9Å`MÈI÷ˆŒ 7ÄhO­µ¹Qœf5ëØ-deÕ4M'M+:MàRP‡ÃBl éâÔf”Õ÷×æè2˜@Ÿ?IFQvÊ4FÓ¨KÂ‚v3øfN[6ãRO!nËvQ4J]aÉx‚O1v5#VµÄ21uÕÏaäà,Hs'‚‰07Bi0M`R­üZ-B½{Œ€NÏrç[a¨ä€K•—j†vkœ @80[2¶U’¶):­sBY°.ƒX³,p‚Çlu†Z"{*Ì${°Ÿ‰f­x: ->53ˆ59xÛ¡::q	äC*g à>`ÛırÊ
_I0X’j½SZ=IpÚ""Fn)C˜º¶½-HlWòaOf*|C_ï¯Synˆôšmpx^:ü8u)¼bAÄ;¶pc ±i§•#W;o%‘,°xµÍWíå¶†’@»T¼MtÀŒcV„*¼*ì=×f_Éò_->eœ8Ø
†e±“9®&&Ôõ9wŒÎ¹a]u »e0$šº i¬ óŞ‘s>6&ˆ«6Ë¦éèú‰'Í¤Ù<U‘ªÜ6 æ¿Š°‹Ù³M³ÌãaˆôŒ³ÈŞ	/¡ˆÉl°ælğˆW3[Hoškˆ×°lº®ë{T7£w½Ù*ŒQ7X³¬çşMV˜`áKaÂS¾£1Vú7«a8Gò'³xf"8ªbó9Œ\4MDüİ¢5ŒÏELMIXánàEW	© Ô¸"_m¬BoF°Ççe«%.„Tâsá¬›+Me†{'^=U•±È_{Á€°QSñf“@$:.o,ñb!²4xôtqp;˜AUTOg wŠ<äàéZ]6‹#ßBEà‡HR5„'N˜u\cÁì c_ç,:S3Ahº.BY´m’àìÔc±Šl¤.Y€g§‡kí^%Î?'-%‚-Œ0ÁşšƒÜkîë@…*Ò#Ä¢œox.h¸JM€_{:[†µök+Nú vıFÊd1h0T D#[K“iq´%°È*/'öAw(ú)cfx&+¾
Ú²©ÙRÇ,ö’¡%œ='ÃøP`0l-%eÑíØXÍ',/'UUnÖ"ğà#.„Šµ	ñßìP›X<ÓÒ*Hñg^m˜Šb±€Ûú:=ŠR“m´`_.]xhŞ	Àev™læÙ)#<.9&N´²‡vñMñÁ„GET_$Y_INF*”,Y:Óhö#CqE§—’»KOgm¸»V=‚Gg	)'Lˆ˜ms6£-{¥¡ÀCj  ÆY³ MˆsF1İÓ„˜WÖç€-ê€' è-´#Ùçy ìtnrˆ=jVb¦b
ïkM¹bĞ„Dº.p¨7ã ]‹™CœÍ&„ÃD;tÔ°Ã¥pH'e¸_cn ×/•PaeÉ¨dI+#Hp;ª_´YÜêš´fe'Ò>ºDI¼¹¯sÍEâ,½±übĞ¤×Øa“=+öÅd	FylÄ¬¹ÙÑXvğ~h'ßc&Ş!! );¡ëâk±fB¸BÁ%:Ç¥w,…6s3]Ô_B.Ytm:ô>Ch°‰=?†öbÉ–e&<0‹
$D¡_ª–İ¥Håks
4zGÅ‰¹>0!’Íş½[^J§ø7¬ÎLw+,=Ja§hmsšM(¯a½'È;à¢˜„Ñ‚p`:%%¬^š# MÄ³?’âB*æì°u©A.wA¥ÇV)‹@ÙVêğ;D3ó DL¼“Ø gi e‰§a€ Í¹2˜›s*C9fÊöˆ¹ÓØm'ãZ„hÒVš#ü`.Y²ö=H?Ğ ÉA{ùqàâgmÚ*.‹Iü ¾9êÔdfŠ‹%Ñ—Hol¥UÕ &(cêxˆQ"CúrÂ£@‡f:j]7c'\YE"j(k-m–*MÏ‚B³JM³ CAC–±X	4DÀ½ Ğ„ áhV´÷`9ch•«óäû»Cjc²¯T;(÷Î 3^¼·%õ",ÌÎîsV?‹ÀfMÂ³!:?UÙÊXƒØB
a`.ß\;6)?cl¤9ÁA‹l`F
d—ğ3.())%Lñ™)"a¸… zl‹Ñ5½ÆJ9 ›Í ?¥v¨Yİ9c0
5‹H	K!¢—’‹7 –`7éP‡É2x,ÁHÒ¤ÙÎI”Âf|ç,61aXšch—rÂ¿ìSt`3a$šµè'^0˜;\°²ğ28U²ÃÏLıœ?!? ¸¦0@( !|¸ªêaj3Cœ¥İ¤ Q_Àg›IèCTLÂ¸5jmY%š;û%åVÓ“nH‹G-6`@^d~#xBÙ‹I%.4YjÖH…tš{K`'<`Ê.oTœ‹Âv¡wm cğvems/ƒ_P¢rÙc„LC`®-¡è5ÿçÆØPı! ñ†A!Ğ	­ld'tfêä£¬ä, ci8*‡ÅMÜlC›âG:“	7F™fò†$¡Ş_šC[kC`W6i>FS¨#AsÓA	Øú_UNbK
74`€`645’ÁG-ß’ 	ÌÅdÃ3(9ÿ¹áğFId°î…ë¤!ä¥mM0›¼±Øl/PVs'ãE›ö+¿·
§šÑ¡0©N”SPÎ#_µ/Hv*3x ³èäñ
InVES¹Æìğ¢ÜôV(ôhF&ğü?½	ÛÓ).é*:F<
GĞ%6°ˆ Ì&ÚiúFŸ l{OÈó_‡QC·‰IÙ¤°‘Nğï)3zaªqeyÆ˜XL+©ş)±¦²±h¬LïÑî	
Š¬m%àÃtÃèEbwi&íµÙC‡ E`Y|`—ğx-£µcTÓXB0Â…'kùµ÷½Ùn_}=‰¡ÚRûg8âuºZğ6>ÿh^82ãBì&Àò.%5…åj-<dMR)!ûH6S†$DS¤€âr´^ÚgN#CESa´Ïa\”´ •¡&ib<pµïs~Íy½ HĞ:s2K|`M DušİØÆŠ"Å"E¶%L¨
©‚;£Üı$
C¬†,ü¹V¶lYp¥p4€÷
r;n	 ÄÉq†™+™Ğiı€'>^ïB

 ^„aR*ˆŒ*Ëı³Bx Z31	p0t¼k<M ã*q¹ÃêA(N.$>¢TVoñA„šsçöap9L:¹4(NFàX,=/EmiİdXa??)G	Aëjr.ÛPD Nüß‚±ÈgZ$[3¹­³m5n£,l2.ÀGDF½mÅPRQ(],Ùaë'HJOVVğÅ*VÄØQè­#Ï±SCo¥th‚dMYr¸va£lHM¤˜J—F€¹DøJ	96ÌÁ0/HPAC`&KLàuÆråŠxSDl­2ÕZªÑ`Ñƒ£
$¢ğzÌä?Æ:+8'ø'¿'md=÷î›:·(´¤É)do5÷uõøÆw^h/¥Ä…| ”  $L ñ¡ñº,YaßèÅ!Åf}E·@ás•md2ÂÖ8	/
fj73‚ÒHˆ ?úÈAÀ&ÆDBâğ$"12Êã4î	[,)S¸2ªQKknoÈÜsWƒGPÜ›,ï%ì"EÊ)› 18L§Dà„Åú"„et&ƒpb]ç ÇËDïH€Â‰fç@UöoöÀmD=255.ŠN6‰sŒ63x³…Ô‹2u×¾P.PU—6ÀWğ‚Ç%'î †Ìƒ@tK:w5(p)UÂ`ì.Ü´½wÒ,WóBÉÀêñRm™c.^{¡œjšhGni¼3È.²êr.¯{(™s;jËÊ=`8êª­°pEhİT10BSZl`60mff GAi¬0+ƒl
ÂÁo±ULLŸNÌnXhÅ÷ÚlMBR‹œ#Î({1ƒe1¤-À¢ªNi¨U¢“Şºq€ºBc! 3í½ÃHoRè£fAË¿AøVC=SAFEŞŠm»iÔò'F0IÄ„.Àa„G´Y4ƒŸIwªÃ>³Æ! ÈWH¹oÖSá7Z "@÷šp,2'vègo©xXRÃ[rF³`&V$†Ğ ¼=¡’"°£öjV1•n€µÚóÂƒ'ğ &È†t="CgHp"	Ã$;X–iÌ,</f'äÁ‡–µeXÆ$I•hR_7§e‡’.Ñ4‹¤\u6T·úy¢ğ8œƒ(mjZo!/lÖ@˜¢Èw!ggÁŞM91,MÁ‰gÆC%À2‘h'Faá P±u§ËËhRŒÌ(ÑhÙ; È·'0[Vl"#m.Í_ëp-Ø,›ìŠŠ¬à?$iÖöÍ°Cd+1)^IÅ-?zoÂ,éP °‚V‘gğ¹Ù!V#fóÑ†	EnyL4bqêAÇKÂ\Ô¶C1‰aåÌÔ½ VfL¢d+/	&C&ÿëİŠ‚bÉNæÆ,!$Ìß–Éâ#&rB ÁXäSº„ØÂœ¡Dñ;,‡Á2Hi‘;ôª @¤¹Ná H£L¤3O/õnsÅ°2go-Ã¾a¡g¹ù8†5xeòÿ×XB³(–„!s¥ÛCvØ:ÕlÃL4M- smÁf#3v[ÖD²è¹Æ½ZA(-‘aX`Ÿğ6M.AWlÑ°TOêGDÄh6?_ Ø£Itq˜UnÙi$2"†P°,eM4ls3ûs«ÊŞK{Ÿ¬PÂQœ.Ï#JÄ¬ªt£@c-À³ 7ì0ù"8q‚'Qê Öe…9H4äch—“ˆaTÜX[NVêåí/y]Y/n

Rş2ÍN¤$ÄòØ`®¯,ïn
cãpj­ñd!3yÜ`/šü³ ´N±àpF–t´ £)HÖ,W4Wä–›ƒe4©GWùÔ½5'9NT,ã0†1é˜XPlØ«&YaÊ,éfU„h.ìŒ'Ê±¬Ò>öŞïd-95S98ZjRˆ–
Is×f­ãs¯%Vt²ƒ? 2f…‹rÃ(ÿ©f]©`môjªÕj/úÑ„b°½S×Ìt.înQ®l: ½ÁÖ83Ë0f¨yØA&¬S1d0!‡|r1hdts‡rÈrqporÈ!nmlrÈ!‡kji;lc•ahgòìCfe¸loŞl™«v!:äÉcbaš¸:|/U+8ÚÜ_4\’MÄØµP„\Åu(ÏÀ%›ê=0J -ª‰Ùs9?JùpcÙšœd•vƒ	ÔCŠ‹ï)ğ. Ù «@@Iğ/zär5I®*0@‹Ü©I9¼´Ã°4<¤D.uı  ŠÎQpôÃ+fDàNÀ×±0nk.!T	Lå‡ÏÅ({ÔCˆŒ¹¨#fÔºeŞxD­li ›ä:½Ç4oâ>,x•(:
	H0+â
«AD”uØwnmFĞe-R½I&\©‰$0 $/Hx€í…E‡d!Ä„ŞÂ0Ô0²NšQ–àv…QİD* ij‹0›ÏK`m-”£G'¯EØŒeI§'uƒ° Ãl,\Úˆj!ÅórÈb0y)Uõê,3ŞQ²à5âpT*÷boÑL˜3nSqld®&%¦Wv eÄ¶
E!±ÈZÂDŸ9{ªİ{Ş/¢]èzãf_Á9&×_ñà‘Lã
Å,N=ËÑÔ›ÍªØÕGbl+ø,ş'"=mÖ+GÓG-,%ìôbÌH ÃM½4J!+5Œ"eò;í»e}‘à,Ğ«'^¡-Q²Lgued®[‚Ôöl%—Ö2Ğ°óu~Ğ„U©Ğ~šlÙ vˆiÅf,–@Èbù_.‡™˜m¢e$L	Ïi–BÊÄüel
s½1 Uá‹Q+-ûlp8¡;'ı;58z¶ÿ½§%=&¨ã0\Å¤L±Ğé,Ú{dS©ˆm j2K s×ïl%LOôD+w˜QxYDsÎ
&‚Â:	 V…Ó*—°~Û VB1¡ã%jVÕö‰)~D²gÁ¢ÓG„lÔI=`³œnÅMÈ=¨£u…àÕİ'ºX@l6„H.fÄc!šÉ[ÄÂ…‹F³BåT¼jıJR1›á¨à0@ÜnĞ–vV±«BP-_t~#¶=€< k”t D¬{jÃFâ,ÔÙIø"%"oõ€fEµÆ‹šâUl¸/hÛ#hƒv,CEÂ	¾30˜‹­mdTÍ:Š`9ts„bFŒU*0ªaFş–û-(ò•r)AÉJ¢uÄCzÓ¯L5Ğˆ:½E¶Ã*ö&ëÀ[Ø{å9ûöô6Ù›)QtHm„]d—XÀŞ)\„F÷ba˜Xü(ìoëıs>vÜiL\–dÛ/,ï0's5	† U¼ÇC«;W3„*Ã‹eF›@Spø­ ‰Ü`
d½ÜcEA(FN¶ ,«zÇ¤SX%ÔK:%¤X­'Ä2¢’XZ’¹B(uÔY)ğfÑ®KlX=$Å@ûT fĞ€û)`²6{M8/ëUlRÌĞ]Mé€·°dƒ}#=ë`¸²#F’<ıàŠ—tµ
˜Œ
iÁÄC,â..¦o«\Q}Q¼fŒ%rá€Œ“ì.´	•1ÌÿŒà]§7ŒiHŒ¢-ó],Šæ
ÙùÜmŠ…`$—‰kT/·Q©\N/(0ê‰¥‹=p<Ì‘±ÏÜà"–cJa0ãI¹²Åƒb¹ª½Ãc	$ŠE´ÀBc÷Ù" sŠTyt‘0xA(Ã)7AÄ†~A¤„èŠ²dï%$X¶ ÓœÔaF×÷EAYğb@‚1CôfL{FjTÈ&°2wØ ›¦‘û_ø`²Â:º~d.«‘Í+s!+Í¨»ê4BŞh¥iosAÆ˜cbˆ-£Ï 	rˆEğ„zK˜Tó!f4)Va$bJ«8‰tH !S`Ğ¢ïx
Œb¦f]Å¤ãg¿l™WGDÑ«I™A‚eIOnõ=‚€%XÕµˆb­hÈc„cÈ Ğ@Œ	rf³ªS2SY6	Oæ3 ÎŠuÖbdàA†û«ŠÃ›oWORDR-¼3=;0œ\“ª­UCTšP5®í
r.f-$êQ¸(HĞ=†©ä6©pä)n	K¢IrÁó[F°gí Gª’€F'-¡ÖˆÄF'®(Y= Fî¹‚5Äfy	6P
PÒ? –2ê$p5!Û0Qµ+äÆŒDöˆ*-9Eˆ…/Å†âÇTçLZÙ;bL &86Óf$x†FpfÂ
ÓAâ Pu-Uq/ ß’;@g wà'Û+„TZ‚Óm5€æ¾s½‚`ép÷nÖ¢ôC!ÚLr³á÷wŞZ,à'™<€`Ü‡kbv„˜PüÆKBfFAULTXÕ±$8q‡ISÌ=xß2a·„y`vm^#s+ìVM\Z‚Ò {.Xn±`ÒålqÅ5äal Y<0J_Ï,òæ}‡aÕĞ)Ö†X"IRšàäNÅk'ÌÑöI 4×¸}e°eÃ-jlHÄn|mÀÙ,y=âSÕ¨MrcÌ2U˜f©oA²/\›©i|ı/N3&c!8ö8ÕŠ7~Ñ=X Î0£º
~SHS-=¦–_‡Ò …A‹¤ŸLÃ¨ö­‚-aSTRO³CgÈ&±‚6ğIHğx‡	(pÑ¤d´[6 ö.)@Üjš¦&+?*£4sà%
$5™Y?`5s~’láU'!T
E¹ÁÀ+Ö¿ØØ©4ç Y"ów ¯Wk¾h«TR­Jïå”µ&bcUp œ…f«^-”„Ç3æB¡gTŒ³®’=º’ˆ‚kÊƒdö£¬j.ç ¡‹`´pwâl_¢Ü¡ze_nH»°Ì¬ì b˜T}8<> ˆ“˜De Í ÷IÁ	½BbTG°ŠÌ`FÂE€	÷¥†pY_n›`6#èÉQ Ş==!BQIè·/nvÕº•LTWo2€duT§ƒC<½p†ğ¾8E×b¸ÅŞ,Øj¼‘xnYfv6İ1‚«§-)I_8]	¶œ£4cG±@F,b4¡l<S¼
'0=
’
ã~ÖS`ÁDm´®¾˜µµ*\ «pÁªuÃjíQa¨úˆGé
)  RRA÷¿ ”ø„V+(CGAö*`9aXäãLÅ \cˆÛØ0oF'ˆVŸ!¥¥'`ÀL#[kAl®kX¬‹b¼m%@¨%‡‰<,Úƒw(x<JX}ıTŠ1E"±O€€1ÚäBPWe€±Bne¸h&hº2~‚T™ ˆ­€Tº Á›aåV›Ö™€`.)å€50€…ÊšéU'qXÜãÜ€° -;òŠIÁ\®eÂ((2)–@ KıIŠV¦ÕcÎŸçÊ;Aú€b~_›ìÅ‚ £9«¿‘´ÂS/N™i5Ãq¡ñh³Ä†EèP=`0L³)íÌ&âÙ¡ „ª0Â©ƒñp33jÅÁM='¬0'¸&•±ÁiÆ=\|&ˆâ	pk¹×{	A- ³X\‘i„¤lNb‹GR{VEğ éQÖ,¢3$†my¶²%˜u6 JÉB×u xÁqå(x¼^^&‰³
ÌÍ” *X’¢U?£ÀBö®°oƒjÁ;)Ãë=)=Z
	….-Ÿ­a´-~úÁH,«»C;{iVS¤I+OUT¯4«Àñ20úŒ‚1ÀØÜ •‚KX±õ‘ØIˆqB3‚P(Ã>I<0-3)T­ıßdX<.>[,<bpsBûàºaÁyé>] 7àj4ÅD{9Gp­ÌfínØ„@7Œ…F¢şNöOÀŒ/NhEœ7ÿ8J`YÓ&{+z½2IALgP¦e„£0Ñş›ÀÄPRåTL,„–0[mLAYY˜à‚Â¢Z¢Ã
Ÿ-Ã<TÅ-¹bÅceÉ[L¯‚Y"ò2Š@Ëƒı¡k£nâ©â­l)L©±… 1# ¯ˆ!\Ü{ÛÚœ59:Á39.5ÅÄ°‡$AH#l&\@ 3 ¡`ĞÄa/tÆsYÕµ³"¿‹ƒm0Ìr'w>5)`1¡¿c'›‘Àx°ì½zpun’—‘°höGU®Â^ÄËE/8+5æ^m"ÎÙ"¹z I-s"úÍ´¬5Ñ85LŠ(¶ì&t_Ar†Ş›l«sckã€¡Ùf+‰¼!¼Ù}::,%9(¾–Ğ%ôeEs}c5ÊFƒ_L_¡1¢YÂ°'u$4”-@'i W„²(gÆªf‡¥	CèD3
¯±â‹ô­ÂONLYè_™Ò¡&‘J Ä­Tw YPÉT¹~ñÁ€Yƒ/o--•sÀBÄ=}UIDjì0Š=>''µ¤˜I:xaÔRø''Ñx‘ã
;ø\ÂuW-ïõ³ 
3Ş4cªöƒaì vs«êh$mŒaCª8a,Ì¼ Öª^!‚¿ø€MÀDüNí³IÅ2jE8’3´ @çTõ_oRXÂ*4e©‰ZÇ),Vkj’Z…m)$	&A`A–"HèvmƒÚ
ÿ9Aƒ3PB³SªD5ÂbD^…0S²6BY½2¥²T,œ“˜·cfLÃŠ!8".·,™!Võ€$Q³7IÄ ÉW˜sˆv¨(‹ú¢(Ä,Nc½%ÄÛrNG¡˜="€N)7d{K’³¬¬²0.,Åi Q•mNñR•7Yí É=2,ñ {)Y”DOCKÚ¼FÕF®äX {éeÜU»¹=ã .Nõ"ÄiH¨S¯6!$Eá¨w5¨3‚ép}”wÔ(Îe¬CæÚ‹ÕSŒUlV°lrp%avw+n Ñb-%“£ÁEÿ›_İú9¢7!ìƒÈfäLÜ(`M“huc†m½ öj1FH0²•&DŸí•H-#ÒT6ö*ç	)$3C±RrZ,ÉÁ°h«é¯Å4Â,à©Ù† Á°âmQF2˜t Ûb 	[Ù"X1,Y‹ãeÂƒKdquo)dz%bdÁÊ©\¼%(Š’QŒÄœwW\nªÍ¨’t\t~ÅÀ²…”NlQõØB>|pÖí\-§ T`n \WB(:u
A‚õ¡ˆŒŠ‡­£×B¶,nÅ0N f8b´SÅ¦ø.±Ù‹İt
×°({˜o^Qì½³9ZCš‹Å(™˜Å¨üäˆåXm  ˜:Ó`³1¾$\ÒfİN•‚lÏ:Í–Uñ!£3Ú3í½½@Ûº©fÃ'ĞÂVb-ß.HˆfÔ´aëAj:Ò7\0!bÙ ÖlØoYyi64QV"¶n_}©"„Í³s¤H?br.bP^Œ‚ÃJ¨%„`b¯	a°$YF¨aFQ˜³;ˆ#A^ TÊ.!A¬XA[HX0£ R»fP¯‘5ğ§- ÛÁUŸÜ(1-:"h¢aeËe¶¢Mvx0 .]aCt ÿPT^¬p#¾#ál×îFæX%Æ'€dT*æÒYğ|M.ÃbVÍÚpæ òkQ_T16_K	32îvXFS8OSC4sD}	^R²¢±2€dEmcQuƒœ÷*QaŠÃ¥ÀŠxÄ:X´×
+,Òªì)p©°:9Z¥d(t::b‡€D®^Ãf³‘!\Â2±óTa3Ú„ˆˆİE0©_KÃ_hi…@­Ø*¥IVle%8QŞµ€@†A3 ]µa!`?¡eE°€Lr[k,BDMHEPNÌ a…¶pÜg_$‰jû=«J6_¿Ş´xq­9"–…`d¨bP²C[›İZ)ªON=‹D;$ln;Ô&$C†f–¬MÙÆ²otµÌ°’	$²èØ!7ª,9NG`HÑ²E¥ˆ`ìÎÊ"0"9_‘#¢©fnÇzÚş^›@ìCbs{ëÑ\°Â)Sh3œì[ØÈ_#SK vYÇ%7PÓXgAÙ.vÛQÓ ¥/j/
2&u˜EÕ[2 ç 2/½LAÁ­¤ˆ€§±ìuHH ¸aÁx3â° ©¢&ŞÀ€Ê­MÕ2Q_.rZ• ˆYzaaRÀÀÖßäZ`ªÁöÅ3!ÁÙ2Î1Ô‚›E¢ıÊS°€cƒYf:`Ú’¿	-å
ÀA‘U_°•Í.(K(Çªºa<.EÂFIB‘aÆX-éo>¤1-ù4
If	Á6`a,>VÑ…¹§5(F):Ü3ˆû*djf¼Iz˜.3f0ã°ZV#¤,dDY„Š÷cœRgFevj„laA˜jÆldÆÜX¬šµç#6Ø"M:XB{Ïñ…LDR ¾
=BÈN	[=dğ‡•ªVSWAPS»PsE2
-l9
œBW8šP5l_Iˆ¹àPÛ€,b‘n*9Hö:Ã9d– 8Ú‚¿°fş„ ÷…®.ktlIÙB¼e,(JUË4=YµìïÇ†xæ˜“Ã  	àln€T.3	"DÂ<RÊ'lÚ#'%2	³ÆœÁNŸH›	mdp¸ ¶Ş-j±YÀE”&º9äŞÖfdQ	Œ%7)æ&C	lºÛö%18Ÿ51142uŒš”éŒ]k{ï
À.ilr!d‹x+ ÷C° ,³Ù©Å—	öŞ¬UKMGTãf;Ó¥Ö3u4{cbaokÿ%u , ™8V<
Ú)Ã%¿gXa|C:ÿ`äH:SPCLiLo 22ÑÉÛß.05.13.27XÅ$xÎ$ª±¨¯‰‚ePD±³âÔ¼5Meõœ€£É˜v7»
p ‚P|RÑ,&ìydxĞ^s¯3Ñ Ô\É¾ çOxœ
b “#`|‹5p!Q²Û.A †ˆ©@0yˆa)
½€(‹Íru
’)s+¿cQ0Ñfƒ
Is"CDÏ“1{mk
¨í8ó13;-;ô™V{8Y5	º487÷¢`ğ1
./å@§„è\íÅèNIŸ fE8€$cRzùc!FA
14Ñ4	T=mésÏ¾lbadbu¢g¶_(j)L >š¹Ô?Ce—µYHeF‰†Qô7H63  %‘2Š{ábV€¡¶ÿ·ŒvL$]‡®
Š^U‹…Q´EÊzIB•;PXÆxš×0Š $kXÕ0„…í`²¯Ü
('G3WfÕE„º^.8÷'-@%2ƒ&lN ¯1}
	öõ 4.êRC¶2bH/xØù"±µÙušn*p	{%Úe+2%©¿DlmÃâ-¼Hor¤I¡dkfQ¬êªñ,{¹e­G:k‡L]3¨AËc¢ğ€…d•
zLM“\sSÄšÎs¶øQèl¤fŞ KCŠ“¢º6n^MìÃ›=Ø–6X(ŞÊ
Ş…Sª›\ĞP,Ä8(0±ìUt :m:%lV:;ú4²7²:5:0©hFíÖY,êfò:¨fT«ÍbÙ@ÌÚZ²Z’ÚÿÈ‚Ô^C°³TsJ†–bW+µ¦°ê:È-µVÙ¡…(%²UÂNJÁXD`Ùäàõ,Æ# *#ì‚Ä!  º|¥Î A*E	lÈf-!DAPGaFFÀ*kD.S‘˜u&(ÒHàçÒğ¡ÈÁG  ¥$‰e0ÿg/šç&ÃúGDL÷³I$NFc¨8„õ&(	(DAn”ÊZí’© Ÿ y”¹	PCcsP¢JÑ¡†·šD—ÜgDÉŸ0 #¯¢;p cÂIdäŞ0Š
äŠ‘1FÕM‹˜{j|Ó¢M#³Š¦Ö.5ƒpÏn Ds¦ƒ;ÀŒ×ï%0ğ`F­AœÉ=E–âAŒÂSßªfàÌºÏh!äŞ°báËæfu¹JÄn~¾ï5Ùwp¢H=Ì°Œ:
" ñ
¯0v±âv¬U#64a35ŸˆŞë6%Ä10³®äd482`Ø®µ)56<¶°„L3Y+¹µØ160C˜™h;­©
”vp„
‹
H÷X	„
a”r ªZ¢Xf‚àb C†€ÇŠÚ°a]fT,ô¡1lõTM»
^ PTt¸mõxÓüB(l)¤C(S+	uŠ<åLµhRSBT¬–d E£ÔZãÜl’ë9DA´–‹§Ÿ¢Œ= <">ÏG&V²°œe-¡·È–Å–ª.7/pKÈğ&â‚FlZP*0Ş²66Œ)XW(X~4„®âMZV•H·®AÌ¡gıGüMC:uV/"^‚S%_HPšÆ-Dİ2ûMîjXd ‘±lN‚a­‚x`ÖÜ`&
N—ím5Û€x|õ,zÁ ¢, 3¦»ÕR7 89®yçù12345$İwæ6 -š#HÒ27H>å¶
>^œ«Å¤iš¦ª¯³H°išn»W<2ÓtÍ²¼Å'%Ó4MÍ4MÓlÚçôÓ4Û×…¨Æ‚ƒ.Û4Mı  )iš¦ë/6[`e¦iš¦:>BFK™¦išPUZ_d«c-‹CÌ(ö,h€ãÁÂóWÂV xÔ%"p„Ùr@¥MàéR…©Qv(Y(Ì"xÎym?DN‚ëõZ>F7½&ÛÌAıpLn¶ìd.^),¯‚·Gm+&X-s N”dQEf‡Ş%M1:P€€í¶o–¤Ü"3'h´,aİÛS#zµ7Ëô5‚˜ªeÈ¨¬è |Õ-M›&l¶b{3æzÉ2ˆ1¼Íå•şos&X`ofR:pUO:SoFÚû¢äPu“:.q˜)a bx¦r®Úq
Th¥)r^óØMˆhi HgÄè½‚bÏ*àQ©ØvÄÛ‚¯¯­qáŞD.a“¿s¡p.(L_¯uÛÂX[]x? %û¯ÉMpÁÜsïp$+-è ´¾12Í*Rõ.^K2ŠD@I HØ9 Çbd_` <")“µª$/^ÉÄFFñBŞ²•QÈĞœğ)ca€ÙÛZÜ'i‚Ã„0°;[P½C]„—šƒ±¯Öc.\ØĞsM/yŠC½IôË€Är2Ša‡IöKğxM&ñšUÒX Apôø¤TfåfPÉ
O…B2÷,:Ø&Cô‹êEdy®•u¥áf%]@tMpÌKX
pôwššA!L)acq‹İ áC)!T)íÚí›Q)÷W)`7,6 H*éiN)(H)1&¶ D %ÕlÒlI'
ğ,v
L…VD@İ‚´‹’P)A
B)0%3£  Öu% ı ‰†=BwUL-á9ÉCŸ8w‚˜-TÄ[–„/œ´›EèXE)ÉâI¾`ó^S
p_eµn;ÇÒJççOh¦‡ôI{#
#Ød5+(`:Kt„­]  ş=ù_×KF­,;Œè=Swİ2¢I%“¸Xk®\Øo#< &4K¹éaÑeDùr?~40\†Íb‡ª€½jù-Q¸á²|è„›å&¡Ã
NFNs?LNZIŸ–,¬k¥¯´ ’Éækq3«“BbíHq¿`Ï‚²iš &)‹Â7…)û™P `¶TÅBîå·èº3  OBğÀ ()={+©`š°ıñFÀ""7„¢5=â¦ 0  ää   +y|`ÀØ@.{a!ÕÅ¹ì…?ÖÆF;¿TõGU€ÿÿ‚ü@m‹„9†ÿ‡ÿˆ(¨FAìÿÿÿßÿŒÿÿÿÿÿ‘ÿ’ÿ“ÿ”ÿ•ÿ–ÿ—ÿ˜ÿ™ÿÿÿÿÿšÿ›ÿœÿÿÿŸÿ ÿ¡ÿ¢ÿ£ÿ¤ÿ¥ÿ¦ÿ§ÿ¨ÿ©ÿÿÿÿÿªÿ«ÿ¬ÿ­ÿ®ÿ¯ÿ°ÿ±ÿ²ÿ³ÿ´ÿµÿ¶ÿ·ÿ¸ÿ¹±Ğÿÿºÿ»ÿ¼ÿ½ÿ¾áÀÿÿKZÂÿÃÿÄÿÅÿÆÿÇÿÈÿÉÿÊÿÿÿÿÿËÿÌÿÍÿÎÿÏÿĞÿÑÿÒÿÓÿÔÿÕÿÖÿ×ÿØÿÙÿÚÿÿÿÿÿÛÿÜÿİÿŞÿßÿàÿáÿâÿãÿäÿåÿæÿçÿèÿéÿêÿÿÿÿÿëÿìÿíÿîÿïÿğÿñÿòÿóÿôÿõÿöÿ÷ÿøÿùÿúñÿÿûÿüÿıÿşLtmÕØ 
éo¶
P;@ø¿ëº …     ]­–"Ùë§‚®[ı   ï Ÿ!x	Û# $· &ÜpV­£õ| +‚(Î4ªµg ã½ oğÿ4 5 6 7 8 9 ß; < h´ê>-opƒ·OA Bß DÆ F àV‰G¶¼ J”(P•â¾ÎÅÖ” Qé /pF[– Vğ X øÿY Z [ \ ] ^ _9?ÔB@{}ÿKˆs ‚ ƒ „ … † ‡ ˆü· à ‰ t Œ   ÿÿB@Ì‘ ’ “ ” • – — ˜ÿÿÿÿ ™ š › œ   Ÿ   ¡ ¢ £ ¤ ¥ ¦ § ¨KDüÿ © ª « ¬ ­ ® ¯Ù±Eüÿ ² ³ ´ µ ¶ · ¸šº½Tÿ » ¼ ½ ¾æÀ ÁÿÿRĞÃ Ä Å Æ Ç È É Êÿÿÿÿ Ë Ì Í Î Ï Ğ Ñ Ò Ó Ô Õ Ö × Ø Ù ÚoPñÿ Û Ü İ Ş ß à©â ãÿÿÿ ä å æ ç è é ê ë ì í î ï ñ¿Sñ ò ó ô õıÿo%÷ ø ù ú û ü ı ş ÿv)¬cITZUTFû^<<.#1ÜVİş,M4.1.010“07ŞX« 1"ıªøö"##$ %%&&¡m
[Ø…W(YlGG#º)u:-TTnm0xª 
³mâ/ÇLjztqZ	=W,7™Ã-]K¿ZÜê?|xXûÜFeEgGaACScs`+0-#'Ikæ{tJûO‘·Í„ £¢‡bÄ‘Sò>L(
BN¦"AŞ’á&Ñh›?¯@É†püA€+t´rï5wŠ	Š€Û%›Í¢/â„:%¡h)P&E#.rg'nØ¨I*ÂE^  ÀaTBB<›µ¨€iuVTFÁa[d’eç×('ceiÑ0¨£ÓnÛÅ£JBúíP
Ïv Ak…DİŞÒpXB1Ù¥Bál²IªfDÍruSµA1~y˜ÀŠBÍTK¡”ABBÁë¢
¶°—0mIsG²ˆ a/™Sp8@pÖäØ„ˆB½ahY(÷º,:r" -{±¿)Äà½dë­€’¼(óÅ}ADR¼‘Í‚CG‹ö¹Â4KrğpÂU Ã†¨×ÖZ5ˆd’.  L(Xnà.a`§ìdxz.Zˆ¢ço—½Ãs!éÁ"V4	˜F)8$©à9ÙvbCwŞÆö
Ñù½…àzÁZõmboÍÙb-6©ÁÂ
&)‹<ICiÑ I½ß#Â&ÍŠIqÙà‚ŞïLc 2~#`'p’á
XÁÕ3˜L†NP	ÂUk>ÍÇ/Ôš¨7VaWa"šñËlØ’O †mfÕHÆ„){&É³›h;E#
%»²íótd1cMj…s Äéf£îŒkè-¼Ø¸ªğmTĞ–¯@Y‘L²Ÿ˜ ¤³-s¤$‚‚Ë’6zòÈEµ-tu€wh”%Â=
x3„LÚ„Âá2¿lâûÎ*´s)sAdâ`µ‚è¶Sr¹ ØB^½Ù¬¢¾}:[Âıd£*MãPê€Àh­§€D• Ü[˜f†ra@Í‚ÜcÂ¬`Ê'ˆ½WÄaÚ…Àao~øF^½êQ¹üV†À3kõN”UÅ	 ¯²Üsx
hğÒbé‹Ä
Ëã¸)›A5$.¿ æ|a.ÄMhÉ.D	¤Wœ&Fsß—@6Mé0ç†êªvl–À °ZlY †@ñğE«;@±?wSƒ$ğøeÅ34x#Vô|î.ˆeM³H š«@5”qoXQ2ÇÚ„YÕøJi|’”èúp'cYäDwrX6›qñLjaWd/X’q™DlÙÂ"<H.ìD›fóxA*Í¾ı«"Y°p=(#’8üº2ˆÄÕ'‚‡Ä¥NÇÁÀ=r Z²grKôí4Ñ N+†'0„czISÂœaØy#Ø²æZC°‹1/±¿ú“?!H˜ ˜/e½W,Ëí[ÖUÍ/ciãaì…07Î'ù# ½‚°
8J•¹t5>ŒŠeqJR•FrÄÀTeÏŞT‡!kuäfŠ%Jr`¸§¢©'5h„eºÂŒrw*º
@SzN¸YEj¿Áj‘8 ä¢NÜ€+6‰HüXENIXäc;JÑf/“­I×•_ƒUIVÊ2ÚI/O¡}P/Šaİ$fA%5i¤³¢\~W`]6YY ¦ûÒ # lš?r+t-ÅZÄiºf¹^hr|sr¨¬:=IvM7X†#(HÓ|K!PW}/H7š#^+ee³eƒ?½Y*l·‡Î¦û–w/6¤]÷­À÷ó®¸7/…- «Cƒ4ÍÂBÌ+d“†/I#šé¾ÖO^àê#ÙkWC§»*{`Dñïá€Ç`¥?©*d-T[‡ º …*ñÖ Ëh iù4*|£ĞQo°µUYq ­	*K v w x  ÙÀˆz??¸Àˆ?S`‹¼M¹T:Wò–XºT F)SatJ
lõFebr†Qğ­İyJ#lAug¡lOúv…o¿`c( 0:0ºø– ?'<7ôá¬µé$GŒ¹}ëº¿?(knN>Oˆ*¸ºr¼¾IÉ±5±Ğğ¿aSA.ËÊZ €@?ÿACGO_{É	Ÿ Ègİ'@œøŸÿæ¿ù¿É4µp+¨­ÅiÕ¦ÏÿIxÂùoş›ÓàŒé€ÉGº“¨Şùûë~ªQåÿö¿Ç‘¦® ã£Fu†uvÉHM‚şËÿå]=Å];‹’Z›— ŠR`Ä)JÑĞğW*C¤xH1œrDŠ¥"s[’¨‰R‘³y|LŠêW”æ¨V»nÃ×ì¾öyà€AAğÔ ™;ì
i	8       ÿ„  °9     fšÿ DÀ/İåòÀ€ì¿Œ€áxÿrùšå Ä„ä±›îsİĞH/7¼3ğr»\n\ƒ<èP‚8èîu]sÄ@ÈCÔ¹²·ù¨Áì`ƒ# ÿ7ìó-£? 	}Ã–½#²û‚ "  MöÍÌ?T' &[¶ì  Š°Ï–w  A&ÿ•©{åÃl»r"/Írû#110 153061k6»2244899ûZì÷38572?Ûşæ660 NnOoEe0Dÿÿo3ckbgcrmywKBGCRMYWğvÂx{áWƒìTÃ™aÈ;¯’WòW€<Z¦^É{ûÿMNWòJ p›’W²»cÙ¨{›¯ä•¼¦›ŸW³z-ix%›Ä?l^É+ùwÁM–ÉMùòJY­Ê \É›q\óY’WòÊ'ÛMùMÈ•½DQ;ìzì•¼²~ÏMê¢O+ye¯Ö~§SÓJ^ÙNQO‹’C6€=²§ŸR'•½’W§z£W²¥äR¤³1òJ –‹•¼²WNOß–½’ìËWïUNe¯ä•;¦8¥ Ò rB÷«¼’Ø,ï¥ ä¨ä reãÆ…ì•l¥¡rTŸ r%¯€“<Y“Ø.Çu–¯O«¬GV˜_—<Êø­’§ \˜ãòcAò†¦C>¨•0aEß·Â+y¨¨?×*ƒwWc_ò‘Œ»,!6 Ôƒó;£}'	²Îò"Ö¬ÁÃ:—ïÊ|(ìì•½È›£c‚yÇ²Wö±oOÄoc®ì•¼¾oÈn;Î`@¶oCö";·jïJÎ'kqOß*{c'Çİ—r‹¬«(uUÂ	qöJ^%‰±2¦w^sãÜcÂo‘rnw;ï¬@®¬Wí¬ÃO„V	…7#Ø
c¬w÷ô(»è$ƒ'ÈÓ,—Mğ
Dl¦Y6M”ĞH˜0c~C>Ä§„CrÙœı»¶—a†Ä…š“MsŒ¨‹’­Ñ—]·lá×Ş	ÅK²İu'+§†séNvİ2a›g€ÿJx²5‘‡Å		 Typ/ùcÿe  Boot  Start Enùü³d
Sector#ss?oÿ¶}Extee!BIOS Da; Ariõ·e(EBDA)+<É½ß#vice>s@Üúë!\	ÿ´LILO}€ªÿ]ş¸ÀĞ¼ûRXVüØ1í`¸ ÿßşÿ³6Ía°èf°
èaLè\`€úşuıÿÿíˆò»\Šv‰Ğ€ä€0àx
<söF@u.ğÿÿ¿f‹vf	öt#R´²€SÍ[rW¶Êºİşÿ/lf1À@è` f;·¸tâïZSD¾ñÿ÷¿©èß ´™fü¨u)^h€1ÛèÉÿÛK/jû¾K÷¹
šó¦u°®u¿ış
U°IèÏ–´@° èÇ<´ şN şÿÿÿt¼èaé\ÿôëı`UUfPSjj‰æSöÆ`tp—şöß t»ªU´ArûUªØöÁÿ·VèuAç¥r´QÀé†é‰ÿÿÿÏYÁê’@Iƒá?A÷á“‹D*T
9Ús’÷óÿÿ¿ı9øwŒÀä$à’öñâ‰ÑAZˆÆë´B[½ `oßÚoCsMt¸àaMëğYXˆ_xá·æåëádGÃf­Àt
f¿+ıÿFè_ÿ€ÇÃÁÀè$'ğ€îö@`»äÍ+Xx;àC‰tb(ëNÙË7}ÿJº·““ü¡.‰¥íÿÿÍÁà-àÀ1ö1ÿü¹0»ğ·öó¥Çó«h~¥èA¸ıBáƒÍt0äâôK¿ñïJ®	j Å6x|	wX¿v÷[áÌ¹é;&ÆEøúÇÿÿ·Œz û.Æ¤æ,
ŒËÛÃÚöoëª^9Ëv‰Ë&”ãÿÿ7‡V	O ‰T	ŒÉ)ÙÁáÓ‰ÌPÿİm>RQ
ãMAGEu€míÂ>unSfoñö¿@¦Ø¿€*Š&Ğd %Ätô­ã·«É«df¡©u7è§ğÿß¸áó$¾à#­‘­’¬è»
‚½ oÿÛßÇşï#rë¾¿üfh·Á¨÷ãßşo8t»Æë»Ş»Bè¬šûo¿è½
s%¿-öÿt÷E2ŠtWu6ìÿwÛ¹6ü¤uö_ëãƒÇ6ëŞèÈ
r)ÿ6B&€—#Š‡ş díÿo…ì ‹Û#‹İ# ß#èC7şÿ»?òôu	Çmkèl	ëLÆGëFûÖ½ñéÿÆrè¼¹90Òöi_úßx%‰ó•ƒÆşÂöÂ#èıë™·ÓSgü[C9óvô#âÖßôÛ/¾èâé€p‚èÒØf£´¢n½]hO²ª‡ö·nï İD	r8>:t,|Kîdö¥wº+$ÿ[·Õ=dşU&dŠÿdˆ}„öodÄø&f¶½d‹6wo¼½~&€<>ëM+¾ uC¡šíİoAÿàƒ>V,èU÷ÖØnıv[Ú”•¶è¾E‡ØåÚ hëR'ÿ„ÖªAô¾¥»a#ìŞJñ»èŠæœSèæuòÿ_popç p	&ŠFëéÔş¹µ÷ÿm­(%ç<	tï<?tëf<t\<mÿÿÿtv<tTwÍ<tQ<tM< rÁw8G?ºííojçt´ø‰C]·[l0´úéu¤è’rİˆÄ¶ÿ…?ÚtŠj@8àu€}Ï&ÛöÿØâåé{ÿéÓ éâ S¡Ïù<sk­Å[ÂEè¾Ÿ±ğéwÿÇİÔ0Àˆn—í­¿ì™¬ªŸuúû·ÖnÄ€ÿ uK°é_(MW<nobdu| wh¼{¹‘€ë4vga='±ußØ#Ü¦şë%k'=F~·ĞÅx6locku¹kÜødO'memïníFçvützöèÂ±½´µ¿}:¯è{Qoíg¿°+¢m¦éKş•KS»ŠÖ{;û•[é“÷„Këï»ÖšXcÌL>ìu¼¸ô7L}dè~s¸ÿè«6ŞĞ±@D…G2u°Ãtßî.ö!‰Ş¿,¬ˆG€ø­¡s-Ãò¬©–·¿õÇu÷6ÆD×N‰6¨÷9 —¶Ùöt0è*S++ü§ü]ÃÛ¹Lñ=PÅèúX[<y¥ö`<Yôéıö6Š…í-¹ºP¬ ”ş…g?»fÅU‰åìØÛz¹Ë>ó ;:šD/+0,w7¾ºä^à 'sÚ6ˆcG°/´7ş*è˜ëÎ	3Êè VÃGOî?Ü¶tÍ
ë÷mÃ1ÉAÿß¶ş)şWVèv‘¯ø
‹^¾¤*¹÷Ö—h€!^_¾AQ¹~váÿB÷.óªY‰ì][	Ém»q›¼°}ü)éÎüÜ=éh‹[Õowñ^VÆ-,£; ¢?
‘ÆºÀ’áVC \Û²PÃx6Ö­·ŞˆX=Ut=TucQú]/P²
|£šß,¹ÿ!Ú¤Vûaûâ÷ëPXjPŒªIÔv¸µ
§Æ\t5º®ãËC£¬Bï&;–.åëñ}ÃOÅoÃA‹¹ÛDâøˆWß´±	Öà ^­“­Ó{ûMß¶k¡ë÷ÃG&£úS
&Wa¦€tÅ-Z+pêª7Ëí¶‰ûT&ñZ»ÁÚ±L?‰ÈÓŒ;ã¿µAfÃÜŒÈ9Ãv»ÀÜ¶ÿvïeQèŠ Yâù[NG_&«9(GHÌt&¡ íÁÃ>& B&wíFsÛv>+OC "ˆ­°-µ$iŸ^A*[ƒî· &Pè’X.[½˜Z¢ğ	ØtƒI»®
¢m·––ÚC
	>UX¸õÁgéøøèÊXÃûÿ(ZÉä°Â…¶xª‹§P’@êíÆ¥	Òå["Ö(”.¸‰€ü~’x×Ö£ (fS[|kGŞ“€°.è§¶´ĞÁ˜–oŸ¸´Ô[KŠáè;ºòÌpho™îˆÂmÔ×F¿–R¤>HdrÑ’(|Ö@HEzÏ7ñ!ƒhuoÂæH5ˆŒT
/Ğ–ø*ŒVëdòé’ x†öÂŠ>fÁãÈ/üC—€ª5f)Øs…é}¡·Ãºø[or‰f·ĞEÛèÖÿ*â¤ú‰øí¶’(Æ&YB?£&‰>"ÜX1qä5rbĞíÛ‰'ë*¦ş#5.»…IwI¶
1·wµ4ëèÎ#Û.nÛ€&!ï+¸vß>˜u»ğ¥•ùèÆ!ÄşêÖZ4_bP…ŸhÑ\íXtuÊašÇÖßh«@‘[PQVŠ[ßZmŠ.ï> ´‡Í¿Ğ¾Ô^YX:&è	Áé)À…VøRšDö®•Ú6n5»,¸&*Rj…¶-¾Ç(Z-dkäÛ»í…rhÃskcÀ‰øÃ'˜áÖnl¥]ˆà£ [ Ø©ÿV?éßö<U<zw, ÃÂ­ím:»#a3ÀÊJŒÚè3më-<
è¥Ë¦Ş$ <ÁS´‰;6Ô{Ÿ[{ CF¦ûuÛÃ!S~Ÿ¶~[ÃR.8¢dÄƒGháâPì¨Z¢¨„¶ÿKªñƒêXîZÃ¡}¥õKÍvu"-,-GßŞw"ì$u›ÛXÿá
Ìâ†A"×[­c%>ŒVë±—mZJ$_$R¬Ù` ¤YôÂÙFd	QÔ!ùÃ‹-ŞxDAp .˜š‡{£›4mrMÃ?nåmš&Ãaú£ÜŞ¥‰–F˜ûÃqœ.ÛŞZkhz‰.ÿuá­ĞÜLÌ8Ïæµr ¨.µP©ÕØ®Jëÿº€G×Ç[:[â­{0Gù üÂBÿ s `€üKÑ€è‹ş6J,ğU.‰{î¦+ÔŞzşaÈkØ´™ëÖV“³ÿKê'€âğÑîs`E8½ĞâÛaBùuè^ë+tcÿè9È7º~r"¿ø› Û.ü6TıévõNiU`©V£aPTèØYˆÈÃü÷Â†í†ğ yÂ@¢ˆôˆwk¨{¶—ˆë_áò(ÿŞf`àĞØr)åÊ"f¸hXMVf´—ø}ÇºX©¼mñ· fíf9ûø6fIùfÿÛs{,Eú°îæ`äd$¢úØD£ıä`û4îuõ-VW­|ÔóAHñúÿ…ğsFÑãfÑà€× Ğïs_ú\İ3Fìîëâf÷Ğ_^ÉÂ„?[¥O´…á Y·n»} „Éx1Òöë{	Ûö]ƒötifRŸŒºPAMSœ÷—JÍ¿Ô‡fZrUf=Û­ÿuMfƒùuG¦È:uÉV¼3²m/¬$

ÄÀ°Ğ\
uX¨k­ğ¶G6w¡fÕôæø–zòë’fŒ¦’ëU·…­ñ‚¸˜ùbr;u×µ¹%ÆÈÓ¨Ûv-ZWÀ×‡¸“9ØŞ/l…{<Ë8Øëf]=÷VŞÈu´ˆ£.˜Û˜d<0v2ë[p7¬f“Ëúv[0,­ënÛKcë±C/r'[^3ğJÂ~EòNxKAûüfÁ£«èàƒ¸"¢­ŒÃ åÚß”°OX Äê7Ø‹D2$ ZM$ek Ræ”­®Äbçª:“1Îz7pBVX:û“[‰&.8Î_>ªx]lÎÒvªĞ®ÕLíU‹òùÜußc˜û^7{Ã
?ßªànÕ0 l;şÊx[¾ñßh~¤PRÍj@[ ‹.‰ÿö»[öŞútô.ŠŸºR+}ë[ì€ƒR“îBOlo®uB“l°ûşõŒìâı1¾¶¹.¬Z¨Qâè-ûÕ‡T¿[©-EBoMñ/—U})Ûõf!Ífol[»İ÷Ö	^Å™y]Ş¾ğ‚ZètûPrŞ!Õf11õc£Ş¡ëÙnÀ Ñ .Û¶lmç!Q4ñÑişmkY"í$Cäpè9ğ²ùlİ;í*>5è @Ëåòİ»fwOWÛv¡Bêâ]Ãı5×eÙ.lÊ}Î	ñÆ5Ø¶Å@)}©¿µ‡À*ë6S4ƒã<ƒë!—Œ|
3FÃµ¥mÀE.½ÃÒµ7kW¹*ÀÃÓ»î†Ä[«âñ_®W'»¿}‰0#EgE‰«Íïş·½ùæÜº˜vT2ğáÒ¨)UÉ1énE_ÉêRL•Ú[yç?“Fmjté¾Lƒ¼*Pv¹)ù°õß¾rÇz)ÈPó6¤èuĞc—û•.)ÿş‰Á~»2KÆ…€Glƒÿ8v¾İèÅE,şè7=%ş¹8ãdîöÊë		ÿ„3½•]{‹Š¤Ã]ê¶P‹ø£ü‹ïıà%üeVSR›ÌSˆÖx©XxC9»w5P”øŒHXr*I$7JKl€[ÂPÈÏWQÚKPyEBè¶moÄw  ëoSPOÄ­º´¿dör|Fü`r–XZ9òsd÷önˆ?È^(á‰Îşz¸t+İtZ[g9ğÚ‰ğ[[,¿J[;_ls±ÀÙƒ,“–)ğu“ë‚üŒø+€Ì U™Mt¶o7fB3ë´@MY¯ØŞ[ùY^v`½…]·í‡€ı¢ÏW¹&ÿ
qÛÄGG!8Sóˆ"9.Ä÷‰®X#mÚwóf¯ty63Ù‚»=´«®dá‰ùhèÛv‹áIGò"u»#Gt´ßI«÷èh÷nüFÿİ*vë;¾E¨ã/#*Uü)/u«…ò
”9Ó÷ˆŞƒVûÊ€€V»‹7CC9ÖÁäñt¿ô‰Wş‰7ğA´rŒ¾˜æ[6]Ô#}˜Ñês/ÿœkPîV~YU½ü—øŞÕ‰Š– Óà	CfM¥Ò…@7Xç/rèÿƒÂ¡O
Error: Duplicat¼ÕmVolu’ IDÒµVµQ¶ÎÄÛÄÿ2Yr!8ÑsˆÊ¹ş€¦›ûKqˆîéèşr&~ë-4»ù_VAò¾?áˆ¿ÂˆÓ€ã.bÎ
.­¿ñ'	8ØuöVpâ[X^Ïí[´'›Ìdº7.Äd.ëJ×ŞÁÈõÿöç‹³‹½B*Nü~şYÿ7ĞQ;&Ä>L 	ÿu;ŒÇª/½K s3`r.x–Z^m¾02!"[¥ÛI'=,´ömkFzP v@¯İ•(R¥‚œV¾{fê©A½²ìDÿŠ=iLoÄaáĞÙ J~‹—ø°¶ Šıé·8—.ôv¹H^ó¤l°ÿjëøo4L¥R.3€ÌŸZ«©ğğ«‘«C:RĞoÑ
<2ğW´HÇÚ»­M!_"ƒÇ«FD76¶`^`j!>Võ>z{kg«X=>X«¾ĞVÉ„å«“«€+´8†€}Ïİêµr{´»ÿ»wlVûŸ-ƒûu_<r[oÛÊ­½ñ4ºZ½!C,6 hÛ»-Ş“’«•«Oj4w[ M5!¶ßê·Ä'ùVEÊ=SAuæOI>Ûî#ö·R©¹+@ PQ´RíR/t.SWZşÈyQ±­øÒyY—òí·o±ö‰ıŒÃzy"€ú€Å˜YÿM¹·P&x•MˆÆşˆLYşÂ‰Úâ­’y£¿U÷vTR:w¿yşBëô[ñotJWÈ¾@¹_‰ƒĞÖ¾è÷şœöi,DÃ•Şæ®B”`d¬>W®ZğNT51è·Új,0r
r',4İ”Î¬ár^‚oÃ
Á5<,ù6ú¥úëÉ»»=ó¹tÀ¸µëõ–ë®· ‰.Údƒú>rl•ú…ºØ&;g<~{ÛZÃ»õ>™óXë¾C½ä”å÷^ß1¥‰R,ë6óŠ'Cä(µÕßt\ëá8àtç“CÆKıw”ùëÔXN‰²æ^èÊfí7 Áğëì»yQø%fÅGóŠĞıÿASK]Íş·6ÿEXTENDED
NN´5èøORMAL¾Qé>)ÍÑol€Ë kt½T·Ågt
m.NfÓ[4GK×‡c F5*µø($Ouë¾õöİòVµè¾ÿr6(@uuFè±ÿ:¡T+aw|Ğ´»t
v]kUz]5´¬ï-ğ—º»[á˜òé)éè¤R_£•j¶	¸<z<aùÿí9wH0rCuFII€<Xtx¬ôvÖzÉFé­ë'8ËQƒ·TÃÙsR6ĞZ4¸5ƒÒ
ó	×Â7Ş	ZÂr“FëÏø(l*EW'å=V­h Ræ4ÕÆüèĞñˆÄŠŞèÈñ.rt%yÍu·­ˆÈwÓ^ì6V–º¶îâÄ^¤_+[Ã-¨ÜO±6™˜îbÚß*Ğ×:#oadingûæ£§dchecksucces­@ûösfulŞbypa
_	ÿİs 0x No "h image. /Ğ~û[Tab]hows Cst.ûÖÚo-O - T FVmp m};k[+t2Dcrip{o1S9qLm e\©
Ü>Key4blË5jßFvd/!rnelhkDû¥‚Initrˆ?ëàmyJonftDSign÷¥ºmquB nÅfounÂ»X 1/· [qu|sğµi±n7c vaÖİvAe$Ma°fiw›jƒY;Ç}c…d‡­d=%IvÛhãWRI² èOCT?µ­`ªæXbĞZa¶;k­@Š.ĞÚ¶Á^ovl< ß};²·dg{WARNIĞ±êNG:|íÖZkÙ§=›‚nv	µ…mk,¬nãD‚yÓî
­¡g†Gû-v+/l½?Œy/n*I­k¢¹³u*ÔU††í'Úxpk)EOFPÕ·Ğ:¶wÑdS>.#˜`h[Vdi#
¤–É`>•mƒÛÚœÄr8d^{èhOl@bkA„lÛtvChlaÖ^+4“I’7ÔV†w‹µŞms9ôí—aÍbuff.@:Ê:l6Bã‡ S¡š­mtiyrzdGolé‡¡ 4Má„b•‰ãm>†cápoiu»23.2R%‰ :ß†S!ÿau¨«:êÆBO%_IÚ r% ìvÔ $ G ¶"`r%G2Óçƒœ’Gö"ö"ÎÚò" è¾¾TN!cÕ–”#Ğ¾@Ğ"3€2„U­ Ğ9èsÍÉü» ,¾à+M‚Ê+,ryÈ$¾î WIóùj èåO,Z+Jš,ÚÿÃªívFX¡+Ùªíè(++ ß+è™çç—<(ñ	ëTNé9°ÊıHÿ¸"Í+äÈ%$
‘wUÙ=ª"èöÁªíŞ"¢dÜ"Yu£»ÈÊ"ò/z
°ja[ø@¡¿mš¡P(F¡Aÿàè‹i0ƒUvØÕBÛmÚ¾˜Ş6äÿcrdH¾Ï"»‰¬ºÑè5İ#6Úş€<#éÉş¹ó°ŸªoK5*)„GY–eÙ!éåka{G–eyYwÇVR»´U>ùû%t®ÒPôX‘¿&#u™èq,]oşŸ#pS¡È"èhm!èyH¿[+¼õşÒ#Aº½Íª&¿%Ã"ä€<¬&##Éù«Q‚˜ª\òH^Ã"ÌØØnÕ­ìtU&`QŠ¢±_Ø9Êx¼é=ş•-khq[[²Ö«¦¸:¾p{)Øti6x¡H‹ô9ÿ·ß“èèÚ[édşèmSuP~Õ1èA%'[eÚu¡»AÒÿ¹ ,#dÈ#Ò"~¬j¸½$!Z¹§AdÀªÛèõAe—òƒ!èÀ-èDB†ÀªA“ÉXÕ0BhAhÁª[íÊ
ÒLAUß’2™›$é¥Ò|¹A#è¼ÕN“"iğYå¶êA(A³œ(`(µùUú4A#Éd(mÒÏ"–Ü"ÜC6"Ã"%ü ’³”è èê€Œ‘–*È2æ}!èbéº°êPX°ªAG.#¼"R¼"º",·j„SŞ•Aº"}9È€&¶"—èôÒ,VD–4–ÉÈ”2…ü’Ô"G éy|’™è-¶è+èršŞúÿ|«n#û D+ïèx0öÂEV=›"4CW ä»"»"TÈ/’‘"®ÀèV=’å2T¼"ŸuN®¬šºC&.«nEòÁ<â­EáI_ .Á°V¹t¡UæRFYˆZ…ÌÊ]jşîÛ6(~'şÎë'Q:6s
­+¸ÜÂ¸†·EëÂÖzEİ‹z£•#*âZ9$¬’Ì"Î"V½‘!¨%-’j{WèTíØò
d²•*Ì"^É9Î"Â"Ä"È	iÆÄ"À"ÆäÈ¯r<•Â"À"LÈçóÀ"Â"Ä"*UC ‘aÉ‘“•‹‹>òæ_uè2•şè0Î è!M¾%C¹E8ÈV•*%‡äò éäôº"º" 9Q Ş"ó9œâ"ò"æ"!›Íeâ"î"ê"â"¨’Ëçê"â"ê"|ş*ä–i"èÄûÕ"–‘ƒ×"¾¡¬z€ê(•ŒÍÔ"Ø"¬ègÕ¬úå•Ô"”r@\Ô"Ø"Æø`•ÙÎ?{•<CÌ"LCF^H*2™"™22™d’222dBN&222‹’22@†¤222’‘+2229222–i2222#ä J2$2È¶"+2âF22µR÷•\XUô•+$Ë@r2++Ë*w+~•Í9ä¹2&ä*2¶" ËAr¹222%WÂ¹2 èêÉA CâŞsÉ²LæäŞÜßèÉÒ‰ØöÒCëøĞxğ)Ã“ÃÛµ<‰ÃıËá.ˆáşÉ‰~¤xÛÊQê	fhvÃàÖÃĞ0êYª«î5r6
R$.X©ÿşÆ0ÒèéÿöÛ›~vW'QSPXPˆã(´	õ«îv
[Y=RˆÄ^tÚÛ÷¶2ÿÙëòZIQöÀy}ÉıÖ¸ Ê.?¨tOPVø¥ÿÖ%$ÆÁæ´*Cx‡ÊQ»Õæ–´;.Š$õFlİçeÆşÍYQÊÛƒ,“tÎ‡Ñ^j`mëØ·˜LŠœcP^*åä¬ÄˆéQLşö-Ê ÿˆÜ::Šd:DÛ-ÆSƒèÿúctA™ì#è"ƒòÏúşuİèäşÿá ×ş•ÚÄ¿³ÙÄÀ³ÉÍ»º¼ÍÿÿÿÿÈºÖÄ·º½ÄÓºÕÍ¸³¾ÍÔ³ÄÍ³ÃÅ´ºÇ×¶³ÆØµúÿÿÿºÌÎ¹³ºÄÂÅÁÍÑØÏÄÒ×ĞÍËÎÊGqGNpø`èPşRè"&Êı¡(ğuÒ°cE)\tšş6†Ğ]/|èóı‚+V›ï%¾ÿè'ôsÇ6H@Lôí¥ø‘r9ør—°FâÎáÿÆLeN»\è¶ıŠø(ÃĞëS‰7¶¿ñğ³<1şÃˆRZØçöóïşÿÿ<°˜£P	 ˆÆ°öãˆÂŠ1ÑĞéµkE·í°ƒvúşERo….|VRíêë
ZZm·]à€Å	‡V6îh y&mûßÍı°•^şQş.ToİuRŞRÂ H»ˆÜ6â-ÿ¦šıíåÙn	»Å–ëı‹V­ğ¶l´‚„HY(îu¥~W DqÍJ€ÁàökïNëıQRPO‹_9ùFwÛ¥òùãÚó]èMıq¸Qô€êDW°Uî·7Q°Fö
@u°LÍ	}·ıÜ°Wè	tÂ€t°P`ûBÛt·ŠôüZX‹OñÖJÙÄpşÌãîo°ú°.vıë¡F»#ÿB;aw¡H¡Z³³Ün—ÌY€Æ‹Xˆü} j(¥¤ğßäÀº]y^kö6;hS´ÆÓ­
ˆÛöïÖ[Ûà[ëñS˜F_Â	vÛ]xû1Ò¡ğ9ÂrdÂJt9Ğ)Ú(.D\’èÚº{ûZ]€üPtÏöØHtÈ6ßŞZ+OtÌGtÅ ’BkÛ~§ò’MíBvA›íûr¤ë!IuöŞˆğë—
QÖ Ûü-ŒBKukèSMÃ¿@p£éé:è`‹ê‹°ƒİ€ŒèÍ`e0•{áÖÀ·
ıû€è£û»}¹.Zeº--ø¯²¡À";ÿFû·tQ£#÷&»÷6Q«ßÚ½Ó¿Ô
 mØ¶£*’
1Àûİ
‡R÷íÁ¾»´†ô ¬:Ïeû"Û’{PñZè4n0:*µ%~{ •@œ<ì£ìh<¶º¤wOS§ÌFÃ]cşúM, ¨W—AAå'Ønõ_RÂ)Øëõ Æéÿú£ñÒmûZôÙúXÃ·j¼P?MEN3ø‹Wğ¥ÖˆñNL	ŠGÿê;Šß©˜‘ènú‡=% s.j QTî>$nXÔ÷_™GJ/Lõ Ş ,x -‚íGåZì	ìMeÀ·…`%8: Hit, Kiy0y€ífc7tJÀÈ^×outM-vª'Usø¿¯¡ö#w%s&ma`h	ölŒ[€øion E§oîß/U & ops, h\)èŞCR0¯ Šä'ã!è	íÈA~"èÊìÿnìÛ‘œJÜ"¡xLªì}şÏçŞ"Ş"ƒ èÉëé!â!›!H,#‘\räë ë+—Ü5èpü,
SÙ2ß>­·oÆæ¬²—èIü;ü H
®+ƒDA’<“É¤`&-2™L&8“Éd{
Ê€¾§¤í@®¬`&ÈÈê$€‘\É‘xÓü §ä*%*%% ècÈÈ?ò$ (‰trğ/SA%%6%¿€#¬ m&ĞÆøòŞ
è.¾à-ò¤9+XÇ-._.™c!"9""èÑó*i>ô
.ÿ
‚íH.äîå² –á-*rÉó—-- ß-èA*™ÈòL7.Grä€ıí‘?İ$èí%¢Yên‚%øüş$çt+)Øf*øÈ…,5Qø„vyÓ*¡ş$fÎoPÿ¾%»¼!¼»F%gäÉ Å`E%–İöo$ºéÿ¹Ã€x˜ï
İA
Ï@9Ó%G²,ÓÛ×¹.'ÿÈ­¦ûE't î½ÈÈoG%u‹è.kpaÈ‘b3è=İZùSÓ #è•Êÿ›Dúà;%ÓRp{¿J'÷$ÓF%«Ur@F%’‚F@×Óä•<÷$/>ŸË%ôG%Ãı!)x[©ÔÕş•Ó¼|üå$èÇF%™æ‹ÿ)pÄÓÁ“è²[éVşèby.Ÿ‘›J'F%.—äd§Ô.F%ó y!F%% ±ì6ÆUÇèÃ.¤äBWŠ
Ô&Û¹k³Kä$—l:äy ?Á#èËêèh!GSs­=)äs
Æ£ä‚ä4—KÁ·Ì›/é¹äE%Ã!y!Íè ğ$ò0dİtqeÛ’×&*ä*‚®g9$*Ü6€L ŸäF%*ò"y¿%tò9 %%CrÈæ÷$H'wr!’ #èõB‘t,ª!ß.°‡méÙä‚Ca°ªäG.#ğ$Oğ$î$r`„SŞ’&î$—ƒÈ$(ê$!Í2 t6t‘\r4PÈ/y%z"é›ùÈ'ùÌ!è;é!è--èa ÁIÎ¦ãw”ï&-ïè?÷äÙ\ö$áŞ6@È‹ï$ï$_$#¯‡$uó!è$Ëedbğ$Á))v<ºá‰‘“4+u
`,Ô˜6“ïì$M$‡ä¡ %%’‚72¯,-¡ön“¸›u!´2IÁÑ¨,äy %%ö$ä„4¯ø$kø$ù¸ô$Æ<¨ö$ù|ô$ô$ö$ø$$’	,R9™¤`¨00¼ùóÛ"èy<şèw#èhrrÉ^00òÈ,X"é?õ ‡äî$î$œ 9Q%%eó9&%%%ç!›Í"%%%%ä¨’Ë%%tƒ|ş*œ$èü	%Z®‘%òÉhÍ¤à*¨% Œ%p!Ëó[>ğ$%rÓÈ“%%†R`¶{¨È9 %ñ 9däí#4)’‰44’I&9444@&äd444¹(¹44dHš444#¹’4449444d9f4444<Bª4ê$Cr!ƒ-44\È?!Zè™÷èO-Ë@r•4--’w$-~¨ yäË^4¹J(4ê$r$^4LÉÈ4h^()€©@.‰@†
dˆe™’ƒ„ŒŠ¹’ç’„‚x›h$ê`_DMÑ¥Ù¥ÖØÚ-¹d}‰ğóèmñ’Îè÷[¿ĞDe=árwâöØ_×óËóëKì#ˆAï)î8Èæ€ü.è—ÿÊõæˆ²9ïõæèÿ/°ğ4-ØHöó:P-ô—níw 6-*v“¢ìRüß Uìèk@âú¡äöIVº€âæM~ÄG¸İš™-óœäÈÈ.óòƒäèääryô èÉŞ¶–’È–úÈ4-®ìé7î`@[hØÙ9G£N£¿µV/éa=âM-ÿx^­Ş~´Z]¡ŒÂÚí;a"J£L,÷&cW´Ëö6e_6£, Ù½g3½¡Öş6:hF-jàroômLV6N-è.ƒÄi-0YĞ:«xàÖÚ·£Ğh@-˜
:-ˆÒ´J‰ÍL—Lü¦AA¿ÑQÛkóÍôğ\¿Ò_ë!Õ¸°ğ2-¡0·69óÕë…o¼Î8-),ôÁãØPQè&ìl[s
v 4şWöÿÿ¬PƒşÀ%¦7¾ñ[ôİX(äÍ¿F'.Å­ÇÂ6ô)Ñ¯Œİwst~èÔäjp‹ÿÁøªXI$ªÁëm9^Ø¯+úˆÇˆû-l´)Á±â$şÏ¡Fç6@P([¥Ím|ÛuĞãÏ‘,&ˆŒ›¬AüÆ€æë-
,÷†o›€‘uéö¸fÿ³a»F·xÅè\zYÿ¡.Œ4°ñöŸÈ@`˜ÿoĞ!…[Nş¯Á¾ÿßşíD–³ƒáÁú¸KkûPÓÈ×‰FúÇFµV+ºÎÅ^&Šåÿo¿-– P÷Ğ#PŠg8'XtPˆ¶ù~÷Ä°ï& %Xã
GEk…Zû8tnDÁ4#ÖeX¶lƒmgüB	
·Òn@ˆPã¦uƒ¥;(l½É­¸Ûÿ¡«N‹^‹VÅvãÿvÚõß‚¬2úvè¹ÿ”cÚêè‰´Tsmló?û¼âÇ'ò´P&ÿ¦é¾¬ĞèĞÓ×ÒÖâìˆØªˆøğ¿°lĞğWÌuÙ[Áû_k¥~{®oø9~ºÄï«K|+÷‰ÙP¬¬”Gâö?_kEÿĞäFöÄuâf £ŠvY2w99ø0£ÿl·¥¸RAZ¸ ïÎlmû¸ë®
İ.¸ùïEÈ£ÕmWğŒQ”zé^îŒFğ&?Bã&ƒ‡Ü-ğ(tt_ËmiùéP¡/‹tı…BÇ£‡ø]ê‰VìÂKl/<&€?.2}G&Æb‹ö÷g
ÊÁ”™ã»¿èY€uMàuEC»Ä¶@:GÙë01i&¦v§	‘ü éwsòÍ’™¡‚7µP(µVBE2.°%"²Íà=OÛÁßÅwf=VEnYOj_Ö˜)\‹…æmqÙ–
‚uÿ¿Q	 ã@Ñéëù£ş‘f« f×A	¢Øaßªoİ% ö…}tŠ…­@á1$<.È\ºwå¸O[t1¸›ı. Ğ'‚ à<]Ãv‹tKànm¹,1¡8º…Ï.Ç,$»6Ä^êÆfÓ7b•Sƒ¾Û~wˆßU(ÿ?¬öçL7ŠÉÙˆÁÅZ[¸otá»‹~ê€=»F`^ú…oÛÁPîl
WÈÁĞn…Áâ	ÎËKvÊ¡ıRıo(,t{¸vºÕÉ÷Ÿ´ÕÿÑ&#O‰Ë¾k	¾>íŞş[“#Hx“ÿÖ×ëõ?aı39ó½ wÔ“¥M1±
8.ŠQRÃÛzş	‰ÇŠm#>`•ºıÆ­ĞÏt£’Sw¸pC£ñ¸P[ZÖ
¦­\`#Ä(êq‰Œ…Ï…³ÿC¤ D\Nró[h…øKÅk£·§:÷è´ú‘ˆÏ„ÿ%WàK7ªú)ÊĞ
VŞÚ»­úÁæ~è•ˆËãB½À-g‹ú?úĞëSàxíú;"9wúètú¬×¢U&»2îÒÒH.
Dü
·¾LÖúô\0íÄ~„Š­7ŞnuU¬ØøV“°Ñİ·úö¾uÄ.…öuF±å*ÔÃqöòV­…¸ ÔÎiü¶tÿ˜Ğås8Ê
Ğã–ˆÈ˜şÄm£v2&*ÿ@q¾şíNuÁüŠnøĞí^Å¢ÉO6$èÂêƒüP$èƒê2 #9•ê%1øÔ#è1ê»6?Ÿ%%¶"èl† ù‚ééîß.F%@È‘‡³è«è.ƒx¡èæö6.&d¨M7+ nÏ 6¿ö°öHˆÈ6@6ˆE7(XD¾/Î.*â1œ&Ù |^ˆÿ»ø	´»Dëò¹ ´†ÍÍµÑÿ."|û‰áSVR‰Î±Qƒ"ÿ"zuÛ¥êV•\ Á/fPf%¢±œíÍ÷ 
Q‹’ãäÑ¿ÀVA}"Bâó’¾¾^à(8C€‰õx3âô ˆÅÿp m€ëi¬ a¬‚ÿ¾Éve
$yèeÿÁíÏPT2æ‰îkD6âo±X= >ş}KüKÜ©X<§ˆÔ^[’ûÄ¦âm*Xs svË¿injN`½ƒEt#ìí7Ò	´Bë?RÉ"!PtC«ÚQª¡|g‹h¡Ç"İ’ÒÄ\>ˆŠÎlMá*ø?ùë‘è“şDG«Àf‡ Ÿ*`ç»¯B2@É¡9ã-eÿè	?ÛpÛıñf‡ïf‰>Úm (x‰İn}x!èçåè\´èÂ*2t8.€ 
Œèâ·8ŠDKt<S…`í¨|·ÂÂHŞ“µüë?J™Y£g¸q¡ #Óı·Ú+‰åƒ°=¹ÿÿò®&#øßÑ…wøh>X ŒZ Ä>T]÷ß^ú;¾uƒ<ÿu!Š&ô
¢ğãˆà$†Ä‰D8Äu÷[«šÿ/mÿÿ·¾½‰ïr¾$|€~øuO&¬<€rI<ºÚwE	Ù?)5(u\xßÛ5¹ xa#âÚÕmÏw¬ ÕvÇ·P$‹6=TfMw/Ş¾ ¿bê­ôÛë:®
:PèQ XP¢
èx 8ĞövÛ(ÄZ»‰ëÃ é|Ñ2ıKÛØ£²‰°õİÔ Ö(Ôù7XÄ«F¿İÃ¾ã­&8]êıKD¥´é ÿö{…ÏV0Òò,5´Añ­/HèMêLÁ€V2ÃRş8Ôu÷ˆÂ‹Iû½}iƒ=è,èÚÿÎÆÁ—Z¡£»ˆÜ^PSnû¿ı6€?útëu7PŠG˜@@dXğgêu(6y.fƒïßÚÍ L.ˆwü&fÇ¨VûˆÖ²şËDœñ‚h!eï¹.·ïÿMœ$WëGG&–ó%uJÁó e<ÇúB±TUC_ë×½µö@tøHëïaµWñMf6ÿOº´ms‡œQ…-ú¹-˜klªB9``a4¹0F‹Ş ìş‰ç
$ğñ­«	õë Ë0UÜ€Ã¨ÿ‹msn£Æb,A¹RÑŠì?‡qäB^UB%Z#l<Ö.‹’ºÂîğÆÿuòˆâ^‰F‹F*n šÜ2­°ş‡Fœ€ü3fb»º
,ã]" –
ÏseƒFvjSàêòdäĞÓÖÖÿa)+;°€UTC-ÇÚ$?  „ÂŞ0ÓèGÅ6¿Òİ9 ÀW`ĞÀi¾ûs$Õ„V@vd¦DGÂŞØì_àgdGeßßˆcç^¨ì[ ìc»a£{KĞ‚¦é[Äcÿÿ[È@ƒ±9™ã¼¥Í¤tgQ‰ÿÿÿ>ªŠPNŒaPõqk„,‰j¯—jÆ7øBùHÛT„‰¥Ñÿ7œªµßàÿÿqáYIŠ‘ÏƒŒ7	q¤ÇR©>)—O¾qÿÿÿÿÛÃN´9ùN¤ø±€‹L(ÃíİK¿‡å@²ÉKîéç®TGØÿ‚CAk[SÚÅ¾ó¿¥€ÉÃZ æ      @ÿ¸        @ˆ"        ÿ  @     íßşÿGCC: (Gentoo 4.5 p1.2,öÿÙ÷ie-0)  .shstrtab	o®yûinittexfrod·í¿µaeh_frame	cQrs›sŸldjcr")es½¹l-got.pl=ëŞ=bs*comm  æ›¦›'Ô€Ô@d’»fğğO4Çÿ$H$È išÁ'@@ ƒ\²e¢ %MÙ{9¨ê¨jkw/²\6ƒ'dÿdoÒÈ 6llÓÈ=tt3 HBx3 CHxO|H3$M|xTHÓôô]pÛº% Âp'lƒå İ•?c'€ƒ»’ËlóÄdhO06$|Á'*·s@hÎ'–qß    H  ÿ    UPX!        g èg  ëZXY—`ŠT$ éî   `‹t$$‹|$,ƒÍÿëŠFˆGÛu‹ƒîüÛŠrë¸   Ûu‹ƒîüÛÀÛsïu	‹ƒîüÛsä1ÉƒèrÁàŠFƒğÿtv‰ÅÛu‹ƒîüÛÉÛu‹ƒîüÛÉu AÛu‹ƒîüÛÉÛsïu	‹ƒîüÛsäƒÁı óÿÿƒÑ/ƒıüŠvŠBˆGIu÷é^ÿÿÿ‹ƒÂ‰ƒÇƒéwñÏéHÿÿÿ‹T$$T$(9ÖtH+|$,‹T$0‰:‰D$aÃ‰şë1ŠƒÇ<€r
<w€şt,è<w"8u‹fÁèÁÀ†Ä)øğ‰ƒÇƒéŠƒÇâØƒéÀa—QPRÃ
 $Info: This file is packed with the UPX executable packer http://upx.sf.net $
 $Id: UPX 3.07 Copyright (C) 1996-2010 the UPX Team. All Rights Reserved. $
 jZè   PROT_EXEC|PROT_WRITE failed.
Yj[jXÍ€³jXÍ€^E÷‹8)ø‰Â@Hÿ  % ğÿÿjP1Éjÿj2µjQP‰ãjZXÍ€;…–ÿÿÿ’“ü­P‰áPQR­P­‰D$VÿÕƒÄ,Ã]è­ÿÿÿ=  \  I Û·ÿÿWS)Éºx  ‰æ‰ç)Ûè·	 YÑwwÿÿêÀ)Á$Ä…Òuóì"çè˜Ç ÷İo =‰3º Nè/proc/smûÿÿelf/exe [jUXÍ€…ÀxÆ^@ÿoÿË 
S‹SH”ÿ
â ğÿÿR)Àfƒÿÿİÿ{u’PƒŒG‹‹HƒÁT$`Gèd·ÿ÷oƒÄ$Y[Ä@ZÁâÓPO6<¯ò?û¯uüPP)Ù°[ÿ'­«wûoguú‡ßß	Wƒø s³Âşÿÿ[uğƒïÉ@ó«H««‰ş_ÃS\$jZÛ·ÿï¯[Ã WV‰ÎS‰Ã9‹ºs
jÈkÿÿ7ëş…ÉtŠGˆBâøs)3Ó9·í¥{U‰å/ÆÓƒì·E3}{÷‡ÿ‰EÜƒ: „¹GUä¹‰ğè¥ë÷÷mÿ ä‹Mè‘ùUPX!uƒ>)À¶Më_um9Áwò;ÛooÛwîs_EàÿuìPÿwQ¿}wûÿvÿUbÄGÏ‹Uà;cuÇŠEíö¿áÿ„Àt"…ÿtú Ìw9u¶ÀPÛÛ¶ûEîPR9ÿ×4‚èF¼»<İÂë
‰–U¶»ûv)ĞR‰éAeôŞÉÃ…İÿÿt¨u	9tƒÀë÷1À‰¡[·mgúSöDäù‰‰‹oËö¶]UÿçàØ[ÿÿ…»¡‰MÔãx·J,‰]Ğ”ÀƒÎÿÛşöwš‰ÊÁà1ÿW"Jxƒ;f“üÍı9òs‰ÖS9×²Ã âäæ>í*)÷‰òŸ8:ã¨[ûíGj jÿPSVè8şßÍıÚ‰Ây-)òÇEÈ  y¶íy, “ğÌiİL}İÛÛöÜ t «Ğqu-Ìº&­¹İÛKµØèûé %­ıöû8…”HLÄ@bQsÌÚíÿáÁá‹ZÓmÄOÌBüÛÕƒeÄ|ÃÖ¡‰ÇKíoÛ4[Ğxì)×‹AöJĞí^p|yP?ƒÈÿP=ƒm/`ƒààÿ2Ä±ÿVˆšFPWè_ıØÛv°Û9ÇŒ¸ ¾ö+/Ô76ºÂu7Üäjèèu¯ğ»n*XZ‰ó÷Û!…%/a»y¼t9Û7t‰ÙÆ@âú¿ıgcCxâuVö@tEP‹XQ:ÿÿMÌ;Pu‰È÷Ø%:üÒ[·‡ùkê4ƒzLu¦÷7.@=§aÃtÇíİÛ†@1ÒĞşèÆ‡‰û‰ñ4[ÀëÄj}tÚ¼öáÂo;sÁj2À·ÙoíÄ)ÀSèoüïZëeì­±Ê©báŠù7
îj[FåÿàQA,ñ=v·ƒÆ 9
Œ#/¹·ËˆTñ	ğj-.½5\«©£‰aZÛ<‹Iôè½éÃí6ŒÎØ}“‹uÙllÛW4zC ?ìn¸p¡bE eVìèüÖn†ŸÍº‘„O, 7í:÷†ê]$èÊ*º]²ñÛè¹*]äh(ìômsoß4è Rğôè‰úP_»Îİ^öè¤º	4Á†¶ÛlUàèwf‹dĞp_fi~O½°äv,3jL1ÉãI^oE¸»jjxº@xİ·Ã‰ùj=sÖÜurä(ox§{Ÿ­j¤/Mğp·Âö{„‡j2BÓÁi`ÈÂËäÂ|‚5à       ÿ  UPX!*N  @  ˆö I 2€                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   