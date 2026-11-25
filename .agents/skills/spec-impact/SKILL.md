---
name: spec-impact
description: Workflow Spec-Driven para gerar um Mini-Plano de Impacto antes de editar arquivos com mais de 300 linhas ou módulos compartilhados em swift-sensors.
---

# Spec-Impact — Mini-Plano Obrigatório Antes de Editar

Ative esta skill sempre que uma tarefa tocar arquivos listados em `.agents/rules/20-spec-driven-impact.md` (`> 300` linhas ou módulos centrais).

## Passo 1 — Ancoragem Rápida (Somente Leitura)
1. Confira o tamanho atual do alvo:
   ```bash
   wc -l "<arquivo-alvo>"
   ```
2. Localize todos os chamadores e dependentes dos símbolos que serão tocados:
   ```bash
   rg -n "<SimboloOuMetodo>" Sources/ Examples/
   ```
3. Leia apenas o trecho relevante da arquitetura/auditoria em `docs/ARCHITECTURE_MAP.md` e `docs/AUDIT_REPORT.md`.

## Passo 2 — Preencher o Mini-Plano de Impacto (Máx. 15 linhas)

Escreva este resumo antes da primeira chamada de edição (`edit_file` / `write_file`):

```markdown
### Mini-Plano de Impacto
- **Alvo:** `<caminho/arquivo.swift>` (`N` linhas)
- **Objetivo:** <1 frase objetiva do que muda>
- **Símbolos / Chamadores afetados:** <lista dos chamadores encontrados via rg>
- **Invariantes preservados:** <ex.: PiP controlsStyle=1, sensores PMU tdie*, sem FPS falso>
- **Risco de regressão:** <ex.: alteração de assinatura em SwiftSensors.shared ou layout canvas 2x>
- **Verificação:** `Scripts/static-audit.sh --summary` (+ lint swift-format nos alterados)
```

## Passo 3 — Execução Mínima e Cirúrgica
- Aplique a menor edição verificável possível.
- Se tocar regras de UI, valide contra `/mobile-craft` e `/swiftui-pro`.
- Nunca adicione código duplicado; reutilize helpers já encontrados no Passo 1.

## Passo 4 — Verificação Offline Obrigatória
Execute o gate padrão antes de concluir:
```bash
Scripts/static-audit.sh --summary
```
Se estiver operando em ciclo automatizado de auditoria (`M1`–`M6`), execute via `Scripts/ralph-loop.sh` para garantir rollback automático em caso de falha.
