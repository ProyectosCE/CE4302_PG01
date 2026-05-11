#include "consumer.h"

Consumer::Consumer(sc_module_name name, int _id) : sc_module(name), id(_id) {
    SC_THREAD(run);
}

void Consumer::run() {
    while (true) {
        Packet pkt;
        in_port->get(pkt);
        
        rx_source_id.write(pkt.source_id);
        rx_dest_id.write(pkt.dest_id);
        rx_data.write(pkt.data);
        
        std::cout << "@" << sc_time_stamp() << " Cons " << id << " <- " << pkt << std::endl;
        wait(10, SC_NS);
    }
}