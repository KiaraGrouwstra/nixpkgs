//! Forward-only streaming reader for the NAR format.
//!
//! A NAR is a sequence of length-prefixed, 8-byte-padded strings; directory
//! entries are sorted by name. That ordering is what makes a single forward
//! pass sufficient: at each directory we either descend into the wanted entry,
//! skip an entry that sorts before it, or conclude the entry is absent because
//! we have passed where it would have been.
//!
//! [`NarReader::locate`] stops at the first content byte of the wanted file, so
//! the caller can stream the contents out and drop the upstream connection
//! without reading the remainder of the archive.

use std::future::Future;
use std::io;
use std::pin::Pin;

use tokio::io::{AsyncRead, AsyncReadExt};

/// Upper bound on a structural token or a file name. Real NAR names are bounded
/// by `NAME_MAX`; this only exists so a corrupt length cannot cause a huge
/// allocation.
const MAX_TOKEN: u64 = 64 * 1024;

/// Upper bound on directory nesting while skipping a subtree.
const MAX_DEPTH: usize = 128;

const SKIP_BUF: usize = 64 * 1024;

/// What [`NarReader::locate`] found at the requested path.
#[derive(Debug, PartialEq, Eq)]
pub enum Located {
    /// A regular file. The reader is positioned at its first content byte.
    File {
        size: u64,
        executable: bool,
    },
    Symlink {
        target: String,
    },
    Directory,
    NotFound,
}

fn padding(n: u64) -> u64 {
    (8 - (n % 8)) % 8
}

fn invalid(msg: impl Into<String>) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, msg.into())
}

pub struct NarReader<R> {
    inner: R,
    position: u64,
    /// Reusable discard buffer. It lives here rather than on the stack because
    /// every `skip` is inside an async fn, and a buffer in a future's state
    /// would be paid for at every level of the parse.
    scratch: Vec<u8>,
}

impl<R: AsyncRead + Unpin + Send> NarReader<R> {
    pub fn new(inner: R) -> Self {
        Self {
            inner,
            position: 0,
            scratch: vec![0u8; SKIP_BUF],
        }
    }

    /// Uncompressed bytes consumed so far. This is the quantity that costs the
    /// server: it is how much of the NAR had to be decompressed to answer.
    pub fn position(&self) -> u64 {
        self.position
    }

    /// Fill `buf` completely, counting the bytes towards [`Self::position`].
    pub async fn read_exact_counted(&mut self, buf: &mut [u8]) -> io::Result<()> {
        self.inner.read_exact(buf).await?;
        self.position += buf.len() as u64;
        Ok(())
    }

    async fn read_u64(&mut self) -> io::Result<u64> {
        let mut buf = [0u8; 8];
        self.read_exact_counted(&mut buf).await?;
        Ok(u64::from_le_bytes(buf))
    }

    async fn skip(&mut self, mut n: u64) -> io::Result<()> {
        while n > 0 {
            let take = n.min(self.scratch.len() as u64) as usize;
            self.inner.read_exact(&mut self.scratch[..take]).await?;
            self.position += take as u64;
            n -= take as u64;
        }
        Ok(())
    }

    /// Read one length-prefixed, padded string.
    async fn read_token(&mut self) -> io::Result<Vec<u8>> {
        let len = self.read_u64().await?;
        if len > MAX_TOKEN {
            return Err(invalid(format!(
                "nar token of {len} bytes exceeds the limit"
            )));
        }
        let mut buf = vec![0u8; len as usize];
        self.read_exact_counted(&mut buf).await?;
        self.skip(padding(len)).await?;
        Ok(buf)
    }

    async fn expect(&mut self, want: &str) -> io::Result<()> {
        let got = self.read_token().await?;
        if got == want.as_bytes() {
            Ok(())
        } else {
            Err(invalid(format!(
                "expected {want:?} in nar, got {:?}",
                String::from_utf8_lossy(&got)
            )))
        }
    }

    /// Consume the `nix-archive-1` magic.
    pub async fn read_magic(&mut self) -> io::Result<()> {
        self.expect("nix-archive-1").await
    }

