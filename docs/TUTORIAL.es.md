<p align="center">
  <a href="TUTORIAL.md">English</a> | <a href="TUTORIAL.pt-BR.md">Português (BR)</a> | <strong>Español</strong>
</p>

# ArkDieHuD — Tutorial Completo Paso a Paso

Bienvenido a **ArkDieHuD**. Esta guía explica cómo instalar la app (incluso con un **Apple ID gratuito**), configurar el **HUD flotante (`PiP`)** sobre juegos, diagnosticar caídas con la **Sonda Doble (`ICMP + UDP + TCP`)**, consultar el **historial de 24h** y usar el **Panel Web en PC/Mac (`:8787`)** sin tapar la pantalla.

---

## 1. Requisitos e Instalación con Apple ID Gratuito

- **Dispositivo:** iPad o iPhone con **iPadOS 17+ / iOS 17+** (Apple Silicon recomendado para sensores térmicos de CPU/GPU).
- **Modo Desarrollador:** necesario para ejecutar compilaciones personales.

### Activar el Modo Desarrollador en iPad
1. Ve a **Ajustes → Privacidad y Seguridad → Modo de Desarrollador**.
2. Actívalo, reinicia el iPad cuando se solicite y confirma al encender.

### Opción A: Instalar `.ipa` listo con Sideloadly / AltStore / SideStore
1. Descarga `ArkDieHuD-unsigned.ipa` desde **[Releases](https://github.com/Despensativo/ArkDieHuD/releases)**.
2. Abre **Sideloadly** (Windows/Mac) o **AltStore / SideStore**.
3. Conecta tu iPad, introduce tu **Apple ID gratuito** e instala `ArkDieHuD-unsigned.ipa`.
4. En el iPad, ve a **Ajustes → General → Gestión de VPN y Dispositivos** y toca **Confiar**.

### Opción B: Compilar desde Xcode (Personal Team gratuito)
1. Clona el repositorio y crea localmente `Examples/Config/LocalSigning.xcconfig` (ignorado por Git):
   ```xcconfig
   DEVELOPMENT_TEAM = TU_TEAM_ID
   PRODUCT_BUNDLE_IDENTIFIER = com.tunombre.ArkDieHuD
   ```
   O genera el `.ipa` sin firma desde la Terminal:
   ```bash
   ./Scripts/export-ipa.sh
   ```
2. Abre `Examples/SwiftSensorsApp.xcodeproj`, elige tu iPad y pulsa **Cmd + R**.

---

## 2. HUD Flotante (PiP) y Métricas Personalizables

1. Abre **ArkDieHuD** y en **HUD Flotante (PiP)** elige tu diseño: *Barra Gamer*, *Overlay Gamer*, *Cuadrícula Compacta* o *Detallado*.
2. Toca **Personalizar Métricas** para activar/desactivar cualquiera de las **12 métricas** o usar uno de los **4 perfiles rápidos**.
3. Pulsa **Superponer en Pantalla (PiP)** y cambia a tu juego. Puedes arrastrarlo a cualquier borde o cambiar su tamaño con dos dedos.

---

## 3. Diagnóstico de Red (Sonda Doble y Multiprotocolo)

Toca **Red y Registro de Paquetes**:
- **Router Local y Destino Externo caen a la vez:** problema en tu **Wi-Fi o router local**.
- **Router Local estable (~1–3 ms) y Destino Externo cae:** problema en tu **ISP, CGNAT o VPN**.
- **Solo UDP (`:53`) pierde paquetes mientras ICMP/TCP siguen estables:** saturación UDP en **NAT/CGNAT o QoS** (afecta directamente a juegos como PUBG).

---

## 4. Historial 24h en SQLite WAL y CSV Unificado

Activa **Grabar logs de telemetría (24h)** para guardar métricas cada 15s, consultar gráficos de **15m | 1h | 6h | 24h** y exportar un CSV unificado (Hardware + Red).

---

## 5. Monitor en PC/Mac (`:8787`) + Modo PiP Discreto

1. Activa **Monitorear en PC/Mac (sin PiP en pantalla)**.
2. Abre `http://<IP_DEL_IPAD>:8787` en tu navegador vía Wi-Fi, o usa cable USB:
   ```bash
   iproxy 8787 8787   # abre http://127.0.0.1:8787
   ```
3. Si usas chat de voz/micrófono en juegos, mantén activado **PiP discreto (ocultar en el borde)**, abre el PiP y **arrastra la píldora hacia el borde lateral** para dejar la pantalla limpia mientras el monitor en PC sigue activo.

---

## 6. Bonus: FPS Reales con Apple Metal HUD

```bash
./launch_metal_hud.sh flash
./launch_metal_hud.sh
```

---

## 7. Detección Automática de 3 Idiomas (`ES` / `PT-BR` / `EN`)

- **App iPad y PiP:** se adapta automáticamente al idioma del sistema (puedes cambiarlo por app en **Ajustes → ArkDieHuD → Idioma**).
- **Panel Web en PC/Mac (`:8787`):** detecta `navigator.language` automáticamente e incluye botones **`EN | PT | ES`** en la cabecera.
