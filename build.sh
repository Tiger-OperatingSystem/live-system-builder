#!/bin/bash

[ ! "${EUID}" = "0" ] && {
  sudo -E "${0}" ${@}
  exit ${?}
}

SKIP_SQUASHFS=0
SKIP_DEBOOSTRAP=0

HERE="$(dirname "$(readlink -f "${0}")")"

name=$(sed     's|[[:space:]]||g;s|#.*||g' distro.yaml | grep -m1 ^"name:"     | cut -d: -f2)
version=$(sed  's|[[:space:]]||g;s|#.*||g' distro.yaml | grep -m1 ^"base:"     | cut -d: -f2)
splash=$(sed   's|[[:space:]]||g;s|#.*||g' distro.yaml | grep -m1 ^"splash:"   | cut -d: -f2)
keyboard=$(sed 's|[[:space:]]||g;s|#.*||g' distro.yaml | grep -m1 ^"keyboard:" | cut -d: -f2)
mirror=$(sed   's|[[:space:]]||g;s|#.*||g' distro.yaml | grep -m1 ^"mirror:"   | cut -d: -f2)
user=$(sed     's|[[:space:]]||g;s|#.*||g' distro.yaml | grep -m1 ^"user:"     | cut -d: -f2)
host=$(sed     's|[[:space:]]||g;s|#.*||g' distro.yaml | grep -m1 ^"host:"     | cut -d: -f2)

echo "---------------------------------------------------------"
echo "  Verificando "
echo "---------------------------------------------------------"

grub_name=$(sed 's|#.*||g' distro.yaml | grep -m1 ^"name:" | cut -d: -f2 | sed 's/^[[:blank:]]*//;s/[[:blank:]]*$//')

name=$(echo "${name}" | sed 's| |_|g' | tr '[:upper:]' '[:lower:]')

for arg in ${@}; do
  [ "${arg}" = "--cleanup" ] && {
    [ -d "${HOME}/${name}" ] && {
      umount -l "${HOME}/${name}/chroot/dev"
      umount -l "${HOME}/${name}/chroot/sys"
      umount -l "${HOME}/${name}/chroot/proc"
      umount -l "${HOME}/${name}/chroot/run"

      umount -l "${HOME}/${name}/chroot/dev"
      umount -l "${HOME}/${name}/chroot/sys"
      umount -l "${HOME}/${name}/chroot/proc"
      umount -l "${HOME}/${name}/chroot/run"
      
      rm -rf    "${HOME}/${name}"
      mkdir -pv "${HOME}/${name}"
      fstrim -va
    }
    shift
  }

  [ "${arg}" = "--skip-squashfs" ] && {
    SKIP_SQUASHFS=1
    shift
  }
  
  [ "${arg}" = "--skip-deboostrap" ] && {
    SKIP_DEBOOSTRAP=1
    shift
  }
done


echo "---------------------------------------------------------"
echo "  Instalando dependencias de compilação"
echo "---------------------------------------------------------"

dependencies=(debootstrap mtools squashfs-tools xorriso casper lib32gcc-s1 grub-common grub-pc-bin grub-efi)

missing=""
for dep in ${dependencies[@]}; do
  dpkg -s ${dep} 2>/dev/null >/dev/null || {
    missing=" ${missing} ${dep}"
  }
done

[ ! "${missing}" = "" ] && {
  echo y | apt install ${dependencies[@]} -y
}

[ "${splash}" = "true" ]  && {
  echo "---------------------------------------------------------"
  echo "  Tela de boot ativa"
  echo "---------------------------------------------------------"
  splash=" quiet splash "
} || {
  splash=""
}

echo "---------------------------------------------------------"
echo "  Iniciando debootstrap"
echo "---------------------------------------------------------"

[ "${SKIP_DEBOOSTRAP}" = 0 ] && {
  debootstrap --arch=amd64 --variant=minbase          \
              --components=main,multiverse,universe   \
              "${version}" "${HOME}/${name}/chroot"
}

echo "---------------------------------------------------------"
echo "  Copiando configurações iniciais"
echo "---------------------------------------------------------"

