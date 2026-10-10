"""Signed distance helpers for sculpting the character meshes.

Every function takes points as an (N, 3) float array and returns (N,) distances
(negative inside). Shapes are combined with smooth unions so parts flow into
each other like clay instead of intersecting like primitives.
"""

import numpy as np
from skimage import measure


def length(v):
    return np.sqrt(np.sum(v * v, axis=-1))


def sphere(p, c, r):
    return length(p - np.asarray(c)) - r


def ellipsoid(p, c, radii):
    """Approximate ellipsoid distance (good enough near the surface)."""
    q = (p - np.asarray(c)) / np.asarray(radii)
    k0 = length(q)
    k1 = length(q / np.asarray(radii))
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


def capsule(p, a, b, ra, rb=None):
    """Round cone from a (radius ra) to b (radius rb)."""
    if rb is None:
        rb = ra
    a = np.asarray(a, dtype=float)
    b = np.asarray(b, dtype=float)
    pa = p - a
    ba = b - a
    h = np.clip(np.sum(pa * ba, axis=-1) / np.dot(ba, ba), 0.0, 1.0)
    r = ra + (rb - ra) * h
    return length(pa - ba * h[:, None]) - r


def segment_t(p, a, b):
    a = np.asarray(a, dtype=float)
    b = np.asarray(b, dtype=float)
    ba = b - a
    return np.clip(np.sum((p - a) * ba, axis=-1) / np.dot(ba, ba), 0.0, 1.0)


def round_box(p, c, half, r, rot=None):
    q = p - np.asarray(c)
    if rot is not None:
        q = q @ rot
    q = np.abs(q) - np.asarray(half)
    return length(np.maximum(q, 0.0)) + np.minimum(np.max(q, axis=-1), 0.0) - r


def torus(p, c, R, r, axis="y"):
    q = p - np.asarray(c)
    if axis == "y":
        a, h = q[:, [0, 2]], q[:, 1]
    elif axis == "x":
        a, h = q[:, [1, 2]], q[:, 0]
    else:
        a, h = q[:, [0, 1]], q[:, 2]
    return np.sqrt((length(a) - R) ** 2 + h * h) - r


def plane(p, n, d):
    n = np.asarray(n, dtype=float)
    n = n / np.linalg.norm(n)
    return p @ n - d


def smin(a, b, k):
    if k <= 0:
        return np.minimum(a, b)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * h - k * h * (1.0 - h)


def smax(a, b, k):
    return -smin(-a, -b, k)


def ssub(a, b, k):
    """a minus b, smoothly."""
    return smax(a, -b, k)


def rot_x(t):
    c, s = np.cos(t), np.sin(t)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def rot_y(t):
    c, s = np.cos(t), np.sin(t)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rot_z(t):
    c, s = np.cos(t), np.sin(t)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def euler_yxz(e):
    """Godot's default Euler order: R = Ry * Rx * Rz."""
    return rot_y(e[1]) @ rot_x(e[0]) @ rot_z(e[2])


def noise3(p, freq, seed=0):
    """Cheap smooth pseudo-noise from summed sines, in about [-1, 1]."""
    rng = np.random.default_rng(seed)
    out = np.zeros(len(p))
    for i in range(4):
        d = rng.normal(size=3)
        d /= np.linalg.norm(d)
        ph = rng.uniform(0, 6.283)
        f = freq * (1.0 + 0.7 * i)
        out += np.sin(p @ d * f + ph) / (1.0 + i)
    return out / 2.08


def polygonize(fn, lo, hi, step, target_tris=None, smooth_iters=0):
    """Marching cubes over the box [lo, hi], optionally decimated.

    Returns vertices (V, 3), faces (F, 3) with counter-clockwise winding seen
    from outside (Godot's front faces are clockwise, so callers flip on export).
    """
    lo = np.asarray(lo, dtype=float)
    hi = np.asarray(hi, dtype=float)
    n = np.ceil((hi - lo) / step).astype(int) + 1
    xs = lo[0] + np.arange(n[0]) * step
    ys = lo[1] + np.arange(n[1]) * step
    zs = lo[2] + np.arange(n[2]) * step
    grid = np.stack(np.meshgrid(xs, ys, zs, indexing="ij"), axis=-1).reshape(-1, 3)
    vals = np.empty(len(grid))
    chunk = 400000
    for i in range(0, len(grid), chunk):
        vals[i:i + chunk] = fn(grid[i:i + chunk])
    vol = vals.reshape(n[0], n[1], n[2])
    verts, faces, _, _ = measure.marching_cubes(vol, 0.0, spacing=(step, step, step))
    verts += lo
    if target_tris and len(faces) > target_tris:
        import pyfqmr
        s = pyfqmr.Simplify()
        s.setMesh(verts, faces)
        s.simplify_mesh(target_count=target_tris, aggressiveness=5, preserve_border=True, verbose=False)
        verts, faces, _ = s.getMesh()
    # Pull vertices back onto the true surface (decimation and the grid move them off it).
    start = verts.copy()
    for _ in range(2):
        d = fn(verts)
        g = gradient(fn, verts, step * 0.25)
        verts = verts - g * d[:, None]
    # Near creases the gradient can fling a vertex away; keep those where they were.
    flung = length(verts - start) > step * 2.0
    verts[flung] = start[flung]
    for _ in range(smooth_iters):
        verts = _laplacian(verts, faces, 0.5)
    return verts.astype(np.float64), faces.astype(np.int64)


def gradient(fn, p, eps):
    e = np.eye(3) * eps
    g = np.stack([fn(p + e[i]) - fn(p - e[i]) for i in range(3)], axis=-1)
    n = length(g)
    return g / np.maximum(n, 1e-12)[:, None]


def _laplacian(v, f, lam):
    acc = np.zeros_like(v)
    cnt = np.zeros(len(v))
    for a, b in ((0, 1), (1, 2), (2, 0)):
        np.add.at(acc, f[:, a], v[f[:, b]])
        np.add.at(cnt, f[:, a], 1)
    avg = acc / np.maximum(cnt, 1)[:, None]
    return v + (avg - v) * lam
