"""Kenney Mini Characters 를 게임 각도(2:1 아이소)로 찍어 캐릭터별 스프라이트 시트를 만든다.

    blender -b -P tool/render_chars.py -- <GLB 폴더> <출력 폴더> [캐릭터 이름 ...]

시트: 가로 COLS 칸 x 세로 len(ROWS) 줄, 한 칸 FR 픽셀. 발은 칸의 (가운데, FOOT_Y) 에 온다.
"front" 는 화면 왼쪽 아래를 보는 모습, "back" 은 오른쪽 위를 보는 모습이다.
나머지 두 방향은 게임에서 좌우로 뒤집어 쓴다.
"""
import math
import os
import sys

import bpy
import numpy as np

FR = 128          # 한 칸 픽셀
COLS = 8          # 동작 하나를 몇 장으로 나눌지
ORTHO = 1.15      # 한 칸에 담기는 세계 크기(가로)
FOOT_Y = 0.85     # 발 위치(위에서부터 비율)
ROWS = [          # (동작, 방향)
    ("idle", "front"), ("idle", "back"),
    ("walk", "front"), ("walk", "back"),
    ("pick-up", "front"), ("pick-up", "back"),
    ("emote-yes", "front"), ("emote-no", "front"),
    ("interact-right", "front"),
    ("holding-both", "front"), ("holding-both", "back"),
    ("sit", "front"), ("sit", "back"),
]
ALL = [f"character-{g}-{c}" for g in ("female", "male") for c in "abcdef"]


def setup_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            pass
    sc.render.resolution_x = sc.render.resolution_y = FR
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
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

    # 2:1 아이소: 30도 위에서, 오른쪽 앞(+X, -Y)에서 원점을 본다.
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = ORTHO
    el, d = math.radians(30), 20
    cam.location = (d * math.cos(el) / math.sqrt(2), -d * math.cos(el) / math.sqrt(2), d * math.sin(el))
    cam.rotation_euler = (math.radians(60), 0, math.radians(45))
    # 발(원점)이 칸의 FOOT_Y 에 오도록 화면을 아래로 민다.
    cam.data.shift_y = FOOT_Y - 0.5
    sc.collection.objects.link(cam)
    sc.camera = cam
    return sc


def load(glb):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=glb)
    new = [o for o in bpy.data.objects if o not in before]
    pivot = bpy.data.objects.new("pivot", None)
    bpy.context.scene.collection.objects.link(pivot)
    for o in new:
        if o.parent is None:
            o.parent = pivot
    arm = next(o for o in new if o.type == "ARMATURE")
    ad = arm.animation_data or arm.animation_data_create()
    for t in list(ad.nla_tracks):
        ad.nla_tracks.remove(t)
    return pivot, ad


def set_action(ad, name):
    act = bpy.data.actions[name]
    ad.action = act
    if hasattr(ad, "action_slot") and getattr(act, "slots", None):
        ad.action_slot = act.slots[0]
    return act.frame_range


def render_sheet(sc, glb, out_png, tmp):
    pivot, ad = load(glb)
    sheet = np.zeros((len(ROWS) * FR, COLS * FR, 4), dtype=np.float32)
    for row, (anim, facing) in enumerate(ROWS):
        # 모델은 -Y 를 본다. back 은 반 바퀴 돌린다.
        pivot.rotation_euler = (0, 0, math.pi if facing == "back" else 0)
        start, end = set_action(ad, anim)
        for i in range(COLS):
            f = start + (end - start) * i / COLS
            sc.frame_set(int(f), subframe=f - int(f))
            sc.render.filepath = tmp
            bpy.ops.render.render(write_still=True)
            img = bpy.data.images.load(tmp)
            px = np.array(img.pixels[:], dtype=np.float32).reshape(FR, FR, 4)
            bpy.data.images.remove(img)
            # 블렌더 픽셀은 아래쪽부터. 시트는 위쪽부터 채운다.
            y0 = (len(ROWS) - 1 - row) * FR
            sheet[y0:y0 + FR, i * FR:(i + 1) * FR] = px
    out = bpy.data.images.new("sheet", COLS * FR, len(ROWS) * FR, alpha=True)
    out.pixels = sheet.ravel()
    out.filepath_raw = out_png
    out.file_format = "PNG"
    out.save()


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    src, dst = args[0], args[1]
    names = args[2:] or ALL
    os.makedirs(dst, exist_ok=True)
    tmp = os.path.join(dst, "_frame.png")
    for n in names:
        sc = setup_scene()
        render_sheet(sc, os.path.join(src, n + ".glb"), os.path.join(dst, n + ".png"), tmp)
        print("done", n)
    if os.path.exists(tmp):
        os.remove(tmp)


main()
