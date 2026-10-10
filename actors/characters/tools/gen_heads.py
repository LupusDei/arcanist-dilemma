"""Sculpts the heads, eyes, brows and lashes, and the beards.

Head space: origin at the Head joint (centre of the skull), +Y up, faces -Z,
metres. Everything is laid out in units of r, the head radius the meshes are
sculpted at (CharacterMeshes.BASE_HEAD_R); the game scales by head_r / r.
"""

import numpy as np

import sdf
from meshio import Surface

BASE_R = 0.155

# Face presets: face width, jaw width, face length, cheek fullness, chin size and jaw squareness.
FACES = {
    "round": dict(w=1.0, jaw=1.0, length=0.95, cheek=1.18, chin=1.0, square=0.0),
    "oval": dict(w=0.93, jaw=0.88, length=1.06, cheek=0.92, chin=0.95, square=0.0),
    "heart": dict(w=0.99, jaw=0.76, length=1.0, cheek=1.0, chin=0.72, square=0.0),
    "square": dict(w=1.0, jaw=1.1, length=1.0, cheek=0.88, chin=1.25, square=1.0),
}

# Cranium: the skull ellipsoid that the hair is groomed on (in units of r, before width).
CRANIUM_C = np.array([0.0, 0.1, 0.05])
CRANIUM_R = np.array([0.86, 0.95, 1.0])


class HeadParams:
    def __init__(self, body="boy", face="round", age=1, r=BASE_R):
        self.body = body
        self.face = face
        self.age = age
        self.r = r
        f = dict(FACES[face])
        girl = body == "girl"
        child = age <= 0
        if girl:
            f["w"] *= 0.97
            f["jaw"] *= 0.9
            f["chin"] *= 0.82
            f["square"] *= 0.45
        if child:
            f["length"] *= 0.9
            f["cheek"] *= 1.12
            f["jaw"] *= 0.92
            f["chin"] *= 0.85
        self.f = f
        self.girl = girl
        self.child = child
        # Big eyes, the concept art's signature.
        self.eye_r = r * 0.2 * (1.12 if child else 1.0) * (1.05 if girl else 1.0)
        ex = r * 0.37 * f["w"]
        ey = -r * 0.03
        ez = -r * 0.69
        self.eyes = [np.array([-ex, ey, ez]), np.array([ex, ey, ez])]
        self.nose = (0.82 if girl else 1.0) * (0.75 if child else 1.0)
        self.mouth_y = -0.5 * r * f["length"] * (0.95 if child else 1.0)
        self.brow = 0.75 if girl else 1.0

    def cranium(self):
        return CRANIUM_C * self.r, CRANIUM_R * self.r * np.array([self.f["w"], 1.0, 1.0])


