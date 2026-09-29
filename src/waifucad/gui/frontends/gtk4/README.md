# GTK4 front-end

Status: ABI scaffold only.

Implement a native bridge returning `GuiFrontendV1`.  Keep toolkit headers and C/C++ ABI details inside this directory so BetterC kernel code never imports them.




The D side is a thin wrapper over the shared toolkit-neutral core in
`src/waifucad/gui/frontends/common/frontend.d`; behavioural fixes are made once there
and propagate to every front-end.
