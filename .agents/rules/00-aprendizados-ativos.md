---
trigger: always_on
---
# Aprendizados Ativos do Projeto (`swift-sensors`)

> Guardrails permanentes de ambiente, plataforma iPadOS e telemetria. Teto estrito `< 4 KB`.

- **`IOKit.xcframework` arm64-only -> build obrigatório `generic/platform=iOS`**: `swift test` no macOS e builds para Simulator falham porque `Frameworks/IOKit.xcframework` possui apenas `ios-arm64`. Sempre validar compilação offline com `xcodebuild -project Examples/SwiftSensorsApp.xcodeproj -scheme SwiftSensorsApp -configuration Debug -destination "generic/platform=iOS" CODE_SIGNING_ALLOWED=NO`.
- **Arrasto do PiP no iPadOS -> manter `controlsStyle = 1` + `.positiveInfinity`**: Em `PiPHUDController.swift`, `controlsStyle = 2` desativa toque/arrasto na janela Pegasus do iPadOS. Nunca remover `setValue(1, forKey: "controlsStyle")` nem alterar `duration: .positiveInfinity` para builds de sideload.
- **Sensores Apple Silicon -> `PMU tdie*` e `PMU2 tdie*`**: Temperatura real de CPU usa `PMU tdie*` (ex.: `PMU tdie6`); GPU usa `PMU2 tdie*` (ex.: `PMU2 tdie1`), sempre ignorando sensores de calibração `tcal`.
- **FPS de jogos terceiros -> proibido usar `CADisplayLink` no HUD**: Sandbox do iPadOS impede leitura de FPS de outros apps (`CADisplayLink` apenas lê a taxa ProMotion 120Hz do próprio processo). Nunca reintroduzir FPS/1% Low/Mediana nos overlays PiP ou no `SlideOverHUDView`.
- **Perda de pacotes -> métrica cumulativa contínua**: `totalLostCount / totalProbes * 100` deve acumular por toda a sessão e nunca desaparecer automaticamente após estabilização da rede.
- **Script `launch_metal_hud.sh` -> interpretado por `python3`**: Apesar da extensão `.sh`, usa `#!/usr/bin/env python3`; validar sintaxe com `python3 -m py_compile` (nunca `bash -n`).
- **Privacidade absoluta -> zero IDs literais versionados**: Nunca gravar UDIDs de dispositivo, `DEVELOPMENT_TEAM`, e-mails ou tokens em código, scripts, regras ou documentação.
- **Operação Git -> confirmar raiz do repositório**: Sempre executar `git -C` dentro de `swift-sensors/` (nunca na pasta pai `/Volumes/--400GB--/FEITOS COM IA/Ipad`).
