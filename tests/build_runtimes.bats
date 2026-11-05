#!/usr/bin/env bats
# Testes do gerador e construtor de runtimes: tools/build-runtimes.sh.

load helper

@test "build-runtimes.sh exibe ajuda estruturada sem crases" {
  run "$ROOT/tools/build-runtimes.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"construtor de runtimes estáticos do dev"* ]]
  [[ "$output" == *"php [versão]"* ]]
  [[ "$output" != *"\`"* ]]
}

@test "build-runtimes.sh php 8.4 --plan simula compilação sem tocar no disco" {
  run "$ROOT/tools/build-runtimes.sh" php 8.4 --plan
  [ "$status" -eq 0 ]
  [[ "$output" == *"COMPILAÇÃO DO PHP 8.4.27 (8.4)"* ]]
  [[ "$output" == *"modo simulação (--plan)"* ]]
  [[ "$output" == *"runtimes/php/php-8.4.27-linux-x86_64.tar.xz"* ]]
}

@test "build-runtimes.sh check-deps detecta ferramentas ausentes" {
  run bash -c "'$ROOT/tools/build-runtimes.sh' check-deps </dev/null"
  # Se ferramentas faltarem, o código é 1 com diagnóstico
  if [[ "$status" -ne 0 ]]; then
    [[ "$output" == *"faltam"* ]]
    [[ "$output" == *"sudo apt install"* ]]
  else
    [[ "$output" == *"ferramentas de compilação do sistema presentes"* ]]
  fi
}

@test "build-runtimes.sh rejeita comando desconhecido" {
  run "$ROOT/tools/build-runtimes.sh" comando-invalido
  [ "$status" -ne 0 ]
  [[ "$output" == *"comando desconhecido"* ]]
}

@test "lib/runtime.sh exporta APT_BUILD_DEPS com ferramentas oficiais incluindo bzip2" {
  run bash -c "source '$ROOT/lib/runtime.sh' && printf '%s\n' \"\${#APT_BUILD_DEPS[@]}\""
  [ "$status" -eq 0 ]
  [ "$output" -ge 14 ]

  run bash -c "source '$ROOT/lib/runtime.sh' && printf '%s ' \"\${APT_BUILD_DEPS[@]}\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"gcc "* ]]
  [[ "$output" == *"g++ "* ]]
  [[ "$output" == *"make "* ]]
  [[ "$output" == *"autoconf "* ]]
  [[ "$output" == *"bison "* ]]
  [[ "$output" == *"re2c "* ]]
  [[ "$output" == *"flex "* ]]
  [[ "$output" == *"bzip2 "* ]]
}

@test "missing_build_deps identifica ferramentas ausentes" {
  run bash -c "source '$ROOT/lib/runtime.sh'
    APT_BUILD_DEPS=(ferramenta_inexistente_1234 gcc)
    missing=\$(missing_build_deps)
    printf '%s\n' \"\$missing\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"ferramenta_inexistente_1234"* ]]
}

@test "check_build_deps aborta em modo nao-interativo quando faltam ferramentas" {
  run bash -c "
    DEV_ROOT='$ROOT'
    source '$ROOT/lib/common.sh'
    source '$ROOT/tools/build-runtimes.sh'
    missing_build_deps() { echo 'gcc'; }
    check_build_deps
  " </dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"faltam 1 ferramentas de compilação no sistema"* ]]
  [[ "$output" == *"sudo apt update && sudo apt install -y gcc"* ]]
}

@test "check_build_deps instala ferramentas com confirmacao positiva do usuario" {
  run bash -c "
    DEV_ROOT='$ROOT'
    source '$ROOT/lib/common.sh'
    source '$ROOT/tools/build-runtimes.sh'
    missing_count=1
    missing_build_deps() {
      if (( missing_count > 0 )); then echo 'gcc'; return 0; fi
      return 0
    }
    confirm() { return 0; }
    sudo() {
      if [[ \"\$1\" == \"apt-get\" ]]; then
        missing_count=0
        return 0
      fi
      return 1
    }
    check_build_deps
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"instalando ferramentas de compilação..."* ]]
  [[ "$output" == *"ferramentas de compilação instaladas com sucesso"* ]]
}

