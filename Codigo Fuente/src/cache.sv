
/*
 * ============================================
 * ARCHIVO: cache.sv
 * DESCRIPCIÓN GENERAL:
 *   Implementa la clase Cache para un sistema multicore con coherencia de caché.
 *   Modela una caché L1 privada por core, soportando los protocolos MSI (write-invalidate)
 *   y Firefly (write-update) para mantener la coherencia entre múltiples núcleos.
 *   La comunicación se realiza mediante mailboxes con Core, Bus y Memoria.
 *
 * ROL EN EL SISTEMA:
 *   - Intermediario entre el Core y el Bus compartido.
 *   - Gestiona el estado de las líneas de caché y las transiciones de acuerdo al protocolo.
 *   - Participa en la resolución de hits/misses y en la actualización/invalidez de líneas.
 *
 * RELACIÓN CON OTROS MÓDULOS:
 *   - Recibe peticiones del Core (lectura/escritura)
 *   - Solicita acceso al Bus y responde a eventos de broadcast
 *   - Recibe respuestas de Memoria
 *
 * PROTOCOLOS INVOLUCRADOS:
 *   - MSI: Write-invalidate
 *   - Firefly: Write-update simplificado
 *
 * MANEJO DE TIEMPO EN LOGS:
 *   - Se emplea $realtime para preservar precisión temporal en impresiones,
 *     incluyendo valores fraccionales cuando aplica en simulación.
 *   - Referencia para uso de $realtime: https://verificationacademy.com/forums/t/time-vs-realtime/38218
 * ============================================
 */
import types_pkg::*;


/*
 * ============================================
 * CLASE: Cache
 * DESCRIPCIÓN:
 *   Modela una caché L1 privada asociada a un core, implementando los protocolos
 *   de coherencia MSI y Firefly. Gestiona el almacenamiento local de líneas de caché,
 *   la interacción con el bus y la actualización de estados según las solicitudes del core
 *   y los eventos de bus.
 *
 * RESPONSABILIDAD:
 *   - Mantener la coherencia de datos entre múltiples cachés.
 *   - Atender solicitudes de lectura/escritura del core.
 *   - Procesar eventos de bus (snooping).
 *
 * INTERFACES DE COMUNICACIÓN:
 *   - from_core: recibe solicitudes del core.
 *   - to_bus: envía solicitudes al bus.
 *   - from_bus: recibe eventos de bus (broadcast).
 *   - from_mem: recibe respuestas de memoria.
 *
 * INTERACCIÓN:
 *   - Interactúa con Core, Bus y Memoria mediante mailboxes.
 *   - Las tareas run, handle_core_requests y handle_bus_snoop son virtuales
 *     para habilitar polimorfismo y extensión futura por herencia.
 * ============================================
 */
