# System Indicators Research - 2026-06-22

This note records the implementation direction for LiquidBar's CPU, GPU, RAM,
and thermal indicators.

## Sources Checked

- Apple HIG: [The menu bar](https://developer.apple.com/design/Human-Interface-Guidelines/the-menu-bar)
- Apple HIG: [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)
- Apple SwiftUI: [Gauge](https://developer.apple.com/documentation/swiftui/gauge)
- Apple Foundation: [ProcessInfo.ThermalState.serious](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum/serious)
- Apple Foundation: [ProcessInfo.ThermalState.critical](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum/critical)
- Apple performance guide: [Respond to thermal state changes](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/RespondToThermalStateChanges.html)
- Apple Metal: [GPU counters and counter sample buffers](https://developer.apple.com/documentation/metal/gpu-counters-and-counter-sample-buffers)
- Bjango: [Designing macOS menu bar extras](https://bjango.com/articles/designingmenubarextras/)
- Stats: [macOS menu bar system monitor](https://mac-stats.com/)
- Bjango iStat Menus: [Product page](https://bjango.com/mac/istatmenus/) and [hidden items / compact modes](https://bjango.com/help/istatmenus7/hiddenitems/)

## Design Conclusions

- Indicators must stay compact. LiquidBar is already a taskbar replacement, so
  system stats should be glanceable chips, not a second dashboard.
- A gauge-like visual model is appropriate for CPU and RAM because each value is
  a current level against a finite capacity.
- Text percentage, horizontal bar, and short history graph are the useful
  variants. They cover the common menu-bar monitor patterns without forcing a
  dense always-on chart.
- Users need presets because menu-bar space is scarce: `full`, `compact`, and
  `dense` support different space budgets.
- Thermal pressure should reduce LiquidBar's own work. Serious thermal state
  degrades graphs to bars. Critical thermal state degrades to percentage text
  and uses a slower refresh interval.
- GPU should be best-effort. Apple's public Metal counter APIs are designed for
  profiling work submitted by the app, not for a stable global system-wide GPU
  utilization number. LiquidBar should show an unavailable placeholder unless a
  robust public source is added later.

## Implementation Decisions

- CPU uses `host_statistics` with `HOST_CPU_LOAD_INFO` and computes deltas
  between samples.
- RAM uses `host_statistics64` with `HOST_VM_INFO64`, counting active, wired,
  and compressed pages against physical memory.
- Thermal uses `ProcessInfo.processInfo.thermalState`.
- Indicator history is bounded by config and further reduced under elevated
  thermal state.
- Rendering uses LiquidBar's native decoration pipeline instead of glyph bars or
  string-built sparklines, so geometry is stable and pixel-snapped with the rest
  of the bar.
- The settings UI exposes per-metric toggles and visual modes instead of a
  single hard-coded monitor style.
