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
      devShell.x86_64-linux = pkgs.mkShell {
        nativeBuildInputs = [
          zig-overlay.packages."x86_64-linux"."0.14.1"
          pkgs.pkg-config
          pkgs.cudaPackages.cudatoolkit
        ];
        shellHook = ''
        export TERM=xterm
        export EDITOR="emacs -nw"
        '';
      };
    };
}
