`timescale 1ns/1ns

module memory_tb;

    import types_pkg::*;
    import model_pkg::*;

    localparam int NUM_CORES = 4;
    localparam int MEM_LATENCY_CYCLES = 20;
    localparam time TIMEOUT = 100ns;

    BusReq_mbx bus_mbx;
    MemResp_mbx mem_mbx[NUM_CORES];

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

    task automatic wait_for_any_response(output int core_id, output MemResponse resp, output bit ready);
        time waited;
        ready = 0;
        waited = 0;

        while (waited < TIMEOUT) begin
            for (int i = 0; i < NUM_CORES; i++) begin
                if (mem_mbx[i].num() != 0) begin
                    core_id = i;
                    mem_mbx[i].get(resp);
                    ready = 1;
                    return;
                end
            end
            #1;
            waited += 1ns;
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
            if (delta < MEM_LATENCY_CYCLES) begin
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
        // Timing variables for latency measurement
        time t_start_core0;
        time t_start_core1;
        time t_start_core3;
        time t_start_burst[3];
        logic [31:0] burst_addr[3];
        int burst_core[3];
        int got_core;
        MemResponse burst_resp;
        bit burst_ready;
        bit ok_metrics;
        time t_end;
        time delta;
        time avg_service_time;

        $timeformat(-9, 3, " ns", 10);

        $display(" TEST MEMORY (PHASE 5)");

        bus_mbx = new();
        for (int i = 0; i < NUM_CORES; i++) begin
            mem_mbx[i] = new();
        end

        mem = new(NUM_CORES);
        mem.from_bus = bus_mbx;
        mem.to_cache = new[NUM_CORES];
        for (int i = 0; i < NUM_CORES; i++) begin
            mem.to_cache[i] = mem_mbx[i];
        end

        fork
            mem.run();
        join_none

        #1;

        // Test 1: basic routing (core 0)
        $display("@%0t [TB] TEST 1: basic routing", $realtime);
        drain_mailboxes();
        t_start_core0 = $time;
        send_req(BusRd, 32'h0000_1000, 0);
        expect_response(0, 32'h0000_1000, t_start_core0, "BusRd core0");
        for (int i = 1; i < NUM_CORES; i++) begin
            if (mem_mbx[i].num() != 0) begin
                $error("[TB] FAIL basic routing: unexpected response in core %0d", i);
            end
        end

        // Test 2: multiple cores
        $display("@%0t [TB] TEST 2: multiple cores", $realtime);
        drain_mailboxes();
        t_start_core1 = $time;
        send_req(BusRdX, 32'h0000_2000, 1);
        t_start_core3 = $time;
        send_req(BusRd,  32'h0000_3000, 3);
        expect_response(1, 32'h0000_2000, t_start_core1, "BusRdX core1");
        expect_response(3, 32'h0000_3000, t_start_core3, "BusRd core3");
        if (mem_mbx[2].num() != 0) begin
            $error("[TB] FAIL multiple cores: unexpected response in core 2");
        end

        // Test 3: BusUpd should be ignored
        $display("@%0t [TB] TEST 3: BusUpd ignored", $realtime);
        drain_mailboxes();
        send_req(BusUpd, 32'h0000_4000, 2);
        expect_no_response_all("BusUpd ignored");

        // Test 4: burst requests (FIFO order)
        $display("@%0t [TB] TEST 4: burst requests FIFO", $realtime);
        drain_mailboxes();
        burst_addr[0] = 32'h0000_5000; burst_core[0] = 0; t_start_burst[0] = $time;
        send_req(BusRd, burst_addr[0], burst_core[0]);
        burst_addr[1] = 32'h0000_5040; burst_core[1] = 1; t_start_burst[1] = $time;
        send_req(BusRdX, burst_addr[1], burst_core[1]);
        burst_addr[2] = 32'h0000_5080; burst_core[2] = 2; t_start_burst[2] = $time;
        send_req(BusRd, burst_addr[2], burst_core[2]);

        for (int i = 0; i < 3; i++) begin
            wait_for_any_response(got_core, burst_resp, burst_ready);
            if (!burst_ready) begin
                $error("[TB] FAIL burst FIFO: timeout waiting for response %0d", i);
            end else begin
                t_end = $time;
                delta = t_end - t_start_burst[i];
                if (delta < MEM_LATENCY_CYCLES) begin
                    $error("[TB] FAIL burst FIFO: latency too small (%0t ns)", delta);
                end
                if (got_core != burst_core[i] ||
                    burst_resp.dest_core_id != burst_core[i] ||
                    burst_resp.address != burst_addr[i]) begin
                    $error("[TB] FAIL burst FIFO: expected core=%0d addr=%h got core=%0d addr=%h",
                        burst_core[i], burst_addr[i], got_core, burst_resp.address);
                end else begin
                    $display("@%0t [TB] PASS burst FIFO idx=%0d", $realtime, i);
                end
            end
        end

        // Test 5: metrics validation
        $display("@%0t [TB] TEST 5: metrics validation", $realtime);
        drain_mailboxes();
        #1;

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

        t_start_core0 = $time;
        send_req(BusRd, 32'h0000_6000, 0);
        t_start_core1 = $time;
        send_req(BusRdX, 32'h0000_7000, 1);
        send_req(BusUpd, 32'h0000_8000, 2);
        t_start_core3 = $time;
        send_req(BusRd, 32'h0000_9000, 3);

        expect_response(0, 32'h0000_6000, t_start_core0, "BusRd core0 metrics");
        expect_response(1, 32'h0000_7000, t_start_core1, "BusRdX core1 metrics");
        expect_response(3, 32'h0000_9000, t_start_core3, "BusRd core3 metrics");

        mem.print_metrics();

        ok_metrics = 1;
        if (mem.total_requests != 4) begin
            ok_metrics = 0;
            $error("[TB] FAIL metrics: total_requests=%0d expected=4", mem.total_requests);
        end
        if (mem.total_responses != 3) begin
            ok_metrics = 0;
            $error("[TB] FAIL metrics: total_responses=%0d expected=3", mem.total_responses);
        end
        if (mem.busrd_count != 2) begin
            ok_metrics = 0;
            $error("[TB] FAIL metrics: busrd_count=%0d expected=2", mem.busrd_count);
        end
        if (mem.busrdx_count != 1) begin
            ok_metrics = 0;
            $error("[TB] FAIL metrics: busrdx_count=%0d expected=1", mem.busrdx_count);
        end
        if (mem.busupd_count != 1) begin
            ok_metrics = 0;
            $error("[TB] FAIL metrics: busupd_count=%0d expected=1", mem.busupd_count);
        end
        // Scaffolding check: no write-backs should be triggered yet.
        if (mem.writeback_count != 0) begin
            ok_metrics = 0;
            $error("[TB] FAIL metrics: writeback_count=%0d expected=0", mem.writeback_count);
        end
        if (mem.responses_per_core[0] != 1) begin
            ok_metrics = 0;
            $error("[TB] FAIL metrics: core0 responses=%0d expected=1", mem.responses_per_core[0]);
        end
        if (mem.responses_per_core[1] != 1) begin
            ok_metrics = 0;
            $error("[TB] FAIL metrics: core1 responses=%0d expected=1", mem.responses_per_core[1]);
        end
        if (mem.responses_per_core[2] != 0) begin
            ok_metrics = 0;
            $error("[TB] FAIL metrics: core2 responses=%0d expected=0", mem.responses_per_core[2]);
        end
        if (mem.responses_per_core[3] != 1) begin
            ok_metrics = 0;
            $error("[TB] FAIL metrics: core3 responses=%0d expected=1", mem.responses_per_core[3]);
        end

        if (mem.total_responses > 0) begin
            avg_service_time = mem.total_service_time / mem.total_responses;
            if (avg_service_time < MEM_LATENCY_CYCLES) begin
                ok_metrics = 0;
                $error("[TB] FAIL metrics: avg_service_time=%0t expected >= %0d",
                    avg_service_time, MEM_LATENCY_CYCLES);
            end
        end

        if (ok_metrics) begin
            $display("@%0t [TB] PASS metrics validation", $realtime);
        end

        $display("@%0t [TB] ALL TESTS COMPLETE", $realtime);
        #10;
        $finish;
    end

endmodule