cp -rf root-filesystem/* "${HOME}/${name}/chroot/"

echo "---------------------------------------------------------"
echo "  Iniciando sistemas de arquivo virtuais"
echo "---------------------------------------------------------"

mount --bind /dev "${HOME}/${name}/chroot/dev"
mount --bind /run "${HOME}/${name}/chroot/run"
chroot "${HOME}/${name}/chroot" mount none -t proc /proc
chroot "${HOME}/${name}/chroot" mount none -t devpts /dev/pts
chroot "${HOME}/${name}/chroot" sh -c "export HOME=/root"

[ "${SKIP_DEBOOSTRAP}" = 0 ] && {
  echo "---------------------------------------------------------"
  echo "  Instalando SystemD"
  echo "---------------------------------------------------------"

  chroot "${HOME}/${name}/chroot" apt install -y systemd-sysv
  chroot "${HOME}/${name}/chroot" sh -c "dbus-uuidgen > /etc/machine-id"
  chroot "${HOME}/${name}/chroot" ln -fs /etc/machine-id /var/lib/dbus/machine-id
  chroot "${HOME}/${name}/chroot" dpkg-divert --local --rename --add /sbin/initctl
  chroot "${HOME}/${name}/chroot" ln -s /bin/true /sbin/initctl
}

echo "---------------------------------------------------------"
echo "  Pré configurando GRUB, locales e resolv"
echo "---------------------------------------------------------"

chroot "${HOME}/${name}/chroot" sh -c "echo 'grub-pc grub-pc/install_devices_empty   boolean true'                  | debconf-set-selections"
chroot "${HOME}/${name}/chroot" sh -c "echo 'locales locales/locales_to_be_generated multiselect pt_BR.UTF-8 UTF-8' | debconf-set-selections"
chroot "${HOME}/${name}/chroot" sh -c "echo 'locales locales/default_environment_locale select pt_BR.UTF-8'         | debconf-set-selections"
chroot "${HOME}/${name}/chroot" sh -c "echo 'debconf debconf/frontend select Noninteractive'                        | debconf-set-selections"
chroot "${HOME}/${name}/chroot" sh -c "echo 'resolvconf resolvconf/linkify-resolvconf boolean false'                | debconf-set-selections"

echo "${name}" > "${HOME}/${name}/chroot/etc/hostname"

echo "---------------------------------------------------------"
echo "  Configurando repositórios base"
echo "---------------------------------------------------------"

cat <<EOF | tee "${HOME}/${name}/chroot/etc/apt/sources.list"
deb http://${mirror}.archive.ubuntu.com/ubuntu/ ${version} main restricted universe multiverse
deb http://${mirror}.archive.ubuntu.com/ubuntu/ ${version}-security main restricted universe multiverse
deb http://${mirror}.archive.ubuntu.com/ubuntu/ ${version}-updates main restricted universe multiverse
EOF


[ -f "lists/packages_32bits.list" ] && {
  echo "---------------------------------------------------------"
  echo "  Ativando suporte a pacotes 32 bit"
  echo "---------------------------------------------------------"
  chroot "${HOME}/${name}/chroot" dpkg --add-architecture i386
}

echo "---------------------------------------------------------"
echo "  Sincronizando repositórios"
echo "---------------------------------------------------------"

chroot ${HOME}/${name}/chroot apt update

[ -f "lists/ppas.list" ] && {
  echo "---------------------------------------------------------"
  echo "  Configurando PPAs"
  echo "---------------------------------------------------------"
  chroot "${HOME}/${name}/chroot" apt install -y software-properties-common
  sed '/^[[:space:]]*$/d' lists/ppas.list | sed 's|#.*||g' |sed "s|^|chroot \"${HOME}/${name}/chroot\" add-apt-repository -y |g" | sh
}

echo "---------------------------------------------------------"
echo "  Instalando pacotes com recomendações"
echo "---------------------------------------------------------"

echo y | chroot "${HOME}/${name}/chroot" apt install -y --fix-missing $(sed 's|#.*||g' lists/packages.list | xargs)

echo "---------------------------------------------------------"
echo "  Instalando pacotes sem recomendações"
echo "---------------------------------------------------------"

echo y | chroot "${HOME}/${name}/chroot" apt install -y --fix-missing --no-install-recommends \
                    $(sed 's|#.*||g' lists/packages_without_recomends.list | xargs)
	      
echo "---------------------------------------------------------"
echo "  Instalando pacotes avulsos"
echo "---------------------------------------------------------"

(
  mkdir -p "${HOME}/${name}/chroot/debian_single_debian_packages"
  cd "${HOME}/${name}/chroot/debian_single_debian_packages"
  sed 's|#.*||g' "${HERE}/lists/single_debian_package_files.list" | sed '/^[[:space:]]*$/d' | sed 's|^|wget |g' | sh

  echo y | chroot "${HOME}/${name}/chroot" bash -c 'apt install -y "/debian_single_debian_packages"/*'

  cd "${HERE}"
  
  rm -rfv "${HOME}/${name}/chroot/debian_single_debian_packages"
)
	                            
[ -f "lists/packages_32bits.list" ] && {
  echo "---------------------------------------------------------"
  echo "  Instalando pacotes 32 bit"
  echo "---------------------------------------------------------"
  echo y | chroot "${HOME}/${name}/chroot" apt install -y    \
              $(sed 's|#.*||g' lists/packages_32bits.list | xargs)
}

chmod +x "/chroot/usr/bin"/*

[ -f "${HOME}/${name}/chroot/usr/bin/finisher" ] && {
  echo "---------------------------------------------------------"
  echo "  Executando script de limpeza"
  echo "---------------------------------------------------------"

  chroot "${HOME}/${name}/chroot" finisher
  rm "${HOME}/${name}/chroot/usr/bin/finisher"
}

echo "---------------------------------------------------------"
echo "  Removendo pacotes indesejados"
echo "---------------------------------------------------------"

chroot "${HOME}/${name}/chroot" apt autoremove --purge -y \
           $(sed 's|#.*||g' lists/packages_to_remove.list | xargs)

echo "---------------------------------------------------------"
echo "  Habilitando internet em modo live"
echo "---------------------------------------------------------"

chroot "${HOME}/${name}/chroot" apt install --reinstall resolvconf
cat <<EOF > "${HOME}/${name}/chroot/etc/NetworkManager/NetworkManager.conf"
[main]
rc-manager=resolvconf
plugins=ifupdown,keyfile
dns=dnsmasq
[ifupdown]
managed=false
EOF
chroot "${HOME}/${name}/chroot" dpkg-reconfigure network-manager

echo "---------------------------------------------------------"
echo "  Finalizando compilação"
echo "---------------------------------------------------------"

chroot "${HOME}/${name}/chroot" truncate -s 0 /etc/machine-id
chroot "${HOME}/${name}/chroot" rm /sbin/initctl
chroot "${HOME}/${name}/chroot" dpkg-divert --rename --remove /sbin/initctl
chroot "${HOME}/${name}/chroot" sh -c "export HISTSIZE=0"

rm -rf chroot "${HOME}/${name}/chroot/tmp"/*
rm -rf chroot "${HOME}/${name}/chroot/root/.bash_history"

echo "RESUME=none"   > "${HOME}/${name}/chroot/etc/initramfs-tools/conf.d/resume"
echo "FRAMEBUFFER=y" > "${HOME}/${name}/chroot/etc/initramfs-tools/conf.d/splash"

sed -i "s/us/${keyboard}/g" "${HOME}/${name}/chroot/etc/default/keyboard"

cp -rf root-filesystem/* "${HOME}/${name}/chroot/"

echo "---------------------------------------------------------"
echo "  Instalando atualizações, se houver"
echo "---------------------------------------------------------"

echo y | chroot "${HOME}/${name}/chroot" apt upgrade -y

[ -f "lists/packages_to_remove_contents.list" ] && {
  echo "---------------------------------------------------------"
  echo "  Apagando conteúdo de pacotes indesejados"
  echo "---------------------------------------------------------"
  (
     echo '#!/bin/bash'
     echo 'cd /var/lib/dpkg/info/'
     echo 'for arg in ${@}; do'
     echo '  echo Clearing ${arg}...'
     echo '  sed "s|^|rm |g"  ${arg}.list | sh 2> /dev/null'
     echo '  apt-mark hold ${arg}'
     echo 'done'
  ) > "${HOME}/${name}/chroot/clear-packages"

  chmod +x "${HOME}/${name}/chroot/clear-packages"
  chroot "${HOME}/${name}/chroot" /clear-packages $(sed 's|#.*||g' lists/packages_to_remove_contents.list | xargs)
  rm "${HOME}/${name}/chroot/clear-packages"
}

[ -f "lists/files_and_directories_to_remove.list" ] && {
  echo "---------------------------------------------------------"
  echo "  Apagando arquivos e diretórios indesejados"
  echo "---------------------------------------------------------"
  (
     echo '#!/bin/bash'
     echo 'cd /var/lib/dpkg/info/'
     echo 'for arg in ${@}; do'
     echo '  echo Removing ${arg}...'
     echo '  find "${arg}" -type f -delete'
     echo 'done'
  ) > "${HOME}/${name}/chroot/clear-files"

  chmod +x "${HOME}/${name}/chroot/clear-files"
  chroot "${HOME}/${name}/chroot" /clear-files $(sed 's|#.*||g' lists/files_and_directories_to_remove.list | xargs)
  rm "${HOME}/${name}/chroot/clear-files"
}

[ -f "lists/packages_to_prevent_futher_updates.list" ] && {
  echo "---------------------------------------------------------"
  echo "  Prevenindo a atualizações de alguns pacotes"
  echo "---------------------------------------------------------"
  (
     echo '#!/bin/bash'
     echo 'cd /var/lib/dpkg/info/'
     echo 'for arg in ${@}; do'
     echo '  apt-mark hold ${arg}'
     echo 'done'
  ) > "${HOME}/${name}/chroot/clear-files"

  chmod +x "${HOME}/${name}/chroot/clear-files"
  chroot "${HOME}/${name}/chroot" /clear-files $(sed 's|#.*||g' lists/packages_to_prevent_futher_updates.list | xargs)
  rm "${HOME}/${name}/chroot/clear-files"
}

echo "---------------------------------------------------------"
echo "  Ativando boot splash"
echo "---------------------------------------------------------"

echo "${splash}"

chmod +x "${HOME}/${name}/chroot/usr/share/plymouth/themes/boot-splash/boot-splash.plymouth"
chmod +x "${HOME}/${name}/chroot/usr/share/plymouth/themes/boot-splash/boot-splash.script"

chroot "${HOME}/${name}/chroot" cp "/usr/share/plymouth/themes/boot-splash/boot-splash.plymouth" "/usr/share/plymouth/themes/xubuntu-logo/xubuntu-logo.plymouth"
  
chroot "${HOME}/${name}/chroot" update-initramfs -u -k all

echo "---------------------------------------------------------"
echo "  Inicializando criação da imagem ISO"
echo "---------------------------------------------------------"

cd "${HOME}/${name}"
mkdir -pv image/{boot/grub,casper,isolinux,preseed}

cp chroot/boot/vmlinuz image/casper/vmlinuz
cp chroot/boot/$(ls -t1 chroot/boot/ | grep "initrd" | head -n 1) image/casper/initrd
touch "image/${name}"

cat <<EOF > image/boot/grub/loopback.cfg
menuentry "${grub_name}" {
   linux /casper/vmlinuz file=/cdrom/preseed/${name}.seed boot=casper ${splash} username=${user} hostname=${host} locale=pt_BR ---
   initrd /casper/initrd
}
menuentry "${grub_name} (Modo Recovery)" {
   linux /casper/vmlinuz file=/cdrom/preseed/${name}.seed boot=casper ${splash} username=${user} hostname=${host} locale=pt_BR recovery ---
   initrd /casper/initrd
}
menuentry "${grub_name} (Modo Recovery - failseafe)" {
   linux /casper/vmlinuz file=/cdrom/preseed/${name}.seed boot=casper ${splash} username=${user} hostname=${host} locale=pt_BR nomodeset recovery ---
   initrd /casper/initrd
}

menuentry "${grub_name} (Iniciar na RAM)" {
   linux /casper/vmlinuz file=/cdrom/preseed/${name}.seed boot=casper ${splash} username=${user} hostname=${host} locale=pt_BR toram ---
   initrd /casper/initrd
}

menuentry "${grub_name} - NVIDIA Legacy" {
   linux /casper/vmlinuz file=/cdrom/preseed/${name}.seed boot=casper ${splash} username=${user} hostname=${host} locale=pt_BR modprobe.blacklist=nvidia,nvidia_uvm,nvidia_drm,nvidia_modeset ---
   initrd /casper/initrd
}

menuentry "Reiniciar" {reboot}
menuentry "Desligar" {halt}
EOF

(
  echo
  cat <<EOF
search --set=root --file /${name}
insmod all_video
set default="0"
set timeout=15

if loadfont /boot/grub/unicode.pf2 ; then
    insmod gfxmenu
	insmod jpeg
	insmod png
	set gfxmode=auto
	insmod efi_gop
	insmod efi_uga
	insmod gfxterm
	terminal_output gfxterm
fi

EOF
  cat image/boot/grub/loopback.cfg
) > image/isolinux/grub.cfg

echo "---------------------------------------------------------"
echo "  Pacotes pré-instalados no sistema"
echo "---------------------------------------------------------"
echo 
chroot chroot dpkg-query -W --showformat='${Package} ${Version}\n' | tee image/casper/filesystem.manifest | cat -n
echo

cp image/casper/filesystem.manifest image/casper/filesystem.manifest-desktop
sed -i '/ubiquity/d'                   image/casper/filesystem.manifest-desktop
sed -i '/casper/d'                     image/casper/filesystem.manifest-desktop
sed -i '/discover/d'                   image/casper/filesystem.manifest-desktop
sed -i '/laptop-detect/d'              image/casper/filesystem.manifest-desktop
sed -i '/os-prober/d'                  image/casper/filesystem.manifest-desktop

sed 's|[[:space:]]||g;s|#.*||g' "${HERE}/lists/packages_to_remove_after_install.list" | sort | tee image/casper/filesystem.manifest-remove

[ "${SKIP_SQUASHFS}" = 0 ] && {
  echo
  echo "---------------------------------------------------------"
  echo "  Comprimindo imagem do sistema"
  echo "---------------------------------------------------------"
  echo
  umount -l "${HOME}/${name}/chroot/dev/pts"
  umount -l "${HOME}/${name}/chroot/dev"
  umount -l "${HOME}/${name}/chroot/sys"
  umount -l "${HOME}/${name}/chroot/proc"
  umount -l "${HOME}/${name}/chroot/run"

  umount -l "${HOME}/${name}/chroot/dev/pts"
  umount -l "${HOME}/${name}/chroot/dev"
  umount -l "${HOME}/${name}/chroot/sys"
  umount -l "${HOME}/${name}/chroot/proc"
  umount -l "${HOME}/${name}/chroot/run"

  rm -rf chroot/dev/*
  rm -rf chroot/sys/*
  rm -rf chroot/proc/*
  rm -rf chroot/home/*
  rm -rf chroot/tmp/*

  mkdir -p chroot/home
  mkdir -p chroot/tmp

  mksquashfs chroot image/casper/filesystem.squashfs -comp xz -noappend
  echo
}

printf $(du -sx --block-size=1 chroot | cut -f1) > image/casper/filesystem.size

cat <<EOF > image/README.diskdefines
#define DISKNAME  ${name}
#define TYPE  binary
#define TYPEbinary  1
#define ARCH  amd64
#define ARCHamd64  1
#define DISKNUM  1
#define DISKNUM1  1
#define TOTALNUM  0
#define TOTALNUM0  1
EOF

cd ${HOME}/${name}/image

grub-mkstandalone                         \
   --format=x86_64-efi                    \
   --output=isolinux/bootx64.efi          \
   --locales=""                           \
   --fonts=""                             \
   "boot/grub/grub.cfg=isolinux/grub.cfg"
(
   cd isolinux &&                                   \
   dd if=/dev/zero of=efiboot.img bs=1M count=10 && \
   mkfs.vfat efiboot.img &&                         \
   mmd -i efiboot.img efi efi/boot &&               \
   mcopy -i efiboot.img ./bootx64.efi ::efi/boot/
)

grub-mkstandalone --format=i386-pc --output=isolinux/core.img                       \
   --install-modules="linux16 linux normal iso9660 biosdisk memdisk search tar ls"  \
   --modules="linux16 linux normal iso9660 biosdisk search" --locales="" --fonts="" \
   "boot/grub/grub.cfg=isolinux/grub.cfg"

cat /usr/lib/grub/i386-pc/cdboot.img isolinux/core.img > isolinux/bios.img

/bin/bash -c '(find . -type f -print0 | xargs -0 md5sum | grep -v "\./md5sum.txt" > md5sum.txt)'

mkdir -pv ../iso 
xorriso -as mkisofs -iso-level 3 -full-iso9660-filenames         \
   -volid "${name}" -eltorito-boot boot/grub/bios.img            \
   -no-emul-boot -boot-load-size 4 -boot-info-table              \
   --eltorito-catalog boot/grub/boot.cat --grub2-boot-info       \
   --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img             \
   -eltorito-alt-boot -e EFI/efiboot.img                         \
   -no-emul-boot -append_partition 2 0xef isolinux/efiboot.img   \
   -output "../iso/${name}-amd64.iso" -graft-points "."          \
      /boot/grub/bios.img=isolinux/bios.img                      \
      /EFI/efiboot.img=isolinux/efiboot.img

md5sum ../iso/${name}-amd64.iso > ../iso/${name}-amd64.md5

ISO=$(readlink -f ../iso/${name}-amd64.iso)

[ -f "${ISO}" ] && {
  echo
  echo "---------------------------------------------------------"
  echo "  ISO: "
  echo "    "$( du -sh "${ISO}")
  echo "---------------------------------------------------------"
  echo
}
