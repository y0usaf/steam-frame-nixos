{
  lib,
  stdenv,
  fetchurl,
  runCommand,
  systemdLibs,
  zstd,
  kmod,
}:
let
  repo = "https://steamdeck-packages.steamos.cloud/archlinux-deckard-hotfixes/release/0.3.x";
  version = "6.18.0";
  modDirVersion = "6.18.0-gfbdbca41fd45";

  fetchPkg =
    name: hash:
    fetchurl {
      inherit name hash;
      url = "${repo}/${lib.replaceStrings [ "+" ] [ "%2B" ] name}";
    };

  kernelPkg = fetchPkg "linux-618-deckard-6.18.0+gfbdbca41fd45-1-aarch64.pkg.tar.zst" "sha256-rD6gK8DimRMK2Ol38dgvunFI11IS7JkUO1ZoT3QRiQk=";
  firmwarePkg = fetchPkg "linux-firmware-deckard-20260801.1+gita0b66dde-1-any.pkg.tar.zst" "sha256-XZzb+i8t0nqtijH0TdG5Cb6kt4L+1ViEwF+MdWH0OOo=";

  kconfig = lib.listToAttrs (
    lib.concatMap (
      line:
      let
        m = builtins.match "(CONFIG_[A-Za-z0-9_]+)=(.*)" line;
      in
      lib.optional (m != null) (lib.nameValuePair (lib.elemAt m 0) (lib.elemAt m 1))
    ) (lib.splitString "\n" (builtins.readFile ./valve/kernel.config))
  );
  get = option: kconfig."CONFIG_${option}" or null;

  valvePackage =
    pname: file: hash:
    stdenv.mkDerivation {
      inherit pname;
      version = lib.elemAt (builtins.match "${pname}-([0-9.]+-[0-9]+)-.*" file) 0;
      src = fetchPkg file hash;
      nativeBuildInputs = [ zstd ];
      unpackPhase = "tar --zstd -xf $src";
      installPhase = ''
        mkdir -p $out
        for d in bin share; do
          if [ -d usr/$d ]; then cp -r usr/$d $out/; fi
        done
      '';
      postFixup = ''
        for f in $out/bin/*; do
          if [ "$(head -c 4 "$f" | tail -c 3)" = ELF ]; then
            patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
              --set-rpath ${
                lib.makeLibraryPath [
                  systemdLibs
                  stdenv.cc.libc
                ]
              } "$f"
          fi
        done
      '';
    };

  valveTree = pname: version: file: hash: valveTreeFrom pname version (fetchPkg file hash);
  valveTreeFrom =
    pname: version: src:
    stdenv.mkDerivation {
      inherit pname version src;
      nativeBuildInputs = [ zstd ];
      dontPatchELF = true;
      dontStrip = true;
      dontPatchShebangs = true;
      dontCheckForBrokenSymlinks = true;
      unpackPhase = "tar --zstd -xf $src && chmod -R u+rwX .";
      installPhase = ''
        mkdir -p $out
        for d in bin lib share libexec local; do
          if [ -d usr/$d ]; then cp -a usr/$d $out/; fi
        done
        for d in opt etc; do
          if [ -d $d ]; then cp -a $d $out/; fi
        done
      '';
    };
in
{
  charger = valvePackage "deckard-charger" "deckard-charger-20260908.2-1-aarch64.pkg.tar.zst" "sha256-mVzyEvpQL94fHzzs2SDTTprU6vQMyDHl8A2pWlLLG1s=";
  fanControl = valvePackage "deckard-fan-control" "deckard-fan-control-20260324.1-2-any.pkg.tar.zst" "sha256-5K1kVGMX+Lx6xd7cc/N0PFfeT58GyZyu+9YaUUrYqFQ=";
  ledControl = valvePackage "deckard-led-control" "deckard-led-control-20260909.1-1-aarch64.pkg.tar.zst" "sha256-EI1jCz/Z7cUV4XrSAn8RGvBLS/3VyLzpchBb2RqLaRE=";
  powerMonitor = valvePackage "deckard-power-monitor" "deckard-power-monitor-20260814.2-1-aarch64.pkg.tar.zst" "sha256-r6zY2p+7ewhtFiPYFo05s6YFNKLbqMrSzdomV6l2DcU=";

  steamvr = valveTree "deckard-steamvr" "r25358740" "deckard-steamvr-rel-r25358740+28b72a4f-1-aarch64.pkg.tar.zst" "sha256-kKYAd16z6IVtxHX4MWapOikKCx87ToKmnI4qjwa53ck=";
  steamClient = valveTree "deckard-steam" "r1789506314" "deckard-steam-rel-r1789506314+d1110443-1-aarch64.pkg.tar.zst" "sha256-qvf8D6vMN2Owr3I8R4WI4qn5qS4xzd/T6bFR7xjjz7s=";
  steamvrSession = valveTree "deckard-steamvr-session" "1.6.1-8" "deckard-steamvr-session-1.6.1-8-aarch64.pkg.tar.zst" "sha256-yLHbtvjUP+9jFg6Sa4seeqDMDEAbTm7ag/TwzLqMTYM=";
  gamescope = valveTree "gamescope-deckard" "3.16.28-1" "gamescope-3.16.28-1-aarch64.pkg.tar.zst" "sha256-bKcmiPYxwh9js5y1VEFldahzABIozzDLE+zlwYHjTNM=";
  steamBootstrap = valveTree "steam-bootstrap" "1.0.0.85-2" "steam-1.0.0.85-2-aarch64.pkg.tar.zst" "sha256-1RY3HKASdpR6lsz9Mw1xsNF52YtRRNrC2R//AURdz9Q=";
  spirvTools = valveTreeFrom "spirv-tools-holo" "1.4.309.0-4" (fetchurl {
    name = "spirv-tools-1.4.309.0-4-aarch64.pkg.tar.zst";
    url = "${repo}/spirv-tools-1%3A1.4.309.0-4-aarch64.pkg.tar.zst";
    hash = "sha256-VFgGK9Lh6QoDj5ArewuBYROZaYw60W70YEyejR7cv/4=";
  });
  vulkanLoader = valveTree "vulkan-icd-loader-holo" "1.4.309.0-4" "vulkan-icd-loader-1.4.309.0-4-aarch64.pkg.tar.zst" "sha256-+hZoQs8K4u5hvcbWXLBvDceG5cgicu4MiVXz0RFVOEc=";
  mesa = valveTree "deckard-mesa" "26.3.0-devel-8aa73b4b" "deckard-mesa-linux-aarch64-26.3.0_devel+git8aa73b4b-1-aarch64.pkg.tar.zst" "sha256-uPmLPbV+1Frv0GsrVA3ItnqGx4Q0VmH5rsOdnF37920=";
  vulkanLayers = valveTree "deckard-vulkan-layers" "20260914.1-1" "deckard-vulkan-layers-linux-aarch64-20260914.1-1-aarch64.pkg.tar.zst" "sha256-BdN/sh78kfYkU7BSzyfZsX4feD98KffT8SsURQg5nLo=";
  fpga = valveTree "deckard-fpga" "20250924.1-1" "deckard-fpga-20250924.1-1-aarch64.pkg.tar.zst" "sha256-tses6YB9SqRjcddxHk+ti4UbFoA+sDEahR85lCdWj9U=";
  v4l2loopback = valveTree "v4l2loopback-deckard" "20251112.1" "linux-618-v4l2loopback-deckard-20251112.1+gfbdbca41fd45-1-aarch64.pkg.tar.zst" "sha256-5IB7bASBt4q6rtqPWgpmNvdoyF3iIpi3+iUTuu3ez1o=";
  audioConfig = valveTree "deckard-audio-config" "20260914.1-1" "deckard-audio-config-20260914.1-1-any.pkg.tar.zst" "sha256-29bYQQscmnGN5ORaTOiodmUdqHiOdwP2ibue68rmF7U=";
  eeprom = valveTree "deckard-eeprom" "20260121.1-3" "deckard-eeprom-20260121.1-3-aarch64.pkg.tar.zst" "sha256-GkL+3twg0VGmeTp6GfgkBAeOsXTZgrbhDdqqZoPwmlQ=";
  hwSupportTree = valveTree "deckard-hw-support-tree" "20260911.1-1" "deckard-hw-support-20260911.1-1-aarch64.pkg.tar.zst" "sha256-rZmH1+NbOozBUghkn4juxu3By9LA5wD6MUiGdrQ/3Kg=";

  hwSupport = stdenv.mkDerivation {
    pname = "deckard-hw-support";
    version = "20260911.1-1";
    src = fetchPkg "deckard-hw-support-20260911.1-1-aarch64.pkg.tar.zst" "sha256-rZmH1+NbOozBUghkn4juxu3By9LA5wD6MUiGdrQ/3Kg=";
    nativeBuildInputs = [ zstd ];
    unpackPhase = "tar --zstd -xf $src";
    installPhase = ''
      mkdir -p $out/bin $out/share/vr
      cp usr/local/bin/* $out/bin/
      cp usr/local/vr/* $out/share/vr/
      substituteInPlace $out/bin/* --replace-quiet /usr/local/vr/ $out/share/vr/
    '';
  };

  kernel = lib.makeOverridable (
    { ... }:
    runCommand "linux-deckard-${modDirVersion}"
      {
        nativeBuildInputs = [
          zstd
          kmod
        ];
        passthru = {
          inherit version modDirVersion;
          configfile = ./valve/kernel.config;
          features = { };
          target = "Image";
          kernelAtLeast = lib.versionAtLeast version;
          kernelOlder = lib.versionOlder version;
          config = kconfig // {
            isSet = option: get option != null;
            getValue = get;
            isYes = option: get option == "y";
            isNo = option: get option == "n";
            isModule = option: get option == "m";
            isEnabled = option: lib.elem (get option) [ "y" "m" ];
            isDisabled = option: !(lib.elem (get option) [ "y" "m" ]);
          };
        };
      }
      ''
        mkdir pkg
        tar --zstd -xf ${kernelPkg} -C pkg
        mkdir -p $out/lib/modules $out/dtbs
        cp pkg/boot/Image-${modDirVersion} $out/Image
        cp -r pkg/usr/lib/modules/${modDirVersion} $out/lib/modules/
        depmod -b $out -a ${modDirVersion}
        cp -r pkg/boot/dtbs/${modDirVersion}/qcom $out/dtbs/
      ''
  ) { };

  firmware = runCommand "linux-firmware-deckard" { nativeBuildInputs = [ zstd ]; } ''
    mkdir pkg
    tar --zstd -xf ${firmwarePkg} -C pkg
    mkdir -p $out/lib
    cp -r pkg/usr/lib/firmware $out/lib/
  '';
}
