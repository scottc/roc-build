{
  description = "godot-roc development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    roc-nightly.url = "github:roc-lang/roc-overlay";
  };

  outputs = { self, nixpkgs, flake-utils, roc-nightly, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        rocNightlyPkg = roc-nightly.packages.${system}.nightly-2026-10-09-258ab27;

      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.zig
            rocNightlyPkg
          ];

          shellHook = ''
            echo "#
# Welcome to the reproduceable development environment.
#
# These are some of tools that are avaliable:
#
# =Compilers=
# roc:          $(roc version)
# zig:          $(zig version)
#
# Tip - To get started run the following command:
# roc run examples/bundle_self.roc
# "
          '';
        };
      });
}
