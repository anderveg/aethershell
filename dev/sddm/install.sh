#!/usr/bin/env bash
# Installe le thème de connexion de la session : sddm-astronaut re-coloré depuis
# style_vars.json, avec le wallpaper courant assombri.
#
#   bash dev/sddm/install.sh              installation complète (une invite polkit)
#   bash dev/sddm/install.sh --colors-only # palette + fond seuls, après un changement
#   bash dev/sddm/install.sh --qylock <nom…> # thèmes qylock récupérés (as-core qylock fetch)
#   ASK_SUDO=1 bash dev/sddm/install.sh   # machine sans agent polkit (sudo à la place)
#
# Prérequis : le thème sddm-astronaut installé dans /usr/share/sddm/themes/.
#   Arch   : yay -S sddm-astronaut-theme   (ou pacman -U du paquet construit à la main)
#   Fedora : pas d'AUR — cloner https://github.com/Keyitdev/sddm-astronaut-theme
#            dans /usr/share/sddm/themes/sddm-astronaut-theme
# La police Inter doit exister : le thème la demande explicitement
#   Arch : inter-font        Fedora : rsms-inter-fonts
# La taille du greeter suit l'écran focalisé (hyprctl) ; hors session,
# forcer avec GREETER_SCREEN=WxH.

set -euo pipefail

DEV="$(cd "$(dirname "$0")" && pwd)"
# Le binaire vit dans dev/core, un cran au-dessus de dev/sddm.
CORE="$(cd "$DEV/.." && pwd)/core"
THEME="/usr/share/sddm/themes/sddm-astronaut-theme"
CONFD="/etc/sddm.conf.d"
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP="$HOME/.config/backups_env/sddm_$STAMP"
MODE="full"
[ "${1:-}" = "--colors-only" ] && MODE="colors"

# pkexec suppose un agent polkit dans la session. Sur une machine qui n'en a pas
# (session fraîchement installée, session lancée par ssh), ASK_SUDO=1 passe par
# sudo : même script root, une invite en terminal au lieu d'une boîte de dialogue.
RUNNER="pkexec"
[ "${ASK_SUDO:-0}" = "1" ] && RUNNER="sudo"

die() { echo "install.sh: $*" >&2; exit 1; }

# --qylock : installe dans /usr/share/sddm/themes des thèmes récupérés par
# `as-core qylock`. Ne touche pas à la sélection courante — le panneau
# (onglet Connexion) le fait ensuite par le helper polkit. Les variantes d'un
# même thème (clockwork en contient trois) sont aplaties en <thème>-<variante> :
# SDDM ne sait nommer qu'un dossier de premier niveau dans Current=.
if [ "${1:-}" = "--qylock" ]; then
    shift
    [ "$#" -gt 0 ] || die "aucun thème nommé (bash dev/sddm/install.sh --qylock <nom…>)"
    QCACHE="$HOME/.local/share/qylock-themes"
    QSTAGE="$(mktemp -d)"
    trap 'rm -rf "$QSTAGE"' EXIT
    {
        echo '#!/bin/bash'
        echo 'set -euo pipefail'
        # Le helper et sa règle polkit : sans eux le panneau ne peut pas
        # sélectionner un thème complet (l'ancienne version ne connaissait que
        # les confs astronaut). Réinstallés à chaque fois pour rester alignés
        # sur le dépôt.
        echo "install -Dm755 '$DEV/greeter-palette' /usr/local/bin/greeter-palette"
        echo "install -Dm644 '$DEV/50-greeter-palette.rules' /etc/polkit-1/rules.d/50-greeter-palette.rules"
        for name in "$@"; do
            src="$QCACHE/$name"
            [ -d "$src" ] || die "thème non récupéré : $name (as-core qylock fetch $name)"
            for sub in "$src"/*/; do
                [ -f "$sub/metadata.desktop" ] || continue
                dst="$name-$(basename "${sub%/}")"
                echo "rm -rf '/usr/share/sddm/themes/$dst'"
                echo "cp -a '${sub%/}' '/usr/share/sddm/themes/$dst'"
                echo "chown -R root:root '/usr/share/sddm/themes/$dst'"
            done
            if [ -f "$src/metadata.desktop" ]; then
                echo "rm -rf '/usr/share/sddm/themes/$name'"
                echo "cp -a '$src' '/usr/share/sddm/themes/$name'"
                echo "chown -R root:root '/usr/share/sddm/themes/$name'"
            fi
        done
    } > "$QSTAGE/root.sh"
    bash -n "$QSTAGE/root.sh" || die "script root invalide"
    echo "▶ installation des thèmes qylock (une invite $RUNNER)"
    "$RUNNER" bash "$QSTAGE/root.sh"
    echo
    echo "thèmes présents dans /usr/share/sddm/themes :"
    ls -1d /usr/share/sddm/themes/*/ 2>/dev/null | sed 's|.*/themes/||; s|/$||; s|^|  |'
    echo "(sélection : panneau → Connexion, ou as-core greeter apply <nom>)"
    exit 0
fi

if [ ! -d "$THEME" ]; then
    if command -v dnf >/dev/null; then
        die "thème absent : pas d'AUR sur Fedora — cloner https://github.com/Keyitdev/sddm-astronaut-theme dans $THEME, puis relancer"
    fi
    die "thème absent : installer sddm-astronaut-theme (AUR : yay -S, ou pacman -U du paquet construit à la main)"
fi
[ -x "$CORE/as-core" ] || die "backend as-core introuvable (lancer dev/rust/build.sh)"

# La police est demandée en dur par palette.conf (Font="Inter") : sans elle le
# thème se rabat sur une autre fonte, sans message. fc-match plutôt que
# `fc-list | grep -q` : sous `pipefail`, grep sort au premier succès et le
# SIGPIPE de fc-list fait échouer le pipeline (faux « police absente »).
case "$(fc-match -f '%{family}' Inter 2>/dev/null || true)" in
    Inter*) : ;;
    *)
        echo "⚠ police Inter absente : le thème retombera sur une autre fonte" >&2
        command -v pacman >/dev/null && echo "  Arch   : sudo pacman -S inter-font" >&2
        command -v dnf    >/dev/null && echo "  Fedora : sudo dnf install rsms-inter-fonts" >&2
        ;;
