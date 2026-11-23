#!/usr/bin/env bash
# Hyprland (colors.lua), Hyprlock, Hyprquickpaper, Terminal & GTK/Qt Theme Sync
# Synchronisé avec style_vars.json.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STYLE_VARS="$SCRIPT_DIR/style_vars.json"

if [ ! -f "$STYLE_VARS" ]; then
    echo "style_vars.json not found at $STYLE_VARS"
    exit 1
fi

# 1 à 4. colors.lua (Hyprland), hyprquickpaper/colors.json, hyprlock-colors.conf
# et hyprlock-bg.conf : chaque cible a son format, mais une seule source — le
# binaire unique les écrit depuis la palette active, `--file` désignant le
# fichier de cette installation (dépôt ou déploiement).
"$SCRIPT_DIR/as-core" theme-sync --file "$STYLE_VARS" \
    || echo "sync_theme.sh : as-core theme-sync a échoué" >&2

# 5. Synchronise la palette des terminaux (OSC universel + Ghostty, Kitty, Alacritty, Foot)
"$SCRIPT_DIR/as-core" terminal-theme >/dev/null 2>&1 || true

# 6. Synchronise la palette vers GTK 3/4 et Qt5ct/Qt6ct
"$SCRIPT_DIR/as-core" sync-apps-theme >/dev/null 2>&1 || true
