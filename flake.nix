{
  description = "Easy sandboxing for the slightly paranoid Nix user";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    {
      overlays.default = final: prev: let
        lib = prev.callPackage ./lib.nix {};
        wrapPackage = lib.wrapPackage;
      in {
        sandboxedPackages = builtins.mapAttrs (name: pkg: args: wrapPackage ({inherit pkg name;} // args)) prev;
        monitor-sandbox = lib.monitor-sandbox; # TODO: Only populate on darwin
        inherit wrapPackage;
      };
    }
    // flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
      };
      lib = pkgs.callPackage ./lib.nix {};
      wrapPackage = lib.wrapPackage;
    in {
      packages = {
        inherit wrapPackage lib;
        sandboxed-hello = wrapPackage {pkg = pkgs.hello;};
        sandboxed-curl = wrapPackage {
          pkg = pkgs.curl;
          shareNet = true;
          linuxOptions = {
            presets = ["ssl"];
          };
        };
        sandboxed-helix = wrapPackage {
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
        sandboxed-hello-wayland = wrapPackage {
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

        sandboxed-dbus-monitor = wrapPackage {
          pkg = pkgs.dbus;
          name = "dbus-monitor";
          linuxOptions = {
            dbus.enable = true;
          };
        };

        sandboxed-eglinfo = wrapPackage {
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
