{
  lib,
  stdenv,
  callPackage,
  fetchurl,
  fetchFromGitHub,
  runCommand,
  git,
  xcursorgen,
  systemdLibs,
  glibc,
  zstd,
  vulkan-headers,
  vulkan-loader,
  spirv-tools,
  spirv-headers,
  gamescope,
  wlroots_0_19,
}:
let
  release = "https://steamdeck-packages.steamos.cloud/archlinux-deckard-hotfixes/release/0.5.x";
  sources = "https://holo-packages.steamos.cloud/archlinux-deckard-hotfixes/source";

  escape = lib.replaceStrings [ "+" ] [ "%2B" ];
  fetchPkg =
    name: hash:
    fetchurl {
      inherit name hash;
      url = "${release}/${escape name}";
    };
  fetchSrc =
    name: hash:
    fetchurl {
      inherit name hash;
      url = "${sources}/${escape name}";
    };
  evlaV =
    repo: tag: hash:
    fetchFromGitHub {
      owner = "evlaV";
      inherit repo tag hash;
    };
  bundleSource =
    file: hash: gitDir: rev:
    runCommand "${gitDir}-${rev}" { nativeBuildInputs = [ git ]; } ''
      tar -xzf ${fetchSrc file hash}
      mkdir $out
      git --git-dir=$(echo */${gitDir}) archive ${rev} | tar -x -C $out
    '';

  khronos =
    repo: version: hash:
    fetchFromGitHub {
      owner = "KhronosGroup";
      inherit repo hash;
      rev = "vulkan-sdk-${version}";
    };

  vulkanLoader =
    (vulkan-loader.override {
      vulkan-headers = vulkan-headers.overrideAttrs {
        version = "1.4.309.0";
        src = khronos "Vulkan-Headers" "1.4.309.0" "sha256-LfJ7um+rzc4HdkJerHWkuPWeEc7ZFSBafbP+svAjklk=";
      };
    }).overrideAttrs
      (o: {
        version = "1.4.309.0";
        src = khronos "Vulkan-Loader" "1.4.309.0" "sha256-LZRACulOrnlL9do216zTeCTXGfy2pLxqs+f9phDD3Pg=";
        cmakeFlags = map (
          f: if lib.hasPrefix "-DSYSCONFDIR=" f then "-DSYSCONFDIR=/etc" else f
        ) o.cmakeFlags;
      });

  spirvTools =
    (spirv-tools.override {
      spirv-headers = spirv-headers.overrideAttrs {
        version = "1.4.363.0";
        src = khronos "SPIRV-Headers" "1.4.363.0" "sha256-PTD3GxQnENDngl6bf9YCmCVmvRgdBZczBosFCOCYEXU=";
      };
    }).overrideAttrs
      {
        version = "1.4.363.0";
        src = khronos "SPIRV-Tools" "1.4.363.0" "sha256-EYMtZe3gcskWKgJ1VTS89poc/RyuzmcnJiOys5qfrwU=";
        doCheck = false;
      };

  mesa = callPackage ./mesa.nix { inherit spirvTools vulkanLoader; };

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

  valveTree =
    pname: version: file: hash:
    valveTreeFrom pname version (fetchPkg file hash);
  valveTreeFrom =
    pname: version: src:
    stdenv.mkDerivation {
      inherit pname version src;
      nativeBuildInputs = [ zstd ];
      dontConfigure = true;
      dontBuild = true;
      dontPatchELF = true;
      dontStrip = true;
      dontPatchShebangs = true;
      dontCheckForBrokenSymlinks = true;
      unpackPhase =
        if lib.hasSuffix ".zst" src.name then
          "tar --zstd -xf $src && chmod -R u+rwX ."
        else
          "cp -a $src/. . && chmod -R u+rwX .";
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
  inherit bundleSource vulkanLoader mesa;

  gamescope =
    (gamescope.override {
      enableWsi = true;
      vulkan-loader = vulkanLoader;
      wlroots_0_19 = wlroots_0_19.override {
        libgbm = mesa;
        vulkan-loader = vulkanLoader;
      };
    }).overrideAttrs
      {
        version = "3.16.30";
        src = fetchFromGitHub {
          owner = "ValveSoftware";
          repo = "gamescope";
          tag = "3.16.30";
          fetchSubmodules = true;
          hash = "sha256-Rg0/P0kd6hmBTcWU9IbSXwV0qjJU+Qu/RHewONc7iqg=";
        };
      };

  charger =
    valvePackage "deckard-charger" "deckard-charger-20260928.1-6-aarch64.pkg.tar.zst"
      "sha256-uP+C1cYqVczi4W+rYFnNG7XubXPdY8UWhhbUY+VK9AE=";
  ledControl =
    valvePackage "deckard-led-control" "deckard-led-control-20260909.1-4-aarch64.pkg.tar.zst"
      "sha256-VLiidEGQDZuQ3pAePCbhbVm12Nl6lN15WWis0vHz8Nk=";
  powerMonitor =
    valvePackage "deckard-power-monitor" "deckard-power-monitor-20260915.1-4-aarch64.pkg.tar.zst"
      "sha256-n1hkm2FI4Ao1Wt4jtrk1AGdaGO61xmuFh7I6l0rxN0Q=";

  fanControl = valveTreeFrom "deckard-fan-control" "20261015.1" (
    evlaV "deckard-fan-control" "20261015.1" "sha256-9tQypf7qzmGlMiLugtGrXVmVyR5IDWbTHfQ0uyA23h0="
  );
  audioConfig = valveTreeFrom "deckard-audio-config" "20261016.1" (
    evlaV "deckard-audio-config" "20261016.1" "sha256-xjUGJziyHZLmNNyV45BT9YqNgbn3chdSzyO3VJgEiEY="
  );

  splctl = stdenv.mkDerivation {
    pname = "deckard-uboot-splctl";
    version = "20260128.3";
    src =
      evlaV "deckard-uboot-splctl" "20260128.3"
        "sha256-BwzmgGsi5WBf4fjPfMDBnyHxA53SarfypSZVOGtzxTY=";
    buildInputs = [ glibc.static ];
    installPhase = "install -Dm755 build/splctl $out/bin/splctl";
  };

  steamvrSession = stdenv.mkDerivation {
    pname = "deckard-steamvr-session";
    version = "1.7.0-4";
    src = fetchSrc "deckard-steamvr-session-1.7.0-4.src.tar.gz" "sha256-D/t6whokAMhV3wZN7uLxF0ccUWcOwxYMgXOd7V06fzg=";
    dontPatchShebangs = true;
    installPhase = ''
      install -TDm755 mesavars.sh $out/share/deckard/mesavars.sh
      for s in gamescope-session gamescope-env-list gamescope-cleanup gamescope-onready; do
        install -TDm755 $s $out/lib/steamos/$s
      done
      for u in plasma-session.target gamescope-session.service gamescope-session.target steamvr-plasma.service ibus-gamescope.service; do
        install -TDm644 $u $out/lib/systemd/user/$u
      done
      for s in gamescope-wayland plasma; do
        install -TDm644 $s.desktop $out/share/wayland-sessions/$s.desktop
      done
      install -TDm755 steamos-session-select $out/bin/steamos-session-select
      install -TDm755 start-gamescope-session $out/bin/start-gamescope-session
      install -TDm644 sddm-steamos.conf $out/etc/sddm.conf.d/steamos.conf
      install -TDm644 gamescope-portals.conf $out/share/xdg-desktop-portal/gamescope-portals/gamescope-portals.conf
      install -TDm644 kde.portal $out/share/xdg-desktop-portal/gamescope-portals/kde.portal
    '';
  };

  steamBootstrap = stdenv.mkDerivation {
    pname = "steam-bootstrap";
    version = "1.0.0.85-5";
    src = fetchSrc "steam-1.0.0.85-5.src.tar.gz" "sha256-MXQQiGz3Xyu7PoZArcUImIunQoM7LPJHdBs352pxCAQ=";
    dontPatchShebangs = true;
    dontCheckForBrokenSymlinks = true;
    postUnpack = "tar -xzf $sourceRoot/steam_1.0.0.85.tar.gz -C $sourceRoot";
    dontBuild = true;
    installPhase = ''
      make -C steam-launcher DESTDIR=$PWD/tmp install
      mkdir -p $out/lib/steam
      cp -a tmp/usr/share $out/
      ln -s /usr/share/application/steam.desktop $out/lib/steam/steam.desktop
      install -Dm755 steam-launcher/com.valvesoftware.Steam.metainfo.xml $out/share/metainfo/com.valvesoftware.Steam.metainfo.xml
      install -Dm755 steam.sh $out/bin/steam
      install -Dm755 bin_steam.sh $out/lib/steam/bin_steam.sh
      ln -s /usr/lib/steam/bin_steam.sh $out/lib/steam/steam
      install -Dm755 steam-launcher/steam_subscriber_agreement.txt -t $out/share/licenses/steam
      install -Dm644 steam-launcher/debian/changelog -t $out/share/doc/steam
    '';
  };

  holoCursors = stdenv.mkDerivation {
    pname = "holo-cursors";
    version = "2-3";
    src =
      bundleSource "holo-cursors-2-3.src.tar.gz" "sha256-6p3XAqDrt1O6kNw919SXXRNGxDpr7eJuX1H8ERYLIS0="
        "holo-cursors"
        "v2";
    nativeBuildInputs = [ xcursorgen ];
    installPhase = ''
      cp -a usr $out
      mkdir -p $out/share/icons/steam/cursors
      cd $out/share/holo
      xcursorgen holo-cursor-config $out/share/icons/steam/cursors/default
    '';
  };

  steamvr =
    valveTree "deckard-steamvr" "r25765468"
      "deckard-steamvr-rel-r25765468+24cb4748-1-aarch64.pkg.tar.zst"
      "sha256-fkPH5uavys4sG0SnCxOIzxklcvmqNUR1nFoWXx2Yxpg=";
  steamClient =
    valveTree "deckard-steam" "r1792099137"
      "deckard-steam-rel-r1792099137+f85bf676-1-aarch64.pkg.tar.zst"
      "sha256-+oEMAJ6PJ8xih8zmNB6BDOTPDDlcrncJOWEPUZsT0r4=";
  vulkanLayers =
    valveTree "deckard-vulkan-layers" "20261023.1-4"
      "deckard-vulkan-layers-linux-aarch64-20261023.1-4-aarch64.pkg.tar.zst"
      "sha256-wW2h/jwT0JQojc+pNBa0+GyLJ421ecMzFZhyzExSf6M=";
  fpga =
    valveTree "deckard-fpga" "20260612.1-3" "deckard-fpga-20260612.1-3-aarch64.pkg.tar.zst"
      "sha256-WJz6dxbrqLUQthWAKfVOlo4LxTDbWmoYZTsHdq94iho=";
  eeprom =
    valveTree "deckard-eeprom" "20260121.1-6" "deckard-eeprom-20260121.1-6-aarch64.pkg.tar.zst"
      "sha256-Y29yRs72IBfbiqN96Mq7nOYh9VJz+je3DqTRiKBZlRg=";
  hwSupportTree =
    valveTree "deckard-hw-support-tree" "20261019.1-1"
      "deckard-hw-support-20261019.1-1-aarch64.pkg.tar.zst"
      "sha256-weMUM9t5ii1uaCRDNm0uAYqfa/W3227J8jNKzNoYR10=";

  hwSupport = stdenv.mkDerivation {
    pname = "deckard-hw-support";
    version = "20261019.1-1";
    src = fetchPkg "deckard-hw-support-20261019.1-1-aarch64.pkg.tar.zst" "sha256-weMUM9t5ii1uaCRDNm0uAYqfa/W3227J8jNKzNoYR10=";
    nativeBuildInputs = [ zstd ];
    unpackPhase = "tar --zstd -xf $src";
    installPhase = ''
      mkdir -p $out/bin $out/share/vr
      cp usr/local/bin/* $out/bin/
      cp usr/local/vr/* $out/share/vr/
      substituteInPlace $out/bin/* --replace-quiet /usr/local/vr/ $out/share/vr/
    '';
  };

  firmware =
    runCommand "linux-firmware-deckard-20261023.1"
      {
        src = fetchFromGitHub {
          owner = "evlaV";
          repo = "deckard-linux-firmware";
          rev = "594f649dc68489760d5f2f1fca4fd542fb8e7858";
          hash = "sha256-ihr4j+sOtkfwACsTmMDGhJhYzgen2dHYMyrxi8Dy2fA=";
        };
      }
      ''
        mkdir -p $out/lib/firmware
        cp -a $src/* $out/lib/firmware/
      '';
}
