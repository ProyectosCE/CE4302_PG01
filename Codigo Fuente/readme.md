# Código Fuente

Este directorio contiene la implementación y simulación del sistema modelado en SystemVerilog para el proyecto.

El objetivo de este README es explicar cómo configurar el entorno de simulación con Questa, cómo ejecutar el proyecto desde Visual Studio Code y cómo está organizada la estructura interna del código.

---

## 1. Requisitos

Para ejecutar este proyecto se requiere:

- Sistema operativo Windows
- Questa Intel FPGA Starter Edition (simulador)
- Visual Studio Code
- Extensión de SystemVerilog para VS Code (SystemVerilog - Language Support de Eirik Prestegårdshus y Verilog-HDL/SystemVerilog/Bluespec SystemVerilog de Masahiro Hiramori)

---

## 2. Instalación de Questa

Descargar e instalar Questa Intel FPGA Starter Edition desde:

[[OBTENER QUESTA AQUÍ]](https://www.altera.com/downloads/simulation-tools/questa-fpgas-standard-edition-software-version-21-1-1)

Durante la instalación:

- Seleccionar únicamente el simulador (Questa)
- No es necesario instalar Quartus ni soporte de dispositivos FPGA
- Se recomienda instalar en una ruta estándar, por ejemplo:

```text
C:\intelFPGA\21.1\
```

---

## 3. Configuración de licencia

Es necesario contar con un archivo de licencia `.dat`.

Generar la licencia desde:

[[OBTENER LICENCIA AQUÍ]](https://www.altera.com/SSLC)

Una vez descargado el archivo, por ejemplo:

```text
C:\LR-XXXXXX_License.dat
```

### 3.1 Variables de entorno

Agregar la siguiente variables de entorno en el sistema:

Nombre:

```text
LM_LICENSE_FILE
```

Valor:

```text
C:\LR-XXXXXX_License.dat
```

Después de configurarla:

- Cerrar todas las terminales
- Abrir una nueva terminal

### 3.2 Verificación

Ejecutar en una terminal:

```bash
vsim
```

Si la licencia está correctamente configurada, se abrirá Questa sin errores.

---

## 4. Uso desde Visual Studio Code

1. Abrir la carpeta `Codigo Fuente` en VS Code
2. Abrir una terminal integrada
3. Navegar a la carpeta de simulación:

```bash
cd sim
```

4. Ejecutar la simulación:

```bash
vsim -do ../scripts/run.do
```

Este comando:

- Compila los archivos SystemVerilog
- Ejecuta el testbench
- Corre la simulación completa

---

## 5. Script de simulación

El archivo:

```text
scripts/run.do
```

contiene los comandos de automatización de Questa.

Ejemplo:

```text
vlib work
vlog ../tb/top_tb.sv
vsim top_tb
run -all
```

Más adelante, cuando se agreguen archivos en `src/`, se debe incluir:

```text
vlog ../src/*.sv
```

---

## 6. Estructura del proyecto

La estructura actual dentro de `Codigo Fuente` es:

```text
Codigo Fuente
│
├── scripts
│   └── run.do
│
├── sim
│   ├── work
│   └── transcript
│
├── src
│
├── tb
│   └── top_tb.sv
│
├── readme.md
└── transcript
```

### 6.1 Descripción de carpetas

- `scripts/`  
  Contiene scripts de automatización para Questa.

- `sim/`  
  Contiene archivos generados por la simulación.  
  Incluye la librería `work` y archivos de log.  
  Esta carpeta no debe subirse al repositorio.

- `src/`  
  Contendrá la implementación del sistema (cache, bus, memoria, cores).

- `tb/`  
  Contiene los testbenches del sistema.  
  Actualmente incluye `top_tb.sv`.

---

## 7. Archivos generados automáticamente

Durante la simulación, Questa genera archivos como:

- `work/` (librería compilada)
- `transcript` (log de ejecución)
- archivos `.wlf` y logs

Estos archivos:

- Son temporales
- No deben subirse al repositorio
- Pueden eliminarse sin afectar el proyecto

---

## 8. Flujo de trabajo recomendado

1. Editar código en `src/` y `tb/`
2. Ejecutar simulación desde `sim/`
3. Analizar resultados
4. Repetir

---
