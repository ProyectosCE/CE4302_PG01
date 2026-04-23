
/*
 * ============================================
 * ARCHIVO: model_pkg.sv
 * DESCRIPCIÓN GENERAL:
 *   Define el paquete principal del modelo multicore, importando los tipos base
 *   y declarando los parámetros globales del sistema. Incluye los archivos fuente
 *   de los módulos Core, Cache, Bus, Memory y Environment.
 *
 * ROL EN EL SISTEMA:
 *   - Punto de integración de todos los componentes del sistema multicore.
 *   - Define la cantidad de cores y la estructura general del modelo.
 *
 * RELACIÓN CON OTROS MÓDULOS:
 *   - Importado por los testbenches y módulos principales.
 *   - Permite la instanciación y conexión de los componentes.
 *
 * PROTOCOLOS INVOLUCRADOS:
 *   - Soporta MSI y Firefly a través de las clases incluidas.
 * ============================================
 */
package model_pkg;

    timeunit 1ns;
    timeprecision 1ns;


    // IMPORTACIÓN DE TIPOS
    /**
     * @brief Importa los tipos y clases base definidos en types_pkg.sv
     */
    import types_pkg::*;


    // PARÁMETROS GLOBALES
    /**
     * @brief Número de cores en el sistema multicore.
     */
    parameter int NUM_CORES = 4;


    // INCLUSIÓN DE MÓDULOS
    /**
     * @brief Incluye los archivos fuente de los módulos principales del sistema multicore.
     *   - core.sv: Procesador (Core)
     *   - protocol_base.sv: Interfaz polimórfica de coherencia
     *   - protocol_msi.sv: Implementación MSI
     *   - protocol_firefly.sv: Implementación Firefly
     *   - cache.sv: Caché privada por core
     *   - bus.sv: Bus compartido
     *   - memory.sv: Memoria principal
     *   - environment.sv: Entorno de simulación
     */
    `include "core.sv"
    `include "protocol_base.sv"
    `include "protocol_msi.sv"
    `include "protocol_firefly.sv"
    `include "cache.sv"
    `include "bus.sv"
    `include "memory.sv"
    `include "environment.sv"
    `include "trace_loader.sv"
    `include "trace_export.sv"
    `include "event_monitor.sv"

endpackage