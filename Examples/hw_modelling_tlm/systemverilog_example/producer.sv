// Producer Component
class Producer;
    localparam NUM_PROD = system_params_pkg::NUM_PROD;  // Get from parameters package
    localparam NUM_CONS = system_params_pkg::NUM_CONS;  // Get from parameters package
    Packet_mbx out_mbx;
    virtual component_interface sigs;  // Declare interface
    int id;
    int num_pkts;

    function new(int id);
        this.id = id;
    endfunction

    virtual task run();
        if(sigs == null) begin
            $fatal(1, "Producer %0d has null interface at %0t", id, $realtime);
        end
        sigs.is_producer = 1; // Mark this interface as producer for tracing
        for (int i = 0; i < num_pkts; i++) begin
            Packet pkt = new();
            pkt.src  = id;
            pkt.dest = $urandom_range(0, 1);
            pkt.data = $urandom_range(0, 100);
            
            // Tracing to interface
            sigs.src_id  = pkt.src;
            sigs.dest_id = pkt.dest;
            sigs.data    = pkt.data;       
            #10;
            out_mbx.put(pkt);
            $display("@%0t [Prod %0d] Generated pkt for Dest %0d data %0h (%0h)", $realtime, id, pkt.dest, pkt.data, sigs.data);
        end
    endtask
endclass