// APB Master Module — AMBA APB4 Specification Compliant
// Implements: IDLE/SETUP/ACCESS FSM, PREADY wait-state support, PSLVERR error
// capture, write strobes (PSTRB), protection (PPROT), multi-slave PSEL decode.
//
// Timing note: APB outputs (PADDR, PSEL, PWRITE, PWDATA, PSTRB, PPROT) are
// sampled from req_* at the clock edge that begins the SETUP phase and held
// stable through ACCESS by the registered output stage — no separate capture
// registers are needed.

module apb_master #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter NUM_SLAVES = 4,
    parameter STRB_WIDTH = DATA_WIDTH / 8
) (
    // -----------------------------------------------------------------------
    // Global signals
    // -----------------------------------------------------------------------
    input  wire                   PCLK,
    input  wire                   PRESETn,

    // -----------------------------------------------------------------------
    // Requester interface
    // -----------------------------------------------------------------------
    input  wire                   req_valid,   // assert to start a transfer
    output wire                   req_ready,   // master is ready for a new req
    input  wire [ADDR_WIDTH-1:0]  req_addr,
    input  wire                   req_write,   // 1 = write, 0 = read
    input  wire [DATA_WIDTH-1:0]  req_wdata,
    input  wire [STRB_WIDTH-1:0]  req_strb,    // PSTRB byte-enables
    input  wire [2:0]             req_prot,    // PPROT[2:0]

    output reg                    rsp_valid,   // one-cycle pulse: transfer done
    output reg  [DATA_WIDTH-1:0]  rsp_rdata,
    output reg                    rsp_slverr,

    // -----------------------------------------------------------------------
    // APB bus outputs
    // -----------------------------------------------------------------------
    output reg  [ADDR_WIDTH-1:0]  PADDR,
    output reg  [NUM_SLAVES-1:0]  PSEL,
    output reg                    PENABLE,
    output reg                    PWRITE,
    output reg  [DATA_WIDTH-1:0]  PWDATA,
    output reg  [STRB_WIDTH-1:0]  PSTRB,
    output reg  [2:0]             PPROT,

    // APB bus inputs
    input  wire [DATA_WIDTH-1:0]  PRDATA,
    input  wire                   PREADY,
    input  wire                   PSLVERR
);

    // -----------------------------------------------------------------------
    // State encoding
    // -----------------------------------------------------------------------
    localparam [1:0] ST_IDLE   = 2'd0,
                     ST_SETUP  = 2'd1,
                     ST_ACCESS = 2'd2;

    reg [1:0] state, nstate;

    // -----------------------------------------------------------------------
    // Address decode: map PADDR[31:28] to one-hot PSEL.
    // Each slave occupies a 256 MB region starting at i * 0x1000_0000.
    // Adjust for your memory map as needed.
    // -----------------------------------------------------------------------
    function [NUM_SLAVES-1:0] addr_decode;
        input [ADDR_WIDTH-1:0] addr;
        reg [3:0] i;
        begin
            addr_decode = {NUM_SLAVES{1'b0}};
            for (i = 0; i < NUM_SLAVES; i = i + 1'b1) begin
                if (addr[ADDR_WIDTH-1 -: 4] == i)
                    addr_decode[i] = 1'b1;
            end
        end
    endfunction

    // -----------------------------------------------------------------------
    // FSM — sequential
    // -----------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) state <= ST_IDLE;
        else          state <= nstate;
    end

    // -----------------------------------------------------------------------
    // FSM — combinational next-state
    // -----------------------------------------------------------------------
    always @(*) begin
        case (state)
            ST_IDLE:   nstate = req_valid ? ST_SETUP : ST_IDLE;
            ST_SETUP:  nstate = ST_ACCESS;
            ST_ACCESS: nstate = PREADY ? (req_valid ? ST_SETUP : ST_IDLE)
                                       : ST_ACCESS;
            default:   nstate = ST_IDLE;
        endcase
    end

    // -----------------------------------------------------------------------
    // APB output drive
    //
    // SETUP entry (nstate == ST_SETUP): sample req_* directly so that PADDR,
    // PSEL, PWRITE, PWDATA, PSTRB and PPROT are correct from the very first
    // SETUP cycle.  No intermediate capture register is needed because outputs
    // are registered — they hold their values unchanged through ACCESS.
    //
    // ACCESS entry (nstate == ST_ACCESS): only PENABLE is raised; all other
    // outputs retain the values driven during SETUP.
    //
    // IDLE entry (nstate == ST_IDLE): deassert PSEL and PENABLE.
    // -----------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            PADDR   <= {ADDR_WIDTH{1'b0}};
            PSEL    <= {NUM_SLAVES{1'b0}};
            PENABLE <= 1'b0;
            PWRITE  <= 1'b0;
            PWDATA  <= {DATA_WIDTH{1'b0}};
            PSTRB   <= {STRB_WIDTH{1'b0}};
            PPROT   <= 3'b000;
        end else begin
            case (nstate)
                ST_SETUP: begin
                    PADDR   <= req_addr;
                    PWRITE  <= req_write;
                    PWDATA  <= req_wdata;
                    PSTRB   <= req_strb;
                    PPROT   <= req_prot;
                    PSEL    <= addr_decode(req_addr);
                    PENABLE <= 1'b0;
                end
                ST_ACCESS: begin
                    PENABLE <= 1'b1;
                    // PADDR, PSEL, PWRITE, PWDATA, PSTRB, PPROT hold
                end
                default: begin   // ST_IDLE
                    PSEL    <= {NUM_SLAVES{1'b0}};
                    PENABLE <= 1'b0;
                end
            endcase
        end
    end

    // -----------------------------------------------------------------------
    // Response — capture bus outputs on transfer completion
    // -----------------------------------------------------------------------
    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            rsp_valid  <= 1'b0;
            rsp_rdata  <= {DATA_WIDTH{1'b0}};
            rsp_slverr <= 1'b0;
        end else begin
            rsp_valid <= (state == ST_ACCESS) && PREADY;
            if ((state == ST_ACCESS) && PREADY) begin
                rsp_rdata  <= PRDATA;
                rsp_slverr <= PSLVERR;
            end
        end
    end

    // -----------------------------------------------------------------------
    // req_ready: true when the master can accept a new request.
    // Asserted in IDLE and at the completion cycle of ACCESS (enabling
    // back-to-back pipelined transfers with zero idle cycles).
    // -----------------------------------------------------------------------
    assign req_ready = (state == ST_IDLE) ||
                       ((state == ST_ACCESS) && PREADY);

endmodule
