# Dell 1350cnw (network colour laser printer)

Carried over from the setup that worked under Omarchy (2026-08-28, printing verified).

## Specifics

- The printer only exposes the raw JetDirect socket (port 9100): no IPP, no driverless printing.
- It speaks **HBPL version 1**, not v2. The obvious driver (`foo2hbpl2`, PPD `Dell-1355`) makes every job fail
  with `PDL Error ... 016-720`. `foo2hbpl1` is needed (like the Dell 1250c / C1660w).
- The upstream wrapper (mikerr/foo2zjs fork) used `$SCREEN` without setting it, which breaks all colour printing:
  the fix (the `case "$RES"` block) is already in `foo2hbpl1-wrapper`.
- Local fix in `foo2hbpl1.c`: the loop over `papers[]` advanced by 1 instead of 3 and read past the array
  (`-Waggressive-loop-optimizations` warning, undefined behaviour). The result is unchanged for the listed sizes (A4...).
- `foo2zjs-pstops` comes from foo2zjs (Arch package `foo2zjs-nightly` 20201127); it is not packaged on Void.
- The PPD is foo2zjs's `Dell-1250c.ppd` with the model names rewritten to 1350cnw.
- The PPD calls the wrapper by its absolute path (`/usr/local/bin/foo2hbpl1-wrapper`): CUPS runs filters with a
  `PATH` that does not include `/usr/local/bin` (job fails with `foo2hbpl1-wrapper: command not found`).

## Installation

```
./drivers/dell-1350cnw/install.sh        # builds into /usr/local, installs the PPD (bootstrap.sh does it too)
sudo sv up cupsd                         # the service is enabled by bootstrap.sh
lpadmin -p Dell_1350cnw -E -v socket://PRINTER_HOST:9100 -m Dell-1350cnw.ppd.gz -o PageSize=A4 -o printer-is-shared=false
lpoptions -d Dell_1350cnw
```

The printer address is deliberately not in the repository (public). The printer gets its address by DHCP, so use
the host name the router publishes for it (`getent hosts <ip>` shows it, e.g. `dellXXXXXX.home`) rather than the IP:
the name follows the printer when its address changes.

## Pitfalls

- A paper size that does not match blocks the printer's internal queue, with no way to cancel: power it off and on.
  Always print in **A4**.
- Normal, harmless warnings: `193-700` (non-genuine toner, levels `???`) and `colord`/DBus
  `CreateProfile failed`.
- With no feedback channel, CUPS marks jobs as "completed" even when the printer rejected them. To diagnose: send a
  stream produced by the wrapper straight to port 9100, then read the event log (`/status/events.htm`) and the queue
  (`/job/queue.htm`) in the printer's web interface.
- A job stuck on "The printer may not exist or is unavailable" means the host is unreachable (printer off, or the
  address in the queue is stale): check with `getent hosts <name>` and `ping`.
