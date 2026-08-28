//! The subset of `.narinfo` this endpoint needs: where the NAR lives, how it is
//! compressed, and how big it is uncompressed.

use std::str::FromStr;

/// Compression schemes Hydra and Nix are known to upload.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Compression {
    None,
    Zstd,
    Xz,
    Bzip2,
    Brotli,
}

impl FromStr for Compression {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "none" | "" => Ok(Self::None),
            "zstd" => Ok(Self::Zstd),
            "xz" => Ok(Self::Xz),
            "bzip2" => Ok(Self::Bzip2),
            "br" | "brotli" => Ok(Self::Brotli),
            other => Err(format!("unsupported compression {other:?}")),
        }
    }
}

#[derive(Debug, Clone)]
pub struct NarInfo {
    /// Cache-relative location of the NAR, e.g. `nar/<filehash>.nar.zst`.
    pub url: String,
    pub compression: Compression,
    /// Uncompressed size. Used only to report how much of the archive a request
    /// had to decompress.
    pub nar_size: u64,
}

#[derive(Debug)]
pub enum ParseError {
    Missing(&'static str),
    Unsupported(String),
    Malformed(String),
}

impl std::fmt::Display for ParseError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Missing(field) => write!(f, "narinfo is missing {field}"),
            Self::Unsupported(msg) | Self::Malformed(msg) => write!(f, "{msg}"),
        }
    }
}

pub fn parse(body: &str) -> Result<NarInfo, ParseError> {
    let mut url = None;
    // Nix treats an absent `Compression` as bzip2 for historical reasons.
    let mut compression = Compression::Bzip2;
    let mut nar_size = 0u64;

    for line in body.lines() {
        let Some((key, value)) = line.split_once(':') else {
            continue;
        };
        let value = value.trim();
        match key {
            "URL" => url = Some(value.to_owned()),
            "Compression" => compression = value.parse().map_err(ParseError::Unsupported)?,
            "NarSize" => {
                nar_size = value
                    .parse()
                    .map_err(|_| ParseError::Malformed(format!("bad NarSize {value:?}")))?
            }
            _ => {}
        }
    }

    Ok(NarInfo {
        url: url.ok_or(ParseError::Missing("URL"))?,
        compression,
        nar_size,
    })
}

/// Whether a string is a Nix store path hash: 32 characters of nix-base32.
pub fn is_store_hash(hash: &str) -> bool {
    hash.len() == 32
        && hash.bytes().all(
            |b| matches!(b, b'0'..=b'9' | b'a'..=b'd' | b'f'..=b'n' | b'p'..=b's' | b'v'..=b'z'),
        )
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE: &str = "\
StorePath: /nix/store/00000000000000000000000000000000-hello-1.0
URL: nar/1bbbb.nar.zst
Compression: zstd
FileHash: sha256:1bbbb
FileSize: 12345
NarHash: sha256:1cccc
NarSize: 67890
References:
Sig: cache.nixos.org-1:abc
";

    #[test]
    fn parses_the_fields_the_endpoint_needs() {
        let info = parse(SAMPLE).unwrap();
        assert_eq!(info.url, "nar/1bbbb.nar.zst");
        assert_eq!(info.compression, Compression::Zstd);
        assert_eq!(info.nar_size, 67890);
    }

    #[test]
    fn an_absent_compression_field_means_bzip2() {
        let info = parse("URL: nar/x.nar.bz2\nNarSize: 1\n").unwrap();
        assert_eq!(info.compression, Compression::Bzip2);
    }

    #[test]
    fn an_unknown_compression_is_an_error_rather_than_a_default() {
        assert!(parse("URL: nar/x.nar.lz4\nCompression: lz4\n").is_err());
    }

    #[test]
    fn store_hashes_exclude_the_letters_nix_base32_omits() {
        assert!(is_store_hash("0prc795zpxdgvvgcg8bxd2l82gpmyx8b"));
        // `e`, `o`, `t` and `u` are not in the alphabet.
        assert!(!is_store_hash("eprc795zpxdgvvgcg8bxd2l82gpmyx8b"));
        assert!(!is_store_hash("short"));
        assert!(!is_store_hash("../../../etc/passwd0000000000000"));
    }
}
