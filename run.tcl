set root_dir [pwd]
set simulator_dir [file join $root_dir "simulator"]
set simulation_dir [file join $root_dir "simulation"]
set source_dir [file join $root_dir "source"]
set waves_dir [file join $root_dir "waves"]
set uvm_dir [file join $root_dir "uvm"]

set uvm_files [glob -nocomplain -directory $uvm_dir *.sv]
set uvm_compile_file [file join $uvm_dir "uvm_compile.f"]
set source_files [glob -nocomplain -directory $source_dir *.sv]
set simulation_files [glob -nocomplain -directory $simulation_dir *.sv]

set RED "\033\[0;31m"
set GREEN "\033\[0;32m"
set YELLOW "\033\[0;33m"
set CYAN "\033\[0;36m"
set RESET "\033\[0m"

proc compile_files {simulator_dir source_files simulation_files} {
    cd $simulator_dir
    set all_files [concat $source_files $simulation_files]
    foreach file $all_files {
        puts "${::YELLOW} Compiling file $file ${::RESET}" 
        if {[catch {
            exec xvlog -nolog -sv $file
        } result]} {
            puts "${::RED} Compilation failed for file: $file. Error: $result${::RESET}"
            return 1
        }
    }
    return 0
}

proc compile_files_uvm {simulator_dir source_files simulation_files uvm_dir uvm_compile_file} {
    cd $simulator_dir 
    if {[catch {
        exec xvlog -nolog -sv -f $uvm_compile_file
    } result]} {
        puts "${::RED} Compilation failed for UVM. Error: $result${::RESET}"
        return 1
    }
    return 0
}

proc run_uvm {simulator_dir} {
    cd $simulator_dir
    if {[catch {
        if {[catch {
            exec xelab work.uvm_tb -s uvm_sim -nolog -debug all
        } result]} {
            puts "${::RED} Elaboration failed. Error: $result${::RESET}"
            return 1
        }
        set temp_compile_file [open "temp_run.tcl" "w"]
        puts $temp_compile_file "add_wave -r /*"
        puts $temp_compile_file "open_vcd uvm_sim.vcd"
        puts $temp_compile_file "log_vcd /*"
        puts $temp_compile_file "run all"
        puts $temp_compile_file "close_vcd"
        close $temp_compile_file
        if {[catch {
            exec xsim uvm_sim  -nolog -gui -tclbatch [file join $simulator_dir "temp_run.tcl"]
            file delete [file join $simulator_dir "temp_run.tcl"]
            foreach file [glob -nocomplain -directory $simulator_dir *.jou] {
                file delete $file
            }
            if {[catch {
                file rename -force [file join $simulator_dir "uvm_sim.vcd"] [file join $::waves_dir "uvm_sim.vcd"]
            } result]} {
                puts "${::RED} Failed to move VCD file. Error: $result${::RESET}"
                return 1

            }
        } result]} {
            puts "${::RED} Simulation failed. Error: $result${::RESET}"
            file delete [file join $simulator_dir "temp_run.tcl"]
            foreach file [glob -nocomplain -directory $simulator_dir *.jou] {
                file delete $file
            }
            return 1
        }
    } result]} {
        puts "${::RED} Simulation failed. Error: $result${::RESET}"
        return 1
    }
    return 0
}

proc run {simulator_dir module_name} {
    cd $simulator_dir
    if {[catch {
        if {[catch {
            exec xelab work.$module_name -s $module_name -nolog -debug all
        } result]} {
            puts "${::RED} Elaboration failed. Error: $result${::RESET}"
            return 1
        }
        set temp_compile_file [open "temp_run.tcl" "w"]
        puts $temp_compile_file "add_wave -r /*"
        puts $temp_compile_file "open_vcd ${module_name}.vcd"
        puts $temp_compile_file "log_vcd /*"
        puts $temp_compile_file "run all"
        puts $temp_compile_file "close_vcd"
        close $temp_compile_file
        if {[catch {
            exec xsim $module_name  -nolog -gui -tclbatch [file join $simulator_dir "temp_run.tcl"]
            file delete [file join $simulator_dir "temp_run.tcl"]
            foreach file [glob -nocomplain -directory $simulator_dir *.jou] {
                file delete $file
            }
            if {[catch {
                file rename -force [file join $simulator_dir "${module_name}.vcd"] [file join $::waves_dir "${module_name}.vcd"]
            } result]} {
                puts "${::RED} Failed to move VCD file. Error: $result${::RESET}"
                return 1

            }
        } result]} {
            puts "${::RED} Simulation failed. Error: $result${::RESET}"
            file delete [file join $simulator_dir "temp_run.tcl"]
            foreach file [glob -nocomplain -directory $simulator_dir *.jou] {
                file delete $file
            }
            return 1
        }
    } result]} {
        puts "${::RED} Simulation failed. Error: $result${::RESET}"
        return 1
    }
    return 0
}


