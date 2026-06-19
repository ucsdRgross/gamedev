shader_type spatial;
render_mode unshaded, depth_prepass_alpha;

/** Ignore transparent pixels with alpha below this value for extrusion */
uniform float extruded_alpha_cull : hint_range(0.0, 1.0) = 1.0;
/** If transparent pixels are extruded, this makes extruded pixels opaque */
uniform bool opaque_extrude = true;
/** Keeps original image on front and back of cube
 * Unaffected by most other parameters */
uniform bool keep_image = true;
/** Removes transparent pixels with alpha below this value on original image */
uniform float image_alpha_cull : hint_range(0.0, 1.0) = 1.0;
/** Offset extruded portion by this vector */
uniform vec2 offset = vec2(0.0);
/** Color which will be mixed with extruded portion */
uniform vec4 color_mix : source_color = vec4(0.0, 0.0, 0.0, 1.0);
/** 0 is no color mix, 1 is solid color */
uniform float mix_strength : hint_range(0.0, 1.0) = 0.0;
/** 2D image where opaque pixels are extruded.
 * Edges of cube ends up having artifact lines when texture uses mipmaps, so the texture is currently set to automatically filter with nearest, though linear will work as well. */
uniform sampler2D Texture : source_color, filter_nearest;
/** Amount of times each pixel refers to the original image in order to calculate whether it is part of an extruded section.
 * Ideally as low as possible, as higher numbers cause lag. */
uniform int texture_calls = 20;
/** Ray bias value shifts intersection checks to try to avoid checking empty sides, with higher values searching further from edge. */
uniform float ray_bias = 1;
/** Allows hollow regions in texture to extrude infinitely for double the performance on front and back faces. */
uniform bool infinite_holes = false;
/** Parameters to change if your texture is a spritesheet */
uniform int Hframes = 1;
uniform int Vframes = 1;
uniform int frame = 0;

// --- 3D skew controls ---------------------------------------------------------
// These deform the cube mesh in the vertex stage. The whole extrusion in
// fragment() is hardcoded to a CANONICAL unit cube (planes at z=0/x=+-1/y=+-1,
// UVtoXY mapping faces to +-1), so the interior raymarch must keep running in
// that un-skewed space or every plane intersection lands in the wrong place and
// the image warps. We therefore skew only the rendered geometry and pass the
// PRE-skew (canonical) vertex down as a varying; the rasterizer interpolates it
// across the slanted triangle to give each fragment its canonical position, and
// inverse(MODEL_MATRIX) * camera is already in that same canonical space (the
// MODEL_MATRIX doesn't know about the in-shader edit). The extruded content then
// rides along with the deformed mesh for free, with no warping. Assumes a unit
// cube whose local extents are -1..1.
/** Frustum: scales the back (-Z) face within its own X/Y plane without moving
 * it in Z, turning the cube into a frustum. 1.0 = cube, >1 = wider base. */
uniform float back_scale = 1.0;
/** Leans the cube: shifts X/Z proportional to height, centered so the cube's
 * middle stays put (X component leans along X, Y component leans along Z). */
uniform vec2 skew_shear = vec2(0.0);
/** Half-extent of the cube mesh in local space. Godot's default BoxMesh has
 * size 1, i.e. half-extent 0.5. Set this to match your mesh so the skew math
 * works in normalized [-1, 1] space regardless of the mesh's world size. */
uniform float cube_half_extent = 0.5;

// Skewed local-space vertex position, handed to fragment(). The fragment
// recovers the canonical (pre-skew) position from this single source, so the
// unskew stays crease-free across the two triangles of each quad face.
varying vec3 skew_pos;

struct imgPoint {
	vec4 color;
	vec2 uv;
};

bool isInImg(vec2 uv){
	return all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)));
}

vec2 getPositionAlongTheLine(vec2 a, vec2 b, float percentage) {
	return mix(a, b, percentage);
}

// Branchless ray/box exit: intersect the segment x->y with the unit image box.
// Original worked in (u, -v) space against the box u in [0,1], -v in [-1,0];
// the slab method (take the far plane per axis, then the nearest of those exits)
// reproduces every branch of the old nested if-tree, and divisions by a zero
// direction component yield +/-inf which max()/min() resolve correctly.
vec2 lineImgIntersect(vec2 x, vec2 y){
	vec2 P = vec2(x.x, -x.y);
	vec2 D = vec2(y.x, -y.y) - P;
	vec2 tFar = max((vec2(0.0, -1.0) - P) / D, (vec2(1.0, 0.0) - P) / D);
	float t = min(tFar.x, tFar.y);
	vec2 Ex = P + t * D;
	return vec2(Ex.x, -Ex.y);
}

