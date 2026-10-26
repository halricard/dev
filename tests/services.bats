#!/usr/bin/env bats
# Testes da biblioteca lib/services.sh.

load helper

@test "pid_file devolve caminho sob DEV_RUN" {
  run libraries 'source "$DEV_ROOT/lib/services.sh" && pid_file mysql'
  [[ "$status" -eq 0 ]]
  [[ "$output" == "$DEV_HOME/services/run/mysql.pid" ]]
}

@test "running identifica processo vivo e morto" {
  run libraries '
    source "$DEV_ROOT/lib/services.sh"
    mkdir -p "$DEV_RUN"
    echo 999999 > "$(pid_file teste)"
    running teste
  '
  [[ "$status" -ne 0 ]]

  run libraries '
    source "$DEV_ROOT/lib/services.sh"
    mkdir -p "$DEV_RUN"
    sleep 5 &
    pid=$!
    echo "$pid" > "$(pid_file sleep_test)"
    running sleep_test && kill "$pid"
  '
  [[ "$status" -eq 0 ]]
}

@test "stack_ports lista as cinco portas da pilha" {
  run libraries 'source "$DEV_ROOT/lib/services.sh" && stack_ports'
  [[ "$status" -eq 0 ]]
  local count
  count="$(printf '%s\n' "$output" | wc -l)"
  [[ "$count" -eq 5 ]]
}

@test "service_of_port mapeia portas aos serviços" {
  run libraries '
    source "$DEV_ROOT/lib/services.sh"
    printf "%s|%s|%s\n" \
      "$(service_of_port "$HTTP_PORT")" \
      "$(service_of_port "$MYSQL_PORT")" \
      "$(service_of_port "$SMTP_PORT")"
  '
  [[ "$status" -eq 0 ]]
  [[ "$output" == "nginx|mysql|mailpit" ]]
}

@test "start_nginx alerta quando binario nao tem permissao para portas privilegiadas" {
  run libraries '
    source "$DEV_ROOT/lib/services.sh"
    source "$DEV_ROOT/lib/runtime.sh"
    prefix="$(nginx_prefix)"
    mkdir -p "$prefix/sbin"
    touch "$prefix/sbin/nginx"
    chmod +x "$prefix/sbin/nginx"

    port_busy() { return 1; }
    has_net_bind_capability() { return 1; }
    grant_net_bind_capability() { return 1; }

    start_nginx
  '
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"o nginx precisa de permissão para escutar nas portas"* ]]
  [[ "$output" == *"sudo setcap 'cap_net_bind_service=+ep'"* ]]
}
