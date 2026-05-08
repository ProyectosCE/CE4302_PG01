/*
 * ============================================
 * ARCHIVO: protocol_base.sv
 * DESCRIPCIÓN GENERAL:
 *   Define la base polimórfica para protocolos de coherencia de caché.
 *   Se utiliza el patrón estrategia para desacoplar la lógica de protocolo
 *   de la clase Cache, manteniendo compatibilidad con el comportamiento existente.
 *
 * POLIMORFISMO:
 *   - Cache mantiene un handle de tipo ProtocolBase.
 *   - En tiempo de construcción se selecciona una implementación concreta
 *     (MSI o Firefly) y toda la lógica de coherencia se delega a dicha clase.
 * ============================================
 */

/**
 * @brief Estado de coherencia de una línea de caché.
 */
typedef enum {Invalid, Shared, Modified} state_e;

/**
 * @brief Estructura de línea de caché compartida entre Cache y protocolos.
 */
typedef struct {
    logic [31:0] tag;
    state_e state;
    bit valid;
} cache_line_t;


/**
 * ============================================
 * CLASE: ProtocolBase
 * DESCRIPCIÓN:
 *   Clase abstracta (virtual) que define la interfaz común de coherencia.
 *   Sus métodos son puntos de extensión para implementar protocolos concretos.
 *
 * RESPONSABILIDAD:
 *   - Definir contratos de handle_core_request y handle_snoop.
 *   - Permitir polimorfismo sin que Cache conozca detalles de MSI/Firefly.
 * ============================================
 */
virtual class ProtocolBase;

    /**
     * @brief Atiende una solicitud del core para una línea específica.
     * @param cache_id Identificador de la caché dueña de la línea.
     * @param req Solicitud de core (PrRd/PrWr).
     * @param index Índice de la línea (pasado para extensiones futuras).
     * @param tag Tag calculado para la dirección solicitada.
     * @param line Línea de caché por referencia (permite actualizar estado/tag).
     * @param to_bus Mailbox hacia bus compartido.
     * @param from_mem Mailbox de respuesta desde memoria.
     */
    virtual task handle_core_request(
        input int cache_id,
        input CoreRequest req,
        input int index,
        input logic [31:0] tag,
        ref cache_line_t line,
        input BusReq_mbx to_bus,
        input MemResp_mbx from_mem,

        ref int read_hits,
        ref int read_misses,

        ref int write_hits,
        ref int write_misses,
        
        ref int bus_stall_count,
        ref real total_bus_stall_time,
        input int BUS_MBX_DEPTH
    );
        $fatal(1,
            "[ProtocolBase] handle_core_request no implementado (cache=%0d addr=%h idx=%0d)",
            cache_id, req.address, index);
    endtask


    /**
     * @brief Atiende un evento de snoop para una línea específica.
     * @param cache_id Identificador de la caché dueña de la línea.
     * @param evt Evento observado en bus.
     * @param index Índice de la línea (pasado para extensiones futuras).
     * @param tag Tag calculado para la dirección observada.
     * @param line Línea de caché por referencia.
     */
    virtual task handle_snoop(
        input int cache_id,
        input BusEvent evt,
        input int index,
        input logic [31:0] tag,
        ref cache_line_t line,

        ref int snoop_busrd,
        ref int snoop_busrdx,
        ref int snoop_busupd,

        ref int invalidations_received,
        ref int updates_received,

        ref int writebacks
    );
        $fatal(1,
            "[ProtocolBase] handle_snoop no implementado (cache=%0d addr=%h idx=%0d)",
            cache_id, evt.address, index);
    endtask

    /**
     * @brief Helper reusable para enviar requests al bus.
     *
     * RESPONSABILIDAD:
     *   - Detectar backpressure/stall
     *   - Medir tiempo bloqueado en mailbox.put()
     *   - Actualizar métricas de stall
     *   - Emitir logs de STALL y PUT
     *
     * REUTILIZACIÓN:
     *   Todos los protocolos (MSI/Firefly)
     *   reutilizan esta lógica.
     */
    task automatic send_bus_request(
        input int cache_id,
        input BusRequest bus_req,
        input BusReq_mbx to_bus,

        ref int bus_stall_count,
        ref real total_bus_stall_time,

        input int BUS_MBX_DEPTH
    );

        real t_put_start;
        real t_put_end;
        real stall_time;

        int occupancy_before;

        occupancy_before = to_bus.num();

        // Detecta potencial backpressure
        if (occupancy_before >= BUS_MBX_DEPTH) begin

            bus_stall_count++;

            $display(
                "@%0t [Cache %0d][STALL] waiting_bus type=%0d addr=%h occ=%0d/%0d",
                $realtime,
                cache_id,
                bus_req.req_type,
                bus_req.address,
                occupancy_before,
                BUS_MBX_DEPTH
            );
        end

        // Medición de bloqueo real
        t_put_start = $realtime;

        to_bus.put(bus_req);

        t_put_end = $realtime;

        stall_time = t_put_end - t_put_start;

        total_bus_stall_time += stall_time;

        $display(
            "@%0t [Cache %0d][PUT] type=%0d addr=%h stall=%0f ns occ_after=%0d",
            $realtime,
            cache_id,
            bus_req.req_type,
            bus_req.address,
            stall_time,
            to_bus.num()
        );

    endtask

endclass