@test "spc_binary baixa e descompacta tarball quando spc nao esta em cache" {
  run bash -c "
    DEV_ROOT='$ROOT'
    source '$ROOT/lib/common.sh'
    source '$ROOT/tools/build-runtimes.sh'
    
    mock_dir=\$(mktemp -d)
    DEV_CACHE=\"\$mock_dir/cache\"
    
    curl() {
      local out=''
      while [[ \$# -gt 0 ]]; do
        if [[ \"\$1\" == \"-o\" ]]; then
          out=\"\$2\"
          shift 2
          continue
        fi
        shift
      done
      
      local build_tmp
      build_tmp=\$(mktemp -d)
      cat <<'SCRIPT' > \"\$build_tmp/spc\"
#!/usr/bin/env bash
if [[ \"\$1\" == \"--version\" ]]; then
  echo 'static-php-cli 2.8.5'
  exit 0
fi
exit 0
SCRIPT
      chmod +x \"\$build_tmp/spc\"
      tar -czf \"\$out\" -C \"\$build_tmp\" spc
      rm -rf \"\$build_tmp\"
      return 0
    }
    
    spc_path=\$(spc_binary)
    [ -x \"\$spc_path\" ]
    \"\$spc_path\" --version
    rm -rf \"\$mock_dir\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"baixando static-php-cli 2.8.5 para compilação local"* ]]
  [[ "$output" == *"static-php-cli 2.8.5"* ]]
}

@test "spc_binary reutiliza binario spc existente no cache sem novo download" {
  run bash -c "
    DEV_ROOT='$ROOT'
    source '$ROOT/lib/common.sh'
    source '$ROOT/tools/build-runtimes.sh'
    
    mock_dir=\$(mktemp -d)
    DEV_CACHE=\"\$mock_dir/cache\"
    mkdir -p \"\$DEV_CACHE/spc\"
    
    cat <<'SCRIPT' > \"\$DEV_CACHE/spc/spc\"
#!/usr/bin/env bash
if [[ \"\$1\" == \"--version\" ]]; then
  echo 'static-php-cli 2.8.5-cached'
  exit 0
fi
exit 0
SCRIPT
    chmod +x \"\$DEV_CACHE/spc/spc\"
    
    curl() {
      echo 'curl should not be called' >&2
      return 1
    }
    
    spc_path=\$(spc_binary)
    [ \"\$spc_path\" = \"\$DEV_CACHE/spc/spc\" ]
    \"\$spc_path\" --version
    rm -rf \"\$mock_dir\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" != *"baixando static-php-cli"* ]]
  [[ "$output" == *"static-php-cli 2.8.5-cached"* ]]
}

@test "filter_spc_extensions remove tokens invalidos e preserva extensoes validas" {
  run bash -c "
    DEV_ROOT='$ROOT'
    source '$ROOT/lib/common.sh'
    source '$ROOT/tools/build-runtimes.sh'

    input='bcmath bz2 core curl date dom lexbor mysqli opcache random spl standard uri zip'
    res=\$(filter_spc_extensions \"\$input\")
    echo \"\$res\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"bcmath"* ]]
  [[ "$output" == *"bz2"* ]]
  [[ "$output" == *"curl"* ]]
  [[ "$output" == *"dom"* ]]
  [[ "$output" == *"mysqli"* ]]
  [[ "$output" == *"opcache"* ]]
  [[ "$output" == *"zip"* ]]
  [[ "$output" != *"core"* ]]
  [[ "$output" != *"standard"* ]]
  [[ "$output" != *"date"* ]]
  [[ "$output" != *"lexbor"* ]]
  [[ "$output" != *"random"* ]]
  [[ "$output" != *"uri"* ]]
}

@test "build_php_runtime orquestra spc com pkg-config, glibc e isolamento de diretorio" {
  run bash -c '
    ROOT="$1"
    mock_dir=$(mktemp -d)
    DEV_ROOT="$mock_dir/dev"
    log_file="$mock_dir/spc_calls.log"
    mkdir -p "$DEV_ROOT/runtimes/php" "$mock_dir/wdev-runtimes/spc-bin"
    
    cat <<SCRIPT > "$mock_dir/wdev-runtimes/spc-bin/spc"
#!/usr/bin/env bash
echo "\$PWD: spc \$* (SPC_LIBC=\${SPC_LIBC:-})" >> "$log_file"
if [[ "\$1" == "--version" ]]; then
  echo "static-php-cli 2.8.5"
  exit 0
fi
if [[ "\$1" == "build" ]]; then
  mkdir -p "\$PWD/buildroot/bin"
  echo "echo 8.4.27" > "\$PWD/buildroot/bin/php"
  cp "\$PWD/buildroot/bin/php" "\$PWD/buildroot/bin/php-fpm"
  chmod +x "\$PWD/buildroot/bin/php" "\$PWD/buildroot/bin/php-fpm"
  exit 0
fi
exit 0
SCRIPT
    chmod +x "$mock_dir/wdev-runtimes/spc-bin/spc"

    WDEV_BUILD_DIR="$mock_dir/wdev-runtimes"
    export WDEV_BUILD_DIR DEV_ROOT

    source "$ROOT/lib/common.sh"
    source "$ROOT/tools/build-runtimes.sh"

    build_php_runtime 8.4 0 1

    cat "$log_file"
    [ -f "$DEV_ROOT/runtimes/php/php-8.4.27-linux-x86_64.tar.xz" ]
    rm -rf "$mock_dir"
  ' _ "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"install-pkg pkg-config (SPC_LIBC=glibc)"* ]]
  [[ "$output" == *"download --with-php=8.4.27 "* ]]
  [[ "$output" == *"build --build-cli --build-fpm"*"opcache"* ]]
  [[ "$output" == *"runtime salvo em runtimes/php/php-8.4.27-linux-x86_64.tar.xz"* ]]
}

@test "compile_runtime rele o manifesto reescrito pelo build antes de instalar" {
  local fake_root="$BATS_TEST_TMPDIR/root"
  mkdir -p "$fake_root/tools" "$fake_root/runtimes"
  cat > "$fake_root/tools/build-runtimes.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo 'PHP_RUNTIME_SHA256="sha-novo"' > "$DEV_ROOT/runtimes/manifest.sh"
SCRIPT
  chmod +x "$fake_root/tools/build-runtimes.sh"

  run bash -c '
    DEV_ROOT="$2"; export DEV_ROOT
    source "$1/lib/common.sh"
    source "$1/lib/runtime.sh"
    PHP_RUNTIME_SHA256="sha-antigo"
    install_runtime() { echo "sha=$PHP_RUNTIME_SHA256"; }
    compile_runtime php 8.5
  ' _ "$ROOT" "$fake_root"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sha=sha-novo"* ]]
}

# Roda build_php_runtime 8.4 com um spc falso. O binário "compilado" informa a
# versão $1 (vazio = o spc não produz binário) e o spc build termina com o status
# $2. $3 é a glibc do manifesto e $4 o símbolo de glibc gravado no binário.
run_mock_build() {
  local reported="$1" build_status="$2" glibc_floor="${3:-}" symbol="${4:-}"
  MOCK_DIR="$BATS_TEST_TMPDIR/mock"
  mkdir -p "$MOCK_DIR/dev/runtimes/php" "$MOCK_DIR/build/spc-bin"
  cat > "$MOCK_DIR/build/spc-bin/spc" <<SCRIPT
#!/usr/bin/env bash
if [[ "\$1" == "build" && -n "$reported" ]]; then
  mkdir -p "\$PWD/buildroot/bin"
  printf '#!/usr/bin/env bash\n# %s\necho %s\n' "$symbol" "$reported" > "\$PWD/buildroot/bin/php"
  cp "\$PWD/buildroot/bin/php" "\$PWD/buildroot/bin/php-fpm"
  chmod +x "\$PWD/buildroot/bin/php" "\$PWD/buildroot/bin/php-fpm"
fi
[[ "\$1" == "build" ]] && exit $build_status
exit 0
SCRIPT
  chmod +x "$MOCK_DIR/build/spc-bin/spc"

  run bash -c '
    ROOT="$1" PHP_RUNTIME_GLIBC="$2"
    DEV_ROOT="$3/dev" WDEV_BUILD_DIR="$3/build"
    export DEV_ROOT WDEV_BUILD_DIR
    source "$ROOT/lib/common.sh"
    source "$ROOT/lib/runtime.sh"
    source "$ROOT/tools/build-runtimes.sh"
    build_php_runtime 8.4 0 1
  ' _ "$ROOT" "$glibc_floor" "$MOCK_DIR"
}

@test "build_php_runtime recusa binario cuja versao difere da fixada" {
  run_mock_build 8.4.26 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"informa PHP 8.4.26, mas o alvo é 8.4.27"* ]]
  [ ! -e "$MOCK_DIR/dev/runtimes/php/php-8.4.26-linux-x86_64.tar.xz" ]
  [ ! -e "$MOCK_DIR/dev/runtimes/php/php-8.4.27-linux-x86_64.tar.xz" ]
}

@test "build_php_runtime aborta quando o spc build falha, mesmo com binario presente" {
  run_mock_build 8.4.27 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"a compilação do PHP 8.4.27 falhou"* ]]
  [ ! -e "$MOCK_DIR/dev/runtimes/php/php-8.4.27-linux-x86_64.tar.xz" ]
}

@test "build_php_runtime nao empacota binario velho de build anterior" {
  local stale
  for stale in "$BATS_TEST_TMPDIR/mock/build/php-8.4.27/buildroot/bin" "$BATS_TEST_TMPDIR/mock/build/buildroot/bin"; do
    mkdir -p "$stale"
    printf '#!/usr/bin/env bash\necho 8.4.27\n' > "$stale/php"
    cp "$stale/php" "$stale/php-fpm"
    chmod +x "$stale/php" "$stale/php-fpm"
  done

  run_mock_build "" 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"não produziu os binários esperados"* ]]
  [ ! -e "$MOCK_DIR/dev/runtimes/php/php-8.4.27-linux-x86_64.tar.xz" ]
}

@test "build_php_runtime recusa binario que exige glibc acima da do manifesto" {
  run_mock_build 8.4.27 0 2.38 GLIBC_2.43
  [ "$status" -ne 0 ]
  [[ "$output" == *"exige glibc 2.43, acima da 2.38 do manifesto"* ]]
  [ ! -e "$MOCK_DIR/dev/runtimes/php/php-8.4.27-linux-x86_64.tar.xz" ]
}

@test "build_php_runtime aceita binario dentro da glibc do manifesto" {
  run_mock_build 8.4.27 0 2.38 GLIBC_2.38
  [ "$status" -eq 0 ]
  [ -f "$MOCK_DIR/dev/runtimes/php/php-8.4.27-linux-x86_64.tar.xz" ]
}