    /// Walk to `want` (a path split into components) from the root node.
    ///
    /// On [`Located::File`] the reader stops at the first content byte, which is
    /// exactly the offset a `.ls` listing records as `narOffset`.
    pub async fn locate(&mut self, want: &[String]) -> io::Result<Located> {
        let mut want = want;
        loop {
            self.expect("(").await?;
            self.expect("type").await?;
            let node_type = self.read_token().await?;

            match node_type.as_slice() {
                b"regular" => {
                    let mut executable = false;
                    let mut token = self.read_token().await?;
                    if token == b"executable" {
                        // Followed by an empty string, then `contents`.
                        self.read_token().await?;
                        executable = true;
                        token = self.read_token().await?;
                    }
                    if token != b"contents" {
                        return Err(invalid("malformed regular node in nar"));
                    }
                    let size = self.read_u64().await?;
                    if want.is_empty() {
                        return Ok(Located::File { size, executable });
                    }
                    // A path component remains but this node is a file.
                    return Ok(Located::NotFound);
                }
                b"symlink" => {
                    self.expect("target").await?;
                    let target = self.read_token().await?;
                    if !want.is_empty() {
                        return Ok(Located::NotFound);
                    }
                    let target = String::from_utf8(target)
                        .map_err(|_| invalid("symlink target is not valid utf-8"))?;
                    return Ok(Located::Symlink { target });
                }
                b"directory" => {
                    if want.is_empty() {
                        return Ok(Located::Directory);
                    }
                    let wanted = want[0].as_bytes();
                    loop {
                        let token = self.read_token().await?;
                        if token == b")" {
                            return Ok(Located::NotFound);
                        }
                        if token != b"entry" {
                            return Err(invalid("malformed directory node in nar"));
                        }
                        self.expect("(").await?;
                        self.expect("name").await?;
                        let name = self.read_token().await?;
                        self.expect("node").await?;

                        match name.as_slice().cmp(wanted) {
                            std::cmp::Ordering::Less => {
                                self.skip_node(0).await?;
                                self.expect(")").await?;
                            }
                            // Entries are sorted, so the wanted name would have
                            // appeared by now.
                            std::cmp::Ordering::Greater => return Ok(Located::NotFound),
                            std::cmp::Ordering::Equal => break,
                        }
                    }
                    want = &want[1..];
                }
                other => {
                    return Err(invalid(format!(
                        "unknown nar node type {:?}",
                        String::from_utf8_lossy(other)
                    )))
                }
            }
        }
    }

    /// Consume a whole node, starting at its opening `(`.
    fn skip_node(
        &mut self,
        depth: usize,
    ) -> Pin<Box<dyn Future<Output = io::Result<()>> + Send + '_>> {
        Box::pin(async move {
            if depth > MAX_DEPTH {
                return Err(invalid("nar nesting is too deep"));
            }
            self.expect("(").await?;
            self.expect("type").await?;
            let node_type = self.read_token().await?;

            match node_type.as_slice() {
                b"regular" => {
                    let mut token = self.read_token().await?;
                    if token == b"executable" {
                        self.read_token().await?;
                        token = self.read_token().await?;
                    }
                    if token != b"contents" {
                        return Err(invalid("malformed regular node in nar"));
                    }
                    let size = self.read_u64().await?;
                    self.skip(size + padding(size)).await?;
                    self.expect(")").await?;
                }
                b"symlink" => {
                    self.expect("target").await?;
                    self.read_token().await?;
                    self.expect(")").await?;
                }
                b"directory" => loop {
                    let token = self.read_token().await?;
                    if token == b")" {
                        break;
                    }
                    if token != b"entry" {
                        return Err(invalid("malformed directory node in nar"));
                    }
                    self.expect("(").await?;
                    self.expect("name").await?;
                    self.read_token().await?;
                    self.expect("node").await?;
                    self.skip_node(depth + 1).await?;
                    self.expect(")").await?;
                },
                other => {
                    return Err(invalid(format!(
                        "unknown nar node type {:?}",
                        String::from_utf8_lossy(other)
                    )))
                }
            }
            Ok(())
        })
    }
}

