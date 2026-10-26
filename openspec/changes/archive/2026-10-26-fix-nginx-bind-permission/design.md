# Design

## Context

O `dev` gerencia daemons locais (nginx, MySQL, PHP-FPM, Mailpit) sob a conta do usuário corrente, sem Docker e sem systemd. O nginx é distribuído como um binário estático extraído em `$DEV_RUNTIME/nginx/<version>/sbin/nginx` e configurado para escutar nas portas padrão 80 (HTTP) e 443 (HTTPS) para permitir URLs limpas (como `http://projeto.localhost`).

No Linux (incluindo WSL2), portas abaixo de 1024 são restritas pelo kernel. Um processo não-root é impedido com `13: Permission denied` ao tentar abrir essas portas a menos que o executável possua a Linux capability `cap_net_bind_service=+ep` ou que o sysctl `net.ipv4.ip_unprivileged_port_start` seja ajustado.

Atualmente, `lib/install.sh` gerencia privilégios `sudo` via `warm_sudo` para pacotes `apt` e confiança de autoridade CA (`mkcert`), mas não atribui a capability necessária ao binário do nginx nem garante a presença de `setcap`.

## Goals / Non-Goals

**Goals:**
- Garantir a presença do pacote `libcap2-bin` nas dependências mínimas do sistema (`APT_MIN`).
- Atribuir automaticamente a capability `cap_net_bind_service=+ep` ao executável do nginx durante o `dev install`.
- Reutilizar a sessão sudo ativa de `warm_sudo` ou enfileirar em `PENDING` caso a execução sudo não-interativa não seja possível.
- Integrar diagnóstico de verificação de permissão de bind no `dev doctor`.
- Adicionar ação de autocura no `dev fix` para restaurar a capability se ela for perdida.
- Preservar as convenções estritas do repositório: prosa e mensagens em português brasileiro, identificadores em inglês, sem identificadores banidos e aderência às regras do `tools/check.sh`.

**Non-Goals:**
- Executar o nginx como usuário `root` (quebraria a propriedade dos logs, pidfiles e sockets em `$DEV_HOME`).
- Alterar as portas padrão para portas não-privilegiadas (como 8080/8443), pois isso quebraria o padrão de vhosts limpos sem porta na URL.
- Modificar o sysctl `net.ipv4.ip_unprivileged_port_start` no sistema operacional hospedeiro, evitando alterações de segurança globais fora do escopo da aplicação.

## Decisions

### Decisão 1: Utilização de Linux File Capabilities (`cap_net_bind_service=+ep`)

- **Escolha**: Aplicar `cap_net_bind_service=+ep` diretamente no executável do nginx através do comando `setcap`.
- **Justificativa**: Concede estritamente a permissão de escutar em portas privilegiadas (< 1024) para o binário do nginx sem conceder privilégios de superusuário ou alterar a execução do processo como usuário normal. O atributo estendido (`security.capability`) é persistido no filesystem ext4 e não se perde entre reinicializações da máquina ou do WSL2.
- **Alternativas consideradas**:
  - *sysctl `net.ipv4.ip_unprivileged_port_start=80`*: Requer modificação de `/etc/sysctl.d/`, afeta todos os usuários e daemons do sistema operacional de forma ampla e nem sempre se comporta de maneira previsível em instâncias de containers ou WSL2.
  - *authbind*: Exige instalação de pacote adicional e configuração por porta em `/etc/authbind/`, além de encapsular a execução em scripts auxiliares.

### Decisão 2: Inclusão de `libcap2-bin` em `APT_MIN`

- **Escolha**: Adicionar `libcap2-bin` ao array `APT_MIN` em `lib/install.sh`.
- **Justificativa**: Garante que o utilitário `setcap` e `getcap` estejam disponíveis no sistema operacional base antes da extração do runtime.

### Decisão 3: Criação de rotinas dedicadas `ensure_nginx_capabilities` e `has_net_bind_capability`

- **Escolha**: Implementar em `lib/runtime.sh` (ou biblioteca apropriada) funções para testar se o binário já tem a capability (`getcap`) e para aplicá-la (`setcap`) com fallback amigável para `sudo`.
- **Justificativa**: Centraliza a lógica de inspeção e concessão tanto para o fluxo de instalação (`dev install`) quanto para o fluxo de reparo (`dev fix`) e diagnóstico (`dev doctor`).

## Risks / Trade-offs

- **[Risco] Filesystem sem suporte a xattr ou montagem com flag restritiva (`nosuid`/`nodev`)**
  → *Mitigação*: `dev doctor` valida a leitura das capabilities via `getcap` e emite aviso explícito caso a capability não tenha sido gravada com sucesso.
- **[Risco] Instalação executada sem terminal interativo e sem sudo cached**
  → *Mitigação*: Se o comando `sudo setcap` falhar sem senha, a instrução exata é adicionada ao array `PENDING` para exibição final ao usuário, impedindo que a instalação finalize silenciosamente com falha de inicialização do serviço.
