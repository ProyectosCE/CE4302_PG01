# SystemC and SystemVerilog Simple HW Modelling Tutorial using TLM

## 1. Introduction: Transaction-Level Modelling (TLM)
This tutorial provides a reference for modelling a **Routed Interconnect** at the transaction level. At this abstraction, the focus is on data flow and routing logic rather than individual clock cycles or bit-level transitions. 

* **SystemC Implementation:** Utilizes the TLM-1.0 standard with `tlm_fifo` acting as the synchronization channel between blocking ports.
* **SystemVerilog Implementation:** Implements a modular OOP environment where blocking **Mailboxes** serve as the transactional transport layer.

* **This simple model does not provide explicit arbitration handling in the Interconnect**
---

## 2. System Architecture: Initiator-Target Pattern
The topology follows a classic TLM pattern where **Initiators** (Producers) start transactions and **Targets** (Consumers) complete them, with an Interconnect acting as a **Router**.

~~~mermaid
graph LR
    subgraph Initiator_Layer
        P0[Producer 0]
        P1[Producer 1]
    end

    subgraph Channel_Layer
        F0((FIFO 0))
        F1((FIFO 1))
    end

    subgraph Interconnect_Logic
        IC{Interconnect\nRouter}
    end

    subgraph Output_Layer
        OF0((FIFO 0))
        OF1((FIFO 1))
    end

    subgraph Target_Layer
        C0[Consumer 0]
        C1[Consumer 1]
    end

    P0 -- "put()" --> F0
    P1 -- "put()" --> F1
    F0 -- "get()" --> IC
    F1 -- "get()" --> IC
    IC -- "put()" --> OF0
    IC -- "put()" --> OF1
    OF0 -- "get()" --> C0
    OF1 -- "get()" --> C1

    style IC fill:#f96,stroke:#333,stroke-width:2px
    style F0 fill:#e1f5fe
    style F1 fill:#e1f5fe
~~~

---

## 3. Required Tool Installation (Linux)

### 3.1. Install Prerequisites
Essential libraries for compiling SystemC and building Verilator from source.
~~~bash
sudo apt-get update
sudo apt-get install -y build-essential wget tar autoconf flex bison \
                       libfl-dev libgoogle-perftools-dev zlib1g zlib1g-dev \
                       python3 help2man git gtkwave
~~~

### 3.2. Install SystemC 3.0.2 (IEEE 1666-2023)
~~~bash
wget https://github.com/accellera-official/systemc/archive/refs/tags/3.0.2.tar.gz -O systemc-3.0.2.tar.gz
tar -xzf systemc-3.0.2.tar.gz
cd systemc-3.0.2
mkdir -p objdir && cd objdir
../configure --prefix=/usr/local/systemc-3.0.2
make -j$(nproc)
sudo make install
cd ../..
rm -rf systemc-3.0.2 systemc-3.0.2.tar.gz
~~~

### 3.3. Install Verilator (Latest from Source)
~~~bash
git clone https://github.com/verilator/verilator
cd verilator
autoconf
./configure
make -j$(nproc)
sudo make install
verilator --version
cd ..
~~~

---

## 4. SystemC Implementation (Transactional Model)

The SystemC model leverages `sc_port` to bind modules to shared `tlm_fifo` channels.

### 4.1. TLM Port Mapping
The Producer acts as a `tlm_put_initiator` while the Interconnect acts as a `tlm_get_target` on its input side and an initiator on its output side.

~~~mermaid
classDiagram
    class Producer {
        +sc_port~tlm_put_if~ out_port
    }
    class Consumer {
        +sc_port~tlm_get_if~ in_port
    }
    class Interconnect {
        +sc_port~tlm_get_if~ in[2]
        +tlm_fifo~Packet~ out[2]
    }
    class tlm_fifo {
        <<channel>>
    }

    Producer --> tlm_fifo : Port Binding
    tlm_fifo <-- Interconnect : Port Binding
    Interconnect --> Consumer : Internal FIFO to Port
~~~

### 4.2. Makefile
~~~makefile
SYSTEMC_HOME ?= /usr/local/systemc-3.0.2
CXXFLAGS = -O2 -std=c++17 -I$(SYSTEMC_HOME)/include
LDFLAGS = -L$(SYSTEMC_HOME)/lib-linux64 -lsystemc -Wl,-rpath=$(SYSTEMC_HOME)/lib-linux64

SRCS = main.cpp producer.cpp consumer.cpp interconnect.cpp top.cpp
OBJS = $(SRCS:.cpp=.o)

all: run

sim: $(OBJS)
	g++ $(CXXFLAGS) -o sim $(OBJS) $(LDFLAGS)

%.o: %.cpp
	g++ $(CXXFLAGS) -c $< -o $@

run: sim
	./sim && vcd2fst sc_trace.vcd sc_trace.fst

clean:
	rm -f sim *.o *.vcd *.fst
~~~

---

## 5. SystemVerilog Implementation

The SV model uses a Class-Based verification approach where the **Environment** handles the transactional wiring of components.

### 5.1. File Hierarchy and Data Flow
The `model_pkg` encapsulates the data objects and component classes, while the `top` module connects them to a physical interface for tracing.

~~~mermaid
flowchart TD
    subgraph Model_Package
        P[producer.sv]
        C[consumer.sv]
        I[interconnect.sv]
        PKT[packet.sv]
    end

    subgraph Transactors
        MBX_IN[(Input Mailbox)]
        MBX_OUT[(Output Mailbox)]
    end

    P -- "put()" --> MBX_IN
    MBX_IN -- "get()" --> I
    I -- "put()" --> MBX_OUT
    MBX_OUT -- "get()" --> C

    I -. "trace" .-> INTF[component_interface.sv]
~~~

### 5.2. Makefile
~~~makefile
SRC_FILES = system_params_pkg.sv model_pkg.sv top.sv
all: run waves

sim: top.sv
    verilator --binary --trace-structs --trace-max-array 128 --trace-fst --timing $(SRC_FILES) --top-module top
run: sim
    ./obj_dir/Vtop
waves:
    gtkwave -f waves.fst &
clean:
    rm -rf obj_dir *.fst

.PHONY: all run sim waves clean
~~~

---

## 6. References
1. **IEEE Computer Society.** (2024). *IEEE Std 1666-2023 (SystemC)*.
2. **IEEE Computer Society.** (2024). *IEEE Std 1800-2023 (SystemVerilog)*.
3. **Veripool.** (2024). *Verilator 5.x User Guide*.