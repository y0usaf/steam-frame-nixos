{ pkgs, ... }:
let
  version = "26.4.1";
  src =
    (pkgs.callPackage ./valve.nix { }).bundleSource "steamos-manager-${version}-5.src.tar.gz"
      "sha256-BT9icR1kfmsmnYHdopWHbkx1i27bOBOAJpU+SDpHu0A="
      "steamos-manager-${version}"
      "304a0816d6f6373d0c83fc5636f29b6df5e2838a";

  steamosManager = pkgs.rustPlatform.buildRustPackage {
    pname = "steamos-manager";
    inherit version src;
    cargoLock.lockFile = "${src}/Cargo.lock";
    doCheck = false;

    postPatch = ''
      substituteInPlace $(grep -rl /usr/share/steamos-manager --include=*.rs .) \
        --replace-fail /usr/share/steamos-manager $out/share/steamos-manager
    '';

    nativeBuildInputs = with pkgs; [
      pkg-config
      rustPlatform.bindgenHook
      wrapGAppsNoGuiHook
    ];
    buildInputs = with pkgs; [
      glib
      gsettings-desktop-schemas
      speechd-minimal
      systemdLibs
    ];

    postInstall = ''
      mkdir -p $out/lib
      mv $out/bin/steamos-manager $out/lib/steamos-manager
      install -Dm644 -t $out/share/steamos-manager/devices data/devices/steam-frame.toml
      install -Dm644 -t $out/share/steamos-manager data/platform.toml
      install -Dm644 -t $out/share/dbus-1/interfaces data/interfaces/com.steampowered.SteamOSManager1.xml
      install -Dm644 -t $out/share/dbus-1/system-services data/system/com.steampowered.SteamOSManager1.service
      install -Dm644 -t $out/share/dbus-1/system.d data/system/com.steampowered.SteamOSManager1.conf
      install -Dm644 -t $out/share/dbus-1/services data/user/com.steampowered.SteamOSManager1.service
      install -Dm644 LICENSE $out/share/licenses/steamos-manager/LICENSE
    '';

    postFixup = ''
      wrapGApp $out/lib/steamos-manager
    '';
  };

  restart = {
    Type = "notify-reload";
    BusName = "com.steampowered.SteamOSManager1";
    Restart = "on-failure";
    RestartSec = 1;
    RestartMaxDelaySec = 10;
    RestartSteps = 3;
  };
  rateLimit = {
    StartLimitIntervalSec = 120;
    StartLimitBurst = 5;
  };
in
{
  environment.systemPackages = [ steamosManager ];
  services.dbus.packages = [ steamosManager ];

  systemd.services.steamos-manager = {
    description = "SteamOS Manager Daemon";
    wantedBy = [ "multi-user.target" ];
    environment.RUST_LOG = "info";
    unitConfig = rateLimit;
    serviceConfig = restart // {
      ExecStart = "${steamosManager}/lib/steamos-manager -r";
    };
  };

  systemd.user.services.steamos-manager = {
    description = "SteamOS Manager Daemon";
    wantedBy = [ "graphical-session.target" ];
    environment.RUST_LOG = "info";
    unitConfig = rateLimit;
    serviceConfig = restart // {
      ExecStart = "${steamosManager}/lib/steamos-manager";
    };
  };
}
