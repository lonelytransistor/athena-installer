#!/usr/bin/env bash
set -e
if ! mount | grep /home | head -n1 | sed -n 's/\(\/dev\/mmcblk2p4\).*/\1/p' | grep /dev/mmcblk2p4 2>&1 > /dev/null ; then
    echo Please mount home partition before continuing
    exit 127
fi
if [ $(uname -m) != "armv7l" ]; then
    echo You are not on a reMarkable 2!
    exit 127
fi
if [[ $(uname -r) =~ "athena" ]]; then
    echo You are inside athena! On the fly installation is not supported!
    exit 127
fi
if [ $UID != 0 ]; then
    echo You are not root!
    exit 127
fi

NORMAL="\e[0m"
BRED="\e[1;31m"
BGREEN="\e[1;32m"
BORANGE="\e[1;33m"
BBLUE="\e[1;34m"
BYELLOW="\e[1;93m"
WRED="\e[7;47;31m"
FRED="\e[5;101;37m"
BSPLASH="\e[0;103;30m"
BSPLASH2="\e[0;104;30m"

OVERLAYROOT="/home/.rootdir"
OVERLAYWORKROOT="/home/.workdir"
#OPKG
function _installOPKG() {
    mkdir -p ${OVERLAYROOT}/{bin,usr/bin,opt/usr/bin,opt/bin,opt/etc/opkg.d,opt/lib/opkg,opt/tmp,opt/var/lock,opt/var/opkg-lists}

    #Download wget
    local wget_remote="http://toltec-dev.org/thirdparty/bin/wget-v1.21.1"
    local wget="/tmp/wget"
    wget -q "${wget_remote}" -O "${wget}"
    chmod 755 "${wget}"
    
    #Download opkg
    local opkg_remote="https://bin.entware.net/armv7sf-k3.2/installer/opkg"
    local opkg_path="${OVERLAYROOT}/opt/usr/bin/opkg"
    wget "${opkg_remote}" -O "${opkg_path}"
    chmod 755 "${opkg_path}"
    
    #Configure opkg
    local opkg_conf="${OVERLAYROOT}/opt/etc/opkg.conf"
    local opkg_conf_d="${OVERLAYROOT}/opt/etc/opkg.d/"
    cat > "${opkg_conf}" << CONF
# Opkg configuration
dest root /
dest ram /opt/tmp
lists_dir ext /opt/var/opkg-lists
option tmp_dir /opt/tmp
CONF
    cat > "${opkg_conf_d}"/10-entware.conf << CONF
arch all 100
arch armv7-3.2 160
src/gz entware https://bin.entware.net/armv7sf-k3.2
CONF
    cat > "${opkg_conf_d}"/15-toltec.conf << CONF
arch rmall 200
src/gz toltec-rmall https://toltec-dev.org/stable/rmall
arch rm2 250
src/gz toltec-rm2 https://toltec-dev.org/stable/rm2
CONF
    cat > "${opkg_conf_d}"/20-athena.conf << CONF
arch rm2 300
src/gz athena https://lonelytransistor.github.io/athena
CONF
    for fconf in $(find "${opkg_conf_d}" -type f -name '*.conf'); do
        cat ${fconf} >> ${opkg_conf}
    done
    chmod 777 "${OVERLAYROOT}/opt/tmp"
    ln -sf /etc/passwd "${OVERLAYROOT}/opt/etc/passwd"
    ln -sf /etc/group "${OVERLAYROOT}/opt/etc/group"
    ln -sf /etc/shells "${OVERLAYROOT}/opt/etc/shells"
    ln -sf /etc/shadow "${OVERLAYROOT}/opt/etc/shadow"
    ln -sf /etc/gshadow "${OVERLAYROOT}/opt/etc/gshadow"
    ln -sf /etc/localtime "${OVERLAYROOT}/opt/etc/localtime"
    
    #Install first opkg packages
    local opkg="${opkg_path} --force-depends --force-space --conf=${opkg_conf} --offline-root=${OVERLAYROOT}/ --tmp-dir=${OVERLAYROOT}/opt/tmp/ --lists-dir=${OVERLAYROOT}/opt/var/opkg-lists/"
    PATH=/tmp:$PATH ${opkg} update
    PATH=/tmp:$PATH ${opkg} install entware-opt ca-certificates wget-ssl athena-hook athena-linux coreutils-df
    cp "{OVERLAYROOT}/opt/bin/df" "{OVERLAYROOT}/bin/df"
    
    #Remove temporary files
    rm "${wget}" "${opkg_path}"
}
# Change bootcmd
function changeBootcmd() {
    echo -e "   ${BYELLOW}Changing bootcmd...${NORMAL}"
    echo -e "      ${BYELLOW}Backing up bootcmd to memory...${NORMAL}"
    old_bootcmd=$(fw_printenv bootcmd | sed -n 's|bootcmd=||p')
    echo -e "      ${BORANGE}Patching bootcmd...${NORMAL}"
    if [ "$1" == "INSTALL" ]; then
        if echo ${old_bootcmd} | grep athena > /dev/null ; then
            echo -e "      ${WRED}Athena found! Bailing!${NORMAL}"
            return 1
        fi
        new_bootcmd=$(echo ${old_bootcmd} | sed 's| run memboot;| run memboot; run athena_boot;|')
    elif [ "$1" == "UNINSTALL" ]; then
        if ! echo ${old_bootcmd} | grep athena > /dev/null ; then
            echo -e "      ${WRED}Athena not found! Bailing!${NORMAL}"
            return 1
        fi
        new_bootcmd=$(echo ${old_bootcmd} | sed 's| run athena_boot;||')
    else
        echo -e "${WRED}Wrong argument!${NORMAL}"
    fi
    echo -e "      ${BRED}Writing new bootcmd...${NORMAL}"
    fw_printenv bootcmd
    fw_setenv bootcmd "${new_bootcmd}" || { fw_setenv bootcmd "${old_bootcmd}" ; return 1 ; }
    fw_printenv bootcmd
    echo -e "      ${BORANGE}Done.${NORMAL}"
}
# General installation
function install() {
    echo -e "${BORANGE}Installing Athena...${NORMAL}"
    systemctl stop xochitl
    
    echo -e "${BGREEN}Preparing overlayfs root.${NORMAL}"
    mkdir -p ${OVERLAYROOT}/{etc,lib/systemd/system/,usr/sbin}
    cp /usr/sbin/rootdev ${OVERLAYROOT}/usr/sbin/rootdev.old
    sed -r '\~^/dev/mmcblk[0-9]+p[0-9]+\s+/home\s~d' /etc/fstab > ${OVERLAYROOT}/etc/fstab
    sed "s|PATH=\"\(.*\)\"$|PATH=\"/opt/bin:/opt/sbin:\1\"|" /etc/profile > ${OVERLAYROOT}/etc/profile
    sed "s|\[Service\]|[Service]\nEnvironment=QML_XHR_ALLOW_FILE_READ=1\nEnvironment=QML_XHR_ALLOW_FILE_WRITE=1\nEnvironment=LD_PRELOAD=/usr/libexec/libAthenaXochitl.so|" /lib/systemd/system/xochitl.service > ${OVERLAYROOT}/lib/systemd/system/xochitl.service
    _installOPKG
    
    echo -e "${BGREEN}Moving hooks into /home.${NORMAL}"
    mv ${OVERLAYROOT}/home/root/.xochitlPlugins /home/root/.xochitlPlugins
    rmdir --ignore-fail-on-non-empty ${OVERLAYROOT}/home/root
    rmdir --ignore-fail-on-non-empty ${OVERLAYROOT}/home
    
    echo -e "${BRED}Patching Athena LD_PRELOAD into xochitl.service.${NORMAL}"
    sed -i "s|\[Service\]|[Service]\nEnvironment=LD_PRELOAD=${OVERLAYROOT}/usr/libexec/libAthenaXochitl.so|" /lib/systemd/system/xochitl.service
    systemctl daemon-reload
    
    echo -e "${BGREEN}Installing Athena uboot vars...${NORMAL}"
    fw_setenv athena_fail 1
    fw_setenv athena_boot 'if test ${athena_fail} != 1; then setenv athena_fail 1; saveenv; run athena_args; run athena_bmmc; setenv athena_fail 2; saveenv; fi;'
    fw_setenv athena_bmmc 'mmc dev ${mmcdev}; if mmc rescan; then if run athena_limg; then if run athena_lfdt; then bootz ${loadaddr} - ${fdt_addr}; fi; fi; fi;'
    fw_setenv athena_part '4'
    fw_setenv athena_lfdt 'ext4load mmc ${mmcdev}:${athena_part} ${fdt_addr} /.rootdir/boot/zero-sugar.dtb'
    fw_setenv athena_limg 'ext4load mmc ${mmcdev}:${athena_part} ${loadaddr} /.rootdir/boot/zImage'
    fw_setenv athena_args 'setenv bootargs console=${console},${baudrate} root=/dev/mmcblk2p${active_partition} rootwait rootfstype=ext4 rw quiet panic=20 systemd.crash_reboot root_ro=/dev/mmcblk2p${active_partition} root_rw=/dev/mmcblk2p${athena_part} crashkernel=64M'
    
    echo -e "${BRED}Entering brickable phase! ${NORMAL}"
    echo -ne "${BORANGE}" ; read -p "Continue? (y/n) " -r REPLY ; echo -ne "\n" ; echo -ne "${NORMAL}\n"
    [[ $REPLY =~ ^[Yy]$ ]] && changeBootcmd INSTALL || echo -e "${BRED}Bootloader has NOT been installed!${NORMAL}"
    
    systemctl start xochitl
    echo -e "${BGREEN}Athena has been installed ${BGREEN}:)${NORMAL}"
}
# General uninstallation
function uninstall() {
    echo -e "${BRED}Entering brickable phase! ${NORMAL}"
    echo -ne "${BORANGE}" ; read -p "Continue? (y/n) " -r REPLY ; echo -ne "\n" ; echo -ne "${NORMAL}\n"
    [[ $REPLY =~ ^[Yy]$ ]] && changeBootcmd UNINSTALL || return 1
    
    echo -e "${BORANGE}Removing Athena uboot vars...${NORMAL}"
    fw_setenv athena_fail
    fw_setenv athena_boot
    fw_setenv athena_bmmc
    fw_setenv athena_part
    fw_setenv athena_lfdt
    fw_setenv athena_limg
    fw_setenv athena_args
    
    echo -e "${BGREEN}Removing Athena...${NORMAL}"
    systemctl stop xochitl
    
    echo -ne "${BORANGE}" ; read -p "Erase overlayfs root (recommended)? (y/n) " -r REPLY ; echo -ne "${NORMAL}\n"
    [[ $REPLY =~ ^[Yy]$ ]] && rm -rf ${OVERLAYROOT} ${OVERLAYWORKROOT}
    
    echo -e "${BGREEN}Removing hooks from /home.${NORMAL}"
    rm -rf /home/root/.xochitlPlugins
    
    echo -e "${BRED}Removing Athena LD_PRELOAD from xochitl.service.${NORMAL}"
    sed -i '/Environment=LD_PRELOAD.*$/d' /lib/systemd/system/xochitl.service
    systemctl daemon-reload
    
    systemctl start xochitl
    echo -e "${BGREEN}Athena has been removed. ${BRED}:(${NORMAL}"
}

echo -en "${BGREEN}Welcome to the Athena setup, the first kernel and distro for the reMarkable 2 tablet.${NORMAL}\n"
echo -en "${BYELLOW}Please note that this piece of software is highly experimental and that you proceed at your own risk.${NORMAL}\n\n"
if fw_printenv | grep athena > /dev/null ; then
    echo -e "${BGREEN}Athena has been detected.${NORMAL}"
    echo -ne "${BORANGE}" ; read -p "Uninstall? (y/n) " -r REPLY ; echo -ne "${NORMAL}\n"
    [[ $REPLY =~ ^[Yy]$ ]] && uninstall
else
    echo -e "${BGREEN}Athena has ${BYELLOW}not${BGREEN} been detected.${NORMAL}"
    echo -ne "${BORANGE}" ; read -p "Install? (y/n) " -r REPLY ; echo -ne "${NORMAL}\n"
    [[ $REPLY =~ ^[Yy]$ ]] && install
fi
