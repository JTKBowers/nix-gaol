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
        sandboxPackage = lib.sandboxPackage;
      in {
        sandboxedPackages = builtins.mapAttrs (name: pkg: args: sandboxPackage ({inherit pkg name;} // args)) prev;
        monitor-sandbox = lib.monitor-sandbox; # TODO: Only populate on darwin
        inherit sandboxPackage;
      };
    }
    // flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {
        inherit system;
      };
      lib = pkgs.callPackage ./lib.nix {};
      sandboxPackage = lib.sandboxPackage;
    in {
      packages = {
        inherit lib;
        sandboxPackage = sandboxPackage;
        sandboxed-hello = sandboxPackage {pkg = pkgs.hello;};
        sandboxed-curl = sandboxPackage {
          pkg = pkgs.curl;
          shareNet = true;
          linuxOptions = {
            presets = ["ssl"];
          };
        };
        sandboxed-helix = sandboxPackage {
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
        sandboxed-hello-wayland = sandboxPackage {
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

        sandboxed-dbus-monitor = sandboxPackage {
          pkg = pkgs.dbus;
          name = "dbus-monitor";
          linuxOptions = {
            dbus.enable = true;
          };
        };

        sandboxed-eglinfo = sandboxPackage {
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