/// Split a request path into NAR components, rejecting anything that could
/// escape the store path or is otherwise not a valid NAR name.
pub fn split_path(path: &str) -> Option<Vec<String>> {
    let mut out = Vec::new();
    for component in path.split('/') {
        if component.is_empty() || component == "." || component == ".." {
            return None;
        }
        if component.contains('\0') {
            return None;
        }
        out.push(component.to_owned());
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Minimal NAR writer, used to build fixtures.
    enum Node {
        File {
            executable: bool,
            contents: &'static [u8],
        },
        Symlink(&'static str),
        Dir(Vec<(&'static str, Node)>),
    }

    fn token(out: &mut Vec<u8>, s: &[u8]) {
        out.extend_from_slice(&(s.len() as u64).to_le_bytes());
        out.extend_from_slice(s);
        out.extend(std::iter::repeat_n(0u8, padding(s.len() as u64) as usize));
    }

    fn write_node(out: &mut Vec<u8>, node: &Node) {
        token(out, b"(");
        token(out, b"type");
        match node {
            Node::File {
                executable,
                contents,
            } => {
                token(out, b"regular");
                if *executable {
                    token(out, b"executable");
                    token(out, b"");
                }
                token(out, b"contents");
                token(out, contents);
            }
            Node::Symlink(target) => {
                token(out, b"symlink");
                token(out, b"target");
                token(out, target.as_bytes());
            }
            Node::Dir(entries) => {
                token(out, b"directory");
                // The format requires sorted entries; sort rather than trusting
                // the fixture so tests cannot accidentally rely on scan order.
                let mut entries: Vec<_> = entries.iter().collect();
                entries.sort_by_key(|(name, _)| *name);
                for (name, child) in entries {
                    token(out, b"entry");
                    token(out, b"(");
                    token(out, b"name");
                    token(out, name.as_bytes());
                    token(out, b"node");
                    write_node(out, child);
                    token(out, b")");
                }
            }
        }
        token(out, b")");
    }

    fn nar(root: Node) -> Vec<u8> {
        let mut out = Vec::new();
        token(&mut out, b"nix-archive-1");
        write_node(&mut out, &root);
        out
    }

    fn fixture() -> Vec<u8> {
        nar(Node::Dir(vec![
            (
                "bin",
                Node::Dir(vec![(
                    "hello",
                    Node::File {
                        executable: true,
                        contents: b"#!/bin/sh\necho hi\n",
                    },
                )]),
            ),
            ("lib", Node::Symlink("share")),
            (
                "share",
                Node::Dir(vec![(
                    "applications",
                    Node::Dir(vec![(
                        "hello.desktop",
                        Node::File {
                            executable: false,
                            contents: b"[Desktop Entry]\nName=Hello\n",
                        },
                    )]),
                )]),
            ),
        ]))
    }

    async fn locate(bytes: &[u8], path: &str) -> (Located, u64) {
        let mut reader = NarReader::new(std::io::Cursor::new(bytes.to_vec()));
        reader.read_magic().await.unwrap();
        let components = split_path(path).unwrap();
        let found = reader.locate(&components).await.unwrap();
        (found, reader.position())
    }

    #[tokio::test]
    async fn finds_a_nested_file_and_stops_at_its_contents() {
        let bytes = fixture();
        let (found, position) = locate(&bytes, "share/applications/hello.desktop").await;
        assert_eq!(
            found,
            Located::File {
                size: 27,
                executable: false
            }
        );
        // The reader must stop exactly at the first content byte, which is what
        // a `.ls` listing calls `narOffset`.
        assert_eq!(
            &bytes[position as usize..][..27],
            b"[Desktop Entry]\nName=Hello\n"
        );
    }

    #[tokio::test]
    async fn reports_the_executable_bit() {
        let (found, _) = locate(&fixture(), "bin/hello").await;
        assert_eq!(
            found,
            Located::File {
                size: 18,
                executable: true
            }
        );
    }

    #[tokio::test]
    async fn returns_symlinks_and_directories_rather_than_following_them() {
        assert_eq!(
            locate(&fixture(), "lib").await.0,
            Located::Symlink {
                target: "share".to_owned()
            }
        );
        assert_eq!(
            locate(&fixture(), "share/applications").await.0,
            Located::Directory
        );
    }

    #[tokio::test]
    async fn misses_do_not_read_the_whole_archive() {
        let bytes = fixture();
        // `aaa` sorts before every entry, so the scan can give up immediately.
        let (found, position) = locate(&bytes, "aaa").await;
        assert_eq!(found, Located::NotFound);
        assert!(
            position < bytes.len() as u64 / 2,
            "gave up after {position} of {} bytes",
            bytes.len()
        );
    }

    #[tokio::test]
    async fn missing_paths_under_a_real_directory_are_not_found() {
        assert_eq!(
            locate(&fixture(), "share/applications/nope.desktop")
                .await
                .0,
            Located::NotFound
        );
        // Descending through a regular file is a miss, not a parse error.
        assert_eq!(
            locate(&fixture(), "bin/hello/more").await.0,
            Located::NotFound
        );
    }

    #[test]
    fn path_traversal_is_rejected() {
        assert!(split_path("../etc/passwd").is_none());
        assert!(split_path("share//applications").is_none());
        assert!(split_path("share/./applications").is_none());
        assert_eq!(
            split_path("share/applications/a.desktop").unwrap(),
            vec!["share", "applications", "a.desktop"]
        );
    }
}
