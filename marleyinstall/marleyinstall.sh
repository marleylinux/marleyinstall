#!/usr/bin/env bash
set -e

# marleyinstall.sh
BASE_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"

# Repo layout support:
# 1) marleyinstall.sh at repo root + scripts under ./marleyinstall/...
# 2) marleyinstall.sh inside ./marleyinstall/ alongside scripts
if [ -d "$BASE_DIR/marleyinstall" ]; then
  ROOT_DIR="$BASE_DIR/marleyinstall"
else
  ROOT_DIR="$BASE_DIR"
fi

say() { printf '%s\n' "$*"; }
p() { printf '%s %s\n' "$1" "$2"; }

is_root() { [ "${EUID:-$(id -u)}" -eq 0 ]; }
sudo_run() { if is_root; then "$@"; else sudo "$@"; fi; }

if ! is_root; then
  sudo -v
fi

# ---------- Quit handling ----------
maybe_quit() {
  case "${1,,}" in
    quit|exit)
      say ""
      say "$BANNER_LINE"
      p "$UI_NOTE" "Exited installer."
      say "$BANNER_LINE"
      exit 0
      ;;
  esac
}

prompt_read() {
  local __varname="$1"
  local __prompt="$2"
  local __default="${3-}"
  local __val=""

  if [ -t 0 ]; then
    if ! read -r -p "$__prompt" __val; then __val=""; fi
  elif [ -r /dev/tty ]; then
    if ! read -r -p "$__prompt" __val < /dev/tty; then __val=""; fi
  else
    __val=""
  fi

  maybe_quit "$__val"

  if [ -z "$__val" ] && [ -n "$__default" ]; then
    __val="$__default"
  fi

  printf -v "$__varname" '%s' "$__val"
}

confirm() {
  local yn=""
  prompt_read yn "$1 [y/N] (or 'quit'): " ""
  case "$yn" in
    [Yy]*) return 0 ;;
    *) return 1 ;;
  esac
}

# ---------- UI selection (emoji vs TTY-safe ASCII fallback) ----------
has_noto_emoji() {
  command -v pacman >/dev/null 2>&1 || return 1
  pacman -Q noto-fonts-emoji >/dev/null 2>&1
}

NOTO_PRESENT_AT_START=0
if has_noto_emoji; then NOTO_PRESENT_AT_START=1; fi

pick_ui() {
  if [ "${NO_EMOJI:-0}" = "1" ]; then USE_EMOJI=0; return; fi
  if [ "${FORCE_EMOJI:-0}" = "1" ]; then USE_EMOJI=1; return; fi
  if [ ! -t 1 ]; then USE_EMOJI=0; return; fi
  if [ "${TERM:-}" = "linux" ]; then USE_EMOJI=0; return; fi

  # Avoid tofu: if we install font during this run, keep ASCII until terminal restart.
  if [ "${NOTO_PRESENT_AT_START:-0}" = "1" ]; then
    USE_EMOJI=1
  else
    USE_EMOJI=0
  fi
}

pick_ui

if [ "${USE_EMOJI:-0}" = "1" ]; then
  UI_ML="🟪"
  UI_INFO="🟦"
  UI_NOTE="🟨"
  UI_OK="🟩"
  UI_ERR="🟥"

  INNER_LINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  BANNER_LINE="${UI_ML}${INNER_LINE}${UI_ML}"

  cat_line() {
    local box="$1"
    printf '%s%s%s\n' "$box" "$INNER_LINE" "$box"
  }
else
  UI_ML="<ml>"
  UI_INFO="<info>"
  UI_NOTE="<note>"
  UI_OK="<ok>"
  UI_ERR="<error>"

  INNER_LINE="======================================================"
  BANNER_LINE="$INNER_LINE"

  cat_line() { printf '%s\n' "$INNER_LINE"; }
fi

cat_section() {
  local box="$1"
  local title="$2"
  say ""
  cat_line "$box"
  p "$box" "$title"
  cat_line "$box"
}

header() {
  say ""
  say "$BANNER_LINE"
  p "$UI_ML" "Arch Install Script - MarleyLinux"
  say "$BANNER_LINE"
}

section() {
  say ""
  say "$BANNER_LINE"
  p "$UI_ML" "$1"
  say "$BANNER_LINE"
}

