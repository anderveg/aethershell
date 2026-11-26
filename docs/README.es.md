# AetherShell

[FR](../README.md) · [EN](README.en.md) · [ES](README.es.md) · [DE](README.de.md)

Un entorno de escritorio para [Hyprland](https://hyprland.org), compuesto por una barra en islas, paneles modulares, widgets de escritorio y herramientas cotidianas, escrito en QML/Qt e impulsado por [Quickshell](https://quickshell.org).

> **Nota:** AetherShell no pretende reinventar la rueda ni imponerse como un estándar. Es simplemente un entorno personal entre otros, aún joven y en pleno desarrollo (ciclo `0.4.x` con un backend unificado en Rust), diseñado para adaptarse a un flujo de trabajo diario y perfeccionarse con la experiencia.

---

## 1. Resumen general

Más que un simple tema de barra, AetherShell reúne los elementos visuales y utilitarios de la sesión gráfica:

* **Barra principal y cápsula modular**: dos modos a elegir, configurables al vuelo:
  * *Clásico*: disposición en tres islas (izquierda, centro, derecha) alojadas en una cápsula común con transparencia ajustable en separaciones y paneles amorfos (`PanneauSurface`) que respetan el vidrio y los bordes de la barra.
  * *Isla dinámica* (`DynamicIsland`): píldora central interactiva todo en uno configurable en su pestaña dedicada **Isla dinámica** (selector de 4 estados *Oculto / Reposo / Expandido / Ambos* por indicador y applet) — compacta en reposo (hora, título multimedia, **Live Activity** multifuente, OSD integrado, actualizaciones condicionales), expandida al pasar el cursor, con **clima inline animado**, **selector de fondo de pantalla** (`SUPER + W`, submapa `aether-wp`), **selector de esquemas de color** (`SUPER + C`, submapa `aether-scheme`), **lanzador de aplicaciones y barra de comandos `as`** (`SUPER + R`), **notas rápidas** (`SUPER + N`), y panel expandido con pestañas (*Controles* con contextos de trabajo `Normal / Focus / Reunión / Relax`, Caffeine, Performance, salida de audio y scratchpad; *Alertas y Tareas* con agenda plegable; *Sistema y Red* con límite de carga de batería; *Apariencia*; *Proyectos Planka*), controlable por teclado (`SUPER + I` / `SUPER + ALT + H`, `SubmapWhichKey`).
* **Vista general y Scratchpad**: superposición *Mission Control* ([`OverviewOverlay.qml`](../dev/OverviewOverlay.qml), `SUPER + G`) que lista las ventanas por escritorio con miniaturas en tiempo real y filtrado instantáneo, además de la gestión del scratchpad (`SUPER + ,` / `SUPER + SHIFT + ,`).
* **Superficies unificadas y temas de extremo a extremo**: renderizado de vidrio unificado a través de [`SurfaceFloutee.qml`](../dev/SurfaceFloutee.qml) (`shell-blur`), curvas de animación unificadas (`Theme.panelAnimDuration`), propagación automática de paletas Matugen a terminales y GTK 3/4 / Qt5ct / Qt6ct, binario de backend unificado en Rust [`as-core`](../dev/rust/as-core/) (demonio `daemon` y sondeos `/proc`/`/sys` sin fork, conectores HTTP/SQLite, lanzador, applets) y seguimientos de eventos (`pactl subscribe`, `udevadm monitor`, `FileView`, `Hyprland.rawEvent`).
* **Barras secundarias opcionales**: soporte para una barra inferior y barras laterales verticales siguiendo la misma lógica de componentes.
* **Panel de configuración unificado**: accesible mediante atajo (`SUPER + SHIFT + H`, mientras `SUPER + H` despliega el panel extendido de la isla) o mediante clic central en cualquier applet. Permite ajustar la apariencia (paletas, desenfoques, radios, opacidad), isla dinámica, aplicaciones preferidas, pantallas, temporizador de inactividad (`hypridle`), inicio automático y secretos locales, aplicándose al vuelo sin reiniciar la sesión.
* **Widgets de escritorio anclables**: catálogo visual de 2 columnas (reloj, fecha, clima, música, sistema, tareas, **notas rápidas**, **stickers**, cuotas de IA...), modo de edición directa en el escritorio (manijas de redimensionamiento, arrastrar y soltar, ajuste a cuadrícula de `32 px`, contenido adaptable y eliminación in situ), estilo `Glass / Tarjeta` o `Transparent` por widget y filtrado por escritorio virtual.
* **Visualizador de audio reactivo**: integración discreta de una onda nativa de PipeWire (`pwscope`) o barras espectrales (`cava`), con apagado automático tras diez segundos de silencio para preservar recursos de GPU/CPU.
* **Seguimiento de tareas e integración con Hermes**: gestión local de listas de verificación Markdown (`- [ ]`) con selector gráfico de archivos e interruptor de monitoreo opcional que confía la ejecución de tareas marcadas al agente Hermes mediante un *worker* en segundo plano.
* **Selectores gráficos integrados**: hojas modales dibujadas directamente en la superficie del shell ([`SelecteurDossier.qml`](../dev/SelecteurDossier.qml), [`SelecteurFichier.qml`](../dev/SelecteurFichier.qml)), evitando la limitación de los diálogos tradicionales de Wayland que se abrirían debajo de la superficie de capa (`Overlay`).
* **Perfiles de tema y catálogo incluido** (`theme_profile`): un solo gesto aplica un escritorio completo — fondo de pantalla, paleta Matugen, ambiente del shell (28 claves de estilo), paquete de iconos, cursor y una **referencia** a un perfil de entorno (noche, concentración...) en lugar de una copia de sus modos. Nueve preajustes acompañados de sus fondos 1920×1080 (≈ 2,6 MB, `../dev/wallpapers/`) se copian en la carpeta elegida en el primer inicio y se referencian por **nombre de archivo únicamente**. Cada aplicación es transaccional: el estado anterior se archiva, una paleta que falla restaura el estilo *antes* de tocar iconos o cursor, y «aplicado» solo se anuncia tras releer el estado real.
* **Gestor de cursores** (`curseurs`): lista, vista previa, instalación y aplicación de un paquete en los cinco canales a la vez — compositor (`hyprctl setcursor`), ajustes de GNOME, INI de GTK3/GTK4, `environment.d` y `style_vars.json` — tamaños de 16 a 64 px.
* **Eje claro / oscuro** (`theme_mode: auto | dark | light`): Matugen se ejecuta en el modo solicitado y la variante de cada color se lee en consecuencia, de modo que un mismo fondo se puede forzar claro u oscuro. El shell, la barra, los paneles y Hyprland cambian instantáneamente; las aplicaciones GTK y Qt solo siguen al iniciarse (sus archivos de tema se leen al inicio), lo que la interfaz indica explícitamente.
* **Gestor de pantalla de inicio de sesión (SDDM)**: ajuste del tema Astronaut y variantes de Qylock desde el panel, sincronización automática de la distribución del teclado y la configuración regional UTF-8 desde el asistente de primer inicio (o pestaña de Teclado), y lanzador de vista previa seguro que aísla la prueba en un escritorio dedicado (`workspace 99`) para no bloquear nunca la sesión activa.

---

## 2. Despliegue y Actualizaciones

### Instalar o actualizar en una línea

```sh
mkdir -p "$HOME/.cache/quickshell"   && curl -fsSL -o "$HOME/.cache/quickshell/install_aethershell.sh"      https://raw.githubusercontent.com/anderveg/aethershell/master/../install.sh   && bash "$HOME/.cache/quickshell/install_aethershell.sh"
```

El script es **descargado y luego ejecutado**, nunca pasado a través de una tubería: se reejecuta a sí mismo desde el disco después de preparar el repositorio, y este `exec` mataría al `bash` que lee la tubería — `curl` saldría con error 23 («Failure writing output to destination») mientras la instalación continúa. Un archivo también deja `stdin` conectado al terminal, por lo que las solicitudes (`sudo`, confirmación de desinstalación) funcionan.

[`../install.sh`](../install.sh) se encarga de todo: lee la distribución en `/etc/os-release` (Arch o Fedora), clona el repositorio o lo actualiza mediante *fast-forward* si ya existe, respalda el entorno antes de desplegar y luego despliega el shell. La misma línea sirve para la instalación inicial y para todas las actualizaciones.

Opciones: `--dir RUTA` (por defecto: `$AETHERSHELL_DIR`, o `~/../dev/aethershell` si existe, sino `~/../dev/aethershell`), `--arch` / `--fedora` para forzar el destino en lugar de leerlo en `/etc/os-release`, `--branche NOMBRE`, `--check` (solo estado, sin desplegar nada), `--no-deploy`, `--help`. Con el enlace, pasan después de `bash -s --`:

```sh
curl -fsSL https://raw.githubusercontent.com/anderveg/aethershell/master/../install.sh | bash -s -- --check
```

El panel sigue la misma versión que el script: «Pantallas y Sistema» → «Actualización del shell» muestra la versión desplegada, la publicada en GitHub y ambas acciones (verificar ahora, actualizar en un terminal, copiar la línea para otra máquina). `core/version.json` se escribe en cada despliegue, y `as-core maj-shell` consulta a GitHub solo una vez cada **280 minutos** — entre ambas, responde desde su caché, por lo que abrir el panel no genera tráfico de red.

### Despliegue manual

El despliegue está pilotado por [`../install.sh`](../install.sh), compatible con **Arch Linux** y **Fedora** (detección automática mediante `/etc/os-release`):

```sh
# Inspeccionar dependencias necesarias sin instalar nada
./../install.sh --deps

# Análisis comparativo previo al vuelo (Repositorio ➜ Sistema vivo) sin modificaciones
./../install.sh --diff

# Despliegue completo con respaldo previo (tarball + instantánea final)
./../install.sh --arch    # o ./../install.sh --fedora

# Despliegue rápido sin nuevo respaldo (cuando el estado ya está archivado)
./../install.sh --deploy-only

# Desinstalación: retira el shell, sus unidades systemd y restablece ~/.config/hypr
# a una configuración mínima (SUPER + Return y SUPER + T abren un terminal)
./../install.sh --uninstall          # confirmación escribiendo «uninstall»
./../install.sh --uninstall --purge  # idem + temas SDDM, cachés y respaldos
```

`--uninstall` archiva primero `~/.config/quickshell` y `~/.config/hypr` en `~/.config/backups_env/uninstall_<marca_de_tiempo>/`, y luego retira únicamente lo que el despliegue había colocado: las cinco unidades systemd de usuario, el shell y, en el lado del sistema, el asistente `greeter-palette`, su regla polkit y los drop-ins de SDDM (se solicita contraseña de root). `--dry-run` lista las acciones sin modificar nada. Los paquetes del sistema nunca se eliminan. La misma opción está en el panel de configuración: pestaña **Sistema** ➜ cajón **Actualización del shell** ➜ *Desinstalar AetherShell*.

### Protección estricta de datos locales

El despliegue nunca reemplaza a ciegas los archivos vivos:
* **Estados locales protegidos**: `style_vars.json`, `bar_applets.json`, `widgets.json`, `autostart.json`, `todo.json`, `secrets.json`, `theme_profiles.json` (tus propios perfiles), etc., nunca se sobrescriben si ya existen en la máquina de destino. Los preajustes incluidos tienen `created_at: 0` y son actualizados por `as-core catalogue install`; tan pronto como vuelvas a guardar uno de ellos, toma tu fecha y ya no se vuelve a reemplazar.
* **Configuración de Hyprland personalizada**: los archivos personales bajo `~/.config/hypr/user/` (`binds.lua`, `autostart.txt`), así como `input.lua`, `general.lua` y los perfiles de hardware se mantienen intactos. En caso de diferencia con el repositorio, se genera una copia comparativa `.upstream` sin tocar el archivo activo.
* **Red de seguridad granular**: cada despliegue crea un archivo `.tar.gz` de respaldo y una instantánea espejo descomprimida bajo `~/.config/backups_env/snapshots/<marca_de_tiempo>/` con tabla de huellas sha256 (`manifest.json`), permitiendo restaurar un solo archivo si es necesario (`./../install.sh --restore-file <ruta>`).

---

### Instalar en otra máquina

Nada en el repositorio nombra a un usuario, carpeta personal o máquina: AetherShell se instala bajo cualquier cuenta, y `./../install.sh` siempre escribe en el `$HOME` de la persona que lo ejecuta.

Las rutas se componen por tanto con una variable, nunca fijas:

| Contexto | A utilizar |
|---|---|
| shell | `"$HOME"`, `"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"` |
| Rust | `paths::home_dir()`, `paths::runtime_dir()` (`../dev/rust/as-core/src/common/paths.rs`) |
| QML | `Quickshell.env("HOME")`, `Quickshell.env("XDG_RUNTIME_DIR")` |
| unidad systemd | `%h` (directiva de unidad) |

`../dev/core/as-core neutralite` verifica los archivos **seguidos**: señala cualquier `/home/<nombre>` que no sea un espacio reservado, así como el nombre de la persona y el de su máquina. El pre-volaje del despliegue lo ejecuta y muestra una advertencia. Una línea puede llevar una exención explícita — `neutralite:ok — <razón>` — para una compatibilidad asumida.

---

## 3. Prerrequisitos

* **Compositor**: [Hyprland](https://hyprland.org) 0.57 o más reciente (configuración modular en Lua);
* **Motor de interfaz**: [Quickshell](https://quickshell.org) 0.3.2 o superior;
* **Fuente de iconos**: `0xProto Nerd Font` (instalador incluido en `../dev/core/install_fonts.sh`);
* **Rust**: `cargo` (paquete `rust` en Arch) — el backend `as-core` se compila en el despliegue; sin él, las correcciones de Rust no surten efecto;
* **Dependencias del sistema**: listadas por distribución en [`../dev/dependencies.txt`](../dev/dependencies.txt) (`matugen`, `wireplumber`, `NetworkManager`, `cava`, etc.).

---

## 4. Estructura del proyecto

```
../install.sh            # Script unificado: instalación, actualización, pre-volaje, despliegue y respaldos
../dev/
├── rust/as-core/     # Backend unificado en Rust (compilado hacia ../dev/core/as-core)
├── core/             # Binario as-core, catálogos JSON, caché y scripts shell de integración
├── widgets/          # Componentes de escritorio (reloj, todo, sistema, clima...)
├── hypr_modular/     # Configuración modular de Hyprland en Lua
├── hyprquickpaper/   # Motor de fondo de pantalla y gestión de paletas
├── wallpapers/       # Nueve fondos 1920×1080 incluidos con el catálogo de temas (≈ 2,6 MB)
├── charge-limit/     # Acción polkit + asistente root del límite de carga de batería
├── sddm/             # Scripts y asistentes para la pantalla de inicio de sesión SDDM
├── systemd/          # Definiciones de unidades de usuario (quickshell.service...)
└── *.qml             # Superficies Quickshell (barra, panel, ventanas emergentes, selectores...)
```

---

## 5. Agradecimientos y Código tomado

AetherShell no nació de la nada: toma prestados bloques, conceptos y porciones de código de otros proyectos de código abierto cuyas aproximaciones eran pertinentes. Un gran agradecimiento a los siguientes autores por su trabajo compartido bajo licencia libre (en particular la colección [Noctalia Community Plugins](https://github.com/noctalia-../dev/community-plugins), bajo licencia MIT):

| Componente / Idea | Autor original | Descripción del intercambio |
|---|---|---|
| [Visualizer+](https://github.com/noctalia-../dev/community-plugins/tree/main/visualizerp) | **al3x** | Motor de captura PipeWire en C (`pwscope.c`), compilado localmente para alimentar la onda de audio. |
| [Agentik](https://github.com/noctalia-../dev/community-plugins/tree/main/agentik) | **notfinaldev** | Principios de lectura no bloqueante del estado del agente, emparejamiento proceso/sesión y gestión de estado. |
| [USB Manager](https://github.com/noctalia-../dev/community-plugins/tree/main/usb-manager) | **Marco Ziliani** | Arquitectura de lectura de hardware directa en `sysfs` y `udev` sin requerir un demonio residente pesado. |
| [To Do](https://github.com/noctalia-../dev/community-plugins/tree/main/todo) | **nightwatch75** | Inspiración inicial para el desacoplamiento entre el applet de la barra y el widget de escritorio para listas de tareas. |
| [NVTOP](https://github.com/noctalia-../dev/community-plugins/tree/main/nvtop) | **tordex** | Principio de monitorización del sistema bajo demanda (proceso lanzado únicamente cuando la vista está abierta). |
| [Wallpaper Depth](https://github.com/noctalia-../dev/official-plugins/tree/main/wallpaper_depth) | **noctalia** | Concepto de inmersión visual de las islas mediante máscaras de profundidad (Depth Anything V2). |
| [WallpaperFx.qml (`pocket-dots`)](https://github.com/diegoMalagrida/pocket-dots) | **diegoMalagrida** | Transiciones de fondo de pantalla por shader (`WallpaperFx.qml` / `wallfx.frag`: propagación orgánica `contagio`, silueta `perfil` y relevo sin contratiempos con `awww`). |
| [Impasto](https://github.com/andreumassanet/impasto) | **andreumassanet** | Inspiración para el morphing todo en uno de la Isla dinámica (selector de fondos de pantalla, lanzador, notas rápidas) y la edición directa / estilo *glass* de los widgets del escritorio. |
| **Quickshell & Hyprland** | **outfoxxed & vaxerski** | Por estos dos proyectos mayores que hacen posible la construcción de un shell de Wayland moderno y eficiente. |

---

## 6. Licencia

AetherShell se distribuye bajo licencia MIT — consulte el archivo [`../LICENSE`](../LICENSE) para más detalles.