def head_sdf(P, p, with_lids=True):
    r = P.r
    f = P.f
    w = f["w"]
    L = f["length"]
    cc, cr = P.cranium()
    d = sdf.ellipsoid(p, cc, cr)
    # The face: a broad mask, cheeks, a jaw line down to the chin.
    face = sdf.ellipsoid(p, (0, -0.3 * r * L, -0.3 * r), (0.74 * r * w * f["jaw"], 0.68 * r * L, 0.66 * r))
    d = sdf.smin(d, face, 0.16 * r)
    jx = 0.6 * r * w * f["jaw"]
    cx = 0.17 * r * f["chin"]
    jaw_r = (0.15 + 0.05 * f["square"]) * r
    for sx in (-1, 1):
        d = sdf.smin(d, sdf.capsule(p, (sx * jx, -0.4 * r * L, 0.1 * r), (sx * cx, -0.86 * r * L, -0.52 * r), jaw_r, 0.12 * r), 0.14 * r)
        d = sdf.smin(d, sdf.sphere(p, (sx * 0.43 * r * w, -0.24 * r, -0.5 * r), 0.27 * r * f["cheek"]), 0.16 * r)
        # Cheekbones.
        d = sdf.smin(d, sdf.ellipsoid(p, (sx * 0.5 * r * w, -0.06 * r, -0.52 * r), (0.2 * r, 0.11 * r, 0.18 * r)), 0.1 * r)
    d = sdf.smin(d, sdf.sphere(p, (0, -0.9 * r * L, -0.55 * r), 0.15 * r * f["chin"]), 0.12 * r)
    if f["square"] > 0:
        for sx in (-1, 1):
            d = sdf.smin(d, sdf.sphere(p, (sx * 0.52 * r * w, -0.58 * r * L, -0.1 * r), 0.2 * r * f["square"]), 0.12 * r)
    # Brow ridge over the eyes.
    by = P.eyes[0][1] + 0.3 * r
    br = 0.075 * r * (0.85 if P.girl else 1.0)
    for sx in (-1, 1):
        d = sdf.smin(d, sdf.capsule(p, (sx * 0.62 * r * w, by - 0.02 * r, -0.66 * r), (sx * 0.08 * r, by, -0.84 * r), br * 0.7, br), 0.1 * r)
    # Eye sockets, so the eyeballs sit in the face.
    for c in P.eyes:
        d = sdf.ssub(d, sdf.sphere(p, c, P.eye_r + 0.012 * r), 0.05 * r)
    # Nose: bridge, a rounded tip, wings and nostrils.
    n = P.nose
    tip = np.array([0, -0.21 * r, -0.98 * r - 0.05 * r * n])
    d = sdf.smin(d, sdf.capsule(p, (0, 0.06 * r, -0.86 * r), tip + np.array([0, 0.02 * r, 0.02 * r]), 0.045 * r * n, 0.06 * r * n), 0.06 * r)
    d = sdf.smin(d, sdf.sphere(p, tip, 0.075 * r * n), 0.05 * r)
    for sx in (-1, 1):
        d = sdf.smin(d, sdf.sphere(p, (sx * 0.075 * r * n, -0.25 * r, -0.92 * r - 0.02 * r * n), 0.055 * r * n), 0.04 * r)
        d = sdf.ssub(d, sdf.sphere(p, (sx * 0.04 * r * n, -0.29 * r, -0.97 * r - 0.03 * r * n), 0.022 * r * n), 0.012 * r)
    # Lips, the line of the mouth curving up at the corners, and the groove under the lower lip.
    my = P.mouth_y
    lip = 1.15 if P.girl else 1.0
    mw = 0.17 * r * (0.92 if P.girl else 1.0)
    d = sdf.smin(d, sdf.ellipsoid(p, (0, my + 0.04 * r, -0.92 * r), (mw, 0.045 * r * lip, 0.065 * r)), 0.04 * r)
    d = sdf.smin(d, sdf.ellipsoid(p, (0, my - 0.045 * r, -0.9 * r), (mw * 0.85, 0.052 * r * lip, 0.065 * r)), 0.04 * r)
    d = sdf.ssub(d, sdf.ellipsoid(p, (0, my, -1.0 * r), (mw * 1.02, 0.009 * r, 0.11 * r)), 0.008 * r)
    for sx in (-1, 1):
        d = sdf.ssub(d, sdf.sphere(p, (sx * mw * 1.0, my + 0.028 * r, -0.9 * r), 0.022 * r), 0.012 * r)
    d = sdf.ssub(d, sdf.capsule(p, (-0.09 * r, my - 0.13 * r, -0.97 * r), (0.09 * r, my - 0.13 * r, -0.97 * r), 0.025 * r), 0.04 * r)
    # Ears.
    for sx in (-1, 1):
        ear_c = np.array([sx * 0.86 * r * w, -0.1 * r, 0.1 * r])
        ear = sdf.ellipsoid(p, ear_c, (0.08 * r, 0.24 * r, 0.16 * r))
        ear = sdf.ssub(ear, sdf.ellipsoid(p, ear_c + np.array([sx * 0.065 * r, 0.01 * r, -0.02 * r]), (0.05 * r, 0.16 * r, 0.1 * r)), 0.02 * r)
        d = sdf.smin(d, ear, 0.05 * r)
    # Neck down into the collar.
    nr = 0.3 * r * (0.88 if P.girl else 1.0)
    d = sdf.smin(d, sdf.capsule(p, (0, -0.45 * r, 0.12 * r), (0, -1.7 * r, 0.2 * r), nr, nr * 1.15), 0.14 * r)
    if with_lids:
        d = sdf.smin(d, lids_sdf(P, p), 0.015 * r)
    return d


def lids_sdf(P, p):
    """Upper and lower eyelids: shells over the eyeball, cut to leave the eye open."""
    r = P.r
    out = np.full(len(p), 1e3)
    for i, c in enumerate(P.eyes):
        sx = -1 if i == 0 else 1
        shell = sdf.sphere(p, c, P.eye_r + 0.03 * r)
        q = p - c
        e = P.eye_r
        # The upper lid rests on the top of the iris and drops a little toward the outer corner.
        up_y = 0.52 * e - 0.1 * np.clip(sx * q[:, 0] / e, -1, 1) * e
        upper = sdf.smax(shell, up_y - q[:, 1], 0.01 * r)
        lower = sdf.smax(shell, q[:, 1] + 0.72 * e, 0.01 * r)
        front = q[:, 2] + 0.05 * e
        out = np.minimum(out, sdf.smax(np.minimum(upper, lower), front, 0.01 * r))
    return out


