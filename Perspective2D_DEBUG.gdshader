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

/*
The rotation pivot is the point the rotations are performed around, and it's
located with respect to the sprite's origin. If the sprite is centered and the
pivot is (0,0,0), the sprite will rotate around its center.

The units of the pivot are with respect to the sprite's size, which defaults to
the size of the sprite's texture unless custom_rect_size is set. The z component
is scaled by the larger of the sprite's width or height. So a pivot point of
(1,0,0) will shift the pivot to the right by the width of the sprite, and a
pivot of (0,0,-1) will shift the pivot away from the camera point by the larger
of the sprite's width and height.

!!! NOTE !!!
Due to this being a 'fake' effect and not real 3D, distortions can happen when
performing rotations that move the sprite *partially* behind the camera point.
The camera is placed at the origin and the sprite in the negative z direction.
When this occurs, the vertices that go behind the camera have a positive z and
become inverted, while the remaining vertices still have a negative z. When the
quad has some vertices inverted and others not, the triangles that form it can
overlap with each other and flip the direction the texture is displayed.

I don't have a good solution for this yet, but it only occurs when performing
rotations with a pivot that would cause a vertex's Z value to become positive.
High field of view values can make this more noticeable due to reducing the
distance between the camera and projection plane, but it's the pivot point and
rotation angles that actually matter. At the default field of view, pivot z
values of up to positive 0.35 seemed to not have any problem with any rotation
angle, going above that risks distortions when rotating at large angles.
*/
uniform vec3 rotation_pivot = vec3(0.0);

uniform float fov : hint_range(1, 179) = 90;

/*
When culling is enabled, the sprite won't be drawn if it faces away from the
camera after rotation. When disabled, the sprite's texture will be flipped if it
faces away.
*/
uniform bool cull_back = true;

/*
The shader works out of the box when the sprite is the same size as the texture.
Otherwise this uniform needs to be set to the size of the sprite rect, or the
texture will be warped incorrectly when the perspective effect is applied.

When either component of this uniform is less than or equal to zero, the shader
uses the size of the texture as the sprite's size.

If your sprite has animation frames or a region, you need to set this uniform.
*/
uniform ivec2 custom_rect_size = ivec2(0);

group_uniforms Debug;
uniform bool debug_mode = false;
uniform vec4 transparent_pixel_color : source_color = vec4(0.9, 0.0, 1.0, 0.5);
uniform vec3 negative_z_tint : source_color = vec3(1.0, 0.5, 0.5);
uniform bool draw_uv_colors = false;
group_uniforms;

// ============================== Varyings ==============================

