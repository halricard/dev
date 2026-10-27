# Tasks

## 1. Suporte a OPcache na Compilação do PHP

- [x] 1.1 Incluir `opcache` na lista `PHP_STANDARD_EXTENSIONS` e na filtragem de extensões do `spc` em `tools/build-runtimes.sh`, garantindo que não seja descartado como built-in token
- [x] 1.2 Adicionar teste unitário em `tests/build_runtimes.bats` validando que `filter_spc_extensions` preserva `opcache` e que a invocação de compilação direcionada ao `spc` inclui `opcache`

## 2. Atualização da Resolução de Versão do PHP 8.4 para 8.4.27

- [x] 2.1 Atualizar o mapeamento de versão da série `8.4` para `8.4.27` em `lib/runtime.sh` (`runtime_version`) e `tools/build-runtimes.sh` (`resolve_php_version`)
- [x] 2.2 Implementar detecção dinâmica da versão compilada em `tools/build-runtimes.sh` (`package_php_runtime`), inspecionando `$src_dir/bin/php -r 'echo PHP_VERSION;'` antes de empacotar o tarball
- [x] 2.3 Atualizar os testes BATS em `tests/releases.bats`, `tests/common.bats`, `tests/services.bats`, `tests/recipes.bats` e `tests/build_runtimes.bats` que referenciam o literal `8.4.6` para `8.4.27`

## 3. Empacotamento do Runtime PHP 8.4.27 e Registro de Checksum

- [x] 3.1 Compilar e empacotar o runtime estático do PHP 8.4.27 com OPcache em `runtimes/php/php-8.4.27-linux-x86_64.tar.xz` e registrar o hash SHA256 em `runtimes/SHA256SUMS`
- [x] 3.2 Limpar referências e artefatos residuais da versão `8.4.6` em `runtimes/` e cache
- [x] 3.3 Executar `runtime_verify php 8.4` em teste ou ambiente local e garantir que o runtime passa sem erros e com `Zend OPcache` ativo

## 4. Validação de Integração e Conformidade

- [x] 4.1 Validar que o fluxo de provisionamento do Moodle aceita o runtime 8.4.27 e prossegue sem abortar por falta de OPcache
- [x] 4.2 Executar a suíte completa `./tools/check.sh` e validar que sintaxe, shellchecks e todos os testes BATS passam
- [x] 4.3 Validar conformidade das especificações OpenSpec através de `openspec validate fix-php84-opcache-and-version --strict`
