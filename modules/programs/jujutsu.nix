{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkIf mkOption types;

  cfg = config.programs.jujutsu;
  tomlFormat = pkgs.formats.toml { };
  packageVersion = lib.getVersion cfg.package;

  # jj v0.29+ deprecated support for "~/Library/Application Support" on Darwin.
  configDir =
    if pkgs.stdenv.isDarwin && !(lib.versionAtLeast packageVersion "0.29.0") then
      "Library/Application Support"
    else
      config.xdg.configHome;
in
{
  meta.maintainers = [ lib.maintainers.shikanime ];

  imports =
    let
      mkRemovedShellIntegration =
        name:
        lib.mkRemovedOptionModule [
          "programs"
          "jujutsu"
          "enable${name}Integration"
        ] "This option is no longer necessary.";
    in
    map mkRemovedShellIntegration [
      "Bash"
      "Fish"
      "Zsh"
    ];

  options.programs.jujutsu = {
    enable = lib.mkEnableOption "a Git-compatible DVCS that is both simple and powerful";

    package = lib.mkPackageOption pkgs "jujutsu" { nullable = true; };

    ediff = mkOption {
      type = types.bool;
      default = config.programs.emacs.enable;
      defaultText = lib.literalExpression "config.programs.emacs.enable";
      description = ''
        Enable ediff as a merge tool
      '';
    };

    settings = mkOption {
      type = tomlFormat.type;
      default = { };
      example = {
        user = {
          name = "John Doe";
          email = "jdoe@example.org";
        };
      };
      description = ''
        Options to add to the {file}`config.toml` file. See
        <https://github.com/martinvonz/jj/blob/main/docs/config.md>
        for options.
      '';
    };

    includes = mkOption {
      type = types.listOf types.lines;
      default = [ ];
      example = [
        ''
          --when.repositories = ["~/work"]

          [user]
          email = "NAME@WORK"
        ''
      ];
      description = ''
        List of additional configuration files to include. Similar to `programs.git.includes`.
      '';
    };
  };

  config = mkIf cfg.enable {
    home.packages = mkIf (cfg.package != null) [ cfg.package ];

    programs.jujutsu.settings = lib.mkMerge [
      (lib.mkIf cfg.ediff {
        merge-tools.ediff =
          let
            emacsDiffScript = pkgs.writeShellScriptBin "emacs-ediff" ''
              set -euxo pipefail
              ${config.programs.emacs.package}/bin/emacsclient -c --eval "(ediff-merge-files-with-ancestor \"$1\" \"$2\" \"$3\" nil \"$4\")"
            '';
          in
          {
            program = lib.getExe emacsDiffScript;
            merge-args = [
              "$left"
              "$right"
              "$base"
              "$output"
            ];
          };
      })
    ];

    home.file = lib.mkMerge [
      {
        "${configDir}/jj/config.toml" = mkIf (cfg.settings != { }) {
          source = tomlFormat.generate "jujutsu-config" cfg.settings;
        };
      }

      (mkIf (cfg.includes != [ ]) (
        let
          files = lib.imap (i: conf: {
            "${configDir}/jj/conf.d/include-${toString i}.toml" = {
              text = conf;
            };
          }) cfg.includes;
        in
        lib.mergeAttrsList files
      ))
    ];
  };
}
