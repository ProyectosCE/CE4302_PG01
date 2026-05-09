import types_pkg::*;

/*
 * CLASS: Memory
 * Implementa un servicio de memoria (no sintetizable) que recibe
 * solicitudes mediante `BusRequest` vía `BusReq_mbx` y responde con
 * `MemResponse` usando `MemResp_mbx[]`.
 *
 * Métricas incluidas:
 *  - total_accesses, total_reads, total_rdx, total_updates
 *  - total_bytes_transferred
 *  - cola interna (req_queue) y max_queue_length
 *  - total_queue_wait_time, total_service_time, total_total_latency
 */

class Memory;

    // Interfaces
    BusReq_mbx  bus_mbx;       // mailbox para recibir BusRequest
    MemResp_mbx mem_mbx[];     // mailboxes para responder a cada core
    int         num_cores;

    // Params (bytes)
    localparam int LINE_SIZE   = 32;
    localparam int UPDATE_SIZE = 4;

    real mem_bandwidth_bytes_per_ns;

    // Cola interna de solicitudes
    BusRequest req_queue[$];

    // Métricas
    int total_accesses;
    int total_reads;
    int total_rdx;
    int total_updates;
    int total_bytes_transferred;

    real total_queue_wait_time;
    real total_service_time;
    real total_total_latency;
    int  max_queue_length;

    real sim_start_time;

    // Notifier
    event queue_event;

    // Constructor
    function new(BusReq_mbx bus_mbx, MemResp_mbx mem_mbx[], int num_cores = 4, real bandwidth = 8.0);
        this.bus_mbx = bus_mbx;
        this.num_cores = num_cores;
        this.mem_mbx = new[mem_mbx.size()];
        for (int i = 0; i < mem_mbx.size() && i < this.mem_mbx.size(); i++) begin
            this.mem_mbx[i] = mem_mbx[i];
        end

        this.mem_bandwidth_bytes_per_ns = bandwidth;

        // init metrics
        this.total_accesses = 0;
        this.total_reads = 0;
        this.total_rdx = 0;
        this.total_updates = 0;
        this.total_bytes_transferred = 0;
        this.total_queue_wait_time = 0.0;
        this.total_service_time = 0.0;
        this.total_total_latency = 0.0;
        this.max_queue_length = 0;
        this.sim_start_time = 0.0;
    endfunction

    // Arranca los procesos internos
    task run();
        this.sim_start_time = $realtime;
        fork
            collector_loop();
            server_loop();
        join_none
    endtask

    // Collector: recibe BusRequest y encola
    task collector_loop();
        BusRequest req;
        forever begin
            bus_mbx.get(req);
            req.t_enqueue = $realtime;
            req_queue.push_back(req);
            if (req_queue.size() > this.max_queue_length) this.max_queue_length = req_queue.size();
            this.total_bytes_transferred += get_transaction_size(req);
            -> queue_event;
            $display("@%0t [MEM][ENQ] core=%0d type=%0d addr=%h q=%0d", $realtime, req.src_core_id, req.req_type, req.address, req_queue.size());
        end
    endtask

    // Server: atiende cola (single-port behavioral)
    task server_loop();
        BusRequest req;
        real t_start;
        real t_done;
        forever begin
            if (req_queue.size() == 0) begin
                @queue_event;
                continue;
            end

            req = req_queue.pop_front();
            t_start = $realtime;
            real queue_wait = t_start - req.t_enqueue;
            this.total_queue_wait_time += queue_wait;

            int bytes = get_transaction_size(req);
            real service_time = bytes / this.mem_bandwidth_bytes_per_ns;

            // contabilizar por tipo
            case (req.req_type)
                BusRd:  this.total_reads++;
                BusRdX: this.total_rdx++;
                BusUpd: this.total_updates++;
                default: ;
            endcase

            // Simula servicio
            # (service_time);

            // Responder al core origen
            if (req.src_core_id >= 0 && req.src_core_id < this.mem_mbx.size()) begin
                MemResponse resp = new(req.address, req.src_core_id);
                this.mem_mbx[req.src_core_id].put(resp);
            end else begin
                $display("@%0t [MEM] WARN src_core_id fuera de rango=%0d", $realtime, req.src_core_id);
            end

            t_done = $realtime;
            this.total_service_time += service_time;
            this.total_total_latency += (t_done - req.t_enqueue);
            this.total_accesses++;

            $display("@%0t [MEM][DONE] core=%0d type=%0d addr=%h q_wait=%0f svc=%0f", t_done, req.src_core_id, req.req_type, req.address, queue_wait, service_time);
        end
    endtask

    function int get_transaction_size(BusRequest req);
        case (req.req_type)
            BusRd:  return LINE_SIZE;
            BusRdX: return LINE_SIZE;
            BusUpd: return UPDATE_SIZE;
            default: return LINE_SIZE;
        endcase
    endfunction

    function real get_avg_queue_wait();
        return (this.total_accesses > 0) ? (this.total_queue_wait_time / real'(this.total_accesses)) : 0.0;
    endfunction

    function real get_avg_service_time();
        return (this.total_accesses > 0) ? (this.total_service_time / real'(this.total_accesses)) : 0.0;
    endfunction

    function real get_avg_total_latency();
        return (this.total_accesses > 0) ? (this.total_total_latency / real'(this.total_accesses)) : 0.0;
    endfunction

    function void print_metrics();
        real total_time = $realtime - this.sim_start_time;
        real bandwidth = (total_time > 0.0) ? (this.total_bytes_transferred / total_time) : 0.0;

        $display("\n=== MEMORY METRICS ===");
        $display("total_accesses       : %0d", this.total_accesses);
        $display("  BusRd               : %0d", this.total_reads);
        $display("  BusRdX              : %0d", this.total_rdx);
        $display("  BusUpd              : %0d", this.total_updates);
        $display("total_bytes_transfer : %0d bytes", this.total_bytes_transferred);
        $display("sim_time             : %0f ns", total_time);
        $display("bandwidth            : %0f bytes/ns", bandwidth);
        $display("max_queue_length     : %0d", this.max_queue_length);
        $display("avg_queue_wait       : %0.3f ns", get_avg_queue_wait());
        $display("avg_service_time     : %0.3f ns", get_avg_service_time());
        $display("avg_total_latency    : %0.3f ns", get_avg_total_latency());
        $display("total_service_time   : %0.3f ns", this.total_service_time);
        $display("======================\n");
    endfunction

endclass