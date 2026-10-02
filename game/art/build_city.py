"""Original miniature city; run with Blender in background mode."""
from pathlib import Path
import json
import math
import random
import bpy
from mathutils import Vector

out = Path(__file__).resolve().parents[1] / 'assets'
# Separate scene: preserve all pre-existing scene data.
scene = bpy.data.scenes.new('Policy City')
bpy.context.window.scene = scene
rng = random.Random(41)
district = 'Foundation'

def material(name, color, metal=0.0, emission=0.0, roughness=0.4):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    for key, value in [('Base Color', (*color, 1)), ('Metallic', metal), ('Roughness', roughness), ('Emission Color', (*color, 1)), ('Emission Strength', emission)]:
        shader.inputs[key].default_value = value
    return mat

stone = material('Warm limestone', (0.71, 0.66, 0.53))
white = material('Ivory cornices', (0.85, 0.81, 0.69))
paving = material('Pale plaza', (0.48, 0.53, 0.48), roughness=0.7)
base = material('Midnight slate', (0.038, 0.077, 0.095), 0.25)
road = material('Streets', (0.028, 0.052, 0.060), roughness=0.8)
glass = material('Teal glass', (0.035, 0.20, 0.22), 0.35, roughness=0.27)
glass_pale = material('Silver teal glass', (0.09, 0.29, 0.30), 0.3)
gold = material('Brass', (0.62, 0.39, 0.13), 0.65)
light = material('Warm windows', (0.95, 0.55, 0.18), emission=0.45)
foliage = material('Cypress', (0.045, 0.16, 0.08), roughness=0.8)
leaf = material('Street trees', (0.11, 0.24, 0.10), roughness=0.8)
water = material('Canal', (0.022, 0.18, 0.22), 0.5, roughness=0.22)

def finish(obj, name, mat):
    obj.name = name
    obj['district'] = district
    obj.data.materials.append(mat)
    return obj

def box(name, loc, size, mat, bevel=0.025):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = finish(bpy.context.object, name, mat)
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        modifier = obj.modifiers.new('Edge light', 'BEVEL')
        modifier.width, modifier.segments = bevel, 2
        obj.modifiers.new('Weighted normals', 'WEIGHTED_NORMAL')
    return obj

def cylinder(name, loc, radius, depth, mat, vertices=16, top=None):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius, radius2=radius if top is None else top, depth=depth, location=loc)
    obj = finish(bpy.context.object, name, mat)
    for face in obj.data.polygons:
        face.use_smooth = len(face.vertices) == 4
    return obj

def mesh(name, vertices, faces, mat):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    data.calc_loop_triangles()
    # Every hand-built roof/bridge/pediment is closed with outward-facing normals.
    volume = sum(data.vertices[a].co.dot(data.vertices[b].co.cross(data.vertices[c].co))
                 for a, b, c in (triangle.vertices for triangle in data.loop_triangles)) / 6
    assert volume > 0, f'{name}: inverted or degenerate closed mesh'
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    return finish(obj, name, mat)

def roof(name, x, y, z, width, depth, height, mat, inset=0.6):
    vertices = [(x + sx * width * scale / 2, y + sy * depth * scale / 2, z + dz)
                for scale, dz in [(1, 0), (inset, height)]
                for sx, sy in [(-1, -1), (1, -1), (1, 1), (-1, 1)]]
    return mesh(name, vertices, [(3, 2, 1, 0), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)], mat)

def windows(x, y, width, depth, bottom, height, floors, bays, civic=False):
    # Window bays and pilasters on all four faces survive the optional city rotation.
    for axis, span, length in [('front', width, depth), ('side', depth, width)]:
        for side in [-1, 1]:
            for bay in range(bays):
                offset = (bay - (bays - 1) / 2) * span / bays
                for floor in range(floors):
                    z = bottom + (floor + 0.52) * height / floors
                    loc = (x + offset, y + side * (length / 2 + 0.012), z) if axis == 'front' else (x + side * (length / 2 + 0.012), y + offset, z)
                    size = (span / bays * 0.48, 0.035, height / floors * 0.63) if axis == 'front' else (0.035, span / bays * 0.48, height / floors * 0.63)
                    box('Recessed window', loc, size, glass, 0)
                    lit_loc = (loc[0], loc[1] + side * 0.02, z) if axis == 'front' else (loc[0] + side * 0.02, loc[1], z)
                    lit_size = (size[0] * 0.20, 0.014, size[2] * 0.94) if axis == 'front' else (0.014, size[1] * 0.20, size[2] * 0.94)
                    if civic or rng.random() < 0.7:
                        box('Warm inner glazing', lit_loc, lit_size, light, 0)
                if bay < bays - 1:
                    offset += span / bays / 2
                    loc = (x + offset, y + side * (length / 2 + 0.038), bottom + height / 2) if axis == 'front' else (x + side * (length / 2 + 0.038), y + offset, bottom + height / 2)
                    size = (0.075, 0.07, height) if axis == 'front' else (0.07, 0.075, height)
                    box('Facade pilaster', loc, size, white, 0)

