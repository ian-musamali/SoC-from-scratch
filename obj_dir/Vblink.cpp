// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Model implementation (design independent parts)

#include "Vblink__pch.h"

//============================================================
// Constructors

Vblink::Vblink(VerilatedContext* _vcontextp__, const char* _vcname__)
    : VerilatedModel{*_vcontextp__}
    , vlSymsp{new Vblink__Syms(contextp(), _vcname__, this)}
    , clk{vlSymsp->TOP.clk}
    , led{vlSymsp->TOP.led}
    , rootp{&(vlSymsp->TOP)}
{
    // Register model with the context
    contextp()->addModel(this);
}

Vblink::Vblink(const char* _vcname__)
    : Vblink(Verilated::threadContextp(), _vcname__)
{
}

//============================================================
// Destructor

Vblink::~Vblink() {
    delete vlSymsp;
}

//============================================================
// Evaluation function

#ifdef VL_DEBUG
void Vblink___024root___eval_debug_assertions(Vblink___024root* vlSelf);
#endif  // VL_DEBUG
void Vblink___024root___eval_static(Vblink___024root* vlSelf);
void Vblink___024root___eval_initial(Vblink___024root* vlSelf);
void Vblink___024root___eval_settle(Vblink___024root* vlSelf);
void Vblink___024root___eval(Vblink___024root* vlSelf);

void Vblink::eval_step() {
    VL_DEBUG_IF(VL_DBG_MSGF("+++++TOP Evaluate Vblink::eval_step\n"); );
#ifdef VL_DEBUG
    // Debug assertions
    Vblink___024root___eval_debug_assertions(&(vlSymsp->TOP));
#endif  // VL_DEBUG
    vlSymsp->__Vm_deleter.deleteAll();
    if (VL_UNLIKELY(!vlSymsp->__Vm_didInit)) {
        vlSymsp->__Vm_didInit = true;
        VL_DEBUG_IF(VL_DBG_MSGF("+ Initial\n"););
        Vblink___024root___eval_static(&(vlSymsp->TOP));
        Vblink___024root___eval_initial(&(vlSymsp->TOP));
        Vblink___024root___eval_settle(&(vlSymsp->TOP));
    }
    VL_DEBUG_IF(VL_DBG_MSGF("+ Eval\n"););
    Vblink___024root___eval(&(vlSymsp->TOP));
    // Evaluate cleanup
    Verilated::endOfEval(vlSymsp->__Vm_evalMsgQp);
}

//============================================================
// Events and timing
bool Vblink::eventsPending() { return false; }

uint64_t Vblink::nextTimeSlot() {
    VL_FATAL_MT(__FILE__, __LINE__, "", "%Error: No delays in the design");
    return 0;
}

//============================================================
// Utilities

const char* Vblink::name() const {
    return vlSymsp->name();
}

//============================================================
// Invoke final blocks

void Vblink___024root___eval_final(Vblink___024root* vlSelf);

VL_ATTR_COLD void Vblink::final() {
    Vblink___024root___eval_final(&(vlSymsp->TOP));
}

//============================================================
// Implementations of abstract methods from VerilatedModel

const char* Vblink::hierName() const { return vlSymsp->name(); }
const char* Vblink::modelName() const { return "Vblink"; }
unsigned Vblink::threads() const { return 1; }
void Vblink::prepareClone() const { contextp()->prepareClone(); }
void Vblink::atClone() const {
    contextp()->threadPoolpOnClone();
}

//============================================================
// Trace configuration

VL_ATTR_COLD void Vblink::trace(VerilatedVcdC* tfp, int levels, int options) {
    vl_fatal(__FILE__, __LINE__, __FILE__,"'Vblink::trace()' called on model that was Verilated without --trace option");
}
