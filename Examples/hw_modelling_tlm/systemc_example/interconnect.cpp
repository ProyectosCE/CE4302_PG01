#include "interconnect.h"

Interconnect::Interconnect(sc_module_name name) : sc_module(name) {
    new (&out[0]) tlm::tlm_fifo<Packet>("out_0", 1);
    new (&out[1]) tlm::tlm_fifo<Packet>("out_1", 1);
    
    SC_THREAD(route_port_0);
    SC_THREAD(route_port_1);
}

void Interconnect::route_port_0() {
    while (true) {
        Packet pkt;
        in[0]->get(pkt);
        std::cout << "@" << sc_time_stamp() << " Interconnect received " << " <- " << pkt << std::endl;
        wait(10, SC_NS);
        out[pkt.dest_id].put(pkt);
    }
}

void Interconnect::route_port_1() {
    while (true) {
        Packet pkt;
        in[1]->get(pkt);
        std::cout << "@" << sc_time_stamp() << " Interconnect received " << " <- " << pkt << std::endl;
        wait(10, SC_NS);
        out[pkt.dest_id].put(pkt);
    }
}