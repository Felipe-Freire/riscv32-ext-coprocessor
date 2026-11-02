// Master RTL file list. Block lists are included in compile order:
// packages first, then primitives, then the blocks, SoC top last.
// Vendor IP file lists go first: the blocks wrap them and the packages in common/ use their macros.
-f ${PROJ_ROOT}/vendor/common_cells.f
-f ${PROJ_ROOT}/vendor/axi.f
-f ${PROJ_ROOT}/rtl/common/common.f
-f ${PROJ_ROOT}/rtl/prim/prim.f
-f ${PROJ_ROOT}/rtl/core/core.f
-f ${PROJ_ROOT}/rtl/coproc/coproc.f
-f ${PROJ_ROOT}/rtl/dma/dma.f
-f ${PROJ_ROOT}/rtl/bus/bus.f
-f ${PROJ_ROOT}/rtl/mem/mem.f
-f ${PROJ_ROOT}/rtl/periph/periph.f
-f ${PROJ_ROOT}/rtl/top/top.f
