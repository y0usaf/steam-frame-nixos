{ lib, pkgs, ... }:
{
  nixpkgs.config.allowUnfreePredicate = pkg: lib.getName pkg == "stremio-linux-shell";

  frame.session.fhsPackages = [ pkgs.stremio-linux-shell ];
}
