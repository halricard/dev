#!/usr/bin/env bats
# Testes das bibliotecas lib/config.sh e lib/certs.sh.

load helper

@test "write_nginx_conf gera configuração com portas corretas" {
  run libraries '
    source "$DEV_ROOT/lib/config.sh"
    write_nginx_conf
    cat "$DEV_ETC/nginx/nginx.conf"
  '
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"127.0.0.1:$HTTP_PORT"* ]]
  [[ "$output" == *"127.0.0.1:$HTTPS_PORT"* ]]
}

@test "write_vhost gera vhost apontando para fpm_socket" {
  run libraries '
    source "$DEV_ROOT/lib/config.sh"
    write_vhost "meu-site" "$DEV_HOME/sites/meu-site" "8.5"
    cat "$DEV_ETC/nginx/sites/meu-site.conf"
  '
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"server_name meu-site.localhost;"* ]]
  [[ "$output" == *"php-8.5.sock"* ]]
}

@test "write_my_cnf gera my.cnf com porta configurada" {
  run libraries '
    source "$DEV_ROOT/lib/config.sh"
    write_my_cnf
    cat "$DEV_ETC/my.cnf"
  '
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"port     = $MYSQL_PORT"* ]]
  [[ "$output" == *"mysql.sock"* ]]
}

@test "generate_ca cria certificado e chave" {
  run libraries '
    source "$DEV_ROOT/lib/certs.sh"
    generate_ca
    [[ -f "$CA_CRT" && -f "$CA_KEY" ]]
  '
  [[ "$status" -eq 0 ]]
}
