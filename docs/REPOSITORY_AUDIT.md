# Phase 01 Repository Audit

## Snapshot

Audited checkout: `main` at `c7725fa` (`Add regression script for SEAL-RV verification`), cloned from `https://github.com/shrutikbalwan/SEAL-RV`. The checkout was clean before Phase 01 work. The repository contains one counter, three CPU RTL files, two CPU testbenches, one counter testbench, one small hex program, a Cocotb test module, a shell regression script, a Cocotb make fragment, a counter-only Yosys Tcl script, a root Makefile, CI, and four phase documents. No Wishbone, memory, PMP, firewall, crypto, AI, DMA, ECC, interrupt, peripheral, or physical-design RTL is present.

## Existing implementation

- `counter`: parameterized up-counter with enable and active-low asynchronous reset.
- `alu`: 32-bit add/sub selected by a 4-bit control; all other controls return zero.
- `regfile`: 32 x 32-bit array, asynchronous two-read behavior, synchronous write, x0 reads zero and ignores writes. No reset or initialization for x1–x31; the physical array cell for x0 is also not initialized because reads are bypassed to zero.
- `cpu_core`: minimal combinational decode around ALU/regfile. Known legal ADD/SUB/ADDI encodings produce those operations, but decoder does not check every funct3/funct7 field, so other encodings with R/I opcodes may alias to add/sub behavior rather than trap. PC uses active-low asynchronous reset to zero and increments by four every clock. No memory data port, branch/jump, trap, CSR, compressed fetch, or bus.
- `hw/tb/cpu_tb.sv` loads `hw/tb/test_prog.hex`; `verification/tb/cpu_tb.sv` drives a separate inline program and checks arithmetic/x0 behavior. These benches duplicate the module name and overlap without being identical; compiling both creates a duplicate module.
- `verification/tests/test_cpu.py` originally held three tests, including an expected-failure branch test. Its reset check sampled PC after a rising edge despite PC having advanced, and its arithmetic test swallowed missing hierarchical access.

## Actual baseline runs (before infrastructure edits)

Commands were run from the repository root in the available Windows environment:

| Command | Observed result |
|---|---|
| `make sim` | Could not start: GNU Make is not installed/on PATH in this environment. |
| `iverilog -g2012 -o counter_sim hw/rtl/counter.sv hw/tb/counter_tb.sv; vvp counter_sim` | Pass; printed `Test passed! Count = 10`. |
| `iverilog -g2012 -o cpu_tb_sim hw/tb/cpu_tb.sv hw/rtl/cpu/alu.sv hw/rtl/cpu/regfile.sv hw/rtl/cpu/cpu_core.sv; vvp cpu_tb_sim` | Pass; printed `Test passed! x3 = 15`; `$readmemh` warned the file has fewer than 256 words. |
| `iverilog -g2012 -s cpu_tb -o verification_cpu_sim verification/tb/cpu_tb.sv hw/rtl/cpu/alu.sv hw/rtl/cpu/regfile.sv hw/rtl/cpu/cpu_core.sv; vvp verification_cpu_sim` | Fail, exit 1: VCD path `verification/waves/cpu.vcd` did not exist relative to the repository root. |
| `yosys -c scripts/synth_counter.tcl` | Could not execute in the original shell environment; the bundled Yosys runtime libraries were not on `PATH`. With the suite `bin` and `lib` directories on `PATH`, the revised synthesis script completed successfully (see post-edit results). |
| `verilator --lint-only --Wall --top-module cpu_core ...` | The wrapper did not complete in the original shell environment. Calling the bundled `verilator_bin.exe` directly with `VERILATOR_ROOT` set completed successfully (see post-edit results). |

The original root `sim` target tested only the counter. Original CI did not run either CPU testbench or Cocotb, did not lint, and did not synthesize the CPU. The original regression shell script lacked `set -e`, so failures could be followed by later commands and an apparent successful script exit. The original Yosys flow synthesized only the counter. The old Phase 03 document reported 11 tests with 2 passes and 9 failures, but checked-in sources contained only three Cocotb tests and no reproducible record for the additional cases; those counts are withdrawn as unsupported claims.

## Duplicate/conflicting files and build issues

- The two CPU benches retain the same module name and must be compiled separately. The root build compiles and runs both as separate simulations, and CI invokes that root target.
- The Cocotb make fragment formerly built source paths relative to caller `PWD`; it now resolves them relative to its own location and sets simulation time unit/precision.
- The CPU testbench VCD path did not match the directory created by the old shell script. It now writes below `build/`.
- Testbenches used `$error`, which Icarus printed while still returning success from simulation. Failure checks now use `$fatal(1,...)`. The x0 check now verifies architectural zero reads after an attempted write, rather than expecting the unreset physical register array cell to be initialized.
- The root targets and CI now include counter/CPU simulation, Cocotb, Verilator lint, and counter/CPU Yosys synthesis smoke tests. The regression script uses `set -euo pipefail`. Verilator `-Wno-fatal` keeps lint warnings visible while errors still fail; it is not a claim of warning-free lint.

## Modified Phase 01 files

Added the eight architecture/specification documents plus this audit. Reworked the root Makefile, CI workflow, Cocotb make fragment/tests, regression shell script, and Yosys script. Updated the counter and CPU testbenches to make failure status reliable. CPU and counter RTL were not modified. Build outputs are under ignored `build/`.

