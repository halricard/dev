#!/usr/bin/env bats
# Testes do instalador e comandos de ambiente.

load helper

@test "dev install --plan executa com sucesso sem tocar no disco" {
  run dev_cmd install --plan
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"PLANO DO CORE"* ]]
  [[ "$output" == *"PHP"* ]]
  [[ "$output" == *"MySQL"* ]]
  [[ "$output" == *"apenas simulação (--plan)"* ]]
}

@test "dev versions lista componentes fixados" {
  run dev_cmd versions
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"VERSÕES FIXADAS"* ]]
  [[ "$output" == *"mysql"* ]]
  [[ "$output" == *"node"* ]]
}

@test "APT_MIN inclui libcap2-bin" {
  run libraries '
    source "$DEV_ROOT/lib/install.sh"
    printf "%s\n" "${APT_MIN[@]}" | grep -x "libcap2-bin"
  '
  [[ "$status" -eq 0 ]]
}

@test "APT_MIN inclui libncurses6" {
  run libraries '
    source "$DEV_ROOT/lib/install.sh"
    printf "%s\n" "${APT_MIN[@]}" | grep -x "libncurses6"
  '
  [[ "$status" -eq 0 ]]
}

@test "compatibilize_libs cria symlinks para dependencias ausentes com fallback de ncurses" {
  run libraries '
    source "$DEV_ROOT/lib/install.sh"
    mock_dir="$DEV_HOME/mock_mysql"
    mkdir -p "$mock_dir/bin" "$mock_dir/lib-compat"
    touch "$mock_dir/bin/mysql"
    chmod +x "$mock_dir/bin/mysql"

    ldd() {
      echo "libncurses.so.6 => not found"
    }
    ls() {
      local arg
      for arg in "$@"; do
        if [[ "$arg" == *"/libncursesw.so."* ]]; then
          echo "/usr/lib/x86_64-linux-gnu/libncursesw.so.6.6"
          return 0
        fi
      done
      return 1
    }

    compatibilize_libs "$mock_dir"
    [[ -L "$mock_dir/lib-compat/libncurses.so.6" ]]
  '
  [[ "$status" -eq 0 ]]
}

@test "set_mysql_root_password detecta erro de biblioteca do mysql" {
  run libraries '
    source "$DEV_ROOT/lib/config.sh"
    config_set MYSQL_PASSWORD "testpass"
    prefix="$(mysql_prefix)"
    mkdir -p "$prefix/bin"
    cat > "$prefix/bin/mysql" << "EOF"
#!/usr/bin/env bash
echo "error while loading shared libraries: libncurses.so.6: cannot open shared object file" >&2
exit 127
EOF
    chmod +x "$prefix/bin/mysql"

    set_mysql_root_password
  '
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"o cliente mysql falhou por falta de bibliotecas dinâmicas"* ]]
}

@test "dev doctor alerta quando cliente mysql tem bibliotecas ausentes" {
  run libraries '
    source "$DEV_ROOT/lib/doctor.sh"
    source "$DEV_ROOT/lib/runtime.sh"
    prefix="$(mysql_prefix)"
    mkdir -p "$prefix/bin"
    cat > "$prefix/bin/mysql" << "EOF"
#!/usr/bin/env bash
exit 127
EOF
    chmod +x "$prefix/bin/mysql"
    cmd_doctor
  '
  [[ "$output" == *"cliente com bibliotecas ausentes"* ]]
}

@test "has_net_bind_capability detecta presenca e ausencia de capability" {
  run libraries '
    source "$DEV_ROOT/lib/runtime.sh"
    temp_bin="$DEV_HOME/mock_nginx"
    touch "$temp_bin"

    getcap() { echo "$1"; }
    ! has_net_bind_capability "$temp_bin" || exit 1

    getcap() { echo "$1 cap_net_bind_service=ep"; }
    has_net_bind_capability "$temp_bin" || exit 1
  '
  [[ "$status" -eq 0 ]]
}

@test "grant_net_bind_capability enfileira comando em PENDING quando sudo restrito" {
  run libraries '
    source "$DEV_ROOT/lib/runtime.sh"
    temp_bin="$DEV_HOME/mock_nginx"
    touch "$temp_bin"
    PENDING=()
    setcap() { return 1; }
    grant_net_bind_capability "$temp_bin" || true
    [[ "${#PENDING[@]}" -eq 1 ]] || exit 1
    [[ "${PENDING[0]}" == *"sudo setcap"* ]] || exit 1
  '
  [[ "$status" -eq 0 ]]
}

@test "dev doctor alerta quando nginx nao tem capability" {
  run libraries '
    source "$DEV_ROOT/lib/doctor.sh"
    source "$DEV_ROOT/lib/runtime.sh"
    mkdir -p "$(runtime_dir nginx)"
    runtime_sha256 nginx > "$(runtime_dir nginx)/.installed"
    getcap() { echo "$1"; }
    cmd_doctor
  '
  [[ "$output" == *"nginx sem permissão para portas 80/443"* ]]
}

@test "dev fix restaura capability do nginx com -f" {
  run libraries '
    source "$DEV_ROOT/lib/fix.sh"
    source "$DEV_ROOT/lib/runtime.sh"
    prefix="$(nginx_prefix)"
    mkdir -p "$prefix/sbin"
    touch "$prefix/sbin/nginx"
    has_net_bind_capability() { return 1; }
    sudo() { return 0; }
    cmd_fix -f
  '
  [[ "$output" == *"permissão 80/443 restaurada no nginx"* ]]
}
