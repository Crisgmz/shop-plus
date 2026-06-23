# Shop+ — Instalador de Windows (Inno Setup)

Genera un instalador `.exe` para Windows de la app de escritorio Shop+,
incluyendo **impresión térmica por TCP (ESC/POS, puerto 9100)**.

## Requisitos

- **Flutter** con soporte de escritorio Windows habilitado
  (`flutter config --enable-windows-desktop`).
- **Visual Studio** con la carga de trabajo *"Desktop development with C++"*.
- **Inno Setup 6** (`winget install JRSoftware.InnoSetup`).

## Construir el instalador (un comando)

```powershell
powershell -ExecutionPolicy Bypass -File installer\build.ps1
```

Esto:
1. Lee la versión desde `pubspec.yaml`.
2. Ejecuta `flutter build windows --release`.
3. Compila `installer\shop_plus.iss` con Inno Setup.
4. Deja el instalador en `installer\Output\ShopPlus-Setup-<versión>.exe`.

### Opciones

```powershell
# Apuntar a otra instancia de Supabase (por defecto usa la de producción):
installer\build.ps1 -SupabaseUrl https://otra.supabase.co -SupabaseAnonKey eyJ...

# Recompilar solo el instalador sin rebuild de Flutter:
installer\build.ps1 -SkipBuild
```

## Compilar manualmente

```powershell
flutter build windows --release
& "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" installer\shop_plus.iss
```

## Impresión por TCP

La app imprime recibos térmicos enviando bytes **ESC/POS crudos** directamente
a la IP de la impresora en el **puerto 9100** (RAW / JetDirect), sin necesidad
de instalar drivers de Windows.

Configuración: dentro de la app → **Configuración → Impresora de red (TCP)**:

- Activar impresión por TCP.
- Dirección IP de la impresora (ej. `192.168.1.50`) y puerto (`9100`).
- Ancho de papel: 80 mm (48 columnas) o 58 mm (32 columnas).
- Copias y apertura de gaveta de efectivo.
- Botón **Probar impresión** para validar la conexión.

Con esto, el diálogo de impresión del recibo muestra un botón
**"Imprimir en red"** que envía el ticket directamente a la impresora.

> La conexión es saliente (la app → impresora), por lo que **no** requiere
> reglas de firewall de entrada. La impresora debe estar en la misma red LAN.
