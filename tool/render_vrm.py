"""VRoid CC0 모델(VRM 0.x)을 게임 캐릭터 시트로 찍는다. 동작 클립이 없어서 뼈를 직접 움직여 자세를 만든다.

    blender -b -P tool/render_vrm.py -- <vrm 폴더> <출력 폴더> [이름 ...]

VRM 은 glTF(.glb) 라서 이름만 .glb 로 바꿔 블렌더 glTF 가져오기로 연다(툰 재질은 빠지고 색 그림은 남는다).
시트 모양은 tool/render_chars.py 와 같다(가로 8칸 x 13줄, 한 칸 128, 발은 FOOT_Y).
"""
import json
import math
import os
import shutil
import struct
import sys

import bpy
import mathutils
import numpy as np
from mathutils import Matrix, Vector

FR, COLS, ORTHO, FOOT_Y, HEIGHT = 128, 8, 1.15, 0.85, 0.92
ROWS = [
    ("idle", "front"), ("idle", "back"),
    ("walk", "front"), ("walk", "back"),
    ("pick", "front"), ("pick", "back"),
    ("yes", "front"), ("no", "front"),
    ("pick", "front"),
    ("carry", "front"), ("carry", "back"),
    ("sit", "front"), ("sit", "back"),
]
# 출력 이름: VRM 파일 이름(확장자 빼고)
MODELS = {
    "vroid-d": "AvatarSample_D",
    "vroid-e": "AvatarSample_E",
    "vroid-f": "AvatarSample_F",
    "vroid-g": "AvatarSample_G",
    "vroid-fumiriya": "Sakurada Fumiriya",
    "vroid-shino": "Sendagaya Shino",
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
    sc.view_settings.exposure = -0.6  # VRoid 텍스처가 밝아서 그대로면 바래 보인다
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (1, 0.97, 0.92, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.55
    sc.world = world
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 1.8
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


def load(path, tmpdir):
    glb = os.path.join(tmpdir, "_model.glb")
    shutil.copyfile(path, glb)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=glb)
    new = [o for o in bpy.data.objects if o not in before]
    # 뼈대에 안 붙은 메시(후미리야의 남은 구체 같은 것)는 지운다
    for o in [o for o in new if o.type == "MESH" and not any(m.type == "ARMATURE" for m in o.modifiers)]:
        new.remove(o)
        bpy.data.objects.remove(o, do_unlink=True)
    for m in bpy.data.materials:
        _ignore_vertex_color(m)
        for nd in (m.node_tree.nodes if m.use_nodes else []):
            if nd.type == "BSDF_PRINCIPLED":
                nd.inputs["Metallic"].default_value = 0.0
                nd.inputs["Roughness"].default_value = 0.85
                # 피부·옷은 불투명하게(후미리야는 알파가 0 으로 들어와 몸이 안 보였다). 눈·속눈썹·머리는 그대로
                if any(k in m.name for k in ("SKIN", "CLOTH")):
                    for l in list(nd.inputs["Alpha"].links):
                        m.node_tree.links.remove(l)
                    nd.inputs["Alpha"].default_value = 1.0
    arm = next(o for o in new if o.type == "ARMATURE")
    pivot = bpy.data.objects.new("pivot", None)
    bpy.context.scene.collection.objects.link(pivot)
    for o in new:
        if o.parent is None:
            o.parent = pivot
    return pivot, arm, [o for o in new if o.type == "MESH"]


def _ignore_vertex_color(m):
    """정점 색 곱하기를 뗀다(흰색으로). 후미리야는 정점 색이 0 이라 몸이 투명하게 나왔다.
    색 곱하기(머리 색 등)는 그대로 둬야 해서 재질을 통째로 바꾸지 않는다."""
    if not m.use_nodes:
        return
    for l in list(m.node_tree.links):
        if l.from_node.type != "VERTEX_COLOR":
            continue
        sock = l.to_socket
        m.node_tree.links.remove(l)
        try:
            sock.default_value = (1, 1, 1, 1) if len(sock.default_value) == 4 else (1, 1, 1)
        except TypeError:
            sock.default_value = 1.0


def bounds(meshes):
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in meshes:
        ev = o.evaluated_get(dg)
        me = ev.to_mesh()
        mw = ev.matrix_world
        pts.extend(mw @ v.co for v in me.vertices)
        ev.to_mesh_clear()
    a = np.array(pts)
    return a.min(0), a.max(0)


class Poser:
    """뼈 방향을 아마추어 공간 방향으로 맞춘다. 모델은 +Y 를 보고, 왼쪽은 side 쪽 X 다."""

    def __init__(self, arm, pivot):
        self.arm = arm
        self.pb = arm.pose.bones
        # 아마추어 공간 ↔ 모델(pivot) 공간: glTF 를 가져오면 아마추어가 돌아가 있을 수 있다
        bpy.context.view_layer.update()
        rel = (pivot.matrix_world.inverted() @ arm.matrix_world).to_3x3().normalized()
        self.to_arm = rel.inverted()
        l = rel @ arm.data.bones["J_Bip_L_UpperArm"].head_local
        self.side = 1.0 if l.x > 0 else -1.0

    def reset(self):
        for b in self.pb:
            b.matrix_basis = Matrix.Identity(4)
        bpy.context.view_layer.update()

    # 팔다리 방향 = 다음 관절까지(가져온 뼈는 축이 전부 위를 봐서 뼈 축으로는 못 쓴다)
    CHILD = {"UpperArm": "LowerArm", "LowerArm": "Hand", "UpperLeg": "LowerLeg", "LowerLeg": "Foot",
             "C_Spine": "C_Chest", "C_Chest": "C_UpperChest", "C_UpperChest": "C_Neck", "C_Neck": "C_Head"}

    def aim(self, name, d):
        b = self.pb.get(name)
        if b is None:
            return
        bpy.context.view_layer.update()
        m = b.matrix.copy()
        key = name[len("J_Bip_"):]
        part = key.split("_", 1)
        child = self.CHILD.get(key) or self.CHILD.get(part[1] if len(part) > 1 else key)
        if child is not None:
            cname = "J_Bip_" + (child if child.startswith("C_") else part[0] + "_" + child)
            c = self.pb.get(cname)
            cur = (c.head - b.head).normalized() if c is not None else (m.to_3x3() @ Vector((0, 1, 0))).normalized()
        else:
            cur = (m.to_3x3() @ Vector((0, 1, 0))).normalized()
        q = cur.rotation_difference((self.to_arm @ Vector(d)).normalized())
        b.matrix = Matrix.Translation(m.to_translation()) @ (q.to_matrix() @ m.to_3x3()).to_4x4()

    def limb(self, lr, upper, lower, upper_d, lower_d):
        self.aim(f"J_Bip_{lr}_{upper}", upper_d)
        self.aim(f"J_Bip_{lr}_{lower}", lower_d)

    def pose(self, anim, f):
        """f: 0~1 동작 안의 시각."""
        self.reset()
        s = self.side
        w = math.sin(2 * math.pi * f)
        arm_down = lambda sx, fwd=0.0: (sx * 0.22, fwd, -1)
        if anim in ("walk", "carry"):
            sw = 0.5 * w
            # 앞으로 간 다리는 정강이가 거의 곧고, 뒤로 간 다리는 무릎이 조금 굽는다
            shin = lambda y: (0, y * 0.35 if y > 0 else y * 1.35, -1)
            self.limb("L", "UpperLeg", "LowerLeg", (0, sw, -1), shin(sw))
            self.limb("R", "UpperLeg", "LowerLeg", (0, -sw, -1), shin(-sw))
            if anim == "walk":
                self.limb("L", "UpperArm", "LowerArm", arm_down(s, -0.4 * w), arm_down(s, -0.4 * w + 0.2))
                self.limb("R", "UpperArm", "LowerArm", arm_down(-s, 0.4 * w), arm_down(-s, 0.4 * w + 0.2))
            else:  # 두 손으로 앞에 든다
                for lr, sx in (("L", s), ("R", -s)):
                    self.limb(lr, "UpperArm", "LowerArm", (sx * 0.15, 0.55, -0.85), (-sx * 0.25, 1, 0.15))
        elif anim == "pick":
            k = math.sin(math.pi * f)  # 숙였다 편다
            self.aim("J_Bip_C_Spine", (0, 0.55 * k, 1))
            self.aim("J_Bip_C_Chest", (0, 0.55 * k, 1))
            for lr, sx in (("L", s), ("R", -s)):
                self.limb(lr, "UpperArm", "LowerArm", (sx * 0.15, 0.3 + 0.8 * k, -1), (sx * 0.05, 0.5 + 0.9 * k, -0.8))
        elif anim == "yes":
            k = 0.5 + 0.5 * w
            for lr, sx in (("L", s), ("R", -s)):
                self.limb(lr, "UpperArm", "LowerArm", (sx * (0.45 + 0.2 * k), 0.1, 1), (sx * (0.2 + 0.3 * k), 0.05, 1))
            self.aim("J_Bip_C_Head", (0, -0.1, 1))
        elif anim == "no":
            self.aim("J_Bip_C_Spine", (0, 0.2, 1))
            self.aim("J_Bip_C_Head", (0.25 * w, 0.45, 1))
            for lr, sx in (("L", s), ("R", -s)):
                self.limb(lr, "UpperArm", "LowerArm", arm_down(sx * 0.6, 0.15), arm_down(sx * 0.6, 0.25))
        elif anim == "sit":
            for lr, sx in (("L", s), ("R", -s)):
                self.limb(lr, "UpperLeg", "LowerLeg", (sx * 0.12, 1, -0.05), (0, 0.15, -1))
                self.limb(lr, "UpperArm", "LowerArm", arm_down(sx, 0.35), (sx * 0.05, 1, -0.3))
        else:  # idle: 팔 내리고 살짝 숨쉬기
            for lr, sx in (("L", s), ("R", -s)):
                self.limb(lr, "UpperArm", "LowerArm", arm_down(sx, 0.02 * w), arm_down(sx, 0.08))
            self.aim("J_Bip_C_Head", (0, 0.03 * w, 1))
        bpy.context.view_layer.update()


def render_sheet(sc, src, out_png, tmpdir):
    pivot, arm, meshes = load(src, tmpdir)
    poser = Poser(arm, pivot)
    poser.pose("idle", 0)
    lo, hi = bounds(meshes)
    k = HEIGHT / (hi[2] - lo[2])
    pivot.scale = (k, k, k)
    pivot.location = (-(lo[0] + hi[0]) / 2 * k, -(lo[1] + hi[1]) / 2 * k, -lo[2] * k)
    bpy.context.view_layer.update()
    base = pivot.location.copy()
    sheet = np.zeros((len(ROWS) * FR, COLS * FR, 4), dtype=np.float32)
    tmp = os.path.join(tmpdir, "_frame.png")
    for row, (anim, facing) in enumerate(ROWS):
        # 모델은 +Y 를 본다: 게임의 front(-Y 쪽)는 반 바퀴, back 은 그대로
        pivot.rotation_euler = (0, 0, 0 if facing == "back" else math.pi)
        for i in range(COLS):
            f = i / COLS
            poser.pose(anim, 0.999 if anim == "sit" else f)
            bob = 0.012 * abs(math.sin(2 * math.pi * f)) if anim in ("walk", "carry") else 0
            sit = -0.22 * HEIGHT if anim == "sit" else 0
            pivot.location = base + Vector((0, 0, bob + sit))
            sc.frame_set(1)
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


def smile_key(path):
    """VRM 의 표정 이름 표에서 'Fcl_ALL_Joy'(눈 감고 활짝 웃기) 번호. 눈 뜬 웃음(Fun)은 너무 옅어서 바꿨다. 가져오면 shape key 이름이 target_N 이 된다."""
    b = open(path, "rb").read()
    n = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + n])
    for m in j["meshes"]:
        names = ((m.get("extras") or {}).get("targetNames")
                 or (m["primitives"][0].get("extras") or {}).get("targetNames") or [])  # 파일마다 둘 중 한 곳에 있다
        for i, x in enumerate(names):
            if x.endswith("Fcl_ALL_Joy"):
                return f"target_{i}"
    return None


