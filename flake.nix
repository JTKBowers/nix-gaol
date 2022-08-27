{
  description = "A flake describing functions to wrap packages using bubblewrap";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  outputs = { self, nixpkgs, flake-utils }: let
    # These are all the platforms that contain a bubblewrap package
    # As this flake only provides wrappers for calling bubblewrap, we can only support the platforms that bubblewrap supports
    supportedPlatforms = builtins.filter (x: (builtins.getAttr x nixpkgs.legacyPackages) ? busybox) (builtins.attrNames nixpkgs.legacyPackages);
  in
    flake-utils.lib.eachSystem supportedPlatforms (system: {
      packages = let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        nix-bubblewrap = pkgs.writeShellScriptBin "nix-bubblewrap" ''
${pkgs.bubblewrap}/bin/bwrap --unshare-all ${let deps = nixpkgs.lib.strings.splitString "\n" (nixpkgs.lib.strings.fileContents (pkgs.writeReferencesToFile pkgs.hello)); in builtins.toString (map (x: "--ro-bind ${x} ${x}") deps)} ${pkgs.hello}/bin/hello
'';
      };
    });
}
