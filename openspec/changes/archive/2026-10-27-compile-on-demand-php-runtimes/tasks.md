# Tasks

## 1. Ferramenta de Compilação Estática Local a partir do Fonte Oficial

- [x] 1.1 Implementar `tools/build-runtimes.sh` com suporte a compilação do PHP (CLI + FPM) para séries parametrizadas (ex: `8.4`, `8.5`) via `static-php-cli` e fontes oficiais, linkando as 47 extensões padrão contra glibc e verificando que `tools/build-runtimes.sh --help` executa corretamente.
- [x] 1.2 Adicionar verificação de requisitos de compilação do sistema (`gcc`, `make`, `autoconf`, `bison`, `re2c`, etc.) no script de build, exibindo comando de instalação `apt` caso faltem dependências.
- [x] 1.3 Adicionar rotina de empacotamento que salva o tarball em `runtimes/php/php-<versão>-linux-x86_64.tar.xz`, calcula o hash SHA256 e o registra em `runtimes/manifest.sh` e `runtimes/SHA256SUMS`.
- [x] 1.4 Adicionar testes unitários em `tests/` para validar a checagem de ferramentas de build e parâmetros do script de compilação.

## 2. Manifesto e Resolução de Runtimes Multi-versão

- [x] 2.1 Estender `runtimes/manifest.sh` e `lib/runtime.sh` para suportar versões parametrizadas (`install_runtime php [versão]`), localizando o tarball local em `runtimes/php/` e validando o checksum.
- [x] 2.2 Atualizar `lib/runtime.sh` para expor função de compilação de runtime (`compile_runtime php <versão>`) que orquestra o build local e sua extração imediata para `~/.dev/runtime/php/<versão>`.
- [x] 2.3 Validar que `php_version()` e `php_bin()` em `lib/common.sh` resolvem com precisão versões como `8.4` e `8.5` no sandbox, mantendo o fallback para `DEFAULT_PHP` quando nenhuma versão for especificada.

## 3. Prompt Interativo no Ciclo de Vida de Projetos

- [x] 3.1 Atualizar `ensure_php()` em `lib/project.sh` para que, ao constatar a ausência da versão do PHP solicitada pela receita ou pelo `dev.conf`, consulte o usuário interativamente: `"O <title> pede PHP <series>, que ainda não foi compilado para este dev. Deseja compilar agora a partir do fonte oficial? [S/n]"`.
- [x] 3.2 Implementar a execução do fluxo de compilação e extração em caso de resposta positiva do usuário, prosseguindo com a criação (`dev new`) ou subida (`dev up`) sem interrupção.
- [x] 3.3 Garantir que a recusa do usuário encerre o comando de forma limpa, sem deixar pastas parciais ou bancos órfãos, com mensagem clara de orientação.
- [x] 3.4 Escrever testes em `tests/recipes.bats` e `tests/updown.bats` simulando a interceptação e o fluxo de aceitação/recusa em `ensure_php()`.

## 4. Orquestração de Múltiplos Daemons PHP-FPM

- [x] 4.1 Atualizar `write_fpm_pools` em `lib/config.sh` para inspecionar os sites registrados em `$DEV_SITES/*` e gerar arquivos de configuração `$DEV_ETC/php/<versão>/php-fpm.conf` e `php.ini` para todas as versões em uso simultâneo.
- [x] 4.2 Atualizar `start_fpm` em `lib/services.sh` para inicializar e monitorar os daemons e sockets de todas as versões ativas (`php-fpm-8.4`, `php-fpm-8.5`), garantindo sockets `unix:$DEV_RUN/php-<versão>.sock`.
- [x] 4.3 Atualizar `stop_fpm` em `lib/services.sh` para encerrar todos os processos `php-fpm-*` e remover seus sockets e PIDs.
- [x] 4.4 Adicionar testes em `tests/services.bats` comprovando o ciclo de vida concorrente de múltiplos daemons FPM.

## 5. Validação Integrada com o Plugin Moodle

- [x] 5.1 Validar a integração ponta a ponta com o plugin Moodle (`dev new moodle teste-moodle`), certificando-se de que o prompt é disparado caso o PHP 8.4 não exista e que o Moodle é instalado com sucesso sob o socket `php-8.4.sock`.
- [x] 5.2 Executar a suíte completa de testes (`tools/test.sh`) e a verificação estática (`tools/check.sh`) para garantir paridade e ausência de regressões.
