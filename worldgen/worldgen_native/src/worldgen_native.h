#pragma once

#include <godot_cpp/classes/fast_noise_lite.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_vector4_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace godot {

// Native ports of the worldgen GDScript hot loops. Each method must stay
// BIT-IDENTICAL to its GDScript twin (see ../START_HERE.md):
// GDScript does all arithmetic in 64-bit doubles and only narrows when
// storing into PackedFloat32Array elements, so every expression here loads
// elements to double, computes in double, and casts back to float on store.
class WorldgenNative : public RefCounted {
	GDCLASS(WorldgenNative, RefCounted)

protected:
	static void _bind_methods();

public:
	PackedFloat32Array fill_depressions(const PackedFloat32Array &height, int64_t w, int64_t h, double oth) const;
	PackedFloat32Array flow_accumulate_mfd(const PackedFloat32Array &filled, const PackedFloat32Array &seed,
			int64_t w, int64_t h, double oth, double exponent) const;
	Array dilate_lake(const PackedByteArray &mask, const PackedFloat32Array &surf, int64_t w, int64_t h, int64_t r) const;
	PackedFloat32Array box_blur(const PackedFloat32Array &src, int64_t w, int64_t h, int64_t passes) const;

	// --- Phase 2: GraphPlacement.MapField (graph_placement.gd) ---
	Array label_landmasses(const PackedByteArray &water, int64_t w, int64_t h) const;
	PackedFloat32Array map_distance_transform(const PackedByteArray &water, int64_t w, int64_t h, int64_t downscale) const;
	PackedVector2Array poisson_land_samples(const PackedInt32Array &labels, const PackedByteArray &blocked,
			int64_t w, int64_t h, int64_t main_label, bool confine_main,
			const PackedVector2Array &seed_pts, double r, int64_t seed_val) const;
	Array measure_land(const PackedInt32Array &labels, int64_t w, int64_t h, int64_t main_label, bool confine_main) const;
	PackedVector2Array jittered_land_samples(const PackedInt32Array &labels, const PackedByteArray &blocked,
			int64_t w, int64_t h, int64_t main_label, bool confine_main, double cs, int64_t seed_val) const;

	// --- Rivers residual: the leftover GDScript loops in rivers.gd execute() ---
	PackedFloat32Array river_downsample(const PackedFloat32Array &height, int64_t w, int64_t h,
			int64_t s, int64_t lw, int64_t lh) const;
	PackedFloat32Array river_seed_field(const PackedFloat32Array &lbase, const Ref<Image> &hum_img,
			int64_t w, int64_t h, int64_t s, int64_t lw, int64_t lh,
			double oth, double hum_bias, double elev_bias) const;
	PackedFloat32Array river_depth_stamp(const PackedFloat32Array &lbase, const PackedFloat32Array &accum,
			int64_t lw, int64_t lh, double oth, double thr, double carve_depth, double width_gain) const;
	Array river_lake_surfaces(const PackedFloat32Array &lbase, const PackedFloat32Array &lfilled,
			int64_t lw, int64_t lh, double oth, double lake_min_depth, int64_t lake_min_area,
			double lake_carve_depth) const;
	Array river_apply_water(const PackedFloat32Array &base, const PackedFloat32Array &wsurf_in,
			const PackedByteArray &is_lake_l, const PackedFloat32Array &lake_surf_l,
			const PackedFloat32Array &depth_l, int64_t w, int64_t h, int64_t s,
			int64_t lw, int64_t lh, double oth) const;

	// --- NoiseBake: the hand-rolled multifractal octave loop (noise_baker.gd _multi) ---
	Ref<Image> bake_multifractal(const Ref<FastNoiseLite> &noise, int64_t w, int64_t h,
			int64_t octaves, double gain, double lacunarity, bool ridged, double offset) const;

	// --- Phase 3: BiomeRegions.build_cells (biome_regions.gd) ---
	Dictionary biome_build_cells(const PackedFloat32Array &heightb, const PackedByteArray &water,
			const PackedInt32Array &labels, const PackedVector2Array &samples,
			const PackedInt32Array &sample_label, const PackedByteArray &warp_bytes,
			const PackedByteArray &humid_bytes, int64_t w, int64_t h,
			double warp_amp, double height_cost) const;

	// --- Phase 4A: GraphDetail._route (graph_detail.gd) — A* edge routing ---
	PackedVector2Array route_edge(const PackedFloat32Array &height, const PackedByteArray &water,
			int64_t w, int64_t h, const Vector2 &a, const Vector2 &b, bool water_mode,
			double target_h, int64_t ds, const Dictionary &opts, const Dictionary &occ,
			const Dictionary &node_occ, const Dictionary &excl) const;

	// --- Phase 4B: WorldMapPainter._paint (map_painter.gd) — per-pixel classifier ---
	PackedByteArray paint_map(const PackedFloat32Array &height, const PackedFloat32Array &wsurf,
			const PackedByteArray &rmask, const PackedByteArray &lmask, const PackedInt32Array &bbuf,
			int64_t w, int64_t h, double oth, bool paint_land, bool paint_water,
			bool include_ocean, const Dictionary &pal) const;

	// --- Determinism: CPU twins of the GPU heightmap shaders (see
	// ../START_HERE.md "Determinism"). These do NOT reproduce the GPU bit-for-bit --
	// that is impossible across vendors, which is the whole problem. They are
	// self-consistent on every machine, which is the actual requirement.
	PackedFloat32Array terrain_landmass(const PackedByteArray &noise_l8,
			const PackedByteArray &warpx_l8, const PackedByteArray &warpy_l8,
			int64_t w, int64_t h, double island_radius, double land_contrast,
			double edge_jag, double island_falloff) const;
	// Twin of tectonic_blueprint + tectonic_deformation in ONE pass: both shaders
	// recompute the same warped-Voronoi nearest plates, so the ids the blueprint
	// packs into blue and the height the deform pass writes fall out together.
	// Returns [PackedFloat32Array height, PackedInt32Array plate_ids].
	Array terrain_tectonics(const PackedFloat32Array &height,
			const PackedByteArray &warpx_l8, const PackedByteArray &warpy_l8,
			const PackedVector4Array &plate_data, const PackedFloat32Array &plate_is_land,
			int64_t w, int64_t h, int64_t plate_count, double warp_strength, double map_px,
			double drift_intensity, double plate_move, double tectonic_band,
			double land_rift_damping, double tectonic_height_cap) const;
	PackedFloat32Array terrain_peaks(const PackedFloat32Array &height,
			const PackedByteArray &ridge_l8, const PackedByteArray &billow_l8,
			const PackedByteArray &detail_l8, const PackedByteArray &warpx_l8,
			const PackedByteArray &warpy_l8, int64_t w, int64_t h,
			double ocean_threshold, double boundary_radius, double edge_jag,
			double peak_uplift, double highland_range, double peak_detail_strength,
			double peak_billow_strength, double peak_height_cap,
			double detail_min_elevation, double detail_falloff,
			double boundary_falloff, double lowland_flatten) const;
	// Returns [PackedFloat32Array eroded_height, PackedByteArray field_l8]; the
	// second is the shader's output_mode 1 (0.5 + 0.5*ero) for the debug viewer.
	Array terrain_erosion(const PackedFloat32Array &height, int64_t w, int64_t h,
			int64_t octaves, double amplitude, double frequency, double gain,
			double lacunarity, double branch_angle, double ridge_rounding,
			double gully_rounding, double detail, double steepness_scale,
			double min_elevation, double elevation_falloff) const;
};

} // namespace godot