def tower_tier(x, y, bottom, width, depth, height, mat):
    box('Glass tower tier', (x, y, bottom + height / 2), (width, depth, height), mat)
    box('Tower cornice', (x, y, bottom + height), (width + 0.09, depth + 0.09, 0.065), gold, 0.01)
    for axis, span, length in [('front', width, depth), ('side', depth, width)]:
        bays = max(3, round(span / 0.28))
        for side in [-1, 1]:
            for bay in range(bays + 1):
                offset = (bay / bays - 0.5) * span * 0.95
                loc = (x + offset, y + side * (length / 2 + 0.016), bottom + height / 2) if axis == 'front' else (x + side * (length / 2 + 0.016), y + offset, bottom + height / 2)
                size = (0.025, 0.028, height) if axis == 'front' else (0.028, 0.025, height)
                box('Brass mullion', loc, size, gold, 0)
            for floor in range(1, math.ceil(height / 0.48)):
                z = bottom + floor * 0.48
                if z >= bottom + height - 0.1:
                    continue
                loc = (x, y + side * (length / 2 + 0.02), z) if axis == 'front' else (x + side * (length / 2 + 0.02), y, z)
                size = (span, 0.025, 0.022) if axis == 'front' else (0.025, span, 0.022)
                box('Fine floor line', loc, size, base, 0)

def tree(x, y, slender=False):
    box('Tree bed', (x, y, 0.25), (0.50, 0.50, 0.14), stone, 0.02)
    cylinder('Trunk', (x, y, 0.52), 0.035, 0.55, base, 8)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1, location=(x, y, 0.98 if slender else 0.86))
    obj = finish(bpy.context.object, 'Cypress' if slender else 'Street tree', foliage if slender else leaf)
    obj.scale = (0.19, 0.19, 0.63) if slender else (0.36, 0.34, 0.44)
    for face in obj.data.polygons:
        face.use_smooth = True

def lamp(x, y):
    cylinder('Lamp foot', (x, y, 0.28), 0.07, 0.16, base, 8)
    cylinder('Lamp post', (x, y, 0.64), 0.018, 0.80, gold, 8)
    box('Lamp crossbar', (x, y, 1.00), (0.28, 0.025, 0.025), gold, 0)
    for side in [-1, 1]:
        box('Lantern', (x + side * 0.12, y, 1.045), (0.09, 0.09, 0.13), light, 0.008)
        roof('Lantern cap', x + side * 0.12, y, 1.11, 0.12, 0.12, 0.055, gold, 0.2)

box('Foundation', (0, 0, -0.32), (18, 14, 0.64), base, 0.16)
box('Foundation reveal', (0, 0, 0.015), (17.96, 13.96, 0.035), gold, 0.035)
box('Ground', (0, 0, 0.09), (17.8, 13.8, 0.12), paving, 0.035)
for x in [-4.0, 4.0]:
    box('Avenue', (x, 0.4, 0.154), (0.52, 12.5, 0.012), road, 0)
box('Rear boulevard', (0, 2.0, 0.16), (14.0, 0.50, 0.012), road, 0)
box('Civic plaza', (0, -2.75, 0.19), (6.55, 4.2, 0.08), stone, 0.03)
for x in [-2.8, -1.4, 0, 1.4, 2.8]:
    box('Plaza joint', (x, -3.9, 0.234), (0.018, 1.6, 0.006), paving, 0)

