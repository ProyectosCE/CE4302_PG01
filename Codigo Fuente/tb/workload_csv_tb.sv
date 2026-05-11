
/*
 * ============================================
 * ARCHIVO: top_tb.sv
 * DESCRIPCIÓN GENERAL:
 *   Testbench de integración para el sistema multicore completo.
 *   Instancia y conecta todos los componentes: cores, caches, bus y memoria.
 *   Simula escenarios de alta contención, productor-consumidor y migración de ownership.
 *
 * ESCENARIOS PROBADOS:
 *   1. Alta contención: Todos los cores acceden a la misma dirección.
 *   2. Productor-consumidor: Unos cores escriben y otros leen la misma dirección.
 *   3. Migración de ownership: Escrituras sucesivas por diferentes cores.
 *
 * COMPORTAMIENTO ESPERADO:
 *   - Se observan logs de solicitudes, transiciones de estado y eventos de bus.
 *   - Se valida la correcta interacción y coherencia entre todos los módulos.
 *
 * NOTA DE TIEMPO:
 *   - Se utiliza $realtime para trazas más precisas y se configura $timeformat
 *     para visualizar tiempos en ns de forma uniforme.
 *   - Referencia para uso de $realtime: https://verificationacademy.com/forums/t/time-vs-realtime/38218
 * ============================================
 */
