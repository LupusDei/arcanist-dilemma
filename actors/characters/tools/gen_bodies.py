"""Sculpts the skinned bodies: one smooth mesh per body, build and age, in the
farm clothes the creation screen shows (shirt, belt, trousers, boots). Colour
regions in uv2.x let the game recolour it for any outfit (see
CharacterMeshes.REGIONS), and every vertex is weighted to the joints of
CharacterBuilder.JOINTS so the existing animations drive it.

The rest skeleton comes from tools/dump_skeletons.gd, so the mesh always fits
the joints the builder makes.
"""

import json
import os

import numpy as np

import sdf
from meshio import Surface, write

JOINTS = ["Hips", "Spine", "Chest", "Neck", "Head", "ShoulderL", "ElbowL", "HandL", "ShoulderR", "ElbowR", "HandR",
          "ThighL", "KneeL", "FootL", "ThighR", "KneeR", "FootR"]
BONE = {n: i for i, n in enumerate(JOINTS)}
SKIN, TOP, BOTTOM, BOOTS, LEATHER, TRIM, INNER, TIE = range(8)

SKELETONS = os.environ.get("CHARACTER_SKELETONS", "")


def load_skeleton(name):
    data = json.load(open(SKELETONS))[name]
    joints = {}
    for n, j in data["joints"].items():
        b = np.array(j["basis"]).reshape(3, 3)  # rows are the basis x, y, z axes
        joints[n] = (np.array(j["origin"]), b.T)  # columns = axes, so local -> body is B @ v
    return joints, data["dims"]


class Part:
    """One primitive of the body: its distance function, colour region and joint weights.

    weights: [(joint, w)] fixed, or for segments a (joint_a, joint_b, parent) triple that
    blends to joint_b near the far end and to parent near the start."""

    def __init__(self, fn, region, bones, seg=None, k=0.025, group=None):
        self.group = group
        self.fn = fn
        self.region = region
        self.bones = bones
        self.seg = seg
        self.k = k

    def weights(self, p):
        out = np.zeros((len(p), len(JOINTS)))
        if self.seg is None:
            for name, w in self.bones:
                out[:, BONE[name]] += w
            return out
        a, b = self.seg
        t = sdf.segment_t(p, a, b)
        ja, jb, parent = self.bones
        to_b = np.clip((t - 0.78) / 0.22, 0, 1) * 0.5
        to_parent = np.clip((0.2 - t) / 0.2, 0, 1) * 0.45 if parent else np.zeros(len(p))
        out[:, BONE[ja]] += 1 - to_b - to_parent
        out[:, BONE[jb]] += to_b
        if parent:
            out[:, BONE[parent]] += to_parent
        return out


