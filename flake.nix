{
  description = "Factor: the toolchain and runtime libraries to build and test it, for rift boxes";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # What ./build.sh needs to compile the VM and fetch a boot image.
      buildTools = pkgs: with pkgs; [ gcc gnumake curl git ];

      # Libraries Factor opens at run time through its FFI (dlopen by
      # name), which a NixOS box has nowhere on the default search path.
      runtimeLibs = pkgs: with pkgs; [ openssl zlib readline ];
    in
    {
      # The profile a rift box reads at this commit: packages on the path,
      # variables in every session. Contract: rift's image/base/profile.nix.
      #
      #   ./build.sh net-bootstrap
      #   ./factor -run=tools.test resource:core compiler threads io
      fixed-labs.rift = forAllSystems (pkgs: {
        packages = buildTools pkgs;
        env.LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath (runtimeLibs pkgs);
      });
    };
}
