{ pkgs, ... }:
let
  rev = "fd665daed3b2212cd3213d51d700b526e8fa57d2";
  src = pkgs.fetchFromGitLab {
    domain = "gitlab.steamos.cloud";
    owner = "holo";
    repo = "steamos-manager";
    inherit rev;
    hash = "sha256-HzNfduyOqnUU8A95ClldlO3TMYHbrJVA0fdE+QLYHTc=";
  };

  steamosManager = pkgs.rustPlatform.buildRustPackage {
    pname = "steamos-manager";
    version = "26.4.1-unstable-2026-09-15";
    inherit src;
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

  systemd.user.services.steamos-manager-session-cleanup = {
    description = "SteamOS Manager temporary session cleanup";
    wantedBy = [ "graphical-session-pre.target" ];
    requires = [ "steamos-manager.service" ];
    after = [
      "default.target"
      "steamos-manager.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${steamosManager}/bin/steamosctl clean-temporary-sessions";
    };
  };
}
