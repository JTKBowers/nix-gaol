{
  writeShellScriptBin,
  writeText,
  ...
}: let
  callSandboxExec = {
    name,
    pkg,
    policy,
  }:
    writeShellScriptBin name ''
      sandbox-exec -f ${policy} -D cwd=$(pwd) -D tmpdir="$TMPDIR" -D path_arg="$1" -D homedir="$HOME" ${pkg}/bin/${name} $@
    '';
in {
  monitorSandboxCalls = writeShellScriptBin "monitor-sandbox" ''
    log stream --style compact --predicate 'sender=="Sandbox"'
  '';
  wrapPackage = {
    pkg,
    name ? pkg.pname,
    extraBindPaths ? [],
    runtimeStorePaths ? [],
    bindCwd ? false,
    extraDepPkgs ? [],
    shareNet ? false,
    presets ? [],
    linuxOptions ? {},
    darwinOptions ? {},
  }: let
    policy = writeText "${name}-policy" ''
      (version 1)
      (deny default)
      (import "/System/Library/Sandbox/Profiles/bsd.sb")

      (allow file-read*
        (subpath "/nix/store") ; TODO: Scope to package closure
      )
      (allow process-exec
        (subpath "${pkg}"))
    '';
  in
    callSandboxExec {inherit name pkg policy;};
}