`timescale 1ns/1ps

module workload_csv_tb;

    import types_pkg::*;
    import model_pkg::*;

    // CONFIGURACIÓN GLOBAL
    localparam NUM_CORES = 4;
    localparam BUS_MBX_DEPTH = 4;

    // COMPONENTES DEL SISTEMA
    Core  cores   [NUM_CORES];
    Cache caches  [NUM_CORES];
    Bus   bus;
    Memory memory;

    // Mailboxes para comunicación entre módulos
    CoreReq_mbx core_to_cache [NUM_CORES];
    BusEvt_mbx  bus_evt_mbx   [NUM_CORES];
    MemResp_mbx mem_mbx       [NUM_CORES];

    // Acknowledgments del core para que no envíe solicitudes a la caché más rápido de lo que puede procesarlas
    CoreAck_mbx cache_to_core [NUM_CORES];

    BusReq_mbx bus_mbx;
    BusReq_mbx mem_req_mbx;
    
    // Mailbox para que la memoria notifique al bus cuando una transacción de memoria ha finalizado (opcional, dependiendo de la implementación del bus)
    MemResp_mbx mem_done_mbx;

    // Monitoreo FSM (transiciones de estado)
    EventMonitor fsm_monitor;


        // Metadata de ejecución/exportación
        string g_results_dir;
        string g_run_id;
        string g_run_timestamp;
        string g_protocol_name;
        string g_workload_name;

    /**
     * @brief Inicializa el sistema: crea instancias, mailboxes y conecta todos los módulos.
     *        Lanza en paralelo la ejecución de caches y el bus/memoria.
     */
    task setup_system(Cache::protocol_e protocol_sel);

        bus_mbx = new(BUS_MBX_DEPTH);
        mem_req_mbx = new(BUS_MBX_DEPTH);
        mem_done_mbx = new(BUS_MBX_DEPTH);

        if (fsm_monitor == null) begin
            string fsm_csv_path;

            fsm_monitor = new();

            fsm_csv_path = $sformatf(
                "%s/csv_state_transitions/%s_%s_%s_state_transitions.csv",
                g_results_dir,
                g_run_id,
                g_protocol_name,
                g_workload_name
            );

            fsm_monitor.enable_transition_export(fsm_csv_path);
        end

        foreach (core_to_cache[i]) core_to_cache[i] = new();
        foreach (bus_evt_mbx[i])  bus_evt_mbx[i]  = new();
        foreach (mem_mbx[i])      mem_mbx[i]      = new();

        foreach (cache_to_core[i]) cache_to_core[i] = new(1);

        foreach (cores[i]) begin
            caches[i] = new(i, protocol_sel, BUS_MBX_DEPTH);
            cores[i]  = new(i);

            caches[i].fsm_monitor = fsm_monitor;

            cores[i].to_cache = core_to_cache[i];

            caches[i].from_core = core_to_cache[i];
            caches[i].to_bus    = bus_mbx;
            caches[i].from_bus  = bus_evt_mbx[i];
            caches[i].from_mem  = mem_mbx[i];

            cores[i].from_cache = cache_to_core[i];
            caches[i].to_core   = cache_to_core[i];

        end

       
        bus = new(bus_mbx, bus_evt_mbx, mem_req_mbx, mem_done_mbx, NUM_CORES);

        // Instancia de Memory: 4 cores, 8 bytes/ns ancho de banda y mailbox para notificar al bus cuando una transacción de memoria ha finalizado.
        memory = new(mem_req_mbx, mem_mbx, mem_done_mbx, NUM_CORES, 8.0);

        // CACHES en paralelo
        fork
            caches[0].run();
            caches[1].run();
            caches[2].run();
            caches[3].run();
        join_none

        // BUS real: arbitraje RR + broadcast + BW modelado + métricas
        bus.run();

        // MEMORIA real: procesa solicitudes con latencias modeladas
        memory.run();

        #10;

    endtask

    /**
     * @brief Ejecuta todos los cores en paralelo, procesando sus traces de solicitudes.
     */
    task run_cores();
        fork
            cores[0].run();
            cores[1].run();
            cores[2].run();
            cores[3].run();
        join
    endtask

    /**
     * @brief Carga traces desde archivo CSV e inyecta en los cores.
     *        Lee plusarg +TRACE_FILE; si no existe, usa default.
     * @param trace_file Ruta del archivo CSV (puede ser vacio para usar default)
     */
    task load_traces_from_file(string trace_file);
        TraceLoader loader;
        string pe_trace_file;
        static string default_trace = "../traces/fake/workload_contention_1000000";

        // Si no se proporciona archivo, usa default
        if (trace_file == "") begin
            trace_file = default_trace;
        end

        $display("[TopTB] Cargando workload base: %s", trace_file);

        foreach (cores[i]) begin
            pe_trace_file = $sformatf("%s_PE%0d.csv", trace_file, i);

            $display("[TopTB] Cargando PE%0d desde: %s", i, pe_trace_file);

            loader = new(pe_trace_file);
            loader.load_into_core(cores[i], i);
        end
endtask



    task export_cache_metrics_csv();
        int fh;
        string path;

        path = $sformatf(
            "%s/csv_per_cache/%s_%s_%s_cache_metrics.csv",
            g_results_dir,
            g_run_id,
            g_protocol_name,
            g_workload_name
        );

        fh = $fopen(path, "w");

        if (fh == 0) begin
            $display("[ERROR] No se pudo abrir CSV de cache metrics: %s", path);
            return;
        end

        $fdisplay(fh,
            "run_id,timestamp,protocol,workload,core_id,read_hits,read_misses,write_hits,write_misses,total_accesses,global_hit_rate,global_miss_rate,read_hit_rate,write_hit_rate,snoop_busrd,snoop_busrdx,snoop_busupd,invalidations_received,updates_received,writebacks,bus_stalls,total_stall_time_ns,avg_stall_time_ns,max_stall_time_ns"
        );

        foreach (caches[i]) begin
            int total_reads;
            int total_writes;
            real read_hit_rate;
            real write_hit_rate;
            real avg_stall_time;

            total_reads  = caches[i].get_total_reads();
            total_writes = caches[i].get_total_writes();

            read_hit_rate =
                (total_reads == 0) ? 0.0 :
                (real'(caches[i].read_hits) / real'(total_reads)) * 100.0;

            write_hit_rate =
                (total_writes == 0) ? 0.0 :
                (real'(caches[i].write_hits) / real'(total_writes)) * 100.0;

            avg_stall_time =
                (caches[i].total_bus_stalls == 0) ? 0.0 :
                caches[i].total_bus_stall_time / real'(caches[i].total_bus_stalls);

            $fdisplay(fh,
                "%s,%s,%s,%s,%0d,%0d,%0d,%0d,%0d,%0d,%0.2f,%0.2f,%0.2f,%0.2f,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0.2f,%0.2f,%0.2f",
                g_run_id,
                g_run_timestamp,
                g_protocol_name,
                g_workload_name,
                i,
                caches[i].read_hits,
                caches[i].read_misses,
                caches[i].write_hits,
                caches[i].write_misses,
                caches[i].get_total_accesses(),
                caches[i].get_hit_rate(),
                caches[i].get_miss_rate(),
                read_hit_rate,
                write_hit_rate,
                caches[i].snoop_busrd,
                caches[i].snoop_busrdx,
                caches[i].snoop_busupd,
                caches[i].invalidations_received,
                caches[i].updates_received,
                caches[i].writebacks,
                caches[i].total_bus_stalls,
                caches[i].total_bus_stall_time,
                avg_stall_time,
                caches[i].max_bus_stall_time
            );
        end

        $fclose(fh);

        $display("[CSV] Cache metrics exportado: %s", path);
    endtask


    task export_summary_csv();
        int fh;
        string path;

        int total_accesses;
        int total_hits;
        int total_misses;
        real global_hit_rate;
        real global_miss_rate;

        total_accesses = 0;
        total_hits     = 0;
        total_misses   = 0;

        foreach (caches[i]) begin
            total_accesses += caches[i].get_total_accesses();
            total_hits     += caches[i].read_hits + caches[i].write_hits;
            total_misses   += caches[i].read_misses + caches[i].write_misses;
        end

        global_hit_rate =
            (total_accesses == 0) ? 0.0 :
            (real'(total_hits) / real'(total_accesses)) * 100.0;

        global_miss_rate =
            (total_accesses == 0) ? 0.0 :
            (real'(total_misses) / real'(total_accesses)) * 100.0;

        path = $sformatf(
            "%s/csv_summary/%s_%s_%s_summary.csv",
            g_results_dir,
            g_run_id,
            g_protocol_name,
            g_workload_name
        );

        fh = $fopen(path, "w");

        if (fh == 0) begin
            $display("[ERROR] No se pudo abrir CSV summary: %s", path);
            return;
        end

        $fdisplay(fh,
            "run_id,timestamp,protocol,workload,num_cores,total_accesses,total_hits,total_misses,global_hit_rate,global_miss_rate,total_bus_requests,total_bus_grants,total_mem_accesses,total_bus_bytes,busrd,busrdx,busupd,total_invalidations,total_updates,total_memory_accesses,total_memory_bytes"
        );

        $fdisplay(fh,
            "%s,%s,%s,%s,%0d,%0d,%0d,%0d,%0.2f,%0.2f,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
            g_run_id,
            g_run_timestamp,
            g_protocol_name,
            g_workload_name,
            NUM_CORES,
            total_accesses,
            total_hits,
            total_misses,
            global_hit_rate,
            global_miss_rate,
            bus.total_requests,
            bus.total_grants,
            bus.total_mem_accesses,
            bus.total_bytes_transferred,
            bus.count_BusRd,
            bus.count_BusRdX,
            bus.count_BusUpd,
            bus.total_invalidations,
            bus.total_updates,
            memory.total_accesses,
            memory.total_bytes_transferred
        );

        $fclose(fh);

        $display("[CSV] Summary exportado: %s", path);
    endtask


    task export_bus_metrics_csv();
        int fh;
        string path;

        real total_time;
        real bandwidth;

        total_time = $realtime - bus.sim_start_time;
        bandwidth = (total_time > 0.0) ?
            (bus.total_bytes_transferred / total_time) : 0.0;

        path = $sformatf(
            "%s/csv_bus_events/%s_%s_%s_bus_summary.csv",
            g_results_dir,
            g_run_id,
            g_protocol_name,
            g_workload_name
        );

        fh = $fopen(path, "w");

        if (fh == 0) begin
            $display("[ERROR] No se pudo abrir CSV bus summary: %s", path);
            return;
        end

        $fdisplay(fh,
            "run_id,timestamp,protocol,workload,total_requests,total_grants,total_mem_accesses,total_bytes,total_invalidations,total_updates,queue_backpressure_events,busrd,busrdx,busupd,total_time_ns,bandwidth_bytes_per_ns"
        );

        $fdisplay(fh,
            "%s,%s,%s,%s,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0.3f,%0.6f",
            g_run_id,
            g_run_timestamp,
            g_protocol_name,
            g_workload_name,
            bus.total_requests,
            bus.total_grants,
            bus.total_mem_accesses,
            bus.total_bytes_transferred,
            bus.total_invalidations,
            bus.total_updates,
            bus.queue_backpressure_events,
            bus.count_BusRd,
            bus.count_BusRdX,
            bus.count_BusUpd,
            total_time,
            bandwidth
        );

        $fclose(fh);

        $display("[CSV] Bus summary exportado: %s", path);
    endtask


    task export_memory_metrics_csv();
        int fh;
        string path;

        real total_time;
        real bandwidth;

        total_time = $realtime - memory.sim_start_time;
        bandwidth = (total_time > 0.0) ?
            (memory.total_bytes_transferred / total_time) : 0.0;

        path = $sformatf(
            "%s/csv_memory/%s_%s_%s_memory_metrics.csv",
            g_results_dir,
            g_run_id,
            g_protocol_name,
            g_workload_name
        );

        fh = $fopen(path, "w");

        if (fh == 0) begin
            $display("[ERROR] No se pudo abrir CSV memory metrics: %s", path);
            return;
        end

        $fdisplay(fh,
            "run_id,timestamp,protocol,workload,total_accesses,busrd,busrdx,busupd,total_bytes,sim_time_ns,bandwidth_bytes_per_ns,max_queue_length,avg_queue_wait_ns,avg_service_time_ns,avg_total_latency_ns,total_service_time_ns"
        );

        $fdisplay(fh,
            "%s,%s,%s,%s,%0d,%0d,%0d,%0d,%0d,%0.3f,%0.6f,%0d,%0.3f,%0.3f,%0.3f,%0.3f",
            g_run_id,
            g_run_timestamp,
            g_protocol_name,
            g_workload_name,
            memory.total_accesses,
            memory.total_reads,
            memory.total_rdx,
            memory.total_updates,
            memory.total_bytes_transferred,
            total_time,
            bandwidth,
            memory.max_queue_length,
            memory.get_avg_queue_wait(),
            memory.get_avg_service_time(),
            memory.get_avg_total_latency(),
            memory.total_service_time
        );

        $fclose(fh);

        $display("[CSV] Memory metrics exportado: %s", path);
endtask

    // TEST
    initial begin

        string trace_file;
        string protocol_name;
        Cache::protocol_e protocol_sel;


        string workload_plusarg;
        string run_id_plusarg;
        string run_timestamp_plusarg;
        string results_dir_plusarg;

        // Formato temporal global del testbench de integración (ns con 1 decimal).
        $timeformat(-9, 3, " ns", 10);



        if (!$value$plusargs("RUN_ID=%s", run_id_plusarg)) begin
            run_id_plusarg = "run_no_id";
        end

        if (!$value$plusargs("RUN_TIMESTAMP=%s", run_timestamp_plusarg)) begin
            run_timestamp_plusarg = "unknown_timestamp";
        end

        if (!$value$plusargs("WORKLOAD=%s", workload_plusarg)) begin
            workload_plusarg = "unknown_workload";
        end

        if (!$value$plusargs("RESULTS_DIR=%s", results_dir_plusarg)) begin
            results_dir_plusarg = "../sim_results";
        end

        g_run_id        = run_id_plusarg;
        g_run_timestamp = run_timestamp_plusarg;
        g_workload_name = workload_plusarg;
        g_results_dir   = results_dir_plusarg;


        $display("========================================");
        $display("   DEMO 2 - SISTEMA MULTICORE COMPLETO");
        $display("           (Cargando desde traces)");
        $display("========================================");

        // Lee plusarg +TRACE_FILE, si no existe usa string vacío
        if (!$value$plusargs("TRACE_FILE=%s", trace_file)) begin
            trace_file = "";
        end

        protocol_name = "";
        if ($value$plusargs("PROTOCOL=%s", protocol_name)) begin
            if (protocol_name == "MSI" || protocol_name == "msi") begin
                $display("[TopTB] Protocolo seleccionado: MSI");
                protocol_sel = Cache::MSI;
                g_protocol_name = "MSI";
            end else begin
                $display("[TopTB] Protocolo seleccionado: FIREFLY");
                protocol_sel = Cache::FIREFLY;
                g_protocol_name = "FIREFLY";
            end
        end else begin
            $display("[TopTB] +PROTOCOL no especificado");
            // salir
            $finish;
        end

        // Ejecuta un único escenario cargando desde archivo
        setup_system(protocol_sel);

        load_traces_from_file(trace_file);

        $display("[TopTB] RUN_ID       : %s", g_run_id);
        $display("[TopTB] TIMESTAMP    : %s", g_run_timestamp);
        $display("[TopTB] WORKLOAD     : %s", g_workload_name);
        $display("[TopTB] RESULTS_DIR  : %s", g_results_dir);

        $display("\n========== EJECUTANDO TRACES ==========\n");

        // No se hace por tiempo, se espera a que cores procesen todo su trace y luego se espera a que bus y memoria terminen de procesar todas las solicitudes.

        run_cores();

        wait (
            caches[0].get_total_accesses() == cores[0].trace_queue.size() &&
            caches[1].get_total_accesses() == cores[1].trace_queue.size() &&
            caches[2].get_total_accesses() == cores[2].trace_queue.size() &&
            caches[3].get_total_accesses() == cores[3].trace_queue.size()
        );

        wait (bus.is_idle());
        wait (memory.is_idle());

        #50;

        $display("\n========== METRICAS CACHES ==========");
        foreach (caches[i]) begin
            caches[i].print_metrics();
        end

        $display("\n========== METRICAS BUS ==========");
        bus.print_metrics();

        $display("\n========== METRICAS MEMORIA ==========");
        memory.print_metrics();

        if (fsm_monitor != null) begin
            fsm_monitor.close();
        end


        $display("\n========== EXPORTANDO CSV ==========");

        export_cache_metrics_csv();
        export_summary_csv();
        export_bus_metrics_csv();
        export_memory_metrics_csv();

        $display("[TopTB] PROTOCOL     : %s", g_protocol_name);

        $display("\n========== FIN SIMULACION ==========");
        $finish;

    end

endmodule