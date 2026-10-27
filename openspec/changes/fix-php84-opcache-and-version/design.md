# Design

## Context

Ao compilar o PHP 8.4 sob demanda para o plugin Moodle via `tools/build-runtimes.sh`, duas falhas ocorrem:
1. `PHP_STANDARD_EXTENSIONS` omite a extensão `opcache`. Ao compilar com `static-php-cli` (`spc`), o binário resultante não inclui `Zend OPcache`. A rotina `runtime_verify` em `lib/runtime.sh` valida estritamente `php -v | grep 'Zend OPcache'`, abortando a instalação.
2. `lib/runtime.sh` e `tools/build-runtimes.sh` possuem a string fixa `8.4.6` para mapear a série `8.4`. No entanto, o `static-php-cli` baixa os fontes oficiais mais recentes da série, compilando o PHP 8.4.27. O sistema então tenta empacotar e gerenciar o binário 8.4.27 sob o nome obsoleto de 8.4.6.

## Goals / Non-Goals

**Goals:**
- Incluir `opcache` na compilação do PHP via `spc` e validar que o binário compilado possui `Zend OPcache` habilitado.
- Atualizar a resolução estática da série `8.4` para `8.4.27` em todos os scripts e testes.
- Tornar o empacotamento (`package_php_runtime`) inteligente o suficiente para detectar a versão real a partir de `php -r 'echo PHP_VERSION;'` nos binários gerados.
- Garantir que `dev new moodle <nome>` execute perfeitamente com PHP 8.4.27 sem queixas de OPcache ou interrupções de versão.

**Non-Goals:**
- Não alterar a versão padrão do ambiente (`PHP 8.5.12`), mantendo 8.4 restrito aos projetos e receitas que expressamente o requisitam (como Moodle).
- Não alterar o mecanismo estático do `spc` nem introduzir compilação dinâmica com arquivos `.so` compartilhados; o OPcache continuará compilado estaticamente no binário.

## Decisions

### Decisão 1: Adicionar `opcache` na lista de compilação do `spc`
- **Abordagem**: Em `tools/build-runtimes.sh`, adicionar `opcache` em `PHP_STANDARD_EXTENSIONS` e garantir que `filter_spc_extensions` preserve `opcache`.
- **Justificativa**: `static-php-cli` suporta nativamente a compilação do `opcache` como módulo integrado ao binário CLI e FPM.
- **Alternativa rejeitada**: Tentar compilar o opcache como extensão dinâmica `.so`. Isso quebraria a premissa de distribuição do `dev` com runtimes estáticos e autocontidos sem dependência de bibliotecas externas no filesystem.

### Decisão 2: Atualizar resolução de versão da série 8.4 para `8.4.27`
- **Abordagem**: Atualizar `lib/runtime.sh` (`runtime_version`) e `tools/build-runtimes.sh` (`resolve_php_version`) de `8.4.6` para `8.4.27`.
- **Justificativa**: 8.4.27 é a versão real fornecida pelo upstream oficial do PHP 8.4 e pelo `static-php-cli` em 2026. Manter 8.4.6 cria incompatibilidade com o binário real compilado.

### Decisão 3: Detecção de versão a partir do binário compilado
- **Abordagem**: No método `package_php_runtime`, se `$src_dir/bin/php` existir e for executável, consultar `actual_version="$("$src_dir/bin/php" -r 'echo PHP_VERSION;' 2>/dev/null || true)"`. Se válida, utilizar `actual_version` para empacotar o arquivo final (`php-<actual_version>-linux-x86_64.tar.xz`).
- **Justificativa**: Evita divergências futuras caso a ferramenta `spc` receba atualizações de patches menores da série 8.4 ou 8.5.

## Risks / Trade-offs

- **[Risco] Recompilação necessária do tarball 8.4**: O tarball antigo em `runtimes/php/php-8.4.6-linux-x86_64.tar.xz` não possui OPcache.
  - **Mitigação**: O novo pacote será gerado com `opcache` e gravado como `runtimes/php/php-8.4.27-linux-x86_64.tar.xz`, com o respectivo hash registrado em `runtimes/SHA256SUMS`.
- **[Risco] Quebra de testes que esperam o literal "8.4.6"**:
  - **Mitigação**: Atualizar todas as suítes BATS (`tests/build_runtimes.bats`, `tests/releases.bats`, `tests/common.bats`, `tests/services.bats`, `tests/recipes.bats`) para validar `8.4.27`.
