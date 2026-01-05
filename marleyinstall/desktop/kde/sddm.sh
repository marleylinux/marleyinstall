#!/usr/bin/env bash
set -e

pacman -S --needed --noconfirm sddm
systemctl enable sddm