def head_mesh(P):
    r = P.r
    fn = lambda q: head_sdf(P, q)
    lo = (-1.15 * r, -1.75 * r, -1.25 * r)
    hi = (1.15 * r, 1.2 * r, 1.2 * r)
    v, f = sdf.polygonize(fn, lo, hi, r * 0.016, target_tris=12000)
    nrm = sdf.gradient(fn, v, r * 0.01)
    # uv carries head-space x,y and uv2.y the depth for the face paint (lips, blush).
    uv = v[:, :2] / r
    uv2 = np.stack([np.zeros(len(v)), v[:, 2] / r], axis=-1)
    return Surface("head", "skin", v, nrm, f, uv=uv, uv2=uv2)


def eye_meshes(P):
    """UV spheres; uv is (angle from forward, angle around) so the shader paints the iris."""
    surfaces = []
    for c in P.eyes:
        v, n, f, uv = _uv_sphere(P.eye_r, 32, 20)
        surfaces.append(Surface("eye", "eye", v + c, n, f, uv=uv))
    return _merge(surfaces, "eyes", "eye")


def _uv_sphere(r, seg, rings):
    verts, uvs = [], []
    for j in range(rings + 1):
        th = np.pi * j / rings  # 0 at front (-Z) to pi at back
        for i in range(seg + 1):
            ph = 2 * np.pi * i / seg
            d = np.array([np.sin(th) * np.cos(ph), np.sin(th) * np.sin(ph), -np.cos(th)])
            verts.append(d * r)
            uvs.append([th / np.pi, i / seg])
    verts = np.array(verts)
    faces = []
    for j in range(rings):
        for i in range(seg):
            a = j * (seg + 1) + i
            b = a + seg + 1
            faces.append([a, b, a + 1])
            faces.append([a + 1, b, b + 1])
    faces = np.array(faces)
    # Counter-clockwise from outside, like marching cubes output.
    t = verts[faces]
    nrm = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0])
    flip = np.sum(nrm * t.mean(axis=1), axis=1) < 0
    faces[flip] = faces[flip][:, ::-1]
    return verts, verts / r, faces, np.array(uvs)


def _merge(surfaces, name, material):
    vs, ns, fs, uvs, uv2s = [], [], [], [], []
    off = 0
    for s in surfaces:
        vs.append(s.verts)
        ns.append(s.normals)
        uvs.append(s.uv)
        uv2s.append(s.uv2)
        fs.append(s.faces[:, ::-1] + off)  # undo Surface()'s flip, it is applied again below
        off += len(s.verts)
    return Surface(name, material, np.concatenate(vs), np.concatenate(ns), np.concatenate(fs), uv=np.concatenate(uvs), uv2=np.concatenate(uv2s))


def project_to_skin(P, pts, lift):
    """Moves points straight back (+z) onto the face, then out along the normal by lift."""
    fn = lambda q: head_sdf(P, q, with_lids=False)
    pts = np.array(pts, dtype=float)
    pts[:, 2] = -2.0 * P.r
    for _ in range(200):
        d = fn(pts)
        pts[:, 2] += np.maximum(d, P.r * 0.002) * (d > 0)
    for _ in range(4):
        d = fn(pts)
        pts -= sdf.gradient(fn, pts, P.r * 0.005) * d[:, None]
    return pts + sdf.gradient(fn, pts, P.r * 0.005) * lift


def brows_mesh(P):
    r = P.r
    e = P.eye_r
    chains = []
    for c in P.eyes:
        sx = np.sign(c[0])
        pts = [
            (c[0] - sx * 0.9 * e, c[1] + 1.4 * e),
            (c[0] - sx * 0.3 * e, c[1] + 1.66 * e),
            (c[0] + sx * 0.4 * e, c[1] + 1.7 * e),
            (c[0] + sx * 1.05 * e, c[1] + 1.48 * e),
        ]
        chains.append(project_to_skin(P, [(x, y, 0) for x, y in pts], 0.0))
    th = 0.036 * r * P.brow
    radii = [th * 1.05, th, th * 0.8, th * 0.35]

    def fn(q):
        d = np.full(len(q), 1e3)
        for ch in chains:
            for i in range(len(ch) - 1):
                d = sdf.smin(d, _flat_capsule(q, ch[i], ch[i + 1], radii[i], radii[i + 1], ch[i] - np.array([0, 0, 0.3 * r])), 0.01 * r)
        return d

    lo = (-0.8 * r, -0.1 * r, -1.15 * r)
    hi = (0.8 * r, 0.6 * r, -0.3 * r)
    v, f = sdf.polygonize(fn, lo, hi, r * 0.01, target_tris=1800)
    n = sdf.gradient(fn, v, r * 0.005)
    return Surface("brows", "hair", v, n, f)


