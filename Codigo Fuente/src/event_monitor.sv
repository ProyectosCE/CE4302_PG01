/* EventMonitor.sv
 * ============================================
 * Monitor de observabilidad del modelo (no implementa bus/memoria).
 *
 * RESPONSABILIDAD ACTUAL:
 *   - Exportar transiciones FSM de caché a CSV.
 *   - Proveer utilidades de cierre de exportadores.
 *
 * NOTA IMPORTANTE:
 *   - El flujo de simulación usa únicamente Bus real (class Bus).
 * ============================================
 */

`timescale 1ns/1ps

import types_pkg::*;

class EventMonitor;

    // Estadísticas
    int bus_rd_count;
    int bus_rdx_count;
    int bus_upd_count;

    // Exportador opcional (si está configurado, escribe un CSV de eventos)
    TraceExporter exporter;

    // Exportador opcional de transiciones FSM
    TraceExporter transition_exporter;

    // Constructor
    function new();
        bus_rd_count = 0;
        bus_rdx_count = 0;
        bus_upd_count = 0;
        exporter = null;
        transition_exporter = null;
    endfunction

    function void enable_transition_export(string filename);
        transition_exporter = new(
            filename,
            "time_ns,cache_id,addr_index,old_state,new_state,cause\n"
        );
    endfunction

    function string state_to_string(state_e state);
        case (state)
            Invalid:  return "Invalid";
            Shared:   return "Shared";
            Modified: return "Modified";
            default:  return "Unknown";
        endcase
    endfunction

    task record_transition(longint time_ns, int cache_id, logic [31:0] address, int index, state_e old_state, state_e new_state, string cause);
        string addr_index;

        if (transition_exporter == null) begin
            return;
        end

        addr_index = $sformatf("%h (idx=%0d)", address, index);
        transition_exporter.log_transition(
            time_ns,
            cache_id,
            addr_index,
            state_to_string(old_state),
            state_to_string(new_state),
            cause
        );
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

    function void close();
        if (exporter != null) begin
            exporter.close();
        end
        if (transition_exporter != null) begin
            transition_exporter.close();
        end
    endfunction

endclass