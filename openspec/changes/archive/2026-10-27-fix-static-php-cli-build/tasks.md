# Tasks

## 1. Atualização das Dependências do Sistema (bzip2)

- [x] 1.1 Incluir `bzip2` no array centralizado `APT_BUILD_DEPS` em `lib/runtime.sh` e atualizar a documentação de requisitos em `tools/build-runtimes.sh`, verificando que `missing_build_deps` aponta `bzip2` quando ausente
- [x] 1.2 Atualizar testes em `tests/build_runtimes.bats` para validar que `APT_BUILD_DEPS` contém `bzip2` e que a contagem mínima de ferramentas é respeitada

## 2. Correção da Obtenção e Download do static-php-cli

- [x] 2.1 Atualizar `SPC_VERSION="2.8.5"` e reescrever `spc_binary()` em `tools/build-runtimes.sh` para baixar o arquivo compactado `spc-linux-x86_64.tar.gz`, extrair o executável `spc` de forma segura para o cache local, marcar permissão de execução e validar funcionamento
- [x] 2.2 Adicionar testes unitários em `tests/build_runtimes.bats` cobrindo o fluxo de download e descompactação de tarball do `spc` e a reutilização do cache existente

## 3. Ajuste de Invocação da CLI do static-php-cli

- [x] 3.1 Corrigir os parâmetros de chamada em `build_php_runtime()` em `tools/build-runtimes.sh` para utilizar `--with-php="$series"` em conformidade com a CLI do `spc`
- [x] 3.2 Executar teste de simulação `tools/build-runtimes.sh php 8.4 --plan` e verificar que a saída é estruturada, correta e livre de erros

## 4. Validação e Conformidade

- [x] 4.1 Executar a suíte completa de verificação `./tools/check.sh` garantindo aprovação em sintaxe, integridade de repositório e todos os testes BATS
- [x] 4.2 Validar conformidade das especificações com `openspec validate fix-static-php-cli-build --strict`
