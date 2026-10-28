{
  config,
  lib,
  pkgs,
  frameSession,
  ...
}:
let
  noto = "${pkgs.noto-fonts-cjk-sans-static}/share/fonts/opentype/noto-cjk";

  framecolor = pkgs.stdenv.mkDerivation {
    pname = "framecolor-sharp";
    version = "0-unstable-2026-10-28";

    src = pkgs.fetchFromGitHub {
      owner = "guix8";
      repo = "framecolor-sharp";
      rev = "bb6ac2e6c82eb108dbf79189db05add391d3d38e";
      hash = "sha256-f6A5heyOfp9/zNrjgfpKpKRb6jJxTlZd+3cpNWx3s6g=";
    };

    nativeBuildInputs = with pkgs; [
      cmake
      meson
      ninja
      pkg-config
      glslang
      python3
      makeWrapper
    ];

    buildInputs = with pkgs; [
      cairo
      freetype
      vulkan-headers
      vulkan-loader
      openvr
    ];

    postPatch = ''
      substituteInPlace src/framecolor_main.cpp \
        --replace-fail /usr/share/fonts/noto-cjk "$out/share/framecolor/fonts"

      substituteInPlace contrib/framecolorctl \
        --replace-fail '$HOME/.local/bin/framecolor' "$out/bin/framecolor" \
        --replace-fail '$fc_data_dir/lib/libvkbasalt.so' "$out/lib/libvkbasalt.so" \
        --replace-fail 'if [ -f "$fc_disabled" ]; then mv "$fc_disabled" "$fc_manifest"; fi' \
          "install -Dm644 $out/share/framecolor/layer/vkBasalt.json \"\$fc_manifest\" && rm -f \"\$fc_disabled\"" \
        --replace-fail 'if [ ! -f "$fc_manifest" ] && [ ! -f "$fc_disabled" ]; then' \
          "if [ ! -f $out/share/framecolor/layer/vkBasalt.json ]; then"

      substituteInPlace contrib/framecolor-guard \
        --replace-fail 'if [ -f "$fc_manifest" ]; then' \
          "if [ -f \"\$fc_manifest\" ]; then install -m644 $out/share/framecolor/layer/vkBasalt.json \"\$fc_manifest\" || true"
    '';

    configurePhase = ''
      runHook preConfigure
      cmake -G Ninja -S . -B build-overlay -DCMAKE_BUILD_TYPE=Release -DOPENVR_LIB_DIR=${pkgs.openvr}/lib
      meson setup --buildtype=release build-layer third_party/vkbasalt
      runHook postConfigure
    '';

    buildPhase = ''
      runHook preBuild
      ninja -C build-overlay -j$NIX_BUILD_CORES
      ninja -C build-layer -j$NIX_BUILD_CORES
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm755 build-overlay/framecolor $out/bin/framecolor
      install -Dm755 build-layer/src/libvkbasalt.so $out/lib/libvkbasalt.so
      install -Dm755 contrib/framecolorctl $out/bin/framecolorctl
      install -Dm755 contrib/framecolor-guard $out/libexec/framecolor-guard

      share=$out/share/framecolor
      install -Dm444 -t $share/fonts ${noto}/NotoSansCJK-Regular.ttc ${noto}/NotoSansCJK-Bold.ttc
      mkdir -p $share/layer
      printf '0 0 0 1 1 1 1 1 1 1 1 1 0 0 0\n' > neutral.txt
      python3 tools/generate_vulkan_lut.py neutral.txt $share/framecolor.cube
      echo "lutFile = $share/framecolor.cube" > $share/vkBasalt.conf
      cat > $share/layer/vkBasalt.json <<EOF
      {
        "file_format_version": "1.0.0",
        "layer": {
          "name": "VK_LAYER_VKBASALT_post_processing",
          "type": "GLOBAL",
          "library_path": "$out/lib/libvkbasalt.so",
          "api_version": "1.3.223",
          "implementation_version": "1",
          "description": "FrameColor Vulkan correction for Steam Frame",
          "functions": {
            "vkGetInstanceProcAddr": "vkBasalt_GetInstanceProcAddr",
            "vkGetDeviceProcAddr": "vkBasalt_GetDeviceProcAddr"
          },
          "enable_environment": { "ENABLE_VKBASALT": "1" },
          "disable_environment": { "DISABLE_VKBASALT": "1" }
        }
      }
      EOF
      runHook postInstall
    '';

    postFixup = ''
      wrapProgram $out/bin/framecolorctl --prefix PATH : ${lib.makeBinPath [ pkgs.coreutils ]}
      wrapProgram $out/libexec/framecolor-guard --prefix PATH : ${lib.makeBinPath [ pkgs.coreutils ]}
    '';

    meta = {
      description = "Colour LUT and CAS sharpening Vulkan layer for SteamVR's vrcompositor on the Steam Frame, with a dashboard overlay";
      homepage = "https://github.com/guix8/framecolor-sharp";
      license = with lib.licenses; [
        mit
        zlib
        bsd3
      ];
      platforms = [ "aarch64-linux" ];
      mainProgram = "framecolor";
    };
  };

  framecolorctl = pkgs.writeShellScriptBin "framecolorctl" ''
    exec ${frameSession.inFhs ''exec ${framecolor}/bin/framecolorctl "$@"''} framecolorctl "$@"
  '';

  guard = "${framecolor}/libexec/framecolor-guard";

  mesaEnv = lib.concatStrings (
    lib.mapAttrsToList (n: v: "Environment=\"${n}=${v}\"\n") frameSession.valveMesaEnv
  );
in
{
  options.frame.framecolor.enable = lib.mkEnableOption "framecolor-sharp, a colour and sharpening layer for SteamVR's compositor with a dashboard to tune it";

  config = lib.mkIf config.frame.framecolor.enable {
    system.build.framecolor = framecolor;

    environment.systemPackages = [ framecolorctl ];

    systemd.user.services.steamvr = {
      environment = {
        VK_IMPLICIT_LAYER_PATH = lib.mkForce "${frameSession.valveMesaEnv.VK_IMPLICIT_LAYER_PATH}:%h/.local/share/framecolor/layer";
        ENABLE_VKBASALT = "1";
        VKBASALT_CONFIG_FILE = "${framecolor}/share/framecolor/vkBasalt.conf";
        VKBASALT_LOG_LEVEL = "warn";
      };
      serviceConfig = {
        ExecCondition = "${guard} start";
        ExecStopPost = [ "-${guard} stop" ];
      };
    };

    systemd.user.units."framecolor.service".text = ''
      [Unit]
      Description=FrameColor dashboard
      After=steamvr.service
      PartOf=steamvr.service

      [Service]
      Slice=session.slice
      Environment=DISPLAY=:0
      ${mesaEnv}EnvironmentFile=${frameSession.mesavars}
      ExecStart=${frameSession.inFhs "${framecolor}/bin/framecolor"}
      Restart=always
      RestartSec=3

      [Install]
      WantedBy=steamvr.service
    '';
  };
}
