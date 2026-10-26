{ pkgs, frameSession, ... }:
let
  version = "3.2+git4403691c";

  powerbuttond = pkgs.stdenv.mkDerivation {
    pname = "steamos-powerbuttond";
    inherit version;
    src =
      (pkgs.callPackage ./valve.nix { }).bundleSource "steamos-powerbuttond-${version}-5.src.tar.gz"
        "sha256-jCRcGsO35nXakC5qPv0vQ8XX7i7H8idAngP7xqLrD8Y="
        "steamos-powerbuttond"
        "4403691ccffdbb85a9a0de6d9348b3d777d078d7";

    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = with pkgs; [
      libevdev
      systemdLibs
    ];

    makeFlags = [ "steamos-powerbuttond" ];

    installPhase = ''
      install -Dm755 -t $out/libexec steamos-powerbuttond
      install -Dm644 steamos-power-button.rules $out/lib/udev/rules.d/70-steamos-power-button.rules
      install -Dm644 steamos-power-button.hwdb $out/lib/udev/hwdb.d/70-steamos-power-button.hwdb
      install -Dm644 LICENSE $out/share/licenses/steamos-powerbuttond/LICENSE
    '';
  };
in
{
  services.udev.packages = [ powerbuttond ];

  services.logind.settings.Login.HandlePowerKey = "ignore";

  systemd.user.services.steamos-powerbuttond = {
    description = "Power Button daemon for SteamOS";
    wantedBy = [ "steamvr.service" ];
    after = [ "steamvr.service" ];
    requisite = [ "steamvr.service" ];
    serviceConfig = {
      ExecStart = frameSession.inFhs "${powerbuttond}/libexec/steamos-powerbuttond";
      Restart = "on-failure";
      Slice = "session.slice";
    };
  };
}
