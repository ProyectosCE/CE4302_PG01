`timescale 1ns/1ns

module memory_tb;

    import types_pkg::*;
    import model_pkg::*;

    localparam int NUM_CORES = 4;
    localparam time TIMEOUT = 20ns;

    BusReq_mbx bus_mbx;
    MemResp_mbx mem_mbx[NUM_CORES];

    Memory mem;

    task automatic get_with_timeout(int core_id, output MemResponse resp, output bit got);
        got = 0;
        fork
            begin
                mem_mbx[core_id].get(resp);
                got = 1;
            end
            begin
                #TIMEOUT;
            end
        join_any
        disable fork;
    endtask

    task automatic expect_response(int core_id, logic [31:0] addr, string label);
        MemResponse resp;
        bit got;

        get_with_timeout(core_id, resp, got);
        if (!got) begin
            $error("[TB] FAIL %s: timeout waiting for response", label);
        end else if (resp.address != addr || resp.dest_core_id != core_id) begin
            $error("[TB] FAIL %s: wrong response addr=%h dest=%0d",
                label, resp.address, resp.dest_core_id);
        end else begin
            $display("@%0t [TB] PASS %s", $realtime, label);
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

    initial begin
        $timeformat(-9, 3, " ns", 10);

        $display(" TEST MEMORY (PHASE 1)");

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
        bus_mbx.put(new(BusRd, 32'h0000_1000, 0));
        expect_response(0, 32'h0000_1000, "BusRd core0");
        for (int i = 1; i < NUM_CORES; i++) begin
            if (mem_mbx[i].num() != 0) begin
                $error("[TB] FAIL basic routing: unexpected response in core %0d", i);
            end
        end

        // Test 2: multiple cores
        $display("@%0t [TB] TEST 2: multiple cores", $realtime);
        bus_mbx.put(new(BusRdX, 32'h0000_2000, 1));
        bus_mbx.put(new(BusRd,  32'h0000_3000, 3));
        expect_response(1, 32'h0000_2000, "BusRdX core1");
        expect_response(3, 32'h0000_3000, "BusRd core3");
        if (mem_mbx[2].num() != 0) begin
            $error("[TB] FAIL multiple cores: unexpected response in core 2");
        end

        // Test 3: BusUpd should be ignored
        $display("@%0t [TB] TEST 3: BusUpd ignored", $realtime);
        bus_mbx.put(new(BusUpd, 32'h0000_4000, 2));
        expect_no_response_all("BusUpd ignored");

        $display("@%0t [TB] ALL TESTS COMPLETE", $realtime);
        #10;
        $finish;
    end

endmodule
