#include "Vblink.h"
#include "verilated.h"
#include <iostream>

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vblink *top = new Vblink;

    for (int i = 0; i < 20; i++) {
        top->clk = 0;
        top->eval();
        top->clk = 1;
        top->eval();
        std::cout << "Cycle: " << i << " led: " << (int)top->led << std::endl;
    }

    delete top;
    return 0;
}
  