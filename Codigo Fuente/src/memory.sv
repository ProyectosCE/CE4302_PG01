import types_pkg::*;

/*
 * ============================================
 * ARCHIVO: memory.sv
 * DESCRIPCION GENERAL:
 *   Implementa la clase Memory como el punto unico de respuesta a
 *   solicitudes de bus. Responde a BusRd y BusRdX con latencia fija
 *   y mantiene una cola FIFO interna. Ignora BusUpd.
 *
 * NOTAS:
 *   - Latencia fija
 *   - Cola FIFO interna
 *   - Con metricas basicas
 *   - Scaffolding de write-back (no implementado aun)
 * ============================================
 */

class Memory;
	/** @brief Latencia fija de memoria (ciclos de 1ns en esta fase). */
	localparam int MEM_LATENCY_CYCLES = 20;

	/** @brief Profundidad maxima del buzon interno de solicitudes (backpressure). */
	localparam int MEM_MBX_DEPTH = 8;

	/** @brief Mailbox de entrada desde el bus (BusRequest). */
	BusReq_mbx from_bus;

	/** @brief Mailboxes de salida hacia caches (uno por core). */
	MemResp_mbx to_cache[];

	/** @brief Numero de cores del sistema. */
	int num_cores;

	/** @brief Elemento interno de cola con timestamp de llegada. */
	typedef struct {
		BusRequest req;
		time arrival_time;
	} mem_req_t;

	/** @brief Cola FIFO interna de solicitudes (mailbox bloqueante). */
	mailbox #(mem_req_t) req_mbx;

	// METRICAS
	/** @brief Contador total de solicitudes. */
	int total_requests;
	/** @brief Contador total de respuestas. */
	int total_responses;
	/** @brief Contador de solicitudes BusRd. */
	int busrd_count;
	/** @brief Contador de solicitudes BusRdX. */
	int busrdx_count;
	/** @brief Contador de solicitudes BusUpd. */
	int busupd_count;
	/** @brief Contador de write-backs observados (stub). */
	int writeback_count;
	/** @brief Respuestas por core (indice = core_id). */
	int responses_per_core[];
	/** @brief Tiempo total de servicio acumulado (end-to-end con espera en cola). */
	time total_service_time;
	/** @brief Contador de solicitudes rechazadas por falta de capacidad. */
	int rejected_requests;

	/** @brief Devuelve un nombre legible para el tipo de solicitud. */
	function string req_type_name(bus_req_type_e req_type);
		return bus_req_name(req_type);
	endfunction

	/**
	 * @brief Indica si una solicitud corresponde a un write-back.
	 * @details
	 *   TODO: Extender BusRequest con tipo de write-back en fases futuras.
	 */
	function bit is_writeback(BusRequest req);
		return 0;
	endfunction

	/**
	 * @brief Constructor.
	 * @param num_cores Numero de cores del sistema.
	 */
	function new(int num_cores);
		this.num_cores = num_cores;

		if (this.num_cores <= 0) begin
			$fatal(1, "[%0t] [MEM] ERROR num_cores invalido: %0d", $realtime, this.num_cores);
		end

		total_requests = 0;
		total_responses = 0;
		busrd_count = 0;
		busrdx_count = 0;
		busupd_count = 0;
		writeback_count = 0;
		total_service_time = 0;
		rejected_requests = 0;
		req_mbx = new();
		responses_per_core = new[num_cores];
		foreach (responses_per_core[i]) begin
			responses_per_core[i] = 0;
		end
	endfunction


	/**
	 * @brief Verifica si la memoria tiene capacidad para aceptar una nueva solicitud.
	 * @return 1 si hay espacio, 0 si se alcanzó el límite de profundidad.
	 */
	function bit has_capacity();
		return (req_mbx.num() < MEM_MBX_DEPTH);
	endfunction

	/**
	 * @brief Hilo recolector: recibe solicitudes y las encola.
	 */
	task collector_task();
		BusRequest req;
		mem_req_t item;
		bit got_req;

		forever begin
			// Intenta obtener solicitud sin bloquearse indefinidamente.
			got_req = from_bus.try_get(req);
			
			if (!got_req) begin
				// No hay solicitudes disponibles; espera.
				#1;
				continue;
			end

			if (req.src_core_id < 0 || req.src_core_id >= num_cores) begin
				$fatal(1, "[%0t] [MEM] ERROR src_core_id out of range: %0d",
					$realtime, req.src_core_id);
			end

			case (req.req_type)
				BusRd: begin
					total_requests++;
					busrd_count++;
				end
				BusRdX: begin
					total_requests++;
					busrdx_count++;
				end
				BusUpd: begin
					busupd_count++;
				end
				default: ;
			endcase

			$display("[%0t] [MEM] [Core %0d] RX type=%s addr=%s",
				$realtime, req.src_core_id, req_type_name(req.req_type), fmt_addr(req.address));

			if (req.req_type == BusUpd) begin
				$display("[%0t] [MEM] [Core %0d] IGNORE type=BusUpd no memory access",
					$realtime, req.src_core_id);
				continue;
			end

			// Verificar capacidad: backpressure.
			if (!has_capacity()) begin
				rejected_requests++;
				$display("[%0t] [MEM] [Core %0d] REJECT type=%s addr=%s (capacity full q=%0d/%0d)",
					$realtime, req.src_core_id, req_type_name(req.req_type), fmt_addr(req.address),
					req_mbx.num(), MEM_MBX_DEPTH);
				// En un sistema real, devolveríamos un NACK al bus.
				// Por simplicidad, rechazamos y el remitente debe reintentar.
				continue;
			end

			item.req = req;
			item.arrival_time = $time;
			req_mbx.put(item);
			$display("[%0t] [MEM] [Core %0d] ENQ type=%s addr=%s q=%0d/%0d",
				$realtime, req.src_core_id, req_type_name(req.req_type), fmt_addr(req.address),
				req_mbx.num(), MEM_MBX_DEPTH);
		end
	endtask


	/**
	 * @brief Hilo trabajador: procesa solicitudes en FIFO con latencia.
	 */
	task worker_task();
		mem_req_t item;
		BusRequest req;
		MemResponse resp;
		time t_end;
		time service_time;

		forever begin
			req_mbx.get(item);
			req = item.req;
			$display("[%0t] [MEM] [Core %0d] DEQ type=%s addr=%s q=%0d",
				$realtime, req.src_core_id, req_type_name(req.req_type), fmt_addr(req.address),
				req_mbx.num());

			if (is_writeback(req)) begin
				handle_writeback(req);
				continue;
			end

			if (req.req_type == BusRd || req.req_type == BusRdX) begin
				#MEM_LATENCY_CYCLES;
				t_end = $time;
				service_time = t_end - item.arrival_time;
				total_service_time += service_time;
				total_responses++;
				responses_per_core[req.src_core_id]++;
				resp = new(req.address, req.src_core_id);
				to_cache[req.src_core_id].put(resp);

				$display("[%0t] [MEM] [Core %0d] TX addr=%s service=%0t",
					$realtime, req.src_core_id, fmt_addr(req.address), service_time);
			end
		end
	endtask


	/**
	 * @brief Manejo de write-back (stub para fases futuras).
	 */
	task handle_writeback(BusRequest req);
		writeback_count++;
		$display("[%0t] [MEM] [Core %0d] WB stub addr=%s",
			$realtime, req.src_core_id, fmt_addr(req.address));
	endtask


	/**
	 * @brief Imprime las metricas de memoria.
	 */
	task print_metrics();
		time avg_service_time;

		$display("[%0t] [MEM] METRICS total_requests=%0d total_responses=%0d rejected=%0d",
			$realtime, total_requests, total_responses, rejected_requests);
		$display("[%0t] [MEM] METRICS BusRd=%0d BusRdX=%0d BusUpd=%0d",
			$realtime, busrd_count, busrdx_count, busupd_count);
		for (int i = 0; i < responses_per_core.size(); i++) begin
			$display("[%0t] [MEM] METRICS per_core core=%0d responses=%0d",
				$realtime, i, responses_per_core[i]);
		end
		if (total_responses > 0) begin
			avg_service_time = total_service_time / total_responses;
			$display("[%0t] [MEM] METRICS avg_service_time=%0t",
				$realtime, avg_service_time);
		end
		if (total_requests != total_responses) begin
			$error("[%0t] [MEM] ERROR total_requests != total_responses (%0d != %0d)",
				$realtime, total_requests, total_responses);
		end
	endtask


	/**
	 * @brief Bucle principal de memoria (cola FIFO y latencia fija).
	 */
	task run();
		if (from_bus == null) begin
			$fatal(1, "[%0t] [MEM] ERROR from_bus no inicializado", $realtime);
		end

		if (to_cache.size() < num_cores) begin
			$fatal(1, "[%0t] [MEM] ERROR to_cache size=%0d num_cores=%0d",
				$realtime, to_cache.size(), num_cores);
		end

		for (int i = 0; i < num_cores; i++) begin
			if (to_cache[i] == null) begin
				$fatal(1, "[%0t] [MEM] ERROR to_cache[%0d] no inicializado", $realtime, i);
			end
		end

		fork
			collector_task();
			worker_task();
		join_none
	endtask

endclass
