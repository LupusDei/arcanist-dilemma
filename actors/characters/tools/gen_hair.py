"""Grooms the hair styles out of locks.

Each style is a thin cap on the skull, cut at the hairline, plus locks: tapered
ribbons that start on the scalp and grow along a flow direction, hugging the
head (or lifting away for spiky tips) and falling under gravity once they leave
it. Locks fuse only slightly, so the creases between them read like stylized
hair. The mesh's uv.x is the position along the lock (0 root, 1 tip) and uv.y
a per-lock random number, for the shader's root shading and lock variation.

Sculpted at w = 1 (the round face); the game scales x by the head's cranium width.
"""

import numpy as np

import sdf
from gen_heads import BASE_R, CRANIUM_C, CRANIUM_R, HeadParams, head_sdf
from meshio import Surface

R = BASE_R
CC = CRANIUM_C * R
CR = CRANIUM_R * R
_REF = HeadParams("boy", "round", 1)


def obstacle(p):
    """What hair rests on: the head and neck, and the shoulders and back below."""
    d = head_sdf(_REF, p, with_lids=False)
    torso = sdf.ellipsoid(p, (0, -2.95 * R, 0.0), (1.6 * R, 1.55 * R, 0.88 * R))
    return sdf.smin(d, torso, 0.3 * R)


def obstacle_grad(p):
    return sdf.gradient(obstacle, p, R * 0.01)


def scalp_dir(az, el):
    """Direction from the skull centre: az 0 is the back (+z), pi the front, +pi/2 the right (+x)."""
    return np.array([np.sin(az) * np.cos(el), np.sin(el), np.cos(az) * np.cos(el)])


def scalp_point(az, el, lift=0.0):
    d = scalp_dir(az, el)
    s = 1.0 / np.sqrt(np.sum((d / CR) ** 2))
    return CC + d * (s + lift * R)


class Lock:
    def __init__(self, pts, radii, normals, seed):
        self.pts = np.asarray(pts)
        self.radii = np.asarray(radii)
        self.normals = np.asarray(normals)
        self.seed = seed
        pad = self.radii.max() * 2.2
        self.lo = self.pts.min(axis=0) - pad
        self.hi = self.pts.max(axis=0) + pad


def grow(root, flow, length, width, lift=(0.02, 0.02), hug=1.0, gravity=0.0, curl=0.0, steps=10, seed=0, taper=0.85, face_stop=0.4, back=0.0):
    """A lock from root (a point on the scalp) growing along flow.

    Growth stops where the lock would fall over the eyes (in front of the face,
    below face_stop * r)."""
    p = np.asarray(root, float)
    tangent = np.asarray(flow, float)
    tangent /= np.linalg.norm(tangent)
    step = length * R / steps
    pts, radii, normals = [p.copy()], [width * R], []
    for i in range(1, steps + 1):
        t = i / steps
        n = obstacle_grad(p[None])[0]
        g = gravity * min(1.0, t * 1.6)
        # Gravity takes over as the lock grows; curl turns it around the surface normal.
        tangent = tangent * (1 - g) + np.array([0, -1.0, 0]) * g
        if back and p[1] < -0.8 * R:
            # Drape behind the shoulders instead of pooling on them.
            tangent = tangent + np.array([0, 0, back])
        if curl:
            tangent = tangent + np.cross(n, tangent) * curl / steps
        tangent -= n * np.dot(tangent, n) * hug * (1 - g)
        tangent /= np.linalg.norm(tangent)
        q = p + tangent * step
        target = (lift[0] + (lift[1] - lift[0]) * t) * R
        rad = width * R * (1 - taper * t ** 1.6)
        for _ in range(3):
            d = obstacle(q[None])[0]
            nn = obstacle_grad(q[None])[0]
            want = target + rad * 0.55
            if d < want:
                q = q + nn * (want - d)
            elif hug > 0 and g < 0.5:
                q = q - nn * (d - want) * hug * (1 - 2 * g)
        if q[2] < -0.3 * R and q[1] < face_stop * R and abs(q[0]) < 0.78 * R:
            break
        p = q
        pts.append(p.copy())
        radii.append(rad)
        normals.append(obstacle_grad(p[None])[0])
    if len(pts) < 3:
        return None
    # Taper whatever length the lock reached down to a point.
    k = len(pts) - 1
    radii = [width * R * (1 - taper * (i / k) ** 1.6) for i in range(k + 1)]
    normals.insert(0, normals[0])
    return Lock(pts, radii, normals, seed)


