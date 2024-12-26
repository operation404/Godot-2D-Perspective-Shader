# 2D Perspective Shader
This shader creates a pseudo-3D perspective effect when applied to 2D sprites. You can rotate the sprite across the XYZ axes, change the pivot point, and adjust the field of view.

The rotation angles are currently in degrees, but it should be easy to change it to radians. The shader uses the size of the sprite's texture for position calculations by default. If your sprite uses H/V animation frames or a subregion of the texture, make sure to set the actual size of the sprite to the size uniform, otherwise you can just leave it as (0,0). Also remember to enable mipmaps and anisotropic filtering to help with texture quality at sharp angles.

***Note:*** Depending on the pivot point it may be possible to rotate the sprite behind the "camera" point, causing the sprite to deform. The virtual camera point is at the origin and the sprite is projected to a virtual depth of -1 at 90 fov. If a rotation causes the z-component of a vertex's position to become positive, you'll see the distortion. Higher fov values can exasperate this due to shortening the projection distance, but the pivot is the most important. Just be mindful of pivot points that may potentially allow rotating the sprite past the camera.

There are two files in this repository: the main shader file, and the debug version with annotations. Most people should use the main version. They work the same way, but the debug version has a few settings left in it that I used for testing purposes, as well as thorough documentation of how the shader actually works for those curious.

## Example
https://github.com/user-attachments/assets/14add0bd-bd17-4438-b7a4-a040b4d91cf2
