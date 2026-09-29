{ pkgs, ... }:
let
  valve = pkgs.callPackage ./valve.nix { };
  python = pkgs.python3.withPackages (p: [ p.pyyaml ]);
  fancontrol = "${python}/bin/python ${valve.fanControl}/share/deckard-fan-control/fancontrol.py";
  runtimeDir = name: {
    WorkingDirectory = "/run/${name}";
    RuntimeDirectory = name;
    RuntimeDirectoryMode = "0755";
    RuntimeDirectoryPreserve = true;
  };
  hw = "${valve.hwSupportTree}/lib";
in
{
  environment.etc = {
    "sysctl.d/70-vrlink-ip-size.conf".source = "${hw}/sysctl.d/50-vrlink-ip-size.conf";
    "sysctl.d/71-proton-max-maps.conf".source = "${hw}/sysctl.d/51-proton-max-maps.conf";
    "sysctl.d/72-sched-realtime.conf".source = "${hw}/sysctl.d/52-sched-realtime.conf";
    "modprobe.d/ath12k-deckard.conf".source = "${hw}/modprobe.d/ath12k.conf";
  };
  systemd.tmpfiles.packages = [ valve.hwSupportTree ];

  systemd.services.deckard-charger = {
    description = "Deckard Battery Charger service";
    unitConfig.DefaultDependencies = false;
    after = [ "local-fs.target" ];
    before = [ "basic.target" ];
    wantedBy = [ "basic.target" ];
    environment.XDG_RUNTIME_DIR = "/run/deckardcharger";
    serviceConfig = runtimeDir "deckardcharger" // {
      ExecStartPre = "${pkgs.coreutils}/bin/ln -sfn /run/deckardcharger /run/vpower";
      ExecStart = "${valve.charger}/bin/deckard_charge_daemon";
      WatchdogSec = "60s";
      Restart = "on-failure";
      RestartSec = "30s";
      EnvironmentFile = "-/run/deckardcharger/env";
    };
  };

  systemd.services.deckard-power-monitor = {
    description = "Deckard Power Monitor service";
    unitConfig.DefaultDependencies = false;
    after = [ "local-fs.target" ];
    before = [ "basic.target" ];
    wantedBy = [ "basic.target" ];
    serviceConfig = runtimeDir "power-monitor" // {
      ExecStart = "${valve.powerMonitor}/bin/deckard_power_monitor --interval-ms 2000";
      Restart = "on-failure";
      RestartSec = "30s";
    };
  };

  systemd.services.deckard-fan-control = {
    description = "Deckard fan control";
    wantedBy = [ "multi-user.target" ];
    path = [ valve.hwSupport ];
    environment.PYTHONUNBUFFERED = "1";
    serviceConfig = {
      Type = "simple";
      ExecStart = "${fancontrol} --run";
      ExecStopPost = "${fancontrol} --stop";
      OOMScoreAdjust = -1000;
      Restart = "on-failure";
      RestartSec = "1s";
    };
  };

  systemd.services.deckard-led-control = {
    description = "LED control";
    wantedBy = [ "multi-user.target" ];
    after = [ "frame-led-ready.service" ];
    serviceConfig = runtimeDir "deckardcharger" // {
      ExecStartPre = "${pkgs.coreutils}/bin/sleep 30";
      ExecStart = "${valve.ledControl}/bin/ledcontrol";
      ExecStop = "${pkgs.bash}/bin/sh -c 'echo shutdown > /run/deckardcharger/power_event || true'";
      KillSignal = "SIGTERM";
      TimeoutStopSec = 2;
    };
  };
}
