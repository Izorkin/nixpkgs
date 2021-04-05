{ lib, pkgs, config, ... }:

let
  cfg = config.services.peertube;

  settingsFormat = pkgs.formats.yaml {};
  configFile = pkgs.writeText  "production.yaml" ''
    listen:
      hostname: 'localhost'
      port: 9000

    webserver:
      https: true
      hostname: '${cfg.hostname}'
      port: 443

    database:
      hostname: '/run/postgresql'
      port: 5432
      ssl: false
      suffix: '_prod'
      username: 'peertube'
      password: 'peertube'
      pool:
        max: 5

    redis:
      hostname: 'localhost'
      port: 6379
      auth: null
      db: 0

    storage:
      tmp: '${cfg.runtimeDir}/storage/tmp/'
      avatars: '${cfg.runtimeDir}/storage/avatars/'
      videos: '${cfg.runtimeDir}/storage/videos/'
      streaming_playlists: '${cfg.runtimeDir}/storage/streaming-playlists/'
      redundancy: '${cfg.runtimeDir}/storage/redundancy/'
      logs: '${cfg.runtimeDir}/storage/logs/'
      previews: '${cfg.runtimeDir}/storage/previews/'
      thumbnails: '${cfg.runtimeDir}/storage/thumbnails/'
      torrents: '${cfg.runtimeDir}/storage/torrents/'
      captions: '${cfg.runtimeDir}/storage/captions/'
      cache: '${cfg.runtimeDir}/storage/cache/'
      plugins: '${cfg.runtimeDir}/storage/plugins/'
      client_overrides: '${cfg.runtimeDir}/storage/client-overrides/'

    ${cfg.extraConfig}
  '';

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

    hostname = lib.mkOption {
      type = lib.types.str;
      default = "example.com";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
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
      "d '${cfg.runtimeDir}/storage' 0750 ${cfg.user} ${cfg.group} - -"
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
        ln -sf ${cfg.package}/config/default.yaml ${cfg.runtimeDir}/config/default.yaml
        ln -sf ${configFile} ${cfg.runtimeDir}/config/production.yaml
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
      };
    };

    users.groups = lib.optionalAttrs (cfg.group == "peertube") {
      peertube = { };
    };
  };
}
