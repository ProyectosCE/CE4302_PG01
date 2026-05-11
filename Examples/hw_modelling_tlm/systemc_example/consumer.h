#ifndef CONSUMER_H
#define CONSUMER_H

#include <systemc.h>
#include <tlm.h>
#include "packet.h"

class Consumer : public sc_module {
public:
    sc_port<tlm::tlm_get_if<Packet>> in_port;
    sc_signal<int> rx_source_id;
    sc_signal<int> rx_dest_id;
    sc_signal<int> rx_data;
    
    int id;
    Consumer(sc_module_name name, int _id);
    
    void run();
};

#endif