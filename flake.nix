{
  description = "the LAME MP3 encoder CLI as a single self-contained binary";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # LAME ships a single CLI (`lame`); the frontend links libmp3lame statically.
  # `pkgsStatic.lame` and the mingw cross both build the portable autotools C
  # cleanly. `--version` exits 0 and prints the version banner — a clean smoke
  # target on every platform.
  #
  # The only override is darwin-specific: pkgsStatic on darwin still leaves
  # libtool building a shared liblmp3lame (Apple has no static libSystem, so the
  # static adapter can't fully suppress `build_libtool_libs`). The frontend then
  # links libmp3lame.0.dylib and fails action-build's portability check. Force
  # libtool to emit only the static archive so libmp3lame folds into the binary
  # (libSystem stays the sole dynamic dep). Linux/musl already links static, so
  # gate on darwin. Same fix xz uses for its liblzma.
  outputs = { self, unpins-lib }:
    let
      ulib = unpins-lib.lib;
      # clang rejects an always_inline SSE intrinsic inlined into a function
      # compiled without the feature, and the i686 baseline has no SSE — the
      # configure probe misses it because `_mm_sfence()` alone compiles. Give
      # the feature to the one file that holds the SSE routines: upstream picks
      # them at RUNTIME (has_SSE), so a CPU without SSE still takes the C path.
      # Dropping HAVE_XMMINTRIN_H instead would ship i686 with no SSE path at all.
      sseTargetAttr = pkgs: drv:
        if pkgs.stdenv.hostPlatform.isx86_32
        then drv.overrideAttrs (old: {
          postPatch = (old.postPatch or "") + ''
            substituteInPlace libmp3lame/vector/xmm_quantize_sub.c \
              --replace-fail '#ifdef HAVE_XMMINTRIN_H' \
                '#ifdef HAVE_XMMINTRIN_H
            #pragma clang attribute push(__attribute__((target("sse"))), apply_to = function)' \
              --replace-fail '#endif	/* HAVE_XMMINTRIN_H */' \
                '#pragma clang attribute pop
            #endif	/* HAVE_XMMINTRIN_H */'
          '';
        })
        else drv;
      # Gate the override itself on darwin so the Linux/cross builds keep their
      # exact derivation (no empty-postConfigure rebuild).
      foldLibtoolStatic = pkgs: drv:
        if pkgs.stdenv.hostPlatform.isDarwin
        then drv.overrideAttrs (old: {
          postConfigure = (old.postConfigure or "") + ''
            sed -i 's/^build_libtool_libs=yes$/build_libtool_libs=no/' libtool
          '';
        })
        else drv;
      # Every ID3v2 text tag came out EMPTY on the six musl targets: `--tt
      # Titulo` wrote a TIT2 frame holding the UTF-16 BOM and nothing else. Not
      # a niche path — with ID3TAGS_EXTENDED on, the default text encoding is
      # TENC_UTF16, so --tt/--ta/--tl/--ty/--tg/--tv were all affected, and the
      # shipped v3.100-1 Linux binaries have it.
      #
      # toUtf16() writes the BOM into the buffer BEFORE checking whether
      # iconv_open("UTF-16LE//TRANSLIT", ...) succeeded, and on failure hands
      # that two-byte buffer back as the converted string. musl's iconv has no
      # //TRANSLIT, so the open always failed and the tag was always just the
      # BOM. glibc and GNU libiconv do have it — which is why the nixpkgs build
      # and macOS looked fine, and why Windows (no iconv at all, so it fell back
      # to Latin-1) looked fine too. Only what we ship on Linux was broken.
      #
      # Fall back to the plain charset name when the //TRANSLIT form is
      # rejected. Where //TRANSLIT works nothing changes; on musl the
      # conversion now runs, and the bytes match a glibc lame exactly.
      translitFallback = drv: drv.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace frontend/parse.c \
            --replace-fail 'iconv_open("ISO_8859-1//TRANSLIT", cur_code);' \
              'iconv_open("ISO_8859-1//TRANSLIT", cur_code);
            if (xiconv == (iconv_t)-1) xiconv = iconv_open("ISO-8859-1", cur_code);' \
            --replace-fail 'iconv_open("UTF-16LE//TRANSLIT", cur_code);' \
              'iconv_open("UTF-16LE//TRANSLIT", cur_code);
            if (xiconv == (iconv_t)-1) xiconv = iconv_open("UTF-16LE", cur_code);'
        '';
      });
      # Windows was the only target without `--id3v2-utf16`/`--id3v2-latin1`;
      # the other eight have them. Upstream turns them on with ID3TAGS_EXTENDED,
      # which comes either from HAVE_ICONV or from a Win32 block that explicitly
      # excludes __MINGW32__ — the expectation being that mingw takes the iconv
      # one. It cannot: that path calls nl_langinfo(CODESET) and mingw has no
      # <langinfo.h>, so adding libiconv gets as far as `checking for iconv...
      # yes` and then fails to compile. mingw fell through both and lost the
      # options in silence; configure only prints "consider installing GNU
      # libiconv" and carries on.
      #
      # The two converters upstream would use live in main.c inside that same
      # __MINGW32__-excluded block — together with `wmain`, which the multicall
      # fold must never see (a wide entry point leaves it with no `main`), and
      # with the MSVC-only <crtdbg.h>/<mbstring.h>. So define them here instead,
      # straight on the Win32 API. One hunk, one file, main.c untouched.
      #
      # The source encoding is CP_ACP, not the CP_UTF8 main.c uses. That is not
      # a deviation: main.c can say UTF-8 only because its `wmain` re-encodes
      # every argument from UTF-16 up front, and `wmain` is precisely what we
      # cannot have. Our entry point is the narrow `main`, so the CRT already
      # handed us argv in the ANSI code page — the same relationship the Linux
      # build has with nl_langinfo(CODESET). Reading it as UTF-8 turns every
      # non-ASCII title into U+FFFD (measured under wine: `Ação` -> A\ufffd\ufffdo).
      # The limit that leaves is the ACP's own: a character it cannot represent
      # was already lost in argv, before any code of ours runs.
      windowsIdTags = drv: drv.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace frontend/parse.c --replace-fail \
            '#if defined( _WIN32 ) && !defined(__MINGW32__)
