// --- Top Level Module ---
module top();
    import system_params_pkg::*;
    import model_pkg::*;
    timeunit 1ns;
    timeprecision 1ns;
    
    logic gclk; // Global clock for tracing purposes
    localparam NUM_PROD = system_params_pkg::NUM_PROD;
    localparam NUM_CONS = system_params_pkg::NUM_CONS;

    // 1. FIXED WIDTHS: Declare as packed arrays of 32-bit vectors
    // This allows you to see the actual hex data, not just a 1 or 0
    logic [NUM_PROD-1:0][31:0] prod_src_id;
    logic [NUM_CONS-1:0][31:0] cons_src_id;
    logic [NUM_PROD-1:0][31:0] prod_dest_id;
    logic [NUM_CONS-1:0][31:0] cons_dest_id;
    logic [NUM_PROD-1:0][31:0] prod_data;
    logic [NUM_CONS-1:0][31:0] cons_data;

    // Interface instances
    component_interface prod_0_if();
    component_interface prod_1_if();
    component_interface cons_0_if();
    component_interface cons_1_if();
    
    // Environment handle
    environment env;

    // Clock generation for tracing        
    initial begin
        gclk = 0;
        forever #5 gclk = ~gclk; // 10ns period clock for tracing
    end

    initial begin
        //setup for waveform dumping
        $dumpfile("waves.fst");
        // Dump all signals in the top module and downwards, including interfaces
        $dumpvars(0, top);
        
        // Create environment
        env = new();
        
        // Connect virtual interfaces to physical instances
        env.prod_ifs[0] = prod_0_if;
        env.prod_ifs[1] = prod_1_if;
        env.cons_ifs[0] = cons_0_if;
        env.cons_ifs[1] = cons_1_if;
        
        // create components and run simulation
        env.create_components();
        env.run_simulation();
        
        // Simulation control
        wait(env.sim_done == 1'b1);
        #30; // acts a draining time for any remaining transactions to complete before finishing the simulation 
        $display("@%0t [Top] Simulation Finished.", $realtime);
        $finish;
    end
    //just to capture the interface signals for tracing in the waveform viewer
    //since verilator doesn't support tracing class variables directly,
    // we use this always_ff block to capture the interface signals into top-level logic for visibility in the waveform viewer
    always_ff @(posedge gclk) begin
        prod_data[0]    <= prod_0_if.data;
        prod_data[1]    <= prod_1_if.data;
        prod_src_id[0]  <= prod_0_if.src_id;
        prod_src_id[1]  <= prod_1_if.src_id;
        prod_dest_id[0] <= prod_0_if.dest_id;
        prod_dest_id[1] <= prod_1_if.dest_id;

        cons_data[0]    <= cons_0_if.data;
        cons_data[1]    <= cons_1_if.data;
        cons_src_id[0]  <= cons_0_if.src_id;
        cons_src_id[1]  <= cons_1_if.src_id;
        cons_dest_id[0] <= cons_0_if.dest_id;
        cons_dest_id[1] <= cons_1_if.dest_id;
    end

endmodule