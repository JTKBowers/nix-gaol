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
        lib = pkgs.callPackage ./lib.nix {};
        wrapPackage = lib.wrapPackage;
      in {
        inherit wrapPackage lib;
        hello-bwrapped = wrapPackage {pkg = pkgs.hello;};
        curl-bwrapped = wrapPackage {
          pkg = pkgs.curl;
          shareNet = true;
          linuxOptions = {
            presets = ["ssl"];
          };
        };
        helix-bwrapped = wrapPackage {
          pkg = pkgs.helix;
          name = "hx";
          bindCwd = true;
          extraDepPkgs = [pkgs.rust-analyzer pkgs.nil];
          linuxOptions = {
            strace = true;
            envs = {
              HOME = "$HOME";
              TERM = "$TERM";
              COLORTERM = "$COLORTERM";
            };
          };
        };
        hello-wayland-bwrapped = wrapPackage {
          pkg = pkgs.hello-wayland;
          name = "hello-wayland";
          linuxOptions = {
            presets = ["wayland"];
            extraBwrapArgs = [
              "--dev /dev"
              "--proc /proc"
            ];
          };
        };

        dbus-monitor = wrapPackage {
          pkg = pkgs.dbus;
          name = "dbus-monitor";
          linuxOptions = {
            dbus.enable = true;
          };
        };

        eglinfo-bwrapped = wrapPackage {
          pkg = pkgs.glxinfo;
          name = "eglinfo";
          linuxOptions = {
            presets = ["graphics" "wayland"];
            extraBwrapArgs = [
              "--proc /proc"
            ];
          };
        };
      };
    })
    // {
      nixosModule = import ./nixos-module.nix;
    };
}
