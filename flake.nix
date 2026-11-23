{
  description = "SwiftTunes development shell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      pkgs = nixpkgs.legacyPackages.aarch64-darwin;
    in
    {
      # Supplies only the tools macOS does not ship. Swift, clang, the SDK,
      # xcrun, make, git and codesign stay Apple's, from Xcode and /usr/bin.
      devShells.aarch64-darwin.default = pkgs.mkShellNoCC {
        packages = [ pkgs.cmake ];

        # stdenv exports MACOSX_DEPLOYMENT_TARGET=14.0. cmake would take it as
        # the deployment target of ace-server and Apple clang would honour it
        # too, so a build in this shell would differ from one outside it,
        # which targets the running macOS.
        shellHook = ''
          unset MACOSX_DEPLOYMENT_TARGET
        '';
      };

      formatter.aarch64-darwin = pkgs.nixfmt;
    };
}
