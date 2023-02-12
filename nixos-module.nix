{
  lib,
  pkgs,
  config,
  ...
}:
with lib; let
  cfg = config;
  wrapPackage = (import ./lib.nix).wrapPackage pkgs;
  pkgOptions = {
    options = {
      pkg = mkOption {
        type = types.package;
        description = "The package to wrap";
        example = "pkgs.hello";
      };
      name = mkOption {
        type = types.str;
        description = "The name of the binary to wrap";
      };
      extraDepPkgs = mkOption {
        type = types.listOf types.package;
        description = "A list of extra packages to make available to the sandbox";
        default = [];
      };
      bindCwd = mkOption {
        type = types.enum [true false "ro"];
        description = "Whether to bind the current working directory";
        default = false;
      };
      envs = mkOption {
        type = types.attrsOf types.str;
        description = "Environment variables to make available to the sandbox";
        default = {};
      };
      extraArgs = mkOption {
        type = types.listOf types.str;
        description = "Extra arguments to pass to bwrap.";
        default = [];
      };
      strace = mkOption {
        type = types.bool;
        description = "Whether to call the wrapped program using strace to log its syscalls";
        default = false;
      };
      logGeneratedCommand = mkOption {
        type = types.bool;
        description = "Whether to log the generated bubblewrap command when it is run";
        default = false;
      };
      extraBindDirs = mkOption {
        type = types.listOf types.str;
        description = "Extra directories to bind into the sandbox";
        default = [];
      };
      extraRoBindDirs = mkOption {
        type = types.listOf types.str;
        description = "Extra directories to ro-bind into the sandbox";
        default = [];
      };
      shareUser = mkOption {
        type = types.bool;
        description = "Whether to share the user. If false (the default) it will create a new user namespace";
        default = false;
      };
      shareIpc = mkOption {
        type = types.bool;
        description = "Whether to share IPC. If false (the default) it will create a new IPC namespace";
        default = false;
      };
    };
  };
in {
  options.sandboxedPackages = mkOption {
    type = types.listOf (types.submodule pkgOptions);
    default = [];
  };

  config = {
    environment.systemPackages = map wrapPackage cfg.sandboxedPackages;
  };
}
