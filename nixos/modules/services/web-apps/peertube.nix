{ lib, pkgs, config, ... }:

let
  cfg = config.services.peertube;

in {
  options.services.peertube = {
    enable = lib.mkEnableOption "Enable Peertube’s service";

    user = lib.mkOption {
      type = lib.types.str;
      default = "peertube";
      description = "User account under which Peertube runs";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "peertube";
      description = "Group under which Peertube runs";
    };

    configFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        The configuration file path for Peertube.
      '';
    };

    database = {
      createLocally = lib.mkOption {
        description = "Configure local PostgreSQL database server for PeerTube.";
        type = lib.types.bool;
        default = true;
      };

      name = lib.mkOption {
        type = lib.types.str;
        default = "peertube_prod";
        description = "Database name.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "peertube";
        description = "Database user.";
      };
    };

    smtp = {
      createLocally = lib.mkOption {
        description = "Configure local Postfix SMTP server for PeerTube.";
        type = lib.types.bool;
        default = true;
      };
    };

    redis = {
      createLocally = lib.mkOption {
        description = "Configure local Redis server for PeerTube.";
        type = lib.types.bool;
        default = true;
      };
    };

    runtimeDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/peertube";
      description = "The directory where Peertube stores its runtime data.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.peertube;
      description = ''
        Peertube package to use.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Make sure the runtimeDir exists with the desired permissions.
    systemd.tmpfiles.rules = [
      "d '${cfg.runtimeDir}' 0750 ${cfg.user} ${cfg.group} - -"
      "d '/var/www/peertube' 0750 ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.peertube = {
      description = "Peertube";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "postgresql.service" "redis.service" ];
      wants = [ "postgresql.service" "redis.service" ];

      environment.NODE_CONFIG_DIR = "${cfg.runtimeDir}/config";
      environment.NODE_ENV = "production";
      environment.HOME = cfg.package;

      path = [ pkgs.nodejs pkgs.bashInteractive pkgs.ffmpeg pkgs.openssl pkgs.sudo pkgs.youtube-dl ];

      script = ''
        install -m 0750 -d ${cfg.runtimeDir}/config
        ln -sf ${cfg.configFile} ${cfg.runtimeDir}/config/production.yaml
        exec npm start
      '';

      serviceConfig = {
        Type = "simple";
        ExecStartPre = let script = pkgs.writeScript "peertube-pre-start.sh" ''
          #!/bin/sh
          sudo -u postgres "${config.services.postgresql.package}/bin/psql" -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;" ${cfg.database.name}
          sudo -u postgres "${config.services.postgresql.package}/bin/psql" -c "CREATE EXTENSION IF NOT EXISTS unaccent;" ${cfg.database.name}
        '';
        in "+${script}";
        Restart = "always";
        RestartSec = 20;
        TimeoutSec = 60;
        WorkingDirectory = cfg.package;
        # User and group
        User = cfg.user;
        Group = cfg.group;
        # State directory and mode
        StateDirectory = "peertube";
        StateDirectoryMode = "0750";
        # Capabilities
        CapabilityBoundingSet = "~CAP_SYS_ADMIN";
        # Sandboxing
        ProtectHome = true;
        ProtectSystem = "full";
        PrivateTmp = true;
        ProtectControlGroups = true;
      };

      unitConfig.RequiresMountsFor = cfg.runtimeDir;
    };

    services.postfix = lib.mkIf cfg.smtp.createLocally {
      enable = true;
    };

    services.redis = lib.mkIf cfg.redis.createLocally {
      enable = true;
    };

    services.postgresql = lib.mkIf cfg.database.createLocally {
      enable = true;
      ensureUsers = [{
        name = cfg.database.user;
        ensurePermissions = { "DATABASE ${cfg.database.name}" = "ALL PRIVILEGES"; };
      }];
      ensureDatabases = [ cfg.database.name ];
      authentication = ''
        host ${cfg.database.name} ${cfg.database.user} 127.0.0.1/32 trust
        host ${cfg.database.name} ${cfg.database.user} 127.0.0.1/32 md5
      '';
    };

    users.users = lib.optionalAttrs (cfg.user == "peertube") {
     peertube  = {
        isSystemUser = true;
        home = cfg.runtimeDir;
        group = cfg.group;
        # todo: fix this. needed for postgres authentication
        password = "peertube";
      };
    };

    users.groups = lib.optionalAttrs (cfg.group == "peertube") {
      peertube = { };
    };
  };
}
