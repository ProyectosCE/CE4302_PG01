#include "top.h"

Top::Top(sc_module_name name) : sc_module(name) {
    new (&prod_fifo[0]) tlm::tlm_fifo<Packet>("p_f0", 1);
    new (&prod_fifo[1]) tlm::tlm_fifo<Packet>("p_f1", 1);
    interconnect = new Interconnect("interconnect");
    
    for (int i = 0; i < 2; i++) {
        // Passing 3 packets per producer
        prods[i] = new Producer(sc_gen_unique_name("p"), i, PKTS_PER_PROD);
        prods[i]->out_port(prod_fifo[i]);
        interconnect->in[i](prod_fifo[i]);

        cons[i] = new Consumer(sc_gen_unique_name("c"), i);
        cons[i]->in_port(interconnect->out[i]);
    }
}

Top::~Top() {
    delete interconnect;
    for(int i=0; i<2; i++) {
        delete prods[i];
        delete cons[i];
    }
}