if {![llength $argv]} {
    puts "${YELLOW} No arguments provided. Please specify the simulation mode as an argument.${RESET}"
    exit 1
}

if {![file isdirectory $simulator_dir]} {
    puts "${RED} Simulator directory does not exist. Please create it before running the script.${RESET}"
    exit 1
}

if {![file isdirectory $simulation_dir]} {
    puts "${RED} Simulation directory already exists. Please remove it before running the script.${RESET}"
    exit 1
}

if {![file isdirectory $source_dir]} {
    puts "${RED} Source directory does not exist. Please create it before running the script.${RESET}"
    exit 1
}

if {![file isdirectory $waves_dir]} {
    puts "${RED} Waves directory does not exist. Please create it before running the script.${RESET}"
    exit 1
}

set mode [lindex $argv 0]

if {$mode ni {compile run compile_run compile_uvm compile_run_uvm run_uvm}} {
    puts "${RED} Invalid simulation mode specified. Please choose from: compile, run, compile_run, compile_uvm, compile_run_uvm, run_uvm.${RESET}"
    exit 1
}


puts "${GREEN} Simulation mode: $mode${RESET}"
puts "${GREEN} Root directory: $root_dir${RESET}"
puts "${GREEN} Simulator directory: $simulator_dir${RESET}"
puts "${GREEN} Simulation directory: $simulation_dir${RESET}"
puts "${GREEN} Source directory: $source_dir${RESET}"
puts "${GREEN} Waves directory: $waves_dir${RESET}"
case $mode {
    "compile" {
        if {[catch {
            compile_files $simulator_dir $simulation_files $source_files
        } result]} {
            puts "${RED}Compile step failed$waves_dir${RESET}"
        }
    }
    "run" {
        puts -nonewline "${CYAN}Give Module Name:${RESET}"
        flush stdout
        gets stdin module_name
        puts "${CYAN}Running simulation for module: $module_name...${RESET}"
        if {[catch {
            run $simulator_dir $module_name
        } result]} {
            puts "${RED}Simulation failed for module: $module_name. Error: $result${RESET}"
        }
    }
    "compile_run" {
        if {[catch {
            compile_files $simulator_dir $simulation_files $source_files
        } result]} {
            puts "${RED}Compile step failed${RESET}"
            exit 1
        }
        puts -nonewline "${CYAN}Give Module Name:${RESET}"
        flush stdout
        gets stdin module_name
        puts "${CYAN}Running simulation for module: $module_name...${RESET}"
        if {[catch {
            run $simulator_dir $module_name
        } result]} {
            puts "${RED}Simulation failed for module: $module_name. Error: $result${RESET}"
        }
    }
    "compile_uvm" {
        if {[compile_files_uvm $simulator_dir $source_files $simulation_files $uvm_dir $uvm_compile_file]} {
            puts "${RED}UVM Compilation failed${RESET} "
        }
    }
    "compile_run_uvm" {
        if {[compile_files_uvm $simulator_dir $source_files $simulation_files $uvm_dir $uvm_compile_file]} {
            puts "${RED}UVM Compilation failed${RESET} "
            exit 1
        }
        if {[run_uvm $simulator_dir]} {
            puts "${RED}UVM Simulation failed${RESET}"
        }
    }
    "run_uvm" {
        if {[run_uvm $simulator_dir]} {
            puts "${RED}UVM Simulation failed${RESET}"
        }
    }
}
exit 0