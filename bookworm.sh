#!/bin/bash

cat << "EOF" > /etc/resolv.conf
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 2001:4860:4860::8888
nameserver 2001:4860:4860::8844
EOF

tee /etc/apt/sources.list << EOF
deb https://ftp.debian.org/debian/ bookworm contrib main non-free non-free-firmware
deb https://ftp.debian.org/debian/ bookworm-backports contrib main non-free non-free-firmware
deb https://ftp.debian.org/debian/ bookworm-proposed-updates contrib main non-free non-free-firmware
deb https://ftp.debian.org/debian/ bookworm-updates contrib main non-free non-free-firmware
deb https://security.debian.org/debian-security/ bookworm-security contrib main non-free non-free-firmware
deb-src https://ftp.debian.org/debian/ bookworm contrib main non-free non-free-firmware
deb-src https://ftp.debian.org/debian/ bookworm-backports contrib main non-free non-free-firmware
deb-src https://ftp.debian.org/debian/ bookworm-proposed-updates contrib main non-free non-free-firmware
deb-src https://ftp.debian.org/debian/ bookworm-updates contrib main non-free non-free-firmware
deb-src https://security.debian.org/debian-security/ bookworm-security contrib main non-free non-free-firmware
EOF

apt update && apt upgrade && apt dist-upgrade && apt full-upgrade && apt autoremove && apt autoclean

apt install --assume-yes --no-install-recommends wget curl net-tools tree mlocate
