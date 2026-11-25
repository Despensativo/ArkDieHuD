# DESIGN — Padrão Visual 2026 (`mobile-craft` + `swiftui-pro` + Modo *Operate*)

## 1. Direção de Arte e Modo de Superfície
- **Modo:** *Operate* (instrumento de precisão técnica e diagnóstico ao vivo). Legibilidade instantânea em movimento, hierarquia espacial rigorosa e zero ornamento vazio.
- **Aparência:** Suporte de primeira classe a **Claro e Escuro** via cores semânticas do sistema (`Color(.systemGroupedBackground)`, `Color(.secondarySystemGroupedBackground)`, `.primary`, `.secondary`). Nenhum `.preferredColorScheme(.dark)` forçado fora do canvas Picture-in-Picture translúcido.
- **Cor Tática Única:** Azul do sistema (`Color.accentColor` / `.blue`) conduz todas as ações interativas; verde, amarelo, laranja e vermelho são reservados **exclusivamente** ao significado semântico de telemetria (temperatura, carga, ping e perda).

## 2. Tipografia e Numerais
- **Fonte base:** SF Pro nativa com estilos semânticos de sistema respeitando **Dynamic Type** (`.largeTitle`, `.title3`, `.headline`, `.subheadline`, `.callout`, `.footnote`). Evitar `.caption2` em informações primárias.
- **Dados Numéricos:** `.monospacedDigit()` obrigatório em todas as leituras numéricas dinâmicas (`°C`, `W`, `ms`, `%`, `GB`, `KB/s`) para evitar oscilação horizontal durante atualizações a 1 Hz.

## 3. Regras Estruturais Anti-Slop (Piso de Qualidade)
- **Ponto Focal Claro:** O topo do app abre com a faixa de telemetria viva em tempo real (`LiveTelemetryStripView`) + controle imediato de PiP/Slide Over, nunca com uma `List` infinita estilo "Ajustes".
- **Zero Emojis como Ícone:** Todo indicador de estado, alerta ou ciclo usa **SF Symbols** com traço consistente (`cpu`, `square.grid.2x2`, `bolt.fill`, `network`, `checkmark.circle.fill`, `exclamationmark.triangle.fill`, `waveform.path.ecg`).
- **Zero Cards Aninhados:** Superfícies de nível único com borda hairline sutil (`1px` em baixa opacidade) e divisores `Divider()` internos em vez de caixas dentro de caixas.
- **Alvos de Toque e Tátil:** Mínimo `44×44 pt` em controles interativos e `.sensoryFeedback(...)` em ações críticas (ativar PiP, trocar alvo, purge de memória).
- **Responsividade (`resizability`):** Layout adaptativo orientado por `@Environment(\.horizontalSizeClass)` (grade expandida em `.regular`, empilhamento limpo em `.compact` e Slide Over).

---

## 4. Identidade Visual — `ArkDieHuD`

- **Nome e Grafia Oficial:** **`ArkDieHuD`** (nos documentos e título; na wordmark visual, **`ArkDie`** em *SF Pro Rounded Bold* + badge **`HuD`** em *SF Mono Heavy* dentro de cápsula translúcida ciano-esmeralda).
- **Conceito da Marca (*Silicon Die Precision*):** Die de silício Apple Silicon em titânio escovado e vidro fumê com pinos microscópicos em cobre/âmbar nas bordas e pulso de telemetria ciano-esmeralda atravessando o núcleo.

### Paleta Oficial

| Token | Hex | Aplicação |
| :--- | :--- | :--- |
| `Space Black` | `#0B0D12` | Fundo do Banner GitHub, Painel Web (`:8787`) e base escura do `AppIcon` |
| `Graphite Surface` | `#141821` | Superfície elevada no Painel Web e moldura interna da marca |
| `Titanium Edge` | `#6E7687` | Chanfro metálico e bordas técnicas hairline (`1px`) |
| `Pulse Cyan` | `#22D3EE` | Início do feixe de pulso da logo e destaque **`HuD`** |
| `Pulse Emerald` | `#34D399` | Fechamento do gradiente da logo, sinal "Ao Vivo" e latência ideal |
| `Silicon Copper` | `#D98A3C` | Pinos do silício e consumo de energia (`Watts`) |
| `Thermal Amber` | `#FB923C` | Alerta térmico moderado e eventos de rajada/UDP |
| `Drop Red` | `#F87171` | Queda de pacote (`DROP`) e temperatura crítica (`>= 55°C`) |

### Ativos de Marca no Repositório

- **Ícone iPadOS (`1024×1024`, sem canal alpha):** [`Examples/SwiftSensorsApp/Assets.xcassets/AppIcon.appiconset`](Examples/SwiftSensorsApp/Assets.xcassets/AppIcon.appiconset/Contents.json) com variantes `Universal`, `Dark` e `Tinted` em escala de cinza de alto contraste.
- **Marca Interna do App (`ArkDieMark`):** [`ArkDieBrandLogoView.swift`](Examples/SwiftSensorsApp/Views/Components/ArkDieBrandLogoView.swift) (`header` no topo do painel + `compact`).
- **Assets GitHub (`Media/`):**
  - Ícone 512×512: [`Media/arkdiehud_icon.png`](Media/arkdiehud_icon.png)
  - Banner Widescreen (1600×800): [`Media/arkdiehud_github_banner.png`](Media/arkdiehud_github_banner.png)
