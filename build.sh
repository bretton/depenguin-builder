#!/usr/bin/env bash

# log
# 2022-07-29: adding script to try automate builds, adapt for custom components
# 2022-07-31: adding extra rc.local, setting rc build script
# 2022-08-01: improvements for passwordless root, git version build script, accessip not in use

# this script must be run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root user"
    exit
fi

# we must be on freebsd
whatosami="$(uname)"
if [ "${whatosami}" != "FreeBSD" ]; then
    echo "Please run on FreeBSD only"
    exit
fi

if [ $# -lt 1 ]; then
  1>&2 echo "
Usage: $0 -i access-ip -f /path/to/authorized_keys -u [0/1]

       Example with upload on:
       $0 -i \"10.0.0.1\" -f /root/copy_in_auth_keys -u 1
"
  exit 1
fi

# get command line flags
while getopts i:f:u: flag
do
    case "${flag}" in
        i) MYACCESSIP="${OPTARG}";;
        f) AUTHKEYFILE="${OPTARG}";;
        u) UPLOAD="${OPTARG}";;
    esac
done

# VARS
if [ -z "${MYACCESSIP}" ]; then
    MYACCESSIP="*"
fi
if [ -z "${AUTHKEYFILE}" ]; then
    touch authorized_keys_in
    AUTHKEYFILE="authorized_keys_in"
fi
if [ -z "${UPLOAD}" ]; then
    UPLOAD=0
fi

# VARS
BASEDIR="$PWD"
CDMOUNT="cd-rom"
CHECKMOUNTCD1=$(mount | grep cd-rom | awk -F" " '{print $1}')
FREEBSDISOSRC="https://download.freebsd.org/releases/amd64/amd64/ISO-IMAGES/13.1/FreeBSD-13.1-RELEASE-amd64-dvd1.iso"
FREEBSDISOFILE="FreeBSD-13.1-RELEASE-amd64-dvd1.iso"
MFSBSDSRC="https://github.com/mmatuska/mfsbsd.git"
MFSBSDDIR="mfsbsd-master"
MFSBSDCOMMITLOCK="0da806178042b0d3cd20fb6b2e6e38a338a24b9c"
OUTIMG="mfsbsd-13.1-RELEASE-amd64.img"
OUTISO="mfsbsd-13.1-RELEASE-amd64.iso"
MYRELEASE="13.1-RELEASE"
MYARCH="amd64"
MYBASE="${BASEDIR}/${CDMOUNT}/usr/freebsd-dist"
MYREMOTECONFIG="${BASEDIR}/settings.cfg"
MYCUSTOMDIR="${BASEDIR}/customfiles"

# make sure we're in /root
cd "${BASEDIR}" || exit

# check remote settings
if [ -f "${MYREMOTECONFIG}" ]; then
    source "${MYREMOTECONFIG}"
else
    echo "Please copy settings.cfg.sample to settings.cfg and set remote parameters"
    exit
fi

# create directory if not existing
if [ ! -d "${BASEDIR}/${CDMOUNT}" ]; then
    mkdir -p "${BASEDIR}/${CDMOUNT}"
fi

# unmount any existing loopback mount
if [ -n "${CHECKMOUNTCD1}" ]; then
    umount "${CHECKMOUNTCD1}"
fi

# fetch the iso
if [ ! -f "${BASEDIR}/${FREEBSDISOFILE}" ]; then
    fetch "${FREEBSDISOSRC}" -o "${BASEDIR}/${FREEBSDISOFILE}"
fi

# mount the iso file
if [ -f "${BASEDIR}/${FREEBSDISOFILE}" ]; then
    mount -t cd9660 /dev/"$(/sbin/mdconfig -f ${FREEBSDISOFILE})" "${BASEDIR}/${CDMOUNT}"
fi

# remove old mfsbsd sources
if [ -d "${MFSBSDDIR}" ]; then
    rm -r "${MFSBSDDIR}"
fi

# clone the mfsBSD repot
git clone "${MFSBSDSRC}" "${MFSBSDDIR}"

if [ -d "${MFSBSDDIR}" ]; then
    cd "${MFSBSDDIR}" || exit
fi

# check out a specific commit
git checkout "${MFSBSDCOMMITLOCK}"

# clean any prior builds
make clean

# copy in our custom configs
if [ -n "${AUTHKEYFILE}" ]; then
   cp -f "${BASEDIR}/${AUTHKEYFILE}" conf/authorized_keys
fi

custom_rc_conf="rc.conf"
if [ -f "${MYCUSTOMDIR}/${custom_rc_conf}" ]; then
    cp -f "${MYCUSTOMDIR}/${custom_rc_conf}" conf/"${custom_rc_conf}"
fi

custom_rc_local="rc.local"
if [ -f "${MYCUSTOMDIR}/${custom_rc_local}" ]; then
    cp -f "${MYCUSTOMDIR}/${custom_rc_local}" conf/"${custom_rc_local}"
fi

custom_boot_config="boot.config"
if [ -f "${MYCUSTOMDIR}/${custom_boot_config}" ]; then
    cp -f "${MYCUSTOMDIR}/${custom_boot_config}" conf/"${custom_boot_config}"
fi

custom_hosts_file="hosts"
if [ -f "${MYCUSTOMDIR}/${custom_hosts_file}" ]; then
    cp -f "${MYCUSTOMDIR}/${custom_hosts_file}" conf/"${custom_hosts_file}"
fi

custom_loader_conf="loader.conf"
if [ -f "${MYCUSTOMDIR}/${custom_loader_conf}" ]; then
    cp -f "${MYCUSTOMDIR}/${custom_loader_conf}" conf/"${custom_loader_conf}"
fi

custom_interfaces_file="interfaces.conf"
if [ -f "${MYCUSTOMDIR}/${custom_interfaces_files}" ]; then
    cp -f "${MYCUSTOMDIR}/${custom_interfaces_file}" conf/"${custom_interfaces_file}"
fi

custom_resolv_conf="resolv.conf"
if [ -f "${MYCUSTOMDIR}/${custom_resolv_conf}" ]; then
    cp -f "${MYCUSTOMDIR}/${custom_resolv_conf}" conf/"${custom_resolv_conf}"
fi

custom_ttys_file="ttys"
if [ -f "${MYCUSTOMDIR}/${custom_ttys_file}" ]; then
    cp -f "${MYCUSTOMDIR}/${custom_ttys_file}" conf/"${custom_ttys_file}"
fi

# delete old img
if [ -f "${OUTIMG}" ]; then
    rm "${OUTIMG}"
fi

if [ -f "${OUTISO}" ]; then
    rm "${OUTISO}"
fi

# create iso
make iso BASE="${MYBASE}" RELEASE="${MYRELEASE}" ARCH="${MYARCH}" ROOTPW_HASH="*"

# scp to depenguin.me site
if [ "${UPLOAD}" -ne 0 ]; then
    scp -P "${remoteport}" "${OUTISO}" "${remoteuser}"@"${remotehost}":"${remotepath}"/"${OUTISO}"
fi

# exit
cd "${BASEDIR}" || exit

# umount cdrom
CHECKMOUNTCD2=$(mount | grep cd-rom | awk -F" " '{print $1}')
if [ -n "${CHECKMOUNTCD2}" ]; then
    umount "${CHECKMOUNTCD2}"
fi

exit