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
 *   - Sin metricas
 * ============================================
 */

class Memory;
	/** @brief Latencia fija de memoria (ciclos de 1ns en esta fase). */
	localparam int MEM_LATENCY_CYCLES = 20;

	/** @brief Mailbox de entrada desde el bus (BusRequest). */
	BusReq_mbx from_bus;

	/** @brief Mailboxes de salida hacia caches (uno por core). */
	MemResp_mbx to_cache[];

	/** @brief Numero de cores del sistema. */
	int num_cores;

	/** @brief Cola FIFO interna de solicitudes. */
	BusRequest req_queue[$];

	/** @brief Evento para notificar nuevas solicitudes. */
	event req_available;

	/** @brief Devuelve un nombre legible para el tipo de solicitud. */
	function string req_type_name(bus_req_type_e req_type);
		case (req_type)
			BusRd:  return "BusRd";
			BusRdX: return "BusRdX";
			BusUpd: return "BusUpd";
			default: return "Unknown";
		endcase
	endfunction

	/**
	 * @brief Constructor.
	 * @param num_cores Numero de cores del sistema.
	 */
	function new(int num_cores);
		this.num_cores = num_cores;

		if (this.num_cores <= 0) begin
			$fatal(1, "[Memory] num_cores invalido: %0d", this.num_cores);
		end
	endfunction


	/**
	 * @brief Hilo recolector: recibe solicitudes y las encola.
	 */
	task collector_task();
		BusRequest req;

		forever begin
			from_bus.get(req);

			if (req.src_core_id < 0 || req.src_core_id >= num_cores) begin
				$fatal(1, "[Memory] src_core_id out of range: %0d", req.src_core_id);
			end

			$display("@%0t [Memory] RX core=%0d type=%s addr=%h",
				$realtime, req.src_core_id, req_type_name(req.req_type), req.address);

			req_queue.push_back(req);
			-> req_available;
		end
	endtask


	/**
	 * @brief Hilo trabajador: procesa solicitudes en FIFO con latencia.
	 */
	task worker_task();
		BusRequest req;
		MemResponse resp;

		forever begin
			while (req_queue.size() == 0) begin
				@req_available;
			end

			req = req_queue.pop_front();

			if (req.req_type == BusRd || req.req_type == BusRdX) begin
				#MEM_LATENCY_CYCLES;
				resp = new(req.address, req.src_core_id);
				to_cache[req.src_core_id].put(resp);

				$display("@%0t [Memory] TX core=%0d addr=%h",
					$realtime, req.src_core_id, req.address);
			end
		end
	endtask


	/**
	 * @brief Bucle principal de memoria (cola FIFO y latencia fija).
	 */
	task run();
		if (from_bus == null) begin
			$fatal(1, "[Memory] from_bus no inicializado");
		end

		if (to_cache.size() < num_cores) begin
			$fatal(1, "[Memory] to_cache size=%0d, num_cores=%0d",
				to_cache.size(), num_cores);
		end

		for (int i = 0; i < num_cores; i++) begin
			if (to_cache[i] == null) begin
				$fatal(1, "[Memory] to_cache[%0d] no inicializado", i);
			end
		end

		fork
			collector_task();
			worker_task();
		join_none
	endtask

endclass