# ---------- Install update + deps BEFORE modes/tutorial output ----------
ensure_system_updated_and_deps() {
  command -v pacman >/dev/null 2>&1 || return 0

  p "$UI_INFO" "Updating system (pacman -Syu)..."
  set +e
  sudo_run pacman -Syu --noconfirm >/dev/null 2>&1
  local rc_update=$?
  set -e
  if [ "$rc_update" -ne 0 ]; then
    p "$UI_NOTE" "System update failed; continuing anyway."
  fi

  local -a pkgs=(noto-fonts-emoji fontconfig base-devel curl git)

  set +e
  sudo_run pacman -S --needed --noconfirm "${pkgs[@]}" >/dev/null 2>&1
  local rc_deps=$?
  set -e
  if [ "$rc_deps" -ne 0 ]; then
    p "$UI_NOTE" "Dependency install failed (base-devel/curl/git/noto-fonts-emoji). Continuing anyway."
    return 0
  fi

  set +e
  sudo_run fc-cache -f >/dev/null 2>&1
  set -e
}

# ---------- Tutorial ----------
tutorial() {
  section "Tutorial: add your own packages (use extra)"

  p "$UI_NOTE" "Tip: type 'quit' or 'exit' at ANY prompt to leave the installer."
  p "$UI_NOTE" "For colored emoji boxes: restart your GUI terminal after installing noto-fonts-emoji."
  p "$UI_NOTE" "Emoji boxes usually will NOT work in a TTY (TERM=linux). This script falls back to ASCII tags."
  p "$UI_NOTE" "Deps ensured at start: base-devel, curl, git, fontconfig, noto-fonts-emoji."
  say ""

  p "$UI_NOTE" "Put your custom scripts in:  $ROOT_DIR/extra"
  p "$UI_NOTE" "The installer discovers any .sh files there (including subfolders)."
  say ""

  p "$UI_NOTE" "Pacman example (official repo packages):"
  p "$UI_NOTE" "  File: extra/<package-name>.sh"
  say "    #!/bin/bash"
  say "    pacman -S --needed --noconfirm <package-name>"
  say ""

  p "$UI_NOTE" "AUR example:"
  p "$UI_NOTE" "  File: extra/<aur-package>.sh"
  say "    #!/bin/bash"
  say "    yay -S --needed --noconfirm <aur-package>"
  say ""

  p "$UI_NOTE" "Important (sudo/yay behavior):"
  p "$UI_NOTE" "  • If a script contains 'pacman', this installer runs it with sudo."
  p "$UI_NOTE" "  • If a script contains 'yay', this installer runs it as your user."
  p "$UI_NOTE" "  • If yay is missing, it offers to install it via utility/yay.sh."
  p "$UI_NOTE" "  • Do NOT use 'sudo yay' in scripts (AUR builds must not run as root)."
}

# ---------- Category helpers ----------
display_label() {
  case "$1" in
    linuxlts) printf '%s' "linux-lts" ;;
    linuxzen) printf '%s' "linux-zen" ;;
    *) printf '%s' "$1" ;;
  esac
}

category_tag() {
  local cat="$1"

  if [ "${USE_EMOJI:-0}" = "1" ]; then
    case "$cat" in
      kernel)   printf '%s' "🟦" ;;
      linux)    printf '%s' "🟦" ;;
      linuxlts) printf '%s' "🟨" ;;
      linuxzen) printf '%s' "🟥" ;;
      amd)      printf '%s' "🟥" ;;
      nvidia)   printf '%s' "🟩" ;;
      vulkan)   printf '%s' "🟦" ;;
      utility)  printf '%s' "🟨" ;;
      desktop)  printf '%s' "🟦" ;;
      hyprland) printf '%s' "🟦" ;;
      hyprapp)  printf '%s' "🟦" ;;
      gnome)    printf '%s' "🟨" ;;
      kde)      printf '%s' "🟪" ;;
      app)      printf '%s' "🟪" ;;
      extra)    printf '%s' "🟪" ;;
      deck)     printf '%s' "🟦" ;;
      computer) printf '%s' "🟦" ;;
      *)        printf '%s' "🟦" ;;
    esac
    return
  fi

  case "$cat" in
    kernel)   printf '%s' "<kernel>" ;;
    linux)    printf '%s' "<linux>" ;;
    linuxlts) printf '%s' "<lts>" ;;
    linuxzen) printf '%s' "<zen>" ;;
    amd)      printf '%s' "<amd>" ;;
    nvidia)   printf '%s' "<nvidia>" ;;
    vulkan)   printf '%s' "<vulkan>" ;;
    utility)  printf '%s' "<utils>" ;;
    desktop)  printf '%s' "<desktop>" ;;
    hyprland) printf '%s' "<hyprland>" ;;
    hyprapp)  printf '%s' "<hyprapp>" ;;
    gnome)    printf '%s' "<gnome>" ;;
    kde)      printf '%s' "<kde>" ;;
    app)      printf '%s' "<apps>" ;;
    extra)    printf '%s' "<extra>" ;;
    deck)     printf '%s' "<deck>" ;;
    computer) printf '%s' "<computer>" ;;
    *)        printf '%s' "<category>" ;;
  esac
}

