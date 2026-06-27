# Wiener Filter in MARS MIPS, Asignment CA - HCMUT - 2025

Bare-metal MIPS Assembly implementation of a discrete-time FIR Wiener Filter running on the MARS 4.5 simulator. The system estimates a clean signal $d(n)$ from a noisy observation $x(n) = s(n) + w(n)$ by solving the optimal Wiener-Hopf equations entirely at the machine instruction level.

---

## Main Components

The codebase is structured into 6 core processing modules mapping directly to the mathematical pipeline:

1. **ASCII Parser & File I/O (`parse_buffer_to_floats`)**
   * Encapsulates syscalls via `macros.asm` to stream raw bytes from `desired.txt` and `input.txt`.
   * Manually converts ASCII strings (handling negative signs and decimal fractions) into IEEE 754 single-precision floats via Coprocessor 1 (`mtc1`, `cvt.s.w`).
   * Enforces a strict 10-sample array boundary check.

2. **Statistical Correlation Engine (`compute_rxx`, `compute_rdx`)**
   * **`compute_rxx`:** Calculates the biased auto-correlation vector $\hat{\gamma}_{xx}(k)$ of the input signal.
   * **`compute_rdx`:** Calculates the cross-correlation vector $\hat{\gamma}_{dx}(k)$ between the target and noisy input.

3. **Toeplitz Matrix Builder (`build_R`)**
   * Assembles the 10x10 Hermitian Toeplitz autocorrelation matrix $R_M$.
   * Maps 2D coordinate logic $R(i, j) = r_{xx}(|i-j|)$ into a flat, row-major 1D array (`Rxx`) in memory.

4. **Linear System Solver (`gauss_solve`)**
   * Solves the Wiener-Hopf matrix equation $R_M \cdot h = \gamma_d$.
   * Executes in-place **Gaussian Elimination** (forward elimination) followed by **Back-Substitution** to derive the optimal filter weights $h_{opt}$ without explicit matrix inversion.

5. **FIR Filter & MMSE Benchmark (`filter_signal`, `compute_mmse`)**
   * **`filter_signal`:** Convolves the input with $h_{opt}$ to generate the estimated output $y(n) = \sum h_k x(n-k)$.
   * **`compute_mmse`:** Evaluates the Minimum Mean Square Error: $\frac{1}{N} \sum (d[n] - y[n])^2$.

6. **Dual-Output Synchronizer (`write_output_file`)**
   * Contains a custom float-to-ASCII formatter (`append_float_4dp`).
   * Concatenates results into a unified memory buffer and pushes identical strings simultaneously to the MARS console and `output.txt`.

---

## File Structure

| File | Description |
| :--- | :--- |
| `BTL.asm` | Main entry point; orchestrates data memory layout, math procedures, and algorithms. |
| `macros.asm` | Wrapper macros (`open_file`, `read_file`, `close_file`) for MARS syscalls. |
| `input.txt` / `desired.txt` | 10-sample space/newline-separated input sequences. |
| `output.txt` | Exported runtime log containing filtered values and MMSE score. |

---

## Quickstart

1. Ensure `BTL.asm`, `macros.asm`, `input.txt`, and `desired.txt` sit in the **same folder** as `Mars4_5.jar`.
2. Open `BTL.asm` in the MARS IDE.
3. **Assemble** the program (**F3**).
4. **Run** execution (**F5**). 

*Benchmark Reference: When tested against the instructor's standard dataset, the MIPS solver achieves numerical parity with Python/NumPy, recording an MMSE of **0.048086844**.*

---

## Authors

* **Lê Quang Thành** (2252749) – Math Engine, Matrix & Gauss Solver
* **Trần Mãnh Tài** (2152950) – File I/O Macros & ASCII Parser
* **Nguyễn Anh Hào** (2052971) – FIR Convolution & MMSE Engine
* **Đoàn Thế Anh** (2252019) – Python Benchmarking & Documentation