vec2 frameUV(vec2 uv){
	int hFrame = frame % Hframes;
	int vFrame = frame / Vframes;
	uv.x = uv.x / float(Hframes) + float(hFrame) / float(Hframes);
	uv.y = uv.y / float(Vframes) + float(vFrame) / float(Vframes);
	return uv;
}

vec2 flippedFrameUV(vec2 uv){
	float frameCenter = 0.5 / float(Hframes) + float(frame % Hframes) / float(Hframes);
	uv = frameUV(uv);
	uv.x = -(uv.x - frameCenter) + frameCenter;
	return uv;
}

// Return colored pixel found starting from UV with given slope
imgPoint imgExtrude(vec2 pos_on_img, vec2 slope, bool flipped){
	vec4 color;
	// Flip y as UV has inverted y axis
	slope.y *= -1.0;
	// Find intersect with image edge
	vec2 edge = lineImgIntersect(pos_on_img, pos_on_img + slope);
	// Both branches map into the active spritesheet frame; pick once.
	pos_on_img = flipped ? flippedFrameUV(pos_on_img) : frameUV(pos_on_img);
	edge = flipped ? flippedFrameUV(edge) : frameUV(edge);
	// Shift the whole march into offset space (not just the texture lookup) so the
	// returned hit position stays consistent with where the colour was sampled.
	// Otherwise the cap, which keys off that position, culls the offset extrusion.
	pos_on_img += offset;
	edge += offset;

	bool extrude = false;
	vec2 point;
	float log_dir = -1.0;
	float log_percentage;
	for (int i = 0; i < texture_calls; i++){
		if (!extrude) {
			// Coarse march from the pixel toward the image edge.
			float percentage = pow(float(i) / float(texture_calls), ray_bias);
			point = getPositionAlongTheLine(pos_on_img, edge, percentage);
			color = texture(Texture, point);
			if (color.w >= extruded_alpha_cull) {
				extrude = true;
				// First checked pixel is already image, can't tell where the edge is.
				if (i == 0) break;
				// Restart the loop, spending the remaining budget on a binary
				// refinement of the edge position.
				i = 0;
				log_percentage = percentage;
			}
		} else {
			// Fine tune the edge: halve the step each time, walk back on a miss.
			log_percentage += log_dir / (float(texture_calls) * float(i * 2));
			vec2 check_point = getPositionAlongTheLine(pos_on_img, edge, log_percentage);
			vec4 check_color = texture(Texture, check_point);
			bool hit = check_color.w >= extruded_alpha_cull;
			color = hit ? check_color : color;
			point = hit ? check_point : point;
			log_dir = hit ? -1.0 : 1.0;
		}
	}

	if (!extrude) return imgPoint(vec4(0.0), edge);
	color.w = opaque_extrude ? 1.0 : color.w;
	color = mix(color, color_mix, mix_strength);
	return imgPoint(color, infinite_holes ? pos_on_img : point);
}

vec2 UVtoXY(vec2 uv){
	vec2 xy = uv * 2.0 - vec2(1.0);
	xy.y *= -1.0;
	return xy;
}
vec2 XYtoUV(vec2 xy){
	vec2 uv = (xy + vec2(1.0)) / 2.0;
	uv.y *= -1.0;
	return uv;
}

vec3 PlaneLineIntersection(vec3 plane_point, vec3 plane_normal, vec3 line_point, vec3 line_dir){
	vec3 d = normalize(line_dir);
	float t = dot(plane_normal, plane_point - line_point) / dot(plane_normal, d);
	return line_point + d * t;
}

// Cull factor (0 = hide, 1 = keep) for the front/back faces: shoot the opposite
// ray to find the back-face hit and hide the fragment when the extrusion would
// have already ended. Returns 1 unconditionally when the back point misses the
// image, so the (expensive) second imgExtrude only runs when it can matter.
float frontBackCull(vec2 uv_point, float first_y, vec2 mray_xy, float mray_y){
	if (!isInImg(uv_point)) return 1.0;
	float second_y = imgExtrude(uv_point, -mray_xy, false).uv.y;
	bool cull = (mray_y > 0.0) ? (second_y > first_y) : (second_y < first_y);
	return cull ? 0.0 : 1.0;
}

