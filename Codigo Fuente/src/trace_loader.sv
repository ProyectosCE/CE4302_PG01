/*
 * ============================================
 * ARCHIVO: trace_loader.sv
 * DESCRIPCIÓN GENERAL:
 *   Cargador de trazas (memory traces) desde archivo CSV.
 *   Parsea el formato: cycle,core_id,op,address
 *   Inyecta solicitudes en la cola de cada core para reproducción.
 *
 * ROL EN EL SISTEMA:
 *   - Intermediario entre archivos de trace y los cores.
 *   - Permite reproducir workloads determinísticos desde software.
 *
 * RELACIÓN CON OTROS MÓDULOS:
 *   - Complementa Core.trace_queue y Core.add_request().
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
import types_pkg::*;

class TraceLoader;

    /**
     * @brief Ruta del archivo CSV a cargar.
     */
    string file_path;

    /**
     * @brief Constructor de TraceLoader.
     * @param path Ruta del archivo CSV
     */
    function new(string path);
        string p;
        p = path;
        if (p.len() >= 2 && p.substr(0,0) == "\"" && p.substr(p.len()-1, p.len()-1) == "\"") begin
            p = p.substr(1, p.len()-2);
        end
        this.file_path = p;
    endfunction

    /**
     * @brief Carga las solicitudes del archivo CSV en los cores correspondientes.
     *        Formato esperado: cycle,core_id,op,address
     * @param cores Arreglo de cores a los que se asignarán las solicitudes
     */
    task load_into_cores(Core cores[]);
        int file, r, line_num;
        string line;
        int cycle;
        int core_id;
        byte unsigned op_char;
        string op_str;
        string address_str;
        string address_clean;
        logic [31:0] address;
        CoreRequest req;
        int total_reqs = 0;
        int skipped = 0;

        file = $fopen(file_path, "r");
        if (file == 0) begin
            $fatal(1, "[%0t] [TRACE_LOADER] ERROR no se puede abrir archivo: %s",
                $realtime, file_path);
        end

        $display("[%0t] [TRACE_LOADER] START file=%s", $realtime, file_path);

        // Lee encabezado (se ignora)
        line_num = 0;
        r = $fgets(line, file);
        if (r <= 0) begin
            $fatal(1, "[%0t] [TRACE_LOADER] ERROR archivo vacio: %s",
                $realtime, file_path);
        end
        line_num++;

        // Lee líneas de datos
        while ($fgets(line, file) != 0) begin
            line_num++;

            // Ignora líneas en blanco o con solo espacios
            if (line.len() == 0 || line == "\n")
                continue;

            // Limpia \r y \n al final de la línea
            if (line.len() && (line[line.len()-1] == 10 || line[line.len()-1] == 13))
                line = line.substr(0, line.len()-1);
            if (line.len() && (line[line.len()-1] == 13))
                line = line.substr(0, line.len()-1);

            // Parsea línea CSV: cycle,core_id,op,address
            // Nota: usar %c para 'op' evita que %s consuma la coma.
            r = $sscanf(line, "%d,%d,%c,%s", cycle, core_id, op_char, address_str);
            if (r != 4) begin
                $warning("[%0t] [TRACE_LOADER] WARN linea=%0d formato invalido: %s",
                    $realtime, line_num, line);
                skipped++;
                continue;
            end

            // Valida core_id
            if (core_id < 0 || core_id >= cores.size()) begin
                $warning("[%0t] [TRACE_LOADER] WARN linea=%0d core_id fuera de rango: %0d",
                    $realtime, line_num, core_id);
                skipped++;
                continue;
            end

            // Traduce operación (R->PrRd, W->PrWr)
            case (op_char)
                "R", "r": op_str = "PrRd";
                "W", "w": op_str = "PrWr";
                default: begin
                    $warning("[%0t] [TRACE_LOADER] WARN linea=%0d operacion invalida: %s",
                        $realtime, line_num, op_char);
                    skipped++;
                    continue;
                end
            endcase

            // Parsea dirección hexadecimal
            address_clean = address_str;
            if (address_clean.len() >= 2 && (address_clean.substr(0,1) == "0x" || address_clean.substr(0,1) == "0X")) begin
                address_clean = address_clean.substr(2, address_clean.len()-1);
            end
            if ($sscanf(address_clean, "%h", address) != 1) begin
                $warning("[%0t] [TRACE_LOADER] WARN linea=%0d direccion invalida: %s",
                    $realtime, line_num, address_str);
                skipped++;
                continue;
            end

            // Crea CoreRequest y agrega al core
            if (op_str == "PrRd") begin
                req = new(PrRd, address, core_id);
            end else begin
                req = new(PrWr, address, core_id);
            end

            cores[core_id].add_request(req);
            total_reqs++;
        end

        $fclose(file);

        $display("[%0t] [TRACE_LOADER] DONE loaded=%0d skipped=%0d lines=%0d",
            $realtime, total_reqs, skipped, line_num - 1);

        if (total_reqs == 0) begin
            $warning("[%0t] [TRACE_LOADER] WARN no se cargaron solicitudes", $realtime);
        end

    endtask

endclass
