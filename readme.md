# `run.tcl` Detailed Guide

This document explains [`run.tcl`](./run.tcl) from the ground up. The script
automates compilation, elaboration, simulation, and waveform generation for
SystemVerilog and UVM designs using Xilinx Vivado's command-line tools.

The script is not a simulator by itself. It is a Tcl program that coordinates
Vivado programs:

| Vivado tool | Purpose |
| --- | --- |
| `xvlog` | Compiles SystemVerilog source files into the Vivado `work` library. |
| `xelab` | Elaborates the compiled design and creates a simulation executable. |
| `xsim` | Runs the elaborated simulation and records waveform data. |

## 1. How to invoke the script

Always run the command from the project root, not from inside `scripts/`:

```bash
vivado -mode tcl -nolog -nojournal -notrace \
  -tempDir ./trash/.Xil \
  -source ./scripts/run.tcl \
  -tclargs <mode>
```

For example:

```bash
vivado -mode tcl -nolog -nojournal -notrace \
  -tempDir ./trash/.Xil \
  -source ./scripts/run.tcl \
  -tclargs compile
```

### Meaning of the command

- `vivado` starts Vivado.
- `-mode tcl` starts Vivado's Tcl command mode. The script itself launches
  `xvlog`, `xelab`, and `xsim` through Tcl's `exec` command.
- `-nolog` prevents Vivado from writing its main log file.
- `-nojournal` prevents Vivado from writing its journal file.
- `-notrace` prevents Vivado from echoing each sourced Tcl command.
- `-tempDir ./trash/.Xil` places Vivado's temporary `.Xil` data under
  `trash/.Xil` instead of the default temporary location. Create the parent
  `trash/` directory first if Vivado does not create it automatically.
- `-source ./scripts/run.tcl` tells Vivado to execute this Tcl file.
- `-tclargs <mode>` passes the mode into the Tcl variable `argv`.
- `<mode>` must be one of the modes documented below.

The same command can be written on one line:

```bash
vivado -mode tcl -nolog -nojournal -notrace -tempDir ./trash/.Xil -source ./scripts/run.tcl -tclargs compile_run
```

### Important: use the exact mode name

The current [`run.tcl`](./run.tcl) accepts these mode names:

```text
compile
run
compile_run
compile_uvm
compile_run_uvm
run_uvm
```

`compile_ru` is **not** currently in that list. If the intended operation is
compile followed by a regular simulation, use `compile_run`:

```bash
vivado -mode tcl -nolog -nojournal -notrace -tempDir ./trash/.Xil -source ./scripts/run.tcl -tclargs compile_run
```

If `compile_ru` is meant to be a shorthand, the mode validation and `case`
statement in `run.tcl` would need to be changed to support that alias.

The script begins with:

```tcl
set root_dir [pwd]
```

`pwd` means "print working directory." Therefore, `root_dir` is the directory
where the command was launched. Every other project path is built relative to
this directory. If the script is launched from the wrong directory, it will
look for the required folders in the wrong place.

## 2. Required project layout

The expected layout is:

```text
project-root/
├── scripts/
│   ├── run.tcl
│   └── readme.md
├── source/
│   └── *.sv
├── simulation/
│   └── *.sv
├── simulator/
├── waves/
└── uvm/
    ├── *.sv
    └── uvm_compile.f
```

The directories have these responsibilities:

- `source/` contains regular design RTL and other design-side SystemVerilog
  files.
- `simulation/` contains regular testbench files and simulation-only
  SystemVerilog files.
- `simulator/` is the working directory for Vivado compilation, elaboration,
  simulation databases, and log files.
- `waves/` receives the final VCD waveform files.
- `uvm/` contains UVM-related files. The file `uvm_compile.f` is the Vivado
  file list used by UVM compilation.

The script collects regular source files with:

```tcl
set source_files [glob -nocomplain -directory $source_dir *.sv]
set simulation_files [glob -nocomplain -directory $simulation_dir *.sv]
```

