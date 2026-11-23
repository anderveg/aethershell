#!/usr/bin/env bash
# Matugen Color Generator for Quickshell + Rofi + Hyprland

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STYLE_VARS="$SCRIPT_DIR/style_vars.json"

if ! command -v matugen &> /dev/null; then
    echo "Matugen not installed. Skipping color generation."
    exit 1
fi

# Dossier configuré (valeur stockée avec un $HOME littéral : on l'étend après).
WALLPAPER_DIR="$(jq -r '.wallpaper_dir // ""' "$STYLE_VARS" 2>/dev/null || true)"
WALLPAPER_DIR="${WALLPAPER_DIR//\$HOME/$HOME}"
[ -z "$WALLPAPER_DIR" ] && WALLPAPER_DIR="$HOME/Images/wallpapers/"

WALLPAPER="${1:-}"
if [ -z "$WALLPAPER" ] && [ -f "$HOME/.cache/quickshell/hyprquickpaper/.current" ]; then
    WALLPAPER="$(cat "$HOME/.cache/quickshell/hyprquickpaper/.current")"
fi
if [ -z "$WALLPAPER" ] || [ ! -f "$WALLPAPER" ]; then
    WALLPAPER="$(find "$WALLPAPER_DIR" "$HOME/Images/wallpapers" "$HOME/Pictures/wallpapers" "$HOME/Pictures" -maxdepth 2 -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.jpeg' -o -iname '*.webp' \) 2>/dev/null | head -n 1)"
fi

if [ -z "$WALLPAPER" ] || [ ! -f "$WALLPAPER" ]; then
    echo "No valid wallpaper found to generate palette."
    exit 1
fi

# Matugen scheme type + contrast level (set from the config panel, stored in style_vars.json)
MATUGEN_SCHEME="$(jq -r '.matugen_scheme // "scheme-tonal-spot"' "$STYLE_VARS" 2>/dev/null || true)"
[ -n "$MATUGEN_SCHEME" ] || MATUGEN_SCHEME="scheme-tonal-spot"
MATUGEN_CONTRAST="$(jq -r '.matugen_contrast // 0' "$STYLE_VARS" 2>/dev/null || true)"
[ -n "$MATUGEN_CONTRAST" ] || MATUGEN_CONTRAST="0"

MATUGEN_JSON="$(matugen image "$WALLPAPER" -t "$MATUGEN_SCHEME" --contrast "$MATUGEN_CONTRAST" --prefer saturation --dry-run --json hex -q 2>/dev/null)"
if [ -z "$MATUGEN_JSON" ]; then
    MATUGEN_JSON="$(matugen image "$WALLPAPER" -t "$MATUGEN_SCHEME" --contrast "$MATUGEN_CONTRAST" --source-color-index 0 --dry-run --json hex -q 2>/dev/null)"
fi
if [ -z "$MATUGEN_JSON" ]; then
    echo "Matugen failed to extract palette from $WALLPAPER"
    exit 1
fi

printf '%s' "$MATUGEN_JSON" \
    | "$SCRIPT_DIR/as-core" colors-matugen --file "$STYLE_VARS"

"$SCRIPT_DIR/sync_theme.sh"
