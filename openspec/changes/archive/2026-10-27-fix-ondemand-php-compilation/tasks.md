# Tasks

## 1. Saneamento e Filtragem de Extensões do PHP

- [x] 1.1 Criar função auxiliar `filter_spc_extensions()` em `tools/build-runtimes.sh` que converte a lista de extensões separada por espaços ou vírgulas e remove palavras-chave não suportadas pelo `spc build` (`core`, `standard`, `date`, `lexbor`, `random`, `uri`), retornando uma lista delimitada por vírgulas pronta para o `spc`
- [x] 1.2 Adicionar testes unitários em `tests/build_runtimes.bats` validando que `filter_spc_extensions` remove corretamente todos os tokens built-in/inválidos e preserva as extensões válidas como `bcmath`, `curl`, `intl`, `mysqli`, `pdo_mysql`, etc.

## 2. Configuração do Ambiente e Pacote Interno do pkg-config

- [x] 2.1 Atualizar `build_php_runtime()` em `tools/build-runtimes.sh` para exportar `SPC_LIBC=glibc`, garantindo que o `static-php-cli` selecione o `GccNativeToolchain` nativo com `gcc` e `g++` em vez do `MuslToolchain`
- [x] 2.2 Inserir a chamada `"$spc" install-pkg pkg-config` no diretório de compilação antes de iniciar o build, atendendo aos requisitos do utilitário `PkgConfigUtil` do `spc`
- [x] 2.3 Atualizar o download de fontes para invocar `"$spc" download --with-php="$series" --for-extensions="$exts_comma" --prefer-pre-built` (ou fontes compatíveis), redirecionando a saída para arquivo de log em `$work_dir/download.log` em vez de descartar com `/dev/null`

## 3. Isolamento do Diretório de Build e Empacotamento

- [x] 3.1 Modificar o fluxo de execução em `build_php_runtime()` para garantir navegação explícita para o diretório isolado `$work_dir` (`/tmp/wdev-runtimes/php-$version`) antes de rodar os comandos do `spc`, preservando e restaurando o diretório de chamada
- [x] 3.2 Executar `"$spc" build --build-cli --build-fpm "$exts_comma"` redirecionando a saída para `$work_dir/build.log` e, caso a execução retorne código diferente de zero, exibir mensagem de aviso com a localização do log de erro
- [x] 3.3 Atualizar a busca de binários gerados para inspecionar primariamente `$work_dir/buildroot/bin/php` e `$work_dir/buildroot/bin/php-fpm` (com fallback para `$BUILD_DIR/buildroot` e `$work_dir`), procedendo ao empacotamento em `runtimes/php/php-$version-linux-x86_64.tar.xz`
- [x] 3.4 Validar simulação de compilação com `tools/build-runtimes.sh php 8.4 --plan` e verificar que o plano reflete o empacotamento correto

## 4. Testes de Integração e Verificação com dev new

- [x] 4.1 Adicionar testes BATS em `tests/build_runtimes.bats` simulando o fluxo de compilação com mocks de `spc` para verificar se `install-pkg pkg-config`, `cd "$work_dir"`, `SPC_LIBC=glibc` e `package_php_runtime` são invocados com os parâmetros e caminhos esperados
- [x] 4.2 Executar a suíte de testes `npx bats tests/build_runtimes.bats` garantindo 100% de sucesso sem regressões
- [x] 4.3 Testar a criação de projeto Moodle com `dev new moodle ead` (ou simulação controlada da compilação do PHP 8.4) confirmando que a compilação do runtime não falha e prossegue com a criação do ambiente

## Workflow follow-up

- Arquivar o change após a aprovação da implementação e testes com `/opsx-archive`.