# Category for summary:
# - kernel/ is special-cased to linux/lts/zen (2nd-level)
# - everything else is top-level folder (desktop stays "desktop" even for desktop/gnome etc.)
file_category() {
  local rel="${1#"$ROOT_DIR"/}"
  local first="${rel%%/*}"

  if [ "$first" = "$rel" ]; then
    printf '%s' "$first"
    return
  fi

  local rest="${rel#*/}"
  local second="${rest%%/*}"

  if [ "$first" = "kernel" ]; then
    printf '%s' "$second"
  else
    printf '%s' "$first"
  fi
}

# ---------- Summary tracking ----------
declare -A CAT_TOTAL CAT_RAN CAT_SKIPPED CAT_FAILED CAT_SKIPPED_ALL CAT_VISITED

inc() {
  local key="$1"
  local name="$2"
  eval "$name[\"\$key\"]=\$(( \${$name[\"\$key\"]:-0} + 1 ))"
}

mark_visited() { CAT_VISITED["$1"]=1; }
mark_skipped_all() { CAT_VISITED["$1"]=1; CAT_SKIPPED_ALL["$1"]=1; }

record_total() { inc "$1" CAT_TOTAL; }
record_ran() { inc "$1" CAT_RAN; }
record_skipped() { inc "$1" CAT_SKIPPED; }
record_failed() { inc "$1" CAT_FAILED; }

