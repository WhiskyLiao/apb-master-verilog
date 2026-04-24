# APB Master

An AMBA APB4-compliant master controller implemented in Verilog. Supports parameterizable address/data widths, multiple slaves, byte-level write strobes, wait states, and slave error reporting.

## Features

- Full AMBA APB4 protocol compliance (SETUP + ACCESS two-phase transfer)
- Parameterizable address width, data width, and slave count
- One-hot slave select with configurable address decoding
- Back-to-back transfer support (zero idle cycles between transactions)
- Wait-state handling via `PREADY`
- Slave error capture via `PSLVERR`
- Write byte strobes (`PSTRB`) and protection signals (`PPROT`)
- All APB outputs registered for clean timing
- Synthesizable (no `automatic` tasks, no `integer` loop variables)

## Files

| File | Description |
|------|-------------|
| `apb_master.v` | APB4 master module |
| `apb_master_tb.v` | Self-checking testbench with 7 test scenarios |

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `ADDR_WIDTH` | 32 | Address bus width in bits |
| `DATA_WIDTH` | 32 | Data bus width in bits |
| `NUM_SLAVES` | 4 | Number of addressable slaves |
| `STRB_WIDTH` | `DATA_WIDTH/8` | Byte strobe width (derived automatically) |

## Ports

### Global

| Port | Direction | Description |
|------|-----------|-------------|
| `PCLK` | input | System clock |
| `PRESETn` | input | Active-low asynchronous reset |

### Requester Interface

| Port | Direction | Description |
|------|-----------|-------------|
| `req_valid` | input | Initiate a transfer |
| `req_ready` | output | Master ready to accept a new request |
| `req_addr` | input | Transfer address |
| `req_write` | input | 1 = write, 0 = read |
| `req_wdata` | input | Write data |
| `req_strb` | input | Write byte strobes |
| `req_prot` | input | AMBA PPROT protection encoding (3 bits) |
| `rsp_valid` | output | Single-cycle pulse on transfer completion |
| `rsp_rdata` | output | Read data returned from slave |
| `rsp_slverr` | output | Slave error flag |

### APB Bus

| Port | Direction | Description |
|------|-----------|-------------|
| `PADDR` | output | APB address |
| `PSEL` | output | One-hot slave select |
| `PENABLE` | output | APB enable (0 = SETUP phase, 1 = ACCESS phase) |
| `PWRITE` | output | Write enable |
| `PWDATA` | output | Write data |
| `PSTRB` | output | Write byte strobes |
| `PPROT` | output | Protection control |
| `PRDATA` | input | Read data from slave |
| `PREADY` | input | Slave ready (hold low to insert wait states) |
| `PSLVERR` | input | Slave error |

## State Machine

```
         req_valid
IDLE ───────────────► SETUP
 ▲                      │
 │                      │ (next cycle)
 │                      ▼
 │    PREADY & !req   ACCESS ◄─── PREADY=0
 └───────────────────    │        (wait states)
                         │ PREADY & req_valid
                         └──────────────► SETUP
```

| State | Description |
|-------|-------------|
| IDLE | No transfer; waiting for `req_valid` |
| SETUP | Address and control sampled; `PSEL` asserted, `PENABLE` low |
| ACCESS | `PENABLE` asserted; waits for slave `PREADY` |

## Address Map

The default decoder assigns each slave a 256 MB region based on the top 4 address bits:

| Slave | Address Range |
|-------|---------------|
| 0 | `0x0000_0000` – `0x0FFF_FFFF` |
| 1 | `0x1000_0000` – `0x1FFF_FFFF` |
| 2 | `0x2000_0000` – `0x2FFF_FFFF` |
| 3 | `0x3000_0000` – `0x3FFF_FFFF` |

## Instantiation

```verilog
apb_master #(
    .ADDR_WIDTH(32),
    .DATA_WIDTH(32),
    .NUM_SLAVES(4)
) u_apb_master (
    .PCLK      (clk),
    .PRESETn   (rst_n),

    // Requester interface
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

    // APB bus
    .PADDR  (PADDR),
    .PSEL   (PSEL),
    .PENABLE(PENABLE),
    .PWRITE (PWRITE),
    .PWDATA (PWDATA),
    .PSTRB  (PSTRB),
    .PPROT  (PPROT),
    .PRDATA (PRDATA),
    .PREADY (PREADY),
    .PSLVERR(PSLVERR)
);
```

## Simulation

Requires [Icarus Verilog](https://github.com/steveicarus/iverilog).

```bash
# Compile
iverilog -o apb_master_tb apb_master.v apb_master_tb.v

# Run
vvp apb_master_tb

# View waveforms (requires GTKWave)
gtkwave apb_master_tb.vcd
```

The testbench covers 7 scenarios: single write, single read, write with wait states, read with wait states, slave error injection, APB timing compliance, and byte-strobe/PPROT verification.

## License

This project is released under the MIT License.
