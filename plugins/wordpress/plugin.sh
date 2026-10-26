#!/usr/bin/env bash
# Plugin WordPress: provisionamento da ferramenta oficial WP-CLI.

plugin_install() {
  local target_dir="$DEV_RUNTIME/wp-cli"
  local target="$target_dir/wp-cli.phar"
  local version="${WPCLI_VERSION:-2.12.0}"

  mkdir -p "$target_dir"
  if [[ ! -f "$target" ]]; then
    local file
    file="$(download "$(url_for wpcli "$version")" "$(cache_name wpcli "$version")")"
    cp "$file" "$target"
    chmod +x "$target"
  fi

  # Cria atalho no DEV_BIN
  mkdir -p "$DEV_BIN"
  cat > "$DEV_BIN/wp" <<'SH'
#!/usr/bin/env bash
# Atalho WP-CLI gerado pelo dev.
exec php -d error_reporting="E_ALL & ~E_DEPRECATED & ~E_USER_DEPRECATED" \
  "$DEV_RUNTIME/wp-cli/wp-cli.phar" "$@"
SH
  chmod +x "$DEV_BIN/wp"
  ok "WP-CLI $version pronto em $target"
}

plugin_remove() {
  rm -f "$DEV_BIN/wp"
  rm -rf "$DEV_RUNTIME/wp-cli"
  ok "ferramentas do WordPress removidas"
}