# ---------- Script command detection (avoid comment/string false positives) ----------
file_uses_cmd() {
  local f="$1"
  local cmd="$2"

  awk -v cmd="$cmd" '
    {
      line=$0
      sub(/^[ \t]+/, "", line)
      if (line ~ /^#/) next
      sub(/[ \t]#.*$/, "", line)
      if (line ~ ("(^|[^[:alnum:]_])" cmd "([^[:alnum:]_]|$)")) { found=1; exit }
    }
    END { exit !found }
  ' "$f"
}

# ---------- Paths (your structure) ----------
DESKTOP_DIR="$ROOT_DIR/desktop"
GNOME_DIR="$DESKTOP_DIR/gnome"
KDE_DIR="$DESKTOP_DIR/kde"
HYPRLAND_DIR="$DESKTOP_DIR/hyprland"
HYPRAPP_DIR="$HYPRLAND_DIR/hyprapp"

KERNEL_DIR="$ROOT_DIR/kernel"
KERNEL_LINUX_DIR="$KERNEL_DIR/linux"
KERNEL_LTS_DIR="$KERNEL_DIR/linuxlts"
KERNEL_ZEN_DIR="$KERNEL_DIR/linuxzen"

DECK_DIR="$ROOT_DIR/deck"
COMPUTER_DIR="$ROOT_DIR/computer"
NVIDIA_DIR="$ROOT_DIR/nvidia"

HYPRLAND_DONE=0

# ---------- fwupd auto-update (trigger only if installed during this run) ----------
fwupd_is_present() {
  command -v pacman >/dev/null 2>&1 || return 1
  command -v fwupdmgr >/dev/null 2>&1 || return 1
  pacman -Q fwupd >/dev/null 2>&1
}

FWUPD_WAS_PRESENT=0
FWUPD_UPDATED=0

maybe_fwupd_update() {
  if [ "${FWUPD_UPDATED:-0}" -eq 1 ]; then return 0; fi
  if [ "${FWUPD_WAS_PRESENT:-0}" -eq 1 ]; then return 0; fi
  if ! fwupd_is_present; then return 0; fi

  FWUPD_WAS_PRESENT=1

  section "Firmware update"
  p "$UI_INFO" "Detected fwupd installed during this run."
  p "$UI_INFO" "Updating firmware now (fwupdmgr)..."

  set +e
  sudo_run fwupdmgr refresh --force >/dev/null 2>&1
  sudo_run fwupdmgr get-updates >/dev/null 2>&1
  sudo_run fwupdmgr update -y >/dev/null 2>&1
  local rc=$?
  set -e

  if [ "$rc" -ne 0 ]; then
    p "$UI_NOTE" "Firmware update finished (no updates or requires manual action). Continuing."
  else
    p "$UI_OK" "Firmware update complete. Continuing."
  fi

  FWUPD_UPDATED=1
}

# ---------- Steam for Deck ----------
steam_is_present() {
  command -v pacman >/dev/null 2>&1 || return 1
  pacman -Q steam >/dev/null 2>&1
}

ensure_steam_for_deck() {
  if steam_is_present; then
    return 0
  fi

  section "Steam (required for Decky)"
  p "$UI_INFO" "Installing Steam so Decky can install..."

  set +e
  sudo_run pacman -S --needed --noconfirm steam >/dev/null 2>&1
  local rc=$?
  set -e

  if [ "$rc" -ne 0 ] || ! steam_is_present; then
    p "$UI_NOTE" "Steam install failed. Continuing anyway."
    return 1
  fi

  p "$UI_OK" "Steam installed."
  return 0
}

# ---------- Script discovery ----------
list_scripts() {
  local dir="$1"
  find "$dir" -type f -name "*.sh" -print0 2>/dev/null | sort -z
}

# ---------- yay handling ----------
YAY_READY=0

ensure_yay() {
  local triggered_by="$1"

  if [ "$YAY_READY" -eq 1 ]; then
    return 0
  fi

  if command -v yay >/dev/null 2>&1; then
    YAY_READY=1
    return 0
  fi

  local yay_script="$ROOT_DIR/utility/yay.sh"
  section "Package '$triggered_by' needs yay"

  if [ ! -f "$yay_script" ]; then
    p "$UI_ERR" "yay is not installed"
    p "$UI_ERR" "utility/yay.sh not found"
    p "$UI_NOTE" "Skipping package"
    return 1
  fi

  p "$UI_ERR" "yay is not installed"
  say ""

  local yn=""
  prompt_read yn "Install yay now using utility/yay.sh? [Y/n] (Enter = yes, or 'quit'): " ""
  case "$yn" in
    [Nn]*)
      p "$UI_NOTE" "Skipping package '$triggered_by' (yay not installed)"
      return 1
      ;;
  esac

  p "$UI_INFO" "Installing yay..."
  if ! bash "$yay_script"; then
    p "$UI_ERR" "yay script failed — skipping packages that require yay"
    return 1
  fi

  if ! command -v yay >/dev/null 2>&1; then
    p "$UI_ERR" "yay install failed — skipping packages that require yay"
    return 1
  fi

  YAY_READY=1
  p "$UI_OK" "yay installed"
  local _continue=""
  prompt_read _continue "Press Enter to continue (or 'quit')..." ""
  return 0
}

# Returns: 0 ok, 1 failed, 2 skipped
run_script() {
  local f="$1"
  local cat
  cat="$(file_category "$f")"
  mark_visited "$cat"

  local name
  name="$(basename "$f" .sh)"

  if file_uses_cmd "$f" "yay"; then
    if ! ensure_yay "$name"; then
      p "$UI_NOTE" "Skipped $name (requires yay)"
      return 2
    fi
    p "$UI_INFO" "Running: $name (user)"
    if bash "$f"; then
      p "$UI_OK" "Done: $name"
      maybe_fwupd_update
      return 0
    fi
    p "$UI_ERR" "Failed: $name"
    return 1
  fi

  if file_uses_cmd "$f" "pacman"; then
    p "$UI_INFO" "Running: $name (sudo)"
    if is_root; then
      if bash "$f"; then
        p "$UI_OK" "Done: $name"
        maybe_fwupd_update
        return 0
      fi
    else
      if sudo bash "$f"; then
        p "$UI_OK" "Done: $name"
        maybe_fwupd_update
        return 0
      fi
    fi
    p "$UI_ERR" "Failed: $name"
    return 1
  fi

  p "$UI_INFO" "Running: $name (user)"
  if bash "$f"; then
    p "$UI_OK" "Done: $name"
    maybe_fwupd_update
    return 0
  fi
  p "$UI_ERR" "Failed: $name"
  return 1
}

run_dir_all() {
  local dir="$1"
  local show_header="${2:-1}"

  local raw label box
  raw="$(basename "$dir")"
  label="$(display_label "$raw")"
  box="$(category_tag "$raw")"

  if [ "$show_header" -eq 1 ]; then
    cat_section "$box" "Install $label"
  fi

  local found=0
  while IFS= read -r -d '' f; do
    found=1
    local rel="${f#"$ROOT_DIR"/}"
    local cat
    cat="$(file_category "$f")"
    record_total "$cat"

    p "$UI_INFO" "$rel"
    if run_script "$f"; then
      record_ran "$cat"
    else
      local rc=$?
      if [ "$rc" -eq 2 ]; then record_skipped "$cat"; else record_failed "$cat"; fi
    fi
  done < <(list_scripts "$dir")

  if [ "$found" -eq 0 ]; then
    p "$UI_INFO" "No scripts found"
  fi
}

run_dir_all_skip_basename() {
  local dir="$1"
  local skip_basename="$2"
  local show_header="${3:-1}"

  local raw label box
  raw="$(basename "$dir")"
  label="$(display_label "$raw")"
  box="$(category_tag "$raw")"

  if [ "$show_header" -eq 1 ]; then
    cat_section "$box" "Install $label"
  fi

  local found=0
  while IFS= read -r -d '' f; do
    found=1

    local base
    base="$(basename "$f")"

    local rel="${f#"$ROOT_DIR"/}"
    local cat
    cat="$(file_category "$f")"
    record_total "$cat"

    if [ -n "$skip_basename" ] && [ "$base" = "$skip_basename" ]; then
      p "$UI_NOTE" "Skipped: $rel"
      record_skipped "$cat"
      continue
    fi

    p "$UI_INFO" "$rel"
    if run_script "$f"; then
      record_ran "$cat"
    else
      local rc=$?
      if [ "$rc" -eq 2 ]; then record_skipped "$cat"; else record_failed "$cat"; fi
    fi
  done < <(list_scripts "$dir")

  if [ "$found" -eq 0 ]; then
    p "$UI_INFO" "No scripts found"
  fi
}

run_dir_manual() {
  local dir="$1"
  local raw label box
  raw="$(basename "$dir")"
  label="$(display_label "$raw")"
  box="$(category_tag "$raw")"

  cat_section "$box" "Install $label (manual)"

  local found=0
  while IFS= read -r -d '' f; do
    found=1
    local rel="${f#"$ROOT_DIR"/}"
    local name
    name="$(basename "$f" .sh)"
    local cat
    cat="$(file_category "$f")"
    record_total "$cat"

    if confirm "Install $name? ($rel)"; then
      p "$UI_OK" "Selected: $name"
      if run_script "$f"; then
        record_ran "$cat"
      else
        local rc=$?
        if [ "$rc" -eq 2 ]; then record_skipped "$cat"; else record_failed "$cat"; fi
      fi
    else
      p "$UI_NOTE" "Skipped: $rel"
      record_skipped "$cat"
    fi
  done < <(list_scripts "$dir")

  if [ "$found" -eq 0 ]; then
    p "$UI_INFO" "No scripts found"
  fi
}

# ---------- Device choice FIRST ----------
DEVICE_CHOICE="skip"
DECKY_WANTED=0

device_choice() {
  section "Device choice"

  p "$UI_INFO" "Pick your device type (drivers/tools only)."
  p "$UI_NOTE" "No on-screen keyboard is installed by any option."
  say ""

  p "$(category_tag deck)"     "1) Steam Deck"
  p "$(category_tag computer)" "2) Regular computer"
  p "$UI_NOTE"                 "3) Skip"

  while :; do
    local c=""
    prompt_read c "Choose (1/2/3) (or 'quit'): " ""
    say ""

    case "$c" in
      1)
        DEVICE_CHOICE="deck"
        cat_section "$(category_tag deck)" "Install deck"

        p "$UI_NOTE" "Installs: PowerTools (better Steam Deck alternative)"
        p "$UI_NOTE" "Trackpads/mouse support works properly only in GNOME or KDE."
        p "$UI_NOTE" "Most window managers do NOT support it — use a keyboard + mouse."
        p "$UI_NOTE" "You may need 'alsamixer' in a terminal to increase speaker volume."
        p "$UI_NOTE" "No on-screen keyboard is installed (drivers/tools only)."
        say ""

        if [ -f "$DECK_DIR/deckyloader.sh" ] && confirm "Install Decky Loader (deckyloader.sh)?"; then
          DECKY_WANTED=1
        else
          DECKY_WANTED=0
        fi

        if [ "$DECKY_WANTED" -eq 1 ]; then
          ensure_steam_for_deck || true
          run_dir_all_skip_basename "$DECK_DIR" "" 0
        else
          run_dir_all_skip_basename "$DECK_DIR" "deckyloader.sh" 0
        fi
        return 0
        ;;
      2)
        DEVICE_CHOICE="computer"
        cat_section "$(category_tag computer)" "Install computer"

        p "$UI_NOTE" "Installs: ryzenadj + lact (CPU/GPU control)"
        p "$UI_NOTE" "No on-screen keyboard is installed (drivers/tools only)."
        say ""

        run_dir_all "$COMPUTER_DIR" 0
        return 0
        ;;
      3)
        DEVICE_CHOICE="skip"
        p "$UI_NOTE" "Skipped device setup"
        return 0
        ;;
      *)
        p "$UI_ERR" "Invalid selection. Try again."
        ;;
    esac
  done
}

