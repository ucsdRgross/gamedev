#pragma once

#include <godot_cpp/classes/fast_noise_lite.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

namespace godot {

// Native ports of the worldgen GDScript hot loops. Each method must stay
// BIT-IDENTICAL to its GDScript twin (see GDEXTENSION_PORT_HANDOFF.md):
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
};

} // namespace godot
