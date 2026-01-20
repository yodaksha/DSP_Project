# 16-Tap FIR Filter - Verilog Implementation

A high-performance, pipelined 16-tap Finite Impulse Response (FIR) digital filter implemented in Verilog with comprehensive testbench verification.

## Overview

This project implements a fully pipelined FIR filter optimized for FPGA deployment, featuring:
- **16 filter taps** with symmetric coefficients (linear phase response)
- **8-stage pipeline** for high throughput (one output per clock cycle)
- **Q1.15 fixed-point arithmetic** for efficient hardware implementation
- **Automatic saturation logic** to prevent overflow
- **Self-checking testbench** with golden reference model

## Architecture

### Pipeline Stages
1. **Input Register** - Input buffering and timing closure
2. **Shift Register** - 16-element delay line for sample history
3. **Parallel Multipliers** - 16 simultaneous MAC operations (Q1.15 × Q1.15 → Q2.30)
4. **Binary Tree Adder (4 stages)** - Logarithmic reduction for speed optimization
   - Stage 4: 16 → 8 sums (33-bit)
   - Stage 5: 8 → 4 sums (34-bit)
   - Stage 6: 4 → 2 sums (35-bit)
   - Stage 7: Final accumulation (36-bit Q6.30)
5. **Scaling & Saturation** - Q6.30 → Q1.15 conversion with overflow protection

### Filter Characteristics
- **Type:** Low-pass symmetric FIR
- **Coefficients:** Hardcoded for 0.5 DC gain
- **Latency:** 6 clock cycles
- **Throughput:** 1 sample/cycle (after initial latency)
- **Dynamic Range:** 16-bit signed input/output [-32768, 32767]

## Files

| File | Description |
|------|-------------|
| `module.v` | FIR filter RTL implementation (125 lines) |
| `testbench.v` | Self-checking testbench with reference model (125 lines) |
| `simulation` | Compiled simulation binary (generated) |
| `waveform.vcd` | Waveform dump file (optional, for GTKWave viewing) |

## Requirements

### Simulation
- **Icarus Verilog** (`iverilog`) - Open-source Verilog simulator
- **VVP** - Icarus Verilog runtime engine

### Installation (macOS)
```bash
brew install icarus-verilog
```

### Installation (Linux)
```bash
sudo apt-get install iverilog
```

## Usage

### Compile and Run Simulation
```bash
iverilog -o simulation testbench.v module.v
vvp simulation
```

### Expected Output
```
✅ OK @ 105000 | y=   256
✅ OK @ 115000 | y=   768
✅ OK @ 125000 | y=  1748
...
✅ OK @ 535000 | y=  7238
```
- **45 test cases** executed
- **100% pass rate** expected
- Tests include impulse response and random input patterns

### Generate Waveform (Optional)
Add to testbench:
```verilog
initial begin
    $dumpfile("waveform.vcd");
    $dumpvars(0, tb_fir_16tap);
end
```
View with GTKWave:
```bash
gtkwave waveform.vcd
```

## Design Details

### Fixed-Point Format
- **Q1.15 (Input/Output):** 1 sign bit, 15 fractional bits
  - Range: -1.0 to ~0.999
  - Resolution: 2⁻¹⁵ ≈ 0.000031
- **Q2.30 (Multiplier Output):** 2 sign bits, 30 fractional bits
- **Q6.30 (Accumulator):** 6 integer bits, 30 fractional bits (prevents overflow)

### Coefficient Values
```verilog
coeff[0..7]  = {512, 1024, 2048, 4096, 8192, 4096, 2048, 1024}
coeff[8..15] = {512, 256, 128, 64, 32, 16, 8, 4}
```
Peak at tap 4 (8192 = 0.25 in Q1.15), sum ≈ 0.5 for unity DC gain.

### Resource Estimates (Typical FPGA)
- **Flip-flops:** ~1200 (pipeline registers)
- **DSP Blocks:** 16 (multipliers)
- **LUTs:** ~800 (adder tree + control)
- **Max Frequency:** ~200-300 MHz (depends on device)

## Testbench Architecture

### Verification Strategy
1. **Golden Reference Model** - Software FIR implementation (combinational)
2. **Latency Alignment** - 6-cycle delay pipeline matches DUT timing
3. **Cycle-Accurate Comparison** - Every output checked against reference
4. **Automatic Pass/Fail** - Self-checking with visual feedback (✅/❌)

### Test Cases
- **Impulse Response Test** - Single pulse (0.5) verifies coefficients
- **Random Input Test** - 30 cycles of random values stress-test overflow/saturation

### Coverage
- ✅ Coefficient accuracy
- ✅ Pipeline functionality
- ✅ Saturation logic (overflow protection)
- ✅ Signed arithmetic edge cases
- ✅ Continuous data flow

## Design Trade-offs

| Aspect | Choice | Rationale |
|--------|--------|-----------|
| **Pipelining** | 8 stages | Higher clock speed vs latency |
| **Adder Tree** | Binary tree | O(log n) depth vs sequential O(n) |
| **Coefficients** | Hardcoded | Simplicity vs reconfigurability |
| **Fixed-Point** | Q1.15 | Hardware efficiency vs dynamic range |
| **Saturation** | Enabled | Graceful limiting vs wraparound distortion |

## Performance

- **Latency:** 6 clock cycles (60ns @ 100MHz)
- **Throughput:** 100 Msamples/sec @ 100MHz
- **Pipeline Efficiency:** 100% (one output per cycle after initial latency)

## Future Enhancements

- [ ] Parameterizable tap count
- [ ] Configurable coefficients (RAM/ROM)
- [ ] AXI-Stream interface for system integration
- [ ] Multi-rate filter (decimation/interpolation)
- [ ] Adaptive filter coefficients
- [ ] Power optimization (clock gating)

## License

MIT License - Free to use, modify, and distribute.

## Author

**Yodaksha**  
GitHub: [@yodaksha](https://github.com/yodaksha)

## References

- Digital Signal Processing (DSP) theory
- Fixed-point arithmetic in hardware
- FIR filter design and implementation
- Verilog RTL best practices
