
/*
 * ============================================
 * ARCHIVO: core.sv
 * DESCRIPCIÓN GENERAL:
 *   Implementa la clase Core, que modela un procesador simple dentro de un sistema multicore.
 *   Genera solicitudes de acceso a memoria (lectura/escritura) y las envía a su caché privada.
 *   No ejecuta instrucciones reales, solo simula el flujo de peticiones.
 *
 * ROL EN EL SISTEMA:
 *   - Origen de solicitudes de memoria.
 *   - Interactúa únicamente con su caché L1 privada.
 *
 * RELACIÓN CON OTROS MÓDULOS:
 *   - Envía solicitudes a la caché (Cache).
 *   - No interactúa directamente con Bus ni Memoria.
 *
 * PROTOCOLOS INVOLUCRADOS:
 *   - Compatible con MSI y Firefly a través de la caché.
 * ============================================
 */
import types_pkg::*;


/*
 * ============================================
 * CLASE: Core
 * DESCRIPCIÓN:
 *   Modela un procesador simple que genera una secuencia de solicitudes de acceso a memoria.
 *   No ejecuta instrucciones reales, solo simula el envío de peticiones a la caché.
 *
 * RESPONSABILIDAD:
 *   - Generar y enviar solicitudes de lectura/escritura.
 *   - Simular el comportamiento de un core en un sistema multicore.
 *
 * INTERFACES DE COMUNICACIÓN:
 *   - to_cache: mailbox para enviar solicitudes a la caché.
 *
 * INTERACCIÓN:
 *   - Interactúa únicamente con la caché mediante mailbox.
 * ============================================
 */
class Core;


    /**
     * @brief Identificador único del core.
     */
    int core_id;


    /**
     * @brief Mailbox para enviar solicitudes a la caché asociada.
     */
    CoreReq_mbx to_cache;


    /**
     * @brief Cola de solicitudes (trace) que el core enviará a la caché.
     */
    CoreRequest trace_queue[$];


    /**
     * @brief Constructor de la clase Core.
     * @param core_id Identificador del core
     */
    function new(int core_id);
        this.core_id = core_id;
    endfunction


    /**
     * @brief Agrega una solicitud a la cola de peticiones del core.
     * @param req Solicitud a agregar
     */
    function void add_request(CoreRequest req);
        trace_queue.push_back(req);
    endfunction


    /**
     * @brief Tarea principal del core. Envía secuencialmente las solicitudes de la cola
     *        a la caché asociada, simulando el comportamiento de un procesador.
     *        Incluye mensajes de debug para seguimiento.
     */
    virtual task run();

        if (to_cache == null) begin
            $fatal(1, "[Core %0d] Mailbox to_cache no inicializado", core_id);
        end

        $display("@%0t [Core %0d] Iniciando ejecucion (%0d requests)",
            $time, core_id, trace_queue.size());

        foreach (trace_queue[i]) begin
            CoreRequest req = trace_queue[i];

            $display("@%0t [Core %0d] Enviando %s addr=%h",
                $time, core_id,
                (req.req_type == PrRd) ? "PrRd" : "PrWr",
                req.address);

            to_cache.put(req);

            #10; // delay entre instrucciones (simulación)
        end

        $display("@%0t [Core %0d] Finalizo ejecucion", $time, core_id);

    endtask

endclass