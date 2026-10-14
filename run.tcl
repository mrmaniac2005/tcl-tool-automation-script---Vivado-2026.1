set root_dir [pwd]
set simulator_dir [file join $root_dir "simulator"]
set simulation_dir [file join $root_dir "simulation"]
set source_dir [file join $root_dir "source"]
set waves_dir [file join $root_dir "waves"]
set uvm_dir [file join $root_dir "uvm"]

set source_files [glob -nocomplain -directory $source_dir *.sv]
set simulation_files [glob -nocomplain -directory $simulation_dir *.sv]
set uvm_compile_file [file join $uvm_dir "uvm_compile.f"]

set RED "\033\[0;31m"
set GREEN "\033\[0;32m"
set YELLOW "\033\[0;33m"
set CYAN "\033\[0;36m"
set RESET "\033\[0m"

proc print_error {message} {
    puts "${::RED}${message}${::RESET}"
}

proc print_success {message} {
    puts "${::GREEN}${message}${::RESET}"
}

proc print_warning {message} {
    puts "${::YELLOW}${message}${::RESET}"
}

proc print_info {message} {
    puts "${::CYAN}${message}${::RESET}"
}

proc clean_simulator {} {
    set simulator_dir $::simulator_dir
    foreach pattern {*.jou *.log *.pb *.wdb *.vcd *.str temp_run.tcl} {
        foreach file [glob -nocomplain -directory $simulator_dir $pattern] {
            file delete -force $file
        }
    }
}

proc compile_files {simulator_dir source_files simulation_files} {
    cd $simulator_dir
    set all_files [concat $source_files $simulation_files]

    if {[llength $all_files] == 0} {
        print_error "No SystemVerilog source files found."
        return 1
    }

    print_info "Starting SystemVerilog compilation..."

    foreach file $all_files {
        puts "${::YELLOW}Compiling: $file${::RESET}"

        if {[catch {
            exec xvlog -nolog -sv $file
        } result]} {
            print_error "Compilation failed:"
            puts $result
            return 1
        }
    }

    print_success "SystemVerilog compilation completed successfully."
    return 0
}

proc compile_files_uvm {simulator_dir uvm_compile_file} {
    cd $simulator_dir

    if {![file exists $uvm_compile_file]} {
        print_error "UVM compile file not found: $uvm_compile_file"
        return 1
    }

    print_info "Starting UVM compilation..."
    print_info "Using file list: $uvm_compile_file"

    if {[catch {
        exec xvlog -nolog -sv -f $uvm_compile_file
    } result]} {
        print_error "UVM compilation failed:"
        puts $result
        return 1
    }

    print_success "UVM compilation completed successfully."
    return 0
}

proc elaborate_design {simulator_dir module_name} {
    cd $simulator_dir

    print_info "Elaborating module: $module_name"

    if {[catch {
        exec xelab work.$module_name -s $module_name -nolog -debug all
    } result]} {
        print_error "Elaboration failed for module: $module_name"
        puts $result
        return 1
    }

    print_success "Elaboration successful."
    return 0
}

proc run_simulation {simulator_dir module_name} {
    cd $simulator_dir

    set temp_script [file join $simulator_dir "temp_run.tcl"]
    set vcd_file [file join $simulator_dir "${module_name}.vcd"]
    set final_vcd [file join $::waves_dir "${module_name}.vcd"]

    set file_handle [open $temp_script "w"]
    puts $file_handle "add_wave -r /*"
    puts $file_handle "open_vcd ${module_name}.vcd"
    puts $file_handle "log_vcd /*"
    puts $file_handle "run all" 
    puts $file_handle "flush_vcd"
    puts $file_handle "close_vcd"
    close $file_handle

    print_info "Starting XSim simulation..."

    if {[catch {
        exec xsim $module_name -nolog -gui -tclbatch $temp_script
    } result]} {
        print_error "Simulation failed:"
        puts $result
        file delete -force $temp_script
        return 1
    }

    file delete -force $temp_script

    foreach file [glob -nocomplain -directory $simulator_dir *.jou] {
        file delete -force $file
    }

    if {![file exists $vcd_file]} {
        print_error "Simulation completed but VCD file was not generated:"
        puts $vcd_file
        return 1
    }

    if {[catch {
        file rename -force $vcd_file $final_vcd
    } result]} {
        print_error "Failed to move VCD file:"
        puts $result
        return 1
    }

    print_success "Simulation completed successfully."
    print_success "VCD saved to: $final_vcd"

    return 0
}

