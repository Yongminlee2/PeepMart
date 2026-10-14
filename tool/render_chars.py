"""Quaternius Ultimate Animated Character Pack(CC0) 을 게임 각도(2:1 아이소)로 찍어 캐릭터별 스프라이트 시트를 만든다.

    blender -b -P tool/render_chars.py -- <FBX 폴더> <출력 폴더> [캐릭터 이름 ...]

시트: 가로 COLS 칸 x 세로 len(ROWS) 줄, 한 칸 FR 픽셀. 발은 칸의 (가운데, FOOT_Y) 에 온다.
"front" 는 화면 왼쪽 아래를 보는 모습, "back" 은 오른쪽 위를 보는 모습이다.
나머지 두 방향은 게임에서 좌우로 뒤집어 쓴다.
"""
import math
import os
import sys

import bpy
import mathutils
import numpy as np

FR = 128          # 한 칸 픽셀
COLS = 8          # 동작 하나를 몇 장으로 나눌지
ORTHO = 1.15      # 한 칸에 담기는 세계 크기(가로)
FOOT_Y = 0.85     # 발 위치(위에서부터 비율)
HEIGHT = 0.92     # 캐릭터 키(세계 크기). 만세를 해도 칸 안에 들어오게
ROWS = [          # (동작, 방향). SitDown 은 마지막 자세로 멈춘다
    ("Idle", "front"), ("Idle", "back"),
    ("Walk", "front"), ("Walk", "back"),
    ("PickUp", "front"), ("PickUp", "back"),
    ("Victory", "front"), ("Defeat", "front"),
    ("PickUp", "front"),  # 일하는 중(계산·청소): 몸을 숙인다
    ("Walk_Carry", "front"), ("Walk_Carry", "back"),
    ("SitDown", "front"), ("SitDown", "back"),
]
TONES = [(0.80, 0.55, 0.42), (0.62, 0.40, 0.28), (0.90, 0.68, 0.55), (0.42, 0.26, 0.17)]
UNIFORM = (0.30, 0.65, 0.35)  # 가게 알바 옷(초록)
# 출력 이름: (FBX, 피부색 번호, 셔츠 색 덮어쓰기). 순서가 게임의 캐릭터 번호다(lib/ui/sprites.dart).
CHARS = {
    "casual-female": ("Casual_Female", 0, None),
    "casual3-female": ("Casual3_Female", 2, None),
    "chef-female": ("Chef_Female", 2, None),
    "suit-female": ("Suit_Female", 1, None),
    "cashier": ("Casual2_Female", 0, UNIFORM),
    "janitor": ("Worker_Male", 1, None),
    "owner": ("Casual_Male", 0, None),
    "casual2-male": ("Casual2_Male", 3, None),
    "old-male": ("OldClassy_Male", 0, None),
    "stocker": ("Casual3_Male", 2, UNIFORM),
    "suit-male": ("Suit_Male", 3, None),
    "doctor-female": ("Doctor_Female_Young", 1, None),
    # 여기부터는 손님만
    "bald-male": ("Casual_Bald", 1, None),
    "chef-male": ("Chef_Male", 0, None),
    "cowboy-female": ("Cowboy_Female", 2, None),
    "cowboy-male": ("Cowboy_Male", 3, None),
    "doctor-male-old": ("Doctor_Male_Old", 2, None),
    "doctor-female-old": ("Doctor_Female_Old", 0, None),
    "doctor-male": ("Doctor_Male_Young", 1, None),
    "kimono-female": ("Kimono_Female", 2, None),
    "kimono-male": ("Kimono_Male", 0, None),
    "old-female": ("OldClassy_Female", 2, None),
    "worker-female": ("Worker_Female", 3, None),
    "pirate-female": ("Pirate_Female", 1, None),
    "pirate-male": ("Pirate_Male", 0, None),
    "viking-female": ("Viking_Female", 2, None),
    "wizard": ("Wizard", 0, None),
    "witch": ("Witch", 2, None),
    "elf": ("Elf", 2, None),
    # 같은 모델에 피부색·셔츠 색만 바꾼 손님
    "casual-female-b": ("Casual_Female", 3, (0.95, 0.55, 0.70)),
    "casual-male-b": ("Casual_Male", 1, (0.98, 0.80, 0.30)),
    "casual2-male-b": ("Casual2_Male", 2, (0.85, 0.30, 0.30)),
    "casual3-female-b": ("Casual3_Female", 1, (0.60, 0.45, 0.85)),
    "casual2-female-b": ("Casual2_Female", 3, (0.40, 0.70, 0.95)),
    "casual3-male-b": ("Casual3_Male", 3, None),
    "casual2-female-c": ("Casual2_Female", 2, None),
    "casual-male-c": ("Casual_Male", 2, (0.45, 0.75, 0.55)),
    "casual-female-c": ("Casual_Female", 1, (1.00, 0.60, 0.30)),
    "bald-male-b": ("Casual_Bald", 3, (0.90, 0.90, 0.90)),
    "worker-male-b": ("Worker_Male", 2, None),
    "suit-female-b": ("Suit_Female", 3, None),
    "suit-male-b": ("Suit_Male", 0, None),
    # 동물·고블린 손님
    "pug": ("Pug", None, None),
    "cow": ("Cow", None, None),
    "goblin-female": ("Goblin_Female", None, None),
    "goblin-male": ("Goblin_Male", None, None),
    # 아이돌(가게에 찾아오는 '스타삐약'): 무대 옷과 머리색. 네 번째 값 = 재질 이름 앞부분 → 색
    "idol-luna": ("Casual3_Female", 2, (1.00, 0.42, 0.72), {"Hair": (0.72, 0.55, 0.98), "Pants": (0.98, 0.95, 1.0), "Belt": (1.0, 0.85, 0.3)}),
    "idol-sera": ("Casual_Female", 0, (0.98, 0.98, 1.00), {"Hair": (0.99, 0.86, 0.42), "Pants": (0.55, 0.75, 1.0), "Belt": (1.0, 0.85, 0.3)}),
    "idol-hana": ("Casual2_Female", 1, (0.40, 0.92, 0.82), {"Hair": (1.0, 0.58, 0.74), "Pants": (0.98, 0.98, 1.0), "Belt": (1.0, 0.85, 0.3)}),
    "idol-rio": ("Casual3_Male", 0, (0.16, 0.16, 0.24), {"Hair": (0.86, 0.88, 0.95), "Pants": (0.95, 0.30, 0.45), "Belt": (1.0, 0.85, 0.3)}),
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


def fix_materials(tone, shirt, extra=None):
    # FBX 재질은 투명·금속으로 들어오고 피부는 거의 검다: 불투명·무광으로, 피부색은 직접 준다.
    # 원래는 검은 피부에 흰 눈(Face)이라, 피부를 밝히면 눈을 어둡게 바꿔야 보인다.
    for m in bpy.data.materials:
        for nd in (m.node_tree.nodes if m.use_nodes else []):
            if nd.type != "BSDF_PRINCIPLED":
                continue
            nd.inputs["Alpha"].default_value = 1.0
            nd.inputs["Metallic"].default_value = 0.0
            nd.inputs["Roughness"].default_value = 0.8
            if tone is None:  # 동물·고블린은 원래 색 그대로
                pass
            elif m.name.startswith("Skin"):
                nd.inputs["Base Color"].default_value = (*TONES[tone], 1.0)
            elif m.name.startswith("Face"):
                nd.inputs["Base Color"].default_value = (0.04, 0.025, 0.02, 1.0)
            if shirt and m.name.startswith("Shirt"):
                nd.inputs["Base Color"].default_value = (*shirt, 1.0)
            for prefix, col in (extra or {}).items():
                if m.name.startswith(prefix):
                    nd.inputs["Base Color"].default_value = (*col, 1.0)
        try:
            m.blend_method = "OPAQUE"
        except Exception:
            pass


def load(fbx, tone, shirt, extra=None):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=fbx)
    new = [o for o in bpy.data.objects if o not in before]
    fix_materials(tone, shirt, extra)
    pivot = bpy.data.objects.new("pivot", None)
    bpy.context.scene.collection.objects.link(pivot)
    for o in new:
        if o.parent is None:
            o.parent = pivot
    arm = next(o for o in new if o.type == "ARMATURE")
    ad = arm.animation_data or arm.animation_data_create()
    for t in list(ad.nla_tracks):
        ad.nla_tracks.remove(t)
    # 서 있는 키를 HEIGHT 에 맞춘다.
    set_action(ad, "Idle")
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()
    zs = [(o.matrix_world @ mathutils.Vector(c)).z for o in new if o.type == "MESH" for c in o.bound_box]
    pivot.scale = [HEIGHT / (max(zs) - min(zs))] * 3
    return pivot, ad


