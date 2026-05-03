// Interface for Tracing - parameterized for multiple ports
interface component_interface();
    logic is_producer;
    logic [31:0] src_id;
    logic [31:0] dest_id;
    logic [31:0] data;
endinterface