def build_parts(joints, dims, body, build, age):
    girl = body == "girl"
    child = age <= 0
    O = {n: joints[n][0] for n in joints}
    sh = dims["shoulders"]
    w = dims["waist"]
    lr = dims["limb_r"] / 0.05
    parts = []

    def add(fn, region, bones, seg=None, k=0.025, group=None):
        parts.append(Part(fn, region, bones, seg, k, group))

    chest = O["Chest"]
    spine = O["Spine"]
    hips = O["Hips"]
    cz = 0.0
    # Torso: ribcage, shoulder girdle, belly and the shirt's hem over the belt.
    rib = (0.16 * sh * (0.95 if girl else 1.0), 0.15, 0.112)
    add(lambda p: sdf.ellipsoid(p, chest + (0, 0.135, cz), rib), TOP, [("Chest", 1.0)])
    sl, sr = O["ShoulderL"], O["ShoulderR"]
    add(lambda p: sdf.capsule(p, sl + (0.03, -0.015, 0), sr + (-0.03, -0.015, 0), 0.052 * (0.92 if girl else 1.0)), TOP, [("Chest", 1.0)])
    # A boy's shirt hangs straight and loose; a girl's comes in a little at the waist.
    loose = 1.0 if girl else 1.1
    add(lambda p: sdf.ellipsoid(p, spine + (0, 0.12, 0.0), (0.13 * w * loose, 0.13, 0.1)), TOP, [("Spine", 0.7), ("Chest", 0.3)])
    add(lambda p: sdf.ellipsoid(p, spine + (0, 0.025, 0.0), (0.142 * w * (loose * 0.5 + 0.5), 0.07, 0.11)), TOP, [("Spine", 0.6), ("Hips", 0.4)])
    if girl and not child:
        for sx in (-1, 1):
            add(lambda p, sx=sx: sdf.sphere(p, chest + (sx * 0.062, 0.12, -0.062), 0.052), TOP, [("Chest", 1.0)], k=0.045)
    # Belt.
    # Belt and buckle: separate shells over the shirt, so their edges stay crisp.
    add(lambda p: _belt(p, spine, 0.143 * w, 0.112), LEATHER, [("Spine", 0.5), ("Hips", 0.5)], k=0.0, group="belt")
    add(lambda p: sdf.round_box(p, spine + (0, 0.0, -0.121), (0.024, 0.02, 0.006), 0.004), TRIM, [("Spine", 0.5), ("Hips", 0.5)], k=0.0, group="belt")
    # Hips and seat.
    add(lambda p: sdf.ellipsoid(p, hips + (0, -0.03, 0.0), (0.15 * w * (1.08 if girl else 1.0), 0.12, 0.115)), BOTTOM, [("Hips", 1.0)])
    # Neck.
    nr = 0.046 * (0.88 if girl else 1.0)
    add(lambda p: sdf.capsule(p, O["Neck"] + (0, -0.04, 0.005), O["Neck"] + (0, 0.1, 0.012), nr * 1.1, nr), SKIN, ("Neck", "Head", "Chest"), seg=(O["Neck"], O["Neck"] + (0, 0.1, 0)))

    for s, sx in (("L", -1), ("R", 1)):
        sh_o, el_o, ha_o = O["Shoulder" + s], O["Elbow" + s], O["Hand" + s]
        th_o, kn_o, ft_o = O["Thigh" + s], O["Knee" + s], O["Foot" + s]
        # Arms in sleeves: the shoulder cap, upper arm, forearm and the cuff at the wrist.
        ua = 0.052 * lr * (0.88 if girl else 1.0)
        add(lambda p, a=sh_o: sdf.sphere(p, a + (-sx * 0.008, -0.012, 0), ua * 1.08), TOP, [("Shoulder" + s, 0.6), ("Chest", 0.4)])
        add(lambda p, a=sh_o, b=el_o: sdf.capsule(p, a, b, ua * 1.12, ua * 0.92), TOP, ("Shoulder" + s, "Elbow" + s, "Chest"), seg=(sh_o, el_o))
        wrist = el_o + (ha_o - el_o) * 0.97
        add(lambda p, a=el_o, b=wrist: sdf.capsule(p, a, b, ua * 0.92, ua * 0.86), TOP, ("Elbow" + s, "Hand" + s, None), seg=(el_o, ha_o))
        cuff_c = el_o + (ha_o - el_o) * 0.9
        axis = (ha_o - el_o) / np.linalg.norm(ha_o - el_o)
        add(lambda p, c=cuff_c, ax=axis: _ring_axis(p, c, ax, ua * 0.9, 0.011), TOP, [("Elbow" + s, 0.6), ("Hand" + s, 0.4)], k=0.008)
        # Legs: loose trousers rolled up to mid-calf, socks, and chunky ankle boots.
        tr = 0.078 * lr * (1.04 if girl else 1.0)
        add(lambda p, a=th_o, b=kn_o: sdf.capsule(p, a + (0, 0.02, 0), b, tr, tr * 0.78), BOTTOM, ("Thigh" + s, "Knee" + s, "Hips"), seg=(th_o, kn_o))
        roll = kn_o + (ft_o - kn_o) * 0.42
        add(lambda p, a=kn_o, b=roll: sdf.capsule(p, a, b, tr * 0.78, tr * 0.8), BOTTOM, ("Knee" + s, "Foot" + s, "Thigh" + s), seg=(kn_o, ft_o))
        add(lambda p, c=roll + (0, 0.012, 0): _ring(p, c, tr * 0.8, 0.02, 1.0), BOTTOM, [("Knee" + s, 1.0)], k=0.01)
        add(lambda p, a=roll, b=ft_o: sdf.capsule(p, a, b + (0, 0.02, 0), tr * 0.52, tr * 0.5), INNER, ("Knee" + s, "Foot" + s, None), seg=(kn_o, ft_o))
        # Boots are their own shell over the sock: ankle shaft, folded cuff, foot, toe, heel and sole.
        g = "boot" + s
        boot_top = kn_o + (ft_o - kn_o) * 0.8
        add(lambda p, a=boot_top, b=ft_o: sdf.capsule(p, a + (0, -0.005, 0), b, tr * 0.68, tr * 0.72), BOOTS, ("Knee" + s, "Foot" + s, None), seg=(kn_o, ft_o), group=g)
        add(lambda p, c=boot_top + (0, -0.006, 0): _ring(p, c, tr * 0.7, 0.014, 1.0), BOOTS, [("Foot" + s, 1.0)], k=0.008, group=g)
        foot_c = ft_o + (0, -0.03, -0.045)
        add(lambda p, c=foot_c: sdf.ellipsoid(p, c, (0.058, 0.055, 0.105)), BOOTS, [("Foot" + s, 1.0)], k=0.03, group=g)
        add(lambda p, c=ft_o: sdf.sphere(p, c + (0, -0.043, -0.125), 0.047), BOOTS, [("Foot" + s, 1.0)], k=0.03, group=g)
        add(lambda p, c=ft_o: sdf.sphere(p, c + (0, -0.05, 0.035), 0.043), BOOTS, [("Foot" + s, 1.0)], k=0.03, group=g)
        add(lambda p, c=ft_o: sdf.round_box(p, np.array([c[0], 0.013, c[2] - 0.047]), (0.054, 0.01, 0.124), 0.006), LEATHER, [("Foot" + s, 1.0)], k=0.0, group=g)
    # The shirt's collar: two flaps lying open around the neck, down to the V.
    neck = O["Neck"]
    under = [pt for pt in parts if pt.group is None]

    def onto(q, lift):
        q = np.array(q, float)[None]
        f = lambda x: body_sdf(under, x)
        for _ in range(6):
            q = q - sdf.gradient(f, q, 0.001) * (f(q) - lift)[:, None]
        return q[0]

    for sx in (-1, 1):
        y0 = neck[1] - 0.03
        chain = [onto(np.array(q), 0.006) for q in (
            (sx * 0.004, y0 + 0.012, 0.062),
            (sx * 0.052, y0 + 0.0, 0.03),
            (sx * 0.064, y0 - 0.012, -0.022),
            (sx * 0.044, y0 - 0.04, -0.07),
            (sx * 0.02, y0 - 0.085, -0.095),
        )]
        for i in range(len(chain) - 1):
            add(lambda p, a=chain[i], b=chain[i + 1], i=i: _flat_ribbon(p, a, b, neck + (0, -0.06, 0), 0.02 - 0.002 * i, 0.007), TOP, [("Chest", 0.7), ("Neck", 0.3)], k=0.01, group="collar")
    return parts


