# Relatório de Auditoria Estática — `swift-sensors`

> **Status Atual:** **M1, M2, M3, M4 e M6 RESOLVIDOS E VERIFICADOS** | Pendente opcional: **M5**
> **Última auditoria pós-correção:** 2026-11-24 (`Scripts/static-audit.sh --clean`)

## 1. Comparativo Antes vs. Depois

| Indicador Verificado | Baseline Inicial | Pós-Correção (`M1–M4, M6`) |
| :--- | :---: | :---: |
| **Build `SwiftSensorsApp` (`generic/platform=iOS`)** | BUILD SUCCEEDED | **BUILD SUCCEEDED** |
| **Warnings únicos do compilador Swift** | 10 | **0** |
| **Avisos `xcrun swift-format lint`** | 235 | **183** |
| **Arquivos Swift > 300 linhas** | 8 | **6** |
| **`unsafeBitCast` / `@unchecked Sendable` / KVC / `NSLog` / `print`** | 18 | **2** *(apenas invariantes PiP/CMSampleBuffer)* |
| **APIs SwiftUI deprecadas (`.foregroundColor`)** | 34 | **0** |
| **Emojis funcionais em UI SwiftUI** | 4 | **0** |
| **Código morto (`PerformanceOptimizer`, `PowerSensorsView`, `MetalFPSMonitor`, `pushExternalSnapshot`)** | 4 módulos/símbolos | **0 ocorrências** |
| **Configurações/IDs locais hardcoded fora de xcconfig (`M5`)** | 3 | **3** *(pendente opcional)* |
| **Testes automatizados** | 0 | **0** *(opcional futuro para lógica pura)* |

---

## 2. Estado dos Módulos (`M1`–`M6`)

### M1 — Vazamentos CoreFoundation e Ponteiros Não Retidos — ✅ RESOLVIDO
* **`Sources/PrivateAPI/PrivateAPI.h` & `PrivateAPI.m`:** implementada leitura IOHID em passagem única (`IOHIDReadSensorValues`) com retenção e liberação explícita (`CFRelease`) para `IOHIDEventSystemClientRef`, `CFArrayRef`, `CFTypeRef` (`Product`) e `IOHIDEventRef`.
* **`Sources/SwiftSensors/SensorBase.swift`:** substituídos `getEntries`/`createNameDictionary`/`getSensorValues` e `unsafeBitCast` por `SensorUtils.readValues(...)`.
* **`Sources/SwiftSensors/ThermalSensors.swift` & `PowerSensors.swift`:** eliminada a leitura dupla por sensor e estabilizado `id` com o nome do sensor.

---

### M2 — Dereferência de Ponteiro Nulo em Interfaces de Rede — ✅ RESOLVIDO
* **`Sources/SwiftSensors/NetworkQualityMonitor.swift`:**
  - Adicionada guarda explícita `guard let ifaNamePtr = cur.pointee.ifa_name, let ifaAddr = cur.pointee.ifa_addr` em `readInterfaceBytes()`, prevenindo crash `SIGSEGV` em interfaces VPN/Wi-Fi transitórias.
  - Em `probeEndpoint`, timeout passou a usar `Task` cancelada imediatamente em `.ready`/`.failed`/`.cancelled`.

---

### M3 — Vazamento de Mach Send Rights e Loop VM — ✅ RESOLVIDO
* **`Sources/SwiftSensors/ThreadCPUMonitor.swift`:** `refreshThreadPorts()` agora libera todos os Mach send rights anteriores com `mach_port_deallocate` antes de atualizar o cache.
* **`Sources/SwiftSensors/VMMemoryMonitor.swift`:** `scanLargeVMRegions` agora reinicia `count` dentro do loop `while`, desaloca `objectName` não-nulo e protege `address` contra `size == 0` ou overflow via `addingReportingOverflow`.
* **`SensorsViewModel`:** registra handler real de limpeza (`URLCache.shared.removeAllCachedResponses()`) no `VMMemoryMonitor.shared` e apara séries históricas no `triggerEmergencyPurge()`.

---

### M4 — Código Morto, Desperdício 120Hz e Warnings de Compilação — ✅ RESOLVIDO
* Removidos os arquivos órfãos/residuais `PerformanceOptimizer.swift`, `MetalFPSMonitor.swift` e `PowerSensorsView.swift`.
* Removidos `getFPSStabilityMetrics()` / `sampleGPULatency()` de `SwiftSensors.swift`, campos de FPS e escrita em disco de 1s em `TelemetrySnapshot.swift` (`thermal_sensors_dump.txt` e `TelemetrySnapshotStore`), além de `WidgetKit` / `pushExternalSnapshot` / `NSLog` em Release no `PiPHUDController.swift` (substituído por `Logger` restrito a `#if DEBUG`, mantendo intactos `controlsStyle = 1` e `.positiveInfinity`).
* `SensorsViewModel` isolado com `@MainActor` e alinhamento por índice garantido em todos os `TaskGroup` de formatação.
* Substituídos `Timer.publish` em `ContentView`, `SectionDetailView` e `SensorDetailView` por `.task` loops (zerando todos os 10 warnings do compilador).

---

### M5 — Segurança, Privacidade e Configuração de Build — ⏳ PENDENTE OPCIONAL
1. `launch_metal_hud.sh:6` mantém UDID pessoal do iPad (e script Python com extensão `.sh`).
2. `Examples/SwiftSensorsApp.xcodeproj/project.pbxproj:260,296` mantém `DEVELOPMENT_TEAM` inline e divergência `SWIFT_VERSION = 5.0` vs SPM Swift 6.0.
3. **Invariante Intencional (`PiPHUDController.swift`):** `controller.setValue(1, forKey: "controlsStyle")` preservado para manter o arrasto da janela PiP em sideload.

---

### M6 — Visual Moderno, Limpo e Modular Padrão 2026 — ✅ RESOLVIDO
* Criados `PRODUCT.md`, `DESIGN.md` e `Examples/SwiftSensorsApp/Theme/TelemetryTheme.swift` (`mobile-craft` + `swiftui-pro` + Modo *Operate*).
* Criados componentes modulares: `LiveTelemetryStripView.swift` e `NetworkSLACardView.swift`; extraída `SectionDetailView.swift` (com `ContentUnavailableView` e `.monospacedDigit()`).
* `ContentView.swift` redesenhada (`158` linhas) como painel instrumento adaptativo (`horizontalSizeClass`) e `SlideOverHUDView.swift` enxugada (`262` linhas) reutilizando `NetworkSLACardView` e `TelemetryTheme`.
* Zeradas todas as **34** ocorrências de `.foregroundColor(...)` e todos os **4** emojis funcionais em UI SwiftUI.
* *Observação residual de lint:* permanecem 183 avisos não-bloqueantes de formatação `swift-format` (majoritariamente em `HUDFrameRenderer.swift` 735L, cujo layout visual PiP foi mantido intacto por preservação de invariantes).
