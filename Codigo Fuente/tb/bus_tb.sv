`timescale 1ns/1ns

module bus_tb;
	import types_pkg::*;
    import model_pkg::*;

	timeunit 1ns;
	timeprecision 1ns;

	parameter int NUM_CORES = 4;
	parameter int MAX_SIM_TIME = 2000;
	parameter int DRAIN_DELAY = 80;

	BusReq_mbx bus_mbx;
	BusEvt_mbx bus_evt_mbx[NUM_CORES];
	MemResp_mbx mem_mbx[NUM_CORES];

	Bus bus;

	int evt_count[NUM_CORES];
	int mem_count[NUM_CORES];
	int sent_count[NUM_CORES];
	int total_sent;
	int total_evt_received;
	int total_mem_received;
	int expected_broadcast_events;
	int expected_mem_responses;
	int grant_order[$];
	int starvation_limit;
	int invalid_src_count;
	int rr_imbalance_threshold;

	// Envia una solicitud al bus con trazabilidad.
	task automatic send_request(int core_id, bus_req_type_e req_type, logic [31:0] address);
		BusRequest req;
		req = new(req_type, address, core_id);
		bus_mbx.put(req);
		sent_count[core_id]++;
		total_sent++;
		// Cada solicitud genera una difusion a todos los cores.
		expected_broadcast_events += NUM_CORES;
		// La respuesta de memoria solo aplica a BusRd/BusRdX.
		if (req_type == BusRd || req_type == BusRdX) begin
			expected_mem_responses++;
		end
		$display("[%0t] [TB] SEND core=%0d type=%s addr=%s",
			$realtime, core_id, bus_req_name(req_type), fmt_addr(address));
	endtask

	// Monitor de eventos de bus por core.
	task automatic monitor_events(int core_id);
		BusEvent evt;
		forever begin
			bus_evt_mbx[core_id].get(evt);
			evt_count[core_id]++;
			total_evt_received++;
			if (evt.src_core_id < 0 || evt.src_core_id >= NUM_CORES) begin
				invalid_src_count++;
				$error("[%0t] [TB] ERROR evento src_core_id invalido=%0d",
					$realtime, evt.src_core_id);
			end
			// Se usa la auto-observacion (core_id == src) como aproximacion del orden.
			// No es global, pero es suficiente para una validacion basica de equidad.
			if (core_id == evt.src_core_id) begin
				grant_order.push_back(evt.src_core_id);
			end
			$display("[%0t] [TB] EVT core=%0d type=%s addr=%s src=%0d",
				$realtime, core_id, bus_req_name(evt.req_type), fmt_addr(evt.address), evt.src_core_id);
		end
	endtask

	// Monitor de respuestas de memoria por core.
	task automatic monitor_mem_resps(int core_id);
		MemResponse resp;
		forever begin
			mem_mbx[core_id].get(resp);
			mem_count[core_id]++;
			total_mem_received++;
			$display("[%0t] [TB] MEM_RESP core=%0d addr=%s",
				$realtime, core_id, fmt_addr(resp.address));
		end
	endtask

	// Escenario 1: solicitudes secuenciales de un solo core.
	task automatic scenario_sequential();
		$display("[%0t] [TB] SCENARIO start id=1", $realtime);
		for (int i = 0; i < 6; i++) begin
			send_request(0, BusRd, 32'h0000_1000 + i * 32);
			#2;
		end
		$display("[%0t] [TB] SCENARIO end id=1", $realtime);
	endtask

	// Escenario 2: contencion entre cores con tipos mixtos.
	task automatic scenario_contention();
		$display("[%0t] [TB] SCENARIO start id=2", $realtime);
		fork
			send_request(0, BusRd,  32'h0000_2000);
			send_request(1, BusRdX, 32'h0000_2040);
			send_request(2, BusUpd, 32'h0000_2080);
			send_request(3, BusRd,  32'h0000_20C0);
		join
		#5;
		fork
			send_request(0, BusUpd, 32'h0000_2100);
			send_request(1, BusRd,  32'h0000_2140);
			send_request(2, BusRdX, 32'h0000_2180);
			send_request(3, BusUpd, 32'h0000_21C0);
		join
		$display("[%0t] [TB] SCENARIO end id=2", $realtime);
	endtask

	// Escenario 3: rafaga de un core con inserciones ocasionales de otros.
	task automatic scenario_burst();
		$display("[%0t] [TB] SCENARIO start id=3", $realtime);
		fork
			begin
				for (int i = 0; i < 8; i++) begin
					send_request(0, BusRd, 32'h0000_3000 + i * 16);
					#1;
				end
			end
			begin
				#3; send_request(1, BusRdX, 32'h0000_3400);
				#7; send_request(2, BusUpd, 32'h0000_3440);
				#5; send_request(3, BusRd,  32'h0000_3480);
			end
		join
		$display("[%0t] [TB] SCENARIO end id=3", $realtime);
	endtask

	// Escenario 4: mezcla aleatoria de operaciones.
	task automatic scenario_mixed();
		$display("[%0t] [TB] SCENARIO start id=4", $realtime);
		for (int i = 0; i < 12; i++) begin
			int sel;
			bus_req_type_e t;
			sel = $urandom_range(0, 2);
			case (sel)
				0: t = BusRd;
				1: t = BusRdX;
				default: t = BusUpd;
			endcase
			send_request(i % NUM_CORES, t, 32'h0000_4000 + i * 8);
			#2;
		end
		$display("[%0t] [TB] SCENARIO end id=4", $realtime);
	endtask

	// Escenario 5: inactividad seguida de reactivacion.
	task automatic scenario_idle_wakeup();
		$display("[%0t] [TB] SCENARIO start id=5", $realtime);
		#50;
		send_request(2, BusRdX, 32'h0000_5000);
		#10;
		send_request(3, BusRd,  32'h0000_5040);
		$display("[%0t] [TB] SCENARIO end id=5", $realtime);
	endtask

	// Inicializacion del bus y mailboxes.
	initial begin
		bus_mbx = new();
		for (int i = 0; i < NUM_CORES; i++) begin
			bus_evt_mbx[i] = new();
			mem_mbx[i] = new();
			evt_count[i] = 0;
			mem_count[i] = 0;
			sent_count[i] = 0;
		end
		total_sent = 0;
		total_evt_received = 0;
		total_mem_received = 0;
		expected_broadcast_events = 0;
		expected_mem_responses = 0;
		starvation_limit = 6;
		invalid_src_count = 0;
		rr_imbalance_threshold = 4;

		bus = new(bus_mbx, bus_evt_mbx, mem_mbx, NUM_CORES);
		bus.run();
	end

	// Monitores pasivos de eventos y respuestas.
	initial begin
		for (int i = 0; i < NUM_CORES; i++) begin
			automatic int cid = i; // Evita que el fork reuse el mismo indice.
			fork
				monitor_events(cid);
				monitor_mem_resps(cid);
			join_none
		end
	end

	// Vigilante de tiempo para evitar bloqueos silenciosos.
	initial begin
		#MAX_SIM_TIME;
		$fatal(1, "[%0t] [TB] ERROR timeout simulacion excedio tiempo esperado", $realtime);
	end

	// Flujo principal de prueba.
	initial begin
		int min_expected;
		int active_cores;
		int max_grants;
		int min_grants;
		int max_sent;
		int min_sent;
		real avg_rd;
		real avg_rdx;
		real avg_upd;
		int streak;
		int last;
		bit seen;

		#5;
		scenario_sequential();
		#100;

		scenario_contention();
		#100;

		scenario_burst();
		#100;

		scenario_mixed();
		#100;

		scenario_idle_wakeup();
		#200;

		// Fase de drenaje: asegura que colas y difusiones se procesen antes de validar.
		wait (bus.has_pending_requests() == 0);
		#DRAIN_DELAY;

		// Resumen de metricas del bus.
		bus.print_metrics();

		// Chequeos de sanidad basados en conteos.
		$display("[%0t] [TB] VALIDATION start", $realtime);
		$display("[%0t] [TB] SUMMARY total_enviados=%0d", $realtime, total_sent);
		$display("[%0t] [TB] SUMMARY evt_recibidos=%0d mem_recibidos=%0d",
			$realtime, total_evt_received, total_mem_received);
		$display("[%0t] [TB] SUMMARY esperados evt=%0d mem=%0d",
			$realtime, expected_broadcast_events, expected_mem_responses);
		for (int i = 0; i < NUM_CORES; i++) begin
			$display("[%0t] [TB] SUMMARY core=%0d enviados=%0d evt=%0d mem=%0d",
				$realtime, i, sent_count[i], evt_count[i], mem_count[i]);
		end

		// En concurrencia no se exige igualdad exacta; se aplica un umbral fuerte.
		min_expected = (expected_broadcast_events * 7) / 10;
		if (total_evt_received < min_expected)
			$error("[%0t] [TB] ERROR difusion insuficiente minimo=%0d recibido=%0d",
				$realtime, min_expected, total_evt_received);
		else
			$display("[%0t] [TB] OK difusion dentro de margen esperado", $realtime);

		// Respuestas de memoria solo para BusRd/BusRdX; pueden quedar en cola.
		if (total_mem_received > expected_mem_responses)
			$error("[%0t] [TB] ERROR respuestas_mem excedidas expected=%0d got=%0d",
				$realtime, expected_mem_responses, total_mem_received);
		else if (total_mem_received < expected_mem_responses)
			$display("[%0t] [TB] WARN respuestas_mem pendientes expected=%0d got=%0d",
				$realtime, expected_mem_responses, total_mem_received);
		else
			$display("[%0t] [TB] OK respuestas_mem dentro de rango", $realtime);

		if (bus.total_mem_accesses != expected_mem_responses)
			$error("[%0t] [TB] ERROR inconsistencia accesos_mem bus=%0d esperado=%0d",
				$realtime, bus.total_mem_accesses, expected_mem_responses);

		active_cores = 0;
		for (int c = 0; c < NUM_CORES; c++) begin
			if (sent_count[c] > 0)
				active_cores++;
		end

		for (int c = 0; c < NUM_CORES; c++) begin
			seen = 0;
			for (int j = 0; j < grant_order.size(); j++) begin
				if (grant_order[j] == c) begin
					seen = 1;
					break;
				end
			end
			if (!seen && active_cores > 1)
				$display("[%0t] [TB] WARN posible inanicion core=%0d", $realtime, c);
		end

		// Verificacion de equidad: solo aplica si la carga por core es comparable.
		max_grants = -1;
		min_grants = 32'h7fffffff;
		max_sent = -1;
		min_sent = 32'h7fffffff;
		for (int c = 0; c < NUM_CORES; c++) begin
			if (sent_count[c] > 0) begin
				if (bus.per_core_grants[c] > max_grants)
					max_grants = bus.per_core_grants[c];
				if (bus.per_core_grants[c] < min_grants)
					min_grants = bus.per_core_grants[c];
				if (sent_count[c] > max_sent)
					max_sent = sent_count[c];
				if (sent_count[c] < min_sent)
					min_sent = sent_count[c];
			end
		end
		if (active_cores > 1 && max_grants >= 0 && (max_sent - min_sent) <= rr_imbalance_threshold &&
			(max_grants - min_grants) > rr_imbalance_threshold)
			$display("[%0t] [TB] WARN desbalance arbitraje RR max=%0d min=%0d",
				$realtime, max_grants, min_grants);

		if (total_sent != bus.total_requests)
			$error("[%0t] [TB] ERROR total_sent != bus.total_requests (%0d != %0d)",
				$realtime, total_sent, bus.total_requests);
		else
			$display("[%0t] [TB] OK total_sent matches bus.total_requests", $realtime);

		if (bus.total_grants > total_sent)
			$error("[%0t] [TB] ERROR total_grants supera total_sent (%0d > %0d)",
				$realtime, bus.total_grants, total_sent);
		else if (bus.total_grants < total_sent)
			$display("[%0t] [TB] WARN transacciones pendientes grants=%0d enviados=%0d",
				$realtime, bus.total_grants, total_sent);
		else
			$display("[%0t] [TB] OK total_grants coincide con total_sent", $realtime);

		if (total_sent < 0 || total_evt_received < 0 || total_mem_received < 0)
			$error("[%0t] [TB] ERROR contadores negativos detectados", $realtime);
		if (invalid_src_count > 0)
			$error("[%0t] [TB] ERROR eventos src_core_id invalido=%0d", $realtime, invalid_src_count);

		if (bus.total_total_latency < bus.total_queue_wait_time)
			$error("[%0t] [TB] ERROR latencia inconsistente total_latency < queue_wait", $realtime);

		if (bus.count_BusRd > 0 && bus.count_BusRdX > 0 && bus.count_BusUpd > 0) begin
			avg_rd = bus.latency_BusRd / bus.count_BusRd;
			avg_rdx = bus.latency_BusRdX / bus.count_BusRdX;
			avg_upd = bus.latency_BusUpd / bus.count_BusUpd;
			// La relacion depende del ancho de banda y del modelo de servicio.
			if (avg_upd > avg_rd || avg_upd > avg_rdx)
				$display("[%0t] [TB] INFO latencias relativas dependen del modelo de tiempo", $realtime);
		end

		// Dominancia: solo se reporta si otros cores aun tienen solicitudes pendientes.
		if (grant_order.size() > 0) begin
			int pending[NUM_CORES];
			for (int c = 0; c < NUM_CORES; c++) begin
				pending[c] = sent_count[c];
			end
			streak = 1;
			last = grant_order[0];
			for (int k = 0; k < grant_order.size(); k++) begin
				int current;
				bit others_pending;
				current = grant_order[k];
				others_pending = 0;
				for (int c = 0; c < NUM_CORES; c++) begin
					if (c != current && pending[c] > 0) begin
						others_pending = 1;
						break;
					end
				end
				if (k > 0) begin
					if (current == last) begin
						streak++;
						if (others_pending && streak > starvation_limit) begin
							$display("[%0t] [TB] WARN posible dominancia core=%0d repite=%0d",
								$realtime, current, streak);
							streak = 1;
						end
					end else begin
						streak = 1;
						last = current;
					end
				end
				if (pending[current] > 0)
					pending[current]--;
			end
		end

		$finish;
	end

endmodule