# The portico, pediment and roof are limestone/teal; brass is only an accent.
district = 'Civic hall'
for level in range(8):
    box('Civic stair', (0, -1.95 + level * 0.10, 0.265 + level * 0.085), (5.65 - level * 0.055, 3.25 - level * 0.20, 0.085), stone, 0.012)
box('Hall plinth', (0, 0.30, 0.52), (5.15, 3.25, 0.74), stone)
box('Policy House', (0, 0.3, 2.01), (4.75, 2.85, 2.3), stone, 0.035)
windows(0, 0.3, 4.75, 2.85, 0.99, 2.03, 1, 6, civic=True)
for x in [-1.98, -1.188, -0.396, 0.396, 1.188, 1.98]:
    cylinder('Column footing', (x, -1.63, 0.96), 0.21, 0.13, stone, 24)
    cylinder('Column base', (x, -1.63, 1.04), 0.17, 0.075, white, 24)
    cylinder('Tapered civic column', (x, -1.63, 2.05), 0.145, 1.98, white, 24, top=0.12)
    cylinder('Column capital', (x, -1.63, 3.06), 0.20, 0.12, stone, 24)
    box('Capital abacus', (x, -1.63, 3.14), (0.42, 0.40, 0.075), white, 0.012)
for z, width, depth, height in [(3.20, 5.16, 3.66, 0.14), (3.32, 5.32, 3.80, 0.095), (3.40, 5.48, 3.94, 0.06)]:
    box('Layered entablature', (0, 0.07, z), (width, depth, height), white, 0.015)
for x in [-2.7, 2.7]:
    box('Gallery plinth', (x, 0.45, 0.505), (0.82, 2.45, 0.71), stone)
    box('Side gallery', (x, 0.45, 1.68), (0.72, 2.35, 1.64), stone)
    windows(x, 0.45, 0.72, 2.35, 0.99, 1.30, 1, 3, civic=True)
    box('Gallery cornice', (x, 0.45, 2.57), (0.9, 2.55, 0.16), white)
    roof('Gallery teal roof', x, 0.45, 2.65, 0.87, 2.50, 0.29, glass, 0.60)
roof('Hall hipped roof', 0, 0.27, 3.44, 4.88, 3.22, 0.55, glass, 0.63)
# Closed triangular prism: the front faces toward negative Blender Y.
mesh('Limestone pediment', [(-2.48, y, 3.46) for y in [-1.97, -1.72]] + [(2.48, y, 3.46) for y in [-1.97, -1.72]] + [(0, y, 4.03) for y in [-1.97, -1.72]], [(0, 2, 4), (1, 5, 3), (0, 1, 3, 2), (2, 3, 5, 4), (4, 5, 1, 0)], white)
for side in [-1, 1]:
    slope = box('Pediment rake', (side * 1.25, -2.005, 3.77), (2.58, 0.115, 0.065), stone, 0.01)
    slope.rotation_euler.y = side * math.atan2(0.57, 2.48)
box('Pediment lower molding', (0, -2.005, 3.49), (5.10, 0.14, 0.07), stone, 0.01)
for x in [-1.15, -0.57, 0, 0.57, 1.15]:
    box('Abstract pediment relief', (x, -1.994, 3.63), (0.15, 0.028, 0.12 + 0.12 * (1 - abs(x) / 1.3)), stone, 0.015)
box('Roof lantern base', (0, 0.60, 3.97), (2.40, 1.88, 0.22), stone)
box('Roof lantern cornice', (0, 0.60, 4.13), (2.55, 2.0, 0.095), white)
roof('Low teal lantern roof', 0, 0.60, 4.18, 2.23, 1.72, 0.37, glass, 0.24)
cylinder('Lantern finial', (0, 0.60, 4.63), 0.035, 0.24, gold, 12, top=0.015)

