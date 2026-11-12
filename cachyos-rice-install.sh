#!/usr/bin/env bash
# CachyOS / Arch installer for binnewbs/arch-hyprland rice
# Run from: ~/rice/arch-hyprland
set -Eeuo pipefail

ROOT="${HOME}/rice/arch-hyprland"
CONFIG_SRC="${ROOT}/.config"
WALL_SRC="${ROOT}/wallpapers"
WALL_DEST="${HOME}/Pictures/wallpapers"
BACKUP_ROOT="${HOME}/.local/share/arch-hyprland-backup/$(date +%Y%m%d-%H%M%S)"
LOG="${HOME}/.local/share/arch-hyprland-install.log"

# Colours
if [[ -t 1 ]]; then
  C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_CYAN=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_BOLD=''; C_RESET=''
fi

step=0
total=7
say()  { printf '%b\n' "$*"; }
ok()   { say "${C_GREEN}  [++++++]${C_RESET} $*"; }
warn() { say "${C_YELLOW}  [!!!!!!]${C_RESET} $*"; }
die()  { say "${C_RED}ОШИБКА: $*${C_RESET}" >&2; exit 1; }
step() { ((step+=1)); printf '\n%b[%d/%d] %s%b\n' "$C_CYAN$C_BOLD" "$step" "$total" "$1" "$C_RESET"; }

on_error() {
  local code=$?
  warn "Скрипт остановился (код ${code}). Лог: ${LOG}"
  exit "$code"
}
trap on_error ERR
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

clear 2>/dev/null || true
say "${C_CYAN}${C_BOLD}"
cat <<'BANNER'
      _          
 _ __(_) ___ ___ 
| '__| |/ __/ _ \
| |  | | (_|  __/
|_|  |_|\___\___|

    HYPRLAND RICE INSTALLER
    CachyOS edition
BANNER
say "${C_RESET}"

# 1. Preconditions
step "Проверка системы и файлов"
[[ -d "$CONFIG_SRC" ]] || die "Не найдена папка $CONFIG_SRC. Проверь, что архив распакован именно туда."
[[ -d "$WALL_SRC" ]] || die "Не найдена папка wallpapers внутри $ROOT."
[[ -r /etc/os-release ]] || die "Не удалось определить дистрибутив."
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == "cachyos" || " ${ID_LIKE:-} " == *" arch "* || "${ID:-}" == "arch" ]] \
  || warn "Обнаружен ${PRETTY_NAME:-неизвестный Linux}; скрипт рассчитан на CachyOS/Arch."
command -v pacman >/dev/null || die "Нужен pacman."
[[ "$EUID" -ne 0 ]] || die "Не запускай скрипт через sudo. Он сам вызовет sudo для pacman."
ok "Папки rice найдены; установка от обычного пользователя."

# 2. Install repository packages
step "Установка пакетов"
OFFICIAL=(
  hyprland xdg-desktop-portal-hyprland
  waybar kitty rofi
  fastfetch cava
  swww
  swaync wlogout
  hyprlock hypridle hyprpolkitagent
  matugen
  nautilus yazi
  grim slurp wl-clipboard
  brightnessctl pamixer playerctl
  network-manager-applet blueman bluez bluez-utils
  hyprpicker
  jq curl wget git rsync unzip
  xdg-utils polkit-gnome
  pipewire wireplumber pipewire-pulse
  ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji
)
# Install available packages from enabled CachyOS/Arch repositories.
AVAILABLE=()
MISSING=()
for pkg in "${OFFICIAL[@]}"; do
  if pacman -Si "$pkg" >/dev/null 2>&1; then AVAILABLE+=("$pkg"); else MISSING+=("$pkg"); fi
