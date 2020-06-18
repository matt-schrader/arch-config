#!/usr/bin/env bash

set -e

print () {
    echo -e "\n\033[1m> $1\033[0m\n"
}

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
  bootctl --path=/efi install

  # Generates boot entries
  mkdir -p /efi/loader/entries
	cat > /boot/loader/loader.conf <<"EOSF"
default arch
EOSF

  cat > /mnt/boot/loader/entries/arch.conf <<"EOSF"
title    Arch Linux
linux    /vmlinuz-linux
initrd   /initramfs-linux.img
options  root=PARTUUID=$(blkid -s PARTUUID -o value "$part_root") rw
EOSF

  # Create user
  useradd -m matthewschrader

EOF

# Set root passwd
print "Set root password"
arch-chroot /mnt /bin/passwd

# Set user passwd
print "Set user password"
arch-chroot /mnt /bin/passwd matthewschrader

# Configure sudo
print "Configure sudo"
cat > /mnt/etc/sudoers <<"EOF"
root ALL=(ALL) ALL
matthewschrader ALL=(ALL) NOPASSWD: ALL
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
print "Configure DNS"
rm /mnt/etc/resolv.conf
ln -s /run/systemd/resolve/resolv.conf /mnt/etc/resolv.conf
systemctl enable systemd-resolved --root=/mnt

# Finish
echo -e "\e[32mAll OK"
