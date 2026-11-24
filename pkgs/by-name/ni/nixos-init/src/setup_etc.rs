use std::{
    collections::HashSet,
    env,
    fs::{self, OpenOptions},
    io::{ErrorKind, Write},
    os::unix::fs::{PermissionsExt, chown},
    path::{Path, PathBuf},
};

use anyhow::{Context, Result, bail};

use crate::fs::atomic_symlink;

const STATIC: &str = "/etc/static";

/// Entrypoint for the `setup-etc` binary.
///
/// Sets up `/etc` from the `etc` tree of a configuration when the `/etc`
/// overlay is not used:
///
/// - `/etc/static` links to the `etc` tree.
/// - Each file of the tree is a symlink in `/etc` that points into
///   `/etc/static`, or a copy when the tree gives a mode for it.
/// - Symlinks into `/etc/static` and copies that a previous configuration made
///   but the current configuration does not have are removed. `/etc/.clean`
///   records the copies.
///
/// Usage: `setup-etc <etc>`
pub fn setup_etc() -> Result<()> {
    let args: Vec<String> = env::args().collect();

    if args.len() != 2 {
        bail!("Usage: {} <etc>", args[0]);
    }

    // `nixos-enter` sets up `/etc/resolv.conf` as a bind mount.
    let in_nixos_enter = env::var("IN_NIXOS_ENTER").is_ok_and(|v| !v.is_empty() && v != "0");

    setup_etc_in(Path::new("/"), Path::new(&args[1]), in_nixos_enter)
}

/// Set up `<root>/etc` from the `etc` tree.
///
/// The symlinks that this creates point to `/etc/static`, not to
/// `<root>/etc/static`, thus they resolve in the system that has `<root>` as
/// its root.
fn setup_etc_in(root: &Path, etc: &Path, in_nixos_enter: bool) -> Result<()> {
    let root_etc = root.join("etc");
    let root_static = root_etc.join("static");

    // Update `/etc/static` atomically, to make the switch to a new
    // configuration more atomic.
    atomic_symlink(etc, &root_static)?;

    remove_obsolete_symlinks(&root_etc, &root_etc, &root_static);

    let clean_path = root_etc.join(".clean");
    let old_copied = match fs::read_to_string(&clean_path) {
        Ok(content) => content.lines().map(str::to_owned).collect(),
        Err(_) => Vec::new(),
    };
    // Record each copy as soon as it is made, so that a later run can remove
    // it even if this run stops before it rewrites `/etc/.clean`.
    let mut clean = OpenOptions::new()
        .append(true)
        .create(true)
        .open(&clean_path)
        .with_context(|| format!("Failed to open {}", clean_path.display()))?;

    let mut linker = Linker {
        root_etc: &root_etc,
        root_static: &root_static,
        etc,
        in_nixos_enter,
        users: IdMap::read(&root_etc.join("passwd")),
        groups: IdMap::read(&root_etc.join("group")),
        created: HashSet::new(),
        copied: Vec::new(),
        clean: &mut clean,
    };
    linker.walk(etc)?;
    let Linker {
        created,
        mut copied,
        ..
    } = linker;

    for name in old_copied {
        if name.is_empty() || created.contains(&name) {
            continue;
        }
        let path = root_etc.join(&name);
        eprintln!("removing obsolete file ‘/etc/{name}’...");
        if let Err(err) = fs::remove_file(&path) {
            eprintln!("could not remove {}: {err}", path.display());
        }
    }

    drop(clean);
    copied.sort();
    let content: String = copied
        .iter()
        .flat_map(|name| [name.as_str(), "\n"])
        .collect();
    fs::write(&clean_path, content)
        .with_context(|| format!("Failed to write {}", clean_path.display()))?;

    // Create `/etc/NIXOS` again: `/etc` may not be persistent.
    OpenOptions::new()
        .append(true)
        .create(true)
        .open(root_etc.join("NIXOS"))
        .context("Failed to create /etc/NIXOS")?;

    Ok(())
}

