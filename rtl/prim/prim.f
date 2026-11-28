// Technology primitives: generic behavioral implementations, the default of RTL simulation
// (MEM_TECH=generic). A technology version keeps the same modules in rtl/prim/<tech>/prim.f, and the
// Makefile hands the list of MEM_TECH to the flows as PRIM_FLIST (rtl/rtl.f reads it).
${PROJ_ROOT}/rtl/prim/prim_ram_1p.sv
