"""Generates every character mesh as .acm files for tools/bake_meshes.gd.

    python3 gen_characters.py OUT_DIR [heads|hair|beards|bodies ...] [--only SUBSTRING]

Then bake: godot --headless --path . --script res://actors/characters/tools/bake_meshes.gd -- OUT_DIR
"""

import os
import sys
from multiprocessing import Pool

import gen_heads as H
import meshio

BODIES = ["boy", "girl"]
FACES = list(H.FACES)
HAIR = ["short", "tousled", "long", "braid", "topknot", "shaved"]
BEARDS = ["full", "long"]
BUILDS = ["slight", "average", "sturdy"]


def job_head(out, body, face, stage):
    age = 0 if stage == "child" else 1
    P = H.HeadParams(body, face, age)
    surfaces = [H.head_mesh(P), H.eye_meshes(P), H.brows_mesh(P), H.lashes_mesh(P)]
    meta = {"cranium_w": P.f["w"], "eye_r": P.eye_r / P.r, "mouth_y": P.mouth_y / P.r, "cheek_x": 0.43 * P.f["w"]}
    name = "%s_%s_%s" % (body, face, "child" if age <= 0 else "adult")
    meshio.write(os.path.join(out, "heads", name + ".acm"), surfaces, meta)
    return name


def job_hair(out, style):
    import gen_hair
    meshio.write(os.path.join(out, "hair", style + ".acm"), [gen_hair.hair_mesh(style)], {})
    return style


def job_beard(out, face, kind):
    P = H.HeadParams("boy", face, 2)
    meshio.write(os.path.join(out, "beards", "%s_%s.acm" % (face, kind)), [H.beard_mesh(P, kind)], {})
    return face + kind


def job_body(out, body, build, stage):
    age = 0 if stage == "child" else 1
    import gen_bodies as B
    name = "%s_%s_%s" % (body, build, "child" if age <= 0 else "adult")
    B.write_body(os.path.join(out, "bodies", name + ".acm"), body, build, age)
    return name


def main():
    out = sys.argv[1]
    kinds = [a for a in sys.argv[2:] if not a.startswith("--")] or ["heads", "hair", "beards", "bodies"]
    only = None
    if "--only" in sys.argv:
        only = sys.argv[sys.argv.index("--only") + 1]
        kinds = [k for k in kinds if k != only]
    jobs = []
    for k in kinds:
        os.makedirs(os.path.join(out, k), exist_ok=True)
    if "heads" in kinds:
        jobs += [(job_head, (out, b, f, a)) for b in BODIES for f in FACES for a in ("adult", "child")]
    if "hair" in kinds:
        jobs += [(job_hair, (out, s)) for s in HAIR]
    if "beards" in kinds:
        jobs += [(job_beard, (out, f, k)) for f in FACES for k in BEARDS]
    if "bodies" in kinds:
        jobs += [(job_body, (out, b, bd, a)) for b in BODIES for bd in BUILDS for a in ("adult", "child")]
    if only:
        jobs = [j for j in jobs if only in "_".join(str(x) for x in j[1][1:])]
    with Pool(min(len(jobs), os.cpu_count() or 2)) as pool:
        for name in pool.starmap(_run, jobs):
            print("wrote", name, flush=True)


def _run(fn, args):
    return fn(*args)


if __name__ == "__main__":
    main()