## Post-edit evidence

Commands run after the infrastructure/testbench edits (from the repository root):

Tool versions reported by the local binaries: Icarus Verilog 14.0 development build, Cocotb 2.1.0, Yosys 0.69+154, and Verilator 5.053 development build. These are local versions; the GitHub Actions Ubuntu packages are not version-pinned.

| Command | Result |
|---|---|
| `iverilog -g2012 -Wall -s counter_tb -o build/counter_tb hw/rtl/counter.sv hw/tb/counter_tb.sv` then `vvp build/counter_tb` | Pass; count was 10. Icarus reports missing explicit timescale on RTL modules. |
| `iverilog -g2012 -Wall -s cpu_tb -o build/cpu_tb hw/rtl/cpu/alu.sv hw/rtl/cpu/regfile.sv hw/rtl/cpu/cpu_core.sv verification/tb/cpu_tb.sv` then `vvp build/cpu_tb` | Pass; x3=15 and x0 write/read behavior passed. Icarus reports missing explicit timescale on RTL modules. |
| `iverilog -g2012 -Wall -s cpu_tb -o build/cpu_hex_tb hw/rtl/cpu/alu.sv hw/rtl/cpu/regfile.sv hw/rtl/cpu/cpu_core.sv hw/tb/cpu_tb.sv` then `vvp build/cpu_hex_tb` | Pass; x3=15. Icarus reports missing explicit timescale and a `$readmemh` short-file warning. |
| Cocotb Icarus runner with 1 ns/1 ps precision, followed by `python -m cocotb_tools.check_results build/cocotb/results.xml` | Pass; 2 tests passed, 0 failed. |
| Temporary `$fatal(1,...)` simulator probe (`iverilog` then `vvp`) | Expected simulator exit status 1 observed, confirming fatal testbench failures propagate through Icarus. Temporary probe was not retained. |
| `make sim` / `make test-cocotb` / `make lint` / `make synth` | GNU Make is unavailable in the Windows shell, so the make targets themselves could not be invoked locally. Their underlying simulation, Cocotb, lint, and synthesis commands were run directly as recorded here. A WSL tool probe found GNU Make, but subsequent WSL invocations were denied by `Wsl/Service/E_ACCESSDENIED`. |
| Yosys with suite runtime path set, `yosys -s scripts/synth.ys` | Pass, exit 0. Both counter and CPU were synthesized; Yosys `check` reported 0 problems for each. Outputs: `build/counter_synth.v` and `build/cpu_core_synth.v`. |
| Verilator 5.053 `--lint-only --Wall -Wno-fatal` on counter and CPU, with `VERILATOR_ROOT` pointing to the bundled `share/verilator` directory | Pass, exit 0. Counter produced no warnings. CPU produced two visible warnings: empty connection for ALU `zero`, and unused `instr[14:12]`. No warning-free lint claim is made. |
| `python -c "import yaml; d=yaml.safe_load(open('.github/workflows/ci.yml', encoding='utf-8')); assert 'jobs' in d and 'build_and_test' in d['jobs']; print('CI YAML parsed; build_and_test has', len(d['jobs']['build_and_test']['steps']), 'steps')"` | Pass; YAML parsed and contains seven workflow steps. |
| `git diff --check` | Pass; no whitespace errors. Git printed line-ending conversion notices for files under the repository's Windows configuration. |

These results cover only the counter and small arithmetic subset. They do not establish ISA compliance or future SoC features. The revised GitHub Actions workflow has not been run here; no remote workflow result is claimed. GNU Make target orchestration remains unexecuted locally because Make is unavailable, although each target's underlying tool invocation passed.

The exact successful Windows commands for Yosys and Verilator were:

```powershell
$suiteRoot = 'C:\Users\shrut\AppData\Local\Programs\oss-cad-suite'
$env:PATH = "$suiteRoot\bin;$suiteRoot\lib;$env:PATH"
& "$suiteRoot\bin\yosys.exe" -s scripts/synth.ys

$env:VERILATOR_ROOT = "$suiteRoot\share\verilator"
& "$suiteRoot\bin\verilator_bin.exe" --lint-only --Wall -Wno-fatal --top-module counter hw/rtl/counter.sv
& "$suiteRoot\bin\verilator_bin.exe" --lint-only --Wall -Wno-fatal --top-module cpu_core hw/rtl/cpu/alu.sv hw/rtl/cpu/regfile.sv hw/rtl/cpu/cpu_core.sv
```

The exact Cocotb runner command used for the passing result was:

```sh
python -c "from pathlib import Path; from cocotb_tools.runner import get_runner; root=Path.cwd(); runner=get_runner('icarus'); runner.build(sources=[root/'hw/rtl/cpu/alu.sv',root/'hw/rtl/cpu/regfile.sv',root/'hw/rtl/cpu/cpu_core.sv'],hdl_toplevel='cpu_core',build_dir=root/'build/cocotb',always=True,timescale=('1ns','1ps')); runner.test(hdl_toplevel='cpu_core',test_module='test_cpu',test_dir=root/'verification/tests',build_dir=root/'build/cocotb',timescale=('1ns','1ps'),results_xml=str(root/'build/cocotb/results.xml'))"
python -m cocotb_tools.check_results build/cocotb/results.xml
```
