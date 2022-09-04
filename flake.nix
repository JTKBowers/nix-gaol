{
  description = "A flake describing functions to wrap packages using bubblewrap";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  outputs = { self, nixpkgs, flake-utils }:
    let
      # These are all the platforms that contain a bubblewrap package
      # As this flake only provides wrappers for calling bubblewrap, we can only support the platforms that bubblewrap supports
      supportedPlatforms = builtins.filter (x: (builtins.getAttr x nixpkgs.legacyPackages) ? busybox) (builtins.attrNames nixpkgs.legacyPackages);
    in
    (flake-utils.lib.eachSystem supportedPlatforms (system: {
      packages =
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          hello-bwrapped = (import ./lib.nix).wrapPackage pkgs { pkg = pkgs.hello; };
          helix-bwrapped = (import ./lib.nix).wrapPackage pkgs {
            pkg = pkgs.helix;
            name = "hx";
            bindCwd = true;
            extraDepPkgs = [ pkgs.rust-analyzer pkgs.rnix-lsp ];
            envs = { HOME = "$HOME"; TERM = "$TERM"; COLORTERM = "$COLORTERM"; };
          };
          hello-wayland-bwrapped = (import ./lib.nix).wrapPackage pkgs {
            pkg = pkgs.hello-wayland;
            name = "hello-wayland";
            envs = { XDG_RUNTIME_DIR = "$XDG_RUNTIME_DIR"; };
            extraRoBindDirs = [ "$XDG_RUNTIME_DIR/wayland-0" ];
            extraArgs = [ "--dev /dev" "--dev-bind /dev/dri /dev/dri" "--proc /proc" ];
          };
        };
    })) // {
      lib = { wrapPackage = (import ./lib.nix).wrapPackage; };
    };
}
