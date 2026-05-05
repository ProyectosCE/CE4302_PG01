`timescale 1ns/1ns

module bus_memory_tb;

    import types_pkg::*;
    import model_pkg::*;

    localparam int NUM_CORES = 4;
    localparam int MEM_LATENCY_CYCLES = 20;
    localparam time TIMEOUT = 200ns;

    localparam int LINE_SIZE_BYTES = 32;
    localparam real BUS_BW_BYTES_PER_NS = 4.0;
    localparam real BUS_LATENCY_NS = LINE_SIZE_BYTES / BUS_BW_BYTES_PER_NS;
    localparam time BUS_LATENCY = BUS_LATENCY_NS * 1ns;
    localparam time MIN_TOTAL_LATENCY = BUS_LATENCY + (MEM_LATENCY_CYCLES * 1ns);

    BusReq_mbx bus_mbx;
    BusReq_mbx bus_to_mem_mbx;
    BusEvt_mbx bus_evt_mbx[NUM_CORES];
    MemResp_mbx mem_mbx[NUM_CORES];

    Bus bus;
    Memory mem;

    task automatic send_req(bus_req_type_e req_type, logic [31:0] addr, int core_id);
        BusRequest req;
        req = new(req_type, addr, core_id);
        bus_mbx.put(req);
    endtask

    task automatic wait_for_response(int core_id, output bit ready);
        time waited;
        ready = 0;
        waited = 0;

        while (mem_mbx[core_id].num() == 0 && waited < TIMEOUT) begin
            #1;
            waited += 1ns;
        end

        if (mem_mbx[core_id].num() > 0) begin
            ready = 1;
        end
    endtask

    task automatic expect_response(int core_id, logic [31:0] addr, time t_start, string label);
        MemResponse resp;
        bit ready;
        time t_end;
        time delta;

        wait_for_response(core_id, ready);
        if (!ready) begin
            $error("[TB] FAIL %s: timeout waiting for response", label);
        end else begin
            mem_mbx[core_id].get(resp);
            t_end = $time;
            delta = t_end - t_start;
            if (delta < MIN_TOTAL_LATENCY) begin
                $error("[TB] FAIL %s: latency too small (%0t ns)", label, delta);
            end
            if (resp.address != addr || resp.dest_core_id != core_id) begin
                $error("[TB] FAIL %s: wrong response addr=%h dest=%0d",
                    label, resp.address, resp.dest_core_id);
            end else begin
                $display("@%0t [TB] PASS %s", $realtime, label);
            end
        end
    endtask

    task automatic expect_no_response_all(string label);
        bit ok;
        ok = 1;

        #TIMEOUT;

        for (int i = 0; i < NUM_CORES; i++) begin
            if (mem_mbx[i].num() != 0) begin
                ok = 0;
                $error("[TB] FAIL %s: unexpected response in core %0d mailbox", label, i);
            end
        end

        if (ok) begin
            $display("@%0t [TB] PASS %s", $realtime, label);
        end
    endtask

    task automatic drain_mailboxes();
        MemResponse resp;
        for (int i = 0; i < NUM_CORES; i++) begin
            while (mem_mbx[i].num() != 0) begin
                mem_mbx[i].get(resp);
            end
        end
    endtask

    initial begin
        time t_start;
        time t_start_burst[3];
        logic [31:0] burst_addr[3];
        MemResponse burst_resp;
        bit burst_ready;
        time t_end;
        time delta;
        int req_before;
        int busupd_before;

        $timeformat(-9, 3, " ns", 10);

        $display(" TEST BUS-MEMORY (PHASE 6)");

        bus_mbx = new();
        bus_to_mem_mbx = new();
        for (int i = 0; i < NUM_CORES; i++) begin
            bus_evt_mbx[i] = new();
            mem_mbx[i] = new();
        end

        bus = new(bus_mbx, bus_evt_mbx, mem_mbx, NUM_CORES);
        bus.bus_to_mem = bus_to_mem_mbx;

        mem = new(NUM_CORES);
        mem.from_bus = bus_to_mem_mbx;
        mem.to_cache = new[NUM_CORES];
        for (int i = 0; i < NUM_CORES; i++) begin
            mem.to_cache[i] = mem_mbx[i];
        end

        // Reset metrics for clean validation
        mem.total_requests = 0;
        mem.total_responses = 0;
        mem.busrd_count = 0;
        mem.busrdx_count = 0;
        mem.busupd_count = 0;
        mem.writeback_count = 0;
        mem.total_service_time = 0;
        foreach (mem.responses_per_core[i]) begin
            mem.responses_per_core[i] = 0;
        end

        fork
            bus.run();
            mem.run();
        join_none

        #1;

        // Test 1: BusRd forwarding
        $display("@%0t [TB] TEST 1: BusRd forwarding", $realtime);
        drain_mailboxes();
        t_start = $time;
        send_req(BusRd, 32'h0000_1000, 0);
        expect_response(0, 32'h0000_1000, t_start, "BusRd forward");

        // Test 2: BusRdX forwarding
        $display("@%0t [TB] TEST 2: BusRdX forwarding", $realtime);
        drain_mailboxes();
        t_start = $time;
        send_req(BusRdX, 32'h0000_2000, 1);
        expect_response(1, 32'h0000_2000, t_start, "BusRdX forward");

        // Test 3: BusUpd should not be forwarded
        $display("@%0t [TB] TEST 3: BusUpd no forward", $realtime);
        drain_mailboxes();
        req_before = mem.total_requests;
        busupd_before = mem.busupd_count;
        send_req(BusUpd, 32'h0000_3000, 2);
        expect_no_response_all("BusUpd no response");
        if (mem.total_requests != req_before) begin
            $error("[TB] FAIL BusUpd forwarding: total_requests=%0d expected=%0d",
                mem.total_requests, req_before);
        end
        if (mem.busupd_count != busupd_before) begin
            $error("[TB] FAIL BusUpd forwarding: busupd_count=%0d expected=%0d",
                mem.busupd_count, busupd_before);
        end

        // Test 4: multiple requests from same core (FIFO end-to-end)
        $display("@%0t [TB] TEST 4: FIFO end-to-end", $realtime);
        drain_mailboxes();
        burst_addr[0] = 32'h0000_A000; t_start_burst[0] = $time;
        send_req(BusRd, burst_addr[0], 0);
        burst_addr[1] = 32'h0000_A040; t_start_burst[1] = $time;
        send_req(BusRd, burst_addr[1], 0);
        burst_addr[2] = 32'h0000_A080; t_start_burst[2] = $time;
        send_req(BusRd, burst_addr[2], 0);

        for (int i = 0; i < 3; i++) begin
            wait_for_response(0, burst_ready);
            if (!burst_ready) begin
                $error("[TB] FAIL FIFO: timeout waiting for response %0d", i);
            end else begin
                mem_mbx[0].get(burst_resp);
                t_end = $time;
                delta = t_end - t_start_burst[i];
                if (delta < MIN_TOTAL_LATENCY) begin
                    $error("[TB] FAIL FIFO: latency too small (%0t ns)", delta);
                end
                if (burst_resp.address != burst_addr[i] || burst_resp.dest_core_id != 0) begin
                    $error("[TB] FAIL FIFO: expected addr=%h got addr=%h",
                        burst_addr[i], burst_resp.address);
                end else begin
                    $display("@%0t [TB] PASS FIFO idx=%0d", $realtime, i);
                end
            end
        end

        $display("@%0t [TB] ALL TESTS COMPLETE", $realtime);
        #10;
        $finish;
    end

endmodule
