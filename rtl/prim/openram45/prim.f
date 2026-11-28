// Technology primitives on the OpenRAM macros of FreePDK45 (MEM_TECH=openram45): the same modules
// as rtl/prim/prim.f, one file per primitive, each from this directory when it maps to a macro and
// from rtl/prim/ otherwise. The macros themselves are not RTL: synthesis reads their Liberty and
// LEF, simulation their Verilog models (MEM_LIBS, MEM_LEFS, MEM_MODELS in syn/tech/tech.mk).
${PROJ_ROOT}/rtl/prim/openram45/prim_ram_1p.sv
