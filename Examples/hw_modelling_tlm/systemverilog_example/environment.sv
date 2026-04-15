class environment;
    // Parameters
    localparam NUM_PROD = system_params_pkg::NUM_PROD;
    localparam NUM_CONS = system_params_pkg::NUM_CONS;
    localparam PKTS_PER_PROD = system_params_pkg::PKTS_PER_PROD;
    
    // Interfaces
    virtual component_interface prod_ifs[NUM_PROD];
    virtual component_interface cons_ifs[NUM_CONS];
    

    // Communication Channels
    Packet_mbx p_to_ic[NUM_PROD];
    Packet_mbx ic_to_c[NUM_CONS];
    
    // Component Handles
    Producer     prods[NUM_PROD];
    Consumer     cons[NUM_CONS];
    Interconnect ic;

    bit sim_done;
    
    virtual function void create_components();
        // 1. Setup Mailboxes
        foreach (p_to_ic[i]) p_to_ic[i] = new(1);
        foreach (ic_to_c[i]) ic_to_c[i] = new(1);

        // 2. Instantiate Interconnect
        ic = new();
        ic.in_mbx = p_to_ic;
        ic.out_mbx = ic_to_c;

        // 3. Instantiate Producers
        foreach (prods[i]) begin
            prods[i] = new(i);
            prods[i].num_pkts = PKTS_PER_PROD;
            prods[i].out_mbx = p_to_ic[i];
            prods[i].sigs = prod_ifs[i];
        end

        // 4. Instantiate Consumers
        foreach (cons[i]) begin
            cons[i] = new(i);
            cons[i].in_mbx = ic_to_c[i];
            cons[i].sigs = cons_ifs[i];
        end
    endfunction

    virtual task run_simulation();
        $display("--- Starting Simulation ---");
        fork
            begin // Start producers in parallel
                run_producers();
            end
            
            begin // Start consumers in parallel
                run_consumers();
            end
            
            begin // Start interconnect routing
                // 5. Set Interconnect Goal
                ic.total_pkts = PKTS_PER_PROD * NUM_PROD;
                ic.run();
            end
        join_any
        wait(ic.processed_pkts == ic.total_pkts);
        $display("@%0t [Environment] All packets processed. Ending simulation.", $realtime);
        #50; // Wait for any final processing
        $display("@%0t [Environment] Simulation Complete.", $realtime);
        $display("@%0t [Environment] Total packets routed by Interconnect: %0d", $realtime, ic.processed_pkts);
        sim_done = 1'b1;
    endtask

    // starts all producers in parallel
    virtual task run_producers();
        foreach (prods[i]) begin
            fork
                automatic int idx = i;
                prods[idx].run();
            join_none
        end
        wait fork;
    endtask

    // starts all consumers in parallel
    virtual task run_consumers();
        foreach (cons[i]) begin
            fork
                automatic int idx = i;
                cons[idx].run();
            join_none
        end
        wait fork;
    endtask

    // starts the interconnect routing
    virtual task run_interconnect();
        ic.run();
    endtask
endclass    