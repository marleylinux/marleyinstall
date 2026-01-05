MarleyInstall

A simple Arch Linux post-install installer that discovers .sh install scripts in folders and runs them in guided or manual mode — with Steam Deck support, AUR (yay) support, TTY-safe fallback UI, and service enable prompts.

Features

Guided mode (category-by-category) + Manual mode (pick a category, then pick each script).

Steam Deck vs regular PC choice at the start:

Deck: installs from deck/, optional Decky Loader (and installs Steam first if needed).

Computer: installs from computer/ (ryzenadj + lact tooling message).

Script discovery is recursive (subfolders supported; filenames with spaces are safe).