`glob` finds matching files. `-nocomplain` prevents Tcl from throwing an error
when no files match. Only files ending in `.sv` directly inside those
directories are collected; nested directories are not searched.

## 3. Tcl syntax used in the script

Understanding a few Tcl rules makes the rest of the script easier to follow.

### Variables and command substitution

```tcl
set simulator_dir [file join $root_dir "simulator"]
```

- `set` creates or updates a variable.
- `$root_dir` reads the value of `root_dir`.
- Square brackets execute another Tcl command and insert its result.
- `file join` combines path components using the correct platform separator.

### Lists and arguments

Tcl commonly stores multiple values in a list. For example:

```tcl
set all_files [concat $source_files $simulation_files]
```

`concat` combines two lists into one. This combined list is then processed by:

```tcl
foreach file $all_files {
    ...
}
```

The loop assigns one filename at a time to `file`.

### Procedures

`proc` defines a reusable function:

```tcl
proc compile_files {simulator_dir source_files simulation_files} {
    ...
}
```

The values in braces are procedure parameters. A procedure can return a value
with `return`. In this script, `0` means success and `1` means failure.

### Error handling with `catch`

Vivado commands are run inside `catch` blocks:

```tcl
if {[catch {
    exec xvlog -nolog -sv $file
} result]} {
    ...
}
```

`exec` starts an external command. If the command fails, `catch` prevents Tcl
from terminating immediately, stores the error text in `result`, prints a
message, and allows the procedure to return failure.

## 4. Initial setup and validation

At startup, the script creates path variables for:

```text
root_dir       current working directory
simulator_dir  root_dir/simulator
simulation_dir root_dir/simulation
source_dir     root_dir/source
waves_dir      root_dir/waves
uvm_dir        root_dir/uvm
```

It also defines ANSI color codes:

- `RED` for errors
- `GREEN` for status messages
- `YELLOW` for warnings and compilation messages
- `CYAN` for prompts
- `RESET` to return terminal output to its normal color

Before selecting a mode, the script:

1. Requires at least one command-line argument.
2. Checks that `simulator/` exists.
3. Checks the state of `simulation/`.
4. Checks that `source/` exists.
5. Checks that `waves/` exists.
6. Verifies that the first argument is a supported mode.

The supported mode list is:

```text
compile
run
compile_run
compile_uvm
compile_run_uvm
run_uvm
```

The script's `simulation` directory check currently reports an error when
`simulation/` exists. This is the literal behavior of the current file, even
though the regular compile modes also search that directory for `.sv` files.
If a regular mode stops at this validation, inspect or correct that check in
`run.tcl` before running the mode.

## 5. Regular SystemVerilog compilation

The `compile` mode calls `compile_files`.

```tcl
compile_files $simulator_dir $simulation_files $source_files
```

The procedure changes into `simulator/`:

```tcl
cd $simulator_dir
```

It then combines the source and simulation file lists and runs this command
once for every file:

```bash
xvlog -nolog -sv path/to/file.sv
```

The options mean:

- `-nolog` avoids creating a separate Vivado log file for that invocation.
- `-sv` tells `xvlog` to parse the input as SystemVerilog.

Each file is announced in the terminal. If any compilation fails, the
filename and Vivado error output are printed, and the procedure returns `1`.
Successful compilation returns `0`.

Example:

```bash
vivado -mode tcl -nolog -nojournal -notrace -tempDir ./trash/.Xil -source ./scripts/run.tcl -tclargs compile
```

Compilation only creates or updates the Vivado simulation work library. It
does not elaborate or run a testbench.

## 6. Running a regular simulation

The `run` mode assumes that compilation has already completed. It prompts for
the top-level module name:

```text
Give Module Name:
```

If the entered name is `my_tb`, the script performs:

```bash
xelab work.my_tb -s my_tb -nolog -debug all
```

