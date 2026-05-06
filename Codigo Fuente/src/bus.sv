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
 *   - No implementa arbitraje, difusion, ni respuestas de memoria.
 * ============================================
 */

/**
 * @brief Modelo de bus de interconexion coherente para un sistema multicore.
 *
 * @details
 *   El Bus es la interconexion central que coordina el trafico de coherencia
 *   entre caches y memoria principal mediante buzones de mensajes. Acepta solicitudes
 *   del bus (BusRd, BusRdX, BusUpd), realiza arbitraje RR sobre colas
 *   por core, difunde un BusEvent a todas las caches y emite una respuesta
 *   de memoria para lecturas luego de una latencia de transferencia modelada.
 *
 *   Flujo general:
 *     Core -> Cache -> BusReq_mbx -> Bus (RR) -> difusion ->
 *     respuesta de memoria (para BusRd/BusRdX).
 *
 *   Modelo de tiempo:
 *     latencia = bytes / ancho de banda, medido con $realtime.
 *
 *   Supuestos del modelo:
 *     - Bus compartido bloqueante (una transaccion a la vez).
 *     - Modelo solo de direcciones (sin datos reales).
 *     - No hay transferencias cache a cache; la memoria siempre responde.
 *
 * @section decisiones_de_diseno Decisiones de diseno
 *   - Politica RR ofrece equidad y evita inanicion.
 *   - Colas por core preservan RR sin cambiar interfaces.
 *   - La respuesta de memoria se modela en el bus como fuente unica de tiempo.
 *   - Latencia derivada de bytes/ancho de banda evita retrasos fijos arbitrarios.
 *   - Solo BusRd/BusRdX generan MemResponse (BusUpd es solo coherencia).
 */
