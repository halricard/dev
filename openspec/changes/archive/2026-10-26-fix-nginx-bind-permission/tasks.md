# Tasks

## 1. Dependências de Sistema e Utilitários de Capability

- [x] 1.1 Incluir `libcap2-bin` na lista `APT_MIN` em `lib/install.sh` e validar que `apt_missing` identifica o pacote se desinstalado.
- [x] 1.2 Implementar funções auxiliares de detecção (`has_net_bind_capability`) e concessão (`grant_net_bind_capability`) para o binário do nginx em `lib/runtime.sh`, com tratamento para `getcap`/`setcap` e integração com `PENDING`.

## 2. Integração no Fluxo de Instalação e Inicialização

- [x] 2.1 Conectar a concessão de capability em `lib/install.sh` durante `install_own_runtime` ou configuração do runtime do nginx, registrando instrução em `PENDING` caso o `sudo` não esteja disponível.
- [x] 2.2 Atualizar `start_nginx` em `lib/services.sh` para verificar a permissão de porta privilegiada e fornecer mensagem de orientação clara caso o nginx falhe por `cap_net_bind_service` ausente.

## 3. Diagnóstico e Autocura (Doctor e Fix)

- [x] 3.1 Adicionar checagem de capability do nginx em `cmd_doctor` (`lib/doctor.sh`), emitindo aviso e dica de solução se a capability não estiver presente.
- [x] 3.2 Implementar passo de recuperação no `cmd_fix` (`lib/fix.sh`) para restaurar `cap_net_bind_service=+ep` no binário do nginx quando ausente.

## 4. Testes Automatizados e Portão de Qualidade

- [x] 4.1 Adicionar testes BATS para as funções de capability, diagnóstico do doctor e detecção de dependências.
- [x] 4.2 Executar `./tools/check.sh` e garantir que o repositório passe com sucesso em todas as validações (sintaxe, shellcheck, identificadores banidos e suíte de testes).