/// Remove the symlinks into `/etc/static` that `/etc/static` no longer has.
///
/// This does not go into `/etc/nixos`, where the NixOS sources can be.
fn remove_obsolete_symlinks(root_etc: &Path, dir: &Path, root_static: &Path) {
    let entries = match fs::read_dir(dir) {
        Ok(entries) => entries,
        Err(err) => {
            eprintln!("could not read {}: {err}", dir.display());
            return;
        }
    };

    for entry in entries.flatten() {
        let path = entry.path();
        let Ok(file_type) = entry.file_type() else {
            continue;
        };

        if file_type.is_dir() {
            if path != root_etc.join("nixos") {
                remove_obsolete_symlinks(root_etc, &path, root_static);
            }
            continue;
        }

        if !file_type.is_symlink() {
            continue;
        }
        let Ok(target) = fs::read_link(&path) else {
            continue;
        };
        if !target
            .as_os_str()
            .as_encoded_bytes()
            .starts_with(STATIC.as_bytes())
        {
            continue;
        }
        let Ok(rel) = path.strip_prefix(root_etc) else {
            continue;
        };
        if is_symlink(&root_static.join(rel)) {
            continue;
        }
        eprintln!("removing obsolete symlink ‘/etc/{}’...", rel.display());
        if let Err(err) = fs::remove_file(&path) {
            eprintln!("could not remove {}: {err}", path.display());
        }
    }
}

struct Linker<'a> {
    root_etc: &'a Path,
    root_static: &'a Path,
    etc: &'a Path,
    in_nixos_enter: bool,
    users: IdMap,
    groups: IdMap,
    /// The names of all entries in the `etc` tree.
    created: HashSet<String>,
    /// The names of the files that were copied.
    copied: Vec<String>,
    clean: &'a mut fs::File,
}

impl Linker<'_> {
    /// Go through the `etc` tree and make an entry in `/etc` for each file.
    fn walk(&mut self, dir: &Path) -> Result<()> {
        let entries =
            fs::read_dir(dir).with_context(|| format!("Failed to read {}", dir.display()))?;

        for entry in entries {
            let entry = entry.with_context(|| format!("Failed to read {}", dir.display()))?;
            let path = entry.path();
            let file_type = entry
                .file_type()
                .with_context(|| format!("Failed to stat {}", path.display()))?;

            self.link(&path, file_type.is_symlink())?;

            if file_type.is_dir() {
                self.walk(&path)?;
            }
        }

        Ok(())
    }

    /// Make the entry in `/etc` for one entry of the `etc` tree.
    fn link(&mut self, source: &Path, source_is_symlink: bool) -> Result<()> {
        let rel = source
            .strip_prefix(self.etc)
            .context("Failed to strip the etc prefix")?;
        let name = rel
            .to_str()
            .with_context(|| format!("{} is not valid UTF-8", rel.display()))?
            .to_owned();

        if name == "resolv.conf" && self.in_nixos_enter {
            return Ok(());
        }

        let target = self.root_etc.join(rel);
        if let Some(parent) = target.parent() {
            fs::create_dir_all(parent)
                .with_context(|| format!("Failed to create {}", parent.display()))?;
        }
        self.created.insert(name.clone());

        // A rename cannot replace a directory.
        if source_is_symlink && target.is_dir() {
            if is_static(&target) {
                let res = if is_symlink(&target) {
                    fs::remove_file(&target)
                } else {
                    fs::remove_dir_all(&target)
                };
                if let Err(err) = res {
                    eprintln!("could not remove {}: {err}", target.display());
                }
            } else {
                eprintln!("/etc/{name} directory contains user files. Symlinking may fail.");
            }
        }

        let static_path = self.root_static.join(rel);
        let mode_path = with_suffix(source, ".mode");

        if mode_path.exists() {
            let mode = read_value(&mode_path)?;
            if mode == "direct-symlink" {
                let res = fs::read_link(&static_path)
                    .map_err(anyhow::Error::from)
                    .and_then(|original| atomic_symlink(original, &target));
                if let Err(err) = res {
                    eprintln!("could not create symlink /etc/{name}: {err:#}");
                }
            } else {
                let uid = read_value(&with_suffix(source, ".uid"))?;
                let gid = read_value(&with_suffix(source, ".gid"))?;
                self.copy(&name, &static_path, &target, &mode, &uid, &gid);
            }
            self.copied.push(name.clone());
            writeln!(self.clean, "{name}").context("Failed to write /etc/.clean")?;
        } else if source_is_symlink {
            let original = Path::new(STATIC).join(rel);
            if let Err(err) = atomic_symlink(original, &target) {
                eprintln!("could not create symlink /etc/{name}: {err:#}");
            }
        }

        Ok(())
    }

    /// Copy a file into `/etc` with its owner and mode.
    ///
    /// `uid` and `gid` are names, or numbers with a `+` prefix.
    fn copy(&self, name: &str, source: &Path, target: &Path, mode: &str, uid: &str, gid: &str) {
        let tmp = with_suffix(target, ".tmp");

        if let Err(err) = fs::copy(source, &tmp) {
            eprintln!(
                "could not copy {} to {}: {err}",
                source.display(),
                tmp.display()
            );
        }

        let uid = self.users.resolve(uid);
        let gid = self.groups.resolve(gid);
        if uid.is_none() || gid.is_none() {
            eprintln!("could not find the owner of /etc/{name}");
        }
        if let Err(err) = chown(&tmp, uid, gid) {
            eprintln!("could not change the owner of {}: {err}", tmp.display());
        }

        match u32::from_str_radix(mode, 8) {
            Ok(mode) => {
                if let Err(err) = fs::set_permissions(&tmp, fs::Permissions::from_mode(mode)) {
                    eprintln!("could not change the mode of {}: {err}", tmp.display());
                }
            }
            Err(err) => eprintln!("invalid mode {mode} for /etc/{name}: {err}"),
        }

        if let Err(err) = fs::rename(&tmp, target) {
            eprintln!("could not create target {}: {err}", target.display());
            let _ = fs::remove_file(&tmp);
        }
    }
}

