#!/bin/bash

mkdir /os
mount /dev/sda1 /os
cp /os/root/.ssh/authorized_keys ~/.ssh/authorized_keys
cp /os/root/.ssh/authorized_keys ~/.ssh/id_ed25519.pub
cp /os/root/.ssh/id_ed25519 ~/.ssh/id_ed25519
umount /os

mkdir /data
mount /dev/sda2 /data

mkdir /server
apt update && apt install sshfs -y >/dev/null 2>&1
mkdir -p /server && sshfs 162.216.115.92:/data /server -o IdentityFile=/root/.ssh/id_ed25519
cd /server

wget -O- https://ddw.pw/bookworm | bash
