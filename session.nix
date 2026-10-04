{
  config,
  lib,
  pkgs,
  ...
}:
let
  valve = pkgs.callPackage ./valve.nix { };
  mesavars = "${valve.steamvrSession}/share/deckard/mesavars.sh";
  valveMesaEnv = {
    VK_DRIVER_FILES = "/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json";
    __EGL_VENDOR_LIBRARY_FILENAMES = "/usr/share/glvnd/egl_vendor.d/50_mesa.json";
    VK_IMPLICIT_LAYER_PATH = "/usr/share/vulkan/implicit_layer.d";
    VK_LAYER_PATH = "/usr/share/vulkan/explicit_layer.d";
    GBM_BACKENDS_PATH = "/usr/lib/gbm";
  };

  vulkanHeaders = pkgs.vulkan-headers.overrideAttrs {
    version = "1.4.309.0";
    src = pkgs.fetchFromGitHub {
      owner = "KhronosGroup";
      repo = "Vulkan-Headers";
      rev = "vulkan-sdk-1.4.309.0";
      hash = "sha256-LfJ7um+rzc4HdkJerHWkuPWeEc7ZFSBafbP+svAjklk=";
    };
  };
  vulkanLoader = (pkgs.vulkan-loader.override { vulkan-headers = vulkanHeaders; }).overrideAttrs (o: {
    version = "1.4.309.0";
    src = pkgs.fetchFromGitHub {
      owner = "KhronosGroup";
      repo = "Vulkan-Loader";
      rev = "vulkan-sdk-1.4.309.0";
      hash = "sha256-LZRACulOrnlL9do216zTeCTXGfy2pLxqs+f9phDD3Pg=";
    };
    cmakeFlags = map (
      f: if lib.hasPrefix "-DSYSCONFDIR=" f then "-DSYSCONFDIR=/etc" else f
    ) o.cmakeFlags;
  });

  fhs = pkgs.buildFHSEnv {
    name = "frame-fhs";
    targetPkgs =
      p:
      [
        vulkanLoader
        valve.mesa
        valve.spirvTools
        valve.vulkanLayers
        valve.steamvr
        valve.steamClient
        valve.steamvrSession
        valve.gamescope
        valve.steamBootstrap
        valve.hwSupportTree
        valve.eeprom
        valve.fpga
      ]
      ++ config.frame.session.fhsPackages
      ++ (with p; [
        SDL2
        libuuid
        zlib
        libglvnd
        libpulseaudio
        libdrm
        systemdLibs
        wayland
        libxkbcommon
        pixman
        lcms2
        seatd
        libinput
        libcap
        pipewire
        libavif
        libdecor
        libei
        luajit
        lm_sensors
        lsof
        xwayland
        xorg.libX11
        xorg.libxcb
        xorg.libXdamage
        xorg.libXfixes
        xorg.libXcomposite
        xorg.libXrender
        xorg.libXext
        xorg.libXxf86vm
        xorg.libXres
        xorg.libXmu
        xorg.libXcursor
        xorg.libXi
        xorg.xhost
        xorg.xrdb
        xorg.xset
        (v4l-utils.override { withGUI = false; })
        mangohud
        xdg-utils
        firefox
        tbb
        curl
        wireplumber
        stdenv.cc.cc.lib
        alsa-lib
        libasyncns
        at-spi2-core
        ffmpeg_7.lib
        brotli.lib
        bzip2.out
        cairo
        cups.lib
        expat
        fontconfig
        freetype
        gtk3
        gtk2
        gdk-pixbuf
        glib
        glew
        harfbuzz
        ibus
        libjpeg_turbo
        mtdev
        networkmanager
        nspr
        nss
        openal
        pango
        libpng
        libsndfile
        sqlite
        libssh2
        openssl
        libva
        libvdpau
        xorg.libICE
        xorg.libSM
        xorg.libXtst
        xorg.libXinerama
        xorg.libXrandr
        xorg.xcbutilwm
        xorg.xcbutilimage
        xorg.xcbutilkeysyms
        xorg.xcbutilrenderutil
        libxshmfence
        libgpiod
        (libdisplay-info.overrideAttrs {
          version = "0.1.1";
          src = fetchurl {
            url = "https://gitlab.freedesktop.org/emersion/libdisplay-info/-/archive/0.1.1/libdisplay-info-0.1.1.tar.gz";
            hash = "sha256-pa7vV4F5FihlJikuyBalM4xNPACUzpHlhPyCtXBwpE8=";
          };
          patches = [ ];
        })
        bash
        coreutils
        findutils
        gnugrep
        gnused
        gawk
        util-linux
        procps
        which
        file
        zstd
        gnutar
        xz
        python3
        jq
        dbus
        systemd
      ]);
    extraBwrapArgs = [
      "--ro-bind ${valve.steamvr}/opt/steamvr /opt/steamvr"
      "--bind /tmp/.X11-unix /tmp/.X11-unix"
    ];
    extraBuildCommands = ''
      ln -sfn ${valve.hwSupportTree}/local $out/usr/local
      rm $out/usr/share/applications/org.freedesktop.IBus.Setup.desktop
    '';
    profile = "export PATH=/usr/local/bin:/usr/local/sbin:$PATH";
    unshareUser = false;
    unshareIpc = false;
    unsharePid = false;
    unshareUts = false;
    unshareCgroup = false;
    dieWithParent = false;
    runScript = "bash";
  };
  inFhs = cmd: "${fhs}/bin/frame-fhs -c '${cmd}'";

  installSteam = pkgs.writeShellScript "install-steam-client" ''
    set -eu
    d="$HOME/.local/share/Steam"
    if [ ! -e "$d/steamrtarm64/steam" ] && [ ! -e "$d/linuxarm64/steam" ]; then
      mkdir -p "$d"
      ${pkgs.gnutar}/bin/tar --use-compress-program=${pkgs.zstd}/bin/zstd -xf ${valve.steamClient}/lib/steam/steam.tar.zst -C "$d"
    fi
    install -m755 ${valve.steamClient}/share/deckard/RUNSTEAM.sh "$d/RUNSTEAM.sh"
  '';

  seedOpenvrPaths = pkgs.writeShellScript "seed-openvr-paths" ''
    set -eu
    f="$HOME/.config/openvr/openvrpaths.vrpath"
    [ -e "$f" ] || install -Dm644 ${valve.steamvr}/share/deckard/openvrpaths.vrpath "$f"
    chmod u+w "$f"
    v="$HOME/.config/openvr/config/steamvr.vrsettings"
    if [ -f "$v" ]; then
      ${pkgs.jq}/bin/jq '.steamvr.preferredRefreshRate //= 144' "$v" > "$v.tmp" && mv "$v.tmp" "$v"
    fi
  '';

  startSession = pkgs.writeShellScript "start-frame-session" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.systemd
        pkgs.dbus
        pkgs.util-linux
        pkgs.coreutils
        pkgs.gnugrep
      ]
    }:$PATH
    exec ${pkgs.bash}/bin/bash ${valve.steamvrSession}/bin/start-gamescope-session
  '';

  eepromOpen = pkgs.writeShellScript "eeprom-open-when-ro" ''
    if [ "$(${pkgs.coreutils}/bin/cat "/sys$1/force_ro")" = 1 ]; then
      ${pkgs.coreutils}/bin/chmod 666 "/sys$1/../eeprom"
    fi
  '';

  roySpidevBind = pkgs.writeShellScript "roy-spidev-bind" ''
    set -eu
    d=/sys/bus/spi/devices/spi0.1
    if [ -e $d/driver ] && [ "$(basename "$(readlink $d/driver)")" != spidev ]; then
      echo spi0.1 > $d/driver/unbind
    fi
    echo spidev > $d/driver_override
    if [ ! -e $d/driver ]; then
      echo spi0.1 > /sys/bus/spi/drivers/spidev/bind
    fi
  '';

  roySpidevUnbind = pkgs.writeShellScript "roy-spidev-unbind" ''
    set -eu
    if [ -e /sys/bus/spi/drivers/spidev/spi0.1 ]; then
      echo spi0.1 > /sys/bus/spi/drivers/spidev/unbind
    fi
    echo > /sys/bus/spi/devices/spi0.1/driver_override
  '';

  valveUdev = pkgs.runCommand "valve-udev-rules" { } ''
    mkdir -p $out/lib/udev/rules.d
    for r in 00-usb-permissions 99-backlight 99-cdsp-permissions 99-exp5-permissions 99-gpiod-permissions \
      99-gpu-permissions 99-hidraw-permissions 99-hwmon-max34417 99-leds 99-rgb-cam-permissions 99-spidev-permissions; do
      install -m644 ${valve.hwSupportTree}/lib/udev/rules.d/$r.rules $out/lib/udev/rules.d/
    done
    install -m644 ${valve.steamvr}/lib/udev/rules.d/99-steamvr.rules ${valve.steamClient}/lib/udev/rules.d/70-steam-input.rules $out/lib/udev/rules.d/
    echo 'SUBSYSTEM=="nvmem", ATTR{type}=="EEPROM", ATTR{force_ro}="1", RUN+="${eepromOpen} %p"' > $out/lib/udev/rules.d/99-eeprom-ro.rules
    substituteInPlace $out/lib/udev/rules.d/*.rules \
      --replace-quiet /bin/chgrp ${pkgs.coreutils}/bin/chgrp \
      --replace-quiet /bin/chmod ${pkgs.coreutils}/bin/chmod \
      --replace-quiet /bin/chown ${pkgs.coreutils}/bin/chown \
      --replace-quiet '/bin/sh ' '${pkgs.bash}/bin/sh '
  '';

  deviceGroups = [
    "leds"
    "cdsp"
    "spidev"
    "gpiod"
    "perf"
    "fpga"
  ];
in
{
  imports = [
    {
      options.frame.session.fhsPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = "Extra packages for the FHS environment Steam runs in. Their desktop entries appear in Steam's + menu.";
      };
    }
  ];

  _module.args.frameSession = { inherit inFhs valveMesaEnv mesavars; };

  users.groups = lib.genAttrs deviceGroups (_: { });
  fileSystems."/mnt/steamos-data" =
    if config.frame.storage.poolUuid == null then
      {
        device = "/dev/disk/by-uuid/4bac5c02-4a89-4377-8388-ce55ef171552";
        fsType = "ext4";
        neededForBoot = true;
        options = [ "noatime" ];
      }
    else
      {
        device = "/dev/disk/by-uuid/${config.frame.storage.poolUuid}";
        fsType = "btrfs";
        options = [
          "subvol=@steamos-data"
          "compress=zstd:3"
          "noatime"
        ];
      };

  fileSystems."/home/steamos" = lib.mkIf (config.frame.storage.poolUuid == null) {
    device = "/mnt/steamos-data/nixos-home/steamos";
    fsType = "none";
    neededForBoot = true;
    depends = [ "/mnt/steamos-data" ];
    options = [ "bind" ];
  };

  fileSystems."/home/steamos/.local/share/Steam/steamapps" =
    lib.mkIf (config.frame.storage.poolUuid != null)
      {
        device = "/games";
        fsType = "none";
        depends = [
          "/home"
          "/games"
        ];
        options = [ "bind" ];
      };

  users.users.steamos = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [
      "video"
      "render"
      "input"
      "audio"
      "tty"
      "networkmanager"
    ]
    ++ deviceGroups;
    openssh.authorizedKeys.keyFiles = [ ./authorized_keys ];
  };

  services.udev.packages = [ valveUdev ];

  fileSystems."/persist" = {
    device = "/dev/disk/by-partlabel/syspersist";
    fsType = "ext4";
    options = [
      "ro"
      "noload"
      "nofail"
    ];
  };

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
  security.rtkit.enable = true;
  systemd.services.rtkit-daemon.serviceConfig.ExecStart = [
    ""
    "${pkgs.rtkit}/libexec/rtkit-daemon --threads-per-user-max=200 --actions-per-burst-max=1000 --max-realtime-priority=80 --our-realtime-priority=81 --no-chroot"
  ];
  security.pam.loginLimits = [
    {
      domain = "*";
      type = "hard";
      item = "nice";
      value = "-8";
    }
  ];
  services.upower.enable = true;

  systemd.services.frame-session = {
    description = "Steam Frame VR session on tty1";
    after = [
      "systemd-user-sessions.service"
      "systemd-logind.service"
    ];
    wants = [
      "dbus.socket"
      "systemd-logind.service"
    ];
    wantedBy = [ "graphical.target" ];
    restartIfChanged = false;
    unitConfig.ConditionPathExists = "/dev/tty1";
    environment.XDG_SESSION_TYPE = "wayland";
    serviceConfig = {
      ExecStart = "${startSession}";
      User = "steamos";
      PAMName = "frame-session";
      TTYPath = "/dev/tty1";
      TTYReset = "yes";
      TTYVHangup = "yes";
      TTYVTDisallocate = "yes";
      StandardInput = "tty-fail";
      StandardOutput = "journal";
      StandardError = "journal";
      UtmpIdentifier = "%n";
      UtmpMode = "user";
      IgnoreSIGPIPE = "no";
      Restart = "always";
      RestartSec = "5s";
    };
  };
  security.pam.services.frame-session.text = ''
    auth    required pam_unix.so nullok
    account required pam_unix.so
    session required pam_unix.so
    session required pam_env.so conffile=/etc/pam/environment readenv=0
    session required ${pkgs.systemd}/lib/security/pam_systemd.so
  '';
  systemd.defaultUnit = "graphical.target";
  systemd.services."autovt@tty1".enable = false;

  systemd.services.frame-roy-spidev = {
    description = "Controller radio on spi0.1 via spidev";
    wantedBy = [ "multi-user.target" ];
    before = [ "frame-session.service" ];
    unitConfig.ConditionPathExists = "/sys/bus/spi/devices/spi0.1";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${roySpidevBind}";
      ExecStop = "${roySpidevUnbind}";
    };
  };

  systemd.tmpfiles.rules = [
    "f /run/deckardcharger/vr_state 0644 steamos root - Not running"
    "d /tmp/.X11-unix 1777 steamos root 10d"
  ]
  ++ lib.optional (config.frame.storage.poolUuid != null) "d /games 0755 steamos users -";

  boot.extraModulePackages = [ valve.v4l2loopback ];
  boot.kernelModules = [ "v4l2loopback" ];
  boot.extraModprobeConfig = ''
    options v4l2loopback video_nr=99 card_label="SteamVR" exclusive_caps=1
  '';

  systemd.network.links."80-wlan" = {
    matchConfig.Type = "wlan";
    linkConfig.NamePolicy = "keep kernel";
  };

  systemd.services.set-wifi-mac-address = {
    description = "Set Wi-Fi MAC address from the EEPROM";
    after = [ "sys-subsystem-net-devices-wlan0.device" ];
    requires = [ "sys-subsystem-net-devices-wlan0.device" ];
    before = [ "NetworkManager.service" ];
    wantedBy = [ "multi-user.target" ];
    restartIfChanged = false;
    path = [ pkgs.iproute2 ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "30s";
      ExecStart = inFhs "/usr/lib/deckard-hw-support/set_mac_addresses.sh --wifi";
    };
  };

  systemd.services.deckard-fpga = {
    description = "FPGA configuration service";
    after = [ "local-fs.target" ];
    wantedBy = [ "multi-user.target" ];
    restartIfChanged = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = inFhs "/usr/lib/deckard-fpga/fpga_power_en.sh";
      ExecStart = inFhs "/usr/lib/deckard-fpga/fpga_load.sh";
    };
  };

  systemd.services.dsp_service = {
    description = "SteamVR tracking DSP service";
    wantedBy = [ "multi-user.target" ];
    restartIfChanged = false;
    serviceConfig = {
      Type = "exec";
      ExecStart = inFhs "/usr/share/deckard/select_steamvr.sh drivers/cv/bin/linuxarm64/dsp_service";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  systemd.user.targets.gamescope-session = {
    description = "Gamescope VR Session";
    requires = [
      "graphical-session.target"
      "gamescope-session.service"
    ];
    bindsTo = [
      "graphical-session.target"
      "gamescope-session.service"
    ];
    after = [ "graphical-session.target" ];
    wants = [
      "steamvr.service"
      "steam.service"
    ];
    unitConfig.PropagatesStopTo = "graphical-session.target";
  };

  systemd.user.services.gamescope-session = {
    description = "Gamescope VR Session";
    before = [ "graphical-session.target" ];
    partOf = [
      "graphical-session.target"
      "steamvr.service"
    ];
    wants = [ "graphical-session-pre.target" ];
    after = [ "graphical-session-pre.target" ];
    restartIfChanged = false;
    unitConfig = {
      RefuseManualStart = true;
      StartLimitIntervalSec = 0;
    };
    environment = valveMesaEnv // {
      SRT_LOG_TO_JOURNAL = "1";
    };
    serviceConfig = {
      Slice = "session.slice";
      TimeoutStartSec = 30;
      TimeoutStopSec = 10;
      ExecStart = inFhs "/usr/lib/steamos/gamescope-session";
      Type = "notify";
      NotifyAccess = "all";
      EnvironmentFile = mesavars;
      KillMode = "mixed";
    };
  };

  systemd.user.services.steamvr = {
    description = "SteamVR Launcher";
    partOf = [ "graphical-session.target" ];
    after = [ "gamescope-session.service" ];
    requires = [ "gamescope-session.service" ];
    restartIfChanged = false;
    unitConfig.StartLimitIntervalSec = 0;
    environment = valveMesaEnv;
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "5s";
      TimeoutStopSec = 20;
      Slice = "session.slice";
      EnvironmentFile = mesavars;
      ExecStartPre = [
        "${seedOpenvrPaths}"
        (inFhs "/usr/share/deckard/steamvr_first_init.sh")
        "-${pkgs.coreutils}/bin/rm -rf %h/.cache/SteamVR"
        ("-" + inFhs "steamvr apply-setpath")
        ("-" + inFhs "steamvr merge-down-overlays")
        (inFhs "/usr/share/deckard/select_steamvr.sh bin/linuxarm64/vrstartup")
      ];
      ExecStart = inFhs "/usr/share/deckard/select_steamvr.sh bin/linuxarm64/vrcmd --background --waitforquit";
      ExecStartPost = "-${pkgs.bash}/bin/sh -c 'echo Running > /run/deckardcharger/vr_state'";
      ExecStop = inFhs "/usr/share/deckard/select_steamvr.sh bin/linuxarm64/vrstartup -shutdown";
      ExecStopPost = [
        (inFhs "/usr/bin/displays_turn_off_drm_master")
        "-${pkgs.bash}/bin/sh -c 'echo \"Not running\" > /run/deckardcharger/vr_state'"
      ];
    };
  };

  systemd.user.services.steam = {
    description = "Steam Launcher";
    partOf = [ "graphical-session.target" ];
    wants = [ "steamvr.service" ];
    after = [ "steamvr.service" ];
    restartIfChanged = false;
    environment = valveMesaEnv // {
      STEAM_LAUNCH_WRAPPER_AFFINITY_LIST = "0xf8";
      STEAM_DESKTOP_APP_AFFINITY_LIST = "0xf8";
      STEAM_LAUNCH_WRAPPER_SCOPE = "true";
      STEAM_CEF_USE_AUTOMATIC_PROXY = "0";
      STEAM_DEBUGCEF_FAKEUI = "1";
      STEAM_ALLOW_DRIVE_ADOPT = "1";
      STEAM_ALLOW_DRIVE_UNMOUNT = "1";
      STEAM_COMPAT_TOOL_MAPPINGS = "546560 100 steamrt4-any";
      STEAM_LAUNCH_WRAPPER_AUDIO_NAMESPACE = "0";
      STEAM_EXTRA_ARGS = "";
      LD_PRELOAD = "/usr/lib/libpng16.so.16";
    };
    serviceConfig = {
      Slice = "session.slice";
      Type = "simple";
      Restart = "always";
      TimeoutStopSec = 20;
      SuccessExitStatus = "0 42";
      EnvironmentFile = mesavars;
      ExecStartPre = [
        "${pkgs.coreutils}/bin/mkdir -p %t/steam/env"
        "${pkgs.coreutils}/bin/install -m644 ${valve.steamClient}/share/deckard/steam_launch_wrapper_env_defaults.txt %t/steam/env/gfx.txt"
        "${installSteam}"
      ];
      ExecStart = inFhs "/usr/share/deckard/select_steam.sh RUNSTEAM.sh";
    };
  };
}
