{
  pkgs,
}:
let
  rev = "733a4be78129d1a9481d22c0a6ace630adacc1da";
  short = builtins.substring 0 12 rev;
  version = "6.18.0";
  localVersion = "-g" + short;
  cross = pkgs.pkgsCross.aarch64-multiplatform;

  kernel = cross.linuxKernel.manualConfig {
    pname = "linux-deckard";
    inherit version;
    modDirVersion = version + localVersion;
    src = cross.fetchzip {
      name = "deckard-linux-" + short;
      url = "https://codeload.github.com/evlaV/deckard-linux/tar.gz/" + rev;
      hash = "sha256-KmqUYdPVMPxVQdvAUhCQ/WebSFZAcIUrVbbMsxVTYQk=";
      extension = "tar.gz";
    };
    configfile = ./gabe_defconfig;
    extraMakeFlags = [ ("LOCALVERSION=" + localVersion) ];
  };
in
(cross.linuxPackagesFor kernel).extend (
  _: super: {
    v4l2loopback = super.v4l2loopback.overrideAttrs {
      version = "20251112.1";
      src = cross.fetchFromGitHub {
        owner = "evlaV";
        repo = "deckard-v4l2loopback";
        tag = "20251112.1";
        hash = "sha256-Ycx9GZM21aY/QwqYpvK1iInhVs0L/va4GTXnNwnggf4=";
      };
    };
  }
)
