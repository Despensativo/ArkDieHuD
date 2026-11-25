# PRODUCT — SwiftSensorsApp (iPadOS Hardware & Network Telemetry Instrument)

## Objetivo do Produto
Instrumento nativo para iPadOS voltado ao monitoramento técnico em tempo real durante sessões prolongadas de jogos, edição de vídeo/foto e diagnóstico de rede:

1. **Sensores de Silício Apple (IOKit/IOHID):** temperaturas individuais por sensor (incluindo die de CPU `PMU tdie*` e die de GPU `PMU2 tdie*`, filtrando calibradores `tcal`), tensão, corrente e potência estimada em Watts.
2. **Qualidade de Rede & SLA (1 Hz):** latência TCP (`NWConnection`), Jitter RFC 3550, perda de pacotes cumulativa de sessão (`totalLostCount / totalProbes * 100`, que nunca some), janelas de 60s/120s, detecção automática de ciclo periódico de provedor (~93s) e throughput de interfaces (`getifaddrs`).
3. **Kernel & Memória (Darwin Mach):** `phys_footprint`, `dirtyRatio`, alerta precoce Jetsam, profiling de threads (`task_threads`) e scanner `vm_region_64`.
4. **Sobreposição Multitarefa:**
   - **HUD Flutuante Picture-in-Picture (PiP):** barra ou painel compacto sobre qualquer jogo/app com gestos completos de arrasto (`controlsStyle = 1`).
   - **Modo Slide Over:** gaveta lateral interativa com seleção de servidor alvo de rede e telemetria detalhada.

## Restrições de Plataforma
- **Sem FPS de terceiros:** devido ao sandbox do iPadOS, o app não exibe FPS capturado por `CADisplayLink` para evitar métricas falsas de 120 Hz do próprio processo.
- **Compilação exclusiva `ios-arm64`:** `IOKit.xcframework` possui apenas slice físico ARM64.