PORTRAIT = 256


def render_portraits(src, out_dir, name, tmpdir):
    """친해지기·키우기 화면용 상반신 초상화: 정면, 서기(idle)와 웃기(yes)."""
    sc = setup_scene()
    sc.render.resolution_x = sc.render.resolution_y = PORTRAIT
    pivot, arm, meshes = load(src, tmpdir)
    poser = Poser(arm, pivot)
    poser.pose("idle", 0)
    lo, hi = bounds(meshes)
    k = HEIGHT / (hi[2] - lo[2])
    pivot.scale = (k, k, k)
    pivot.location = (-(lo[0] + hi[0]) / 2 * k, -(lo[1] + hi[1]) / 2 * k, -lo[2] * k)
    pivot.rotation_euler = (0, 0, math.pi)  # 카메라(-Y)를 본다
    cam = sc.camera
    cam.location = (0, -6, HEIGHT * 0.80)
    cam.rotation_euler = (math.radians(90), 0, 0)
    cam.data.shift_y = 0
    cam.data.ortho_scale = HEIGHT * 0.46
    smile = smile_key(src)
    for anim in ("idle", "yes"):
        for o in meshes:
            keys = o.data.shape_keys
            if keys and smile and smile in keys.key_blocks:
                keys.key_blocks[smile].value = 1.0 if anim == "yes" else 0.0
        poser.reset()
        poser.pose("idle", 0)
        if anim == "yes":
            poser.aim("J_Bip_C_Head", (0.12, 0, 1))
        bpy.context.view_layer.update()
        sc.render.filepath = os.path.join(out_dir, f"{name}-{anim}.png")
        bpy.ops.render.render(write_still=True)


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    only_portraits = "--portraits" in args
    args = [a for a in args if a != "--portraits"]
    src, dst = args[0], args[1]
    names = args[2:] or list(MODELS)
    if only_portraits:  # 초상화만 다시
        os.makedirs(dst, exist_ok=True)
        for n in names:
            render_portraits(os.path.join(src, MODELS[n] + ".vrm"), dst, n, dst)
            print("done", n)
        return
    os.makedirs(dst, exist_ok=True)
    for n in names:
        sc = setup_scene()
        render_sheet(sc, os.path.join(src, MODELS[n] + ".vrm"), os.path.join(dst, f"character-{n}.png"), dst)
        os.makedirs(os.path.join(dst, "portraits"), exist_ok=True)
        render_portraits(os.path.join(src, MODELS[n] + ".vrm"), os.path.join(dst, "portraits"), n, dst)
        print("done", n)


main()
