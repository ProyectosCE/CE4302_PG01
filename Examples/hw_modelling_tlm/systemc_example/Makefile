SYSTEMC_HOME ?= /usr/local/systemc-3.0.2
CXXFLAGS = -O2 -std=c++17 -I$(SYSTEMC_HOME)/include
LDFLAGS = -L$(SYSTEMC_HOME)/lib-linux64 -lsystemc -Wl,-rpath=$(SYSTEMC_HOME)/lib-linux64

# List all source files
SRCS = main.cpp producer.cpp consumer.cpp interconnect.cpp top.cpp
OBJS = $(SRCS:.cpp=.o)

all: run waves

sim: $(OBJS)
	g++ $(CXXFLAGS) -o sim $(OBJS) $(LDFLAGS)

%.o: %.cpp
	g++ $(CXXFLAGS) -c $< -o $@

run: sim
	./sim && vcd2fst sc_trace.vcd sc_trace.fst

clean:
	rm -f sim *.o *.vcd *.fst

waves: sc_trace.fst
	gtkwave sc_trace.fst &
.PHONY: all sim run waves clean