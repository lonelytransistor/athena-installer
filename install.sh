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
_opkgRootDir="${OVERLAYROOT}"
_opkgTmpDir="/tmp/opkg.bash/"

#OPKG
_opkgDir="opt/lib/opkg"
#_opkgRepoUrl=("https://lonelytransistor.github.io/athena" "https://toltec-dev.org/stable/rmall" "https://toltec-dev.org/stable/rm2" "https://bin.entware.net/armv7sf-k3.2")
#_opkgRepoNames=(athena toltecrmall toltecrm2 entware)
_opkgRepoUrl=("https://lonelytransistor.github.io/athena" "https://bin.entware.net/armv7sf-k3.2")
_opkgRepoNames=(athena entware)
function _opkg() {
    set -e
    
    if [ "$1" == "update" ]; then
        mkdir -p "${_opkgRootDir}" "${_opkgRootDir}/${_opkgDir}/info" "${_opkgTmpDir}"
        
        for i in "${!_opkgRepoNames[@]}"; do
            wget "${_opkgRepoUrl[$i]}/Packages" -O "${_opkgTmpDir}/${_opkgRepoNames[$i]}"
        done
    elif [ "$1" == "install" ]; then
        for i in "${!_opkgRepoNames[@]}"; do
            echo Checking in ${_opkgRepoNames[$i]}
            
            pData=$(cat "${_opkgTmpDir}/${_opkgRepoNames[$i]}" | awk "/Package: $2\$/ {p=1; next};/Package:/ {p=0}; {if (p==1) print \$0}")
            if [ "$pData" != "" ]; then
                pName="$2"
                pUrl=$(grep Filename <<< "${pData}" | tr ': ' '\n' | tail -n1)
                pVer=$(grep Version <<< "${pData}" | tr ': ' '\n' | tail -n1)
                pArch=$(grep Architecture <<< "${pData}" | tr ': ' '\n' | tail -n1)
                pDeps=$(grep Depends <<< "${pData}" | tr ': ' '\n' | tail -n1)
                
                if [ "${pUrl}" != "" ] && [ "${pVer}" != "" ]; then
                    wget "${_opkgRepoUrl[$i]}/${pUrl}" -O "${_opkgTmpDir}/pkg.tar.gz"
                    
                    tar -xzvf "${_opkgTmpDir}/pkg.tar.gz" -C "${_opkgTmpDir}/" ./data.tar.gz ./control.tar.gz
                    tar -xzvf "${_opkgTmpDir}/control.tar.gz" -C "${_opkgTmpDir}/" ./control
                    
                    tar -xzvf "${_opkgTmpDir}/data.tar.gz" -C "${_opkgRootDir}/" | sed -n "s|.\(/.*[^/]\)$|\1|p" > "${_opkgRootDir}/${_opkgDir}/info/${pName}.list"
                    cat "${_opkgTmpDir}/control" > "${_opkgRootDir}/${_opkgDir}/info/${pName}.control"

                    echo -ne "Package: ${pName}\n" >> "${_opkgRootDir}/${_opkgDir}/status"
                    echo -ne "Version: ${pVer}\n" >> "${_opkgRootDir}/${_opkgDir}/status"
                    [ "${pDeps}" != "" ] && echo -ne "Depends: ${pArch}\n" >> "${_opkgRootDir}/${_opkgDir}/status"
                    echo -ne "Status: install user installed\n" >> "${_opkgRootDir}/${_opkgDir}/status"
                    [ "${pArch}" != "" ] && echo -ne "Architecture: ${pArch}\n" >> "${_opkgRootDir}/${_opkgDir}/status"
                    echo -ne "Installed-Time: $(date +%s)\n" >> "${_opkgRootDir}/${_opkgDir}/status"
                    echo -ne "\n" >> "${_opkgRootDir}/${_opkgDir}/status"
                    break
                fi
            fi
        done
    fi
}
function _installOPKG() {
    dir_list=( bin etc lib/opkg tmp var/lock )
    for dir in "${dir_list[@]}"; do
        mkdir -p ${OVERLAYROOT}/opt/${dir}
    done

    # Add Entware
    local ENTWARE_REMOTE=https://bin.entware.net/armv7sf-k3.2/installer
    wget "${ENTWARE_REMOTE}/opkg" -O "${OVERLAYROOT}/opt/bin/opkg"
    wget "${ENTWARE_REMOTE}/opkg.conf" -O "${OVERLAYROOT}/opt/etc/opkg.conf"
    wget "${ENTWARE_REMOTE}/ld-2.27.so" -O "${OVERLAYROOT}/opt/lib/ld-2.27.so"
    wget "${ENTWARE_REMOTE}/libc-2.27.so" -O "${OVERLAYROOT}/opt/lib/libc-2.27.so"
    wget "${ENTWARE_REMOTE}/libgcc_s.so.1" -O "${OVERLAYROOT}/opt/lib/libgcc_s.so.1"
    wget "${ENTWARE_REMOTE}/libpthread-2.27.so" -O "${OVERLAYROOT}/opt/lib/libpthread-2.27.so"
    sed -i 's|http://|https://|g' ${OVERLAYROOT}/opt/etc/opkg.conf
    chmod 755 "${OVERLAYROOT}/opt/bin/opkg"
    
    # Add Toltec
    sed -i '/^src\/gz\b.*\bhttps:\/\/toltec\.delab\.re\//d' ${OVERLAYROOT}/opt/etc/opkg.conf
    sed -i '/^src\/gz\b.*\bhttps:\/\/toltec-dev\.org\//d' ${OVERLAYROOT}/opt/etc/opkg.conf
    echo "src/gz toltec https://toltec-dev.org/stable" >> ${OVERLAYROOT}/opt/etc/opkg.conf
    # Add Athena
    echo "src/gz athena https://lonelytransistor.github.io/athena" >> ${OVERLAYROOT}/opt/etc/opkg.conf
}
#

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