def locks_sdf(locks, q, k=0.025, want_t=False):
    d = np.full(len(q), 1e3)
    tt = np.zeros(len(q))
    sid = np.zeros(len(q))
    for lk in locks:
        m = np.all((q > lk.lo) & (q < lk.hi), axis=1)
        if not m.any():
            continue
        qm = q[m]
        dl = np.full(len(qm), 1e3)
        tl = np.zeros(len(qm))
        n_seg = len(lk.pts) - 1
        for i in range(n_seg):
            a, b = lk.pts[i], lk.pts[i + 1]
            ba = b - a
            h = np.clip(np.sum((qm - a) * ba, axis=-1) / max(np.dot(ba, ba), 1e-12), 0, 1)
            perp = qm - a - ba * h[:, None]
            nrm = (lk.normals[i] + lk.normals[i + 1])
            nrm /= np.linalg.norm(nrm)
            pn = perp @ nrm
            rad = lk.radii[i] + (lk.radii[i + 1] - lk.radii[i]) * h
            # Flattened against the head, with fine strand ridges across the lock's width.
            bin_ = np.cross(nrm, ba / np.linalg.norm(ba))
            lat = perp @ bin_
            ridge = 0.05 * rad * np.cos(lat / np.maximum(rad, 1e-6) * np.pi * 2.2)
            ds = np.sqrt(np.sum(perp * perp, axis=-1) + (1.7 ** 2 - 1) * pn * pn) - rad + ridge
            closer = ds < dl
            tl = np.where(closer, (i + h) / n_seg, tl)
            dl = sdf.smin(dl, ds, 0.2 * min(lk.radii[i], lk.radii[i + 1]) + 1e-5)
        old = d[m]
        if want_t:
            tt[m] = np.where(dl < old, tl, tt[m])
            sid[m] = np.where(dl < old, lk.seed, sid[m])
        d[m] = sdf.smin(old, dl, k * R)
    if want_t:
        return d, tt, sid
    return d


# ---------------------------------------------------------------- hairline and cap

def _hairline_el(az, front=0.48, temple=0.3, sideburn=-0.1, nape=-0.55):
    """Elevation (sin) of the hairline around the head by azimuth (radians, |az| from the back)."""
    a = np.abs(az)
    xs = [0.0, 1.15, 1.45, 1.75, 2.15, np.pi]
    ys = [nape, nape * 0.4, 0.2, sideburn, temple, front]
    return np.interp(a, xs, ys)


def cap_sdf(q, thick, **hairline):
    rel = q - CC
    cap = sdf.ellipsoid(q, CC, CR + thick * R)
    az = np.arctan2(rel[:, 0], rel[:, 2])
    el = rel[:, 1] / np.maximum(sdf.length(rel / (CR / CR[1])), 1e-6)
    cut = (_hairline_el(az, **hairline) - el) * R
    return sdf.smax(cap, cut, 0.03 * R)


# ---------------------------------------------------------------- styles

def _rng(seed):
    return np.random.default_rng(seed)


def scalp_roots(n, margin=0.12, seed=0):
    """Roots spread evenly over the scalp inside the hairline (a Fibonacci sphere)."""
    rng = _rng(seed)
    out = []
    golden = np.pi * (3 - np.sqrt(5))
    for i in range(n):
        y = 1 - 2 * (i + 0.5) / n
        az = (i * golden) % (2 * np.pi) - np.pi
        el = np.arcsin(y)
        if np.sin(el) < _hairline_el(az) + margin:
            continue
        az += rng.normal(0, 0.04)
        el += rng.normal(0, 0.04)
        out.append((az, el, scalp_point(az, el, 0.01)))
    return out


def _tangent(root, toward):
    d = toward - root
    n = obstacle_grad(root[None])[0]
    return d - n * np.dot(d, n)


def _keep(locks):
    return [lk for lk in locks if lk is not None]