// Maps a side-face pixel onto the front image plane (project to z=0 along the
// reversed ray, then onto the side's own plane along the in-plane ray).
vec2 sideForwardUV(vec3 point, vec3 plane_normal, vec2 atlas_offset, vec3 mray){
	vec3 ray_intersection = PlaneLineIntersection(vec3(0.0), vec3(0.0, 0.0, 1.0), point, -mray);
	vec3 image_intersection = PlaneLineIntersection(vec3(0.0), plane_normal, ray_intersection, vec3(mray.xy, 0.0));
	return XYtoUV(image_intersection.xy) + atlas_offset;
}

// Cull factor for side faces: a back ray that hits nothing means no extrusion.
// sign() collapses the old "== 0.0 ? hide : keep" branch (alpha is never < 0).
float sideCull(vec2 uv_point, vec2 mray_xy){
	if (!isInImg(uv_point)) return 1.0;
	return sign(imgExtrude(uv_point, -mray_xy, false).color.w);
}

// Inverse Jacobian of the shear + frustum skew applied to the view ray d. scale
// is the frustum scale sampled at whatever depth the caller wants (surface for
// recovery, deeper for the forward march or the cap).
vec3 unskewRay(vec3 d, float p, float q, float r, float m, float scale){
	float vy = (d.y - m * d.z) / (scale - m * q);
	float vz = d.z - q * vy;
	float vx = (d.x - p * vy - r * vz) / scale;
	return normalize(vec3(vx, vy, vz));
}

void vertex() {
	// Work in canonical [-1,1] space so the skew is independent of the mesh's
	// world size. h runs 0 (bottom) -> 1 (top); tz runs 0 (front +Z) -> 1 (back
	// -Z). The frustum scales X/Y by sf with depth; the shear leans X/Z with
	// height, centred on (h - 0.5) so the cube stays put. Default uniforms
	// (back_scale 1, shear 0) leave the cube untouched.
	vec3 c = VERTEX / cube_half_extent;
	float h = (c.y + 1.0) * 0.5;
	float tz = (1.0 - c.z) * 0.5;
	float sf = mix(1.0, back_scale, tz);
	c.x = c.x * sf + skew_shear.x * (h - 0.5);
	c.y = c.y * sf;
	c.z = c.z + skew_shear.y * (h - 0.5);
	skew_pos = c;                  // normalized skewed position (canonical units)
	VERTEX = c * cube_half_extent; // back to world units for rasterisation
}

