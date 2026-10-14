// Master RTL file list. Block lists are included in compile order:
// common packages first, integration top last.
-f ${PROJ_ROOT}/rtl/common/common.f
-f ${PROJ_ROOT}/rtl/core/core.f
-f ${PROJ_ROOT}/rtl/coproc/coproc.f
-f ${PROJ_ROOT}/rtl/top/top.f