### Elaboration

`xelab` resolves module instances, parameters, signals, and library
references. The script expects the top-level module to be in the `work`
library, so the elaboration name is `work.<module_name>`.

The `-s my_tb` option gives the elaborated simulation a snapshot name. The
same name is then passed to `xsim`.

### Temporary simulation commands

After successful elaboration, the script creates
`simulator/temp_run.tcl` containing commands equivalent to:

```tcl
add_wave -r /*
open_vcd my_tb.vcd
log_vcd /*
run all
close_vcd
```

These commands:

1. Add all signals recursively to the waveform view.
2. Open a VCD file for writing.
3. Log all signals into the VCD.
4. Run the simulation until there are no more scheduled events.
5. Close the VCD file cleanly.

The temporary file is passed to:

```bash
xsim my_tb -nolog -gui -tclbatch simulator/temp_run.tcl
```

Although `-gui` is present, the outer Vivado invocation is in batch mode. The
temporary Tcl batch file is what controls the simulation and waveform
recording.

After `xsim` finishes, the script:

1. Deletes `simulator/temp_run.tcl`.
2. Deletes `.jou` files in `simulator/`.
3. Moves `simulator/my_tb.vcd` to `waves/my_tb.vcd`.

## 7. Compile and run together

The `compile_run` mode combines the regular compilation and run flows:

1. Compile `.sv` files from `source/` and `simulation/`.
2. Stop with an error if compilation fails.
3. Prompt for the top-level module name.
4. Elaborate that module.
5. Run it with `xsim`.
6. Move the generated VCD to `waves/`.

Example:

```bash
vivado -mode tcl -nolog -nojournal -notrace -tempDir ./trash/.Xil -source ./scripts/run.tcl -tclargs compile_run
```

This is usually the most convenient mode when the source files have changed
and a complete regular simulation is needed.

## 8. UVM compilation

The `compile_uvm` mode calls `compile_files_uvm`. The procedure changes into
`simulator/` and runs:

```bash
xvlog -nolog -sv -f uvm/uvm_compile.f
```

The `-f` option tells `xvlog` to read a file list. The file list determines
which UVM and testbench files are compiled and in what order. The procedure
does not individually compile the `source_files` or `simulation_files`
arguments; the contents of `uvm_compile.f` control this compilation.

Before using this mode, confirm that:

- `uvm/uvm_compile.f` exists.
- Every path listed in the file list is valid.
- The list includes the UVM package and the testbench files required by
  `uvm_tb`.

Example:

```bash
vivado -mode tcl -nolog -nojournal -notrace -tempDir ./trash/.Xil -source ./scripts/run.tcl -tclargs compile_uvm
```

## 9. Running the UVM simulation

The UVM run procedure is fixed to the top-level design `uvm_tb`. It elaborates:

```bash
xelab work.uvm_tb -s uvm_sim -nolog -debug all
```

It then creates a temporary batch file containing:

```tcl
add_wave -r /*
open_vcd uvm_sim.vcd
log_vcd /*
run all
close_vcd
```

The simulation command is:

```bash
xsim uvm_sim -nolog -gui -tclbatch simulator/temp_run.tcl
```

The final waveform is moved to:

```text
waves/uvm_sim.vcd
```

The `run_uvm` mode assumes that UVM compilation and elaboration prerequisites
already exist. The `compile_run_uvm` mode performs UVM compilation first and
then runs the UVM simulation automatically.

Examples:

```bash
vivado -mode tcl -nolog -nojournal -notrace -tempDir ./trash/.Xil -source ./scripts/run.tcl -tclargs compile_run_uvm
vivado -mode tcl -nolog -nojournal -notrace -tempDir ./trash/.Xil -source ./scripts/run.tcl -tclargs run_uvm
```

## 10. Complete mode comparison

