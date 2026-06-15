# APB Master — Verilog

An AMBA APB4-compliant master controller implemented in synthesisable Verilog. Supports parameterisable address/data widths, multiple slaves, byte-level write strobes, wait states, and slave error reporting.

## Features

- Full AMBA APB4 protocol compliance (SETUP + ACCESS two-phase transfer)
- Parameterisable address width, data width, and slave count
- One-hot slave select with configurable address decoding
- Back-to-back transfer support (zero idle cycles between transactions)
- Wait-state handling via `PREADY`
- Slave error capture via `PSLVERR`
- Write byte strobes (`PSTRB`) and protection signals (`PPROT`)
- All APB outputs registered for clean timing
- Synthesisable (no `automatic` tasks, no `integer` loop variables)

## Repository Layout

```
.
├── rtl/
│   └── apb_master.v       # Synthesisable APB4 master
├── tb/
│   └── apb_master_tb.v    # Self-checking testbench
├── sim/                   # Simulation artefacts (git-ignored)
├── Makefile               # Icarus Verilog simulation flow
├── LICENSE
└── README.md
```

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

## Operation

The master implements the three-state APB transfer FSM:

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

Requires [Icarus Verilog](https://steveicarus.github.io/iverilog/) (`iverilog` / `vvp`). Optional [GTKWave](https://gtkwave.sourceforge.net/) for waveforms.

```bash
make run      # compile RTL + testbench and run the simulation
make waves    # run, then open the waveform in GTKWave
make clean    # remove the sim/ build directory
```

Build artefacts (the compiled binary, `*.vcd`, and `sim.log`) are written to the git-ignored `sim/` directory.

### Test Cases

| # | Description |
|---|-------------|
| 1 | Single write |
| 2 | Single read |
| 3 | Write with wait states |
| 4 | Read with wait states |
| 5 | Slave error injection |
| 6 | APB timing compliance |
| 7 | Byte-strobe / `PPROT` verification |

Expected output:

```
 Results: 15 passed, 0 failed
ALL TESTS PASSED
```

## Synthesis Notes

- All APB outputs are registered; no combinational path from `req_*` to the bus.
- No latches; all state is held in `always @(posedge PCLK or negedge PRESETn)`.
- Synthesisable subset only — no `automatic` tasks or `integer` loop variables.

## License

Released under the MIT License — see [LICENSE](LICENSE).