def style_short():
    """Neat and side-swept: everything flows from a crown at the back-left, the front lifts a little."""
    rng = _rng(1)
    crown = scalp_point(-0.5, 1.2)
    locks = []
    for az, el, root in scalp_roots(170, 0.1, 1):
        flow = _tangent(root, root + (root - crown))
        front = np.clip((-root[2] / R - 0.2) / 0.6, 0, 1)
        flow = flow / np.linalg.norm(flow) + np.array([0.9, 0.25, 0]) * front
        length = 0.55 + 0.25 * front + rng.normal(0, 0.05)
        locks.append(grow(root, flow, length, 0.2, lift=(0.015, 0.02 + 0.07 * front), seed=rng.random(), taper=0.8, face_stop=0.5))
    return 0.05, {"front": 0.5}, _keep(locks)


def style_tousled():
    """The concept boy's: windswept chunks lifting at the tips, a fringe that stops above the brows."""
    rng = _rng(2)
    crown = scalp_point(0.4, 1.25)
    locks = []
    for az, el, root in scalp_roots(160, 0.08, 2):
        flow = _tangent(root, root + (root - crown))
        flow = flow / np.linalg.norm(flow) + rng.normal(0, 0.35, 3)
        front = np.clip((-root[2] / R - 0.2) / 0.6, 0, 1)
        flow += np.array([0.25, -0.5, -0.3]) * front
        length = rng.uniform(0.7, 1.0)
        locks.append(grow(root, flow, length, 0.22, lift=(0.02, rng.uniform(0.07, 0.17)), hug=0.6, seed=rng.random(), taper=0.92, face_stop=0.42))
    return 0.06, {"front": 0.42}, _keep(locks)


def style_long():
    """Long and loose from a side part, falling past the shoulders and framing the face."""
    rng = _rng(3)
    part_x = 0.28 * R
    locks = []
    for az, el, root in scalp_roots(190, 0.06, 3):
        side = 1.0 if root[0] > part_x else -1.0
        away = np.array([side, 0, 0]) * 0.8 + np.array([0, -0.6, 0])
        flow = _tangent(root, root + away * R)
        if np.linalg.norm(flow) < 1e-6:
            flow = np.array([side, -1.0, 0])
        back = np.clip((root[2] / R + 0.3), 0, 1)
        length = 2.5 + 0.45 * back + rng.normal(0, 0.15)
        framing = root[2] < -0.35 * R
        if framing:
            length = min(length, 2.2)
        locks.append(grow(root, flow, length, 0.24, lift=(0.0, 0.05), hug=1.0, gravity=0.6, curl=rng.normal(0, 0.15), steps=14, seed=rng.random(), taper=0.6, face_stop=0.42, back=0.0 if framing else 0.45))
    # An under layer for volume at the back.
    for i in range(10):
        az = -1.2 + i * 0.27
        root = scalp_point(az, 0.25, 0.02)
        locks.append(grow(root, (np.sin(az) * 0.3, -1, 0.25), 2.7 + rng.normal(0, 0.1), 0.28, lift=(0.08, 0.1), gravity=0.75, steps=12, seed=rng.random(), taper=0.5))
    return 0.035, {"front": 0.5, "sideburn": 0.05}, _keep(locks)


def _gathered(seed, target, n=170, width=0.17):
    """Hair combed smoothly toward a point (a braid's nape or a bun's crown)."""
    rng = _rng(seed)
    locks = []
    for az, el, root in scalp_roots(n, 0.05, seed):
        flow = _tangent(root, target)
        dist = np.linalg.norm(target - root) / R
        locks.append(grow(root, flow, dist * 1.1 + 0.2, width, lift=(0.0, 0.01), hug=1.0, seed=rng.random(), taper=0.35, steps=12))
    return _keep(locks)


def _braid_chain(start, end_ctrl, end, count, r0, r1):
    """A three-strand braid along a quadratic curve: lobes alternating side to side."""
    parts = []
    for i in range(count):
        t = (i + 0.5) / count
        p = (1 - t) ** 2 * start + 2 * (1 - t) * t * end_ctrl + t * t * end
        dp = 2 * (1 - t) * (end_ctrl - start) + 2 * t * (end - end_ctrl)
        dp /= np.linalg.norm(dp)
        side = np.cross(dp, np.array([0, 0, 1.0]))
        side /= max(np.linalg.norm(side), 1e-6)
        rad = r0 + (r1 - r0) * t
        sgn = 1 if i % 2 == 0 else -1
        a = p + side * rad * 0.55 * sgn - dp * rad * 0.7
        b = p - side * rad * 0.35 * sgn + dp * rad * 0.8
        parts.append((a, b, rad))
    return parts