def _flat_ribbon(p, a, b, centre, half, thick):
    """A flat strip from a to b, lying on the surface around centre (its width runs away from centre)."""
    a = np.asarray(a, float)
    b = np.asarray(b, float)
    ba = b - a
    h = np.clip(np.sum((p - a) * ba, axis=-1) / np.dot(ba, ba), 0, 1)
    perp = p - a - ba[None] * h[:, None]
    out = (a + b) / 2 - centre
    out -= ba * np.dot(out, ba) / np.dot(ba, ba)
    out /= np.linalg.norm(out)
    side = np.cross(ba / np.linalg.norm(ba), out)
    u = perp @ side
    v = perp @ out
    w = perp @ (ba / np.linalg.norm(ba))
    return sdf.length(np.stack([np.maximum(np.abs(u) - half, 0), np.maximum(np.abs(v) - thick * 0.5, 0), w], -1)) - 0.003


def _ring(p, c, R, r, zscale):
    q = (p - c) * np.array([1.0, 1.0, 1.0 / zscale])
    return sdf.torus(q, (0, 0, 0), R, r, axis="y") * min(1.0, zscale)


def _belt(p, c, rx, rz, height=0.042, thick=0.012):
    """A flat band around the waist (an elliptical tube with a rectangular section)."""
    q = p - c
    ang = np.arctan2(q[:, 2] / rz, q[:, 0] / rx)
    rim = np.stack([np.cos(ang) * rx, np.sin(ang) * rz], -1)
    radial = sdf.length(q[:, [0, 2]]) - sdf.length(rim)
    return sdf.length(np.maximum(np.stack([np.abs(radial) - thick * 0.5, np.abs(q[:, 1]) - height * 0.5], -1), 0)) - 0.004


