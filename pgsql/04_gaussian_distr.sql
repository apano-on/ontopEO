CREATE OR REPLACE FUNCTION ontop_openeo.create_gaussian_kernel(window_size TEXT, std_dev TEXT)
RETURNS TEXT AS $$
import numpy as np

# Convert inputs
window_size_int = int(window_size)
std_dev_double = float(std_dev)
mid = (window_size_int - 1) / 2

# Create 1D Gaussian
g = np.exp(-((np.arange(window_size_int) - mid) ** 2) / (2 * std_dev_double ** 2))
g /= g.sum()  # Normalize

# Create 2D Gaussian kernel
kernel = np.outer(g, g)
kernel /= kernel.sum()  # Normalize

# Convert to formatted text
result = "[\n" + ",\n".join(
    ["  [" + ", ".join(f"{val:.6f}" for val in row) + "]" for row in kernel]
) + "\n]"

return result
$$ LANGUAGE plpython3u;
