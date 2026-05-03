`include "component_interface.sv"
package model_pkg;
    import system_params_pkg::*;
    timeunit 1ns;
    timeprecision 1ns;

    `include "packet.sv"
    
    // Typedef for typed mailbox
    typedef mailbox #(Packet) Packet_mbx;
    
    `include "producer.sv"
    `include "consumer.sv"
    `include "interconnect.sv"
    `include "environment.sv"
endpackage
