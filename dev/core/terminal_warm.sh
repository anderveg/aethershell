#!/usr/bin/env bash
# ~/.config/quickshell/core/terminal_warm.sh
# Préchauffe une instance résidente de Ghostty pour que SUPER+Entrée ouvre une
# fenêtre instantanément.
#
# Pourquoi : le démarrage à froid de Ghostty coûte ~780 ms sur cette machine
# (GTK4 + libadwaita + contexte OpenGL + balayage fontconfig), même avec le
# cache de pages chaud — mesuré, et identique quel que soit GSK_RENDERER, le
# backend GDK ou la présence du flou. Kitty, lui, ouvre en ~150 ms : le coût
# est propre à Ghostty.
#
# Avec `--gtk-single-instance=true` (voir binds.lua), les lancements suivants
# ne réinitialisent plus l'application : ils demandent une nouvelle fenêtre au
# process déjà vivant, soit ~110 ms au lieu de ~780 ms. Encore faut-il qu'un
# process soit vivant — d'où la fenêtre de chauffe lancée ici au démarrage de
# session, immédiatement rangée sur un bureau spécial silencieux.
#
# La fermer (SUPER+Q depuis l'aperçu, Ctrl+Shift+W) ne tue pas l'instance :
# Ghostty garde son process quand la dernière fenêtre se ferme
# (quit-after-last-window-closed = false). Le préchauffage survit donc à la
# fermeture de sa propre fenêtre.
#
# Lancé depuis core/autostart.json (entrée désactivable dans le panneau :
# Applications -> « Programmes lancés au démarrage »).

set -u

command -v ghostty >/dev/null 2>&1 || exit 0
command -v hyprctl >/dev/null 2>&1 || exit 0
command -v jq      >/dev/null 2>&1 || exit 0

# Une instance tourne déjà (session reprise, script relancé) : elle sert déjà
# les nouveaux lancements, rien à préchauffer.
pgrep -x ghostty >/dev/null 2>&1 && exit 0

ghostty --gtk-single-instance=true >/dev/null 2>&1 &
pid=$!

# Attendre que le compositeur ait mappé SA fenêtre (on l'identifie par le pid
# du process lancé, jamais par sa classe : ce serait celle de tous les
# terminaux de l'utilisateur).
addr=""
for _ in $(seq 1 200); do
    addr=$(hyprctl clients -j 2>/dev/null \
        | jq -r --argjson p "$pid" '.[] | select(.pid == $p) | .address' 2>/dev/null \
        | head -n 1)
    [ -n "$addr" ] && break
    sleep 0.05
done

# Pas de fenêtre (démarrage en cours, compositeur occupé) : on laisse le
# process vivre, il servira quand même les lancements suivants.
[ -n "$addr" ] || exit 0

# Bureau spécial silencieux : aucun focus volé, aucune vignette sur les bureaux
# de travail. `window = address:…` cible précisément cette fenêtre, pour ne
# jamais déplacer celle que l'utilisateur vient d'ouvrir au même moment.
hyprctl dispatch \
    "hl.dsp.window.move({ workspace = \"special:keepalive\", follow = false, window = \"address:$addr\" })" \
    >/dev/null 2>&1

exit 0
