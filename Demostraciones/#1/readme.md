# Demostración 1

## Sistema embebido tipo IoT / RT

## Definición de enfoque y workloads

### 1. Introducción

En este proyecto se propone el modelado de un sistema multiprocesador con memoria compartida, con el objetivo de analizar el impacto de los protocolos de coherencia de caché sobre el rendimiento del sistema.

El enfoque seleccionado corresponde a un sistema embebido tipo IoT / tiempo real, en el cual múltiples tareas concurrentes acceden a datos compartidos. Este tipo de sistemas es común en aplicaciones modernas como sensores inteligentes, procesamiento distribuido y comunicación en dispositivos embebidos [1], [2].

A diferencia de arquitecturas de propósito general, los sistemas embebidos se caracterizan por recursos limitados, simplicidad en el hardware y requerimientos de tiempo de respuesta predecibles. Por esta razón, el modelo propuesto busca reflejar estas condiciones mediante decisiones de diseño específicas en la jerarquía de memoria y el interconnect.

---

### 2. Alcance del sistema

El sistema a modelar consiste en:

* 4 elementos de procesamiento (PEs) que representan tareas independientes
* Caché L1 privada por cada PE
* Interconnect basado en bus compartido
* Memoria principal compartida

Configuración de la caché:

* Tamaño: 2 KB
* Organización: direct-mapped
* Política de escritura: write-back con write-allocate

Interconnect:

* Bus compartido
* Arbitraje tipo round-robin

Memoria:

* Latencia moderada (mayor que acceso a caché)

Este diseño busca representar un sistema embebido multicore simplificado, donde cada PE modela una tarea de un sistema operativo en tiempo real.

---

### 3. Justificación del diseño

El uso de 4 PEs permite generar escenarios de contención, compartición de datos y comportamiento concurrente, manteniendo la complejidad del sistema en un nivel manejable.

La caché de tamaño reducido (2 KB) se selecciona para reflejar las limitaciones de memoria típicas en sistemas embebidos, además de inducir fallos de caché que permitan observar el impacto de los protocolos de coherencia.

La organización direct-mapped reduce la complejidad de implementación y modela estructuras de hardware simples, comunes en microcontroladores, a costa de introducir conflictos de mapeo.

La política write-back con write-allocate permite reducir el tráfico hacia memoria principal, lo cual es relevante en sistemas donde el consumo energético y el ancho de banda son limitados.

El uso de un bus compartido como interconnect responde a su simplicidad y a su uso extendido en arquitecturas embebidas, donde se prioriza bajo costo y facilidad de implementación.

El arbitraje round-robin asegura acceso equitativo al bus entre los PEs, evitando condiciones de inanición.

La inclusión de latencia en memoria permite modelar diferencias reales entre accesos a caché y memoria principal, lo cual es fundamental para el análisis de desempeño.

---

### 4. Definición de workloads

Se proponen tres escenarios basados en patrones comunes en sistemas embebidos:

#### 4.1 Sensor compartido

Un PE produce datos (sensor) y los demás los consumen:

* PE0: escritura periódica de datos
* PE1–PE3: lecturas frecuentes del mismo dato

Este patrón modela el acceso a sensores compartidos en sistemas IoT, donde múltiples tareas requieren la misma información.

---

#### 4.2 Control distribuido

Todos los PEs acceden y modifican una variable compartida:

* Lectura del estado global
* Escritura del estado actualizado

Este comportamiento es representativo de sistemas de control donde múltiples módulos cooperan sobre un estado común, generando alta actividad de coherencia.

---

#### 4.3 Buffer circular (productor-consumidor)

* PE0: produce datos en un buffer
* PE1: consume datos
* PE2–PE3: monitorean el buffer

Este patrón es común en comunicación de datos, procesamiento en pipeline y streaming.

---

### 5. Estrategia de validación

La validación del sistema se realizará mediante:

* Generación de logs de ejecución que registren accesos a memoria y eventos relevantes
* Verificación de consistencia de datos entre PEs
* Análisis de secuencias de eventos para validar el comportamiento del protocolo de coherencia

El objetivo principal es asegurar que los datos leídos por cada PE correspondan al valor más reciente escrito, lo cual es la base del problema de coherencia.

---

### 6. Métricas a evaluar

Se consideran las siguientes métricas para el análisis del sistema:

* Tráfico en el bus: número de transacciones generadas
* Latencia percibida: tiempo promedio de acceso a memoria
* Frecuencia de eventos de coherencia: número de invalidaciones, actualizaciones u otros eventos relevantes

Estas métricas permiten evaluar la eficiencia del sistema y comparar el impacto de diferentes protocolos de coherencia.

---

### Referencias

[1] J. L. Hennessy and D. A. Patterson, *Computer Architecture: A Quantitative Approach*, 6th ed. Elsevier, 2017.

[2] V. Nagarajan et al., *A Primer on Memory Consistency and Cache Coherence*. Morgan & Claypool, 2020.
