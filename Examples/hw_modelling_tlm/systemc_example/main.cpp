#include <systemc.h>
#include "top.h"

int sc_main(int argc, char* argv[]) {
    sc_core::sc_set_time_resolution(1, SC_NS);
    Top top("top");
    
    sc_trace_file *wf = sc_create_vcd_trace_file("sc_trace");
    
    for(int i=0; i<2; i++) {
        std::string p = "P" + std::to_string(i);
        sc_trace(wf, top.prods[i]->tx_data, p + "_Data");
        std::string c = "C" + std::to_string(i);
        sc_trace(wf, top.cons[i]->rx_data, c + "_Data");
    }
    
    sc_start(200, SC_NS);
    sc_close_vcd_trace_file(wf);
    return 0;
}