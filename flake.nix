{
  description = "A flake describing functions to wrap packages using bubblewrap";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (system: {
      packages = let
        pkgs = import nixpkgs {
          inherit system;
        };
        wrapPackage =
          (import ./lib.nix).wrapPackage pkgs;
      in {
        hello-bwrapped = wrapPackage {pkg = pkgs.hello;};
        curl-bwrapped = wrapPackage {
          pkg = pkgs.curl;
          shareNet = true;
          presets = ["ssl"];
        };
        helix-bwrapped = wrapPackage {
          pkg = pkgs.helix;
          name = "hx";
          bindCwd = true;
          extraDepPkgs = [pkgs.rust-analyzer pkgs.rnix-lsp];
          envs = {
            HOME = "$HOME";
            TERM = "$TERM";
            COLORTERM = "$COLORTERM";
          };
        };
        hello-wayland-bwrapped = wrapPackage {
          pkg = pkgs.hello-wayland;
          name = "hello-wayland";
          envs = {XDG_RUNTIME_DIR = "$XDG_RUNTIME_DIR";};
          extraBindPaths = ["$XDG_RUNTIME_DIR/wayland-0"];
          extraArgs = ["--dev /dev" "--dev-bind /dev/dri /dev/dri" "--proc /proc"];
        };
      };
    })
    // {
      lib = {wrapPackage = (import ./lib.nix).wrapPackage;};
      nixosModule = import ./nixos-module.nix;
    };
}
