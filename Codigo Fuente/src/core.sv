
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
 *
 * MANEJO DE TIEMPO EN LOGS:
 *   - Para trazas se utiliza $realtime en lugar de $time, permitiendo reflejar
 *     tiempos fraccionales cuando la simulación tiene precisión menor al timeunit.
 *   - Referencia para uso de $realtime: https://verificationacademy.com/forums/t/time-vs-realtime/38218
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
 *   - La tarea run se mantiene virtual para permitir polimorfismo y
 *     extensiones futuras mediante herencia (referencia: https://www.edn.com/inheritance-and-polymorphism-of-systemverilog-oop-for-uvm-verification/).
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
     * @brief Mailbox para recibir respuestas desde la caché.
     */
    CoreResp_mbx from_cache;


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
     *        Se declara virtual para que subclases puedan especializar su ejecución (referencia: https://www.edn.com/inheritance-and-polymorphism-of-systemverilog-oop-for-uvm-verification/).
     */
    virtual task run();

        if (to_cache == null) begin
            $fatal(1, "[%0t] [CORE] [Core %0d] ERROR to_cache no inicializado", $realtime, core_id);
        end
        if (from_cache == null) begin
            $fatal(1, "[%0t] [CORE] [Core %0d] ERROR from_cache no inicializado", $realtime, core_id);
        end

        $display("[%0t] [CORE] [Core %0d] START requests=%0d",
            $realtime, core_id, trace_queue.size());

        foreach (trace_queue[i]) begin
            CoreRequest req = trace_queue[i];
            CoreResponse resp;

            time t_req_start;
            time t_req_end;
            time req_latency;

            t_req_start = $realtime;
            $display("[%0t] [CORE] [Core %0d] REQ_START type=%s addr=%s",
                $realtime, core_id, core_req_name(req.req_type), fmt_addr(req.address));

            to_cache.put(req);

            // FIX: core blocking hasta completar la solicitud.
            from_cache.get(resp);

            t_req_end = $realtime;
            req_latency = t_req_end - t_req_start;
            $display("[%0t] [CORE] [Core %0d] REQ_DONE type=%s addr=%s latency=%0t",
                $realtime, core_id, core_req_name(resp.req_type), fmt_addr(resp.address), req_latency);

            #10; // delay entre instrucciones (simulación)
        end

        $display("[%0t] [CORE] [Core %0d] DONE", $realtime, core_id);

    endtask

endclass