---
trigger: always_on
---
# Arquitetura, Nomenclatura e Padrões Swift (`swift-sensors`)

## 1. Separação Estrita de Camadas

- **`Sources/PrivateAPI/`**: apenas declarações C/Objective-C mínimas para `IOKit` / `IOHID`. Proibido lógica de negócio.
- **`Sources/SwiftSensors/`**: biblioteca SPM pura de telemetria (`Swift 6`, `Sendable`, `actor` por domínio). **Proibido importar `SwiftUI` ou acoplar estado de interface** nesta camada.
- **`Examples/SwiftSensorsApp/`**: aplicativo consumidor (`SwiftUI`, `AVKit`, `CoreGraphics`). ViewModels e controladores de UI devem ser isolados com `@MainActor`.

## 2. Regra de Ouro Anti-Duplicação

Antes de criar qualquer função utilitária, extensão, formatador (`SensorFormatter`), modelo de snapshot, cálculo de cor/temperatura ou componente SwiftUI:
1. Busque implementações existentes com `rg -n "<termo>" Sources/ Examples/`.
2. Reutilize ou extraia para um helper compartilhado em vez de duplicar lógica entre `HUDFrameRenderer`, `SlideOverHUDView` e `Views/Components/`.

## 3. Padrões Obrigatórios Swift 6 & Segurança de Memória

- **CoreFoundation (`IOKit` / `CoreMedia` / `CF*`):** toda chamada `*Create` ou `*Copy` (`IOHIDEventSystemClientCreate`, `IOHIDServiceClientCopyProperty`, `IOHIDServiceClientCopyEvent`) segue ownership +1 e exige liberação explícita (`takeRetainedValue()` / `CFRelease`). Nunca usar `unsafeBitCast` sem justificar ownership.
- **Mach Kernel & Ponteiros C:** ao usar `task_threads` ou `vm_region_64`, liberar Mach send rights antigos com `mach_port_deallocate` e proteger somas de endereço contra overflow (`addingReportingOverflow`). Ao iterar `getifaddrs`, validar sempre `guard let ifaAddr = cur.pointee.ifa_addr` antes de `.pointee`.
- **Logging:** usar `os.Logger` em código novo; evitar `print(` e remover `NSLog("SWIFTSENSORS_DEBUG...")` de caminhos em Release.
- **SwiftUI Moderno:** usar `.foregroundStyle(...)` em vez de `.foregroundColor(...)` (deprecado).

## 4. Direção Visual 2026 (`Examples/SwiftSensorsApp/Views/`)

Qualquer criação ou refino de interface deve seguir as skills **`mobile-craft`** + **`swiftui-pro`** + **`polimento-ui` (Modo Operate)**:
- Priorizar **SF Symbols** semânticos em vez de emojis (`🟢`, `❌`, `⚡`, `⚠️`, `✅`) em badges, alertas e status.
- Aplicar `.monospacedDigit()` em toda leitura numérica em tempo real (`°C`, `W`, `ms`, `%`, `GB`).
- Evitar visual genérico de lista de configurações sem foco e evitar cards aninhados; manter suporte a Claro/Escuro e janelas **Slide Over / Stage Manager**.
- Validar UI alterada com build limpo (`Scripts/static-audit.sh`) e captura visual em dispositivo/preview antes de concluir.
