// Project-wide packages (memory map, shared types). List each package after the ones it imports.
// soc_pkg needs vendor/axi.f first (axi_pkg) and includes axi/typedef.svh.
+incdir+${PROJ_ROOT}/vendor/axi/include
${PROJ_ROOT}/rtl/common/soc_pkg.sv
