{
  description = "the LAME MP3 encoder CLI as a single self-contained binary";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # LAME ships a single CLI (`lame`); the frontend links libmp3lame statically.
  outputs = { self, unpins-lib }:
    let
      ulib = unpins-lib.lib;
      # darwin: pkgsStatic still leaves libtool building a shared libmp3lame
      # (Apple has no static libSystem, so the static adapter can't fully
      # suppress `build_libtool_libs`), and the frontend would then link
      # libmp3lame.0.dylib. Force libtool to emit only the static archive so
      # libmp3lame folds into the binary. Same fix xz uses for its liblzma.
      # Gated on darwin so the other targets keep their exact derivation.
      foldLibtoolStatic = pkgs: drv:
        if pkgs.stdenv.hostPlatform.isDarwin
        then drv.overrideAttrs (old: {
          postConfigure = (old.postConfigure or "") + ''
            sed -i 's/^build_libtool_libs=yes$/build_libtool_libs=no/' libtool
          '';
        })
        else drv;
      # ID3v2 text tags came out empty on musl (no //TRANSLIT in its iconv);
      # the measured why is in the patch header.
      translitFallback = drv: drv.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./patches/iconv-translit-fallback.patch ];
      });
      # Windows lacked `--id3v2-utf16`/`--id3v2-latin1` (mingw takes neither of
      # upstream's ID3TAGS_EXTENDED paths); the patch defines the converters on
      # the Win32 API. The why, measured, is in its header.
      windowsIdTags = drv: drv.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./patches/windows-id3tags-extended.patch ];
      });
      # 0.1 s of 440 Hz mono at 8 kHz, 16-bit — the smallest WAV that still
      # exercises a real encode. Kept as a constant so the check needs no
      # generator in the builder.
      probeWavB64 =
        "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";
      # `smoke` runs `--version`, which prints the same banner from an encoder
      # that can no longer tag, encode or decode. Do the real thing wherever the
      # build host can run the result (native, i686-from-x86_64, darwin — not
      # the crosses, not mingw).
      #
      # The tag half is the guard for the //TRANSLIT bug above, and it has to
      # ask the question the right way round: `--id3v2-only`, because lame also
      # writes an ASCII ID3v1 trailer and grepping the whole file would match
      # that even with an empty v2 frame. Then the UTF-16 text must appear once
      # the NULs are stripped, and must NOT appear as plain bytes — otherwise
      # the conversion silently did nothing.
      withRoundTrip = pkgs: drv: drv.overrideAttrs (old: {
        doInstallCheck = pkgs.stdenv.buildPlatform.canExecute pkgs.stdenv.hostPlatform;
        installCheckPhase = ''
          runHook preInstallCheck
          echo '${probeWavB64}' | base64 -d > p.wav
          "$out/bin/lame" p.wav p.mp3
          "$out/bin/lame" --decode p.mp3 back.wav
          test -s back.wav || { echo "decoding produced nothing"; exit 1; }
          "$out/bin/lame" --id3v2-only --id3v2-utf16 --tt UNPINPROBE p.wav u.mp3
          LC_ALL=C tr -d '\000' < u.mp3 | grep -q UNPINPROBE || {
            echo "--id3v2-utf16 wrote an empty tag"; exit 1; }
          grep -q UNPINPROBE u.mp3 && {
            echo "--id3v2-utf16 stored the title unconverted"; exit 1; }
          "$out/bin/lame" --id3v2-only --id3v2-latin1 --tt UNPINPROBE p.wav l.mp3
          grep -q UNPINPROBE l.mp3 || {
            echo "--id3v2-latin1 wrote an empty tag"; exit 1; }
          echo "installCheck: encode, decode, and ID3v2 titles in UTF-16 and Latin-1"
          runHook postInstallCheck
        '';
      });
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "lame";

      # Build via the unpin-llvm engine + emit a bitcode multicall module.
      engine = "unpin-llvm";
      multicall = {
        # The `.exe` on the engine too, not the nixpkgs mingw-gcc cross.
        windows = true;
        programs = [{ name = "lame"; }];
      };
      smoke = [ "--version" ];
      smokePattern = "^LAME (32|64)bits version 3\\.100";
      build = pkgs: withRoundTrip pkgs
        (translitFallback (foldLibtoolStatic pkgs pkgs.pkgsStatic.lame));
      windowsBuild = pkgs: windowsIdTags (ulib.mingwStaticCross pkgs).lame;
    };
}