varying vec4 vertex_color;
varying float z_reciprocal;
varying flat lowp int facing_camera; // Can't use bool varyings in vertex function

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
    // Since we're manually sampling in the fragment function, need to save
    // vertex color so it can be applied manually
    vertex_color = COLOR;

    vec2 size = any(lessThanEqual(custom_rect_size, ivec2(0)))
                    ? vec2(1.0) / TEXTURE_PIXEL_SIZE
                    : vec2(custom_rect_size);

    /*
    The larger of the sprite's width and height is used to perform normalization
    to better ensure good looking transformations even with large angles and
    fov. Using the larger value ensures that the later calculations result in a
    predictable magnification value at specific fov values, as the max value of
    any x or y components of a vertex's position with respect to the sprite's
    center would be 0.5. Using the smaller dimension for normalization would
    mean no longer being able to rely on the max value of position vector's
    components, causing the magnification to vary based on the ratio between the
    dimensions of the sprite's size.
    */
    float size_scale = max(size.x, size.y);
    vec2 normalized_size = size / size_scale;

    /*
    The distance to the projection plane from the origin when the fov is 90. The
    actual projection distance has to scale based on the field of view using the
    equation:
    P_z = (B_z / 2) + (B_z / 2) * tan(fov / 2)

    At a fov of 90, the projection z is equal to -1. As fov approaches 180, the
    projection z approaches -0.5, and as fov approaches 0, the projection z
    approaches -infinity.

    The distance to the projection plane serves as the focal length for the
    perspective projection, and the values were chosen to achieve the following
    properties:
    - At all fov values, a point which has not been rotated will have the same x
      and y components before and after the perspective divide.
    - At fov 90, a point will have its x and y components scaled by x2 when
      rotated towards the camera, and scaled by x2/3 when rotated away.
    - At fov 180, a point will have its x and y components scaled by infinity
      when rotated towards the camera, and scaled by x1/2 when rotated away.
    - At fov 0, a point will have its x and y components scaled by x1 whether it
      was rotated towards or away from the camera.

    Since the rotation and projection math uses normalized values, the vertices
    of the sprite will have components no greater than 0.5 when the rotation
    pivot is (0,0,0) and the sprite's origin is centered on the sprite. This
    means that the rotated vertices will have z components in the range [-0.5,
    0.5], based on the angle of the rotation. The projection distance is then
    added to the z component of each vertex's position so that a unrotated
    vertex lies directly on the projection plane, and a rotated vertex is in
    front or behind it based on the angle of the rotation.

    When performing the perspective divide, the chosen projection z value and
    the z component of a rotated vertex are used to divide the x and y
    components of each vertex by the following equation: denominator =
    projection_z / (vertex_z + projection_z)

            fov 90             fov 180             fov 0
      z=0  -1/(0-1)=1          -.5/(0-.5)=1        -inf/(0-inf)=1
     z=.5  -1/(.5-1)=1/.5      -.5/(.5-.5)=-inf    -inf/(.5-inf)=1
    z=-.5  -1/(-.5-1)=1/1.5    -.5/(-.5-.5)=.5     -inf/(-.5-inf)=1
    */
    const float base_z = -1.0;
    float projection_z = (base_z * 0.5) + ((base_z * 0.5) / tan(radians(fov) / 2.0));

    // Scale pivot's x or y to account for aspect ratio of the sprite's size
    vec3 scaled_pivot = vec3(rotation_pivot.xy * normalized_size, rotation_pivot.z);

    // Negate x & z angles so rotations properly match actual 3D scenes in Godot
    mat3 rot_mat = create_rotation_matrix(radians(vec3(-x_rotation, y_rotation, -z_rotation)));

    vec3 local_vert_pos = vec3(VERTEX / size_scale, 0.0) - scaled_pivot;

    /*
    In order to perform back-face culling, we need the projected positions of
    the other vertices. This means each vertex of the quad needs to compute the
    locations of each other vertex, since there's no easy way to share this data
    between the vertices during the vertex function. This could be computed on
    the CPU and passed to the shader as a uniform, but that significantly
    reduces the ease of use of the shader. Rather than just have a single shader
    which takes the rotation angles as uniforms, there'd need to be a companion
    script which performs the rotation computations and supplies the result to
    the shader. Unless GPU processing becomes a bottleneck, I value the ease of
    use over the reduction in repeated computations.
    */
    vec3 verts[4] = get_quad_vertices_f3(VERTEX_ID, local_vert_pos, normalized_size);
    verts[0] = rot_mat * verts[0]; // top left
    verts[1] = rot_mat * verts[1]; // bot left
    verts[2] = rot_mat * verts[2]; // bot right
    verts[3] = rot_mat * verts[3]; // top right

    /*
    Undo the translation by the pivot's z before doing the perspective divide.
    Need to wait until after the divide to undo the x&y translation, otherwise
    the perspective divide won't scale correctly with respect to the pivot.

    Also add the projection z distance so that vertices positions with a z value
    of 0 rest directly on the projection plane. Negative z values will be behind
    it and positive z values in front.
    */
    verts[0].z += scaled_pivot.z + projection_z;
    verts[1].z += scaled_pivot.z + projection_z;
    verts[2].z += scaled_pivot.z + projection_z;
    verts[3].z += scaled_pivot.z + projection_z;

    // Perform the perspective divide. See note for projection_z for details
    verts[0].xy *= projection_z / verts[0].z;
    verts[1].xy *= projection_z / verts[1].z;
    verts[2].xy *= projection_z / verts[2].z;
    verts[3].xy *= projection_z / verts[3].z;

    /*
    To handle back-face culling, we can simply calculate the winding order of
    the projected vertices. In Godot, the standard vertex indices are as
    follows: 0: top-left, 1: bottom-left, 2: bottom-right, 3: top-right The
    vertices 0-1-2 wind counterclockwise when facing towards the camera. When
    the 	winding-order is no longer counterclockwise, the sprite is
    culled.
    */
    float wind_order = winding_order(verts[0].xy, verts[1].xy, verts[2].xy);
    facing_camera = int(wind_order < 0.0);

    /*
    We don't need to undo the translation and scaling for each of the vertex
    positions, only the position for this vertex. The calculations for
    perspective correct texture mapping only care about the z component, and the
    winding order calculations only care about position relative to the other
    vertices.
    */
    VERTEX = (verts[VERTEX_ID].xy + scaled_pivot.xy) * size_scale;

    /*
    When vertices have a non-affine transformation applied to them, the texture
    may look odd when drawn due to the UVs not being modified. The UV
    coordinates are interpolated linearly in screen space, but the actual
    distance between projected points varies based on distance from the camera.
    This can be fixed by instead using altered coordinates which are linear in
    screen space and can be interpolated, then transformed back to proper UV
    values.

    By taking the reciprocal of a vertex's depth and multiplying its UV
    coordinates by this value, we get coordinates which can be interpolated. By
    interpolating U/z, U/z, and 1/z, any fragment can then divide U/z and V/z by
    the reciprocal to find the perspective-correct UV coordinates.

    More details here:
    https://en.wikipedia.org/wiki/Texture_mapping#Perspective_correctness
    */
    z_reciprocal = 1.0 / verts[VERTEX_ID].z;
    UV *= z_reciprocal;
}

// ============================== Fragment ==============================

void fragment()
{
    if (cull_back && !bool(facing_camera)) discard;

    // Correct the interpolated UV before using it to sample
    vec2 uv = UV / z_reciprocal;
    COLOR = texture(TEXTURE, uv) * vertex_color;

    if (debug_mode)
    {
        COLOR = mix(COLOR, transparent_pixel_color, 1.0 - COLOR.a);
        if (!bool(facing_camera)) COLOR.xyz *= negative_z_tint;
        if (draw_uv_colors) COLOR = vec4(uv, 0.0, 1.0);
    }
}
