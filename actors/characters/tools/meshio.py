"""Writes character meshes in the small binary format CharacterMeshes reads.

Layout (little-endian): b"ACM1", uint32 json length, json header, then for
each surface in order: positions f32[V*3], normals f32[V*3], uv f32[V*2],
uv2 f32[V*2], bones i32[V*4], weights f32[V*4], indices i32[F*3].
uv2.x carries the colour region (see CharacterStyle.REGIONS).
"""

import json
import struct

import numpy as np


class Surface:
    def __init__(self, name, material, verts, normals, faces, uv=None, uv2=None, bones=None, weights=None):
        n = len(verts)
        self.name = name
        self.material = material
        self.verts = np.asarray(verts, dtype=np.float32)
        self.normals = np.asarray(normals, dtype=np.float32)
        # Godot's front faces wind clockwise; marching cubes gives counter-clockwise.
        self.faces = np.asarray(faces, dtype=np.int32)[:, ::-1].copy()
        self.uv = np.zeros((n, 2), np.float32) if uv is None else np.asarray(uv, np.float32)
        self.uv2 = np.zeros((n, 2), np.float32) if uv2 is None else np.asarray(uv2, np.float32)
        self.bones = np.zeros((n, 4), np.int32) if bones is None else np.asarray(bones, np.int32)
        self.weights = np.zeros((n, 4), np.float32) if weights is None else np.asarray(weights, np.float32)
        if weights is None:
            self.weights[:, 0] = 1.0


def write(path, surfaces, meta=None):
    header = {
        "surfaces": [
            {"name": s.name, "material": s.material, "verts": int(len(s.verts)), "tris": int(len(s.faces))}
            for s in surfaces
        ],
        "meta": meta or {},
    }
    blob = json.dumps(header).encode("utf-8")
    with open(path, "wb") as f:
        f.write(b"ACM1")
        f.write(struct.pack("<I", len(blob)))
        f.write(blob)
        for s in surfaces:
            for arr in (s.verts, s.normals, s.uv, s.uv2, s.bones, s.weights, s.faces):
                f.write(np.ascontiguousarray(arr).tobytes())


def mirror_x(surface, name=None):
    v = surface.verts.copy()
    v[:, 0] *= -1
    n = surface.normals.copy()
    n[:, 0] *= -1
    out = Surface(name or surface.name, surface.material, v, n, surface.faces[:, ::-1], surface.uv, surface.uv2, surface.bones, surface.weights)
    # Surface() flips winding again; mirroring already flips handedness, so undo that.
    out.faces = surface.faces[:, ::-1].copy()
    return out