# ---------- Kernel selection ----------
kernel_choice_guided() {
  section "Kernel choice"
  p "$(category_tag linux)"    "1) linux"
  p "$(category_tag linuxlts)" "2) linux-lts"
  p "$(category_tag linuxzen)" "3) linux-zen"
  p "$UI_NOTE"                "4) Skip"

  while :; do
    local k=""
    prompt_read k "Choose (1/2/3/4) (or 'quit'): " ""
    say ""

    case "$k" in
      1) run_dir_all "$KERNEL_LINUX_DIR"; return 0 ;;
      2) run_dir_all "$KERNEL_LTS_DIR"; return 0 ;;
      3) run_dir_all "$KERNEL_ZEN_DIR"; return 0 ;;
      4) p "$UI_NOTE" "Skipped kernel selection"; return 0 ;;
      *) p "$UI_ERR" "Invalid selection. Try again." ;;
    esac
  done
}

kernel_choice_manual() {
  section "Kernel (manual)"
  p "$(category_tag linux)"    "1) linux"
  p "$(category_tag linuxlts)" "2) linux-lts"
  p "$(category_tag linuxzen)" "3) linux-zen"
  p "$UI_NOTE"                "4) Back"

  while :; do
    local k=""
    prompt_read k "Choose (1/2/3/4) (or 'quit'): " ""
    say ""

    case "$k" in
      1) run_dir_manual "$KERNEL_LINUX_DIR"; return 0 ;;
      2) run_dir_manual "$KERNEL_LTS_DIR"; return 0 ;;
      3) run_dir_manual "$KERNEL_ZEN_DIR"; return 0 ;;
      4) return 0 ;;
      *) p "$UI_ERR" "Invalid selection. Try again." ;;
    esac
  done
}

