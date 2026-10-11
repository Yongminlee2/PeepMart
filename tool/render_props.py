"""Kenney 음식·가구 모델을 캐릭터와 같은 각도(2:1 아이소)로 한 장씩 찍는다.

    blender -b -P tool/render_props.py -- <food GLB 폴더> <furniture OBJ 폴더> <출력 폴더>

음식(food-*.png)은 가장 긴 변이 FOOD_FIT 이 되도록 키워 FR_FOOD 칸 가운데에 둔다.
가구(prop-*.png)는 모두 같은 배율(책장 기준)이라 서로 크기가 맞고, 바닥 한가운데가
칸의 (가운데, FOOT_Y) 에 온다. 한 칸 = 세계 1.
"""
import math
import os
import sys

import bpy
import numpy as np

FOOT_Y = 0.80

# 출력 이름: 원본 파일
FOOD = {
    "soda": "soda-can", "donut": "donut-sprinkles", "noodles": "chinese", "sandwich": "sandwich",
    "icecream": "ice-cream", "fruit": "apple", "banana": "banana", "croissant": "croissant",
    "coffee": "cup-coffee", "milk": "carton", "cookie": "cookie-chocolate", "hotdog": "hot-dog",
    "cake": "cake", "muffin": "muffin", "watermelon": "watermelon", "strawberry": "strawberry",
    "burger": "burger", "frappe": "frappe", "bento": "styrofoam-dinner", "chocolate": "chocolate",
    "pizza": "pizza", "cupcake": "cupcake", "sundae": "sundae", "riceball": "rice-ball",
    "fries": "fries", "tea": "cup-tea", "sushi": "sushi-salmon", "grapes": "grapes",
    "popsicle": "popsicle", "pie": "pie",
}
FR_FOOD, ORTHO_FOOD, FOOD_FIT = 96, 1.25, 0.8
FOOD_FIT_EXTRA = {"sandwich": 1.9, "pizza": 1.3, "chocolate": 1.2, "cookie-chocolate": 1.2, "cookie": 1.3}  # 납작해서 작아 보이는 것

PROPS = {"crate": "cardboardBoxOpen", "rack": "bookcaseOpenLow", "plant": "pottedPlant",
         "plant-small": "plantSmall2", "trash": "trashcan", "flowers": "plantSmall1", "lamp": "lampRoundFloor",
         "chair": "chairCushion", "table": "tableRound"}
FR_PROP, ORTHO_PROP = 192, 1.9
RACK_WIDTH = 0.92  # 진열대 가로가 칸의 이만큼이 되도록 가구 전체 배율을 정한다


def scene(fr, ortho, foot):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            pass
    sc.render.resolution_x = sc.render.resolution_y = fr
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (1, 0.97, 0.92, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.9
    sc.world = world
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(40), 0, math.radians(-20))
    sc.collection.objects.link(sun)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = ortho
    el, d = math.radians(30), 20
    cam.location = (d * math.cos(el) / math.sqrt(2), -d * math.cos(el) / math.sqrt(2), d * math.sin(el))
    cam.rotation_euler = (math.radians(60), 0, math.radians(45))
    cam.data.shift_y = foot - 0.5
    sc.collection.objects.link(cam)
    sc.camera = cam
    return sc


def load(path):
    before = set(bpy.data.objects)
    if path.endswith(".glb"):
        bpy.ops.import_scene.gltf(filepath=path)
    else:
        bpy.ops.wm.obj_import(filepath=path, up_axis="Y", forward_axis="NEGATIVE_Z")
    meshes = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    bpy.context.view_layer.update()
    pts = np.array([o.matrix_world @ v.co for o in meshes for v in o.data.vertices])
    return meshes, pts.min(0), pts.max(0)


def place(meshes, lo, hi, scale, center_z):
    """바닥 한가운데를 원점으로 옮기고 키운다. center_z 면 높이도 가운데로."""
    pivot = bpy.data.objects.new("pivot", None)
    bpy.context.scene.collection.objects.link(pivot)
    for o in meshes:
        if o.parent is None:
            o.parent = pivot
    mid = (lo + hi) / 2
    z0 = mid[2] if center_z else lo[2]
    pivot.scale = (scale,) * 3
    pivot.location = (-mid[0] * scale, -mid[1] * scale, -z0 * scale)


def shoot(sc, out):
    sc.render.filepath = out
    bpy.ops.render.render(write_still=True)


def main():
    a = sys.argv[sys.argv.index("--") + 1:]
    food_dir, furn_dir, out = a
    os.makedirs(out, exist_ok=True)
    for name, src in FOOD.items():
        sc = scene(FR_FOOD, ORTHO_FOOD, 0.5)
        meshes, lo, hi = load(os.path.join(food_dir, src + ".glb"))
        place(meshes, lo, hi, FOOD_FIT * FOOD_FIT_EXTRA.get(name, 1) / max(hi - lo), True)
        shoot(sc, os.path.join(out, f"food-{name}.png"))
    scene(FR_PROP, ORTHO_PROP, FOOT_Y)
    _, lo, hi = load(os.path.join(furn_dir, PROPS["rack"] + ".obj"))
    k = RACK_WIDTH / max(hi[0] - lo[0], hi[1] - lo[1])
    for name, src in PROPS.items():
        sc = scene(FR_PROP, ORTHO_PROP, FOOT_Y)
        sc.view_settings.exposure = -0.8  # 가구 재질이 밝아서 바랜 듯 나온다
        meshes, lo, hi = load(os.path.join(furn_dir, src + ".obj"))
        place(meshes, lo, hi, k, False)
        shoot(sc, os.path.join(out, f"prop-{name}.png"))
    print("done")


main()