def set_action(ad, name):
    act = next(a for a in bpy.data.actions if a.name.endswith("|" + name))
    ad.action = act
    if hasattr(ad, "action_slot") and getattr(act, "slots", None):
        ad.action_slot = act.slots[0]
    return act.frame_range


def render_sheet(sc, src, out_png, tmp):
    pivot, ad = load(*src)
    sheet = np.zeros((len(ROWS) * FR, COLS * FR, 4), dtype=np.float32)
    for row, (anim, facing) in enumerate(ROWS):
        # 모델은 -Y 를 본다. back 은 반 바퀴 돌린다.
        pivot.rotation_euler = (0, 0, math.pi if facing == "back" else 0)
        start, end = set_action(ad, anim)
        for i in range(COLS):
            f = end if anim == "SitDown" else start + (end - start) * i / COLS
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
    names = args[2:] or list(CHARS)
    os.makedirs(dst, exist_ok=True)
    for n in names:
        fbx, tone, shirt, *extra = CHARS[n]
        tmp = os.path.join(dst, f"_frame_{n}.png")
        sc = setup_scene()
        render_sheet(sc, (os.path.join(src, fbx + ".fbx"), tone, shirt, extra[0] if extra else None),
                     os.path.join(dst, f"character-{n}.png"), tmp)
        os.remove(tmp)
        print("done", n)


main()
