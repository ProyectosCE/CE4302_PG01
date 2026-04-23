/* EventMonitor.sv
 * ============================================
 * Módulo para monitorear eventos en el bus y generar estadísticas.
 *   - Se utiliza en top_tb antes de run_cores().
 *
 * FORMATO DE ARCHIVO:
 *   CSV con encabezado (ignorado) y líneas de formato:
 *   cycle,core_id,op,address
 *   0,0,R,0x00001000
 *   1,2,W,0x00001000
 *
 * VALIDACIONES:
 *   - core_id en rango 0..3
 *   - op en {R, W}
 *   - address válida (hexadecimal 32 bits)
 * ============================================
 */

`timescale 1ns/1ps

class EventMonitor;

    // Estadísticas
    int bus_rd_count;
    int bus_rdx_count;
    int bus_upd_count;

    // Exportador opcional (si está configurado, escribe un CSV de eventos)
    TraceExporter exporter;

    // Constructor
    function new();
        bus_rd_count = 0;
        bus_rdx_count = 0;
        bus_upd_count = 0;
        exporter = null;
    endfunction

    /**
     * @brief Monitorea el bus para contar eventos de tipo BusRd, BusRdX y BusUpd.
     *        Se debe llamar en paralelo con la ejecución de los cores y caches.
     * @param bus_mbx Mailbox desde donde se reciben las solicitudes del bus
     * @param bus_evt_mbx Arreglo de mailboxes para enviar eventos a los caches
     * @param mem_mbx Arreglo de mailboxes para enviar respuestas de memoria a los cores
     */
    task monitor_bus(BusReq_mbx bus_mbx, BusEvt_mbx bus_evt_mbx[], MemResp_mbx mem_mbx[]);
        // Inicializar estadísticas
        bus_rd_count = 0;
        bus_rdx_count = 0;
        bus_upd_count = 0;

        // Monitorear el bus indefinidamente
        forever begin
            BusRequest  bus_req;
            BusEvent    evt;
            MemResponse mem_resp;
            string bus_op;

            // Esperar una solicitud en el bus
            bus_mbx.get(bus_req);

            // Registrar evento (tiempo, core origen, tipo, address)
            bus_op = (bus_req.req_type == BusRd)  ? "BusRd" :
                     (bus_req.req_type == BusRdX) ? "BusRdX" :
                     (bus_req.req_type == BusUpd) ? "BusUpd" : "Unknown";

            $display("@%0t [EventMonitor] Core=%0d Op=%s Addr=%h",
                $realtime, bus_req.src_core_id, bus_op,
                bus_req.address);

            if (exporter != null) begin
                exporter.log_event($rtoi($realtime), bus_req.src_core_id, bus_op, bus_req.address);
            end

            // Contar por tipo de transacción
            case (bus_req.req_type)
                BusRd:   bus_rd_count++;
                BusRdX:  bus_rdx_count++;
                BusUpd:  bus_upd_count++;
                default: /* no contar */;
            endcase

            // Reenviar evento a los caches y simular respuesta de memoria
            evt = new(bus_req.req_type, bus_req.address, bus_req.src_core_id);

            // Enviar evento a todos los caches
            bus_evt_mbx[0].put(evt);
            bus_evt_mbx[1].put(evt);
            bus_evt_mbx[2].put(evt);
            bus_evt_mbx[3].put(evt);
            // Simular tiempo de bus y memoria
            #10.5;
            mem_resp = new(bus_req.address, bus_req.src_core_id);
            mem_mbx[bus_req.src_core_id].put(mem_resp);
        end
    endtask


    /**
     * @brief Imprime las estadísticas acumuladas al finalizar la simulación.
     */
    task print_stats();
        $display("\n=== EventMonitor Statistics ===");
        $display("Total BusRd  : %0d", bus_rd_count);
        $display("Total BusRdX : %0d", bus_rdx_count);
        $display("Total BusUpd : %0d", bus_upd_count);
        $display("==============================\n");
    endtask

endclass