def _ring_axis(p, c, axis, R, r):
    q = p - c
    h = q @ axis
    radial = sdf.length(q - np.outer(h, axis))
    return np.sqrt((radial - R) ** 2 + h * h) - r


def body_sdf(parts, p, want_attr=False, group=None):
    d = np.full(len(p), 1e3)
    raw = []
    for part in [pt for pt in parts if pt.group == group]:
        di = part.fn(p)
        raw.append(di)
        d = sdf.smin(d, di, part.k)
    # Keep the sole flat on the ground.
    d = np.maximum(d, -p[:, 1])
    if want_attr:
        return d, np.stack(raw, axis=1)
    return d


def vneck_zone(p, joints):
    """Front of the chest around the collar, where the shader cuts the shirt's V opening."""
    c = joints["Chest"][0]
    rel = p - c
    return (rel[:, 2] < -0.03) & (rel[:, 1] > 0.12) & (np.abs(rel[:, 0]) < 0.12)


def attributes(parts, v, joints, girl, tau=0.008, group=None):
    parts = [pt for pt in parts if pt.group == group]
    _, raw = body_sdf(parts, v, want_attr=True, group=group)
    soft = np.exp(-(raw - raw.min(axis=1, keepdims=True)) / tau)
    soft /= soft.sum(axis=1, keepdims=True)
    weights = np.zeros((len(v), len(JOINTS)))
    for i, part in enumerate(parts):
        weights += part.weights(v) * soft[:, i:i + 1]
    region = np.array([parts[i].region for i in raw.argmin(axis=1)], dtype=float)
    return weights, region


def smooth_weights(weights, faces, iters=4):
    for _ in range(iters):
        acc = np.zeros_like(weights)
        cnt = np.zeros(len(weights))
        for a, b in ((0, 1), (1, 2), (2, 0)):
            np.add.at(acc, faces[:, a], weights[faces[:, b]])
            np.add.at(cnt, faces[:, a], 1)
        weights = 0.5 * weights + 0.5 * acc / np.maximum(cnt, 1)[:, None]
    return weights


def top4(weights, bone_offset=0):
    idx = np.argsort(-weights, axis=1)[:, :4]
    w = np.take_along_axis(weights, idx, axis=1)
    w /= np.maximum(w.sum(axis=1, keepdims=True), 1e-9)
    return idx.astype(np.int32), w.astype(np.float32)


def hand_sdf(p, side, scale):
    """A relaxed hand in the Hand joint's space: palm toward the body, fingers curled a little."""
    sx = -1 if side == "L" else 1
    s = scale
    d = sdf.round_box(p, (0, -0.048 * s, 0), (0.014 * s, 0.036 * s, 0.031 * s), 0.011 * s)
    # Wrist stub that tucks into the sleeve.
    d = sdf.smin(d, sdf.capsule(p, (0, 0.03 * s, 0), (0, -0.01 * s, 0), 0.026 * s, 0.025 * s), 0.012 * s)
    for i, z in enumerate((-0.022, -0.007, 0.008, 0.022)):
        length = (0.04, 0.044, 0.042, 0.034)[i] * s
        rad = (0.0088, 0.009, 0.0088, 0.0078)[i] * s
        k0 = np.array([0.0, -0.085 * s + abs(z) * 0.2 * s, z * s])
        # Two bends inward, toward the palm.
        k1 = k0 + np.array([sx * 0.008 * s, -length * 0.55, z * 0.08 * s])
        k2 = k1 + np.array([sx * 0.018 * s, -length * 0.4, 0.0])
        d = sdf.smin(d, sdf.capsule(p, k0, k1, rad, rad * 0.92), 0.008 * s)
        d = sdf.smin(d, sdf.capsule(p, k1, k2, rad * 0.92, rad * 0.8), 0.004 * s)
    # Thumb, forward of the palm and pointing down and in.
    t0 = np.array([sx * 0.004 * s, -0.03 * s, -0.03 * s])
    t1 = t0 + np.array([sx * 0.012 * s, -0.03 * s, -0.012 * s])
    t2 = t1 + np.array([sx * 0.012 * s, -0.022 * s, 0.004 * s])
    d = sdf.smin(d, sdf.capsule(p, t0, t1, 0.012 * s, 0.01 * s), 0.01 * s)
    d = sdf.smin(d, sdf.capsule(p, t1, t2, 0.01 * s, 0.0085 * s), 0.004 * s)
    return d


