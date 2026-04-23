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
        input MemResp_mbx from_mem
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
        ref cache_line_t line
    );
        $fatal(1,
            "[ProtocolBase] handle_snoop no implementado (cache=%0d addr=%h idx=%0d)",
            cache_id, evt.address, index);
    endtask

endclass
