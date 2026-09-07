# Changelog

## [Unreleased]

### Fixed

- ID3 tags written by `--tt`, `--ta`, `--tl`, `--ty`, `--tg` and `--tv` came
  out empty on Linux. The title was stored as an empty UTF-16 string, so tag
  editors and players showed nothing. Every Linux binary released so far,
  including 3.100-1, is affected; macOS and Windows were not.

- On Windows, `--id3v2-utf16` and `--id3v2-latin1` did not exist. They are
  there now, and accented text in tags works the same as on Linux and macOS.

### Changed

- The Windows binary is now built by the same compiler as the Linux and macOS
  ones (555 KB to 439 KB). Checked on Windows 10 against the previous binary:
  `--version`, and encoding a WAV gives a byte-identical MP3.

  It now uses the Universal C Runtime, which is part of Windows 10 and later.
  On Windows 7 or 8.1 that runtime has to be installed first — it comes through
  Windows Update. The previous binary did not need it.
