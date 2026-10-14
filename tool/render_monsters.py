"""Quaternius 'Cute Animated Monsters'(CC0) 를 게임 캐릭터 시트로 찍는다(귀여운 손님).

    blender -b -P tool/render_monsters.py -- <FBX 폴더> <Textures 폴더> <출력 폴더> [이름 ...]

시트 모양은 tool/render_chars.py 와 같다. 몬스터마다 있는 동작이 달라서 없는 동작은 비슷한 것으로 대신한다.
"""
import math
import os
import sys

import bpy
import mathutils
import numpy as np

FR, COLS, ORTHO, FOOT_Y = 128, 8, 1.15, 0.85
HEIGHT = 0.7  # 사람보다 작고 동글게
ROWS = [
    ("Idle", "front"), ("Idle", "back"),
    ("Walk", "front"), ("Walk", "back"),
    ("Pick", "front"), ("Pick", "back"),
    ("Yes", "front"), ("No", "front"),
    ("Pick", "front"),
    ("Walk", "front"), ("Walk", "back"),
    ("Sit", "front"), ("Sit", "back"),
]
# 우리 동작 → 몬스터 동작 후보(앞에서부터 있는 것)
FALLBACK = {
    "Idle": ["Idle", "Flying"],
    "Walk": ["Walk", "Flying", "Idle"],
    "Pick": ["Bite_InPlace", "Bite_Front", "Jump", "Idle", "Flying"],
    "Yes": ["Yes", "Dance", "Jump", "Idle", "Flying"],
    "No": ["No", "HitRecieve", "Idle", "Flying"],
    "Sit": ["Idle", "Flying"],
}
# 출력 이름 → FBX (무섭게 생긴 악마·해골은 뺐다)
MONSTERS = {
    "mon-alien": "Alien", "mon-alien-tall": "Alien_Tall", "mon-bat": "Bat", "mon-bee": "Bee", "mon-cactus": "Cactus",
    "mon-chicken": "Chicken", "mon-crab": "Crab", "mon-cthulhu": "Cthulhu", "mon-cyclops": "Cyclops", "mon-deer": "Deer",
    "mon-ghost": "Ghost", "mon-mushroom": "Mushroom", "mon-panda": "Panda", "mon-penguin": "Penguin", "mon-pig": "Pig",
    "mon-tree": "Tree", "mon-dragon": "YellowDragon", "mon-yeti": "Yeti",
}


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


def load(fbx, texture):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=fbx)
    new = [o for o in bpy.data.objects if o not in before]
    img = bpy.data.images.load(texture)  # FBX 는 텍스처를 못 찾아 하얗게 나온다: 직접 붙인다
    for m in bpy.data.materials:
        m.use_nodes = True
        for nd in m.node_tree.nodes:
            if nd.type == "BSDF_PRINCIPLED":
                tex = m.node_tree.nodes.new("ShaderNodeTexImage")
                tex.image = img
                m.node_tree.links.new(tex.outputs["Color"], nd.inputs["Base Color"])
                nd.inputs["Alpha"].default_value = 1.0
                nd.inputs["Metallic"].default_value = 0.0
                nd.inputs["Roughness"].default_value = 0.8
        try:
            m.blend_method = "OPAQUE"
        except Exception:
            pass
    pivot = bpy.data.objects.new("pivot", None)
    bpy.context.scene.collection.objects.link(pivot)
    for o in new:
        if o.parent is None:
            o.parent = pivot
    arm = next(o for o in new if o.type == "ARMATURE")
    ad = arm.animation_data or arm.animation_data_create()
    for t in list(ad.nla_tracks):
        ad.nla_tracks.remove(t)
    names = {a.name.split("|")[-1]: a for a in bpy.data.actions}
    set_action(ad, names, "Idle")
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    meshes = [o for o in new if o.type == "MESH"]
    lo, hi = bounds(meshes)
    k = HEIGHT / (hi[2] - lo[2])
    pivot.scale = (k, k, k)
    pivot.location = (-(lo[0] + hi[0]) / 2 * k, -(lo[1] + hi[1]) / 2 * k, -lo[2] * k)  # 발을 바닥 가운데에
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


def render_sheet(sc, fbx, texture, out_png, tmp):
    pivot, ad, names = load(fbx, texture)
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
    src, texdir, dst = args[0], args[1], args[2]
    names = args[3:] or list(MONSTERS)
    os.makedirs(dst, exist_ok=True)
    for n in names:
        sc = setup_scene()
        tmp = os.path.join(dst, f"_frame_{n}.png")
        render_sheet(sc, os.path.join(src, MONSTERS[n] + ".fbx"), os.path.join(texdir, MONSTERS[n] + "_Texture.png"),
                     os.path.join(dst, f"character-{n}.png"), tmp)
        os.remove(tmp)
        print("done", n)


main()
