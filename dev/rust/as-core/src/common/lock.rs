use std::collections::HashSet;
use std::fs::{File, OpenOptions};
use std::io;
use std::os::unix::io::AsRawFd;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};

/// Verrou inter-processus `flock(LOCK_EX)` sur un fichier voisin `<cible>.verrou`.
/// Ne jamais supprimer le fichier `.verrou` ni verrouiller le JSON cible directement.
///
/// Deux propriétés, apprises à la dure :
/// 1. **Réentrant dans un même processus** — `flock` refuse un second verrou sur le
///    même fichier via un autre descripteur, y compris depuis le même process. Or
///    nos chemins « lire, modifier, écrire » prennent le verrou puis appellent
///    `write_json_atomic`, qui le reprend : sans réentrance, l'appelant se bloquait
///    sur LUI-MÊME (constaté sur `preset_save`, qui gelait deux secondes puis
///    écrivait sans verrou).
/// 2. **Attente bornée** — un process tué en tenant le verrou (timeout, SIGKILL)
///    laissait l'appelant bloqué indéfiniment. On réessaie 2 s, puis on continue
///    sans verrou : l'écriture reste atomique (`.tmp` + `rename`), perdre une mise
///    à jour concurrente est moins grave qu'un gel.
pub struct FileLock {
    _file: Option<File>,
    /// `None` = verrou déjà tenu par ce processus (aucun `flock` refait).
    tenu: Option<PathBuf>,
}

fn verrous_du_processus() -> &'static Mutex<HashSet<PathBuf>> {
    static TENUS: OnceLock<Mutex<HashSet<PathBuf>>> = OnceLock::new();
    TENUS.get_or_init(|| Mutex::new(HashSet::new()))
}

impl FileLock {
    pub fn acquire(target: &Path) -> io::Result<Self> {
        let mut lock_os = target.as_os_str().to_os_string();
        lock_os.push(".verrou");
        let lock_path = PathBuf::from(lock_os);

        // Réentrance : ce processus tient déjà ce verrou, on ne redemande rien.
        {
            let set = verrous_du_processus()
                .lock()
                .unwrap_or_else(|e| e.into_inner());
            if set.contains(&lock_path) {
                return Ok(Self {
                    _file: None,
                    tenu: None,
                });
            }
        }

        if let Some(parent) = lock_path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let file = OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .open(&lock_path)?;

        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(2);
        loop {
            let ret = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
            if ret == 0 {
                let mut set = verrous_du_processus()
                    .lock()
                    .unwrap_or_else(|e| e.into_inner());
                set.insert(lock_path.clone());
                return Ok(Self {
                    _file: Some(file),
                    tenu: Some(lock_path),
                });
            }
            let err = io::Error::last_os_error();
            if err.kind() != io::ErrorKind::WouldBlock {
                return Err(err);
            }
            if std::time::Instant::now() >= deadline {
                eprintln!(
                    "as-core: verrou de {} indisponible après 2 s, écriture sans verrou",
                    target.display()
                );
                return Ok(Self {
                    _file: None,
                    tenu: None,
                });
            }
            std::thread::sleep(std::time::Duration::from_millis(25));
        }
    }
}

impl Drop for FileLock {
    fn drop(&mut self) {
        if let (Some(file), Some(chemin)) = (&self._file, &self.tenu) {
            let mut set = verrous_du_processus()
                .lock()
                .unwrap_or_else(|e| e.into_inner());
            if set.remove(chemin) {
                unsafe {
                    libc::flock(file.as_raw_fd(), libc::LOCK_UN);
                }
            }
        }
    }
}
