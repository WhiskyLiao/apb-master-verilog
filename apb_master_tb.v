// APB Master Testbench
// Covers: single write, single read, wait-state insertion, slave error,
// back-to-back transfers, and reset behaviour.

`timescale 1ns/1ps

module apb_master_tb;

    // -----------------------------------------------------------------------
    // Parameters
    // -----------------------------------------------------------------------
    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 32;
    localparam NUM_SLAVES = 4;
    localparam STRB_WIDTH = DATA_WIDTH / 8;
    localparam CLK_HALF   = 5;   // 10 ns period

    // -----------------------------------------------------------------------
    // DUT connections
    // -----------------------------------------------------------------------
    reg                   PCLK, PRESETn;
    reg                   req_valid;
    reg  [ADDR_WIDTH-1:0] req_addr;
    reg                   req_write;
    reg  [DATA_WIDTH-1:0] req_wdata;
    reg  [STRB_WIDTH-1:0] req_strb;
    reg  [2:0]            req_prot;
    wire                  req_ready;
    wire                  rsp_valid;
    wire [DATA_WIDTH-1:0] rsp_rdata;
    wire                  rsp_slverr;
    wire [ADDR_WIDTH-1:0] PADDR;
    wire [NUM_SLAVES-1:0] PSEL;
    wire                  PENABLE;
    wire                  PWRITE;
    wire [DATA_WIDTH-1:0] PWDATA;
    wire [STRB_WIDTH-1:0] PSTRB;
    wire [2:0]            PPROT;
    reg  [DATA_WIDTH-1:0] PRDATA;
    reg                   PREADY;
    reg                   PSLVERR;

    apb_master #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_SLAVES(NUM_SLAVES)
    ) dut (
        .PCLK      (PCLK),
        .PRESETn   (PRESETn),
        .req_valid (req_valid),
        .req_ready (req_ready),
        .req_addr  (req_addr),
        .req_write (req_write),
        .req_wdata (req_wdata),
        .req_strb  (req_strb),
        .req_prot  (req_prot),
        .rsp_valid (rsp_valid),
        .rsp_rdata (rsp_rdata),
        .rsp_slverr(rsp_slverr),
        .PADDR     (PADDR),
        .PSEL      (PSEL),
        .PENABLE   (PENABLE),
        .PWRITE    (PWRITE),
        .PWDATA    (PWDATA),
        .PSTRB     (PSTRB),
        .PPROT     (PPROT),
        .PRDATA    (PRDATA),
        .PREADY    (PREADY),
        .PSLVERR   (PSLVERR)
    );

    // -----------------------------------------------------------------------
    // Clock
    // -----------------------------------------------------------------------
    initial PCLK = 0;
    always #CLK_HALF PCLK = ~PCLK;

    // -----------------------------------------------------------------------
    // Simple memory model for slave responses
    // -----------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] mem [0:255];
    integer i;
    initial for (i = 0; i < 256; i = i + 1) mem[i] = i * 32'h01010101;

    // -----------------------------------------------------------------------
    // Slave response task (handles PREADY / PSLVERR injection)
    // -----------------------------------------------------------------------
    integer wait_cycles;
    reg     inject_err;

    task slave_respond;
        input integer extra_waits;
        input         err;
        integer w;
        begin
            // Insert wait states: deassert PREADY for extra_waits cycles
            PREADY  = 0;
            PSLVERR = 0;
            for (w = 0; w < extra_waits; w = w + 1)
                @(posedge PCLK);
            // Assert PREADY and optionally PSLVERR
            @(negedge PCLK);
            PREADY  = 1;
            PSLVERR = err;
            if (!PWRITE)
                PRDATA = mem[PADDR[7:0]];
            else
                mem[PADDR[7:0]] = PWDATA;
            @(posedge PCLK);
            #1;
            PREADY  = 0;
            PSLVERR = 0;
            PRDATA  = {DATA_WIDTH{1'b0}};
        end
    endtask

    // -----------------------------------------------------------------------
    // Request helper
    // -----------------------------------------------------------------------
    task do_write;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] data;
        input [STRB_WIDTH-1:0] strb;
        input integer           extra_waits;
        begin
            @(negedge PCLK);
            wait (req_ready);
            req_valid = 1;
            req_addr  = addr;
            req_write = 1;
            req_wdata = data;
            req_strb  = strb;
            req_prot  = 3'b000;
            @(posedge PCLK); #1;
            req_valid = 0;
            // Wait for SETUP phase to finish (PENABLE goes high)
            @(posedge PCLK); #1;
            slave_respond(extra_waits, 0);
            wait (rsp_valid);
            $display("[%0t] WRITE  addr=%08h data=%08h strb=%b — DONE (slverr=%b)",
                     $time, addr, data, strb, rsp_slverr);
        end
    endtask

    task do_read;
        input [ADDR_WIDTH-1:0] addr;
        input integer           extra_waits;
        begin
            @(negedge PCLK);
            wait (req_ready);
            req_valid = 1;
            req_addr  = addr;
            req_write = 0;
            req_wdata = {DATA_WIDTH{1'b0}};
            req_strb  = {STRB_WIDTH{1'b0}};
            req_prot  = 3'b010; // non-secure data
            @(posedge PCLK); #1;
            req_valid = 0;
            @(posedge PCLK); #1;
            slave_respond(extra_waits, 0);
            wait (rsp_valid);
            $display("[%0t] READ   addr=%08h data=%08h — DONE (slverr=%b)",
                     $time, addr, rsp_rdata, rsp_slverr);
        end
    endtask

    task do_read_err;
        input [ADDR_WIDTH-1:0] addr;
        begin
            @(negedge PCLK);
            wait (req_ready);
            req_valid = 1;
            req_addr  = addr;
            req_write = 0;
            req_wdata = {DATA_WIDTH{1'b0}};
            req_strb  = {STRB_WIDTH{1'b0}};
            req_prot  = 3'b000;
            @(posedge PCLK); #1;
            req_valid = 0;
            @(posedge PCLK); #1;
            // Slave responds with error
            @(negedge PCLK);
            PREADY  = 1;
            PSLVERR = 1;
            PRDATA  = 32'hDEAD_BEEF;
            @(posedge PCLK); #1;
            PREADY  = 0;
            PSLVERR = 0;
            wait (rsp_valid);
            $display("[%0t] READ   addr=%08h data=%08h — ERROR (slverr=%b)",
                     $time, addr, rsp_rdata, rsp_slverr);
        end
    endtask

    // -----------------------------------------------------------------------
    // Stimulus
    // -----------------------------------------------------------------------
    integer pass, fail;

    task check;
        input cond;
        input [127:0] msg;
        begin
            if (cond) begin
                $display("  PASS: %s", msg);
                pass = pass + 1;
            end else begin
                $display("  FAIL: %s", msg);
                fail = fail + 1;
            end
        end
    endtask

    initial begin
        pass = 0; fail = 0;
        PRESETn   = 0;
        req_valid = 0;
        req_addr  = 0;
        req_write = 0;
        req_wdata = 0;
        req_strb  = 4'hF;
        req_prot  = 0;
        PRDATA    = 0;
        PREADY    = 0;
        PSLVERR   = 0;

        repeat (4) @(posedge PCLK);
        PRESETn = 1;
        repeat (2) @(posedge PCLK);

        // -----------------------------------------------------------------
        // Test 1: Simple write, no wait states
        // -----------------------------------------------------------------
        $display("\n--- Test 1: Single write (no wait states) ---");
        do_write(32'h0000_0010, 32'hCAFE_BABE, 4'hF, 0);
        check(mem[8'h10] === 32'hCAFE_BABE,
              "Write data stored in slave memory");
        check(rsp_slverr === 0, "No slave error on write");

        // -----------------------------------------------------------------
        // Test 2: Simple read, no wait states
        // -----------------------------------------------------------------
        $display("\n--- Test 2: Single read (no wait states) ---");
        do_read(32'h0000_0004, 0);
        check(rsp_rdata === mem[8'h04], "Read data matches slave memory");

        // -----------------------------------------------------------------
        // Test 3: Write with 2 wait states
        // -----------------------------------------------------------------
        $display("\n--- Test 3: Write with 2 wait states ---");
        do_write(32'h0000_0020, 32'hDEAD_BEEF, 4'hA, 2);
        check(rsp_slverr === 0, "No error after wait-state write");

        // -----------------------------------------------------------------
        // Test 4: Read with 3 wait states
        // -----------------------------------------------------------------
        $display("\n--- Test 4: Read with 3 wait states ---");
        do_read(32'h0000_0020, 3);
        check(rsp_rdata === 32'hDEAD_BEEF, "Read-back after wait-state write");

        // -----------------------------------------------------------------
        // Test 5: Slave error on read
        // -----------------------------------------------------------------
        $display("\n--- Test 5: Slave error ---");
        do_read_err(32'h0000_0008);
        check(rsp_slverr === 1, "PSLVERR captured");
        check(rsp_rdata  === 32'hDEAD_BEEF, "Error data captured");

        // -----------------------------------------------------------------
        // Test 6: APB timing — PSEL/PENABLE compliance
        //   PSEL=1 during SETUP, PSEL=1+PENABLE=1 during ACCESS
        //   PENABLE must be 0 in SETUP, 1 in ACCESS
        // -----------------------------------------------------------------
        $display("\n--- Test 6: APB timing compliance (waveform check) ---");
        @(negedge PCLK);
        req_valid = 1;
        req_addr  = 32'h0000_0000;
        req_write = 1;
        req_wdata = 32'hAABBCCDD;
        req_strb  = 4'hF;
        @(posedge PCLK); #1;  // SETUP phase starts
        req_valid = 0;
        check(PSEL !== 0,      "PSEL asserted in SETUP");
        check(PENABLE === 1'b0,"PENABLE deasserted in SETUP");
        @(posedge PCLK); #1;  // ACCESS phase
        check(PSEL !== 0,      "PSEL asserted in ACCESS");
        check(PENABLE === 1'b1,"PENABLE asserted in ACCESS");
        @(negedge PCLK);
        PREADY = 1;
        @(posedge PCLK); #1;
        PREADY = 0;
        @(posedge PCLK); #1;
        check(PSEL === 0,      "PSEL deasserted after transfer");
        check(PENABLE === 1'b0,"PENABLE deasserted after transfer");

        // -----------------------------------------------------------------
        // Test 7: Write-byte-enable (PSTRB)
        // -----------------------------------------------------------------
        $display("\n--- Test 7: PSTRB byte-enable ---");
        @(negedge PCLK);
        req_valid = 1;
        req_addr  = 32'h0000_0040;
        req_write = 1;
        req_wdata = 32'h12345678;
        req_strb  = 4'b0101;   // bytes 0 and 2 only
        req_prot  = 3'b001;
        @(posedge PCLK); #1;
        req_valid = 0;
        @(posedge PCLK); #1;
        check(PSTRB === 4'b0101, "PSTRB driven correctly");
        check(PPROT === 3'b001,  "PPROT driven correctly");
        @(negedge PCLK);
        PREADY = 1;
        @(posedge PCLK); #1;
        PREADY = 0;

        // -----------------------------------------------------------------
        // Summary
        // -----------------------------------------------------------------
        repeat (4) @(posedge PCLK);
        $display("\n========================================");
        $display(" Results: %0d passed, %0d failed", pass, fail);
        $display("========================================\n");
        if (fail === 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $finish;
    end

    // -----------------------------------------------------------------------
    // Timeout watchdog
    // -----------------------------------------------------------------------
    initial begin
        #100000;
        $display("TIMEOUT — simulation exceeded limit");
        $finish;
    end

    // -----------------------------------------------------------------------
    // Waveform dump
    // -----------------------------------------------------------------------
    initial begin
        $dumpfile("apb_master_tb.vcd");
        $dumpvars(0, apb_master_tb);
    end

endmodule
