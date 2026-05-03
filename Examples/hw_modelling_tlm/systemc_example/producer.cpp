#include "producer.h"

Producer::Producer(sc_module_name name, int _id, int _num_pkts) 
    : sc_module(name), id(_id), num_pkts(_num_pkts) {
    
    // Seed the RNG with unique ID + device entropy
    rng.seed(std::random_device()() + id);
    SC_THREAD(run);
}

void Producer::run() {
    // Range distributions (min, max inclusive)
    std::uniform_int_distribution<int> dist_dest(0, 1);
    std::uniform_int_distribution<int> dist_data(0, 100);

    for (int i = 0; i < num_pkts; ++i) {
        Packet pkt;
        pkt.source_id = id;
        pkt.dest_id   = dist_dest(rng);
        pkt.data      = dist_data(rng);
        
        tx_source_id.write(pkt.source_id);
        tx_dest_id.write(pkt.dest_id);
        tx_data.write(pkt.data);
        
        wait(10, SC_NS);
        
        out_port->put(pkt);
        std::cout << "@" << sc_time_stamp() << " [Prod " << id << "] Generated pkt for Dest " << pkt.dest_id << " data " << pkt.data << std::endl;
    }
}