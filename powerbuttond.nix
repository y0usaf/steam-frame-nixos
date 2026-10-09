{ pkgs, ... }:
let
  version = "4.2";

  powerbuttond = pkgs.stdenv.mkDerivation {
    pname = "steamos-powerbuttond";
    inherit version;
    src = pkgs.fetchFromGitLab {
      domain = "gitlab.steamos.cloud";
      owner = "holo";
      repo = "powerbuttond";
      tag = "v${version}";
      hash = "sha256-ahdWiCFid+wk2db0TvOEKfUxkJ+Yo5oBbrZ0ZqkUalE=";
    };

    postPatch = ''
      substituteInPlace powerbuttond.c \
        --replace-fail /.steam/root/ubuntu12_32/steam /.steam/steam/steamrtarm64/steam
    '';

    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = with pkgs; [
      libevdev
      systemdLibs
    ];

    makeFlags = [ "steamos-powerbuttond" ];

    installPhase = ''
      install -Dm755 -t $out/libexec steamos-powerbuttond
      install -Dm644 -t $out/lib/udev/rules.d steamos-power-button.rules
      install -Dm644 ${./powerbuttond/70-steamos-power-button.hwdb} $out/lib/udev/hwdb.d/70-steamos-power-button.hwdb
      install -Dm644 LICENSE $out/share/licenses/steamos-powerbuttond/LICENSE
    '';
  };
in
{
  services.udev.packages = [ powerbuttond ];

  systemd.user.services.steamos-powerbuttond = {
    description = "Power Button daemon for SteamOS";
    wantedBy = [ "steamvr.service" ];
    requisite = [ "steamvr.service" ];
    serviceConfig = {
      ExecStart = "${powerbuttond}/libexec/steamos-powerbuttond";
      Restart = "on-failure";
      Slice = "session.slice";
    };
  };
}
