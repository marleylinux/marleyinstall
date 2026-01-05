#!/usr/bin/env bash
set -e

pacman -S --needed --noconfirm gdm
systemctl enable gdm