esac

echo "▶ génération depuis style_vars.json"
"$CORE/as-core" greeter gen-palette
[ -f "$DEV/out/Themes/palette.conf" ] || die "palette.conf non généré"
[ -f "$DEV/out/Backgrounds/wallpaper.png" ] || die "fond non généré"

# Détecte la disposition clavier choisie dans style_vars.json (ou input.lua)
# pour aligner immédiatement SDDM et sa locale lors de l'installation.
KB_LAYOUT="fr"
for candidate_style in "$HOME/.config/quickshell/core/style_vars.json" "$DEV/../core/style_vars.json"; do
    if [ -f "$candidate_style" ]; then
        detected_kb="$(jq -r '.kb_layout // ""' "$candidate_style" 2>/dev/null || true)"
        if [[ "$detected_kb" =~ ^[a-z]{2}(-[a-z0-9_]+)?$ ]]; then
            KB_LAYOUT="$detected_kb"
            break
        fi
    fi
done

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# ── Clavier virtuel ─────────────────────────────────────────────────────────
# Chaque thème de connexion installé reçoit un bouton discret en bas à droite
# (`ClavierVirtuel.qml`) qui affiche Qt Virtual Keyboard. Les thèmes qui le
# gèrent déjà (sddm-astronaut, entre autres) ne sont pas touchés, et un thème
# dont le Main.qml n'a pas d'`id: root` est laissé tel quel.
# Les fichiers retouchés sont préparés ici (lecture seule côté utilisateur) ;
# root.sh ne fait que les copier, original sauvegardé en .aethershell-orig.
VK_STAGE="$STAGE/themes"
export VK_STAGE
if compgen -G "/usr/share/sddm/themes/*/Main.qml" > /dev/null; then
    while IFS= read -r mainqml; do
        td="$(dirname "$mainqml")"
        nom="$(basename "$td")"
        # Thème qui gère déjà Qt Virtual Keyboard (sddm-astronaut et d'autres) :
        # on n'ajoute pas un second bouton. Nos deux composants sont exclus du
        # test, sinon un thème déjà équipé passerait pour incompatible.
        autres="$(ls "$td"/*.qml "$td"/Components/*.qml 2>/dev/null \
            | grep -vE "/(ClavierVirtuel|PanneauClavier)\.qml$" | tr '\n' ' ' || true)"
        grep -qs "InputPanel\|QtQuick.VirtualKeyboard" "$mainqml" $autres && continue
        grep -q "id: root" "$mainqml" || continue
        mkdir -p "$VK_STAGE/$nom"
        # Composants toujours rafraîchis : une correction du bouton ou du panneau
        # doit atteindre les thèmes déjà équipés.
        cp -f "$DEV/clavier/ClavierVirtuel.qml" "$DEV/clavier/PanneauClavier.qml" "$VK_STAGE/$nom/"
        if ! grep -q "ClavierVirtuel" "$mainqml"; then
            cp -f "$mainqml" "$VK_STAGE/$nom/Main.qml"
            python3 - "$VK_STAGE/$nom/Main.qml" <<'PYX'
import sys
chemin = sys.argv[1]
src = open(chemin).read()
bloc = """
    // AetherShell — clavier virtuel (bouton discret en bas à droite).
    // Posé par dev/sddm/install.sh ; la version d'origine du thème est
    // conservée en Main.qml.aethershell-orig.
    ClavierVirtuel { id: clavierVirtuel; echelle: root.s !== undefined ? root.s : 1 }
"""
fin = src.rstrip().rfind("}")
if fin < 0:
    sys.exit("Main.qml : accolade finale introuvable")
