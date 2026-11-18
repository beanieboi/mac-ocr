{
  description = "mac-ocr dev tooling";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      # periphery is only packaged for aarch64-darwin.
      system = "aarch64-darwin";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      # `nix run .#periphery -- scan`
      apps.${system}.periphery = {
        type = "app";
        program = "${pkgs.periphery}/bin/periphery";
      };

      # NoCC so the shell doesn't set SDKROOT/DEVELOPER_DIR and swift keeps using Xcode's toolchain.
      devShells.${system}.default = pkgs.mkShellNoCC {
        packages = [ pkgs.periphery ];
      };
    };
}
