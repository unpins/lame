{
  description = "Standalone build of the LAME MP3 encoder CLI";

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
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "lame";
      smoke = [ "--version" ];
      smokePattern = "3\\.100";
      build = pkgs: foldLibtoolStatic pkgs pkgs.pkgsStatic.lame;
      windowsBuild = pkgs: (ulib.mingwStaticCross pkgs).lame;
    };
}
