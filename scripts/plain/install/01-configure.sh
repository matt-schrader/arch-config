#!/usr/bin/env bash

set -e

print () {
    echo -e "\n\033[1m> $1\033[0m\n"
}

# Tests
ls /sys/firmware/efi/efivars > /dev/null && \
  ping archlinux.org -c 1 > /dev/null &&    \
  timedatectl set-ntp true > /dev/null &&   \
  print "Tests ok"

# Set DISK
#select ENTRY in $(ls /dev/disk/by-id/);
#do
#    DISK="/dev/disk/by-id/$ENTRY"
#    echo "Installing on $ENTRY."
#    break
#done
#
#read -p "> Do you want to wipe all datas on $ENTRY ?" -n 1 -r
#echo # move to a new line
#if [[ $REPLY =~ ^[Yy]$ ]]
#then
#    # Clear disk
#    dd if=/dev/zero of=$DISK bs=512 count=1
#    wipefs -af $DISK
#    sgdisk -Zo $DISK
#fi

devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
device=$(dialog --stdout --menu "Select installtion disk" 0 0 0 ${devicelist}) || exit 1
clear

### Set up logging ###
exec 1> >(tee "stdout.log")
exec 2> >(tee "stderr.log")

# EFI part
### Setup the disk and partitions ###
swap_size=$(free --mebi | awk '/Mem:/ {print $2}')
swap_end=$(( $swap_size + 129 + 1 ))MiB

parted --script "${device}" -- mklabel gpt \
  mkpart ESP fat32 1Mib 129MiB \
  set 1 boot on \
  mkpart primary linux-swap 129MiB ${swap_end} \
  mkpart primary ext4 ${swap_end} 100%

# Simple globbing was not enough as on one device I needed to match /dev/mmcblk0p1
# but not /dev/mmcblk0boot1 while being able to match /dev/sda1 on other devices.
part_boot="$(ls ${device}* | grep -E "^${device}p?1$")"
part_swap="$(ls ${device}* | grep -E "^${device}p?2$")"
part_root="$(ls ${device}* | grep -E "^${device}p?3$")"

wipefs "${part_boot}"
wipefs "${part_swap}"
wipefs "${part_root}"

mkfs.vfat -F32 "${part_boot}"
mkswap "${part_swap}"
mkfs.f2fs -f "${part_root}"

swapon "${part_swap}"
mount "${part_root}" /mnt
mkdir /mnt/boot
mount "${part_boot}" /mnt/boot

# Sort mirrors
print "Sort mirrors"
pacman -Sy reflector --noconfirm
reflector --country "United States"  --latest 6 --protocol https --sort rate --save /etc/pacman.d/mirrorlist

# Install
print "Install Arch Linux"
pacstrap /mnt base base-devel linux-lts linux-lts-headers linux-firmware amd-ucode efibootmgr vim git ansible connman 

# Generate fstab 
print "Generate fstab"
genfstab -U /mnt >> /mnt/etc/fstab
 
# Set hostname
echo "Please enter hostname :"
read hostname
echo $hostname > /mnt/etc/hostname

user=$(dialog --stdout --inputbox "Enter admin username" 0 0) || exit 1
clear
: ${user:?"user cannot be empty"}

password=$(dialog --stdout --passwordbox "Enter admin password" 0 0) || exit 1
clear
: ${password:?"password cannot be empty"}
password2=$(dialog --stdout --passwordbox "Enter admin password again" 0 0) || exit 1
clear
[[ "$password" == "$password2" ]] || ( echo "Passwords did not match"; exit 1; )

# Configure /etc/hosts
print "Configure hosts file"
cat > /mnt/etc/hosts <<EOF
#<ip-address>	<hostname.domain.org>	<hostname>
127.0.0.1	    localhost   	        $hostname
::1   		    localhost              	$hostname
EOF

# Prepare locales and keymap
print "Prepare locales and keymap"
echo "KEYMAP=us" > /mnt/etc/vconsole.conf
sed -i 's/#\(en_US.UTF-8\)/\1/' /mnt/etc/locale.gen
echo 'LANG="en_US.UTF-8"' > /mnt/etc/locale.conf

# Prepare initramfs
print "Prepare initramfs"
cat > /mnt/etc/mkinitcpio.conf <<"EOF"
MODULES=()
BINARIES=()
FILES=()
HOOKS=(base udev autodetect modconf block keyboard keymap filesystems)
COMPRESSION="lz4"
EOF

# Chroot and configure
print "Chroot and configure system"

arch-chroot /mnt /bin/bash -xe <<"EOF"

  # Sync clock
  hwclock --systohc

  # Set date
  timedatectl set-ntp true
  timedatectl set-timezone America/Chicago

  # Generate locale
  locale-gen
  source /etc/locale.conf

  # Generate Initramfs
  mkinitcpio -P

  # Install bootloader
  bootctl --path=/mnt install

  # Generates boot entries
  mkdir -p /boot/loader/entries
	cat > /boot/loader/loader.conf <<"EOSF"
default arch
EOSF

  cat > /boot/loader/entries/arch.conf <<"EOSF"
title    Arch Linux
linux    /vmlinuz-linux
initrd   /initramfs-linux.img
options  root=PARTUUID=$(blkid -s PARTUUID -o value "$part_root") rw
EOSF

  # Create user
	useradd -mU -G lock,docker,wheel,uucp,video,audio,storage,games,input "$user"

EOF

echo "$user:$password" | chpasswd --root /mnt
echo "root:$password" | chpasswd --root /mnt

# Configure sudo
print "Configure sudo"
cat > /mnt/etc/sudoers <<"EOF"
root ALL=(ALL) ALL
$user ALL=(ALL) NOPASSWD: ALL
Defaults rootpw
EOF

# Configure network
print "Configure networking"
cat > /mnt/etc/systemd/network/enoX.network <<"EOF"
[Match]
Name=en*

[Network]
MulticastDNS=yes
DHCP=ipv4
IPForward=yes

[DHCP]
UseDomains=yes
UseDNS=yes
RouteMetric=10
EOF

systemctl enable systemd-networkd --root=/mnt
systemctl disable systemd-networkd-wait-online --root=/mnt

cat > /mnt/etc/connman/main.conf <<"EOF"
[General]
PreferredTechnologies=ethernet,wifi
NetworkInterfaceBlacklist = vmnet,vboxnet,virbr,ifb,ve-,vb-,docker,veth,eth,wlan
AllowHostnameUpdates = false
AllowDomainnameUpdates = false
SingleConnectedTechnology = true
EOF
systemctl enable connman --root=/mnt

# Configure DNS
# Might need to add floonetwork to resolv.conf
#print "Configure DNS"
#rm /mnt/etc/resolv.conf
#ln -s /run/systemd/resolve/resolv.conf /mnt/etc/resolv.conf
#systemctl enable systemd-resolved --root=/mnt

# Finish
echo -e "\e[32mAll OK"
