{
  config,
  lib,
  pkgs,
  ...
}:
let
  valve = pkgs.callPackage ../pkgs/valve.nix { };
  amixer = "${pkgs.alsa-utils}/bin/amixer";
  mute = [
    "${amixer} -cLPASS sset 'Speaker Left Digital' 0"
    "${amixer} -cLPASS sset 'Speaker Right Digital' 0"
  ];
  steamvrPath = pkgs.writeShellScriptBin "steamvr" "echo ${valve.steamvr}/opt/steamvr";
  setup = pkgs.buildFHSEnv {
    name = "deckard-audio-setup";
    targetPkgs = p: [
      valve.audioConfig
      valve.eeprom
      valve.firmware
      steamvrPath
      p.alsa-utils
    ];
    runScript = "/usr/share/deckard-audio-config/soundsetup.sh";
  };
  ucm = pkgs.buildEnv {
    name = "deckard-ucm2";
    paths = [
      pkgs.alsa-ucm-conf
      valve.audioConfig
    ];
    pathsToLink = [ "/share/alsa/ucm2" ];
  };
  speakerLv2 = pkgs.runCommand "valve-speaker-lv2" { nativeBuildInputs = [ pkgs.patchelf ]; } ''
    mkdir -p $out/lib/lv2
    cp -r --no-preserve=mode ${valve.audioConfig}/lib/lv2/valve_{denver,boulder}_speakers.lv2 $out/lib/lv2/
    patchelf --set-rpath ${
      lib.makeLibraryPath [
        pkgs.stdenv.cc.cc.lib
        pkgs.stdenv.cc.libc
      ]
    } $out/lib/lv2/*/*.so
  '';
  wireplumberRules = pkgs.runCommand "deckard-wireplumber" { } ''
    mkdir -p $out/share/wireplumber/wireplumber.conf.d
    install -m644 ${valve.audioConfig}/etc/wireplumber/wireplumber.conf.d/*.conf $out/share/wireplumber/wireplumber.conf.d/
  '';
  speakerChains = pkgs.runCommand "deckard-speaker-chains" { } ''
    for c in denver boulder; do
      mkdir -p $out/$c/pipewire/filter-chain.conf.d
      ln -s ${valve.audioConfig}/etc/pipewire/filter-chains/filter-chain-$c.conf $out/$c/pipewire/filter-chain.conf.d/speakers.conf
    done
  '';
in
{
  services.pipewire.wireplumber.configPackages = [ wireplumberRules ];
  environment.etc."wireplumber/scripts/microphone-tracker.lua".source =
    "${valve.audioConfig}/etc/wireplumber/scripts/microphone-tracker.lua";
  environment.etc."wireplumber/scripts/spatial-node-config.lua".source =
    "${valve.audioConfig}/etc/wireplumber/scripts/spatial-node-config.lua";

  services.pipewire.configPackages = [
    (pkgs.runCommand "deckard-pipewire-access" { } ''
      install -Dm644 ${valve.audioConfig}/etc/pipewire/pipewire.conf.d/module-access-args.conf \
        $out/share/pipewire/pipewire.conf.d/10-module-access-args.conf
    '')
  ];
  services.pipewire.wireplumber.extraConfig."10-frame-no-video-monitors"."wireplumber.profiles".main =
    {
      "monitor.libcamera" = "disabled";
      "monitor.v4l2" = "disabled";
    };

  systemd.services.deckard-audio-setup = {
    description = "Valve's speaker calibration for the built-in speakers";
    wantedBy = [ "sound.target" ];
    after = [ "sound.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = mute;
      ExecStart = "${setup}/bin/deckard-audio-setup";
      ExecStartPost = "-${config.systemd.package}/bin/systemctl --user --machine=steamos@.host try-restart wireplumber.service";
      ExecStopPost = mute;
    };
  };

  systemd.user.services.wireplumber.environment.ALSA_CONFIG_UCM2 = "${ucm}/share/alsa/ucm2";

  systemd.user.services.deckard-speaker-eq = {
    description = "Valve's speaker EQ for the built-in speakers";
    wantedBy = [ "pipewire.service" ];
    bindsTo = [ "pipewire.service" ];
    after = [ "pipewire.service" ];
    unitConfig = {
      StartLimitIntervalSec = 300;
      StartLimitBurst = 5;
    };
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = 10;
    };
    environment.LV2_PATH = "${speakerLv2}/lib/lv2";
    path = [ pkgs.coreutils ];
    script = ''
      firmware=$(for f in /sys/bus/i2c/drivers/max98390/*/max98390/firmware; do echo "$(cat "$f")"; done | sort -u)
      case "$firmware" in
        dsm_param_GG.bin) chain=boulder ;;
        dsm_param_OW_2018b.bin | dsm_param_FG_2018b.bin) chain=denver ;;
        *)
          echo "amps have no calibrated DSM parameters loaded: $firmware" >&2
          exit 1
          ;;
      esac
      XDG_CONFIG_HOME=${speakerChains}/$chain exec ${config.services.pipewire.package}/bin/pipewire -c filter-chain.conf
    '';
  };

  environment.systemPackages = [ pkgs.alsa-utils ];
}
