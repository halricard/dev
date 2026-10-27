# Design

## Context

O `dev` foi projetado para executar PHP e Nginx de forma nativa e estática no Linux/WSL2, sem recorrer a contêineres Docker. O repositório armazena tarballs pré-compilados em `runtimes/` (atualmente PHP 8.5.12 e Nginx 1.30.5).

Projetos como Moodle 502/LTS exigem PHP 8.4 e falham terminantemente no PHP 8.5. A política do projeto veda o download de binários arbitrários de repositórios públicos terceiros: qualquer runtime precisa ser compilado localmente a partir das fontes oficiais do PHP, mantendo as 47 extensões estáticas padronizadas e compatibilidade com a glibc do sistema.

Para suportar múltiplos projetos simultâneos (ex: WordPress em PHP 8.5 e Moodle em PHP 8.4), o `dev` precisa ser capaz de:
1. Detectar versões ausentes no fluxo de criação/execução.
2. Perguntar no CLI e orquestrar a compilação local sob demanda a partir do código-fonte oficial.
3. Salvar o tarball em `runtimes/php/` e instalá-lo no sandbox `~/.dev/runtime/php/<versão>`.
4. Gerenciar múltiplos daemons do PHP-FPM em simultâneo.

## Goals / Non-Goals

**Goals:**
- Fornecer ferramenta e fluxo de compilação estática (`tools/build-runtimes.sh php <versão>`) baseada no `static-php-cli` e fontes oficiais do PHP (php.net).
- Interceptar a falta da versão em `ensure_php()` com prompt interativo `[S/n]` no CLI durante `dev new` e `dev up`.
- Armazenar o artefato compilado em `runtimes/php/php-<versão>-linux-x86_64.tar.xz` e extrair para o sandbox, tornando-o reutilizável para qualquer projeto subsequente sem recompilar.
- Atualizar `services.sh` e `config.sh` para suportar múltiplos daemons `php-fpm-<versão>` concorrentes (com sockets `php-<versão>.sock` dedicados) com base nos sites ativos.
- Manter o PHP 8.5 como o padrão inalterado da máquina (`DEFAULT_PHP`).

**Non-Goals:**
- Baixar binários pré-compilados de terceiros ou gerados fora da máquina.
- Mudar a versão padrão global da máquina para 8.4.
- Adicionar dependências de sistema pesadas ou desnecessárias em tempo de execução (o binário gerado continua estático).

## Decisions

### 1. Compilação Local Baseada em `tools/build-runtimes.sh` e `static-php-cli`
- **Decisão**: Utilizar o `static-php-cli` (`spc`) com build estático direcionado à glibc do sistema, emulando exatamente o pipeline com o qual o PHP 8.5.12 existente foi construído. O build baixa fontes oficiais do PHP e de suas bibliotecas dependentes (OpenSSL, ICU, curl, etc.) e linka os binários `php` e `php-fpm`.
- **Alternativas consideradas**:
  - *Instalar via pacotes do sistema (`ppa:ondrej/php` ou `apt`)*: Rejeitado porque introduz dependências globais na distribuição hospedeira, requer privilégios de root para cada versão e quebra o modelo de sandbox isolado em `~/.dev`.
  - *Download de binários externos prontos*: Rejeitado expressamente pela diretriz do usuário de compilar a partir da fonte oficial.

### 2. Prompt Interativo em `ensure_php`
- **Decisão**: Em `lib/project.sh`, quando `ensure_php "$series" "$title"` verificar que nem o sandbox `~/.dev/runtime/php` nem `runtimes/php/` possuem a versão necessária:
  1. O CLI exibe mensagem informando que a aplicação requer a versão específica (ex: 8.4).
  2. Pergunta ao usuário: `"O $title requer PHP $series, que ainda não foi compilado. Deseja compilar agora a partir do fonte oficial? (Isso pode levar alguns minutos) [S/n]"`.
  3. Se aceito, chama o processo de compilação com feedback de progresso, salva o tarball em `runtimes/php/`, extrai para o sandbox e continua a operação (`dev new` ou `dev up`).
  4. Se rejeitado (ou em ambiente não-interativo sem confirmação), aborta com orientações claras.
- **Alternativas consideradas**:
  - *Apenas exibir erro instruindo a compilar manualmente*: Rejeitado porque cria fricção desnecessária e obriga o desenvolvedor a interromper e reiniciar o comando `dev new`.

### 3. Manifesto e Descoberta de Runtimes Multi-versão
- **Decisão**: O `runtimes/manifest.sh` manterá a declaração de compatibilidade da glibc e extensões esperadas, e passará a suportar resolução de versões dinâmicas ou mapeamento para versões conhecidas (8.4.x, 8.5.x). Ao compilar uma nova versão, seu hash é calculado e atualizado no manifesto ou `SHA256SUMS`.
- **Alternativas consideradas**:
  - *Múltiplos manifestos separados*: Rejeitado para manter `runtimes/manifest.sh` como fonte única da verdade para runtimes do repositório.

### 4. Orquestração de Múltiplos Daemons PHP-FPM
- **Decisão**: 
  - `write_fpm_pools` e `start_fpm`: Em vez de gerenciar apenas `$(php_version "")`, o sistema inspeciona os vhosts e projetos ativos em `$DEV_SITES` e identifica a lista de versões PHP distintas em uso (além do padrão da máquina).
  - Para cada versão PHP necessária, gera sua configuração `$DEV_ETC/php/<versão>/php-fpm.conf` com PID `$DEV_RUN/php-fpm-<versão>.pid` e socket `$DEV_RUN/php-<versão>.sock`.
  - `start_fpm` sobe todos os daemons necessários e `stop_fpm` encerra todos os processos `php-fpm-*` correspondentes.
- **Alternativas consideradas**:
  - *Um único daemon FPM alternando versão*: Inviável no PHP-FPM, pois cada daemon é compilado em sua respectiva versão binária.
  - *Subir o FPM de versões secundárias sob demanda*: Pode causar atraso nas requisições Nginx; subir na inicialização do serviço ou no `dev up` garante resposta imediata.

## Risks / Trade-offs

- **[Risco] Tempo de compilação da primeira vez (15-20 minutos)** → *Mitigação*: Informar previamente no prompt que o processo leva alguns minutos; exibir barra ou indicador de progresso com logs direcionados a arquivo de log (`$DEV_LOG/build-php-<versão>.log`); após a primeira compilação, o tarball fica salvo em `runtimes/php/` e nunca mais precisará ser recompilado nesta máquina ou em outros clones que compartilhem o diretório.
- **[Risco] Falta de ferramentas de compilação no sistema operacional hospedeiro** → *Mitigação*: O script verifica antecipadamente a presença de `gcc`, `make`, `autoconf`, `bison`, etc. Se faltarem, emite aviso claro recomendando o comando `sudo apt install ...` para suprir as dependências antes de iniciar o build.
- **[Risco] Múltiplos daemons PHP-FPM consumindo memória** → *Mitigação*: Cada pool de desenvolvimento pode ser configurado com `pm = ondemand` ou `pm.max_children` reduzido para evitar consumo excessivo de RAM quando o site não estiver recebendo requisições.
