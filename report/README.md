# Report Build Notes

## Files

- `main.typ`: Final report source.
- `assets/pynqriscv_diag_submission.png`: Vivado block-design figure.
- `assets/pynq_risc.png`: Custom architecture figure.
- `assets/worst_path.png`: Timing-path screenshot excerpt.
- `tum-templates-typst/`: TUM Typst template as a git submodule (`lufixSch/tum-templates-typst`).

## Compile (local)

From repo root:

```bash
git submodule update --init --recursive
typst compile report/main.typ report/report.pdf
```

No Typst package installation step is needed for the TUM template because it is used directly from the git submodule at `report/tum-templates-typst/`.

## Final checks before submission

1. Add the Vivado critical timing-path screenshot into the report.
2. Confirm utilization/timing values match your final implementation run.
3. Optionally add waveform/schematic screenshots for debugging evidence.

## Note

The report content is grounded in the repository sources, requirement PDF, and teammates' implementation/timing notes. Before submission, verify that the final numbers and screenshot correspond to the exact Vivado run you intend to submit.