/// Map from user or group names to their ids, from `/etc/passwd` or
/// `/etc/group`.
struct IdMap(Vec<(String, u32)>);

impl IdMap {
    fn read(path: &Path) -> Self {
        let content = fs::read_to_string(path).unwrap_or_default();
        Self(
            content
                .lines()
                .filter_map(|line| {
                    let mut fields = line.split(':');
                    let name = fields.next()?;
                    let id = fields.nth(1)?.parse().ok()?;
                    Some((name.to_owned(), id))
                })
                .collect(),
        )
    }

    fn resolve(&self, value: &str) -> Option<u32> {
        if let Some(id) = value.strip_prefix('+') {
            return id.parse().ok();
        }
        self.0
            .iter()
            .find(|(name, _)| name == value)
            .map(|(_, id)| *id)
    }
}

/// Return true if the path points to the files in `/etc/static`.
///
/// That is: a symlink into `/etc/static`, or a directory that only contains
/// such entries.
fn is_static(path: &Path) -> bool {
    if is_symlink(path) {
        return fs::read_link(path).is_ok_and(|target| {
            target
                .as_os_str()
                .as_encoded_bytes()
                .starts_with(format!("{STATIC}/").as_bytes())
        });
    }

    if path.is_dir() {
        let Ok(entries) = fs::read_dir(path) else {
            return false;
        };
        return entries
            .into_iter()
            .all(|entry| entry.is_ok_and(|entry| is_static(&entry.path())));
    }

    false
}

fn is_symlink(path: &Path) -> bool {
    fs::symlink_metadata(path).is_ok_and(|m| m.file_type().is_symlink())
}

fn with_suffix(path: &Path, suffix: &str) -> PathBuf {
    let mut s = path.as_os_str().to_os_string();
    s.push(suffix);
    PathBuf::from(s)
}

