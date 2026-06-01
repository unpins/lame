# lame

Standalone build of [LAME](https://lame.sourceforge.io/) — the high-quality MP3 encoder CLI.

[![CI](https://github.com/unpins/lame/actions/workflows/lame.yml/badge.svg)](https://github.com/unpins/lame/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) project — native single-binary builds with no third-party runtime dependencies.

Encodes WAV/AIFF/raw PCM to MP3 (and decodes MP3 back to WAV) with `libmp3lame` linked in statically.

## Installation

Install with [unpin](https://github.com/unpins/unpin):

```bash
unpin lame
```

Or run without installing:

```bash
unpin run lame --version
```

## Build locally

```bash
nix build github:unpins/lame
./result/bin/lame --version
```

Or run directly:

```bash
nix run github:unpins/lame -- in.wav out.mp3
```

The first invocation will offer to add the [unpins.cachix.org](https://unpins.cachix.org) substituter so most pulls come pre-built.

## Man pages

`lame.1` is embedded in the binary — read with `unpin man lame`.

## Manual download

The [Releases](https://github.com/unpins/lame/releases) page has standalone binaries for manual download.

## Build notes

- Single upstream CLI (`lame`); `libmp3lame` is linked in statically.
- **Windows:** `mingw` cross, single `.exe`, no companion DLLs.
- **No upstream features disabled** on any platform.