# Deliberate skyline: setback towers and a round corner tower.
district = 'Skyline'
for x, y, width, depth, height, tiers, mat in [(-6.25, 2.9, 1.55, 1.5, 4.25, 2, glass), (-3.6, 4.65, 1.70, 1.6, 4.40, 3, glass), (-0.65, 4.9, 1.35, 1.35, 4.75, 2, glass_pale), (2.25, 4.55, 1.55, 1.6, 5.35, 3, glass), (4.75, 2.95, 1.35, 1.5, 4.40, 2, glass_pale)]:
    box('Tower podium', (x, y, 0.45), (width + 0.3, depth + 0.3, 0.58), stone)
    bottom = 0.74
    for tier in range(tiers):
        tier_height = height * (0.69 if tier == 0 else 0.31 / (tiers - 1))
        tower_tier(x, y, bottom, width * (1 - 0.16 * tier), depth * (1 - 0.16 * tier), tier_height, mat)
        bottom += tier_height
    box('Tower roof terrace', (x, y, bottom + 0.035), (width * 0.64, depth * 0.64, 0.08), stone, 0.01)
    cylinder('Tower spire', (x, y, bottom + 0.27), 0.018, 0.45, gold, 8)
x, y = 6.60, 4.65
cylinder('Round tower podium', (x, y, 0.45), 0.87, 0.58, stone, 32)
cylinder('Round teal tower', (x, y, 2.94), 0.75, 4.42, glass, 32)
for floor in range(10):
    cylinder('Round tower collar', (x, y, 0.78 + floor * 0.48), 0.768, 0.028, gold, 32)
for bay in range(20):
    angle = bay * math.tau / 20
    cylinder('Round tower mullion', (x + 0.762 * math.cos(angle), y + 0.762 * math.sin(angle), 2.94), 0.014, 4.42, gold, 8)
cylinder('Round tower upper crown', (x, y, 5.19), 0.84, 0.10, stone, 32)
cylinder('Round crown glass', (x, y, 5.40), 0.66, 0.33, glass_pale, 32)
cylinder('Round crown brass rim', (x, y, 5.58), 0.71, 0.065, gold, 32)
cylinder('Round tower finial', (x, y, 5.79), 0.02, 0.38, gold, 8)

# Lower streets frame, rather than obstruct, the civic steps and plaza.
district = 'Neighborhood'
for x, y, width, depth, height, mansard in [(-6.6, -3.45, 1.65, 1.50, 1.85, True), (-4.75, -3.25, 1.42, 1.65, 2.10, True), (4.8, -3.10, 1.40, 1.6, 1.95, True), (6.15, -2.80, 1.15, 1.8, 2.45, False), (-6.70, -0.60, 1.45, 1.45, 2.65, False), (-4.9, 0.75, 1.45, 1.45, 2.10, False), (4.95, -0.15, 1.5, 1.55, 2.60, False), (-7.15, 5.4, 1.2, 1.15, 1.65, False), (0.8, 2.65, 1.3, 0.75, 1.65, False)]:
    bottom = 0.28
    box('Neighborhood plinth', (x, y, bottom), (width + 0.12, depth + 0.12, 0.23), stone)
    box('Ivory neighborhood block', (x, y, bottom + height / 2), (width, depth, height), stone)
    floors = max(2, round(height / 0.7))
    windows(x, y, width, depth, bottom + 0.10, height - 0.23, floors, 3)
    for floor in range(1, floors):
        box('String course', (x, y, bottom + floor * height / floors), (width + 0.075, depth + 0.075, 0.05), white, 0)
    box('Neighborhood cornice', (x, y, bottom + height), (width + 0.18, depth + 0.18, 0.13), white, 0.015)
    if mansard:
        roof('Slate mansard', x, y, bottom + height + 0.055, width + 0.15, depth + 0.15, 0.43, base, 0.63)
        for dx in [-0.35, 0.35]:
            box('Dormer cheek', (x + dx, y - depth / 2 + 0.04, bottom + height + 0.22), (0.25, 0.22, 0.24), stone, 0.01)
            box('Dormer glazing', (x + dx, y - depth / 2 - 0.077, bottom + height + 0.22), (0.11, 0.015, 0.14), light, 0)
            roof('Dormer cap', x + dx, y - depth / 2 + 0.02, bottom + height + 0.34, 0.3, 0.27, 0.09, base, 0.15)
    else:
        box('Roof terrace', (x, y, bottom + height + 0.08), (width * 0.83, depth * 0.83, 0.045), paving, 0)
        for side in [-1, 1]:
            box('Terrace parapet', (x, y + side * depth * 0.45, bottom + height + 0.19), (width, 0.075, 0.23), stone, 0.01)
        box('Roof garden', (x, y + depth * 0.22, bottom + height + 0.18), (width * 0.6, 0.28, 0.16), foliage, 0.04)
    box('Shopfront canopy', (x, y - depth / 2 - 0.15, 0.79), (width * 0.81, 0.27, 0.10), glass, 0.012)

