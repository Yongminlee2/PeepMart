"""KayKit 'Adventurers'(CC0, Kay Lousberg) 꼬마 캐릭터를 게임 캐릭터 시트로 찍는다(귀여운 손님).

    blender -b -P tool/render_kaykit.py -- <gltf 폴더(캐릭터 + Rig_Medium 동작 glb)> <출력 폴더> [이름 ...]

캐릭터 glb 에는 동작이 없어서 같은 뼈대(Rig_Medium)의 동작 파일 두 개를 읽어 붙인다.
"""
import math
import os
import sys

import bpy
import mathutils
import numpy as np

FR, COLS, ORTHO, FOOT_Y = 128, 8, 1.15, 0.85
HEIGHT = 0.85  # 머리 큰 꼬마 체형
ROWS = [
    ("Idle", "front"), ("Idle", "back"),
    ("Walk", "front"), ("Walk", "back"),
    ("Pick", "front"), ("Pick", "back"),
    ("Yes", "front"), ("No", "front"),
    ("Pick", "front"),
    ("Walk", "front"), ("Walk", "back"),
    ("Sit", "front"), ("Sit", "back"),
]
# 우리 동작 → KayKit 동작 후보
FALLBACK = {
    "Idle": ["Idle_A"],
    "Walk": ["Walking_A"],
    "Pick": ["PickUp", "Interact"],
    "Yes": ["Jump_Full_Short", "Use_Item"],
    "No": ["Hit_A"],
    "Sit": ["Idle_B", "Idle_A"],
}
CHARS = {"kk-knight": "Knight", "kk-barbarian": "Barbarian", "kk-mage": "Mage", "kk-ranger": "Ranger",
         "kk-rogue": "Rogue", "kk-rogue-hood": "Rogue_Hooded"}
ANIMS = ["Rig_Medium_General.glb", "Rig_Medium_MovementBasic.glb"]


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
    cam.data.ortho_scale = ORTHO
    el, d = math.radians(30), 20
    cam.location = (d * math.cos(el) / math.sqrt(2), -d * math.cos(el) / math.sqrt(2), d * math.sin(el))
    cam.rotation_euler = (math.radians(60), 0, math.radians(45))
    cam.data.shift_y = FOOT_Y - 0.5
    sc.collection.objects.link(cam)
    sc.camera = cam
    return sc


def load(src_dir, name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(src_dir, name + ".glb"))
    new = [o for o in bpy.data.objects if o not in before]
    arm = next(o for o in new if o.type == "ARMATURE")
    # 뼈대에 안 붙은 것(남은 구체)은 지운다
    for o in [o for o in new if o.type == "MESH" and o.parent is None]:
        new.remove(o)
        bpy.data.objects.remove(o, do_unlink=True)
    # 같은 뼈대의 동작 파일: 동작만 남기고 딸려 온 물체는 지운다
    names = {}
    for f in ANIMS:
        b2, a2 = set(bpy.data.objects), set(bpy.data.actions)
        bpy.ops.import_scene.gltf(filepath=os.path.join(src_dir, f))
        for a in set(bpy.data.actions) - a2:
            a.use_fake_user = True
            names[a.name.split("|")[-1]] = a
        for o in set(bpy.data.objects) - b2:
            bpy.data.objects.remove(o, do_unlink=True)
    for m in bpy.data.materials:
        for nd in (m.node_tree.nodes if m.use_nodes else []):
            if nd.type == "BSDF_PRINCIPLED":
                nd.inputs["Metallic"].default_value = 0.0
                nd.inputs["Roughness"].default_value = 0.8
    pivot = bpy.data.objects.new("pivot", None)
    bpy.context.scene.collection.objects.link(pivot)
    for o in new:
        if o.parent is None:
            o.parent = pivot
    ad = arm.animation_data or arm.animation_data_create()
    for t in list(ad.nla_tracks):
        ad.nla_tracks.remove(t)
    set_action(ad, names, "Idle")
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    meshes = [o for o in new if o.type == "MESH"]
    lo, hi = bounds(meshes)
    k = HEIGHT / (hi[2] - lo[2])
    pivot.scale = (k, k, k)
    pivot.location = (-(lo[0] + hi[0]) / 2 * k, -(lo[1] + hi[1]) / 2 * k, -lo[2] * k)
    return pivot, ad, names


def bounds(meshes):
    """뼈대로 움직인 뒤의 실제 꼭짓점으로 잰다(bound_box 는 FBX 배율 때문에 틀린다)."""
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in meshes:
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        pts.extend(ev.matrix_world @ v.co for v in me.vertices)
        ev.to_mesh_clear()
    a = np.array(pts)
    return a.min(0), a.max(0)


def set_action(ad, names, ours):
    for cand in FALLBACK[ours]:
        if cand in names:
            act = names[cand]
            ad.action = act
            if hasattr(ad, "action_slot") and getattr(act, "slots", None):
                ad.action_slot = act.slots[0]
            return act.frame_range
    act = next(iter(names.values()))
    ad.action = act
    return act.frame_range


def render_sheet(sc, src_dir, name, out_png, tmp):
    pivot, ad, names = load(src_dir, name)
    sheet = np.zeros((len(ROWS) * FR, COLS * FR, 4), dtype=np.float32)
    for row, (anim, facing) in enumerate(ROWS):
        pivot.rotation_euler = (0, 0, math.pi if facing == "back" else 0)
        start, end = set_action(ad, names, anim)
        for i in range(COLS):
            f = start + (end - start) * i / COLS
            sc.frame_set(int(f), subframe=f - int(f))
            sc.render.filepath = tmp
            bpy.ops.render.render(write_still=True)
            img = bpy.data.images.load(tmp)
            px = np.array(img.pixels[:], dtype=np.float32).reshape(FR, FR, 4)
            bpy.data.images.remove(img)
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
    names = args[2:] or list(CHARS)
    os.makedirs(dst, exist_ok=True)
    for n in names:
        sc = setup_scene()
        tmp = os.path.join(dst, f"_frame_{n}.png")
        render_sheet(sc, src, CHARS[n], os.path.join(dst, f"character-{n}.png"), tmp)
        os.remove(tmp)
        print("done", n)


main()
