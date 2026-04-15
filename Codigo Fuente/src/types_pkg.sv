package types_pkg;

    timeunit 1ns;
    timeprecision 1ns;

    // ENUMS
    typedef enum {
        PrRd,
        PrWr
    } core_req_type_e;

    typedef enum {
        BusRd,
        BusRdX,
        BusUpd
    } bus_req_type_e;

    // CoreRequest
    class CoreRequest;
        core_req_type_e req_type;
        logic [31:0] address;
        int src_core_id;

        function new(core_req_type_e req_type, logic [31:0] address, int src_core_id);
            this.req_type = req_type;
            this.address = address;
            this.src_core_id = src_core_id;
        endfunction

        function void print();
            $display("[CoreRequest] type=%0d addr=%h core=%0d", req_type, address, src_core_id);
        endfunction
    endclass

    // BusRequest
    class BusRequest;
        bus_req_type_e req_type;
        logic [31:0] address;
        int src_core_id;

        function new(bus_req_type_e req_type, logic [31:0] address, int src_core_id);
            this.req_type = req_type;
            this.address = address;
            this.src_core_id = src_core_id;
        endfunction

        function void print();
            $display("[BusRequest] type=%0d addr=%h core=%0d", req_type, address, src_core_id);
        endfunction
    endclass

    // BusEvent (broadcast)
    class BusEvent;
        bus_req_type_e req_type;
        logic [31:0] address;
        int src_core_id;

        function new(bus_req_type_e req_type, logic [31:0] address, int src_core_id);
            this.req_type = req_type;
            this.address = address;
            this.src_core_id = src_core_id;
        endfunction

        function void print();
            $display("[BusEvent] type=%0d addr=%h core=%0d", req_type, address, src_core_id);
        endfunction
    endclass

    // MemResponse
    class MemResponse;
        logic [31:0] address;
        int dest_core_id;

        function new(logic [31:0] address, int dest_core_id);
            this.address = address;
            this.dest_core_id = dest_core_id;
        endfunction

        function void print();
            $display("[MemResponse] addr=%h dest=%0d", address, dest_core_id);
        endfunction
    endclass

    // Typedefs para mailboxes
    typedef mailbox #(CoreRequest) CoreReq_mbx;
    typedef mailbox #(BusRequest)  BusReq_mbx;
    typedef mailbox #(BusEvent)    BusEvt_mbx;
    typedef mailbox #(MemResponse) MemResp_mbx;

endpackage