#!/bin/bash

echo "================================= enable forward and bbr ======================================="
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf && \
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf && \
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf && \
sysctl -p | grep -E "bbr|ip_forward"

echo "================================= create /etc/resolv.conf ======================================"
cat << "EOF" > /etc/resolv.conf
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 2001:4860:4860::8888
nameserver 2001:4860:4860::8844
EOF

echo "================================= create .bash_aliases ========================================="

cat << "EOF" > ~/.bash_aliases
if [ -x /usr/bin/dircolors ]; then
  test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
  export LS_OPTIONS='--color=auto'
  alias ls='ls $LS_OPTIONS -A'
  alias ll='ls $LS_OPTIONS -lA'
  alias l='ls $LS_OPTIONS -lAh'
  alias dir='dir $LS_OPTIONS -l'
  alias vdir='vdir $LS_OPTIONS -l'
  alias ip='ip $LS_OPTIONS'
  alias diff='diff $LS_OPTIONS'
  alias grep='grep $LS_OPTIONS'
  alias fgrep='fgrep $LS_OPTIONS'
  alias egrep='egrep $LS_OPTIONS'
fi

alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

alias cls='clear'
alias nano='nano -lK'
alias ns='netstat -plunt'
alias ss='ss -plunt'
alias wgetncc='wget --no-check-certificate'
alias finnix='grub-reboot finnix;reboot'
alias update='apt update; apt upgrade -y; apt autoremove -y; apt autoclean -y; apt clean'
EOF

echo "================================= create .bashrc ==============================================="

cat << "EOF" > ~/.bashrc

# If not running interactively, don't do anything!
case $- in
  *i*) ;;
    *) return;;
esac

TERM=xterm-256color
COLORTERM=24bit
#COLORTERM=truecolor

# bash will check the terminal size when it regains control.
shopt -s checkwinsize

# Enable history appending instead of overwriting.
shopt -s histappend

HISTSIZE=1000
HISTFILESIZE=2000
HISTCONTROL=ignoreboth

case "$TERM" in
  xterm-color|*-256color) color_prompt=yes;;
esac
if [ -n "$force_color_prompt" ]; then
  if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
    color_prompt=yes
  else
    color_prompt=
  fi
fi
if [ "$color_prompt" = yes ]; then
  PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
  PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

case "$TERM" in
xterm*|rxvt*)
PS1="# \[\e[0m\][\[\e[0;94m\]\D{%F} \[\e[0;91m\]\t\[\e[0m\]] \[\e[0m\][\[\e[0;94m\]$(uname -s) \[\e[0;91m\]$(uname -r)\[\e[0m\]] [\[\e[0;94m\]$(lsb_release -cs)\[\e[0m\] \[\e[0;91m\]$(cat /etc/debian_version)\[\e[0m\]] \[\e[0m\][\[\e[0;94m\]$(echo $SHELL) \[\e[0;91m\]\V\[\e[0m\]] \[\e[0m\][\[\e[0;94m\]\u\[\e[0;30m\]@\[\e[0m\]\[\e[0;91m\]\h\[\e[0m\]] \[\e[0m\][\[\e[0;94m\]\$(pwd)\[\e[0m\]]\n\[\e[0;91m\]\\$ \[\e[0m\]"  ;;
*)
  ;;
esac

export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

if [ -f ~/.bash_aliases ]; then
  . ~/.bash_aliases
fi

if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
  . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
  . /etc/bash_completion
  fi
fi
EOF

echo "================================= create .tmux.conf ============================================"

cat << "EOF" > ~/.tmux.conf

set-option -g prefix Escape
bind-key Escape send-prefix

set-option -g default-terminal "xterm-256color"
set-option -sa terminal-overrides ",xterm*:Tc"

set-option -g history-limit 5000
set-option -s escape-time 0
set-option -g window-size largest
set-option -g message-style bg=green
set-window-option -g aggressive-resize on
EOF

echo "================================= create .bash_profile ========================================="

cat << "EOF" > ~/.bash_profile
if [[ -z "$TMUX" ]] && [ "$SSH_TTY" == "/dev/pts/0" ]; then
    tmux attach -t default || tmux new -s default
fi
if [ "$BASH" ]; then
  if [ -f ~/.bashrc ]; then
    source ~/.bashrc
  fi
fi
EOF

echo "================================= update and install ==========================================="

tee /etc/apt/sources.list << EOF
deb https://ftp.debian.org/debian/ trixie contrib main non-free non-free-firmware
deb https://ftp.debian.org/debian/ trixie-backports contrib main non-free non-free-firmware
deb https://ftp.debian.org/debian/ trixie-proposed-updates contrib main non-free non-free-firmware
deb https://ftp.debian.org/debian/ trixie-updates contrib main non-free non-free-firmware
deb https://security.debian.org/debian-security/ trixie-security contrib main non-free non-free-firmware
deb-src https://ftp.debian.org/debian/ trixie contrib main non-free non-free-firmware
deb-src https://ftp.debian.org/debian/ trixie-backports contrib main non-free non-free-firmware
deb-src https://ftp.debian.org/debian/ trixie-proposed-updates contrib main non-free non-free-firmware
deb-src https://ftp.debian.org/debian/ trixie-updates contrib main non-free non-free-firmware
deb-src https://security.debian.org/debian-security/ trixie-security contrib main non-free non-free-firmware
EOF

apt update && apt install --assume-yes --no-install-recommends wget curl tmux net-tools tree mlocate lsb-release

# echo "================================= source .bash_profile ========================================="
# source ~/.bash_profile

# echo "================================= Disconet and Reconnect========================================"
read -p "Press enter to continue"

exit
