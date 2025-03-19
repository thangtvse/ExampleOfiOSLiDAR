import bpy
import math
import os
import json
import mathutils

# Path to your export directory
# Change this to match your actual export directory path
EXPORT_DIRECTORY = "./data"

# Clear existing cameras
for obj in bpy.context.scene.objects:
    if obj.type == 'CAMERA':
        bpy.data.objects.remove(obj)

# Get camera transforms from JSON
json_path = os.path.join(EXPORT_DIRECTORY, "camera_transforms.json")
with open(json_path, 'r') as f:
    transforms_data = json.load(f)

def create_camera_from_arkit_matrix(index, matrix_values):
    """Creates a camera from ARKit camera matrix values"""
    
    # Reshape flat array into 4x4 matrix
    arkit_matrix = mathutils.Matrix((
        (matrix_values[0], matrix_values[1], matrix_values[2], matrix_values[3]),
        (matrix_values[4], matrix_values[5], matrix_values[6], matrix_values[7]),
        (matrix_values[8], matrix_values[9], matrix_values[10], matrix_values[11]),
        (matrix_values[12], matrix_values[13], matrix_values[14], matrix_values[15])
    ))
    
    # Create a new camera
    cam_data = bpy.data.cameras.new(f"Camera_{index}")
    cam_obj = bpy.data.objects.new(f"Camera_{index}", cam_data)
    
    # Set field of view (iPhone camera is around 60-70 degrees)
    cam_data.lens_unit = 'FOV'
    cam_data.angle = math.radians(65.0)
    
    # Add to scene
    bpy.context.collection.objects.link(cam_obj)
    
    # ARKit coordinate system: Right-handed
    # Y-up, X-right, Z-backward (away from device)
    # 
    # Blender coordinate system: Right-handed
    # Z-up, X-right, Y-forward
    
    # Extract position from the ARKit matrix (translation is in the 4th row)
    arkit_pos = mathutils.Vector((arkit_matrix[3][0], arkit_matrix[3][1], arkit_matrix[3][2]))
    
    # ARKit: Y-up (+Y), X-right (+X), Z-backward (-Z from camera perspective)
    # Blender: Z-up (+Z), X-right (+X), Y-forward (-Y from camera perspective)
    
    # Create a coordinate system conversion matrix
    # This matrix converts from ARKit to Blender coordinate system
    arkit_to_blender = mathutils.Matrix((
        (1, 0, 0, 0),   # X axis stays the same
        (0, 0, -1, 0),  # Y axis in Blender is -Z in ARKit
        (0, 1, 0, 0),   # Z axis in Blender is Y in ARKit
        (0, 0, 0, 1)
    ))
    
    # Apply the coordinate conversion to the ARKit matrix
    blender_transform = arkit_to_blender @ arkit_matrix

    # Blender cameras look down the -Z axis, while ARKit looks down +Z
    # Rotate 180 degrees around X axis to flip the camera direction
    camera_flip = mathutils.Matrix.Rotation(math.radians(180.0), 4, 'X')
    
    # Apply the camera direction correction
    cam_obj.matrix_world = blender_transform @ camera_flip
    
    # Set up background image
    image_path = os.path.join(EXPORT_DIRECTORY, f"image_{index}.jpg")
    if os.path.exists(image_path):
        img = bpy.data.images.load(image_path)
        cam_data.show_background_images = True
        bg = cam_data.background_images.new()
        bg.image = img
    
    return cam_obj

# Create cameras for each transform
cameras = []
for i, transform in enumerate(transforms_data):
    camera = create_camera_from_arkit_matrix(i, transform)
    cameras.append(camera)
    print(f"Created Camera_{i}")

# Set the active camera to the first one if available
if cameras:
    bpy.context.scene.camera = cameras[0]
    print("Set first camera as active")

print(f"Created {len(cameras)} cameras from ARKit transforms")