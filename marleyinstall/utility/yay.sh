#!/usr/bin/env bash
set -e

# Must NOT be run as root
if [ "$EUID" -eq 0 ]; then
  echo "Do not run yay installer as root."
  exit 1
fi

cd "$HOME"

# Clean old build if it exists
if [ -d yay ]; then
  rm -rf yay
fi

git clone https://aur.archlinux.org/yay.git
cd yay

makepkg -si --noconfirm

