# Proposal

## Why

A pilha base do `dev` padroniza o PHP 8.5 para o core da máquina e para a maioria dos projetos (WordPress, Laravel). No entanto, aplicações legadas ou com ciclos de lançamento específicos como o Moodle (branch 502/LTS) requerem estritamente o PHP 8.4 e recusam a execução em PHP 8.5.

Atualmente, o repositório só distribui o binário do PHP 8.5 em `runtimes/php/` e o comando `dev new moodle` falha imediatamente ao verificar que o PHP 8.4 não está instalado. Além disso, as diretrizes do projeto proíbem o download de binários arbitrários de repositórios públicos terceiros. É necessário que o `dev` ofereça suporte à compilação local sob demanda do PHP a partir de fontes oficiais e permita a convivência de múltiplos daemons PHP-FPM para projetos simultâneos.

## What Changes

- **Detecção e Prompt Interativo de Compilação**: Ao criar (`dev new`) ou subir (`dev up`) um projeto que exige uma versão específica do PHP não presente no sandbox (`~/.dev/runtime/php/<versão>`) nem em `runtimes/php/`, o CLI pergunta interativamente ao usuário se deseja compilar a versão necessária a partir das fontes oficiais.
- **Compilação Local a partir do Fonte Oficial**: Adição da capacidade de compilação local (utilizando `tools/build-runtimes.sh php <versão>` baseado no `static-php-cli` / fontes oficiais do PHP), gerando binários estáticos x86_64 compatíveis com glibc, com o mesmo conjunto padrão de extensões e sem SQLite.
- **Armazenamento e Reutilização em `runtimes/php/`**: Após a compilação, o pacote `.tar.xz` é salvo no diretório `runtimes/php/`, seu sha256 é registrado no manifesto/SHA256SUMS do repositório, e o runtime é extraído para `~/.dev/runtime/php/<versão>`, ficando imediatamente disponível para outros projetos sem recompilação.
- **Gerenciamento de Múltiplos Daemons PHP-FPM**: Atualização dos scripts de serviços e vhosts para instanciar e gerenciar pools e daemons individuais do PHP-FPM por versão em uso (ex: `php-fpm-8.4` e `php-fpm-8.5`), garantindo sockets dedicados (`php-8.4.sock`, `php-8.5.sock`) e isolamento completo entre projetos.
- **Preservação do Padrão da Máquina**: A versão padrão global da máquina (`DEFAULT_PHP`) continua sendo a versão central (8.5), enquanto projetos individuais declaram sua versão em `dev.conf` (`PHP="8.4"`).

## Capabilities

### Modified Capabilities

- `environment-core`: Gerenciamento de runtimes estáticos e múltiplos serviços PHP-FPM; inclusão do fluxo de compilação local de runtimes a partir do fonte oficial e suporte a múltiplos daemons `php-fpm-<versão>`.
- `project-lifecycle`: Interceptação em `ensure_php` durante `dev new` e `dev up` para oferecer prompt interativo de compilação quando a versão solicitada pelo projeto não estiver instalada.
- `application-plugins`: Garantia de compatibilidade do plugin Moodle com o fluxo interativo de compilação e execução sob PHP 8.4.

## Impact

- **CLI e UX**: `dev new moodle` e `dev up` deixam de abortar bruscamente quando o PHP 8.4 estiver ausente, passando a guiar o desenvolvedor com pergunta interativa `[S/n]`.
- **Serviços**: `dev start`, `dev stop` e `dev status` passam a reconhecer e controlar múltiplos daemons `php-fpm-<versão>` ativos em conformidade com os vhosts registrados.
- **Dependências de Build**: Compilar runtimes sob demanda requer ferramentas de compilação no sistema operacional (`gcc`, `make`, etc.), que serão validadas antes do build com mensagens diagnósticas caso faltem pacotes.
