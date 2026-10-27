#!/usr/bin/env bash
# Geração de arquivos de configuração: nginx, php.ini, php-fpm e MySQL.

write_nginx_conf() {
  local prefix
  prefix="$(nginx_prefix)"
  mkdir -p "$DEV_ETC/nginx/sites" "$DEV_RUN" "$DEV_LOG"
  cat > "$DEV_ETC/nginx/nginx.conf" <<CONF
# Gerado pelo dev. Não edite: reescrito a cada start.

worker_processes  auto;
daemon            on;
pid               $DEV_RUN/nginx.pid;
error_log         $DEV_LOG/nginx-error.log warn;

events {
    worker_connections  1024;
}

http {
    include       $prefix/conf/mime.types;
    default_type  application/octet-stream;
    access_log    $DEV_LOG/nginx-access.log;

    sendfile      on;
    tcp_nopush    on;
    server_tokens off;

    client_max_body_size 128M;

    client_body_temp_path $DEV_RUN/nginx-client-body;
    proxy_temp_path       $DEV_RUN/nginx-proxy;
    fastcgi_temp_path     $DEV_RUN/nginx-fastcgi;

    server {
        listen      127.0.0.1:$HTTP_PORT default_server;
        listen      127.0.0.1:$HTTPS_PORT ssl default_server;
        http2       on;
        server_name _;

        ssl_certificate     $LEAF_CRT;
        ssl_certificate_key $LEAF_KEY;

        location / {
            default_type text/html;
            return 404 '<!doctype html><meta charset=utf-8><title>dev</title><p style="font:16px system-ui;margin:3rem">Nenhum projeto responde por este endereço.<br>Veja os projetos ativos com <code>dev sites</code>.';
        }
    }

    include $DEV_ETC/nginx/sites/*.conf;
}
CONF
}

write_vhost() {
  local extra_ini=""
  if [[ -f "$DEV_QUIET/$1" ]]; then
    extra_ini='\n display_errors=Off'
  fi

  local name="$1" docroot="$2" php_series="${3:-8.5}"
  mkdir -p "$DEV_ETC/nginx/sites"
  local socket
  socket="$(fpm_socket "$(php_version "$php_series")")"
  cat > "$DEV_ETC/nginx/sites/$name.conf" <<CONF
# Gerado pelo dev para "$name". Não edite.

server {
    listen      127.0.0.1:$HTTP_PORT;
    listen      127.0.0.1:$HTTPS_PORT ssl;
    http2       on;
    server_name $name.localhost;
    root        $docroot;

    ssl_certificate     $LEAF_CRT;
    ssl_certificate_key $LEAF_KEY;

    index index.php index.html;

    access_log $DEV_LOG/$name-access.log;
    error_log  $DEV_LOG/$name-error.log;

    location / {
        try_files \$uri \$uri/index.html \$uri/ /index.php?\$query_string;
    }

    location ~ \.php(/|\$) {
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        set \$path_info \$fastcgi_path_info;
        try_files \$fastcgi_script_name =404;

        fastcgi_pass unix:$socket;
        fastcgi_index index.php;
        include $(nginx_prefix)/conf/fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$path_info;
        fastcgi_param HTTPS \$https if_not_empty;
        fastcgi_read_timeout 300;

        fastcgi_param PHP_ADMIN_VALUE "error_log=$DEV_LOG/$name-php.log$extra_ini";
    }

    location = /wp-config.php {
        deny all;
    }
    location ~ /\.(?!well-known).* {
        deny all;
    }
}
CONF
}

write_service_vhosts() {
  local php_series
  php_series="$(config_get DEFAULT_PHP)"
  write_vhost "adminer" "$DEV_HOME/adminer" "$php_series"
  cat > "$DEV_ETC/nginx/sites/mail.conf" <<CONF
# Gerado pelo dev. A interface do Mailpit por https.
server {
    listen      127.0.0.1:$HTTP_PORT;
    listen      127.0.0.1:$HTTPS_PORT ssl;
    server_name mail.localhost;
    ssl_certificate     $LEAF_CRT;
    ssl_certificate_key $LEAF_KEY;
    location / {
        proxy_pass http://127.0.0.1:$MAILPIT_UI_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }
}
CONF
}

write_site_vhosts() {
  local file name dir
  for file in "$DEV_SITES"/*; do
    [[ -f "$file" ]] || continue
    name="$(basename "$file")"
    dir="$(cat "$file")"
    (
      if [[ -f "$dir/dev.conf" ]] && load_project "$dir" >/dev/null 2>&1; then
        write_vhost "$name" "$dir/${PROJECT_DOCROOT:-.}" "${PROJECT_PHP:-$(config_get DEFAULT_PHP)}"
      else
        write_vhost "$name" "$dir" "$(config_get DEFAULT_PHP)"
      fi
    )
  done
  for file in "$DEV_ETC/nginx/sites"/*.conf; do
    [[ -f "$file" ]] || continue
    name="$(basename "$file" .conf)"
    case "$name" in adminer|mail) continue ;; esac
    [[ -f "$DEV_SITES/$name" ]] || rm -f "$file"
  done
}

write_nginx_files() {
  write_nginx_conf
  write_service_vhosts
  write_site_vhosts
}

write_adminer() {
  local password user
  password="$(config_get MYSQL_PASSWORD)"
  user="$(config_get MYSQL_USER)"
  mkdir -p "$DEV_HOME/adminer"
  cat > "$DEV_HOME/adminer/index.php" <<PHP
<?php
// Gerado pelo dev. Não edite: reescrito a cada start.
function dev_local() {
    return in_array(\$_SERVER['REMOTE_ADDR'] ?? '', ['127.0.0.1', '::1'], true);
}

if (dev_local() && !isset(\$_GET['username']) && empty(\$_POST['auth'])) {
    \$_POST['auth'] = [
        'driver'   => 'server',
        'server'   => '127.0.0.1:$MYSQL_PORT',
        'username' => '$user',
        'password' => '$password',
        'db'       => \$_GET['db'] ?? '',
    ];
}

function adminer_object() {
    if (!dev_local()) {
        return new \\Adminer\\Adminer;
    }
    class AdminerDev extends \\Adminer\\Adminer {
        function name() { return 'dev'; }
        function credentials() {
            return ['127.0.0.1:$MYSQL_PORT', '$user', '$password'];
        }
        function login(\$login, \$password) { return true; }
        function permanentLogin(\$create = false) { return 'dev'; }
        function verifyLoginToken() { return false; }
    }
    return new AdminerDev;
}

include __DIR__ . '/adminer.php';
PHP
}

write_php_ini() {
  local version="$1"
  local cfg="$DEV_ETC/php/$version"
  mkdir -p "$cfg/conf.d"
  [[ -f "$cfg/conf.d/local.ini" ]] || cat > "$cfg/conf.d/local.ini" <<'LOCAL'
; Seus ajustes. O dev nunca mexe neste arquivo, e ele é carregado depois do
; php.ini — o que estiver aqui vence. Depois de editar: dev restart
LOCAL
  local opcache_ini="" so_file
  for so_file in "$DEV_RUNTIME/php/$version"/lib/php/extensions/*/opcache.so; do
    [[ -f "$so_file" ]] && opcache_ini="zend_extension = $so_file"
  done
  cat > "$cfg/php.ini" <<INI
; Escrito pelo dev, reescrito a cada start.
; Para ajustar: conf.d/local.ini, ao lado deste arquivo.

display_errors = On
display_startup_errors = On
error_reporting = E_ALL
log_errors = On

memory_limit = 512M
max_execution_time = 300
upload_max_filesize = 128M
post_max_size = 128M

max_input_vars = 5000

date.timezone = America/Sao_Paulo

$opcache_ini
opcache.enable = 1
opcache.enable_cli = 0
opcache.validate_timestamps = 1
opcache.revalidate_freq = 0

sendmail_path = "$DEV_RUNTIME/mailpit/bin/mailpit sendmail --smtp-addr 127.0.0.1:$SMTP_PORT"
INI
}

write_fpm_pool_for_version() {
  local version="$1" cfg
  cfg="$DEV_ETC/php/$version"
  write_php_ini "$version"
  mkdir -p "$cfg"
  cat > "$cfg/php-fpm.conf" <<CONF
; Gerado pelo dev. Não edite: reescrito a cada start.
[global]
pid   = $DEV_RUN/php-fpm-$version.pid
error_log = $DEV_LOG/php-fpm-$version.log
daemonize = yes

[dev]
user  = $USER
group = $USER
listen = $(fpm_socket "$version")
listen.owner = $USER
listen.group = $USER
listen.mode  = 0660

pm = dynamic
pm.max_children      = 10
pm.start_servers     = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3

env[PATH] = /usr/local/bin:/usr/bin:/bin
clear_env = no

php_admin_value[error_log] = $DEV_LOG/php-$version.log
php_admin_flag[log_errors] = on
CONF
}

write_fpm_pools() {
  local ver
  while IFS= read -r ver; do
    [[ -n "$ver" ]] || continue
    write_fpm_pool_for_version "$ver"
  done < <(active_php_versions)
}

write_my_cnf() {
  mkdir -p "$DEV_ETC" "$DEV_DATA"
  cat > "$DEV_ETC/my.cnf" <<CONF
# Gerado pelo dev. Não edite: reescrito a cada start.
[mysqld]
basedir  = $(mysql_prefix)
datadir  = $DEV_DATA
socket   = $DEV_RUN/mysql.sock
pid-file = $DEV_RUN/mysql.pid
port     = $MYSQL_PORT
bind-address = 127.0.0.1
log-error = $DEV_LOG/mysql.log

innodb_buffer_pool_size = 256M
max_allowed_packet = 128M

[client]
socket = $DEV_RUN/mysql.sock
port   = $MYSQL_PORT
CONF
}

write_configs() {
  if [[ -f "$DEV_ROOT/lib/certs.sh" ]]; then
    # shellcheck source=/dev/null
    source "$DEV_ROOT/lib/certs.sh"
    reissue_leaf
  fi
  write_nginx_files
  write_fpm_pools
  write_my_cnf
  write_adminer
  write_cli_shortcuts
  ok "configuração escrita"
}

init_datadir() {
  local prefix password
  if [[ -d "$DEV_DATA/mysql" ]]; then
    ok "banco de dados  já inicializado"
    return 0
  fi
  prefix="$(mysql_prefix)"
  sandbox_libs
  with_progress "inicializando o MySQL" \
    "$prefix/bin/mysqld" --defaults-file="$DEV_ETC/my.cnf" \
    --initialize-insecure --user="$USER" \
    || die "o MySQL não conseguiu inicializar o banco"

  password="$(openssl rand -base64 18 2>/dev/null | tr -d '/+=' | cut -c1-24 || true)"
  [[ -n "$password" ]] || die "não consegui sortear a senha do banco"
  config_set MYSQL_PASSWORD "$password"
  config_set MYSQL_USER root
  ok "banco inicializado  senha do root guardada em $DEV_CONFIG"
}

mysql_password_applied() {
  sandbox_libs
  local password
  password="$(config_get MYSQL_PASSWORD)"
  [[ -n "$password" ]] || return 1
  MYSQL_PWD="$password" "$(mysql_prefix)/bin/mysql" \
    --socket="$DEV_RUN/mysql.sock" -u "$(config_get MYSQL_USER)" \
    -e 'SELECT 1' >/dev/null 2>&1
}

set_mysql_root_password() {
  sandbox_libs
  local prefix password err_output
  prefix="$(mysql_prefix)"
  password="$(config_get MYSQL_PASSWORD)"
  [[ -n "$password" ]] || die "não há senha de banco no config — rode \`$DEV install\`"

  mysql_password_applied && return 0

  if ! err_output="$(MYSQL_PWD="" "$prefix/bin/mysql" --socket="$DEV_RUN/mysql.sock" \
      -u root -e 'SELECT 1' 2>&1)"; then
    if [[ "$err_output" == *"error while loading shared libraries"* ]]; then
      die "o cliente mysql falhou por falta de bibliotecas dinâmicas: $err_output"
    elif [[ "$err_output" == *"Can't connect"* ]]; then
      die "não consegui conectar ao MySQL pelo socket $DEV_RUN/mysql.sock"
    else
      die "o MySQL não aceita a senha do config nem a senha vazia ($err_output)"
    fi
  fi

  MYSQL_PWD="" "$prefix/bin/mysql" --socket="$DEV_RUN/mysql.sock" -u root <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '$password';
FLUSH PRIVILEGES;
SQL
  ok "senha do banco aplicada"
}