class Cache;


    /**
     * @brief Identificador único de la caché (asociado a un core).
     */
    int cache_id;

    /**
     * @brief Número de líneas de la caché (directamente mapeada).
     */
    localparam NUM_LINES = 64;

    // PROTOCOLO

    /**
     * @brief Enum de protocolos de coherencia soportados.
     *   - MSI: Write-invalidate
     *   - FIREFLY: Write-update simplificado
     */
    typedef enum {MSI, FIREFLY} protocol_e;

    /**
     * @brief Protocolo de coherencia utilizado por la instancia.
     */
    protocol_e protocol;


    // MAILBOXES DE COMUNICACIÓN 
    /**
     * @brief Mailbox para recibir solicitudes del core (lectura/escritura).
     */
    CoreReq_mbx from_core;
    /**
     * @brief Mailbox para enviar solicitudes al bus compartido.
     */
    BusReq_mbx  to_bus;
    /**
     * @brief Mailbox para recibir eventos de bus (broadcast de otros cores).
     */
    BusEvt_mbx  from_bus;
    /**
     * @brief Mailbox para recibir respuestas de memoria.
     */
    MemResp_mbx from_mem;


    /**
     * @brief Enum de estados de línea de caché (protocolo MSI).
     *   - I: Invalid
     *   - S: Shared
     *   - M: Modified
     */
    typedef enum {I, S, M} state_e;


    /**
     * @brief Estructura que representa una línea de caché.
     *   - tag: etiqueta de la dirección almacenada
     *   - state: estado de coherencia (I/S/M)
     *   - valid: indica si la línea contiene datos válidos
     */
    typedef struct {
        logic [31:0] tag;
        state_e state;
        bit valid;
    } cache_line_t;


    /**
     * @brief Array de líneas de caché (directamente mapeada).
     */
    cache_line_t lines[NUM_LINES];


    /**
     * @brief Constructor de la clase Cache.
     * @param cache_id Identificador de la caché (core asociado)
     * @param protocol Protocolo de coherencia a utilizar (MSI/Firefly)
     * Inicializa todas las líneas en estado inválido.
     */
    function new(int cache_id, protocol_e protocol);
        this.cache_id = cache_id;
        this.protocol = protocol;

        foreach (lines[i]) begin
            lines[i].valid = 0;
            lines[i].state = I;
            lines[i].tag   = 0;
        end
    endfunction


    /**
     * @brief Calcula el índice de la línea de caché a partir de la dirección.
     * @param addr Dirección solicitada
     * @return Índice de la línea en el array lines
     */
    function int get_index(logic [31:0] addr);
        return addr[10:5];
    endfunction


    /**
     * @brief Extrae el tag de la dirección solicitada.
     * @param addr Dirección solicitada
     * @return Tag correspondiente a la línea
     */
    function logic [31:0] get_tag(logic [31:0] addr);
        return addr[31:11];
    endfunction


    /**
     * @brief Tarea principal de la caché. Inicia la atención de solicitudes del core y
     *        el procesamiento de eventos de bus en paralelo.
     *        Verifica la inicialización de los mailboxes.
     *        Se declara virtual para permitir especializaciones en subclases.
     */
    virtual task run();

        if (from_core == null || to_bus == null || from_mem == null || from_bus == null) begin
            $fatal(1, "[Cache %0d] Mailboxes no inicializados", cache_id);
        end

        $display("@%0t [Cache %0d] Iniciando (protocol=%0d)", $realtime, cache_id, protocol);

        fork
            handle_core_requests(); // Atiende peticiones del core
            handle_bus_snoop();     // Atiende eventos de bus (snooping)
        join

    endtask


    /**
     * @brief Atiende solicitudes del core (lectura/escritura) y gestiona las transiciones
     *        de estado de las líneas de caché según el protocolo de coherencia.
     *        Implementa la lógica de hit/miss y la interacción con el bus/memoria.
     *        Parte fundamental del protocolo MSI/Firefly.
     *        Se declara virtual para permitir override sin alterar la API (referencia: https://www.edn.com/inheritance-and-polymorphism-of-systemverilog-oop-for-uvm-verification/).
     */
    virtual task handle_core_requests();

        CoreRequest req;
        BusRequest bus_req;
        MemResponse mem_resp;

        int index;
        logic [31:0] tag;
        cache_line_t line;
        bit hit;

        forever begin
            from_core.get(req); // Espera solicitud del core

            index = get_index(req.address);
            tag   = get_tag(req.address);
            line  = lines[index];

            // Determina si hay HIT: línea válida, tag coincide y no está inválida
            hit = (line.valid && line.tag == tag && line.state != I);

            // HIT 
            if (hit) begin

                if (req.req_type == PrRd) begin
                    $display("@%0t [Cache %0d] PrRd %h -> HIT (%0d)",
                        $realtime, cache_id, req.address, line.state);
                end

                else begin // PrWr
                    $display("@%0t [Cache %0d] PrWr %h -> HIT (%0d)",
                        $realtime, cache_id, req.address, line.state);

                    // Escritura sobre línea en estado S
                    if (line.state == S) begin

                        if (protocol == MSI) begin
                            // MSI: Write-invalidate
                            // Solicita invalidación a otros caches (BusRdX)
                            bus_req = new(BusRdX, req.address, cache_id);
                            to_bus.put(bus_req);
                            from_mem.get(mem_resp); // Espera respuesta de memoria

                            lines[index].state = M; // Transición a Modified
                        end
                        else begin
                            // Firefly: Write-update
                            // Solicita actualización a otros caches (BusUpd)
                            bus_req = new(BusUpd, req.address, cache_id);
                            to_bus.put(bus_req);

                            // Permanece en estado S (Firefly)
                        end
                    end
                end
            end

            // MISS 
            else begin

                if (req.req_type == PrRd) begin


                    $display("@%0t [Cache %0d] PrRd %h -> MISS -> BusRd",
                        $realtime, cache_id, req.address);

                    // Solicita lectura al bus (BusRd)
                    bus_req = new(BusRd, req.address, cache_id);
                    to_bus.put(bus_req);

                    from_mem.get(mem_resp); // Espera respuesta de memoria

                    // Actualiza línea: válida, estado S
                    lines[index].tag   = tag;
                    lines[index].valid = 1;
                    lines[index].state = S;
                end

                else begin // PrWr

                    $display("@%0t [Cache %0d] PrWr %h -> MISS -> BusRdX",
                        $realtime, cache_id, req.address);

                    // Solicita escritura exclusiva al bus (BusRdX)
                    bus_req = new(BusRdX, req.address, cache_id);
                    to_bus.put(bus_req);

                    from_mem.get(mem_resp); // Espera respuesta de memoria

                    // Actualiza línea: válida, estado M
                    lines[index].tag   = tag;
                    lines[index].valid = 1;
                    lines[index].state = M;
                end
            end
        end
    endtask


    /**
     * @brief Atiende eventos de bus (snooping) para mantener la coherencia de caché.
     *        Procesa los mensajes de broadcast y actualiza el estado de las líneas locales
     *        según el tipo de evento y el protocolo.
     *        Parte fundamental del protocolo MSI/Firefly.
     *        Se declara virtual para facilitar extensiones de comportamiento (referencia: https://www.edn.com/inheritance-and-polymorphism-of-systemverilog-oop-for-uvm-verification/).
     */
        virtual task handle_bus_snoop();

        BusEvent evt;
        int index;
        logic [31:0] tag;
        cache_line_t line;

        forever begin
            from_bus.get(evt); // Espera evento de bus

            // Ignora eventos generados por sí mismo
            if (evt.src_core_id == cache_id)
                continue;

            index = get_index(evt.address);
            tag   = get_tag(evt.address);
            line  = lines[index];

            // Solo procesa si la línea es válida y el tag coincide
            if (!(line.valid && line.tag == tag))
                continue;

            case (evt.req_type)

                // BusRd 
                BusRd: begin
                    if (line.state == M) begin
                        // Otro core solicita lectura y esta caché tiene la línea modificada
                        // Transición M->S y (en modelo real) escribiría back a memoria
                        $display("@%0t [Cache %0d] SNOOP BusRd -> M->S (WB)",
                            $realtime, cache_id);
                        lines[index].state = S;
                    end
                end

                // BusRdX
                BusRdX: begin
                    if (line.state == S || line.state == M) begin
                        // Otro core solicita escritura exclusiva, se invalida la línea local
                        $display("@%0t [Cache %0d] SNOOP BusRdX -> -> I",
                            $realtime, cache_id);
                        lines[index].state = I;
                        lines[index].valid = 0;
                    end
                end

                // BusUpd (Firefly)
                BusUpd: begin
                    if (line.state == S) begin
                        // Otro core realiza update, la línea permanece en S (Firefly)
                        $display("@%0t [Cache %0d] SNOOP BusUpd -> permanece S",
                            $realtime, cache_id);
                    end
                end

            endcase
        end
    endtask

endclass