def hand_surface(joints, side, scale):
    o, B = joints["Hand" + side]
    fn = lambda q: hand_sdf(q, side, scale)
    lo = np.array([-0.05, -0.18, -0.07]) * scale
    hi = np.array([0.05, 0.05, 0.06]) * scale
    v, f = sdf.polygonize(fn, lo, hi, 0.0018 * scale, target_tris=2600)
    n = sdf.gradient(fn, v, 0.001 * scale)
    vb = v @ B.T + o
    nb = n @ B.T
    bones = np.zeros((len(v), 4), np.int32)
    bones[:, 0] = BONE["Hand" + side]
    w = np.zeros((len(v), 4), np.float32)
    w[:, 0] = 1
    return Surface("hand" + side, "skin", vb, nb, f, uv2=np.zeros((len(v), 2)), bones=bones, weights=w)


def group_surface(parts, group, joints, girl):
    """A separate shell (belt, boot): polygonized on its own so its edges stay crisp."""
    fn = lambda q: body_sdf(parts, q, group=group)
    # Find its extent on a coarse grid first.
    xs = np.arange(-0.42, 0.42, 0.015)
    ys = np.arange(0.0, 1.6, 0.015)
    zs = np.arange(-0.3, 0.3, 0.015)
    grid = np.stack(np.meshgrid(xs, ys, zs, indexing="ij"), -1).reshape(-1, 3)
    near = grid[fn(grid) < 0.02]
    lo, hi = near.min(axis=0) - 0.03, near.max(axis=0) + 0.03
    lo[1] = max(lo[1], -0.005)
    v, f = sdf.polygonize(fn, lo, hi, 0.0035, target_tris=5000)
    n = sdf.gradient(fn, v, 0.0015)
    weights, region = attributes(parts, v, joints, girl, group=group)
    weights = smooth_weights(weights, f, 2)
    bones, w = top4(weights)
    uv2 = np.stack([region, np.zeros(len(v))], -1)
    return Surface("body", "body", v, n, f, uv=v[:, :2], uv2=uv2, bones=bones, weights=w)


def write_body(path, body, build, age):
    name = "%s_%s_%s" % (body, build, "child" if age <= 0 else "adult")
    joints, dims = load_skeleton(name)
    girl = body == "girl"
    parts = build_parts(joints, dims, body, build, age)
    fn = lambda q: body_sdf(parts, q)
    lo = (-0.42, -0.005, -0.25)
    hi = (0.42, joints["Neck"][0][1] + 0.13, 0.22)
    v, f = sdf.polygonize(fn, lo, hi, 0.0055, target_tris=26000)
    n = sdf.gradient(fn, v, 0.002)
    weights, region = attributes(parts, v, joints, girl)
    weights = smooth_weights(weights, f)
    bones, w = top4(weights)
    uv2 = np.stack([region, (vneck_zone(v, joints) & (region == TOP)).astype(float)], -1)
    # uv: rest-pose body-space x,y, for cloth grain and the collar's V.
    surfaces = [Surface("body", "body", v, n, f, uv=v[:, :2], uv2=uv2, bones=bones, weights=w)]
    for group in sorted({pt.group for pt in parts if pt.group}):
        surfaces.append(group_surface(parts, group, joints, girl))
    hand_scale = 0.92 if girl else 1.0
    for s in ("L", "R"):
        surfaces.append(hand_surface(joints, s, hand_scale))
    chest = joints["Chest"][0]
    write(path, surfaces, {"skinned": True, "joints": JOINTS, "vneck_y": float(chest[1] + (0.205 if girl else 0.2)), "vneck_slope": 1.6})