def _flat_capsule(q, a, b, ra, rb, centre, flat=1.8):
    """A round cone squashed along the direction away from centre (so it lies flat on a surface)."""
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    ba = b - a
    t = np.clip(np.sum((q - a) * ba, axis=-1) / np.dot(ba, ba), 0, 1)
    perp = q - a - ba * t[:, None]
    nrm = (a + b) / 2 - centre
    nrm /= np.linalg.norm(nrm)
    pn = perp @ nrm
    dist = np.sqrt(np.sum(perp * perp, axis=-1) + (flat * flat - 1) * pn * pn)
    return dist - (ra + (rb - ra) * t)


def lashes_mesh(P):
    r = P.r
    e = P.eye_r

    def fn(q):
        d = np.full(len(q), 1e3)
        for c in P.eyes:
            sx = np.sign(c[0])
            qq = q - c
            # A dark line along the upper lid's edge, thicker toward the outer corner.
            edge = 0.52 * e - 0.1 * np.clip(sx * qq[:, 0] / e, -1, 1) * e
            outer = np.clip(sx * qq[:, 0] / e, 0, 1)
            thick = 0.012 * r * (1.0 + 1.2 * outer) * (1.3 if P.girl else 1.0)
            shell = np.abs(sdf.length(qq) - (e + 0.03 * r)) - thick
            band = sdf.smax(shell, np.abs(qq[:, 1] - edge) - thick * 1.1, 0.003 * r)
            band = sdf.smax(band, qq[:, 2] + 0.2 * e, 0.003 * r)
            d = np.minimum(d, band)
            if P.girl:
                # Three lashes flicking out at the outer corner.
                for k in range(3):
                    a = 0.25 + k * 0.32
                    base = c + np.array([sx * np.cos(a) * e * 0.98, np.sin(a) * e * 0.62 + 0.0 * e, -0.55 * e])
                    tip = base + np.array([sx * (0.09 - 0.02 * k) * r, (0.035 + 0.02 * k) * r, 0.0])
                    d = np.minimum(d, sdf.capsule(q, base, tip, 0.016 * r, 0.004 * r))
        return d

    lo = (-0.8 * r, -0.3 * r, -1.1 * r)
    hi = (0.8 * r, 0.4 * r, -0.3 * r)
    v, f = sdf.polygonize(fn, lo, hi, r * 0.007, target_tris=2400)
    n = sdf.gradient(fn, v, r * 0.004)
    return Surface("lashes", "lash", v, n, f)


def beard_mesh(P, kind):
    r = P.r
    my = P.mouth_y

    def fn(q):
        head = head_sdf(P, q, with_lids=False)
        shell = head - 0.08 * r
        # Jaw and chin, leaving the mouth and cheeks clear.
        region = sdf.ellipsoid(q, (0, -0.8 * r, -0.35 * r), (0.95 * r, 0.6 * r, 0.85 * r))
        d = sdf.smax(shell, region, 0.05 * r)
        d = sdf.smax(d, q[:, 1] - (my + 0.1 * r) - np.clip(np.abs(q[:, 0]) / r - 0.45, 0, 1) * 0.5 * r, 0.04 * r)
        if kind == "long":
            d = sdf.smin(d, sdf.capsule(q, (0, -0.85 * r, -0.62 * r), (0.0, -2.1 * r, -0.62 * r), 0.42 * r, 0.1 * r), 0.15 * r)
        mouth = sdf.ellipsoid(q, (0, my - 0.03 * r, -0.95 * r), (0.2 * r, 0.08 * r, 0.25 * r))
        d = sdf.smax(d, -mouth, 0.02 * r)
        # Moustache sweeping out and down.
        for sx in (-1, 1):
            d = sdf.smin(d, sdf.capsule(q, (sx * 0.02 * r, my + 0.1 * r, -1.0 * r), (sx * 0.3 * r, my - 0.08 * r, -0.86 * r), 0.06 * r, 0.03 * r), 0.03 * r)
        # Clumps running down.
        d = d + np.cos(q[:, 0] / r * 22 + np.sin(q[:, 1] / r * 3) * 2) * 0.012 * r
        return sdf.smax(d, -(head + 0.002 * r), 0.005 * r)

    lo = (-1.1 * r, -2.4 * r, -1.25 * r)
    hi = (1.1 * r, -0.1 * r, 0.6 * r)
    v, f = sdf.polygonize(fn, lo, hi, r * 0.02, target_tris=6000)
    n = sdf.gradient(fn, v, r * 0.01)
    # uv.x: 0 at the root to 1 at the tip, for the hair shader's root shading.
    t = np.clip((-v[:, 1] / r - 0.3) / 1.5, 0, 1)
    return Surface("beard", "hair", v, n, f, uv=np.stack([t, np.zeros(len(v))], -1))
