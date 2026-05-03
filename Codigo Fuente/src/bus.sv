import types_pkg::*;

/*
 * ============================================
 * ARCHIVO: bus.sv
 * DESCRIPCION GENERAL:
 *   Define la clase Bus como punto central de comunicacion entre caches y
 *   memoria. 
 *
 * RESPONSABILIDAD :
 *   - Recibir solicitudes desde las caches (BusReq_mbx compartido).
 *   - Clasificar solicitudes en colas internas por core.
 *   - Preparar el flujo concurrente para fases posteriores.
 *
 * NOTA:
 *   - No implementa arbitraje, broadcast, ni respuestas de memoria.
 * ============================================
 */

/**
 * @brief Clase Bus base.
 *        Prepara la infraestructura para arbitraje y transacciones futuras.
 */
class Bus;

	/** @brief Mailbox compartido de entrada desde caches. */
	BusReq_mbx bus_mbx;

	/** @brief Mailboxes de broadcast hacia caches (uno por core). */
	BusEvt_mbx bus_evt_mbx[];

	/** @brief Mailboxes de respuesta desde memoria hacia caches (uno por core). */
	MemResp_mbx mem_mbx[];

	/** @brief Numero de cores del sistema. */
	int num_cores;

	/** @brief Puntero de round robin para arbitraje. */
	int rr_ptr;

	/** @brief Tamano de linea de cache (bytes). */
	localparam int LINE_SIZE = 32;

	/** @brief Tamano de actualizacion en BusUpd (bytes). */
	localparam int UPDATE_SIZE = 4;

	/** @brief Ancho de banda del bus (bytes/ns). */
	real bus_bandwidth_bytes_per_ns;

	/** @brief Colas por core para requests entrantes. */
	BusRequest req_queues[][$];

	// Metrics: global counters
	int total_requests;
	int total_grants;
	int total_mem_accesses;
	int total_bytes_transferred;

	// Metrics: per-core counters
	int per_core_requests[];
	int per_core_grants[];

	// Metrics: per-type counters
	int count_BusRd;
	int count_BusRdX;
	int count_BusUpd;

	// Metrics: latency accumulators (ns)
	real total_queue_wait_time;
	real total_service_time;
	real total_total_latency;

	// Optional: per-type latency accumulators
	real latency_BusRd;
	real latency_BusRdX;
	real latency_BusUpd;

	// Simulation time tracking
	real sim_start_time;

	/**
	 * @brief Evento de notificacion para el scheduler.
	 *        Nota: puede perder pulsos si llegan multiples eventos seguidos.
	 */
	event queue_event;

	/**
	 * @brief Constructor del Bus.
	 * @param bus_mbx Mailbox compartido de solicitudes desde caches.
	 * @param bus_evt_mbx Arreglo de mailboxes para broadcast a caches.
	 * @param mem_mbx Arreglo de mailboxes para respuestas de memoria.
	 * @param num_cores Numero de cores del sistema.
	 */
	function new(
		BusReq_mbx bus_mbx,
		BusEvt_mbx bus_evt_mbx[],
		MemResp_mbx mem_mbx[],
		int num_cores
	);
		int evt_size;
		int mem_size;

		this.bus_mbx = bus_mbx;
		this.num_cores = num_cores;
		this.rr_ptr = 0;
		this.bus_bandwidth_bytes_per_ns = 4.0;
		this.sim_start_time = $realtime;

		this.total_requests = 0;
		this.total_grants = 0;
		this.total_mem_accesses = 0;
		this.total_bytes_transferred = 0;
		this.count_BusRd = 0;
		this.count_BusRdX = 0;
		this.count_BusUpd = 0;
		this.total_queue_wait_time = 0.0;
		this.total_service_time = 0.0;
		this.total_total_latency = 0.0;
		this.latency_BusRd = 0.0;
		this.latency_BusRdX = 0.0;
		this.latency_BusUpd = 0.0;

		if (this.bus_mbx == null) begin
			$fatal(1, "[Bus] bus_mbx no inicializado");
		end
		if (this.num_cores <= 0) begin
			$fatal(1, "[Bus] num_cores invalido: %0d", this.num_cores);
		end

		evt_size = bus_evt_mbx.size();
		mem_size = mem_mbx.size();

		if (evt_size < this.num_cores) begin
			$fatal(1, "[Bus] bus_evt_mbx size=%0d, num_cores=%0d", evt_size, this.num_cores);
		end
		if (mem_size < this.num_cores) begin
			$fatal(1, "[Bus] mem_mbx size=%0d, num_cores=%0d", mem_size, this.num_cores);
		end

		this.bus_evt_mbx = new[this.num_cores];
		this.mem_mbx = new[this.num_cores];
		this.req_queues = new[this.num_cores];
		this.per_core_requests = new[this.num_cores];
		this.per_core_grants = new[this.num_cores];

		for (int i = 0; i < this.num_cores; i++) begin
			this.bus_evt_mbx[i] = bus_evt_mbx[i];
			this.mem_mbx[i] = mem_mbx[i];
		end

		for (int i = 0; i < this.num_cores; i++) begin
			this.req_queues[i] = {};
			this.per_core_requests[i] = 0;
			this.per_core_grants[i] = 0;
		end
	endfunction


	/**
	 * @brief Inicia el Bus con dos threads concurrentes:
	 *        - Collector: recibe solicitudes y las encola por core.
	 *        - Scheduler: placeholder para futuras fases.
	 */
	task run();
		fork
			collector_loop();
			scheduler_loop();
		join_none
	endtask


	/**
	 * @brief Indica si existe al menos una solicitud pendiente en cualquier cola.
	 * @return 1 si hay elementos, 0 si todas las colas estan vacias.
	 */
	function bit has_pending_requests();
		for (int i = 0; i < num_cores; i++) begin
			if (req_queues[i].size() > 0) begin
				return 1;
			end
		end
		return 0;
	endfunction


	/**
	 * @brief Devuelve el tamano de la transaccion (bytes) segun el tipo.
	 * @param req Solicitud del bus.
	 * @return Tamano en bytes.
	 */
	function int get_transaction_size(BusRequest req);
		case (req.req_type)
			BusRd:  return LINE_SIZE;
			BusRdX: return LINE_SIZE;
			BusUpd: return UPDATE_SIZE;
			default: return LINE_SIZE;
		endcase
	endfunction


	/**
	 * @brief Busca el siguiente core con solicitudes pendientes usando round robin.
	 * @return Indice del core con cola no vacia, o -1 si todas estan vacias.
	 */
	function int get_next_core_rr();
		for (int i = 0; i < num_cores; i++) begin
			int idx;
			idx = (rr_ptr + i) % num_cores;
			if (req_queues[idx].size() > 0) begin
				return idx;
			end
		end
		return -1;
	endfunction


	/**
	 * @brief Crea un evento de bus a partir de una solicitud.
	 * @param req Solicitud del bus.
	 * @return Evento de bus listo para broadcast.
	 */
	function BusEvent create_bus_event(BusRequest req);
		BusEvent evt;
		case (req.req_type)
			BusRd:  evt = new(BusRd, req.address, req.src_core_id);
			BusRdX: evt = new(BusRdX, req.address, req.src_core_id);
			BusUpd: evt = new(BusUpd, req.address, req.src_core_id);
			default: evt = new(req.req_type, req.address, req.src_core_id);
		endcase
		return evt;
	endfunction


	/**
	 * @brief Broadcast de evento a todas las caches.
	 * @param evt Evento a difundir.
	 */
	task broadcast_event(BusEvent evt);
		for (int i = 0; i < num_cores; i++) begin
			BusEvent evt_copy;
			evt_copy = new(evt.req_type, evt.address, evt.src_core_id);
			bus_evt_mbx[i].put(evt_copy);
		end
		$display("@%0t [BUS] BROADCAST type=%0d addr=%h src=%0d",
			$realtime, evt.req_type, evt.address, evt.src_core_id);
	endtask


	/**
	 * @brief Thread colector: recibe solicitudes del mailbox compartido
	 *        y las clasifica por core.
	 */
	task collector_loop();
		BusRequest req;
		int core_id;

		forever begin
			bus_mbx.get(req);
			core_id = req.src_core_id;

			if (core_id < 0 || core_id >= num_cores) begin
				$display("@%0t [BUS] WARN: src_core_id invalido=%0d addr=%h",
					$realtime, core_id, req.address);
				continue;
			end

			req.t_enqueue = $realtime;
			total_requests++;
			per_core_requests[core_id]++;
			req_queues[core_id].push_back(req);
			// Enqueue timestamp for metrics

			// Nota: logging de debug
			$display("@%0t [BUS] Recibido req core=%0d type=%0d addr=%h (q=%0d)",
				$realtime, core_id, req.req_type, req.address, req_queues[core_id].size());

			-> queue_event;
		end
	endtask


	/**
	 * @brief Thread scheduler (placeholder). No realiza arbitraje aun.
	 *        Solo reacciona a nuevas solicitudes sin bloquear la simulacion.
	 *        Limitacion: @queue_event puede perder eventos si llegan muy seguido.
	 */
	task scheduler_loop();
		BusRequest req;
		BusEvent evt;
		MemResponse mem_resp;
		int core_id;
		int bytes;
		real t_grant;
		real t_done;
		real latency;
		real queue_wait;
		real service_time;
		real total_latency;
		forever begin
			core_id = get_next_core_rr();

			if (core_id < 0) begin
				$display("@%0t [BUS] No pending requests, waiting...", $realtime);
				@queue_event;
				continue;
			end

			req = req_queues[core_id].pop_front();
			t_grant = $realtime;
			queue_wait = t_grant - req.t_enqueue;
			total_grants++;
			per_core_grants[core_id]++;
			total_queue_wait_time += queue_wait;
			case (req.req_type)
				BusRd:  count_BusRd++;
				BusRdX: count_BusRdX++;
				BusUpd: count_BusUpd++;
			endcase
			$display("@%0t [BUS] GRANT core=%0d type=%0d addr=%h",
				$realtime, core_id, req.req_type, req.address);

			// Yield para evitar delta-cycle lock
			#0;

			evt = create_bus_event(req);
			broadcast_event(evt);
			// Yield to allow caches to react to broadcast
			#0;

			bytes = get_transaction_size(req);
			latency = bytes / bus_bandwidth_bytes_per_ns;
			total_bytes_transferred += bytes;

			#(latency);

			if (req.req_type == BusRd || req.req_type == BusRdX) begin
				total_mem_accesses++;
				mem_resp = new(req.address, core_id);
				mem_mbx[core_id].put(mem_resp);
			end

			// Yield to allow caches to process the response
			#0;

			t_done = $realtime;
			service_time = t_done - t_grant;
			total_latency = t_done - req.t_enqueue;
			total_service_time += service_time;
			total_total_latency += total_latency;
			case (req.req_type)
				BusRd:  latency_BusRd += total_latency;
				BusRdX: latency_BusRdX += total_latency;
				BusUpd: latency_BusUpd += total_latency;
			endcase
			$display("@%0t [BUS] DONE core=%0d type=%0d addr=%h latency=%0f ns bytes=%0d",
				$t_done, core_id, req.req_type, req.address, latency, bytes);

			rr_ptr = (core_id + 1) % num_cores;
		end
	endtask


	/**
	 * @brief Imprime los metrics acumulados del bus.
	 */
	function void print_metrics();
		real avg_queue_wait;
		real avg_service_time;
		real avg_total_latency;
		real total_time;
		real bandwidth;
		real avg_latency_BusRd;
		real avg_latency_BusRdX;
		real avg_latency_BusUpd;

		avg_queue_wait = (total_grants > 0) ? (total_queue_wait_time / total_grants) : 0.0;
		avg_service_time = (total_grants > 0) ? (total_service_time / total_grants) : 0.0;
		avg_total_latency = (total_grants > 0) ? (total_total_latency / total_grants) : 0.0;

		avg_latency_BusRd = (count_BusRd > 0) ? (latency_BusRd / count_BusRd) : 0.0;
		avg_latency_BusRdX = (count_BusRdX > 0) ? (latency_BusRdX / count_BusRdX) : 0.0;
		avg_latency_BusUpd = (count_BusUpd > 0) ? (latency_BusUpd / count_BusUpd) : 0.0;

		total_time = $realtime - sim_start_time;
		bandwidth = (total_time > 0.0) ? (total_bytes_transferred / total_time) : 0.0;

		$display("===== BUS METRICS =====");
		$display("total_requests=%0d total_grants=%0d total_mem_accesses=%0d total_bytes=%0d",
			total_requests, total_grants, total_mem_accesses, total_bytes_transferred);
		$display("per_core stats:");
		for (int i = 0; i < num_cores; i++) begin
			$display("  core%0d req=%0d grant=%0d", i, per_core_requests[i], per_core_grants[i]);
		end
		$display("per_type counts: BusRd=%0d BusRdX=%0d BusUpd=%0d",
			count_BusRd, count_BusRdX, count_BusUpd);
		$display("avg_queue_wait=%0f ns avg_service=%0f ns avg_total=%0f ns",
			avg_queue_wait, avg_service_time, avg_total_latency);
		$display("avg_latency_BusRd=%0f ns avg_latency_BusRdX=%0f ns avg_latency_BusUpd=%0f ns",
			avg_latency_BusRd, avg_latency_BusRdX, avg_latency_BusUpd);
		$display("total_time=%0f ns bandwidth=%0f bytes/ns", total_time, bandwidth);
	endfunction

endclass
