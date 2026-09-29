{ pkgs, ... }:
let
  valve = pkgs.callPackage ./valve.nix { };
  wireplumberRules = pkgs.runCommand "deckard-wireplumber-alsa" { } ''
    mkdir -p $out/share/wireplumber/wireplumber.conf.d
    for f in 50-alsa-config 51-alsa-disable; do
      install -m644 ${valve.audioConfig}/etc/wireplumber/wireplumber.conf.d/$f.conf $out/share/wireplumber/wireplumber.conf.d/
    done
  '';
  amixer = "${pkgs.alsa-utils}/bin/amixer";
in
{
  services.pipewire.wireplumber.configPackages = [ wireplumberRules ];
  services.pipewire.wireplumber.extraConfig."10-frame-no-video-monitors"."wireplumber.profiles".main = {
    "monitor.libcamera" = "disabled";
    "monitor.v4l2" = "disabled";
  };

  systemd.services.deckard-speakers-muted = {
    description = "Mute the built-in speakers until Valve's speaker calibration runs";
    wantedBy = [ "sound.target" ];
    after = [ "sound.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = [
        "${amixer} -c0 sset 'Speaker Left Digital' 0"
        "${amixer} -c0 sset 'Speaker Right Digital' 0"
      ];
    };
  };

  environment.systemPackages = [ pkgs.alsa-utils ];
}