| Mode | Compiles regular files | Compiles from UVM file list | Prompts for module | Elaborates | Runs simulation | Output |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `compile` | Yes | No | No | No | No | Vivado work library |
| `run` | No | No | Yes | Yes | Yes | `waves/<module>.vcd` |
| `compile_run` | Yes | No | Yes | Yes | Yes | `waves/<module>.vcd` |
| `compile_uvm` | No | Yes | No | No | No | Vivado work library |
| `compile_run_uvm` | No | Yes | No | Yes (`uvm_tb`) | Yes | `waves/uvm_sim.vcd` |
| `run_uvm` | No | No | No | Yes (`uvm_tb`) | Yes | `waves/uvm_sim.vcd` |

## 11. Error and cleanup behavior

The script reports failures at several stages:

- Missing mode argument
- Missing required directories
- Invalid mode name
- SystemVerilog compilation failure
- UVM compilation failure
- Elaboration failure
- Simulation failure
- VCD move failure

For regular and UVM simulations, the script attempts to remove
`temp_run.tcl` and `.jou` files after the simulation. If a failure occurs,
temporary files may still remain and can be removed manually after confirming
that no Vivado process is using them.

The script uses nested `catch` blocks so that Vivado's error output is printed
with a stage-specific message instead of terminating with only a raw Tcl
exception.

## 12. Troubleshooting

### "No arguments provided"

Pass a mode after `-tclargs`:

```bash
vivado -mode tcl -nolog -nojournal -notrace -tempDir ./trash/.Xil -source ./scripts/run.tcl -tclargs compile
```

### "Invalid simulation mode specified"

Use exactly one of the six supported names. Mode names are case-sensitive.

### A required directory does not exist

Run the command from the project root and verify the layout in this document:

```bash
pwd
ls
```

Create only the directories required by the project; an empty directory does
not provide source files or a valid testbench.

### `xvlog`, `xelab`, or `xsim` cannot be found

The Vivado environment has not been loaded into `PATH`. Start Vivado from a
terminal where the vendor setup script has been sourced, or use the project's
normal Vivado launch procedure.

### `xvlog` reports syntax or missing-module errors

Check the reported file first. Then verify that:

- The file is valid SystemVerilog.
- All dependencies are present in `source/`, `simulation/`, or the UVM file
  list.
- Compilation order in `uvm_compile.f` is correct for UVM.

### `xelab` cannot find `work.<module_name>`

The requested module was not compiled into the `work` library, or the entered
name does not exactly match the module declaration. Re-run the appropriate
compile mode and enter the top-level module name, not the filename.

For example, if `my_testbench.sv` contains:

```systemverilog
module tb_top;
```

enter `tb_top`, not `my_testbench`.

### No VCD file appears in `waves/`

Check the terminal output for an `xsim` error. Also verify that:

- The simulation reached `run all`.
- The simulation did not terminate before writing the VCD.
- `waves/` exists and is writable.
- The expected output name is used: `<module_name>.vcd` for regular runs or
  `uvm_sim.vcd` for UVM.

## 13. Recommended workflow

For a regular testbench:

```bash
# Compile and run in one command.
vivado -mode tcl -nolog -nojournal -notrace -tempDir ./trash/.Xil -source ./scripts/run.tcl -tclargs compile_run
```

For UVM:

```bash
# Compile UVM files and run the fixed uvm_tb top level.
vivado -mode tcl -nolog -nojournal -notrace -tempDir ./trash/.Xil -source ./scripts/run.tcl -tclargs compile_run_uvm
```

When debugging a failure, split the process into stages:

```bash
vivado -mode tcl -nolog -nojournal -notrace -tempDir ./trash/.Xil -source ./scripts/run.tcl -tclargs compile
vivado -mode tcl -nolog -nojournal -notrace -tempDir ./trash/.Xil -source ./scripts/run.tcl -tclargs run
```

This makes it clear whether the problem is in compilation, elaboration, or
simulation.
