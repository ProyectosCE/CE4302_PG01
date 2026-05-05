
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
 *   - Delega la lógica de coherencia a una estrategia polimórfica (ProtocolBase),
 *     permitiendo extensión futura sin modificar la clase Cache.
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
    protocol_e protocol_mode;

    /**
     * @brief Estrategia polimórfica de coherencia (MSI o Firefly).
     *        Cache delega aquí el comportamiento específico del protocolo.
     */
    ProtocolBase protocol;


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
     * @brief Array de líneas de caché (directamente mapeada).
     */
    cache_line_t lines[NUM_LINES];


    // METRICAS
    /** @brief Total de accesos de lectura (PrRd). */
    int read_count;
    /** @brief Total de accesos de escritura (PrWr). */
    int write_count;
    /** @brief Total de hits detectados. */
    int hit_count;
    /** @brief Total de misses detectados. */
    int miss_count;
    /** @brief Total de invalidaciones por snoop. */
    int invalidation_count;
    /** @brief Total de transiciones de estado de línea. */
    int state_transition_count;


    /**
     * @brief Constructor de la clase Cache.
     * @param cache_id Identificador de la caché (core asociado)
     * @param protocol Protocolo de coherencia a utilizar (MSI/Firefly)
     * Inicializa todas las líneas en estado inválido y selecciona dinámicamente
     * la implementación polimórfica del protocolo de coherencia.
     */
    function new(int cache_id, protocol_e protocol_sel);
        ProtocolMSI     msi_impl;
        ProtocolFirefly firefly_impl;

        this.cache_id = cache_id;
        this.protocol_mode = protocol_sel;

        case (protocol_sel)
            MSI: begin
                msi_impl = new();
                this.protocol = msi_impl;
            end
            FIREFLY: begin
                firefly_impl = new();
                this.protocol = firefly_impl;
            end
            default: $fatal(1, "[Cache %0d] Protocolo invalido: %0d", cache_id, protocol_sel);
        endcase

        foreach (lines[i]) begin
            lines[i].valid = 0;
            lines[i].state = Invalid;
            lines[i].tag   = 0;
        end

        read_count = 0;
        write_count = 0;
        hit_count = 0;
        miss_count = 0;
        invalidation_count = 0;
        state_transition_count = 0;
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
     * @brief Convierte el estado de coherencia a un string corto.
     */
    function string state_name(state_e state);
        case (state)
            Invalid:  return "I";
            Shared:   return "S";
            Modified: return "M";
            default:  return "?";
        endcase
    endfunction


    /**
     * @brief Registra transiciones de estado de la línea.
     */
    task log_state_change(state_e old_state, state_e new_state, logic [31:0] addr);
        if (old_state != new_state) begin
            state_transition_count++;
            $display("@%0t [Cache %0d] STATE CHANGE: %s -> %s addr=%h",
                $realtime, cache_id, state_name(old_state), state_name(new_state), addr);
        end
    endtask


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

        if (protocol == null) begin
            $fatal(1, "[Cache %0d] Protocolo no inicializado", cache_id);
        end

        $display("@%0t [Cache %0d] Iniciando (protocol=%0d)", $realtime, cache_id, protocol_mode);

        fork
            handle_core_requests(); // Atiende peticiones del core
            handle_bus_snoop();     // Atiende eventos de bus (snooping)
        join

    endtask


    /**
     * @brief Atiende solicitudes del core (lectura/escritura) y gestiona las transiciones
     *        delegando completamente la decisión de coherencia al protocolo activo.
     *        Cache conserva únicamente responsabilidades de almacenamiento,
     *        indexado y orquestación de comunicación.
     *        Se declara virtual para permitir override sin alterar la API.
     */
    virtual task handle_core_requests();

        CoreRequest req;
        int index;
        logic [31:0] tag;
        state_e old_state;
        state_e new_state;
        bit hit;
        string action_hint;
        bit tag_match;
        bit valid_line;
        state_e log_state;

        forever begin
            from_core.get(req); // Espera solicitud del core

            index = get_index(req.address);
            tag   = get_tag(req.address);

            old_state = lines[index].state;
            tag_match = (lines[index].tag == tag);
            valid_line = (lines[index].valid && tag_match);
            log_state = valid_line ? old_state : Invalid;
            hit = (valid_line && old_state != Invalid);

            if (valid_line && old_state == Modified && !hit) begin
                $error("[Cache %0d] Invalid MISS: state=M addr=%h", cache_id, req.address);
            end
            if (old_state == Invalid && hit) begin
                $error("[Cache %0d] Invalid HIT: state=I addr=%h", cache_id, req.address);
            end

            if (valid_line && old_state == Modified) begin
                $display("@%0t [Cache %0d] ACCESS M addr=%h -> %s",
                    $realtime, cache_id, req.address, hit ? "HIT" : "MISS");
            end

            if (req.req_type == PrRd) begin
                read_count++;
                action_hint = hit ? "" : " -> BusRd";
                $display("@%0t [Cache %0d] PrRd %h -> %s (state=%s)%s",
                    $realtime, cache_id, req.address, hit ? "HIT" : "MISS",
                    state_name(log_state), action_hint);
            end else begin
                write_count++;
                if (!hit) begin
                    action_hint = " -> BusRdX";
                end else if (old_state == Shared) begin
                    action_hint = (protocol_mode == FIREFLY) ? " -> BusUpd" : " -> BusRdX";
                end else begin
                    action_hint = "";
                end
                $display("@%0t [Cache %0d] PrWr %h -> %s (state=%s)%s",
                    $realtime, cache_id, req.address, hit ? "HIT" : "MISS",
                    state_name(log_state), action_hint);
            end

            if (hit) begin
                hit_count++;
            end else begin
                miss_count++;
            end

            protocol.handle_core_request(
                cache_id,
                req,
                index,
                tag,
                lines[index],
                to_bus,
                from_mem
            );

            new_state = lines[index].state;
            log_state_change(old_state, new_state, req.address);
        end
    endtask


    /**
     * @brief Atiende eventos de bus (snooping) para mantener la coherencia de caché.
     *        Procesa los mensajes de broadcast y actualiza el estado de las líneas locales
     *        según el tipo de evento delegando la semántica al protocolo activo.
     *        Se declara virtual para facilitar extensiones de comportamiento.
     */
    virtual task handle_bus_snoop();

        BusEvent evt;
        int index;
        logic [31:0] tag;
        state_e old_state;
        state_e new_state;

        forever begin
            from_bus.get(evt); // Espera evento de bus

            // Ignora eventos generados por sí mismo
            if (evt.src_core_id == cache_id)
                continue;

            index = get_index(evt.address);
            tag   = get_tag(evt.address);

            old_state = lines[index].state;

            protocol.handle_snoop(
                cache_id,
                evt,
                index,
                tag,
                lines[index]
            );

            new_state = lines[index].state;
            if (evt.req_type == BusRdX && old_state != Invalid && new_state == Invalid) begin
                invalidation_count++;
            end
            log_state_change(old_state, new_state, evt.address);
        end
    endtask


    /**
     * @brief Imprime las metricas de la cache.
     */
    function void print_metrics();
        int total_accesses;
        real hit_rate;

        total_accesses = hit_count + miss_count;
        hit_rate = (total_accesses > 0) ? (real'(hit_count) / total_accesses) : 0.0;

        $display("[Cache %0d Metrics]", cache_id);
        $display("Reads: %0d", read_count);
        $display("Writes: %0d", write_count);
        $display("Hits: %0d", hit_count);
        $display("Misses: %0d", miss_count);
        $display("Hit Rate: %0f", hit_rate);
        $display("Invalidations: %0d", invalidation_count);
        $display("State Transitions: %0d", state_transition_count);
        $display("-------------------------------------------");
    endfunction

endclass