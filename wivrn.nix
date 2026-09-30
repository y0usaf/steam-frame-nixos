{
  lib,
  pkgs,
  frameSession,
  ...
}:
let
  inherit (pkgs.wivrn) src version;

  archives = {
    simdjson = {
      url = "https://github.com/simdjson/simdjson/archive/refs/tags/v4.2.2.tar.gz";
      hash = "sha256-PvriLLQfgymf4LLooYevVD092pOru5EFhviX32cPnqo=";
    };
    spdlog = {
      url = "https://github.com/gabime/spdlog/archive/refs/tags/v1.16.0.tar.gz";
      hash = "sha256-h0F1PkiKeN0NACTJgOH7W1yFiIRH4wnZy52Um9tSqj4=";
    };
    glm = {
      url = "https://github.com/g-truc/glm/releases/download/1.0.2/glm-1.0.2.zip";
      hash = "sha256-d//wdcWrDK8Hb63kFVjFRY2aJCq6KyB2u3IAi9tRo14=";
    };
    fastgltf = {
      url = "https://github.com/spnda/fastgltf/archive/refs/tags/v0.9.0.tar.gz";
      hash = "sha256-C7Vk4SexTCLwYttQ+JOB3S4KINuvSYfKE4pK6HKHEvk=";
    };
    imgui = {
      url = "https://github.com/ocornut/imgui/archive/refs/tags/v1.92.9.tar.gz";
      hash = "sha256-r5ftZJGCw5MUMgUUpnK4IAirRiuSk/4j03swv6XQVRk=";
      postPatch = ''
        for p in ${src}/patches/imgui/*; do
          patch -p1 --forward < "$p"
        done
      '';
    };
    stb = {
      url = "https://github.com/nothings/stb/archive/013ac3beddff3dbffafd5177e7972067cd2b5083.zip";
      hash = "sha256-t/R2kCu+8bMPjswtnZXEWcMjAsi1WdCbWJtZVUY7evg=";
    };
    implot = {
      url = "https://github.com/epezent/implot/releases/download/v1.0/implot-v1.0.tar.gz";
      hash = "sha256-IMoU1aRvNqZQdGCWx066i+qZyUMs08h3NDuWsXpq5WY=";
    };
    uni-algo = {
      url = "https://github.com/uni-algo/uni-algo/archive/v1.2.0.tar.gz";
      hash = "sha256-8qFTnNhjW8YIjQUUSnPs/ntNdO4DYfq+1vh/nxnnTKk=";
    };
    entt = {
      url = "https://github.com/skypjack/entt/archive/refs/tags/v4.0.0.tar.gz";
      hash = "sha256-MqL/LHLLBH39VzBgBu8jiCC3DafGzk5+ilB6xjNlIS4=";
    };
    spirv-reflect = {
      url = "https://github.com/KhronosGroup/SPIRV-Reflect/archive/refs/tags/vulkan-sdk-1.4.328.1.tar.gz";
      hash = "sha256-d/S1tWMNlg18F+Od3Vvy591i5tjaJCWe0UyltZeD6jU=";
    };
  };

  deps = lib.mapAttrs (
    name:
    {
      url,
      hash,
      postPatch ? "",
    }:
    pkgs.srcOnly {
      inherit name postPatch;
      stdenv = pkgs.stdenvNoCC;
      src = pkgs.fetchurl { inherit url hash; };
      nativeBuildInputs = [ pkgs.unzip ];
    }
  ) archives;

  webxrProfiles = pkgs.fetchurl {
    url = "https://registry.npmjs.com/@webxr-input-profiles/assets/-/assets-1.0.20.tgz";
    hash = "sha256-MN8qImgiD8DQ4DS+0VUKq916JQBXPFIW9k/HDVnD2R4=";
  };

  wivrn = pkgs.stdenv.mkDerivation {
    pname = "wivrn-client";
    inherit version src;
    strictDeps = true;

    nativeBuildInputs = with pkgs; [
      cmake
      pkg-config
      gettext
      librsvg
      glslang
      spirv-tools
      hexdump
      python3
      ktx-tools
    ];

    buildInputs = with pkgs; [
      boost
      ffmpeg-headless
      fontconfig
      freetype
      harfbuzz
      openssl
      curl
      openxr-loader
      pipewire
      vulkan-headers
      vulkan-loader
      ktx-tools
    ];

    cmakeFlags = [
      (lib.cmakeBool "WIVRN_BUILD_CLIENT" true)
      (lib.cmakeBool "WIVRN_BUILD_SERVER" false)
      (lib.cmakeBool "WIVRN_BUILD_WIVRNCTL" false)
      (lib.cmakeBool "FETCHCONTENT_FULLY_DISCONNECTED" true)
      (lib.cmakeFeature "GIT_TAG" src.rev)
    ]
    ++ lib.mapAttrsToList (
      name: dep: lib.cmakeFeature "FETCHCONTENT_SOURCE_DIR_${lib.toUpper name}" "${dep}"
    ) deps;

    preConfigure = ''
      cp ${webxrProfiles} "@webxr-input-profiles-1.0.20.tgz"
    '';

    postFixup = ''
      patchelf --set-rpath "$(patchelf --print-rpath $out/bin/wivrn | tr : '\n' | grep -vF ${pkgs.vulkan-loader}/ | paste -sd:)" $out/bin/wivrn
    '';
  };

  desktopItem = pkgs.makeDesktopItem {
    name = "wivrn";
    desktopName = "WiVRn";
    exec = "wivrn";
    icon = "${src}/images/wivrn.svg";
  };
in
{
  system.build.wivrnClient = wivrn;

  frame.session.fhsPackages = [
    wivrn
    desktopItem
  ];

  systemd.user.services.wivrn-client = {
    description = "WiVRn client";
    bindsTo = [ "steamvr.service" ];
    after = [ "steamvr.service" ];
    environment = frameSession.valveMesaEnv;
    serviceConfig = {
      Slice = "session.slice";
      EnvironmentFile = frameSession.mesavars;
      ExecStart = frameSession.inFhs "${wivrn}/bin/wivrn";
      TimeoutStopSec = 10;
    };
  };
}
