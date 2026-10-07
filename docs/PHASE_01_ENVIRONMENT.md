# PHASE_01_ENVIRONMENT
## VLSI Development Environment Setup

### Operating System
* Ubuntu Linux (via GitHub Actions `ubuntu-latest` runner).

### Tools Installed
* **Icarus Verilog** (iverilog): Standard open-source RTL simulator.
* **Yosys**: Open-source synthesis suite.
* **GTKWave**: Waveform viewer.
* **Make**: Automation.

### Installation Commands (Ubuntu/Debian)
```bash
sudo apt-get update
sudo apt-get install -y iverilog yosys gtkwave make
```

### Verification Commands
```bash
make sim   # Runs iverilog and vvp
make synth # Runs yosys logic synthesis
```

### Known Issues
* None for basic RTL. Future scaling to SKY130 ASIC flow will require Docker and OpenLane images.

### Reproducibility
The CI pipeline in `.github/workflows/ci.yml` fully automates and reproduces this environment on every push.
