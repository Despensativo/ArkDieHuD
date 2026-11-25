---
trigger: always_on
---
# Workflow Spec-Driven (Mini-Plano de Impacto Obrigatório)

Antes de editar **qualquer arquivo com mais de 300 linhas** ou **qualquer módulo compartilhado**, você **DEVE** parar para mapear o impacto e registrar um **Mini-Plano de Impacto** seguindo a skill `.agents/skills/spec-impact/SKILL.md`.

## Arquivos Cobertos por Esta Regra

1. **Arquivos > 300 linhas (inventário atual):**
   - `Sources/SwiftSensors/NetworkQualityMonitor.swift` (949L)
   - `Examples/SwiftSensorsApp/HUD/HUDFrameRenderer.swift` (597L)
   - `Examples/SwiftSensorsApp/Views/Screens/NetworkDiagnosticsView.swift` (594L)
   - `Examples/SwiftSensorsApp/HUD/PiPHUDController.swift` (582L)
   - `Examples/SwiftSensorsApp/HUD/HUDMetricItems.swift` (555L)
   - `Examples/SwiftSensorsApp/Stores/TelemetryLogStore.swift` (485L)
   - `Examples/SwiftSensorsApp/Views/Screens/TelemetryLogsView.swift` (452L)
   - `Sources/SwiftSensors/NetworkProbeModels.swift` (444L)
   - `Examples/SwiftSensorsApp/Views/Screens/SlideOverHUDView.swift` (429L)
   - `Sources/SwiftSensors/ICMPProber.swift` (413L)
   - `Examples/SwiftSensorsApp/Views/Components/NetworkSLACardView.swift` (399L)
   - `Examples/SwiftSensorsApp/ViewModels/SensorsViewModel.swift` (390L)
   - `Examples/SwiftSensorsApp/Models/TelemetrySnapshot.swift` (390L)
   - `Examples/SwiftSensorsApp/Stores/TelemetryWebDashboardHTML.swift` (377L)
   - `Examples/SwiftSensorsApp/Views/Components/NetworkLatencyChartView.swift` (328L)
   - `Sources/SwiftSensors/SystemStats.swift` (316L)
   - `Examples/SwiftSensorsApp/Views/Components/LiveTelemetryStripView.swift` (301L)
2. **Módulos compartilhados / contratos públicos (independente do número de linhas):**
   - `Package.swift`
   - `Sources/PrivateAPI/PrivateAPI.h`
   - `Sources/SwiftSensors/SwiftSensors.swift`
   - `Sources/SwiftSensors/SensorBase.swift`
   - `Examples/SwiftSensorsApp/Theme/TelemetryTheme.swift`
   - `Examples/SwiftSensorsApp/HUD/HUDLayoutMode.swift`
   - `Examples/SwiftSensorsApp/Navigation/NavigationDestination.swift`

## Regra de Higiene em Edições Grandes

- Se uma alteração for expandir um arquivo além de 300–400 linhas, prefira fatiar o bloco em um novo componente/helper coeso respeitando a separação de camadas (`10-arquitetura-swift.md`).
- Toda edição em arquivos desta lista só é considerada concluída após passar por `Scripts/static-audit.sh --summary` (zero erros de build em `generic/platform=iOS`).