done
if ((${#AVAILABLE[@]})); then
  say "Устанавливаю пакеты из репозиториев: ${#AVAILABLE[@]}"
  sudo pacman -Syu --needed "${AVAILABLE[@]}"
fi

# AUR fallback only for packages absent from configured repositories.
AUR_NEEDED=()
for pkg in "${MISSING[@]}"; do
  case "$pkg" in
    matugen|swww) AUR_NEEDED+=("$pkg") ;;
    *) warn "Пакет '$pkg' не найден в подключённых репозиториях — пропускаю." ;;
  esac
done
if ((${#AUR_NEEDED[@]})); then
  AUR_HELPER=""
  command -v yay >/dev/null && AUR_HELPER="yay"
  command -v paru >/dev/null && AUR_HELPER="paru"
  if [[ -n "$AUR_HELPER" ]]; then
    "$AUR_HELPER" -S --needed "${AUR_NEEDED[@]}"
  else
    warn "Не найден AUR-helper (yay/paru). Не устанавливаю AUR-пакеты автоматически."
    warn "Если отсутствуют swww или matugen, установи их вручную через AUR."
  fi
fi
ok "Установка доступных пакетов завершена."

# 3. Backup existing configs
step "Резервное копирование текущих конфигов"
mkdir -p "$BACKUP_ROOT/config"
for item in "$CONFIG_SRC"/* "$CONFIG_SRC"/.[!.]*; do
  [[ -e "$item" ]] || continue
  name="$(basename "$item")"
  if [[ -e "${HOME}/.config/${name}" || -L "${HOME}/.config/${name}" ]]; then
    mkdir -p "$BACKUP_ROOT/config"
    mv "${HOME}/.config/${name}" "$BACKUP_ROOT/config/"
  fi
done
ok "Старые конфиги (если были) сохранены в $BACKUP_ROOT"

# 4. Deploy dotfiles
step "Копирование конфигураций rice"
mkdir -p "$HOME/.config"
rsync -a "$CONFIG_SRC/" "$HOME/.config/"
# Remove the author's fixed 1920x1080 eDP-1 monitor rule: it can break other laptops.
HYPR_CONF="$HOME/.config/hypr/hyprland.conf"
if [[ -f "$HYPR_CONF" ]]; then
  sed -i -E 's/^[[:space:]]*monitor[[:space:]]*=[[:space:]]*eDP-1,/# Rice installer: disabled machine-specific monitor rule: monitor = eDP-1,/' "$HYPR_CONF"
fi
ok "Конфиги скопированы; жёсткая настройка монитора eDP-1 отключена."

# 5. Wallpapers and wallpaper picker
step "Установка обоев и настройка выбора"
mkdir -p "$WALL_DEST"
rsync -a --ignore-existing "$WALL_SRC/" "$WALL_DEST/"
WPPICKER="$HOME/.config/hypr/scripts/wppicker.sh"
if [[ -f "$WPPICKER" ]]; then
  cat > "$WPPICKER" <<'WALLSCRIPT'
#!/usr/bin/env bash
set -euo pipefail
WALLPAPER_DIR="$HOME/Pictures/wallpapers"
SYMLINK_PATH="$HOME/.config/hypr/current_wallpaper"
mkdir -p "$WALLPAPER_DIR"
command -v rofi >/dev/null || { notify-send "Wallpaper" "Не найден rofi"; exit 1; }
command -v matugen >/dev/null || { notify-send "Wallpaper" "Не найден matugen"; exit 1; }
mapfile -d '' -t files < <(find "$WALLPAPER_DIR" -maxdepth 1 -type f \( \
  -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.webp' \
  \) -print0 | sort -z)
((${#files[@]})) || { notify-send "Wallpaper" "В ~/Pictures/wallpapers нет изображений"; exit 0; }
selected="$(printf '%s\n' "${files[@]}" | sed "s|$WALLPAPER_DIR/||" | rofi -dmenu -i -p 'Wallpaper')"
[[ -n "$selected" ]] || exit 0
selected_path="$WALLPAPER_DIR/$selected"
matugen image "$selected_path"
mkdir -p "$(dirname "$SYMLINK_PATH")"
ln -sfn "$selected_path" "$SYMLINK_PATH"
WALLSCRIPT
  chmod +x "$WPPICKER"
fi
ok "Обои скопированы в $WALL_DEST; скрипт Super+W настроен на эту папку."

# 6. Permissions and user service
step "Права доступа и пользовательские службы"
find "$HOME/.config/hypr/scripts" -maxdepth 1 -type f -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
if command -v systemctl >/dev/null; then
  systemctl --user enable --now pipewire.service pipewire-pulse.service wireplumber.service 2>/dev/null || \
    warn "Не удалось включить аудиослужбы автоматически (это можно настроить позже)."
fi
ok "Права на скрипты выставлены."

# 7. Verify commands
step "Финальная проверка"
CHECKS=(Hyprland waybar kitty rofi fastfetch cava swww matugen swaync wlogout hyprlock hypridle grim slurp wl-copy brightnessctl pamixer playerctl yazi nautilus)
FAILED=()
for cmd in "${CHECKS[@]}"; do
  if command -v "$cmd" >/dev/null 2>&1; then ok "$cmd"; else FAILED+=("$cmd"); warn "$cmd — команда не найдена"; fi
done

say "\n${C_GREEN}${C_BOLD}Готово!${C_RESET}"
say "Резервная копия: $BACKUP_ROOT"
say "Обои: $WALL_DEST"
say "Лог: $LOG"
say "\nГорячие клавиши rice: Super+Enter — терминал, Super+D — меню, Super+W — обои."
if ((${#FAILED[@]})); then
  say "${C_YELLOW}Не найдены команды: ${FAILED[*]}${C_RESET}"
  say "Проверь их установку; часть пакетов могла отсутствовать в репозиториях."
fi
say "\nПеред выходом из текущей сессии сохрани работу. Затем выйди и выбери Hyprland на экране входа."
say "Если после входа возникнут проблемы: восстанови папки из $BACKUP_ROOT/config в ~/.config."
