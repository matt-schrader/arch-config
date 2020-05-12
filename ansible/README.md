### Run ansible

```
git clone https://aur.archlinux.org/ansible-aur-git.git
cd ansible-aur-git
makepkg -si


git clone --recursive https://github.com/eoli3n/arch-config
cd arch-config/ansible
ansible-playbook install-{zfs,btrfs}.yml -K
```
