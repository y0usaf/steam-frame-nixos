{
  lib,
  stdenv,
  fetchFromGitHub,
  meson,
  ninja,
  pkg-config,
  bison,
  flex,
  glslang,
  python3Packages,
  wayland-scanner,
  libdrm,
  dbus,
  wayland,
  wayland-protocols,
  libglvnd,
  libx11,
  libxcb,
  libxcb-keysyms,
  libxext,
  libxfixes,
  libxrandr,
  libxshmfence,
  libxxf86vm,
  xorgproto,
  expat,
  elfutils,
  zstd,
  zlib,
  udev,
  libdisplay-info,
  valgrind-light,
  lua5_4,
  libconfig,
  libarchive,
  libxml2,
  ncurses,
  lm_sensors,
  spirvTools,
  vulkanLoader,
}:
stdenv.mkDerivation {
  pname = "deckard-mesa";
  version = "26.3.0-devel+gite07916b4";

  src = fetchFromGitHub {
    owner = "evlaV";
    repo = "deckard-mesa";
    rev = "e07916b45ff2681b29c9af125203ea82a923d58b";
    hash = "sha256-GBQTV3mV/BxviMicVbLsMt+SM4cp5GEe3BQHUXD8xFU=";
  };

  postPatch = "patchShebangs .";

  strictDeps = true;
  separateDebugInfo = true;
  mesonBuildType = "release";

  mesonFlags = [
    "--sysconfdir=/etc"
    "-Db_ndebug=true"
    "-Dgallium-drivers=zink"
    "-Dvulkan-drivers=freedreno"
    "-Dvulkan-layers=vram-report-limit"
    "-Dgbm=enabled"
    "-Dglvnd=enabled"
    "-Dglx=auto"
    "-Dglx-direct=true"
    "-Dplatforms=x11,wayland"
    "-Dtools=freedreno,drm-shim"
    "-Dgpuvis=true"
    "-Dperfetto=false"
    "-Dvalgrind=enabled"
    "-Dllvm=disabled"
    "-Dlibunwind=disabled"
    "-Dmicrosoft-clc=disabled"
    "-Dandroid-libbacktrace=disabled"
    "-Dandroid-libperfetto=disabled"
    "-Dgallium-va=disabled"
    "-Dgallium-mediafoundation=disabled"
    "-Dtu-build-id="
    "-Dc_args=-march=armv8.2-a"
    "-Dcpp_args=-march=armv8.2-a"
  ];

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    bison
    flex
    (lib.getBin glslang)
    wayland-scanner
    python3Packages.python
    python3Packages.mako
    python3Packages.packaging
    python3Packages.pyyaml
    python3Packages.ply
    python3Packages.pycparser
  ];

  buildInputs = [
    libdrm
    dbus
    wayland
    wayland-protocols
    libglvnd
    libx11
    libxcb
    libxcb-keysyms
    libxext
    libxfixes
    libxrandr
    libxshmfence
    libxxf86vm
    xorgproto
    expat
    elfutils
    zstd
    zlib
    udev
    libdisplay-info
    valgrind-light
    lua5_4
    libconfig
    libarchive
    libxml2
    ncurses
    lm_sensors
    spirvTools
    python3Packages.python
  ];

  postFixup = ''
    for js in $out/share/glvnd/egl_vendor.d/*.json; do
      substituteInPlace "$js" --replace-fail '"libEGL_' '"'"$out/lib/libEGL_"
    done
    for js in $out/share/vulkan/implicit_layer.d/*.json; do
      substituteInPlace "$js" --replace-quiet '"libVkLayer_' '"'"$out/lib/libVkLayer_"
    done
    patchelf --add-rpath ${vulkanLoader}/lib $out/lib/libgallium*.so
  '';
}
