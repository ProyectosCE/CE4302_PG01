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

	/** @brief Colas por core para requests entrantes. */
	BusRequest req_queues[][$];

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

		for (int i = 0; i < this.num_cores; i++) begin
			this.bus_evt_mbx[i] = bus_evt_mbx[i];
			this.mem_mbx[i] = mem_mbx[i];
		end

		for (int i = 0; i < this.num_cores; i++) begin
			this.req_queues[i] = {};
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

			req_queues[core_id].push_back(req);

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
		int core_id;
		forever begin
			if (!has_pending_requests()) begin
				$display("@%0t [BUS] No pending requests, waiting...", $realtime);
				@queue_event;
			end

			$display("@%0t [BUS] Scheduler evaluating queues", $realtime);
			core_id = get_next_core_rr();

			if (core_id < 0) begin
				$display("@%0t [BUS] No pending requests, waiting...", $realtime);
				@queue_event;
				continue;
			end

			req = req_queues[core_id].pop_front();
			$display("@%0t [BUS] GRANT core=%0d type=%0d addr=%h",
				$realtime, core_id, req.req_type, req.address);

			rr_ptr = (core_id + 1) % num_cores;
		end
	endtask

endclass