open(chemin, "w").write(src.rstrip()[:fin].rstrip("\n") + "\n" + bloc + "}\n")
PYX
        fi
        echo "  clavier virtuel : $nom"
    done < <(ls -1 /usr/share/sddm/themes/*/Main.qml 2>/dev/null)
fi

{
    echo '#!/bin/bash'
    echo 'set -euo pipefail'
    echo "mkdir -p '$BACKUP'"
    # Helper privilégié + règle polkit : le panneau peut alors changer de thème
    # ou rafraîchir la palette sans invite (programme root, non modifiable).
    echo "install -Dm755 '$DEV/greeter-palette' /usr/local/bin/greeter-palette"
    echo "install -Dm644 '$DEV/50-greeter-palette.rules' /etc/polkit-1/rules.d/50-greeter-palette.rules"
    echo "install -Dm644 '$DEV/out/Themes/palette.conf' '$THEME/Themes/palette.conf'"
    echo "install -Dm644 '$DEV/out/Backgrounds/wallpaper.png' '$THEME/Backgrounds/wallpaper.png'"
    # Clavier virtuel : les thèmes préparés plus haut reçoivent le bouton discret
    # en bas à droite. L'original du Main.qml est conservé une seule fois.
    if [ -n "${VK_STAGE:-}" ] && [ -d "$VK_STAGE" ]; then
        echo "for t in '$VK_STAGE'/*/; do"
        echo "  nom=\$(basename \"\$t\")"
        echo "  cible=/usr/share/sddm/themes/\$nom"
        echo "  [ -d \"\$cible\" ] || continue"
        echo "  if [ -f \"\$t/Main.qml\" ]; then"
        echo "    cp -n \"\$cible/Main.qml\" \"$BACKUP/\${nom}_Main.qml.aethershell-orig\" 2>/dev/null || true"
        echo "    install -Dm644 \"\$t/Main.qml\" \"\$cible/Main.qml\""
        echo "  fi"
        echo "  install -Dm644 \"\$t/ClavierVirtuel.qml\" \"\$cible/ClavierVirtuel.qml\""
        echo "  install -Dm644 \"\$t/PanneauClavier.qml\" \"\$cible/PanneauClavier.qml\""
        echo "done"
    fi
    # Reprise d'un renommage : la nomenclature précédente portait le nom de
    # l'hôte du laptop, on retire les artefacts qu'elle a laissés.
    echo "rm -f /usr/local/bin/wallpaper-greeter /etc/polkit-1/rules.d/50-wallpaper-greeter.rules"
    if [ "$MODE" = "full" ]; then
        # Sauvegarde puis neutralisation des Current= locaux : sans ça trois
        # fichiers se contredisent et l'ordre lexical décide du thème affiché.
        echo "cp -n '$THEME/metadata.desktop' '$BACKUP/metadata.desktop'"
        echo "sed -i 's|^ConfigFile=.*|ConfigFile=Themes/palette.conf|' '$THEME/metadata.desktop'"
        echo "mkdir -p '$CONFD'"
        for f in "$CONFD"/*.conf; do
            [ -e "$f" ] || continue
            [ "$(basename "$f")" = "10-sddm-theme.conf" ] && continue
            echo "cp -n '$f' '$BACKUP/$(basename "$f")' 2>/dev/null || true"
            echo "sed -i 's|^Current=|# désactivé par dev/sddm/install.sh — Current=|' '$f'"
        done
        # Fedora garde son Current=breeze dans /etc/sddm.conf, hors de conf.d :
        # sans cette ligne deux Current= cohabitent après l'installation.
        if [ -f /etc/sddm.conf ] && grep -q '^Current=' /etc/sddm.conf; then
            echo "cp -n '/etc/sddm.conf' '$BACKUP/sddm.conf' 2>/dev/null || true"
            echo "sed -i 's|^Current=|# désactivé par dev/sddm/install.sh — Current=|' '/etc/sddm.conf'"
        fi
        # Écrit /etc/sddm.conf.d/10-sddm-theme.conf + drop-in locale systemd + localectl
        echo "rm -f '$CONFD/10-sddm-theme.conf'"
        echo "/usr/local/bin/greeter-palette set-keymap '$KB_LAYOUT'"
    else
        echo "/usr/local/bin/greeter-palette set-keymap '$KB_LAYOUT' >/dev/null 2>&1 || true"
    fi
} > "$STAGE/root.sh"

echo "▶ installation (une invite $RUNNER)"
"$RUNNER" bash "$STAGE/root.sh"

echo
echo "thème   : $THEME/Themes/palette.conf"
echo "fond    : $THEME/Backgrounds/wallpaper.png"
[ "$MODE" = "full" ] && echo "sélect. : $CONFD/10-sddm-theme.conf (Current=sddm-astronaut-theme)"
echo "sauveg. : $BACKUP"
echo
echo "test    : QT_QPA_PLATFORM=wayland sddm-greeter-qt6 --test-mode --theme $THEME  (Échap pour fermer ; la connexion y est désactivée)"