function install() {
    echo -e "${BORANGE}Installing Athena...${NORMAL}"
    systemctl stop xochitl
    
    echo -e "${BGREEN}Preparing overlayfs root.${NORMAL}"
    _installOPKG
    _opkg update
    _opkg install athena-hook
    _opkg install athena-linux
    
    echo -e "${BGREEN}Moving hooks into /home.${NORMAL}"
    mv ${_opkgRootDir}/home/root/.xochitlPlugins /home/root/.xochitlPlugins
    rmdir --ignore-fail-on-non-empty ${_opkgRootDir}/home/root
    rmdir --ignore-fail-on-non-empty ${_opkgRootDir}/home
    
    echo -e "${BRED}Patching Athena LD_PRELOAD into xochitl.service.${NORMAL}"
    sed -Ei '/Environment=(QML_XHR_ALLOW_FILE_READ|QML_XHR_ALLOW_FILE_WRITE|LD_PRELOAD).*$/d' /lib/systemd/system/xochitl.service
    sed -i "s|\[Service\]|[Service]\nEnvironment=QML_XHR_ALLOW_FILE_READ=1\nEnvironment=QML_XHR_ALLOW_FILE_WRITE=1\nEnvironment=LD_PRELOAD=${OVERLAYROOT}/usr/libexec/libAthenaXochitl.so|" /lib/systemd/system/xochitl.service
    systemctl daemon-reload
    
    echo -e "${BGREEN}Installing Athena uboot vars...${NORMAL}"
    fw_setenv athena_fail 1
    fw_setenv athena_home_partition 4
    fw_setenv athena_dtb '/.rootdir/boot/zero-sugar.dtb'
    fw_setenv athena_img '/.rootdir/boot/zImage'
    fw_setenv athena_load_fdt 'ext4load mmc ${mmcdev}:${mmcpart} ${fdt_addr} ${athena_fdt}'
    fw_setenv athena_load_img 'ext4load mmc ${mmcdev}:${mmcpart} ${loadaddr} ${athena_img}'
    fw_setenv athena_boot_mmc 'mmc dev ${mmcdev}; if mmc rescan; then if run athena_load_img; then if run athena_load_fdt; then bootz ${loadaddr} - ${fdt_addr}; fi; fi; fi;'
    fw_setenv athena_set_args 'setenv bootargs console=${console},${baudrate} root=/dev/mmcblk2p${active_partition} root_ro=/dev/mmcblk2p${active_partition} root_rw=/dev/mmcblk2p${athena_home_partition} quiet panic=20 systemd.crash_reboot crashkernel=64M'
    fw_setenv athena_boot 'if test ${athena_fail} != 1; then setenv athena_fail 1; saveenv; then run athena_set_bootargs; setenv mmcpart ${active_partition}; run athena_boot_mmc; fi;'
    
    echo -e "${BRED}Entering brickable phase! ${NORMAL}"
    echo -ne "${BORANGE}" ; read -p "Continue? (y/n) " -r REPLY ; echo -ne "\n" ; echo -ne "${NORMAL}\n"
    [[ $REPLY =~ ^[Yy]$ ]] && changeBootcmd INSTALL || echo -e "${BRED}Bootloader has NOT been installed!${NORMAL}"
    
    systemctl start xochitl
    echo -e "${BGREEN}Athena has been installed ${BGREEN}:)${NORMAL}"
}
function uninstall() {
    echo -e "${BRED}Entering brickable phase! ${NORMAL}"
    echo -ne "${BORANGE}" ; read -p "Continue? (y/n) " -r REPLY ; echo -ne "\n" ; echo -ne "${NORMAL}\n"
    [[ $REPLY =~ ^[Yy]$ ]] && changeBootcmd UNINSTALL || return 1
    
    echo -e "${BORANGE}Removing Athena uboot vars...${NORMAL}"
    fw_setenv athena_fail
    fw_setenv athena_home_partition
    fw_setenv athena_dtb
    fw_setenv athena_img
    fw_setenv athena_load_fdt
    fw_setenv athena_load_img
    fw_setenv athena_boot_mmc
    fw_setenv athena_set_args
    fw_setenv athena_boot
    
    echo -e "${BGREEN}Removing Athena...${NORMAL}"
    systemctl stop xochitl
    
    echo -ne "${BORANGE}" ; read -p "Erase overlayfs root (recommended)? (y/n) " -r REPLY ; echo -ne "${NORMAL}\n"
    [[ $REPLY =~ ^[Yy]$ ]] && rm -rf ${OVERLAYROOT}
    
    echo -e "${BGREEN}Removing hooks from /home.${NORMAL}"
    rm -rf /home/root/.xochitlPlugins
    
    echo -e "${BRED}Removing Athena LD_PRELOAD from xochitl.service.${NORMAL}"
    sed -Ei '/Environment=(QML_XHR_ALLOW_FILE_READ|QML_XHR_ALLOW_FILE_WRITE|LD_PRELOAD).*$/d' /lib/systemd/system/xochitl.service
    systemctl daemon-reload
    
    systemctl start xochitl
    echo -e "${BGREEN}Athena has been removed. ${BRED}:(${NORMAL}"
}

echo -en "${BGREEN}Hello to the Athena setup, the first kernel and distro for the reMarkable 2 tablet!${NORMAL}\n"
echo -en "${BYELLOW}Please note that this piece of software is highly experimental and you proceed at your own risk.${NORMAL}\n\n"
if fw_printenv | grep athena > /dev/null ; then
    echo -e "${BGREEN}Athena has been detected.${NORMAL}"
    echo -ne "${BORANGE}" ; read -p "Uninstall? (y/n) " -r REPLY ; echo -ne "${NORMAL}\n"
    [[ $REPLY =~ ^[Yy]$ ]] && uninstall
else
    echo -e "${BGREEN}Athena has not been detected.${NORMAL}"
    echo -ne "${BORANGE}" ; read -p "Install? (y/n) " -r REPLY ; echo -ne "${NORMAL}\n"
    [[ $REPLY =~ ^[Yy]$ ]] && install
fi
