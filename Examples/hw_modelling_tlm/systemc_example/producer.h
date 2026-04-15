#ifndef PRODUCER_H
#define PRODUCER_H

#include <systemc.h>
#include <tlm.h>
#include <random>
#include "packet.h"

class Producer : public sc_module {
public:
    sc_port<tlm::tlm_put_if<Packet>> out_port;
    
    sc_signal<int> tx_source_id;
    sc_signal<int> tx_dest_id;
    sc_signal<int> tx_data;
    
    int id;
    int num_pkts;

    Producer(sc_module_name name, int _id, int _num_pkts);
    void run();

private:
    std::mt19937 rng; // Mersenne Twister RNG engine
};

#endif