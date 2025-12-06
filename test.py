import numpy as np
import matplotlib.pyplot as plt   # <--- NEW

# ---------- I/O helpers ----------

def read_signal(path):
    with open(path, "r") as f:
        tokens = f.read().strip().split()
    if not tokens:
        raise ValueError(f"{path} is empty")
    return np.array([float(t) for t in tokens], dtype=float)


def write_error(path, message):
    with open(path, "w") as f:
        f.write(message + "\n")


def write_result(path, output_signal, mmse_value,
                 sig_fmt="{:.4f}", mmse_fmt="{:.6f}"):
    with open(path, "w") as f:
        f.write(" ".join(sig_fmt.format(v) for v in output_signal) + "\n")
        f.write(mmse_fmt.format(mmse_value) + "\n")


# ---------- Correlation estimates ----------

def autocorrelation(x, max_lag):
    x = np.asarray(x, dtype=float)
    N = len(x)
    gamma = np.empty(max_lag + 1, dtype=float)
    for k in range(max_lag + 1):
        gamma[k] = np.dot(x[k:], x[:N - k]) / N
    return gamma


def cross_correlation(d, x, max_lag):
    d = np.asarray(d, dtype=float)
    x = np.asarray(x, dtype=float)
    if d.shape != x.shape:
        raise ValueError("d and x must have the same length")
    N = len(x)
    gamma = np.empty(max_lag + 1, dtype=float)
    for k in range(max_lag + 1):
        gamma[k] = np.dot(d[k:], x[:N - k]) / N
    return gamma


# ---------- Wiener filter design & application ----------

def wiener_filter_coeffs(x, d, M):
    x = np.asarray(x, dtype=float)
    d = np.asarray(d, dtype=float)

    if x.shape != d.shape:
        raise ValueError("Input and desired signals must have the same length")
    N = len(x)
    if M > N:
        raise ValueError("Filter length M cannot exceed signal length N")

    gamma_xx = autocorrelation(x, M - 1)
    gamma_dx = cross_correlation(d, x, M - 1)

    R = np.empty((M, M), dtype=float)
    for i in range(M):
        for j in range(M):
            R[i, j] = gamma_xx[abs(i - j)]

    h_opt = np.linalg.solve(R, gamma_dx)
    return h_opt


def apply_wiener_filter(x, h):
    x = np.asarray(x, dtype=float)
    h = np.asarray(h, dtype=float)

    N = len(x)
    M = len(h)
    y = np.zeros(N, dtype=float)

    for n in range(N):
        acc = 0.0
        for k in range(M):
            idx = n - k
            if idx >= 0:
                acc += h[k] * x[idx]
        y[n] = acc
    return y


def mmse(d, y):
    d = np.asarray(d, dtype=float)
    y = np.asarray(y, dtype=float)
    if d.shape != y.shape:
        raise ValueError("d and y must have the same length for MMSE")
    return np.mean((d - y) ** 2)


# ---------- Plotting ----------

def plot_results(d, y, h_opt, mmse_value):
    """
    Plot desired/unknown system output (d) and Wiener filter output (y)
    similar to the example figure in the assignment.
    """
    N = len(d)
    n = np.arange(N)

    plt.figure(figsize=(12, 4))

    # Blue dashed: desired / unknown system output
    plt.plot(n, d, 'b--', label='Output of unknown system')

    # Red solid: Wiener filter output
    plt.plot(n, y, 'r-', linewidth=1.5, label='Output of Wiener filter')

    # Title with estimated parameters & MMSE
    coeff_str = np.array2string(h_opt, precision=5, separator=' ')
    plt.title(f"Estimated system parameters: {coeff_str}, "
              f"min MSE = {mmse_value:.5f}")

    plt.xlabel("Time samples")
    plt.ylabel("Amplitude")
    plt.grid(True, alpha=0.3)
    plt.legend(loc='upper right')
    plt.tight_layout()
    plt.show()


# ---------- Main script ----------

def main():
    desired_path = "desired.txt"
    input_path = "input.txt"
    output_path = "output.txt"

    try:
        d = read_signal(desired_path)
        x = read_signal(input_path)
    except Exception as e:
        print(f"File error: {e}")
        return

    if len(d) != len(x):
        msg = "Error: size not match"
        print(msg)
        write_error(output_path, msg)
        return

    N = len(x)
    M = N

    h_opt = wiener_filter_coeffs(x, d, M)
    y = apply_wiener_filter(x, h_opt)
    mmse_value = mmse(d, y)

    print(" ".join(f"{v:.4f}" for v in y))
    print(f"{mmse_value:.6f}")
    write_result(output_path, y, mmse_value)

    # --- NEW: show plot ---
    plot_results(d, y, h_opt, mmse_value)


if __name__ == "__main__":
    main()