# ---------- Desktop (only subfolders; no "desktop base") ----------
# NOTE: no top-level desktop banner here anymore; guided_flow prints it so prompts match other categories.
install_desktop_guided() {
  cat_section "$(category_tag gnome)" "Desktop → GNOME"
  if confirm "Install GNOME?"; then
    run_dir_all "$GNOME_DIR" 0
  else
    p "$UI_NOTE" "Skipped GNOME"
  fi

  cat_section "$(category_tag kde)" "Desktop → KDE"
  if confirm "Install KDE?"; then
    run_dir_all "$KDE_DIR" 0
  else
    p "$UI_NOTE" "Skipped KDE"
  fi

  cat_section "$(category_tag hyprland)" "Desktop → Hyprland"
  if confirm "Install Hyprland?"; then
    run_dir_all_skip_basename "$HYPRLAND_DIR" "" 0
    HYPRLAND_DONE=1

    if [ -d "$HYPRAPP_DIR" ]; then
      cat_section "$(category_tag hyprapp)" "Desktop → Hyprland → Hyprapp"
      if confirm "Install Hyprapp?"; then
        run_dir_all "$HYPRAPP_DIR" 0
      else
        p "$UI_NOTE" "Skipped Hyprapp"
      fi
    fi
  else
    p "$UI_NOTE" "Skipped Hyprland"
  fi
}

desktop_manual_menu() {
  cat_section "$(category_tag desktop)" "Desktop (manual)"
  p "$UI_INFO" "Pick a desktop folder to install from."
  say ""

  while :; do
    p "$(category_tag gnome)"    "1) GNOME"
    p "$(category_tag kde)"      "2) KDE"
    p "$(category_tag hyprland)" "3) Hyprland"
    p "$(category_tag hyprapp)"  "4) Hyprapp (requires Hyprland)"
    p "$UI_OK"                   "5) Back"

    local c=""
    prompt_read c "Select (1-5) (or 'quit'): " ""
    say ""

    case "$c" in
      1) run_dir_manual "$GNOME_DIR" ;;
      2) run_dir_manual "$KDE_DIR" ;;
      3)
        run_dir_manual "$HYPRLAND_DIR"
        HYPRLAND_DONE=1
        ;;
      4)
        if [ "$HYPRLAND_DONE" -ne 1 ]; then
          p "$UI_NOTE" "Hyprapp requires Hyprland. Install Hyprland first?"
          if confirm "Install Hyprland now?"; then
            run_dir_manual "$HYPRLAND_DIR"
            HYPRLAND_DONE=1
          else
            p "$UI_NOTE" "Skipped Hyprapp"
            continue
          fi
        fi
        run_dir_manual "$HYPRAPP_DIR"
        ;;
      5) return 0 ;;
      *) p "$UI_ERR" "Invalid selection. Try again." ;;
    esac

    say ""
  done
}

