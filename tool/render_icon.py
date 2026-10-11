"""앱 아이콘용 큰 그림: 플레이어 캐릭터가 도넛·캔음료를 들고 반기는 모습(투명 배경).

    blender -b -P tool/render_icon.py -- <Mini Characters GLB 폴더> <Food Kit GLB 폴더> <출력 png>

배경·차양 무늬는 tool/make_icons.py 가 PIL 로 얹는다.
"""
import math
import os
import sys

import bpy

a = sys.argv[sys.argv.index("--") + 1:]
chars, food, out = a

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
    try:
        sc.render.engine = eng
        break
    except TypeError:
        pass
sc.render.resolution_x = sc.render.resolution_y = 1024
sc.render.film_transparent = True
sc.view_settings.view_transform = "Standard"
world = bpy.data.worlds.new("w")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (1, 0.97, 0.92, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
sc.world = world
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 3.2
sun.rotation_euler = (math.radians(40), 0, math.radians(-30))
sc.collection.objects.link(sun)


def imp(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


new = imp(os.path.join(chars, "character-male-a.glb"))
arm = next(o for o in new if o.type == "ARMATURE")
ad = arm.animation_data or arm.animation_data_create()
for t in list(ad.nla_tracks):
    ad.nla_tracks.remove(t)
act = bpy.data.actions["emote-yes"]
ad.action = act
if hasattr(ad, "action_slot") and getattr(act, "slots", None):
    ad.action_slot = act.slots[0]
s, e = act.frame_range
sc.frame_set(int(s + (e - s) * 0.3))

for name, loc, scale in (("donut-sprinkles", (0.36, -0.15, 0.3), 0.6), ("soda-can", (-0.38, -0.15, 0.24), 0.6)):
    for o in imp(os.path.join(food, name + ".glb")):
        if o.parent is None:
            o.location = loc
            o.scale = (scale,) * 3
            o.rotation_euler = (math.radians(15), math.radians(-10), math.radians(20))

# 정면에서 살짝 내려다본다. 아이콘은 작게 보이니 캐릭터를 크게.
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
cam.data.type = "ORTHO"
cam.data.ortho_scale = 1.05
el = math.radians(18)
cam.location = (math.sin(math.radians(25)) * 10 * math.cos(el), -math.cos(math.radians(25)) * 10 * math.cos(el), 10 * math.sin(el) + 0.36)
cam.rotation_euler = (math.radians(90 - 18), 0, math.radians(25))
sc.collection.objects.link(cam)
sc.camera = cam
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
print("done")
