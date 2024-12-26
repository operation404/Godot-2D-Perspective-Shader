/*
    Copyright 2024 "Lich" Caelan B.
    Licensed under the Apache License, Version 2.0
    Repository: https://github.com/operation404/Godot-2D-Perspective-Shader
*/

shader_type canvas_item;

// ============================== Uniforms ==============================

// Rotation inputs are in degrees
uniform float x_rotation : hint_range(-180, 180) = 0.0;
uniform float y_rotation : hint_range(-180, 180) = 0.0;
uniform float z_rotation : hint_range(-180, 180) = 0.0;

// Pivot is centered at sprite's origin and units are scaled by sprite size.
// WARNING: Changing the pivot can make it possible to rotate the sprite behind
// the virtual camera, which will cause visual distortions.
uniform vec3 rotation_pivot = vec3(0.0);

uniform float fov : hint_range(1, 179) = 90;
uniform bool cull_back = true;

// Size defaults to the size of the sprite's texture. If using only a subregion of
// the texture, set this uniform as the sprite's actual size.
uniform ivec2 custom_rect_size = ivec2(0);

// ============================== Varyings ==============================

varying vec4 vertex_color;
varying float z_reciprocal;
varying flat lowp int facing_camera;

// ============================== Vertex ==============================

mat3 create_rotation_matrix(vec3 rotation) {
    float sx = sin(rotation.x); float cx = cos(rotation.x);
    float sy = sin(rotation.y); float cy = cos(rotation.y);
    float sz = sin(rotation.z); float cz = cos(rotation.z);
    float sx_sy = sx*sy;        float cx_sy = cx*sy;

    return mat3(vec3(cy*cz,           cy*sz,           -sy  ),
                vec3(sx_sy*cz-cx*sz,  sx_sy*sz+cx*cz,  sx*cy),
                vec3(cx_sy*cz+sx*sz,  cx_sy*sz-sx*cz,  cx*cy));
}

vec3[4] get_quad_vertices_f3(int vert_id, vec3 vert_pos, vec2 size)
{
    vec2 shifts = vec2(float(vert_id > 1), float(vert_id % 3 > 0));
    vec3 verts[4];
    verts[0] = vec3(vert_pos.xy - (size * shifts), vert_pos.z);
    verts[1] = verts[0] + vec3(0.0, size.y, 0.0);
    verts[2] = verts[0] + vec3(size.x, size.y, 0.0);
    verts[3] = verts[0] + vec3(size.x, 0.0, 0.0);
    return verts;
}

float winding_order(vec2 p1, vec2 p2, vec2 p3)
{
    vec2 e21 = p2 - p1;
    vec2 e31 = p3 - p1;
    return e21.x * e31.y - e31.x * e21.y;
}

void vertex()
{
    vertex_color = COLOR;

    vec2 size = any(lessThanEqual(custom_rect_size, ivec2(0)))
                    ? vec2(1.0) / TEXTURE_PIXEL_SIZE
                    : vec2(custom_rect_size);

    float size_scale = max(size.x, size.y);
    vec2 normalized_size = size / size_scale;

    const float base_z = -1.0;
    float projection_z = (base_z * 0.5) + ((base_z * 0.5) / tan(radians(fov) / 2.0));

    vec3 scaled_pivot = vec3(rotation_pivot.xy * normalized_size, rotation_pivot.z);
    mat3 rot_mat = create_rotation_matrix(radians(vec3(-x_rotation, y_rotation, -z_rotation)));

    vec3 local_vert_pos = vec3(VERTEX / size_scale, 0.0) - scaled_pivot;

    vec3 verts[4] = get_quad_vertices_f3(VERTEX_ID, local_vert_pos, normalized_size);
    verts[0] = rot_mat * verts[0];
    verts[1] = rot_mat * verts[1];
    verts[2] = rot_mat * verts[2];
    verts[3] = rot_mat * verts[3];

    verts[0].z += scaled_pivot.z + projection_z;
    verts[1].z += scaled_pivot.z + projection_z;
    verts[2].z += scaled_pivot.z + projection_z;
    verts[3].z += scaled_pivot.z + projection_z;

    verts[0].xy *= projection_z / verts[0].z;
    verts[1].xy *= projection_z / verts[1].z;
    verts[2].xy *= projection_z / verts[2].z;
    verts[3].xy *= projection_z / verts[3].z;

    float wind_order = winding_order(verts[0].xy, verts[1].xy, verts[2].xy);
    facing_camera = int(wind_order < 0.0);

    VERTEX = (verts[VERTEX_ID].xy + scaled_pivot.xy) * size_scale;

    z_reciprocal = 1.0 / verts[VERTEX_ID].z;
    UV *= z_reciprocal;
}

// ============================== Fragment ==============================

void fragment()
{
    if (cull_back && !bool(facing_camera)) discard;

    vec2 uv = UV / z_reciprocal;
    COLOR = texture(TEXTURE, uv) * vertex_color;
}