proc run {simulator_dir module_name} {
    if {[elaborate_design $simulator_dir $module_name]} {
        return 1
    }

    if {[run_simulation $simulator_dir $module_name]} {
        return 1
    }

    return 0
}

proc run_uvm {simulator_dir} {
    set module_name "uvm_tb"

    if {[elaborate_design $simulator_dir $module_name]} {
        return 1
    }

    if {[run_simulation $simulator_dir $module_name]} {
        return 1
    }

    return 0
}

if {![llength $argv]} {
    print_warning "No simulation mode specified."
    puts ""
    puts "Usage:"
    puts "  vivado -mode tcl -source simulate.tcl -tclargs <mode>"
    puts ""
    puts "Available modes:"
    puts "  compile"
    puts "  run"
    puts "  compile_run"
    puts "  compile_uvm"
    puts "  compile_run_uvm"
    puts "  run_uvm"
    exit 1
}

set mode [lindex $argv 0]

set valid_modes {
    compile
    run
    compile_run
    compile_uvm
    compile_run_uvm
    run_uvm
}

if {$mode ni $valid_modes} {
    print_error "Invalid simulation mode: $mode"
    puts ""
    puts "Valid modes:"
    puts "  compile"
    puts "  run"
    puts "  compile_run"
    puts "  compile_uvm"
    puts "  compile_run_uvm"
    puts "  run_uvm"
    exit 1
}

set required_directories {
    simulator_dir
    simulation_dir
    source_dir
    waves_dir
}

foreach directory_variable $required_directories {
    set directory [set $directory_variable]

    if {![file isdirectory $directory]} {
        print_error "Required directory does not exist:"
        puts $directory
        exit 1
    }
}

print_success "=========================================="
print_success " Vivado XSim Simulation Framework"
print_success "=========================================="

print_info "Simulation mode : $mode"
print_info "Root directory  : $root_dir"
print_info "Simulator       : $simulator_dir"
print_info "Source          : $source_dir"
print_info "Simulation      : $simulation_dir"
print_info "UVM             : $uvm_dir"
print_info "Waves           : $waves_dir"

puts ""

switch $mode {
    compile {
        if {[compile_files $simulator_dir $source_files $simulation_files]} {
            print_error "Compilation failed."
            exit 1
        }
    }

    run {
        puts -nonewline "${CYAN}Enter module name: ${RESET}"
        flush stdout
        gets stdin module_name

        if {$module_name eq ""} {
            print_error "Module name cannot be empty."
            exit 1
        }

        print_info "Running simulation for: $module_name"

        if {[run $simulator_dir $module_name]} {
            print_error "Simulation failed for module: $module_name"
            exit 1
        }
    }

    compile_run {
        if {[compile_files $simulator_dir $source_files $simulation_files]} {
            print_error "Compilation failed."
            exit 1
        }

        puts -nonewline "${CYAN}Enter module name: ${RESET}"
        flush stdout
        gets stdin module_name

        if {$module_name eq ""} {
            print_error "Module name cannot be empty."
            exit 1
        }

        print_info "Running simulation for: $module_name"

        if {[run $simulator_dir $module_name]} {
            print_error "Simulation failed for module: $module_name"
            exit 1
        }
    }

    compile_uvm {
        if {[compile_files_uvm $simulator_dir $uvm_compile_file]} {
            print_error "UVM compilation failed."
            exit 1
        }
    }

    compile_run_uvm {
        if {[compile_files_uvm $simulator_dir $uvm_compile_file]} {
            print_error "UVM compilation failed."
            exit 1
        }

        if {[run_uvm $simulator_dir]} {
            print_error "UVM simulation failed."
            exit 1
        }
    }

    run_uvm {
        if {[run_uvm $simulator_dir]} {
            print_error "UVM simulation failed."
            exit 1
        }
    }
}

puts ""
print_success "Simulation flow completed successfully."

exit 0