# Raised quays and three arched crossings make the foreground readable.
district = 'Canal and bridges'
box('Front canal', (0, -5.66, 0.165), (17.30, 1.28, 0.025), water, 0)
box('Side canal', (7.50, 0.55, 0.165), (1.12, 11.20, 0.025), water, 0)
for y in [-6.35, -4.97]:
    box('Front quay', (0, y, 0.215), (17.42, 0.16, 0.14), stone, 0.015)
for x in [6.89, 8.11]:
    box('Side quay', (x, 0.50, 0.215), (0.14, 11.24, 0.14), stone, 0.015)
for x in [-5.4, 0, 4.95]:
    for y in [-6.60, -4.69]:
        box('Bridge abutment', (x, y, 0.24), (1.12, 0.22, 0.20), stone, 0.01)
    # A closed arched slab plus matching stone parapets, not a flat crossing box.
    for center, width, thickness, name in [(x, 0.88, 0.15, 'Arched bridge deck'), (x - 0.49, 0.09, 0.31, 'Bridge parapet'), (x + 0.49, 0.09, 0.31, 'Bridge parapet')]:
        vertices = []
        for step in range(13):
            t = step / 12
            y = -6.62 + 1.95 * t
            z = 0.28 + 0.30 * (1 - (2 * t - 1) ** 2)
            for dx, dz in [(-width / 2, 0), (width / 2, 0), (width / 2, thickness), (-width / 2, thickness)]:
                vertices.append((center + dx, y, z + dz))
        faces = [(0, 1, 2, 3), (48, 51, 50, 49)]
        for step in range(12):
            for edge in range(4):
                a, b = step * 4 + edge, step * 4 + (edge + 1) % 4
                faces.append((a, a + 4, b + 4, b))
        mesh(name, vertices, faces, stone)
box('Side crossing deck', (7.5, 1.20, 0.30), (1.60, 0.86, 0.20), stone)
for y in [0.72, 1.68]:
    box('Side crossing parapet', (7.5, y, 0.51), (1.60, 0.08, 0.25), white, 0.01)
# Sparse opaque ripples suggest water without shaders or animation dependencies.
for ripple in range(34):
    x, y = rng.uniform(-8.2, 8.2), rng.uniform(-6.18, -5.14)
    if min(abs(x - bridge) for bridge in [-5.4, 0, 4.95]) > 0.65:
        box('Water glint', (x, y, 0.181), (rng.uniform(0.08, 0.28), 0.014, 0.006), glass_pale, 0)
for x in range(-8, 9):
    cylinder('Quay railing post', (x, -6.43, 0.40), 0.013, 0.34, gold, 8)
box('Front quay handrail', (0, -6.43, 0.57), (17.1, 0.025, 0.025), gold, 0)
for y in range(-4, 7):
    cylinder('Side railing post', (8.20, y, 0.40), 0.013, 0.34, gold, 8)
box('Side quay handrail', (8.20, 1.0, 0.57), (0.025, 10.2, 0.025), gold, 0)

# Plaza fountain and restrained planting keep the foreground open.
district = 'Gardens and lamps'
cylinder('Fountain surround', (0, -3.89, 0.30), 0.60, 0.12, white, 40)
cylinder('Fountain water', (0, -3.89, 0.365), 0.48, 0.028, water, 40)
cylinder('Fountain stem', (0, -3.89, 0.54), 0.095, 0.37, stone, 16)
cylinder('Fountain basin', (0, -3.89, 0.73), 0.24, 0.07, gold, 24)
cylinder('Fountain finial', (0, -3.89, 0.85), 0.045, 0.21, gold, 12, top=0.008)
for x in [-2.55, 2.55]:
    box('Plaza garden curb', (x, -3.56, 0.29), (1.10, 1.03, 0.18), white, 0.02)
    box('Plaza garden bed', (x, -3.56, 0.39), (0.91, 0.84, 0.07), foliage, 0.025)
    tree(x, -3.56, True)
