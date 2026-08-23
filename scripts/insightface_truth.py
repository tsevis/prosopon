#!/usr/bin/env python3
"""Regenerate the reference fixture the Swift InsightFace port is checked against.

The Swift tests prove the port agrees with the published Python implementation on the
same image: same faces, same boxes, same 106 landmarks. This writes the ground truth
they compare with, and prints the landmark indices the port depends on so that a change
in the upstream model would be caught rather than silently absorbed.

Usage:  insightface_truth.py <image> <output.json>
"""
import json
import sys

import cv2
import numpy as np
from insightface.app import FaceAnalysis

# Contours in the 106-point layout, confirmed by inspection.
EYE_LEFT, EYE_RIGHT, MOUTH_OUTER = range(33, 43), range(87, 97), range(52, 64)


def main(argv):
    if len(argv) != 3:
        print(__doc__)
        return 2
    image_path, output_path = argv[1], argv[2]

    app = FaceAnalysis(name="buffalo_l", allowed_modules=["detection", "landmark_2d_106"],
                       providers=["CPUExecutionProvider"])
    app.prepare(ctx_id=-1, det_size=(640, 640))
    image = cv2.imread(image_path)
    if image is None:
        print(f"cannot read {image_path}")
        return 1

    faces = sorted(app.get(image), key=lambda f: f.bbox[0])
    record = {"image": image_path.split("/")[-1],
              "width": image.shape[1], "height": image.shape[0], "faces": []}
    for face in faces:
        record["faces"].append({
            "bbox": [float(v) for v in face.bbox],
            "score": float(face.det_score),
            "kps": [[float(a), float(b)] for a, b in face.kps],
            "lm106": [[float(a), float(b)] for a, b in face.landmark_2d_106],
        })
    json.dump(record, open(output_path, "w"), indent=1)
    print(f"wrote {len(faces)} faces to {output_path}")

    # Re-derive the indices the Swift port hard-codes, so drift is visible.
    print("\nindices, taken as the extremes of each contour along the eye axis:")
    for name, contour, invert in [("left eye", EYE_LEFT, False),
                                  ("right eye", EYE_RIGHT, False),
                                  ("mouth", MOUTH_OUTER, False)]:
        outer, inner = [], []
        for face in faces:
            marks, keypoints = face.landmark_2d_106, face.kps
            axis = keypoints[1] - keypoints[0]
            axis = axis / np.linalg.norm(axis)
            projected = {i: float(np.dot(marks[i], axis)) for i in contour}
            outer.append(min(projected, key=projected.get))
            inner.append(max(projected, key=projected.get))
        print(f"  {name:10s} lower {sorted(set(outer))}  upper {sorted(set(inner))}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
