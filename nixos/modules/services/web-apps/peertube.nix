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
      port: 9000

    webserver:
      https: true
      hostname: '${cfg.hostname}'
      port: 443

    database:
      hostname: '${cfg.database.host}'
      port: ${toString cfg.database.port}
      name: '${cfg.database.name}'
      username: '${cfg.database.user}'

    redis:
      hostname: '${cfg.redis.host}'
      port: ${toString cfg.redis.port}

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
        description = ''
          A file containing the password corresponding to
          <option>database.user</option>.
        '';
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

      host = lib.mkOption {
        description = "Redis host.";
        type = lib.types.str;
        default = "127.0.0.1";
      };

      port = lib.mkOption {
        description = "Redis port.";
        type = lib.types.port;
        default = 6379;
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = "/run/keys/peertube-redis-db-password";
        description = ''
          Password for redis database.
        '';
      };

      enableUnixSocket = lib.mkOption {
        description = "Use Unix socket";
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
      "d '${cfg.runtimeDir}/config' 0700 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.runtimeDir}/storage' 0750 ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.peertube = {
      description = "Peertube";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "redis.service" ]
        ++ (if databaseActuallyCreateLocally then [ "postgresql.service" ] else []);
      wants = [ "redis.service" ]
        ++ (if databaseActuallyCreateLocally then [ "postgresql.service" ] else []);

      environment.NODE_CONFIG_DIR = "${cfg.runtimeDir}/config";
      environment.NODE_ENV = "production";
      environment.HOME = cfg.package;

      path = [ pkgs.nodejs pkgs.bashInteractive pkgs.ffmpeg pkgs.openssl pkgs.sudo pkgs.youtube-dl ];

      serviceConfig = {
        Type = "simple";
        ExecStartPre = let preStartScript = pkgs.writeScript "peertube-pre-start.sh" ''
          #!/bin/sh
          cat > ${cfg.runtimeDir}/config/local-production.yaml <<EOF
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
          ${lib.optionalString databaseActuallyCreateLocally ''
          sudo -u postgres ${config.services.postgresql.package}/bin/psql -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;" ${cfg.database.name}
          sudo -u postgres ${config.services.postgresql.package}/bin/psql -c "CREATE EXTENSION IF NOT EXISTS unaccent;" ${cfg.database.name}
          ''}
        '';
        in "+${preStartScript}";
        ExecStart = let startScript = pkgs.writeScript "peertube-start.sh" ''
          #!/bin/sh
          install -m 0750 -d ${cfg.runtimeDir}/config
          ln -sf ${cfg.package}/config/default.yaml ${cfg.runtimeDir}/config/default.yaml
          ln -sf ${configFile} ${cfg.runtimeDir}/config/production.yaml
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
          home = cfg.runtimeDir;
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