for x, y, slender in [(-3.36, -1.6, True), (3.36, -1.6, True), (-3.4, 0.4, True), (3.4, 0.4, True), (-8.1, -4.0, False), (-8.1, -2.5, False), (-8.1, -0.8, False), (-8.1, 1.0, False), (-8.1, 3.1, False), (-7.8, 6.2, False), (-3.0, -4.58, True), (3.0, -4.58, True), (-6.7, -4.55, False), (6.20, -4.30, True), (6.24, 0.60, True), (8.53, -3.6, False), (8.53, -1.7, False), (8.53, 2.9, False), (8.5, 5.6, False)]:
    tree(x, y, slender)
for x, y in [(-7.8, -6.62), (-3.0, -6.62), (2.5, -6.62), (7.8, -6.62), (-3.25, -3.1), (3.25, -3.1), (-7.8, -1.7), (-7.8, 4.2), (8.50, -2.6), (8.50, 0.0), (8.50, 4.4)]:
    lamp(x, y)

# Native joins retain semantic/material groups while bounding Godot draw surfaces.
bpy.ops.object.select_all(action='DESELECT')
groups = {}
for obj in list(scene.objects):
    bpy.context.view_layer.objects.active = obj
    for modifier in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    groups.setdefault((obj['district'], obj.data.materials[0].name), []).append(obj)
for (group, mat_name), objects in groups.items():
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    if len(objects) > 1:
        bpy.ops.object.join()
    bpy.context.object.name = f'{group} | {mat_name}'
    bpy.ops.object.select_all(action='DESELECT')

# Deterministic scene/export smoke check; runs whenever the native asset regenerates.
triangles = 0
coordinates = []
for obj in scene.objects:
    assert obj.type == 'MESH' and len(obj.data.materials) == 1
    obj.data.calc_loop_triangles()
    triangles += len(obj.data.loop_triangles)
    coordinates.extend(obj.matrix_world @ vertex.co for vertex in obj.data.vertices)
assert coordinates and all(math.isfinite(value) for coord in coordinates for value in coord)
bounds = [[min(coord[axis] for coord in coordinates), max(coord[axis] for coord in coordinates)] for axis in range(3)]
assert -9.1 <= bounds[0][0] < bounds[0][1] <= 9.1
assert -7.1 <= bounds[1][0] < bounds[1][1] <= 7.1
assert -0.7 <= bounds[2][0] < bounds[2][1] <= 7.2
assert 0 < triangles <= 120000
assert 0 < len(scene.objects) <= 80
# Retain readable static framing within the original 15-unit, 400x215 panel.
target = Vector((0, 0, 0.8))
forward = (Vector((17, -23, 19)) - target).normalized()
right = Vector((0, 0, 1)).cross(forward).normalized()
up = forward.cross(right)
projection = [[min((coord - target).dot(axis) for coord in coordinates),
               max((coord - target).dot(axis) for coord in coordinates)] for axis in [right, up]]
assert -13.85 < projection[0][0] < projection[0][1] < 13.85
assert -7.4 < projection[1][0] < projection[1][1] < 7.4
# The native 18-unit camera also encloses every angle of the optional Y rotation.
horizontal_up = math.hypot(up.x, up.y)
rotation_envelope = [min((coord.z - target.z) * up.z - math.hypot(coord.x, coord.y) * horizontal_up for coord in coordinates),
                     max((coord.z - target.z) * up.z + math.hypot(coord.x, coord.y) * horizontal_up for coord in coordinates)]
assert -8.9 < rotation_envelope[0] < rotation_envelope[1] < 8.9
out.mkdir(exist_ok=True)
# Git retains the prior native assets; do not create unowned .blend1 backups.
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(Path(__file__).with_name('policy_city.blend')))
bpy.ops.export_scene.gltf(filepath=str(out / 'policy_city.glb'), export_format='GLB', export_apply=True, use_active_scene=True, export_cameras=False, export_lights=False)
size = (out / 'policy_city.glb').stat().st_size
assert 1000 < size <= 16 * 1024 * 1024
print('PASS: refined original city exported ' + json.dumps({'meshes': len(scene.objects), 'materials': len({obj.data.materials[0].name for obj in scene.objects}), 'draw_surfaces': len(scene.objects), 'triangles': triangles, 'bounds_blender_xyz': bounds, 'static_camera_projection': projection, 'rotation_vertical_envelope': rotation_envelope, 'glb_bytes': size}, sort_keys=True))
