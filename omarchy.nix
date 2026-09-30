{
  lib,
  pkgs,
  frameSession,
  ...
}:
let
  width = 1920;
  height = 1080;
  mode = "${toString width}x${toString height}@60";
  scale = "1.5";
  overlayMetres = "2.67";
  themes = [
    "tokyo-night"
    "catppuccin"
    "rose-pine"
    "kanagawa"
  ];

  src = pkgs.fetchFromGitHub {
    owner = "basecamp";
    repo = "omarchy";
    rev = "c668141e9c42b13c80c9ca4ea108e11708c5e8a5";
    hash = "sha256-nstxM+CP6al2I4N1LAKdYBvJ4tytD1m8jssiCD7PXTY=";
  };

  omarchy = pkgs.runCommand "omarchy-4.0.4" { } ''
    cp -r ${src} $out
    chmod -R u+w $out
    rm -rf $out/manual $out/test $out/docs $out/agents
    find $out/themes -mindepth 1 -maxdepth 1 ${
      lib.concatMapStringsSep " " (t: "! -name ${t}") themes
    } -exec rm -r {} +
    patchShebangs $out/bin
  '';

  aquamarine = pkgs.aquamarine.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./omarchy/aquamarine-gamescope.patch ];
  });

  uwsmApp = pkgs.writeShellScriptBin "uwsm-app" ''
    [ "$1" = -- ] && shift
    exec ${pkgs.util-linux}/bin/setsid -f "$@"
  '';

  tools = with pkgs; [
    coreutils
    findutils
    gnugrep
    gnused
    gawk
    gnutar
    gzip
    procps
    util-linux
    systemd
    jq
    gum
    fzf
    socat
    inotify-tools
    curl
    imagemagick
    libnotify
    fontconfig
    wl-clipboard
    wtype
    grim
    slurp
    brightnessctl
    pamixer
    networkmanager
    xdg-utils
    xdg-terminal-exec
    foot
    hyprland
    quickshell
  ];

  fontsConf = pkgs.writeText "fonts.conf" ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <include>${
        pkgs.makeFontsConf {
          fontDirectories = with pkgs; [
            jetbrains-mono
            nerd-fonts.symbols-only
            liberation_ttf
          ];
        }
      }</include>
      <include>${omarchy}/default/fontconfig/conf.avail/50-omarchy.conf</include>
      <alias binding="same">
        <family>JetBrainsMono Nerd Font</family>
        <prefer>
          <family>JetBrains Mono</family>
          <family>Symbols Nerd Font</family>
        </prefer>
      </alias>
    </fontconfig>
  '';

  session = pkgs.writeShellScript "omarchy-session" ''
    export OMARCHY_PATH=${omarchy}
    export OMARCHY_MODE=${mode}
    export OMARCHY_SCALE=${scale}
    export PATH=${omarchy}/bin:${uwsmApp}/bin:${lib.makeBinPath tools}:$PATH
    export XDG_DATA_DIRS=${omarchy}/default:${pkgs.foot}/share:''${XDG_DATA_DIRS:-/usr/share}
    export FONTCONFIG_FILE=${fontsConf}
    export XDG_CURRENT_DESKTOP=Hyprland
    export ENABLE_GAMESCOPE_WSI=0
    export LIBSEAT_BACKEND=seatd
    export LD_LIBRARY_PATH=${aquamarine}/lib
    unset DISPLAY
    [ -e "$HOME/.local/state/omarchy/current/theme" ] || OMARCHY_THEME_HEADLESS=1 omarchy-theme-set "Tokyo Night"
    exec ${pkgs.hyprland}/bin/Hyprland -c ${./omarchy/hyprland.lua}
  '';

  overlay = lib.concatStringsSep " " [
    "gamescope"
    "--backend openvr"
    "--expose-wayland"
    "-W ${toString width}"
    "-H ${toString height}"
    "--vr-overlay-key valve.omarchy.desktop"
    "--vr-overlay-explicit-name Omarchy"
    "--vr-overlay-icon ${omarchy}/icon.png"
    "--vr-overlay-physical-width ${overlayMetres}"
    "--vr-overlay-show-immediately"
    "--vr-overlay-enable-control-bar"
    "--vr-overlay-enable-control-bar-keyboard"
    "--vr-overlay-enable-control-bar-close"
    "--vr-overlay-enable-click-stabilization"
    "-- ${session}"
  ];
in
{
  system.build.omarchySession = session;

  systemd.user.services.omarchy = {
    description = "Omarchy desktop overlay";
    bindsTo = [ "steamvr.service" ];
    after = [ "steamvr.service" ];
    environment = frameSession.valveMesaEnv;
    serviceConfig = {
      Slice = "session.slice";
      EnvironmentFile = frameSession.mesavars;
      ExecStart = frameSession.inFhs overlay;
      ExecStopPost = "${pkgs.runtimeShell} -c 'cd %t && rm -rf hypr quickshell omarchy-*'";
      TimeoutStopSec = 10;
    };
  };
}
