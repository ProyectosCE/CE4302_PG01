// Consumer Component
class Consumer;
    localparam NUM_PROD = system_params_pkg::NUM_PROD;  // Get from parameters package
    localparam NUM_CONS = system_params_pkg::NUM_CONS;  // Get from parameters package
    virtual component_interface sigs;  // Declare interface
    Packet_mbx in_mbx;
    int id;
    int received_pkts;

    function new(int id);
        this.id = id;
    endfunction

    virtual task run();
        Packet pkt;
        received_pkts = 0;
        if(sigs == null) begin
            $fatal(1, "Consumer %0d has null interface at %0t", id, $realtime);
        end
        sigs.is_producer = 0; // Mark this interface as consumer for tracing
        forever begin
            in_mbx.get(pkt);
            if(pkt == null) begin
                $fatal(1, "Consumer %0d received null packet at %0t", id, $realtime);
            end
            received_pkts++;
            // Tracing to interface
            sigs.src_id  = pkt.src;
            sigs.dest_id = pkt.dest;
            sigs.data    = pkt.data;
            #10; // Processing delay
            $display("@%0t [Cons %0d] Processed pkt from Src %0d with data %0h (%0h) (Total: %0d)", $realtime, id, pkt.src, pkt.data, sigs.data, received_pkts);
        end
    endtask
endclass
