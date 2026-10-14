{
  pkgs,
}:
let
  inherit (pkgs) lib;

  commit = "fbdbca41fd45111219b6a188d5d7fe5c9e7872b7";
  version = "6.18.0";
  localVersion = "-gfbdbca41fd45";
  modDirVersion = version + localVersion;

  src = pkgs.fetchzip {
    name = "deckard-linux-${builtins.substring 0 12 commit}";
    url = "https://codeload.github.com/evlaV/deckard-linux/tar.gz/${commit}";
    hash = "sha256-evSMHO+lGmz7auKJvpp8t1stZJdxF5Omhx4ne8q9sTw=";
  };

  kernel =
    (pkgs.pkgsCross.aarch64-multiplatform.linuxKernel.manualConfig {
      pname = "linux-deckard";
      inherit src version modDirVersion;
      configfile = ./deckard-gabe_defconfig;
    }).overrideAttrs
      (old: {
        makeFlags = old.makeFlags ++ [ "LOCALVERSION=${localVersion}" ];
      });
in
kernel // { inherit src; }
