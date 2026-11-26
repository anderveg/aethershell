# AetherShell

[FR](../README.md) · [EN](README.en.md) · [ES](README.es.md) · [DE](README.de.md)

Eine Desktop-Umgebung für [Hyprland](https://hyprland.org), bestehend aus einer Insel-Leiste, modularen Panels, Desktop-Widgets und alltäglichen Werkzeugen, geschrieben in QML/Qt und angetrieben von [Quickshell](https://quickshell.org).

> **Hinweis:** AetherShell beansprucht nicht, das Rad neu zu erfinden oder sich als Standard zu etablieren. Es ist einfach eine persönliche Desktop-Umgebung unter anderen, noch jung und aktiv in der Entwicklung (`0.4.x`-Zyklus mit einem einheitlichen Rust-Backend), konzipiert für einen täglichen Arbeitsablauf und kontinuierliche Verfeinerung durch Erfahrung.

---

## 1. Überblick

AetherShell ist mehr als nur ein einfaches Leisten-Theme; es vereint die visuellen und funktionalen Komponenten der grafischen Sitzung:

* **Hauptleiste & Modulare Kapsel**: zwei umschaltbare Modi, zur Laufzeit konfigurierbar:
  * *Klassisch*: Ein Drei-Insel-Layout (links, mitte, rechts) in einer gemeinsamen Kapsel mit anpassbarer Trenntransparenz und angepassten Leisten-Panels (`PanneauSurface`), die Glasoptik und Ränder respektieren.
  * *Dynamische Insel* (`DynamicIsland`): Eine interaktive zentrale All-in-One-Pille, konfigurierbar über ihren dedizierten Tab **Dynamische Insel** (4-Zustände-Wähler *Versteckt / Ruhe / Erweitert / Beide* pro Indikator und Applet) — kompakt im Ruhezustand (Uhrzeit, Medientitel, Multi-Source **Live Activity**, integriertes OSD, bedingte Updates), beim Hover erweitert, mit **animiertem Inline-Wetter**, **Inline-Hintergrundbild-Wähler** (`SUPER + W`, `aether-wp`-Submap), **Inline-Farbschema-Wähler** (`SUPER + C`, `aether-scheme`-Submap), **App-Starter & `as`-Befehlsleiste** (`SUPER + R`), **Schnellnotizen** (`SUPER + N`), und einem erweiterten Panel mit Tabs (*Steuerung* mit Arbeitskontexten `Normal / Focus / Meeting / Chill`, Caffeine, Performance, Audioausgabe und Scratchpad; *Warnungen & Aufgaben* mit einklappbarer Agenda; *System & Netzwerk* mit Akkuladebegrenzung; *Erscheinungsbild*; *Planka-Projekte*), vollständig tastaturgesteuert (`SUPER + I` / `SUPER + ALT + H`, `SubmapWhichKey`).
* **Fensterübersicht & Scratchpad**: *Mission Control*-Overlay ([`OverviewOverlay.qml`](../dev/OverviewOverlay.qml), `SUPER + G`), das Arbeitsbereichsfenster mit Live-Vorschaubildern und Sofortfilterung anzeigt, sowie Scratchpad-Verwaltung (`SUPER + ,` / `SUPER + SHIFT + ,`).
* **Einheitliche Oberflächen & Durchgehendes Theming**: Einheitsglas-Rendering über [`SurfaceFloutee.qml`](../dev/SurfaceFloutee.qml) (`shell-blur`), einheitliche Animationskurven (`Theme.panelAnimDuration`), automatische Weitergabe von Matugen-Paletten an Terminals und GTK 3/4 / Qt5ct / Qt6ct, einheitliches Rust-Backend-Binary [`as-core`](../dev/rust/as-core/) (`daemon`-Dienst und forkfreie `/proc`/`/sys`-Abfragen, HTTP/SQLite-Konnektoren, Launcher, Applets) und Ereignisüberwachung (`pactl subscribe`, `udevadm monitor`, `FileView`, `Hyprland.rawEvent`).
* **Optionale Sekundärleisten**: Unterstützung für eine untere Leiste und vertikale Seitenleisten nach derselben Komponentenarchitektur.
* **Einheitliches Konfigurationspanel**: Erreichbar über einen Hotkey (`SUPER + SHIFT + H`, während `SUPER + H` das erweiterte Panel der Dynamischen Insel umschaltet) oder durch Mittelklick auf ein beliebiges Applet. Ermöglicht die Anpassung von Erscheinungsbild (Paletten, Unschärfen, Eckenradien, Opazität), bevorzugten Anwendungen, Anzeigen, Inaktivitäts-Timeout (`hypridle`), Autostart und lokalen Geheimnissen mit Live-Hot-Reloading ohne Neustart der Sitzung.
* **Andockbare Desktop-Widgets**: Ziehbare Blöcke (Aufgaben, Systemmonitor, Wetter, Musik, Uhr, Agent...) konfigurierbar und filterbar nach virtuellem Arbeitsbereich (Mittelklick zum Beschränken eines Widgets auf einen oder mehrere Arbeitsbereiche).
* **Reaktiver Audio-Visualisierer**: Diskrete Integration einer nativen PipeWire-Wellenform (`pwscope`) oder von Spektralstreifen (`cava`), mit automatischer Abschaltung nach zehn Sekunden Stille zur Schonung von GPU/CPU-Ressourcen.
* **Aufgabenverfolgung & Hermes-Integration**: Lokale Markdown-Checklisten-Verwaltung (`- [ ]`) mit grafischem Dateiwähler und optionalem Überwachungsschalter, der abgehakte Aufgaben über einen Hintergrund-Worker an den Hermes-Agenten delegiert.
* **Integrierte grafische Wähler**: Modale Fenster, die direkt in der Shell-Oberfläche gezeichnet werden ([`SelecteurDossier.qml`](../dev/SelecteurDossier.qml), [`SelecteurFichier.qml`](../dev/SelecteurFichier.qml)), wodurch die Einschränkung traditioneller Wayland-Dialoge umgangen wird, die sich unterhalb der Overlay-Schicht öffnen würden.
* **Theme-Profile & Mitgelieferter Katalog** (`theme_profile`): Eine Geste wendet einen ganzen Desktop an — Hintergrundbild, Matugen-Palette, Shell-Ambiente (28 Stil-Schlüssel), Icon-Paket, Cursor und eine optionale Referenz auf ein Umgebungsprofil (Nacht, Fokus...). Neun kuratierte Voreinstellungen werden mit ihren 1920×1080-Hintergrundbildern (`../dev/wallpapers/`, ca. 2,6 MB gesamt) geliefert, in den beim Erststart-Assistenten gewählten Ordner kopiert und nur über den **Dateinamen** referenziert. Jede Anwendung ist transaktional: der vorherige Zustand wird archiviert (`__avant__`), eine fehlerhafte Palette stellt den Shell-Stil wieder her, *bevor* Icons oder Cursor berührt werden, und „angewendet“ wird erst nach Neulesen des Live-Zustands gemeldet.
* **Cursor-Manager** (`curseurs`): Listet, zeigt Vorschauen, installiert und wendet Cursor-Pakete auf alle fünf Kanäle gleichzeitig an — Compositor (`hyprctl setcursor`), GNOME-Einstellungen, GTK3/GTK4-INI, `environment.d` und `style_vars.json` — im Größenbereich von 16–64 px.
* **Hell/Dunkel-Achse** (`theme_mode: auto | dark | light`): Matugen wird mit dem passenden Modus aufgerufen und die Variante jedes Tokens entsprechend gelesen, sodass ein Hintergrundbild erzwungen hell oder dunkel dargestellt werden kann. Shell, Leiste, Panels und Hyprland schalten sofort um; GTK- und Qt-Anwendungen folgen erst beim Start (ihre Theme-Dateien werden beim Start gelesen), was in der Benutzeroberfläche explizit angegeben wird.
* **Anmeldebildschirm-Manager (SDDM)**: Konfiguration des Astronaut-Themes und von Qylock-Varianten über das Panel, automatische Tastaturlayout- und UTF-8-Gebietsschema-Synchronisation aus dem Erststart-Assistenten (oder Tastatur-Tab) und ein sicherer Vorschau-Starter, der Tests auf einem dedizierten Arbeitsbereich (`workspace 99`) isoliert, um die aktive Sitzung niemals einzufrieren.

---

## 2. Deployment & Updates

### Einzeilige Installation oder Aktualisierung

```sh
mkdir -p "$HOME/.cache/quickshell"   && curl -fsSL -o "$HOME/.cache/quickshell/install_aethershell.sh"      https://raw.githubusercontent.com/anderveg/aethershell/master/../install.sh   && bash "$HOME/.cache/quickshell/install_aethershell.sh"
```

Das Skript wird **heruntergeladen und dann ausgeführt**, niemals über eine Pipe geleitet: Es führt sich nach der Vorbereitung des Repositories selbst von der Festplatte aus aus, und dieses `exec` würde das `bash` töten, das die Pipe liest — `curl` würde daraufhin mit Fehler 23 («Failure writing output to destination») abbrechen, während die Installation fortfährt. Eine Datei belässt zudem `stdin` beim Terminal, sodass Eingabeaufforderungen (`sudo`, Deinstallationsbestätigung) funktionieren.

[`../install.sh`](../install.sh) erledigt alles: Es erkennt die Distribution aus `/etc/os-release` (Arch oder Fedora), klont das Repository oder aktualisiert es via Fast-Forward falls bereits vorhanden, sichert die Umgebung und deployt die Shell. Derselbe Befehl dient für die Erstinstallation und anschließende Updates.

Optionen: `--dir PFAD` (Standard: `$AETHERSHELL_DIR`, ansonsten `~/../dev/aethershell` falls vorhanden, sonst `~/../dev/aethershell`), `--arch` / `--fedora` zum Überschreiben des Ziels anstelle des Lesens von `/etc/os-release`, `--branche NAME`, `--check` (nur Status, ohne zu deployen), `--no-deploy`, `--help`. Bei der Ein-Zeilen-Curl-Verwendung nach `bash -s --` übergeben:

```sh
curl -fsSL https://raw.githubusercontent.com/anderveg/aethershell/master/../install.sh | bash -s -- --check
```

Das Panel verfolgt dieselbe Version wie das Skript: „Anzeigen & System“ → „Shell-Aktualisierung“ zeigt die deployte Version, die auf GitHub veröffentlichte Version und verfügbare Aktionen an (jetzt prüfen, im Terminal aktualisieren, Einzeiler für eine andere Maschine kopieren). `core/version.json` wird bei jedem Deployment geschrieben, und `as-core maj-shell` fragt GitHub nur einmal alle **280 Minuten** ab — dazwischen wird aus dem Cache bedient, um unnötige Netzwerkaufrufe beim Öffnen des Panels zu vermeiden.

### Manuelles Deployment

Das Deployment wird von [`../install.sh`](../install.sh) gesteuert, kompatibel mit **Arch Linux** und **Fedora** (automatische Erkennung über `/etc/os-release`):

```sh
# Erforderliche Abhängigkeiten prüfen, ohne etwas zu installieren
./../install.sh --deps

# Vorab-Diff-Analyse (Repository ➜ Live-System) ohne Änderungen
./../install.sh --diff

# Vollständiges Deployment mit vorherigem Backup (Tarball + feingranulares Snapshot)
./../install.sh --arch    # oder ./../install.sh --fedora

# Schnelles Deployment ohne neues Backup (wenn der Zustand bereits archiviert ist)
./../install.sh --deploy-only

# Deinstallation: Entfernt die Shell, ihre systemd-Units und setzt ~/.config/hypr
# auf eine minimale Konfiguration zurück (SUPER + Return und SUPER + T öffnen ein Terminal)
./../install.sh --uninstall          # Bestätigung durch Tippen von "uninstall"
./../install.sh --uninstall --purge  # dasselbe + SDDM-Themes, Caches und Backups
```

`--uninstall` archiviert zuerst `~/.config/quickshell` und `~/.config/hypr` in `~/.config/backups_env/uninstall_<zeitstempel>/` und entfernt dann nur das, was das Deployment installiert hatte: die fünf Benutzer-systemd-Units, die Shell selbst und systemseitig den `greeter-palette`-Helper, seine polkit-Regel und die SDDM-Drop-Ins (Root-Passwort erforderlich). `--dry-run` listet die Aktionen auf, ohne etwas zu berühren. Systempakete werden niemals entfernt. Dieselbe Option befindet sich im Konfigurationspanel: **System**-Tab ➜ **Shell-Aktualisierung**-Schublade ➜ *AetherShell deinstallieren*.

### Strikter Schutz lokaler Daten

Das Deployment überschreibt niemals blind Live-Dateien:
* **Geschützte lokale Zustände**: `style_vars.json`, `bar_applets.json`, `widgets.json`, `autostart.json`, `todo.json`, `secrets.json`, `theme_profiles.json` (Ihre eigenen Profil) usw. werden niemals überschrieben, wenn sie auf der Zielmaschine bereits existieren. Mitgelieferte Theme-Presets haben `created_at: 0` und werden durch `as-core catalogue install` aktualisiert; sobald Sie eines davon erneut speichern, erhält es Ihr eigenes Datum und wird nie wieder ersetzt.
* **Personalisierte Hyprland-Konfiguration**: `binds.lua`, `input.lua`, `general.lua` und Hardware-Profile bleiben maßgeblich. Bei Abweichungen zum Repository wird eine `.upstream`-Vergleichskopie erstellt, ohne die aktive Datei zu berühren.
* **Granulares Sicherheitsnetz**: Jedes Deployment erstellt ein Backup-`.tar.gz`-Archiv und ein unkomprimiertes Spiegel-Snapshot unter `~/.config/backups_env/snapshots/<zeitstempel>/` mit einer SHA-256-Prüfsummentabelle (`manifest.json`), die bei Bedarf eine Einzeldateiwiederherstellung ermöglicht (`./../install.sh --restore-file <pfad>`).

---

### Installation auf einer anderen Maschine

Nichts im Repository enthält hartcodierte Benutzernamen, persönliche Ordner oder Maschinen-Hostnamen: AetherShell installiert sich unter jedem Benutzerkonto, und `./../install.sh` schreibt immer in das `$HOME` des ausführenden Benutzers.

Pfade werden stets über Variablen zusammengesetzt, niemals hartcodiert:

| Kontext | Zu verwenden |
|---|---|
| Shell | `"$HOME"`, `"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"` |
| Rust | `paths::home_dir()`, `paths::runtime_dir()` (`../dev/rust/as-core/src/common/paths.rs`) |
| QML | `Quickshell.env("HOME")`, `Quickshell.env("XDG_RUNTIME_DIR")` |
| systemd-Unit | `%h` (Unit-Direktive) |

`../dev/core/as-core neutralite` untersucht **verfolgte** Dateien: Es markiert jedes `/home/<name>`, das kein Platzhalter ist, sowie Benutzernamen und Maschinen-Hostname. Der Deployment-Vorabflug führt dies aus und gibt eine Warnung aus. Eine Zeile kann eine explizite Ausnahme enthalten — `neutralite:ok — <grund>` — für beabsichtigte Kompatibilität.

---

## 3. Voraussetzungen

* **Compositor**: [Hyprland](https://hyprland.org) 0.57 oder neuer (modulare Lua-Konfiguration);
* **UI-Engine**: [Quickshell](https://quickshell.org) 0.3.2 oder neuer;
* **Icon-Schriftart**: `0xProto Nerd Font` (Installer bereitgestellt in `../dev/core/install_fonts.sh`);
* **Rust**: `cargo` (`rust`-Paket unter Arch) — das `as-core`-Backend wird beim Deployment kompiliert; ohne es greifen Rust-Fixes nicht;
* **Systemabhängigkeiten**: Nach Distribution aufgelistet in [`../dev/dependencies.txt`](../dev/dependencies.txt) (`matugen`, `wireplumber`, `NetworkManager`, `cava` usw.).

---

## 4. Projektstruktur

```
../install.sh            # Einheitliches Skript: Installation, Update, Vorabprüfungen, Deployment und Backups
../dev/
├── rust/as-core/     # Einheitliches Rust-Backend (kompiliert nach ../dev/core/as-core)
├── core/             # as-core Binary, JSON-Kataloge, Caches und Shell-Integrationsskripte
├── wallpapers/       # Neun 1920×1080 Hintergrundbilder mit dem Theme-Katalog (~2,6 MB)
├── widgets/          # Desktop-Komponenten (Uhr, Todo, System, Wetter...)
├── hypr_modular/     # Modulare Hyprland-Konfiguration in Lua
├── hyprquickpaper/   # Hintergrundbild-Engine und Palettenverwaltung
├── sddm/             # Skripte und Helfer für den SDDM-Anmeldebildschirm
├── charge-limit/     # polkit-Aktion + Root-Helper für das Akkuladeelimit (`aether-charge-limit`)
├── systemd/          # Benutzer-systemd-Units (quickshell.service...)
└── *.qml             # Quickshell-Oberflächen (Leiste, Panel, Popups, Wähler...)
```

---

## 5. Danksagungen & Code-Übernahmen

AetherShell ist nicht im Vakuum entstanden: Es baut auf Bausteinen, Konzepten und Code-Snippets anderer Open-Source-Projekte mit überzeugenden Ansätzen auf. Vielen Dank an die folgenden Autoren für ihre unter offenen Lizenzen geteilte Arbeit (insbesondere die [Noctalia Community Plugins](https://github.com/noctalia-../dev/community-plugins)-Sammlung unter MIT-Lizenz):

| Komponente / Konzept | Ursprünglicher Autor | Beschreibung |
|---|---|---|
| [Visualizer+](https://github.com/noctalia-../dev/community-plugins/tree/main/visualizerp) | **al3x** | PipeWire-Erfassungs-Engine in C (`pwscope.c`), lokal kompiliert, um die Audio-Wellenform zu speisen. |
| [Agentik](https://github.com/noctalia-../dev/community-plugins/tree/main/agentik) | **notfinaldev** | Prinzipien des nicht-blockierenden Agenten-Status-Pollings, Prozess/Sitzungs-Abgleichs und Zustandsmanagements. |
| [USB Manager](https://github.com/noctalia-../dev/community-plugins/tree/main/usb-manager) | **Marco Ziliani** | Hardware-Polling-Architektur, die direkt von `sysfs` und `udev` liest, ohne einen schweren residenten Daemon zu erfordern. |
| [To Do](https://github.com/noctalia-../dev/community-plugins/tree/main/todo) | **nightwatch75** | Initiale Inspiration für die Entkopplung von Leisten-Applet und Desktop-Widget für Aufgabenlisten. |
| [NVTOP](https://github.com/noctalia-../dev/community-plugins/tree/main/nvtop) | **tordex** | Bedarfsgesteuertes Systemüberwachungsprinzip (Prozess wird nur bei geöffneter Ansicht gestartet). |
| [Wallpaper Depth](https://github.com/noctalia-../dev/official-plugins/tree/main/wallpaper_depth) | **noctalia** | Visuelles Immersionskonzept für Inseln mittels Tiefenkarten (Depth Anything V2). |
| [WallpaperFx.qml (`pocket-dots`)](https://github.com/diegoMalagrida/pocket-dots) | **diegoMalagrida** | Shader-basierte Hintergrundbild-Übergänge (`WallpaperFx.qml` / `wallfx.frag`: organische 4-px-Zellenausbreitung und nahtlose `awww`-Übergabe). |
| **Quickshell & Hyprland** | **outfoxxed & vaxerski** | Für diese beiden großen Projekte, die den Aufbau einer modernen, performanten Wayland-Shell ermöglichen. |

---

## 6. Lizenz

AetherShell wird unter der MIT-Lizenz vertrieben — siehe die [`../LICENSE`](../LICENSE)-Datei für Details.
