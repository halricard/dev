#!/usr/bin/env bash
# Plugin Laravel: provisionamento do laravel-installer via Composer.

plugin_install() {
  local target_dir="$DEV_RUNTIME/laravel-installer"
  local bin="$target_dir/bin/laravel"

  mkdir -p "$target_dir"
  if [[ ! -x "$bin" ]]; then
    local php
    php="$(php_bin "$(config_get DEFAULT_PHP)")"
    mkdir -p "$target_dir/bin"
    cat > "$bin" <<'SH'
#!/usr/bin/env bash
# Wrapper do Laravel Installer via Composer.
exec composer create-project laravel/laravel "$@"
SH
    chmod +x "$bin"
  fi
  ok "instalador do Laravel pronto em $bin"
}

plugin_remove() {
  rm -rf "$DEV_RUNTIME/laravel-installer"
  ok "ferramentas do Laravel removidas"
}
