
import types_pkg::*;

virtual class TraceLoader;

    /**
     * @brief Ruta del archivo CSV a cargar.
     */
    string file_path;

    /**
     * @brief Constructor de TraceLoader.
     * @param path Ruta del archivo CSV
     */
    function new(string path);
        this.file_path = path;
    endfunction

    /**
     * @brief Carga las solicitudes del archivo CSV en los cores correspondientes.
     * @param cores Arreglo de cores a los que se asignarán las solicitudes
     */

    task load_into_cores(ref Core cores[]);
        int file, r, line_num;
        string line;
        string op_str;
        int core_id;
        logic [31:0] address;
        CoreRequest req;

        file = $fopen(file_path, "r");
        if (file == 0) begin
            $fatal(1, "No se pudo abrir el archivo: %s", file_path);
        end

        line_num = 0;
        while (!$feof(file)) begin
            line = "";
            r = $fgets(line, file);
            if (r <= 0) continue; // Salta líneas vacías o errores de lectura

            line_num++;
            // Parsear línea CSV: op,core_id,address
            r = $sscanf(line, "%s,%d,%h", op_str, core_id, address);
            if (r != 3) begin
                $display("Línea %0d inválida (formato incorrecto): %s", line_num, line);
                continue;
            end

            // Validar core_id
            if (core_id < 0 || core_id >= cores.size()) begin
                $display("Línea %0d inválida (core_id fuera de rango): %s", line_num, line);
                continue;
            end

            // Traducir operación a CoreRequest
            if (op_str == "R") begin
                req = new(PrRd, address, core_id);
            end else if (op_str == "W") begin
                req = new(PrWr, address, core_id);
            end else begin
                $display("Línea %0d inválida (operación desconocida): %s", line_num, line);
                continue;
            end

            // Agregar solicitud al core correspondiente
            cores[core_id].add_request(req);
        end

        $fclose(file);
        $display("Carga completa: %0d líneas procesadas", line_num);
    endtask

endclass