#define ID3TAGS_EXTENDED

char* toLatin1(char const* s)
{
    return utf8ToLatin1(s);
}

unsigned short* toUtf16(char const* s)
{
    return utf8ToUtf16(s);
}
#endif' \
            '#if defined( _WIN32 ) && !defined(HAVE_ICONV)
#define ID3TAGS_EXTENDED
#include <windows.h>

char* toLatin1(char const* s)
{
    int n = MultiByteToWideChar(CP_ACP, 0, s, -1, NULL, 0);
    wchar_t* w = (n > 0) ? malloc(n * sizeof(wchar_t)) : NULL;
    char* out = NULL;
    if (w != NULL && MultiByteToWideChar(CP_ACP, 0, s, -1, w, n) != 0) {
        int m = WideCharToMultiByte(28591, 0, w, -1, NULL, 0, NULL, NULL);
        if (m > 0 && (out = malloc(m)) != NULL) {
            if (WideCharToMultiByte(28591, 0, w, -1, out, m, NULL, NULL) == 0) {
                free(out);
                out = NULL;
            }
        }
    }
    free(w);
    return out;
}

unsigned short* toUtf16(char const* s)
{
    int n = MultiByteToWideChar(CP_ACP, 0, s, -1, NULL, 0);
    wchar_t* w = (n > 0) ? malloc((n + 1) * sizeof(wchar_t)) : NULL;
    if (w != NULL) {
        w[0] = 0xfeff;
        if (MultiByteToWideChar(CP_ACP, 0, s, -1, w + 1, n) == 0) {
            free(w);
            w = NULL;
        }
    }
    return (unsigned short*) w;
}
#endif'
        '';
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
        (translitFallback (foldLibtoolStatic pkgs (sseTargetAttr pkgs pkgs.pkgsStatic.lame)));
      windowsBuild = pkgs: windowsIdTags (ulib.mingwStaticCross pkgs).lame;
    };
}
