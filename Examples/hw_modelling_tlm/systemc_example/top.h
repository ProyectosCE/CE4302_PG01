#ifndef TOP_H
#define TOP_H

#include <systemc.h>
#include <tlm.h>
#ifndef PKTS_PER_PROD 
#define PKTS_PER_PROD 10
#endif
#include "producer.h"
#include "consumer.h"
#include "interconnect.h"

class Top : public sc_module {
public:
    tlm::tlm_fifo<Packet> prod_fifo[2];
    Interconnect* interconnect;
    Producer* prods[2];
    Consumer* cons[2];
    
    Top(sc_module_name name);
    ~Top(); // Good practice to clean up pointers
};

#endif