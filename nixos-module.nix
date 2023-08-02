{
  lib,
  pkgs,
  config,
  ...
}:
with lib; let
  cfg = config;
  wrapPackage = (import ./lib.nix).wrapPackage pkgs;
  samePathBindOption = {
    options = {
      mode = mkOption {
        type = types.enum ["ro" "rw"];
        description = "Whether to mount this path as read-only (the default) or read-write.";
        default = "ro";
      };
      path = mkOption {
        type = types.str;
        description = "The source and destination path to mount";
      };
    };
  };
  diffPathBindOption = {
    options = {
      mode = mkOption {
        type = types.enum ["ro" "rw"];
        description = "Whether to mount this path as read-only (the default) or read-write.";
        default = "ro";
      };
      srcPath = mkOption {
        type = types.str;
        description = "The path outside the sandbox to mount inside the sandbox. Required if path is not set";
      };
      dstPath = mkOption {
        type = types.str;
        description = "The path inside the sandbox. Required if path is not set";
      };
    };
  };
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
      extraBindPaths = mkOption {
        type = types.listOf (types.oneOf [types.str (types.submodule samePathBindOption) (types.subModule diffPathBindOption)]);
        description = "Extra paths to bind into the sandbox";
        default = [];
      };
      runtimeStorePaths = mkOption {
        type = types.listOf types.str;
        description = "Links to the nix store that aren't present at build time. Intended for things like /run/opengl-driver.";
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
      sharePid = mkOption {
        type = types.bool;
        description = "Whether to share PID. If false (the default) it will create a new PID namespace";
        default = false;
      };
      shareNet = mkOption {
        type = types.bool;
        description = "Whether to allow network access in the sandbox.";
        default = false;
      };
      shareUts = mkOption {
        type = types.bool;
        description = "Whether to share UTS. If false (the default) it will create a new UTS namespace";
        default = false;
      };
      shareCgroup = mkOption {
        type = types.bool;
        description = "Whether to share the cgroup. If false (the default) it will create a new cgroup namespace";
        default = false;
      };
      clearEnv = mkOption {
        type = types.bool;
        description = "Whether to clear the environment variables. If true it will pass in the environment variables from the context in which it is run.";
        default = true;
      };
      presets = mkOption {
        type = types.listOf (types.enum ["ssl"]);
        description = "Presets for common functionality";
        default = [];
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
