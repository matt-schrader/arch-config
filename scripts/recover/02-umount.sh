#!/usr/bin/env bash

print () {
    echo -e "\n\033[1m> $1\033[0m\n"
}

print "Disable SWAP"
swapoff /dev/zvol/zroot/swap

print "Umount /boot"
umount /mnt/boot

print "Umount slash dataset"
zfs zroot/ROOT/default

print "Umount zfs"
zfs umount -a

print "Export zpool"
zpool export zroot

# Finish
echo -e "\e[32mAll OK"
