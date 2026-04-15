package model_pkg;

    timeunit 1ns;
    timeprecision 1ns;

    // Importar tipos definidos
    import types_pkg::*;

    // Parámetros globales del sistema
    parameter int NUM_CORES = 4;

    // Inclusión de componentes
    `include "core.sv"
    `include "cache.sv"
    `include "bus.sv"
    `include "memory.sv"
    `include "environment.sv"

endpackage