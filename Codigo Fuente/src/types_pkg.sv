
/*
 * ============================================
 * ARCHIVO: types_pkg.sv
 * DESCRIPCIÓN GENERAL:
 *   Define los tipos, enums y clases base para la comunicación y modelado
 *   de solicitudes, eventos y respuestas en el sistema multicore.
 *   Incluye los tipos de mensajes utilizados entre Core, Cache, Bus y Memoria,
 *   así como los mailboxes para la comunicación entre módulos.
 *
 * ROL EN EL SISTEMA:
 *   - Provee la base de tipos para la interacción entre componentes.
 *   - Permite la extensibilidad y claridad en la definición de protocolos.
 *
 * RELACIÓN CON OTROS MÓDULOS:
 *   - Importado por todos los módulos principales (Core, Cache, Bus, Memory).
 *   - Esencial para la interoperabilidad y simulación del sistema.
 *
 * PROTOCOLOS INVOLUCRADOS:
 *   - Define los tipos de mensajes compatibles con MSI y Firefly.
 * ============================================
 */
package types_pkg;

    timeunit 1ns;
    timeprecision 1ns;


    // ENUMS

    /**
     * @brief Tipos de solicitud que puede generar un core.
     *   - PrRd: Lectura (Processor Read)
     *   - PrWr: Escritura (Processor Write)
     */
    typedef enum {
        PrRd, ///< Lectura
        PrWr  ///< Escritura
    } core_req_type_e;

    /**
     * @brief Tipos de solicitud que pueden circular por el bus.
     *   - BusRd: Lectura compartida
     *   - BusRdX: Lectura exclusiva (invalida a otros)
     *   - BusUpd: Actualización (Firefly)
     */
    typedef enum {
        BusRd,   ///< Lectura compartida
        BusRdX,  ///< Lectura exclusiva (invalida)
        BusUpd   ///< Actualización (Firefly)
    } bus_req_type_e;

    function automatic string fmt_addr(logic [31:0] addr);
        return $sformatf("0x%08h", addr);
    endfunction

    function automatic string core_req_name(core_req_type_e req_type);
        case (req_type)
            PrRd:   return "PrRd";
            PrWr:   return "PrWr";
            default: return "Unknown";
        endcase
    endfunction

    function automatic string bus_req_name(bus_req_type_e req_type);
        case (req_type)
            BusRd:  return "BusRd";
            BusRdX: return "BusRdX";
            BusUpd: return "BusUpd";
            default: return "Unknown";
        endcase
    endfunction

    function automatic string core_tag(int core_id);
        return $sformatf("Core %0d", core_id);
    endfunction


    /**
     * ============================================
     * CLASE: CoreRequest
     * DESCRIPCIÓN:
     *   Representa una solicitud generada por un core hacia su caché.
     *   Incluye el tipo de operación, la dirección y el identificador del core origen.
     * ============================================
     */
    class CoreRequest;
        /**
         * @brief Tipo de solicitud (lectura o escritura)
         */
        core_req_type_e req_type;
        /**
         * @brief Dirección de memoria solicitada
         */
        logic [31:0] address;
        /**
         * @brief Identificador del core que genera la solicitud
         */
        int src_core_id;

        /**
         * @brief Constructor de CoreRequest
         * @param req_type Tipo de solicitud
         * @param address Dirección de memoria
         * @param src_core_id Core origen
         */
        function new(core_req_type_e req_type, logic [31:0] address, int src_core_id);
            this.req_type = req_type;
            this.address = address;
            this.src_core_id = src_core_id;
        endfunction

        /**
         * @brief Imprime la solicitud por consola (debug)
         */
        function void print();
            $display("[%0t] [TYPES] [Core %0d] CoreRequest type=%s addr=%s",
                $realtime, src_core_id, core_req_name(req_type), fmt_addr(address));
        endfunction
    endclass


    /**
     * ============================================
     * CLASE: CoreResponse
     * DESCRIPCIÓN:
     *   Representa la respuesta de la caché al core al completar una solicitud.
     *   Incluye el tipo de operación, la dirección y el core destino.
     * ============================================
     */
    class CoreResponse;
        /** @brief Tipo de solicitud completada. */
        core_req_type_e req_type;
        /** @brief Dirección de memoria completada. */
        logic [31:0] address;
        /** @brief Identificador del core destino. */
        int dest_core_id;

        /**
         * @brief Constructor de CoreResponse
         * @param req_type Tipo de solicitud completada
         * @param address Dirección de memoria completada
         * @param dest_core_id Core destino
         */
        function new(core_req_type_e req_type, logic [31:0] address, int dest_core_id);
            this.req_type = req_type;
            this.address = address;
            this.dest_core_id = dest_core_id;
        endfunction

        /**
         * @brief Imprime la respuesta por consola (debug)
         */
        function void print();
            $display("[%0t] [TYPES] [Core %0d] CoreResponse type=%s addr=%s",
                $realtime, dest_core_id, core_req_name(req_type), fmt_addr(address));
        endfunction
    endclass


    /**
     * ============================================
     * CLASE: BusRequest
     * DESCRIPCIÓN:
     *   Representa una solicitud enviada al bus por una caché.
     *   Incluye el tipo de operación, la dirección y el core origen.
     * ============================================
     */
    class BusRequest;
        /**
         * @brief Tipo de solicitud en el bus
         */
        bus_req_type_e req_type;
        /**
         * @brief Dirección de memoria solicitada
         */
        logic [31:0] address;
        /**
         * @brief Identificador del core origen
         */
        int src_core_id;
        /**
         * @brief Timestamp de encolado (metricas)
         */
        real t_enqueue;

        /**
         * @brief Constructor de BusRequest
         * @param req_type Tipo de solicitud
         * @param address Dirección de memoria
         * @param src_core_id Core origen
         */
        function new(bus_req_type_e req_type, logic [31:0] address, int src_core_id);
            this.req_type = req_type;
            this.address = address;
            this.src_core_id = src_core_id;
        endfunction

        /**
         * @brief Imprime la solicitud por consola (debug)
         */
        function void print();
            $display("[%0t] [TYPES] [Core %0d] BusRequest type=%s addr=%s",
                $realtime, src_core_id, bus_req_name(req_type), fmt_addr(address));
        endfunction
    endclass


    /**
     * ============================================
     * CLASE: BusEvent
     * DESCRIPCIÓN:
     *   Representa un evento de bus (broadcast) que es recibido por todas las cachés.
     *   Utilizado para el snooping y la actualización/invalidez de líneas.
     * ============================================
     */
    class BusEvent;
        /**
         * @brief Tipo de evento en el bus
         */
        bus_req_type_e req_type;
        /**
         * @brief Dirección de memoria involucrada
         */
        logic [31:0] address;
        /**
         * @brief Identificador del core origen
         */
        int src_core_id;
        /**
         * @brief Timestamp de broadcast del evento (para filtrar eventos obsoletos).
         */
        real t_broadcast;

        /**
         * @brief Constructor de BusEvent
         * @param req_type Tipo de evento
         * @param address Dirección de memoria
         * @param src_core_id Core origen
         */
        function new(bus_req_type_e req_type, logic [31:0] address, int src_core_id);
            this.req_type = req_type;
            this.address = address;
            this.src_core_id = src_core_id;
        endfunction

        /**
         * @brief Imprime el evento por consola (debug)
         */
        function void print();
            $display("[%0t] [TYPES] [Core %0d] BusEvent type=%s addr=%s",
                $realtime, src_core_id, bus_req_name(req_type), fmt_addr(address));
        endfunction
    endclass


    /**
     * ============================================
     * CLASE: MemResponse
     * DESCRIPCIÓN:
     *   Representa la respuesta de memoria a una solicitud de bus.
     *   Incluye la dirección y el core destino.
     * ============================================
     */
    class MemResponse;
        /**
         * @brief Dirección de memoria respondida
         */
        logic [31:0] address;
        /**
         * @brief Identificador del core destino
         */
        int dest_core_id;

        /**
         * @brief Constructor de MemResponse
         * @param address Dirección de memoria
         * @param dest_core_id Core destino
         */
        function new(logic [31:0] address, int dest_core_id);
            this.address = address;
            this.dest_core_id = dest_core_id;
        endfunction

        /**
         * @brief Imprime la respuesta por consola (debug)
         */
        function void print();
            $display("[%0t] [TYPES] [Core %0d] MemResponse addr=%s",
                $realtime, dest_core_id, fmt_addr(address));
        endfunction
    endclass


    // MAILBOXES

    /**
     * @brief Mailbox para solicitudes del core a la caché.
     */
    typedef mailbox #(CoreRequest) CoreReq_mbx;
    /**
     * @brief Mailbox para respuestas de la caché al core.
     */
    typedef mailbox #(CoreResponse) CoreResp_mbx;
    /**
     * @brief Mailbox para solicitudes de la caché al bus.
     */
    typedef mailbox #(BusRequest)  BusReq_mbx;
    /**
     * @brief Mailbox para eventos de bus (broadcast).
     */
    typedef mailbox #(BusEvent)    BusEvt_mbx;
    /**
     * @brief Mailbox para respuestas de memoria.
     */
    typedef mailbox #(MemResponse) MemResp_mbx;
    /**
     * @brief Mailbox para sincronizar acks de snoop hacia el bus.
     */
    typedef mailbox #(int) BusAck_mbx;

endpackage