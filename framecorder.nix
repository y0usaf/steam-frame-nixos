{
  pkgs,
  frameSession,
  ...
}:
let
  version = "0.1.1";
  src = pkgs.fetchFromGitHub {
    owner = "coah80";
    repo = "framecorder";
    tag = "v${version}";
    hash = "sha256-GbaNFKQaxwz/9STW5tVLItfdcDFACy2yvgpj02vmtRg=";
  };

  grabSocket = "/run/framecorder-grab.sock";
  card = "/dev/dri/card0";

  framecorder = pkgs.rustPlatform.buildRustPackage {
    pname = "framecorder";
    inherit version src;
    cargoLock.lockFile = "${src}/Cargo.lock";
    patches = [ ./framecorder/grab-socket.patch ];

    nativeBuildInputs = with pkgs; [
      pkg-config
      shaderc
      rustPlatform.bindgenHook
    ];
    buildInputs = with pkgs; [
      ffmpeg_7-headless
      pipewire
    ];
    doCheck = false;

    postInstall = ''
      rm $out/bin/framecorder-setup
      install -Dm644 app/icons/128x128.png $out/share/icons/hicolor/128x128/apps/framecorder.png
    '';
  };

  sync = pkgs.rustPlatform.buildRustPackage {
    pname = "framecorder-sync";
    inherit version src;
    sourceRoot = "${src.name}/sync";
    cargoLock.lockFile = "${src}/sync/Cargo.lock";
    doCheck = false;
  };

  desktopItem = pkgs.makeDesktopItem {
    name = "framecorder";
    desktopName = "framecorder";
    comment = "Records what the Frame's panels show";
    exec = "framecorder-ui --show";
    icon = "framecorder";
    categories = [
      "AudioVideo"
      "Recorder"
    ];
  };
in
{
  system.build.framecorder = framecorder;

  frame.session.fhsPackages = [
    framecorder
    desktopItem
  ];

  systemd.sockets.framecorder-grab = {
    description = "framecorder panel helper";
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = grabSocket;
      Accept = true;
      SocketUser = "steamos";
      SocketMode = "0600";
    };
  };

  systemd.services."framecorder-grab@" = {
    description = "framecorder panel helper";
    serviceConfig = {
      ExecStart = "${framecorder}/bin/framecorder-grab ${card}";
      StandardInput = "socket";
      StandardOutput = "journal";
      StandardError = "journal";
      User = "steamos";
      AmbientCapabilities = "CAP_SYS_ADMIN";
      CapabilityBoundingSet = "CAP_SYS_ADMIN";
      DevicePolicy = "closed";
      DeviceAllow = "${card} rw";
    };
  };

  systemd.user.services.framecorder-ui = {
    description = "framecorder dashboard tab";
    bindsTo = [ "steamvr.service" ];
    after = [ "steamvr.service" ];
    wantedBy = [ "steamvr.service" ];
    environment = frameSession.valveMesaEnv;
    serviceConfig = {
      Slice = "session.slice";
      Nice = 5;
      Restart = "on-failure";
      RestartSec = 5;
      EnvironmentFile = frameSession.mesavars;
      ExecStart = frameSession.inFhs "${framecorder}/bin/framecorder-ui";
    };
  };

  systemd.user.services.framecorder-sync = {
    description = "framecorder Wi-Fi sync";
    wantedBy = [ "default.target" ];
    unitConfig.ConditionUser = "steamos";
    serviceConfig = {
      Slice = "session.slice";
      Nice = 10;
      IOSchedulingClass = "idle";
      MemoryHigh = "64M";
      Restart = "on-failure";
      RestartSec = 5;
      ExecStart = "${sync}/bin/framecorder-sync";
    };
  };

  networking.firewall.allowedTCPPorts = [ 38619 ];
}
