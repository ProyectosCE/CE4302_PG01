# Demostración 1

## Sistema embebido multicore con datos compartidos en memoria cacheable

## Definición de enfoque y workloads

---

### 1. Introducción

En este proyecto se propone el modelado de un sistema multiprocesador con memoria compartida, con el objetivo de analizar el impacto de los protocolos de coherencia de caché sobre el desempeño del interconnect.

El enfoque seleccionado corresponde a un sistema embebido multicore con múltiples tareas concurrentes que acceden a estructuras de datos compartidas en memoria. A diferencia de sistemas embebidos tradicionales donde pueden utilizarse mecanismos como DMA o memoria no cacheable, en este modelo se estudia específicamente el comportamiento de datos compartidos en regiones de memoria cacheable, ya que estos son los que generan tráfico de coherencia y permiten analizar el impacto de protocolos write-invalidate y write-update [1], [2].

De esta forma, el proyecto no modela periféricos ni sensores físicos directamente, sino el procesamiento de datos ya presentes en memoria compartida, lo cual es un escenario común en sistemas embebidos modernos donde múltiples tareas interactúan sobre estructuras de datos comunes.

---

### 2. Alcance del sistema

El sistema a modelar consiste en:

* 4 elementos de procesamiento (PEs) que representan tareas concurrentes
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

Este diseño busca representar un sistema embebido multicore simplificado, enfocado en el análisis del tráfico generado por acceso a memoria compartida cacheable.

---

### 3. Justificación del diseño

El uso de 4 PEs permite generar escenarios de contención y compartición de datos, suficientes para observar efectos de coherencia sin aumentar excesivamente la complejidad del sistema.

La selección de una caché de 2 KB responde a dos objetivos: reflejar restricciones típicas de sistemas embebidos y forzar fallos de caché que generen tráfico hacia el interconnect.

La organización direct-mapped reduce la complejidad de implementación y, al mismo tiempo, introduce conflictos de mapeo que incrementan la actividad del sistema, lo cual es útil para el análisis.

La política write-back con write-allocate permite modelar sistemas modernos donde se busca reducir el tráfico hacia memoria principal, haciendo más relevante el comportamiento del protocolo de coherencia.

El uso de un bus compartido permite observar claramente la contención entre PEs, lo cual es fundamental para evaluar el impacto de los protocolos sobre el tráfico y la latencia.

El arbitraje round-robin asegura acceso equitativo al bus, evitando inanición y permitiendo comparar el comportamiento bajo condiciones controladas.

La inclusión de latencia en memoria permite distinguir claramente entre accesos a caché y accesos a memoria, haciendo visible el costo de los fallos de caché.

---

### 4. Definición de workloads

Los workloads fueron diseñados específicamente para generar suficiente tráfico en el interconnect y activar eventos de coherencia de manera frecuente, permitiendo comparar protocolos write-invalidate y write-update.

#### 4.1 Variable compartida con alta contención

Todos los PEs acceden a una misma variable en memoria cacheable:

* Lecturas y escrituras frecuentes en todos los PEs

Este patrón genera alta contención y múltiples eventos de invalidación o actualización, permitiendo observar el comportamiento de los protocolos bajo carga intensa.

---

#### 4.2 Productor-consumidor multicore

* Dos PEs producen datos en un buffer compartido
* Dos PEs consumen datos del mismo buffer

Todos los accesos se realizan sobre memoria cacheable compartida.

Este workload genera tráfico constante de lectura y escritura, simulando comunicación entre tareas y permitiendo analizar la interacción entre coherencia y flujo de datos.

---

#### 4.3 Migración de ownership

Una misma dirección de memoria es escrita de forma alternada por distintos PEs:

* PE0, PE1, PE2 y PE3 escriben sobre la misma variable en secuencia

Este patrón genera cambios constantes en los estados de coherencia, provocando transferencias de ownership y alto tráfico en el bus.

---

Estos workloads permiten cubrir distintos tipos de comportamiento: alta contención, comunicación entre tareas y migración de datos, todos relevantes para el análisis del interconnect.

---

### 5. Estrategia de validación

La validación del sistema se realizará mediante:

* Generación de logs de ejecución que registren accesos a memoria y eventos del protocolo
* Verificación de consistencia de datos entre PEs
* Análisis de secuencias de eventos de coherencia

Se busca asegurar que los valores leídos correspondan a los valores más recientes escritos, garantizando el correcto funcionamiento del protocolo.

---

### 6. Métricas a evaluar

Se consideran las siguientes métricas:

* Tráfico en el bus (número de transacciones)
* Latencia promedio de acceso a memoria
* Frecuencia de eventos de coherencia
* Utilización del bus

Estas métricas permiten analizar el impacto de los protocolos sobre el desempeño del sistema.

---

### 7. Interacción entre software y hardware

Dado que el sistema se divide en generación de workloads (software) y modelado de interconnect/caché (hardware), es necesario definir claramente las expectativas entre ambos.

Software hacia hardware:

* Generar memory traces con patrones de acceso definidos
* Especificar direcciones, tipo de acceso (read/write) y orden de ejecución
* Garantizar que los workloads generen suficiente tráfico y contención

Hardware hacia software:

* Definir formato esperado de los traces
* Proveer retroalimentación sobre comportamiento observado (latencias, conflictos, eventos)
* Exponer métricas que permitan evaluar el desempeño de los workloads

Esta interacción es clave para asegurar que los workloads ejerciten correctamente el sistema y que los resultados sean interpretables.

---

### 8. Lenguaje de implementación

* Lenguaje seleccionado: SystemVerilog

---

### Referencias

[1] J. L. Hennessy and D. A. Patterson, *Computer Architecture: A Quantitative Approach*, 6th ed. Elsevier, 2017.

[2] V. Nagarajan et al., *A Primer on Memory Consistency and Cache Coherence*. Morgan & Claypool, 2020.
