"""Original miniature city; run with Blender in background mode."""
from pathlib import Path
import bpy
import random

out = Path(__file__).resolve().parents[1] / 'assets'
# Separate scene: preserve all pre-existing scene data.
scene = bpy.data.scenes.new('Policy City')
bpy.context.window.scene = scene
rng = random.Random(41)

def material(name, color, metal=0.0, emission=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    for key, value in [('Base Color', (*color, 1)), ('Metallic', metal), ('Roughness', 0.4), ('Emission Color', (*color, 1)), ('Emission Strength', emission)]:
        shader.inputs[key].default_value = value
    return mat

stone = material('Warm limestone', (0.71, 0.69, 0.60))
white = material('Porcelain', (0.80, 0.84, 0.80))
base = material('Midnight slate', (0.038, 0.077, 0.095), 0.35)
road = material('Streets', (0.014, 0.033, 0.047))
glass = material('Green glass', (0.045, 0.23, 0.24), 0.45)
gold = material('Brass', (0.70, 0.43, 0.15), 0.75)
light = material('Warm windows', (1.0, 0.64, 0.25), emission=1.2)
foliage = material('Cypress', (0.07, 0.26, 0.18))
water = material('Canal', (0.022, 0.22, 0.30), 0.5)

def box(name, loc, size, mat, bevel=0.04):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.object
    obj.name, obj.dimensions = name, size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    if bevel:
        modifier = obj.modifiers.new('Edge light', 'BEVEL')
        modifier.width, modifier.segments = bevel, 2
        obj.modifiers.new('Weighted normals', 'WEIGHTED_NORMAL')
    return obj

def cylinder(name, loc, radius, depth, mat, vertices=24):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)

box('Foundation', (0, 0, -0.36), (18, 14, 0.72), base, 0.3)
box('Brass reveal', (0, 0, -0.01), (17.85, 13.85, 0.055), gold, 0.1)
box('Ground', (0, 0, 0.07), (17.7, 13.7, 0.14), base, 0.1)
for x in [-5.1, 0, 5.1]:
    box('Avenue', (x, 0, 0.15), (0.65, 13.5, 0.02), road, 0)
for y in [-4.5, 0, 4.5]:
    box('Boulevard', (0, y, 0.16), (17.5, 0.65, 0.02), road, 0)
box('Canal', (7.5, 0, 0.19), (0.85, 13.3, 0.03), water, 0)
for y in [-4.5, 0, 4.5]:
    box('Bridge', (7.5, y, 0.26), (1.1, 0.64, 0.16), stone)
for level in range(3):
    box('Civic stair', (0, -1.3, 0.22 + level * 0.15), (4.8 - level * 0.3, 3.6 - level * 0.18, 0.15), stone)
box('Policy House', (0, -0.2, 1.4), (3.75, 2.45, 1.9), stone)
for x in [-1.65, -1.1, -0.55, 0, 0.55, 1.1, 1.65]:
    cylinder('Civic column', (x, -1.8, 1.45), 0.105, 1.75, white)
    cylinder('Column capital', (x, -1.8, 2.30), 0.15, 0.13, stone)
box('Entablature', (0, -0.28, 2.45), (4.35, 3.38, 0.23), white)
box('Roof', (0, -0.25, 2.65), (3.82, 2.83, 0.2), gold)
for x in [-1.0, 0, 1.0]:
    box('Civic window', (x, -1.44, 1.43), (0.4, 0.03, 0.86), glass, 0.01)
for x, y in [(-7, -5.5), (-6.7, -2.4), (-6.7, 2.2), (-6.7, 5.4), (-3.2, 3), (-2, 5.5), (1.2, 5.5), (3, 2.7), (3.4, -5.4), (-2.4, -5.4), (6.1, -2.5), (6.1, 2.4), (5.7, 5.4)]:
    height, width = rng.uniform(1.2, 4.7), rng.uniform(1.0, 1.7)
    box('City building', (x, y, 0.2 + height / 2), (width, 1.5, height), glass if height > 3 else white)
    box('Roof crown', (x, y, height + 0.24), (width + 0.12, 1.62, 0.13), gold if height > 3.5 else stone)
    for floor in range(int(height / 0.48)):
        for side in [-1, 1]:
            box('Window band', (x, y + side * 0.757, 0.52 + floor * 0.48), (width * 0.74, 0.016, 0.10), light, 0)
    if height > 3.5:
        cylinder('Antenna', (x, y, height + 0.7), 0.027, 0.8, gold, 8)
for x, y in [(-3.4, -2.8), (3.4, -2.8), (-3.5, 0.8), (1.7, 2.8), (-7.8, 0.8), (8.3, -2.5), (8.3, 3.0)]:
    box('Planter', (x, y, 0.24), (0.5, 0.5, 0.22), stone)
    cylinder('Trunk', (x, y, 0.65), 0.05, 0.8, gold, 8)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.38, location=(x, y, 1.05))
    bpy.context.object.scale = (0.8, 0.8, 1.65)
    bpy.context.object.name = 'Cypress canopy'
    bpy.context.object.data.materials.append(foliage)
for x in [-4.6, 4.6]:
    for y in [-3, 0.5, 3.5]:
        cylinder('Street light', (x, y, 0.65), 0.027, 1.0, gold, 8)
        box('Lantern', (x, y, 1.2), (0.16, 0.16, 0.18), light, 0.02)
out.mkdir(exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(Path(__file__).with_name('policy_city.blend')))
bpy.ops.export_scene.gltf(filepath=str(out / 'policy_city.glb'), export_format='GLB', export_apply=True, use_active_scene=True, export_cameras=False, export_lights=False)
assert (out / 'policy_city.glb').stat().st_size > 1000
print(f'PASS: original city exported, {len(scene.objects)} objects')
