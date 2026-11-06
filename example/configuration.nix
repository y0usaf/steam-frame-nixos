{ pkgs, ... }:
{
  system.stateVersion = "26.05";

  frame = {
    authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIReplaceWithYourOwnPublicKey you@pc" ];
    wivrn.enable = true;
    session.fhsPackages = [ pkgs.vlc ];
  };
}
