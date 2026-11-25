# Guia de Revisão Contínua Offline — `swift-sensors`

Este repositório opera 100% offline no macOS sem depender de GitHub Actions. Toda a esteira de governança, auditoria e proteção contra regressões está versionada em `.agents/`, `docs/` e `Scripts/`.

---

## 1. Fluxo Rápido do Dia a Dia

1. **Auditoria estática completa:**
   ```bash
   Scripts/static-audit.sh
   ```
   Use `--summary` para uma visão compacta ou `--clean` após grandes limpezas para forçar recompilação completa dos warnings do compilador Swift.

2. **Edição de módulos grandes (`> 300` linhas) ou contratos centrais:**
   - Antes de alterar arquivos como `HUDFrameRenderer.swift`, `SlideOverHUDView.swift` ou `SensorBase.swift`, execute a skill `.agents/skills/spec-impact/SKILL.md` e registre o Mini-Plano de Impacto.
   - Sempre busque helpers existentes com `rg -n "<termo>" Sources/ Examples/` antes de criar funções novas.

3. **Hooks Git automáticos (`Scripts/hooks`):**
   - Já ativados via `Scripts/install-hooks.sh` (`git config core.hooksPath Scripts/hooks`).
   - **`pre-commit`**: bloqueia arquivos locais/sensíveis (`*.db`, `*.sqlite`, `*.p12`, UDIDs/tokens no diff), executa `xcrun swift-format lint` nos `.swift` staged, valida sintaxe de `*.sh` (Python ou Bash pelo shebang) e alerta quando um `.swift` > 300 linhas é alterado.
   - **`pre-push`**: exige que o build offline `xcodebuild ... -destination "generic/platform=iOS" CODE_SIGNING_ALLOWED=NO` passe com `BUILD SUCCEEDED`.

---

## 2. Executando Correções Seguras com o Ralph Loop (`M1` → `M6`)

O script `Scripts/ralph-loop.sh` permite atacar os módulos do `docs/AUDIT_REPORT.md` um de cada vez com rollback automático caso o build quebre ou haja violação de segurança:

1. **Testar apenas o gate offline (sem alterar Git):**
   ```bash
   Scripts/ralph-loop.sh --check-only --module M1
   ```
2. **Garantir um ponto de restauração (commit de checkpoint):**
   Por segurança, o `ralph-loop.sh` **aborta** se existirem arquivos não commitados sem a flag `--create-checkpoint`. Quando quiser iniciar um ciclo limpo em um módulo:
   ```bash
   Scripts/ralph-loop.sh --module M1 --max-iterations 3 --create-checkpoint --cmd "<comando_de_correcao>"
   ```
3. **Ordem recomendada de resolução:**
   - `M1`: Vazamentos CoreFoundation (`SensorBase.swift`, `ThermalSensors.swift`, `PowerSensors.swift`)
   - `M2`: Ponteiro nulo `ifa_addr` em `NetworkQualityMonitor.swift`
   - `M3`: `mach_port_deallocate` e guarda de `vm_region_64` (`ThreadCPUMonitor`, `VMMemoryMonitor`)
   - `M4`: Código morto (`PerformanceOptimizer`, `PowerSensorsView`), `CADisplayLink` 120Hz ocioso e warnings `Combine`
   - `M5`: Parametrização de UDID em `launch_metal_hud.sh` e alinhamento Swift 6
   - `M6`: Polimento UI 2026 e fatiamento de views > 300 linhas

---

## 3. Fluxo Recomendado para Evolução Visual (Padrão 2026)

Ao evoluir a interface SwiftUI (`ContentView`, `SlideOverHUDView`, componentes de gráfico):
- Ative **`/mobile-craft`** em conjunto com **`/swiftui-pro`** e **`/polimento-ui` (Modo Operate)**.
- Troque emojis de UI por **SF Symbols**, mantenha `.monospacedDigit()` nos valores ao vivo, substitua `.foregroundColor` por `.foregroundStyle` e valide visualmente no iPad com captura real (`xcrun devicectl device capture screenshot`).
- Ao finalizar um módulo maior (`M1`..`M6`), rode **`/revisao-dupla`** localmente para auditoria independente antes do commit final.
