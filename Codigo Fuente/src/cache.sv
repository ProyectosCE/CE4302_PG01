
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

    /**
     * @brief Profundidad real del mailbox hacia el bus
     */
    int bus_mbx_depth;

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

    /**
     * @brief Monitor opcional para registrar transiciones de FSM.
     */
    EventMonitor fsm_monitor;


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
     * @brief Mailbox para enviar acknowledgments al core
     */
    CoreAck_mbx to_core;

    /**
     * @brief Array de líneas de caché (directamente mapeada).
     */
    cache_line_t lines[NUM_LINES];

    // CACHE METRICS
    // Hits / Misses
    int read_hits;
    int read_misses;

    int write_hits;
    int write_misses;

    // Snooping traffic
    int snoop_busrd;
    int snoop_busrdx;
    int snoop_busupd;

    // Coherence events
    int invalidations_received;
    int updates_received;

    // Memory traffic
    int writebacks;


    /**
     * @brief Constructor de la clase Cache.
     * @param cache_id Identificador de la caché (core asociado)
     * @param protocol Protocolo de coherencia a utilizar (MSI/Firefly)
     * Inicializa todas las líneas en estado inválido y selecciona dinámicamente
     * la implementación polimórfica del protocolo de coherencia.
     */
    function new(int cache_id, protocol_e protocol_sel, int bus_mbx_depth);
        ProtocolMSI     msi_impl;
        ProtocolFirefly firefly_impl;

        this.cache_id = cache_id;
        this.protocol_mode = protocol_sel;
        this.bus_mbx_depth = bus_mbx_depth;

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

        this.total_bus_stall_time = 0.0;
        this.total_bus_stalls = 0;
        this.max_bus_stall_time = 0.0;
    
        // CACHE METRICS INIT
        read_hits  = 0;
        read_misses = 0;

        write_hits = 0;
        write_misses = 0;

        snoop_busrd  = 0;
        snoop_busrdx = 0;
        snoop_busupd = 0;

        invalidations_received = 0;
        updates_received = 0;

        writebacks = 0;

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

        if (from_core == null || to_core == null || to_bus == null || from_mem == null || from_bus == null) begin
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

        forever begin
            from_core.get(req); // Espera solicitud del core

            index = get_index(req.address);
            tag   = get_tag(req.address);

            protocol.handle_core_request(
                cache_id,
                req,
                index,
                tag,
                lines[index],
                to_bus,
                from_mem,

                read_hits,
                read_misses,

                write_hits,
                write_misses,

                total_bus_stalls,
                total_bus_stall_time,
                max_bus_stall_time,
                bus_mbx_depth,
                fsm_monitor
            );

            to_core.put(new(cache_id)); // Acknowledge al core que la solicitud fue atendida
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

        forever begin
            from_bus.get(evt); // Espera evento de bus

            // Ignora eventos generados por sí mismo
            if (evt.src_core_id == cache_id)
                continue;

            index = get_index(evt.address);
            tag   = get_tag(evt.address);

            protocol.handle_snoop(
                cache_id,
                evt,
                index,
                tag,
                lines[index],

                snoop_busrd,
                snoop_busrdx,
                snoop_busupd,

                invalidations_received,
                updates_received,

                writebacks,
                fsm_monitor
            );
        end
    endtask

    // BUS STALL METRICS
    real total_bus_stall_time;
    int total_bus_stalls;
    real max_bus_stall_time;


    /**
    * @brief Registra tiempo bloqueado intentando acceder al bus.
    */
    function void record_bus_stall(
        real stall_time,
        BusRequest req
    );

        if (stall_time <= 0.0)
            return;

        total_bus_stalls++;
        total_bus_stall_time += stall_time;

        if (stall_time > max_bus_stall_time)
            max_bus_stall_time = stall_time;

        $display(
            "@%0t [CACHE%0d][STALL] blocked_on_bus=%0f ns type=%0d addr=%h",
            $realtime,
            cache_id,
            stall_time,
            req.req_type,
            req.address
        );

    endfunction

        
    /**
     * @brief Total de accesos de lectura.
     */
    function int get_total_reads();
        return read_hits + read_misses;
    endfunction


    /**
     * @brief Total de accesos de escritura.
     */
    function int get_total_writes();
        return write_hits + write_misses;
    endfunction


    /**
     * @brief Total de accesos a caché.
     */
    function int get_total_accesses();
        return get_total_reads() + get_total_writes();
    endfunction


    /**
     * @brief Calcula hit rate global.
     */
    function real get_hit_rate();

        int total_hits;
        int total_accesses;

        total_hits = read_hits + write_hits;
        total_accesses = get_total_accesses();

        if (total_accesses == 0)
            return 0.0;

        return (real'(total_hits) / real'(total_accesses)) * 100.0;

    endfunction


    /**
     * @brief Calcula miss rate global.
     */
    function real get_miss_rate();

        int total_misses;
        int total_accesses;

        total_misses = read_misses + write_misses;
        total_accesses = get_total_accesses();

        if (total_accesses == 0)
            return 0.0;

        return (real'(total_misses) / real'(total_accesses)) * 100.0;

    endfunction


    /**
     * @brief Calcula tasa de invalidaciones recibidas.
     *        Métrica útil principalmente para MSI.
     */
    function real get_invalidation_rate();

        if (get_total_accesses() == 0)
            return 0.0;

        return (real'(invalidations_received)
               / real'(get_total_accesses())) * 100.0;

    endfunction


    /**
     * @brief Calcula tráfico de updates.
     *        Métrica útil principalmente para Firefly.
     */
    function real get_update_traffic_rate();

        int total_snoop_events;

        total_snoop_events =
            snoop_busrd +
            snoop_busrdx +
            snoop_busupd;

        if (total_snoop_events == 0)
            return 0.0;

        return (real'(updates_received)
               / real'(total_snoop_events)) * 100.0;

    endfunction


    /**
     * @brief Calcula tasa de writebacks.
     */
    function real get_writeback_rate();

        int coherence_events;

        coherence_events =
            snoop_busrd +
            snoop_busrdx;

        if (coherence_events == 0)
            return 0.0;

        return (real'(writebacks)
               / real'(coherence_events)) * 100.0;

    endfunction

    /**
    * @brief Imprime métricas completas de la caché.
    */
    function void print_metrics();

        real read_hit_rate;
        real write_hit_rate;
        real avg_stall_time;

        int total_reads;
        int total_writes;

        total_reads  = get_total_reads();
        total_writes = get_total_writes();

        // Read hit rate
        if (total_reads == 0)
            read_hit_rate = 0.0;
        else
            read_hit_rate =
                (real'(read_hits) / real'(total_reads)) * 100.0;

        // Write hit rate
        if (total_writes == 0)
            write_hit_rate = 0.0;
        else
            write_hit_rate =
                (real'(write_hits) / real'(total_writes)) * 100.0;

        // Average stall time
        if (total_bus_stalls == 0)
            avg_stall_time = 0.0;
        else
            avg_stall_time =
                total_bus_stall_time / real'(total_bus_stalls);

        $display("");
        $display("==================================================");
        $display("CACHE %0d METRICS", cache_id);
        $display("==================================================");

        // Access metrics
        $display("READ HITS           : %0d", read_hits);
        $display("READ MISSES         : %0d", read_misses);

        $display("WRITE HITS          : %0d", write_hits);
        $display("WRITE MISSES        : %0d", write_misses);

        $display("TOTAL ACCESSES      : %0d", get_total_accesses());

        $display("");

        // Rates
        $display("GLOBAL HIT RATE     : %0.2f %%", get_hit_rate());
        $display("GLOBAL MISS RATE    : %0.2f %%", get_miss_rate());

        $display("READ HIT RATE       : %0.2f %%", read_hit_rate);
        $display("WRITE HIT RATE      : %0.2f %%", write_hit_rate);

        $display("");

        // Snooping traffic
        $display("SNOOP BusRd         : %0d", snoop_busrd);
        $display("SNOOP BusRdX        : %0d", snoop_busrdx);
        $display("SNOOP BusUpd        : %0d", snoop_busupd);

        $display("");

        // Coherence metrics
        $display("INVALIDATIONS RX    : %0d", invalidations_received);
        $display("UPDATES RX          : %0d", updates_received);

        $display("INVALIDATION RATE   : %0.2f %%",
            get_invalidation_rate());

        $display("UPDATE TRAFFIC RATE : %0.2f %%",
            get_update_traffic_rate());

        $display("");

        // Memory traffic
        $display("WRITEBACKS          : %0d", writebacks);

        $display("WRITEBACK RATE      : %0.2f %%",
            get_writeback_rate());

        $display("");

        // Stall metrics
        $display("BUS STALLS          : %0d", total_bus_stalls);

        $display("TOTAL STALL TIME    : %0.2f ns",
            total_bus_stall_time);

        $display("AVG STALL TIME      : %0.2f ns",
            avg_stall_time);

        $display("MAX STALL TIME      : %0.2f ns",
            max_bus_stall_time);

        $display("==================================================");
        $display("");

    endfunction

endclass