# Proposal

## Why

Ao executar `./dev install` ou `./dev start` em Linux/WSL2 como usuário comum (não-root), o nginx falha na inicialização com o erro:
`nginx: [emerg] bind() to 127.0.0.1:80 failed (13: Permission denied)`.

Isso ocorre porque as portas 80 e 443 são portas privilegiadas (< 1024) no Linux. Como o `dev` opera sem Docker e sem systemd, executando todos os daemons sob o usuário comum, o binário estático do nginx precisa da Linux capability `cap_net_bind_service=+ep` para conseguir escutar nessas portas sem ser executado como root. Atualmente o instalador não instala o utilitário `setcap` nem atribui essa capability ao binário após a extração do runtime.

## What Changes

- Adiciona o pacote `libcap2-bin` (provedor do utilitário `setcap`) à lista de dependências mínimas do sistema (`APT_MIN`) no instalador.
- Concede a permissão `cap_net_bind_service=+ep` ao binário do nginx (`$DEV_RUNTIME/nginx/<version>/sbin/nginx`) durante a etapa de instalação/configuração do runtime, aproveitando o momento em que o sudo já está ativo (`warm_sudo`) ou registrando em `PENDING` caso não haja privilégios não-interativos.
- Adiciona verificação no `dev doctor` para checar se o binário do nginx possui a capability necessária para escutar em portas privilegiadas (< 1024), alertando caso esteja ausente.
- Adiciona rotina no `dev fix` para restaurar a capability `cap_net_bind_service` no executável do nginx se for detectada sua ausência.

## Capabilities

### Modified Capabilities

- `environment-core`: Exige o pacote `libcap2-bin` nas dependências de sistema, estabelece a atribuição de `cap_net_bind_service=+ep` ao binário do nginx para ligação nas portas 80 e 443 sem root, e inclui validação e autocura dessa permissão no `dev doctor` e `dev fix`.

## Impact

- `lib/install.sh`: Atualização da lista `APT_MIN` e inclusão da concessão de capability no binário do nginx.
- `lib/runtime.sh` / `lib/services.sh`: Funções auxiliares para verificação e aplicação da capability `cap_net_bind_service`.
- `lib/doctor.sh`: Nova verificação de permissão de bind nas portas privilegiadas.
- `lib/fix.sh`: Ação de recuperação para reaplicar capability caso perdida.
- Suíte de testes: Atualização dos testes de instalação, verificação de dependências e diagnóstico de integridade.
