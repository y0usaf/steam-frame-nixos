{
  inputs.nixpkgs.url = "https://releases.nixos.org/nixpkgs/nixpkgs-26.11pre1080803.419fe0f449b3/nixexprs.tar.zst";

  outputs =
    { nixpkgs, ... }:
    let
      rootUuid = "47e26947-1018-45a7-95ae-4516d0bcf929";
      frame = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit rootUuid; };
        modules = [
          ./frame.nix
          ./hardware.nix
          ./session.nix
          ./audio.nix
        ];
      };
    in
    {
      nixosConfigurations.frame = frame;
      packages.x86_64-linux.image = nixpkgs.legacyPackages.x86_64-linux.callPackage ./image.nix {
        inherit rootUuid;
        nixos = frame;
      };
    };
}
