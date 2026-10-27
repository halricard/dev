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

@test "process_exe identifica executavel via cmdline quando readlink e restrito" {
  run libraries '
    source "$DEV_ROOT/lib/services.sh"
    readlink() {
      if [[ "$*" == *"/exe" ]]; then return 1; fi
      command readlink "$@"
    }
    bash -c "exec -a \"$DEV_RUNTIME/nginx/1.30.5/sbin/nginx\" sleep 2" &
    sub_pid=$!
    res="$(process_exe "$sub_pid")"
    kill "$sub_pid" 2>/dev/null || true
    [[ "$res" == "$DEV_RUNTIME/nginx/1.30.5/sbin/nginx" ]]
  '
  [[ "$status" -eq 0 ]]
}

@test "port_owner classifica processo com pid registrado como own" {
  run libraries '
    source "$DEV_ROOT/lib/services.sh"
    mkdir -p "$DEV_RUN"
    echo "$$" > "$(pid_file nginx)"
    port_busy() { return 0; }
    ss() { printf "LISTEN 0 511 127.0.0.1:80 0.0.0.0:* users:((\"nginx\",pid=%s,fd=6))\n" "$$"; }
    sudo() { return 1; }
    port_owner "$HTTP_PORT"
    printf "%s|%s\n" "$OWNER_CLASS" "$OWNER_SERVICE"
  '
  [[ "$status" -eq 0 ]]
  [[ "$output" == "own|nginx" ]]
}

@test "take_over_ports nao encerra servico proprio e nao consome stdin" {
  run libraries '
    source "$DEV_ROOT/lib/services.sh"
    mkdir -p "$DEV_RUN"
    echo "$$" > "$(pid_file nginx)"
    port_busy() { [[ "$1" == "$HTTP_PORT" ]]; }
    ss() { printf "LISTEN 0 511 127.0.0.1:80 0.0.0.0:* users:((\"nginx\",pid=%s,fd=6))\n" "$$"; }
    take_over_ports
  '
  [[ "$status" -eq 0 ]]
  [[ "$output" != *"continua ocupada"* ]]
  [[ "$output" != *"não consegui encerrar"* ]]
}

@test "take_over_ports isola stdin e respeita confirmacao do usuario" {
  run libraries '
    source "$DEV_ROOT/lib/services.sh"
    port_busy() { [[ "$1" == "$HTTP_PORT" ]]; }
    port_owner() {
      OWNER_CLASS="user"
      OWNER_PID="$$"
      OWNER_NAME="custom-proc"
      OWNER_USER="$USER"
    }
    confirm() { return 1; }
    take_over_ports
  '
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"porta $HTTP_PORT continua ocupada por custom-proc"* ]]
}