# ---------- Guided flow ----------
guided_flow() {
  section "Guided flow"
  kernel_choice_guided

  if [ "$DEVICE_CHOICE" != "deck" ]; then
    cat_section "$(category_tag nvidia)" "Install NVIDIA"
    if confirm "Install NVIDIA?"; then
      run_dir_all "$NVIDIA_DIR" 0
    else
      p "$UI_NOTE" "Skipped NVIDIA"
    fi
  fi

  cat_section "$(category_tag amd)" "Install AMD"
  if confirm "Install AMD?"; then run_dir_all "$ROOT_DIR/amd" 0; else p "$UI_NOTE" "Skipped AMD"; fi

  cat_section "$(category_tag vulkan)" "Install Vulkan"
  if confirm "Install Vulkan?"; then run_dir_all "$ROOT_DIR/vulkan" 0; else p "$UI_NOTE" "Skipped Vulkan"; fi

  cat_section "$(category_tag utility)" "Install utilities"
  if confirm "Install utilities?"; then run_dir_all "$ROOT_DIR/utility" 0; else p "$UI_NOTE" "Skipped utilities"; fi

  # ✅ FIX: desktop confirm now has the same banner style as other categories
  cat_section "$(category_tag desktop)" "Install desktop"
  if confirm "Install desktop?"; then
    install_desktop_guided
  else
    mark_skipped_all "desktop"
    p "$UI_NOTE" "Skipped desktop"
  fi

  cat_section "$(category_tag app)" "Install apps"
  if confirm "Install apps?"; then run_dir_all "$ROOT_DIR/app" 0; else p "$UI_NOTE" "Skipped apps"; fi

  cat_section "$(category_tag extra)" "Install extra"
  if confirm "Install extra?"; then run_dir_all "$ROOT_DIR/extra" 0; else p "$UI_NOTE" "Skipped extra"; fi
}

# ---------- Manual menu ----------
manual_menu() {
  section "Manual menu"
  p "$UI_INFO" "Pick a category, then choose each package inside it."
  say ""

  while :; do
    p "$(category_tag kernel)" "1) Kernel"

    if [ "$DEVICE_CHOICE" != "deck" ]; then
      p "$(category_tag nvidia)"  "2) NVIDIA"
      p "$(category_tag amd)"     "3) AMD"
      p "$(category_tag vulkan)"  "4) Vulkan"
      p "$(category_tag utility)" "5) utilities"
      p "$(category_tag desktop)" "6) desktop"
      p "$(category_tag app)"     "7) apps"
      p "$(category_tag extra)"   "8) extra"
      p "$UI_OK"                  "9) Finish"
    else
      p "$(category_tag amd)"     "2) AMD"
      p "$(category_tag vulkan)"  "3) Vulkan"
      p "$(category_tag utility)" "4) utilities"
      p "$(category_tag desktop)" "5) desktop"
      p "$(category_tag app)"     "6) apps"
      p "$(category_tag extra)"   "7) extra"
      p "$UI_OK"                  "8) Finish"
    fi

    local c=""
    prompt_read c "Select (or 'quit'): " ""
    say ""

    if [ "$DEVICE_CHOICE" != "deck" ]; then
      case "$c" in
        1) kernel_choice_manual ;;
        2) run_dir_manual "$NVIDIA_DIR" ;;
        3) run_dir_manual "$ROOT_DIR/amd" ;;
        4) run_dir_manual "$ROOT_DIR/vulkan" ;;
        5) run_dir_manual "$ROOT_DIR/utility" ;;
        6) desktop_manual_menu ;;
        7) run_dir_manual "$ROOT_DIR/app" ;;
        8) run_dir_manual "$ROOT_DIR/extra" ;;
        9) return 0 ;;
        *) p "$UI_ERR" "Invalid selection. Try again." ;;
      esac
    else
      case "$c" in
        1) kernel_choice_manual ;;
        2) run_dir_manual "$ROOT_DIR/amd" ;;
        3) run_dir_manual "$ROOT_DIR/vulkan" ;;
        4) run_dir_manual "$ROOT_DIR/utility" ;;
        5) desktop_manual_menu ;;
        6) run_dir_manual "$ROOT_DIR/app" ;;
        7) run_dir_manual "$ROOT_DIR/extra" ;;
        8) return 0 ;;
        *) p "$UI_ERR" "Invalid selection. Try again." ;;
      esac
    fi

    say ""
  done
}

# ---------- Post-install: offer to enable services (before summary) ----------
pkg_installed() {
  command -v pacman >/dev/null 2>&1 || return 1
  pacman -Q "$1" >/dev/null 2>&1
}

normalize_unit() {
  local u="$1"
  case "$u" in
    *.service|*.socket|*.target) printf '%s' "$u" ;;
    *) printf '%s.service' "$u" ;;
  esac
}

