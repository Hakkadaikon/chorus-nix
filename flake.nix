{
  description = "Nix build for Chorus Nostr relay — cross-compile to x86_64-linux-musl static binary";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    chorus-src = {
      url = "github:mikedilger/chorus";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, chorus-src }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "x86_64-darwin" "aarch64-darwin" "aarch64-linux" ];
    in
    {
      packages = forAllSystems (system:
        let
          # Native pkgs (for building on this system, targeting x86_64-linux-musl)
          pkgs = import nixpkgs { inherit system; };

          # Cross-compilation pkgs for static musl binary
          crossPkgs = import nixpkgs {
            localSystem = system;
            crossSystem = {
              config = "x86_64-unknown-linux-musl";
              isStatic = true;
            };
          };

          chorus = crossPkgs.rustPlatform.buildRustPackage {
            pname = "chorus";
            version = chorus-src.shortRev or "dev";
            src = chorus-src;
            cargoLock = {
              lockFile = "${chorus-src}/Cargo.lock";
              outputHashes = {
                "pocket-db-0.1.0" = "sha256-7NYYnQ198Emdmefs2hkHa/4WqGC/nY6wKC5Td5iIKpE=";
              };
            };
          };
        in
        {
          default = chorus;
          chorus = chorus;
        }
      );
    };
}