class Bus;

	/** @brief Buzon compartido de entrada desde caches. */
	BusReq_mbx bus_mbx;

	/** @brief Buzon opcional de solicitudes hacia memoria (BusRequest). */
	BusReq_mbx bus_to_mem;

	/** @brief Buzones de difusion hacia caches (uno por core). */
	BusEvt_mbx bus_evt_mbx[];

	/** @brief Buzones de respuesta desde memoria hacia caches (uno por core). */
	MemResp_mbx mem_mbx[];

	/** @brief Buzones de ack desde caches para sincronizar broadcasts (opcional). */
	BusAck_mbx bus_evt_ack_mbx[];

	/** @brief Numero de cores del sistema. */
	int num_cores;

	/** @brief Puntero RR para equidad y evitar inanicion. */
	int rr_ptr;

	/** @brief Tamano de linea de cache (bytes). */
	localparam int LINE_SIZE = 32;

	/** @brief Tamano de actualizacion en BusUpd (bytes). */
	localparam int UPDATE_SIZE = 4;

	/** @brief Abstraccion temporal: ancho de banda efectivo en bytes/ns. */
	real bus_bandwidth_bytes_per_ns;

	/** @brief Profundidad maxima del buzon de solicitudes (backpressure). */
	localparam int BUS_MBX_DEPTH = 16;

	/** @brief Contador de transacciones rechazadas por falta de capacidad. */
	int rejected_requests;

	/**
	 * @brief Colas por core para preservar RR sin alterar el buzon compartido.
	 *
	 * @details
	 *   Permiten arbitraje por core sin introducir una FIFO global que cambie
	 *   el comportamiento observable de las solicitudes.
	 */
	BusRequest req_queues[][$];

	/** @brief Total de solicitudes encoladas observadas por el bus. */
	int total_requests;
	/** @brief Total de concesiones emitidas por el planificador. */
	int total_grants;
	/** @brief Total de accesos a memoria (solo BusRd/BusRdX). */
	int total_mem_accesses;
	/** @brief Total de bytes transferidos en el bus (modelo). */
	int total_bytes_transferred;
	/** @brief Invalidaciones inferidas a partir de BusRdX. */
	int total_invalidations;
	/** @brief Actualizaciones inferidas a partir de BusUpd. */
	int total_updates;

	/** @brief Identificador monotono de transacciones (concesiones). */
	int grant_id;

	/** @brief Conteo por core de solicitudes encoladas. */
	int per_core_requests[];
	/** @brief Conteo por core de concesiones emitidas. */
	int per_core_grants[];

	/** @brief Cantidad de transacciones BusRd concedidas. */
	int count_BusRd;
	/** @brief Cantidad de transacciones BusRdX concedidas. */
	int count_BusRdX;
	/** @brief Cantidad de transacciones BusUpd concedidas. */
	int count_BusUpd;

	/** @brief Suma de tiempos en cola (t_grant - t_enqueue). */
	real total_queue_wait_time;
	/** @brief Suma de tiempos de servicio (t_done - t_grant). */
	real total_service_time;
	/** @brief Suma de latencias totales (t_done - t_enqueue). */
	real total_total_latency;

	/** @brief Suma de latencia total de BusRd (para promedios). */
	real latency_BusRd;
	/** @brief Suma de latencia total de BusRdX (para promedios). */
	real latency_BusRdX;
	/** @brief Suma de latencia total de BusUpd (para promedios). */
	real latency_BusUpd;

	/** @brief Tiempo de inicio de simulacion para normalizar el ancho de banda. */
	real sim_start_time;

	/**
	 * @brief Evento de notificacion para el planificador.
	 *        Nota: puede perder pulsos si llegan multiples eventos seguidos.
	 */
	event queue_event;

	/**
	 * @brief Constructor del Bus.
	 * @param bus_mbx Buzon compartido de solicitudes desde caches.
	 * @param bus_evt_mbx Arreglo de buzones para difusion a caches.
	 * @param mem_mbx Arreglo de buzones para respuestas de memoria.
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
		this.bus_to_mem = null;
		this.total_requests = 0;
		this.total_grants = 0;
		this.total_mem_accesses = 0;
		this.total_bytes_transferred = 0;
		this.total_invalidations = 0;
		this.total_updates = 0;
		this.grant_id = 0;
		this.count_BusRd = 0;
		this.count_BusRdX = 0;
		this.count_BusUpd = 0;
		this.total_queue_wait_time = 0.0;
		this.total_service_time = 0.0;
		this.total_total_latency = 0.0;
		this.latency_BusRd = 0.0;
		this.latency_BusRdX = 0.0;
		this.latency_BusUpd = 0.0;
		this.rejected_requests = 0;

		if (this.bus_mbx == null) begin
			$fatal(1, "[%0t] [BUS] ERROR bus_mbx no inicializado", $realtime);
		end
		if (this.num_cores <= 0) begin
			$fatal(1, "[%0t] [BUS] ERROR num_cores invalido: %0d", $realtime, this.num_cores);
		end

		evt_size = bus_evt_mbx.size();
		mem_size = mem_mbx.size();

		if (evt_size < this.num_cores) begin
			$fatal(1, "[%0t] [BUS] ERROR bus_evt_mbx size=%0d num_cores=%0d",
				$realtime, evt_size, this.num_cores);
		end
		if (mem_size < this.num_cores) begin
			$fatal(1, "[%0t] [BUS] ERROR mem_mbx size=%0d num_cores=%0d",
				$realtime, mem_size, this.num_cores);
		end

		this.bus_evt_mbx = new[this.num_cores];
		this.mem_mbx = new[this.num_cores];
		this.bus_evt_ack_mbx = null;
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
	 * @brief Inicia el Bus con dos hilos concurrentes:
	 *        - Recolector: recibe solicitudes y las encola por core.
	 *        - Planificador: esqueleto para futuras fases.
	 */
	task run();
		sim_start_time = $realtime;
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
	 * @brief Verifica si el bus tiene capacidad para aceptar una nueva solicitud.
	 * @return 1 si hay espacio, 0 si se alcanzó el límite de profundidad.
	 */
	function bit has_capacity();
		int total_queued;
		total_queued = 0;
		for (int i = 0; i < num_cores; i++) begin
			total_queued += req_queues[i].size();
		end
		return (total_queued < BUS_MBX_DEPTH);
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


	/** @brief Devuelve un nombre legible para el tipo de solicitud. */
	function string req_type_name(bus_req_type_e req_type);
		return bus_req_name(req_type);
	endfunction


	/**
	 * @brief Busca el siguiente core con solicitudes pendientes usando RR.
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
	 * @return Evento de bus listo para difusion.
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
	 * @brief Difusion de evento a todas las caches.
	 * @param evt Evento a difundir.
	 */
	task broadcast_event(BusEvent evt);
		for (int i = 0; i < num_cores; i++) begin
			BusEvent evt_copy;
			evt_copy = new(evt.req_type, evt.address, evt.src_core_id);
			evt_copy.t_broadcast = $realtime;
			bus_evt_mbx[i].put(evt_copy);
		end
		$display("[%0t] [BUS] BROADCAST type=%s addr=%s src=%0d",
			$realtime, req_type_name(evt.req_type), fmt_addr(evt.address), evt.src_core_id);
	endtask


	/**
	 * @brief Hilo recolector: recibe solicitudes y encola por core.
	 *
	 * @details
	 *   Corre en paralelo con el planificador (fork/join_none). Separar la
	 *   recepcion del arbitraje permite que el bus siga aceptando trafico
	 *   mientras se ejecuta una transaccion ya concedida.
	 *   
	 *   Con backpressure: el buzon se mantiene no bloqueante con try_get(),
	 *   pero se verifica la capacidad interna para simular limites reales.
	 */
	task collector_loop();
		BusRequest req;
		int core_id;
		bit got_req;

		forever begin
			// Intenta obtener solicitud sin bloquearse indefinidamente.
			// Si hay espacio en el bus, acepta; si no, rechaza (simula backpressure).
			got_req = bus_mbx.try_get(req);
			
			if (!got_req) begin
				// No hay solicitudes disponibles; espera.
				#1;
				continue;
			end
			
			core_id = req.src_core_id;

			if (core_id < 0 || core_id >= num_cores) begin
				$display("[%0t] [BUS] WARN invalid src_core_id=%0d addr=%s",
					$realtime, core_id, fmt_addr(req.address));
				continue;
			end

			// Verificar capacidad: backpressure.
			if (!has_capacity()) begin
				rejected_requests++;
				$display("[%0t] [BUS] [Core %0d] REJECT type=%s addr=%s (capacity full q=%0d/%0d)",
					$realtime, core_id, req_type_name(req.req_type), fmt_addr(req.address),
					0, BUS_MBX_DEPTH);
				// En un sistema real, devolveríamos un NACK o esperaríamos.
				// Por simplicidad, rechazamos y el remitente debe reintentar (fuera del alcance del testbench).
				continue;
			end

			req.t_enqueue = $realtime; // Referencia para medir tiempo en cola.
			total_requests++;
			per_core_requests[core_id]++;
			req_queues[core_id].push_back(req);
			// Marca de encolado para metricas

			// Nota: registro de depuracion
			$display("[%0t] [BUS] [Core %0d] ENQ type=%s addr=%s q=%0d/%0d",
				$realtime, core_id, req_type_name(req.req_type), fmt_addr(req.address),
				req_queues[core_id].size(), BUS_MBX_DEPTH);

			-> queue_event;
		end
	endtask


	/**
	 * @brief Hilo planificador: arbitraje y ejecucion de transacciones.
	 *
	 * @details
	 *   Corre en paralelo con el recolector. Selecciona el siguiente core
	 *   con politica RR, difunde el evento de coherencia, modela la latencia
	 *   del bus y emite respuestas de memoria para lecturas. Esta separacion
	 *   mejora el realismo al mantener un bus bloqueante sin frenar la entrada.
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
			real pure_bus_latency;
		real queue_wait;
		real service_time;
		real total_latency;
		forever begin
			// Seleccion de core segun politica RR sobre colas por core.
			core_id = get_next_core_rr();

			if (core_id < 0) begin
				$display("[%0t] [BUS] IDLE no pending requests", $realtime);
				@queue_event;
				continue;
			end

			req = req_queues[core_id].pop_front();
			t_grant = $realtime;
			grant_id++;
			queue_wait = t_grant - req.t_enqueue; // Tiempo en cola para esta solicitud.
			total_grants++;
			per_core_grants[core_id]++;
			total_queue_wait_time += queue_wait; // Acumula espera en cola del bus.
			case (req.req_type)
				BusRd:  count_BusRd++;
				BusRdX: begin
					count_BusRdX++;
					total_invalidations++;
				end
				BusUpd: begin
					count_BusUpd++;
					total_updates++;
				end
			endcase
			$display("[%0t] [BUS] [Core %0d] GRANT id=%0d type=%s addr=%s q_wait=%0f ns q=%0d",
				$realtime, core_id, grant_id, req_type_name(req.req_type), fmt_addr(req.address),
				queue_wait, req_queues[core_id].size());

			// #0 permite avanzar procesos concurrentes en el mismo tiempo simulado.
			#0;

			evt = create_bus_event(req);
			// Difusion previa a la latencia para habilitar observacion de coherencia.
			broadcast_event(evt);
			// FIX: illegal comparison (array vs null) replaced with size check.
			if (bus_evt_ack_mbx.size() != 0) begin
				if (bus_evt_ack_mbx.size() < num_cores) begin
					$fatal(1, "[%0t] [BUS] ERROR bus_evt_ack_mbx size=%0d num_cores=%0d",
						$realtime, bus_evt_ack_mbx.size(), num_cores);
				end
				for (int i = 0; i < num_cores; i++) begin
					int ack_id;
					if (bus_evt_ack_mbx[i] == null) begin
						$fatal(1, "[%0t] [BUS] ERROR bus_evt_ack_mbx[%0d] no inicializado",
							$realtime, i);
					end
					bus_evt_ack_mbx[i].get(ack_id);
				end
				#0;
			end
			// #0 deja reaccionar a caches en un ciclo delta.
			#0;

			bytes = get_transaction_size(req);
			latency = bytes / bus_bandwidth_bytes_per_ns; // Latencia derivada del modelo.
			pure_bus_latency = latency;
			total_bytes_transferred += bytes; // Base para metricas de ancho de banda.

			#(latency);

			// Respuesta de memoria solo para lecturas.
			if (req.req_type == BusRd || req.req_type == BusRdX) begin
				total_mem_accesses++;
				if (bus_to_mem != null) begin
					bus_to_mem.put(req);
					$display("[%0t] [BUS] [Core %0d] FWD_MEM type=%s addr=%s",
						$realtime, req.src_core_id, req_type_name(req.req_type), fmt_addr(req.address));
				end else begin
					mem_resp = new(req.address, core_id);
					mem_mbx[core_id].put(mem_resp);
				end
			end

			// #0 permite a las caches procesar la respuesta en un ciclo delta.
			#0;

			t_done = $realtime;
			// service_time incluye difusion, arbitraje y latencia de transferencia.
			service_time = t_done - t_grant;
			// total_latency abarca desde encolado hasta t_done.
			total_latency = t_done - req.t_enqueue;
			total_service_time += service_time;
			total_total_latency += total_latency;
			case (req.req_type)
				BusRd:  latency_BusRd += total_latency;
				BusRdX: latency_BusRdX += total_latency;
				BusUpd: latency_BusUpd += total_latency;
			endcase
			// Usa t_done local para reportar el tiempo de fin de la transaccion.
			$display("[%0t] [BUS] [Core %0d] DONE type=%s addr=%s bytes=%0d service=%0f ns total=%0f ns",
				t_done, core_id, req_type_name(req.req_type), fmt_addr(req.address), bytes,
				service_time, total_latency);

			rr_ptr = (core_id + 1) % num_cores; // Avanza RR para equidad.
		end
	endtask


	/**
	 * @brief Imprime metricas acumuladas y promedios derivados del bus.
	 *
	 * @details
	 *   Definiciones:
	 *     queue_wait    = tiempo en cola (t_grant - t_enqueue)
	 *     service_time  = tiempo de servicio (t_done - t_grant)
	 *     total_latency = latencia total (t_done - t_enqueue)
	 *
	 *   Ancho de banda:
	 *     total_bytes / tiempo_total (desde sim_start_time hasta $realtime)
	 *
	 *   Interpretacion:
	 *     BusRd  -> lecturas compartidas
	 *     BusRdX -> invalidaciones (escritura con invalidacion)
	 *     BusUpd -> actualizaciones (escritura con actualizacion)
	 *
	 *   Nota: invalidaciones y actualizaciones se infieren a partir del tipo de solicitud;
	 *   no se observan efectos por cache de forma directa.
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

		$display("[%0t] [BUS] METRICS total_requests=%0d total_grants=%0d total_mem_accesses=%0d total_bytes=%0d",
			$realtime, total_requests, total_grants, total_mem_accesses, total_bytes_transferred);
		if (total_requests != total_grants) begin
			$display("[%0t] [BUS] WARN requests != grants", $realtime);
		end
		$display("[%0t] [BUS] METRICS total_invalidations=%0d total_updates=%0d grant_id=%0d rejected=%0d",
			$realtime, total_invalidations, total_updates, grant_id, rejected_requests);
		for (int i = 0; i < num_cores; i++) begin
			$display("[%0t] [BUS] METRICS per_core core=%0d req=%0d grant=%0d",
				$realtime, i, per_core_requests[i], per_core_grants[i]);
		end
		$display("[%0t] [BUS] METRICS per_type BusRd=%0d BusRdX=%0d BusUpd=%0d",
			$realtime, count_BusRd, count_BusRdX, count_BusUpd);
		$display("[%0t] [BUS] METRICS avg_queue_wait=%0f ns avg_service=%0f ns avg_total=%0f ns",
			$realtime, avg_queue_wait, avg_service_time, avg_total_latency);
		$display("[%0t] [BUS] METRICS avg_latency BusRd=%0f ns BusRdX=%0f ns BusUpd=%0f ns",
			$realtime, avg_latency_BusRd, avg_latency_BusRdX, avg_latency_BusUpd);
		$display("[%0t] [BUS] METRICS total_time=%0f ns bandwidth=%0f bytes/ns",
			$realtime, total_time, bandwidth);
	endfunction

endclass
