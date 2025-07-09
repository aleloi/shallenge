{
  inputs = {
    nixpkgs.url  = "github:NixOS/nixpkgs/nixos-25.05";
    zig-overlay = {
      url = "github:mitchellh/zig-overlay";
    };
  };

  outputs = {self, zig-overlay, nixpkgs, ... }:
  let
    pkgs = import nixpkgs {
      overlays = [zig-overlay.overlays.default ];
      system = "x86_64-linux";
    };
  in
    {
      packages.${pkgs.system} = {
        default = self.packages.${pkgs.system}.shallenge;
        shallenge = pkgs.stdenv.mkDerivation {
          pname = "shallenge";
          version = "0.1.0";
          src = ./.;

          nativeBuildInputs = [
            pkgs.zig
            pkgs.pkg-config
            pkgs.cudaPackages.cudatoolkit
            pkgs.autoAddDriverRunpath
          ];

           buildPhase = "
          ZIG_GLOBAL_CACHE_DIR=/tmp/ zig build --verbose -Dgpu-runtime=cuda -Doptimize=ReleaseFast
          ";

          installPhase = "
          mkdir -p $out/bin
          cp zig-out/bin/shallenge $out/bin/
          echo
          echo installed in $out
          echo
          ";

          meta = with pkgs.lib; {
            description = "SHAllenge solver in Zig+nvptx, original by Snektron";
            license = licenses.mit;
            platforms = platforms.unix;
          };
        };
      };
      
      devShell.x86_64-linux = pkgs.mkShell {
        nativeBuildInputs = [
          zig-overlay.packages."x86_64-linux"."0.14.1"
          pkgs.pkg-config
          pkgs.cudaPackages.cudatoolkit
        ];
      };
    };
}
