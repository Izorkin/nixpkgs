{ lib, pkgs, config, ... }:

let
  cfg = config.services.peertube;
  # We only want to create a redis and database if we're actually going to connect to it.
  redisActuallyCreateLocally = cfg.redis.createLocally && cfg.redis.host == "127.0.0.1";
  databaseActuallyCreateLocally = cfg.database.createLocally && cfg.database.host == "/run/postgresql";

  settingsFormat = pkgs.formats.yaml {};
  configFile = pkgs.writeText  "production.yaml" ''
    listen:
      hostname: 'localhost'
      port: ${toString cfg.listenHttp}

    webserver:
      https: ${toString (if cfg.enableWebHttps then "true" else "false")}
      hostname: '${cfg.hostname}'
      port: ${toString cfg.listenWeb}

    redis:
      hostname: '${cfg.redis.host}'
      port: ${toString cfg.redis.port}

    database:
      hostname: '${cfg.database.host}'
      port: ${toString cfg.database.port}
      name: '${cfg.database.name}'
      username: '${cfg.database.user}'

    storage:
      tmp: '/var/lib/peertube/storage/tmp/'
      avatars: '/var/lib/peertube/storage/avatars/'
      videos: '/var/lib/peertube/storage/videos/'
      streaming_playlists: '/var/lib/peertube/storage/streaming-playlists/'
      redundancy: '/var/lib/peertube/storage/redundancy/'
      logs: '/var/lib/peertube/storage/logs/'
      previews: '/var/lib/peertube/storage/previews/'
      thumbnails: '/var/lib/peertube/storage/thumbnails/'
      torrents: '/var/lib/peertube/storage/torrents/'
      captions: '/var/lib/peertube/storage/captions/'
      cache: '/var/lib/peertube/storage/cache/'
      plugins: '/var/lib/peertube/storage/plugins/'
      client_overrides: '/var/lib/peertube/storage/client-overrides/'

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
      description = "Server name of reverse proxy";
    };

    listenHttp = lib.mkOption {
      type = lib.types.int;
      default = 9000;
      description = "listen port for HTTP server";
    };

    listenWeb = lib.mkOption {
      type = lib.types.int;
      default = 443;
      description = "listen port for WEB server";
    };

    enableWebHttps = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable or disable HTTPS protocol";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      example = ''
        listen:
          hostname: '0.0.0.0'
        trust_proxy:
          - '192.168.10.21'
        log:
          level: 'debug'
      '';
      description = "Extra config options for peertube";
    };

    redis = {
      createLocally = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Configure local Redis server for PeerTube.";
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Redis host.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 6379;
        description = "Redis port.";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = "/run/keys/peertube-redis-db-password";
        description = "Password for redis database";
      };

      enableUnixSocket = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Use Unix socket";
      };
    };

    database = {
      createLocally = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Configure local PostgreSQL database server for PeerTube.";
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "/run/postgresql";
        example = "192.168.15.47";
        description = "Database host address or unix socket.";
      };

      port = lib.mkOption {
        type = lib.types.int;
        default = 5432;
        description = "Database host port.";
      };

      name = lib.mkOption {
        type = lib.types.str;
        default = "peertube";
        description = "Database name.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "peertube";
        description = "Database user.";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = "/run/keys/peertube-db-password";
        description = "Password for PostgreSQL database";
      };
    };

    smtp = {
      createLocally = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Configure local Postfix SMTP server for PeerTube.";
      };
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
    systemd.tmpfiles.rules = [
      "d '/var/lib/peertube/config' 0700 ${cfg.user} ${cfg.group} - -"
      "z '/var/lib/peertube/config' 0700 ${cfg.user} ${cfg.group} - -"
      "d '/var/lib/peertube/storage' 0750 ${cfg.user} ${cfg.group} - -"
      "z '/var/lib/peertube/storage' 0750 ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.peertube = {
      description = "Peertube";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "redis.service" ]
        ++ (if databaseActuallyCreateLocally then [ "postgresql.service" ] else []);
      wants = [ "redis.service" ]
        ++ (if databaseActuallyCreateLocally then [ "postgresql.service" ] else []);

      environment.NODE_CONFIG_DIR = "/var/lib/peertube/config";
      environment.NODE_ENV = "production";
      environment.NODE_EXTRA_CA_CERTS = "/etc/ssl/certs/ca-certificates.crt";
      environment.HOME = cfg.package;

      path = [ pkgs.nodejs pkgs.bashInteractive pkgs.ffmpeg pkgs.openssl pkgs.sudo pkgs.youtube-dl ];

      serviceConfig = {
        Type = "simple";
        ExecStartPre = let preStartScript = pkgs.writeScript "peertube-pre-start.sh" ''
          #!/bin/sh
          umask 077
          cat > /var/lib/peertube/config/local-production.yaml <<EOF
          ${lib.optionalString ((!databaseActuallyCreateLocally) && (cfg.database.passwordFile != null)) ''
          database:
            password: '$(cat ${cfg.database.passwordFile})'
          ''}
          ${lib.optionalString ((redisActuallyCreateLocally) && (cfg.redis.passwordFile == null)) ''
          redis:
            hostname:
            port:
            socket: '/run/redis/redis.sock'
          ''}
          ${lib.optionalString ((redisActuallyCreateLocally) && (cfg.redis.passwordFile != null)) ''
          redis:
            hostname:
            port:
            socket: '/run/redis/redis.sock'
            auth: '$(cat ${cfg.redis.passwordFile})'
          ''}
          EOF
          chown ${cfg.user}:${cfg.group} /var/lib/peertube/config/local-production.yaml
          ${lib.optionalString databaseActuallyCreateLocally ''
          sudo -u postgres ${config.services.postgresql.package}/bin/psql -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;" ${cfg.database.name}
          sudo -u postgres ${config.services.postgresql.package}/bin/psql -c "CREATE EXTENSION IF NOT EXISTS unaccent;" ${cfg.database.name}
          ''}
          sudo -u ${cfg.user} ln -sf ${cfg.package}/config/default.yaml /var/lib/peertube/config/default.yaml
          sudo -u ${cfg.user} ln -sf ${configFile} /var/lib/peertube/config/production.yaml
        '';
        in "+${preStartScript}";
        ExecStart = let startScript = pkgs.writeScript "peertube-start.sh" ''
          #!/bin/sh
          exec npm start
        '';
        in "${startScript}";
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
        # Access write directories
        UMask = "0027";
        # Capabilities
        CapabilityBoundingSet = "~CAP_SYS_ADMIN";
        # Sandboxing
        ProtectHome = true;
        ProtectSystem = "full";
        PrivateTmp = true;
        ProtectControlGroups = true;
      };
    };

    services.postfix = lib.mkIf cfg.smtp.createLocally {
      enable = true;
    };

    services.redis = lib.mkMerge [
      (lib.mkIf redisActuallyCreateLocally {
        enable = true;
      })
      (lib.mkIf cfg.redis.enableUnixSocket {
        unixSocket = "/run/redis/redis.sock";
        unixSocketPerm = 770;
      })
    ];

    services.postgresql = lib.mkIf databaseActuallyCreateLocally {
      enable = true;
      ensureUsers = [{
        name = cfg.database.user;
        ensurePermissions = { "DATABASE ${cfg.database.name}" = "ALL PRIVILEGES"; };
      }];
      ensureDatabases = [ cfg.database.name ];
    };

    users.users = lib.mkMerge [
      (lib.mkIf (cfg.user == "peertube") {
        peertube = {
          isSystemUser = true;
          group = cfg.group;
        };
      })
      (lib.mkIf cfg.redis.enableUnixSocket {${config.services.peertube.user}.extraGroups = [ "redis" ];})
    ];

    users.groups = lib.optionalAttrs (cfg.group == "peertube") {
      peertube = { };
    };
  };
}