def style_braid():
    rng = _rng(4)
    nape = np.array([0.15, -0.5, 0.92]) * R
    locks = _gathered(4, nape)
    # A loose strand framing each side of the face.
    for side in (-1, 1):
        root = scalp_point(side * 2.3, 0.4, 0.02)
        locks.append(grow(root, (side * 0.1, -1, -0.15), 1.3, 0.12, lift=(0.02, 0.03), gravity=0.6, seed=rng.random(), taper=0.85))
    # Over the right shoulder, between the neck and the arm, and down the front.
    braid = _braid_chain(nape, np.array([0.95, -1.35, 0.35]) * R, np.array([0.72, -3.1, -0.95]) * R, 11, 0.3 * R, 0.17 * R)
    return 0.05, {"front": 0.5, "sideburn": 0.12}, _keep(locks), braid


def style_topknot():
    top = np.array([0.0, 1.02, 0.2]) * R
    locks = _gathered(5, top, width=0.16)
    bun = []
    for k in range(4):
        y = 1.05 + k * 0.14
        rr = 0.3 - k * 0.055
        bun.append((np.array([0, y, 0.2]) * R, rr * R, 0.13 * R * (1 - k * 0.12)))
    return 0.05, {"front": 0.52, "sideburn": 0.1}, locks, bun


def hair_sdf_fn(style):
    braid = bun = None
    out = {"short": style_short, "tousled": style_tousled, "long": style_long, "braid": style_braid, "topknot": style_topknot}[style]()
    if style == "braid":
        thick, hl, locks, braid = out
    elif style == "topknot":
        thick, hl, locks, bun = out
    else:
        thick, hl, locks = out

    def fn(q, want_t=False):
        cap = cap_sdf(q, thick, **hl)
        res = locks_sdf(locks, q, want_t=want_t)
        d, tt, sid = res if want_t else (res, None, None)
        d = sdf.smin(cap, d, 0.03 * R)
        if braid:
            for a, b, rad in braid:
                d = sdf.smin(d, sdf.capsule(q, a, b, rad * 0.75, rad * 0.75), 0.015 * R)
            last = braid[-1][1]
            tie = sdf.capsule(q, last, last + np.array([0.02, -0.12, -0.03]) * R, 0.09 * R, 0.08 * R)
            d = np.minimum(d, tie)
            d = sdf.smin(d, sdf.capsule(q, last + np.array([0.02, -0.1, -0.03]) * R, last + np.array([0.06, -0.55, -0.1]) * R, 0.13 * R, 0.02 * R), 0.02 * R)
        if bun:
            for c, rr, tube in bun:
                d = sdf.smin(d, sdf.torus(q, c, rr, tube), 0.03 * R)
            d = sdf.smin(d, sdf.sphere(q, np.array([0, 1.42, 0.2]) * R, 0.2 * R), 0.06 * R)
        if want_t:
            return d, tt, sid
        return d

    return fn


def hair_mesh(style):
    if style == "shaved":
        fn = lambda q: cap_sdf(q, 0.025, front=0.42, nape=-0.7)
        lo, hi = (-1.2 * R, -1.0 * R, -1.25 * R), (1.2 * R, 1.3 * R, 1.3 * R)
        v, f = sdf.polygonize(fn, lo, hi, R * 0.02, target_tris=5000)
        n = sdf.gradient(fn, v, R * 0.01)
        uv = np.stack([np.full(len(v), 0.3), np.zeros(len(v))], -1)
        return Surface("hair", "hair_shaved", v, n, f, uv=uv)
    fn = hair_sdf_fn(style)
    long = style in ("long", "braid")
    lo = (-1.5 * R, (-3.7 if long else -1.2) * R, (-1.4 if long else -1.3) * R)
    hi = ((1.6 if long else 1.3) * R, (1.6 if style == "topknot" else 1.4) * R, 1.4 * R)
    v, f = sdf.polygonize(fn, lo, hi, R * 0.018, target_tris=14000 if long else 10000)
    n = sdf.gradient(fn, v, R * 0.008)
    _, tt, sid = fn(v, want_t=True)
    # Braid, bun and tie aren't locks: give them mid-length shading.
    loose = (tt == 0) & (sid == 0)
    tt[loose] = 0.6
    sid[loose] = 0.5
    return Surface("hair", "hair", v, n, f, uv=np.stack([tt, sid], -1))