void fragment() {
	// True view ray in model space: from the camera (brought into model space)
	// to the fragment's actual skewed position. MODEL_MATRIX is unaware of the
	// in-shader skew, so model space here IS canonical cube space.
	// Camera in canonical [-1,1] space to match skew_pos (model_ray is a
	// direction, so the shared 1/cube_half_extent scale cancels under normalize).
	vec3 model_camera = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz / cube_half_extent;
	vec3 d = skew_pos - model_camera;
	// Recover the canonical (pre-skew) position from the single skewed source,
	// so every term below is a continuous function of one varying. Mixing two
	// independently-interpolated varyings here would crease along each quad's
	// triangle diagonal (the frustum is non-affine) and the side faces zig-zag.
	// Frustum doesn't touch Z and shear doesn't touch Y, so the inversion is
	// explicit: scale comes straight from Z, then Y, then X.
	float tz = (1.0 - skew_pos.z) * 0.5;
	float sf = mix(1.0, back_scale, tz);
	float cy = skew_pos.y / sf;
	float cx = (skew_pos.x - skew_shear.x * cy * 0.5) / sf;
	float cz = skew_pos.z - skew_shear.y * cy * 0.5;
	// Unskew the view ray via the inverse Jacobian of the shear + frustum skew
	// (skewed = S(canonical), so d_canonical = J^-1 * d_skewed). At identity
	// (back_scale 1, shear 0) it reduces to the original ray. J is
	//   [ sf  p   r ]      sf = frustum scale at this fragment
	//   [ 0   sf  m ]      p,q = half the shear   r,m = frustum's depth cross-terms
	//   [ 0   q   1 ]
	float p = skew_shear.x * 0.5;
	float q = skew_shear.y * 0.5;
	float r = -cx * (back_scale - 1.0) * 0.5;
	float m = -cy * (back_scale - 1.0) * 0.5;
	// Recovery above must use the surface scale (sf); the rays sample the far
	// scale to cancel the first-order frustum drift over the extrusion depth.
	// The forward march always wants the far (back) scale. The back-ray cap heads
	// toward the face OPPOSITE the camera and wants that face's scale: viewing
	// from the front (camera +Z) the cap aims at the back face (back_scale),
	// viewing from behind it aims at the front face (scale 1). model_camera.z
	// gives that hemisphere directly, with no per-fragment feedback loop.
	vec3 model_ray = unskewRay(d, p, q, r, m, back_scale);
	float cap_scale = mix(1.0, back_scale, step(0.0, model_camera.z));
	vec3 cap_ray   = unskewRay(d, p, q, r, m, cap_scale);

	// Determine which face of the cube we are looking at
	ivec2 face = ivec2(UV / vec2(1.0 / 3.0, 1.0 / 2.0));
	// Make each face have similar UV
	vec2 adjusted_UV = mod(UV, vec2(1.0 / 3.0, 1.0 / 2.0)) * vec2(3.0, 2.0);

	// The frustum turns the four SIDE faces into trapezoids, whose interpolated
	// mesh UV kinks along each quad's triangle diagonal (a non-parallelogram
	// can't be UV-mapped affinely) -- that crease is the zig-zag. Front/back stay
	// square, so leave them on the mesh UV. For the side faces, rebuild
	// adjusted_UV from the crease-free canonical position recovered above. fc is
	// the value UVtoXY(adjusted_UV) would hold; inverting UVtoXY feeds the
	// existing per-face math unchanged. The per-face signs reproduce the original
	// unwrap -- flip a component if a given side face looks mirrored/inverted.
	// fc is the crease-free value UVtoXY(adjusted_UV) should hold. The axis
	// pairing (which two canonical axes lie in each face) is geometric; the
	// per-axis signs match the mesh's authored UV unwrap in the 3x2 atlas and
	// were pinned by testing. Note the mirror symmetry: +X/-X carry the same
	// depth-axis (U) orientation, while top/bottom differ by a V flip (they are
	// reflections of each other across the horizontal plane).
	if (face.y == 1 || face.x == 1) {
		vec2 fc;
		if (face.x == 1 && face.y == 0)      fc = vec2(-cz, cy);   // +X
		else if (face.x == 0 && face.y == 1) fc = vec2(cz, cy);    // -X
		else if (face.x == 1 && face.y == 1) fc = vec2(-cx, cz);   // +Y (top)
		else                                  fc = vec2(cx, cz);   // -Y (bottom)
		adjusted_UV = vec2((fc.x + 1.0) * 0.5, (1.0 - fc.y) * 0.5);
	}

	float zf = step(0.0, cap_ray.z); // 1 when looking from +Z, else 0 (cap geometry)
	vec2 xy = UVtoXY(adjusted_UV);

	// Z
	if (face.x == 0 && face.y == 0) {
		vec4 color = texture(Texture, frameUV(adjusted_UV));
		if (color.w >= image_alpha_cull && keep_image) {
			ALBEDO = color.rgb;
			ALPHA = color.w;
		} else {
			// Cast a ray from the focal point; colour the pixel with whatever
			// opaque pixel it collides with.
			imgPoint first_pixel = imgExtrude(adjusted_UV, model_ray.xy, false);
			ALBEDO = first_pixel.color.rgb;
			ALPHA = first_pixel.color.w;
			// Cap the extrusion using the opposite (back-face) hit.
			vec3 point = vec3(xy, 2.0);
			vec3 ray_intersection = PlaneLineIntersection(vec3(0.0), vec3(0.0, 0.0, 1.0), point, cap_ray);
			vec2 uv_point = XYtoUV(ray_intersection.xy) + vec2(0.0, 1.0);
			ALPHA *= frontBackCull(uv_point, first_pixel.uv.y, cap_ray.xy, cap_ray.y);
		}
	}
	// -Z
	else if (face.x == 2 && face.y == 0) {
		vec4 color = texture(Texture, flippedFrameUV(adjusted_UV));
		if (color.w >= image_alpha_cull && keep_image) {
			ALBEDO = color.rgb;
			ALPHA = color.w;
		} else {
			imgPoint first_pixel = imgExtrude(adjusted_UV, vec2(-model_ray.x, model_ray.y), true);
			ALBEDO = first_pixel.color.rgb;
			ALPHA = first_pixel.color.w;

			vec3 point = vec3(UVtoXY(vec2(-adjusted_UV.x, adjusted_UV.y)), -2.0);
			vec3 ray_intersection = PlaneLineIntersection(vec3(0.0), vec3(0.0, 0.0, 1.0), point, cap_ray);
			vec2 uv_point = XYtoUV(ray_intersection.xy) + vec2(1.0, 1.0);
			ALPHA *= frontBackCull(uv_point, first_pixel.uv.y, cap_ray.xy, cap_ray.y);
		}
	}
	// X
	else if (face.x == 1 && face.y == 0) {
		vec3 point = vec3(0.0, UVtoXY(adjusted_UV).yx);
		vec2 new_uv = sideForwardUV(point, vec3(1.0, 0.0, 0.0), vec2(0.5, 1.0), model_ray);
		vec4 img_color = imgExtrude(new_uv, model_ray.xy, false).color;
		ALBEDO = img_color.rgb;
		ALPHA = img_color.w;

		point = vec3(1.0, xy.y, mix(1.0 - xy.x, -1.0 - xy.x, zf));
		vec3 ray_intersection = PlaneLineIntersection(vec3(0.0), vec3(0.0, 0.0, 1.0), point, cap_ray);
		vec2 uv_point = XYtoUV(ray_intersection.xy) + vec2(0.0, 1.0);
		ALPHA *= sideCull(uv_point, cap_ray.xy);
	}
	// -X
	else if (face.x == 0 && face.y == 1) {
		vec3 point = vec3(0.0, UVtoXY(adjusted_UV).yx);
		vec2 new_uv = sideForwardUV(point, vec3(-1.0, 0.0, 0.0), vec2(-0.5, 1.0), model_ray);
		vec4 img_color = imgExtrude(new_uv, model_ray.xy, false).color;
		ALBEDO = img_color.rgb;
		ALPHA = img_color.w;

		point = vec3(-1.0, xy.y, mix(1.0 + xy.x, -1.0 + xy.x, zf));
		vec3 ray_intersection = PlaneLineIntersection(vec3(0.0), vec3(0.0, 0.0, 1.0), point, cap_ray);
		vec2 uv_point = XYtoUV(ray_intersection.xy) + vec2(0.0, 1.0);
		ALPHA *= sideCull(uv_point, cap_ray.xy);
	}
	// Y
	else if (face.x == 1 && face.y == 1) {
		vec2 rotated_UV = -xy;
		vec3 point = vec3(rotated_UV.x, 0.0, rotated_UV.y);
		vec2 new_uv = sideForwardUV(point, vec3(0.0, 1.0, 0.0), vec2(0.0, 0.5), model_ray);
		vec4 img_color = imgExtrude(new_uv, model_ray.xy, false).color;
		ALBEDO = img_color.rgb;
		ALPHA = img_color.w;

		vec2 fxy = UVtoXY(vec2(-adjusted_UV.x, adjusted_UV.y));
		point = vec3(fxy.x, 1.0, mix(fxy.y + 1.0, fxy.y - 1.0, zf));
		vec3 ray_intersection = PlaneLineIntersection(vec3(0.0), vec3(0.0, 0.0, 1.0), point, cap_ray);
		vec2 uv_point = XYtoUV(ray_intersection.xy) + vec2(1.0, 1.0);
		ALPHA *= sideCull(uv_point, cap_ray.xy);
	}
	// -Y
	else if (face.x == 2 && face.y == 1) {
		vec3 point = vec3(xy.x, 0.0, xy.y);
		vec2 new_uv = sideForwardUV(point, vec3(0.0, -1.0, 0.0), vec2(0.0, 1.5), model_ray);
		vec4 img_color = imgExtrude(new_uv, model_ray.xy, false).color;
		ALBEDO = img_color.rgb;
		ALPHA = img_color.w;

		point = vec3(xy.x, -1.0, mix(xy.y + 1.0, xy.y - 1.0, zf));
		vec3 ray_intersection = PlaneLineIntersection(vec3(0.0), vec3(0.0, 0.0, 1.0), point, cap_ray);
		vec2 uv_point = XYtoUV(ray_intersection.xy) + vec2(0.0, 1.0);
		ALPHA *= sideCull(uv_point, cap_ray.xy);
	}
}
