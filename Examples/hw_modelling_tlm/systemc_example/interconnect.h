#ifndef INTERCONNECT_H
#define INTERCONNECT_H

#include <systemc.h>
#include <tlm.h>
#include "packet.h"

class Interconnect : public sc_module {
public:
    sc_port<tlm::tlm_get_if<Packet>> in[2];
    tlm::tlm_fifo<Packet> out[2];
    
    Interconnect(sc_module_name name);
    
    void route_port_0();
    void route_port_1();
};

#endif