unit_exists() {
  command -v systemctl >/dev/null 2>&1 || return 1
  local unit
  unit="$(normalize_unit "$1")"
  systemctl list-unit-files "$unit" >/dev/null 2>&1
}

enable_unit() {
  local unit="$1"
  local now_flag="$2"
  local real
  real="$(normalize_unit "$unit")"

  if [ "$now_flag" -eq 1 ]; then
    sudo_run systemctl enable --now "$real" >/dev/null 2>&1
  else
    sudo_run systemctl enable "$real" >/dev/null 2>&1
  fi
}

offer_enable_services() {
  command -v systemctl >/dev/null 2>&1 || return 0

  local -a PKGS=(
    "lact"
    "networkmanager"
    "modemmanager"
    "bluez"
    "vmware"
    "cpupower"
    "greetd"
    "sddm"
    "gdm"
  )

  local -a UNITS=(
    "lactd"
    "NetworkManager"
    "ModemManager"
    "bluetooth"
    "vmware-networks-configuration.service"
    "cpupower"
    "greetd"
    "sddm"
    "gdm"
  )

  local -a NOW=(
    1
    1
    1
    1
    1
    1
    0
    0
    0
  )

  local any=0
  local i

  for i in "${!PKGS[@]}"; do
    if pkg_installed "${PKGS[$i]}" && unit_exists "${UNITS[$i]}"; then
      any=1
      break
    fi
  done

  if [ "$any" -eq 0 ]; then
    return 0
  fi

  section "Services"
  p "$UI_INFO" "Detected installed services. Enable any you want."
  say ""

  for i in "${!PKGS[@]}"; do
    local pkg="${PKGS[$i]}"
    local unit="${UNITS[$i]}"
    local now="${NOW[$i]}"

    if ! pkg_installed "$pkg"; then
      continue
    fi
    if ! unit_exists "$unit"; then
      continue
    fi

    local unit_display
    unit_display="$(normalize_unit "$unit")"

    if confirm "Enable $unit_display?"; then
      set +e
      enable_unit "$unit" "$now"
      local rc=$?
      set -e

      if [ "$rc" -ne 0 ]; then
        p "$UI_NOTE" "Failed to enable $unit_display"
      else
        if [ "$now" -eq 1 ]; then
          p "$UI_OK" "Enabled + started $unit_display"
        else
          p "$UI_OK" "Enabled $unit_display"
        fi
      fi
    else
      p "$UI_NOTE" "Left disabled: $unit_display"
    fi
  done
}

print_summary() {
  section "Summary"

  local -a order=(deck computer linux linuxlts linuxzen nvidia amd vulkan utility desktop app extra)
  local any=0

  for cat in "${order[@]}"; do
    if [ "${CAT_VISITED[$cat]+x}" != "x" ] && [ "${CAT_TOTAL[$cat]:-0}" -eq 0 ]; then
      continue
    fi
    any=1

    local label box total ran skipped failed
    label="$(display_label "$cat")"
    box="$(category_tag "$cat")"

    total="${CAT_TOTAL[$cat]:-0}"
    ran="${CAT_RAN[$cat]:-0}"
    skipped="${CAT_SKIPPED[$cat]:-0}"
    failed="${CAT_FAILED[$cat]:-0}"

    if [ "${CAT_SKIPPED_ALL[$cat]+x}" = "x" ] && [ "$total" -eq 0 ]; then
      p "$UI_NOTE" "$box $label → skipped (category)"
      continue
    fi

    p "$UI_INFO" "$box $label → ran: $ran | skipped: $skipped | failed: $failed | total: $total"
  done

  if [ "$any" -eq 0 ]; then
    p "$UI_INFO" "Nothing selected"
  fi
}

# ---------- Start ----------
ensure_system_updated_and_deps

# Snapshot fwupd state AFTER base update/deps (so only installs via scripts trigger updates)
if fwupd_is_present; then
  FWUPD_WAS_PRESENT=1
fi

header
p "$UI_INFO" "Modes:"
p "$UI_OK" "Guided (goes category-by-category)"
p "$UI_ERR" "Manual (pick a category; then pick each package)"
tutorial

device_choice

section "Install mode"
p "$UI_OK"  "1) Guided"
p "$UI_OK" "2) Manual"

while :; do
  MODE=""
  prompt_read MODE "Select (1/2) (or 'quit'): " ""
  say ""

  case "$MODE" in
    1) guided_flow; break ;;
    2) manual_menu; break ;;
    *) p "$UI_ERR" "Invalid selection. Try again." ;;
  esac
done

offer_enable_services
print_summary

say ""
say "$BANNER_LINE"
p "$UI_OK" "Installation complete. Enjoy! - MarleyLinux"
say "$BANNER_LINE"

