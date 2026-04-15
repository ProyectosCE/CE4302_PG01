// Interconnect Component
class Interconnect;
    Packet_mbx in_mbx[2];
    Packet_mbx out_mbx[2];
    semaphore mutex = new(1);
    int total_pkts = -1;
    int processed_pkts;

    // Internal routing logic
    virtual task route(int port);
        Packet pkt;
        forever begin
            in_mbx[port].get(pkt);
            if(pkt == null) begin
                $fatal(1, "Interconnect received null packet on port %0d at %0t", port, $realtime);
            end
            $display("@%0t [Interconnect] packet from src %0d dest %0d data %0h", $realtime, pkt.src, pkt.dest, pkt.data);
            #10; // Routing delay
            out_mbx[pkt.dest].put(pkt);
            mutex.get();
            processed_pkts++;
            $display("@%0t [Interconnect] %0d/%0d packets processed", $realtime, processed_pkts, total_pkts);
            mutex.put();
        end
    endtask
    
    virtual task run();
        fork
            begin
                route(0);
            end
            begin
                route(1);
            end
        join
    endtask
endclass