/// Read a file of the `etc` tree that holds one value.
fn read_value(path: &Path) -> Result<String> {
    match fs::read_to_string(path) {
        Ok(content) => Ok(content.strip_suffix('\n').unwrap_or(&content).to_owned()),
        Err(err) if err.kind() == ErrorKind::NotFound => Ok(String::new()),
        Err(err) => Err(err).with_context(|| format!("Failed to read {}", path.display())),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    use std::os::unix::fs::{MetadataExt, symlink};

    struct Setup {
        _dir: tempfile::TempDir,
        root: PathBuf,
        store: PathBuf,
        uid: u32,
        gid: u32,
    }

    impl Setup {
        fn new() -> Result<Self> {
            let dir = tempfile::tempdir()?;
            let root = dir.path().join("root");
            let store = dir.path().join("store");
            fs::create_dir_all(root.join("etc"))?;
            fs::create_dir_all(&store)?;
            let meta = fs::metadata(dir.path())?;
            Ok(Self {
                root,
                store,
                uid: meta.uid(),
                gid: meta.gid(),
                _dir: dir,
            })
        }

        /// Make an `etc` tree with the given files: (name, content, mode).
        fn etc(&self, gen_name: &str, files: &[(&str, &str, Option<&str>)]) -> Result<PathBuf> {
            let etc = self.store.join(gen_name).join("etc");
            for (name, content, mode) in files {
                let file = self
                    .store
                    .join(format!("{gen_name}-{}", name.replace('/', "-")));
                fs::write(&file, content)?;
                let link = etc.join(name);
                fs::create_dir_all(link.parent().unwrap())?;
                symlink(&file, &link)?;
                if let Some(mode) = mode {
                    fs::write(with_suffix(&link, ".mode"), format!("{mode}\n"))?;
                    if *mode != "direct-symlink" {
                        fs::write(with_suffix(&link, ".uid"), format!("+{}\n", self.uid))?;
                        fs::write(with_suffix(&link, ".gid"), format!("+{}\n", self.gid))?;
                    }
                }
            }
            Ok(etc)
        }

        fn path(&self, name: &str) -> PathBuf {
            self.root.join("etc").join(name)
        }
    }

    #[test]
    fn links_copies_and_cleans() -> Result<()> {
        let s = Setup::new()?;

        let gen1 = s.etc(
            "gen1",
            &[
                ("hosts", "hosts1", None),
                ("old", "old", None),
                ("old-copy", "old-copy", Some("0600")),
                ("ssh/sshd_config", "sshd", Some("0640")),
                ("direct", "direct", Some("direct-symlink")),
            ],
        )?;
        fs::write(s.path("user-file"), "mine")?;

        setup_etc_in(&s.root, &gen1, false)?;

        assert_eq!(fs::read_link(s.path("static"))?, gen1);
        assert_eq!(
            fs::read_link(s.path("hosts"))?,
            Path::new("/etc/static/hosts")
        );
        assert!(!is_symlink(&s.path("ssh/sshd_config")));
        let meta = fs::metadata(s.path("ssh/sshd_config"))?;
        assert_eq!(meta.mode() & 0o7777, 0o640);
        assert_eq!(fs::read_to_string(s.path("ssh/sshd_config"))?, "sshd");
        assert_eq!(
            fs::read_link(s.path("direct"))?,
            s.store.join("gen1-direct")
        );
        assert_eq!(
            fs::read_to_string(s.path(".clean"))?,
            "direct\nold-copy\nssh/sshd_config\n"
        );
        assert!(s.path("NIXOS").exists());

        let gen2 = s.etc(
            "gen2",
            &[
                ("hosts", "hosts2", None),
                ("ssh/sshd_config", "sshd2", Some("0644")),
            ],
        )?;

        setup_etc_in(&s.root, &gen2, false)?;

        assert_eq!(fs::read_link(s.path("static"))?, gen2);
        assert!(!s.path("old").exists() && !is_symlink(&s.path("old")));
        assert!(!s.path("old-copy").exists());
        assert!(!is_symlink(&s.path("direct")));
        assert_eq!(fs::read_to_string(s.path("ssh/sshd_config"))?, "sshd2");
        assert_eq!(fs::read_to_string(s.path(".clean"))?, "ssh/sshd_config\n");
        assert_eq!(fs::read_to_string(s.path("user-file"))?, "mine");

        Ok(())
    }

    #[test]
    fn replaces_static_directory() -> Result<()> {
        let s = Setup::new()?;

        let gen1 = s.etc("gen1", &[("dir/a", "a", None)])?;
        setup_etc_in(&s.root, &gen1, false)?;
        assert!(s.path("dir").is_dir() && !is_symlink(&s.path("dir")));

        // The new configuration has `dir` as one symlink to a directory.
        let gen2 = s.store.join("gen2/etc");
        fs::create_dir_all(&gen2)?;
        let dir = s.store.join("gen2-dir");
        fs::create_dir_all(&dir)?;
        fs::write(dir.join("b"), "b")?;
        symlink(&dir, gen2.join("dir"))?;

        setup_etc_in(&s.root, &gen2, false)?;
        assert_eq!(fs::read_link(s.path("dir"))?, Path::new("/etc/static/dir"));

        Ok(())
    }

    #[test]
    fn skips_resolv_conf_in_nixos_enter() -> Result<()> {
        let s = Setup::new()?;

        let gen1 = s.etc("gen1", &[("resolv.conf", "nameserver ::1", None)])?;
        setup_etc_in(&s.root, &gen1, true)?;
        assert!(!is_symlink(&s.path("resolv.conf")));

        setup_etc_in(&s.root, &gen1, false)?;
        assert!(is_symlink(&s.path("resolv.conf")));

        Ok(())
    }

    #[test]
    fn keeps_nixos_directory() -> Result<()> {
        let s = Setup::new()?;

        fs::create_dir_all(s.path("nixos"))?;
        symlink("/etc/static/gone", s.path("nixos/link"))?;
        symlink("/etc/static/gone", s.path("link"))?;

        let gen1 = s.etc("gen1", &[])?;
        fs::create_dir_all(&gen1)?;
        setup_etc_in(&s.root, &gen1, false)?;

        assert!(is_symlink(&s.path("nixos/link")));
        assert!(!is_symlink(&s.path("link")));

        Ok(())
    }

    #[test]
    fn resolves_ids() {
        let map = IdMap(vec![("root".to_owned(), 0), ("sshd".to_owned(), 993)]);
        assert_eq!(map.resolve("sshd"), Some(993));
        assert_eq!(map.resolve("+42"), Some(42));
        assert_eq!(map.resolve("nobody"), None);
    }
}
