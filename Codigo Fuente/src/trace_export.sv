class TraceExporter;

    // Archivo de salida
    int file;

    // Constructor
    function new(string filename);
        file = $fopen(filename, "w");
        if (file == 0) begin
            $fatal(1, "[%0t] [TRACE_EXPORT] ERROR no se puede crear archivo: %s",
                $realtime, filename);
        end
        // Escribir encabezado
        $fwrite(file, "time_ns,core_id,bus_op,address\n");
    endfunction

    /**
     * @brief Registra un evento en el archivo de trace.
     * @param time_ns Tiempo del evento (ns)
     * @param core_id ID del core que originó la transacción
     * @param bus_op Tipo de operación en el bus (BusRd, BusRdX, BusUpd)
     * @param address Dirección involucrada en la transacción
     */
    task log_event(longint time_ns, int core_id, string bus_op, logic [31:0] address);
        $fwrite(file, "%0d,%0d,%s,%h\n", time_ns, core_id, bus_op, address);
    endtask

    // Destructor para cerrar el archivo al finalizar la simulación
    function void close();
        $fclose(file);
    endfunction
endclass