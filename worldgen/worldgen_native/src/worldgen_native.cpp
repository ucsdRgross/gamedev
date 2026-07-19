#include "worldgen_native.h"

#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/vector4.hpp>
#include <godot_cpp/variant/packed_vector4_array.hpp>

#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>
#include <thread>
#include <vector>

using namespace godot;

// GDScript maxf/minf semantics: (a > b) ? a : b, all in double.
static inline double gd_maxf(double a, double b) { return (a > b) ? a : b; }
static inline double gd_minf(double a, double b) { return (a < b) ? a : b; }

// Priority-Flood (+epsilon) depression fill, bucket-queue variant.
// Twin of GenerationStep.fill_depressions in world_gen_step.gd.
PackedFloat32Array WorldgenNative::fill_depressions(const PackedFloat32Array &height, int64_t w, int64_t h, double oth) const {
	const int64_t n = w * h;
	const float *H = height.ptr();

	PackedFloat32Array Wout;
	Wout.resize(n);
	float *W = Wout.ptrw();
	for (int64_t i = 0; i < n; i++) {
		W[i] = std::numeric_limits<float>::infinity();
	}
	std::vector<uint8_t> closed(n, 0);
	constexpr double EPS = 0.00001;
	constexpr int FILL_BUCKETS = 1024;

	double hmin = std::numeric_limits<double>::infinity();
	double hmax = -std::numeric_limits<double>::infinity();
	for (int64_t i = 0; i < n; i++) {
		const double v = (double)H[i];
		if (v < hmin) hmin = v;
		if (v > hmax) hmax = v;
	}
	const double span = gd_maxf(1e-6, hmax - hmin);
	const double scale = (double)(FILL_BUCKETS - 1) / span;

	std::vector<std::vector<int32_t>> buckets(FILL_BUCKETS);

	// Seed the open boundary: map edges and every ocean cell.
	for (int64_t y = 0; y < h; y++) {
		for (int64_t x = 0; x < w; x++) {
			const int64_t i = (y * w) + x;
			if (x == 0 || y == 0 || x == w - 1 || y == h - 1 || (double)H[i] < oth) {
				W[i] = H[i];
				closed[i] = 1;
				const int64_t lv = (int64_t)(((double)H[i] - hmin) * scale);
				buckets[lv].push_back((int32_t)i);
			}
		}
	}

	int cur = 0;
	size_t cursor = 0;
	while (cur < FILL_BUCKETS) {
		if (cursor >= buckets[cur].size()) {
			cur += 1;
			cursor = 0;
			continue;
		}
		const int32_t ci = buckets[cur][cursor];
		cursor += 1;
		const int64_t cx = ci % w;
		const int64_t cy = ci / w;
		for (int oy = -1; oy <= 1; oy++) {
			for (int ox = -1; ox <= 1; ox++) {
				if (ox == 0 && oy == 0) continue;
				const int64_t nx = cx + ox;
				const int64_t ny = cy + oy;
				if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
				const int64_t ni = (ny * w) + nx;
				if (closed[ni] == 1) continue;
				const double wn = gd_maxf((double)H[ni], (double)W[ci] + EPS);
				W[ni] = (float)wn;
				closed[ni] = 1;
				const int64_t lv = (int64_t)gd_minf((double)(int64_t)((wn - hmin) * scale), (double)(FILL_BUCKETS - 1));
				buckets[lv].push_back((int32_t)ni);
			}
		}
	}
	return Wout;
}

// Multiple-Flow-Direction accumulation (Kahn topological pass).
// Twin of GenerationStep.flow_accumulate_mfd in world_gen_step.gd.
PackedFloat32Array WorldgenNative::flow_accumulate_mfd(const PackedFloat32Array &filled, const PackedFloat32Array &seed,
		int64_t w, int64_t h, double oth, double exponent) const {
	const int64_t n = w * h;
	const float *F = filled.ptr();

	PackedFloat32Array accum_out = seed.duplicate();
	float *accum = accum_out.ptrw();

	std::vector<int32_t> et(n * 8);
	std::vector<float> ew(n * 8);
	std::vector<int32_t> ec(n, 0);
	std::vector<int32_t> indeg(n, 0);

	for (int64_t y = 0; y < h; y++) {
		for (int64_t x = 0; x < w; x++) {
			const int64_t i = (y * w) + x;
			if ((double)F[i] < oth) continue; // ocean: sink
			const double hi = (double)F[i];
			const int64_t base = i * 8;
			int k = 0;
			double sum_w = 0.0;
			for (int oy = -1; oy <= 1; oy++) {
				for (int ox = -1; ox <= 1; ox++) {
					if (ox == 0 && oy == 0) continue;
					const int64_t nx = x + ox;
					const int64_t ny = y + oy;
					if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
					const int64_t ni = (ny * w) + nx;
					const double drop = hi - (double)F[ni];
					if (drop <= 0.0) continue;
					et[base + k] = (int32_t)ni;
					ew[base + k] = (float)std::pow(drop, exponent);
					sum_w += (double)ew[base + k];
					k += 1;
				}
			}
			ec[i] = k;
			if (sum_w > 0.0) {
				for (int j = 0; j < k; j++) {
					ew[base + j] = (float)((double)ew[base + j] / sum_w);
					indeg[et[base + j]] += 1;
				}
			}
		}
	}

	std::vector<int32_t> queue(n);
	int64_t qh = 0;
	int64_t qt = 0;
	for (int64_t i = 0; i < n; i++) {
		if (indeg[i] == 0) {
			queue[qt] = (int32_t)i;
			qt += 1;
		}
	}
	while (qh < qt) {
		const int32_t c = queue[qh];
		qh += 1;
		const int64_t base = (int64_t)c * 8;
		const double ac = (double)accum[c];
		for (int j = 0; j < ec[c]; j++) {
			const int32_t ch = et[base + j];
			accum[ch] = (float)((double)accum[ch] + ac * (double)ew[base + j]);
			indeg[ch] -= 1;
			if (indeg[ch] == 0) {
				queue[qt] = ch;
				qt += 1;
			}
		}
	}
	return accum_out;
}

// Twin of StepRivers._dilate_lake in rivers.gd. Returns [mask, surface].
Array WorldgenNative::dilate_lake(const PackedByteArray &mask_in, const PackedFloat32Array &surf_in, int64_t w, int64_t h, int64_t r) const {
	PackedByteArray mask = mask_in.duplicate();
	PackedFloat32Array surf = surf_in.duplicate();
	uint8_t *M = mask.ptrw();
	float *S = surf.ptrw();

	std::vector<int32_t> added;
	for (int64_t it = 0; it < r; it++) {
		added.clear();
		for (int64_t y = 0; y < h; y++) {
			for (int64_t x = 0; x < w; x++) {
				const int64_t i = (y * w) + x;
				if (M[i] == 1) continue;
				double s = -1.0;
				for (int oy = -1; oy <= 1; oy++) {
					for (int ox = -1; ox <= 1; ox++) {
						if (ox == 0 && oy == 0) continue;
						const int64_t nx = x + ox;
						const int64_t ny = y + oy;
						if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
						const int64_t ni = (ny * w) + nx;
						if (M[ni] == 1) s = gd_maxf(s, (double)S[ni]);
					}
				}
				if (s >= 0.0) {
					added.push_back((int32_t)i);
					S[i] = (float)s;
				}
			}
		}
		for (const int32_t i : added) {
			M[i] = 1;
		}
	}
	Array out;
	out.append(mask);
	out.append(surf);
	return out;
}

// Twin of StepRivers._box_blur in rivers.gd.
PackedFloat32Array WorldgenNative::box_blur(const PackedFloat32Array &src, int64_t w, int64_t h, int64_t passes) const {
	PackedFloat32Array a = src;
	for (int64_t p = 0; p < passes; p++) {
		PackedFloat32Array out = a.duplicate();
		const float *A = a.ptr();
		float *O = out.ptrw();
		for (int64_t y = 0; y < h; y++) {
			for (int64_t x = 0; x < w; x++) {
				double sum = 0.0;
				int n = 0;
				for (int oy = -1; oy <= 1; oy++) {
					for (int ox = -1; ox <= 1; ox++) {
						const int64_t nx = x + ox;
						const int64_t ny = y + oy;
						if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
						sum += (double)A[(ny * w) + nx];
						n += 1;
					}
				}
				O[(y * w) + x] = (float)(sum / (double)n);
			}
		}
		a = out;
	}
	return a;
}

// --- Phase 2: GraphPlacement.MapField twins (graph_placement.gd) --------------

// Twin of MapField._label_landmasses. Returns [labels: PackedInt32Array,
// counts: PackedInt32Array (index = landmass id), seeds: PackedVector2Array].
// The GDScript wrapper rebuilds sizes / label_seed / main_label / total_land
// from these with the original loop so tie-breaks stay identical.
Array WorldgenNative::label_landmasses(const PackedByteArray &water, int64_t w, int64_t h) const {
	const int64_t n = w * h;
	const uint8_t *WA = water.ptr();

	PackedInt32Array labels_out;
	labels_out.resize(n);
	int32_t *L = labels_out.ptrw();
	for (int64_t i = 0; i < n; i++) {
		L[i] = -1;
	}
	PackedInt32Array counts;
	PackedVector2Array seeds;

	static const int OFF[4][2] = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } };
	std::vector<int32_t> stack;
	int32_t cur = 0;
	for (int64_t sy = 0; sy < h; sy++) {
		for (int64_t sx = 0; sx < w; sx++) {
			const int64_t si = sy * w + sx;
			if (WA[si] == 1 || L[si] != -1) continue;
			int64_t cnt = 0;
			stack.clear();
			stack.push_back((int32_t)si);
			L[si] = cur;
			seeds.push_back(Vector2((real_t)sx, (real_t)sy));
			while (!stack.empty()) {
				const int32_t idx = stack.back();
				stack.pop_back();
				cnt += 1;
				const int64_t x = idx % w;
				const int64_t y = idx / w;
				for (int k = 0; k < 4; k++) {
					const int64_t nx = x + OFF[k][0];
					const int64_t ny = y + OFF[k][1];
					if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
					const int64_t ni = ny * w + nx;
					if (WA[ni] == 0 && L[ni] == -1) {
						L[ni] = cur;
						stack.push_back((int32_t)ni);
					}
				}
			}
			counts.push_back((int32_t)cnt);
			cur += 1;
		}
	}
	Array out;
	out.append(labels_out);
	out.append(counts);
	out.append(seeds);
	return out;
}

// Twin of MapField._build_distance_transform + _chamfer. Returns the signed dt
// grid; the wrapper computes _dtw/_dth with the same formulas.
PackedFloat32Array WorldgenNative::map_distance_transform(const PackedByteArray &water, int64_t w, int64_t h, int64_t downscale) const {
	const int64_t ds = (downscale > 1) ? downscale : 1;
	const int64_t dtw = (int64_t)std::ceil((double)w / (double)ds);
	const int64_t dth = (int64_t)std::ceil((double)h / (double)ds);
	const int64_t n = dtw * dth;
	const uint8_t *WA = water.ptr();

	std::vector<float> to_water(n), to_land(n);
	const double BIG = 1e9;
	for (int64_t gy = 0; gy < dth; gy++) {
		for (int64_t gx = 0; gx < dtw; gx++) {
			const int64_t i = gy * dtw + gx;
			const int64_t sy = (gy * ds < h - 1) ? gy * ds : h - 1;
			const int64_t sx = (gx * ds < w - 1) ? gx * ds : w - 1;
			const bool landcell = WA[sy * w + sx] == 0;
			to_water[i] = landcell ? (float)BIG : 0.0f;
			to_land[i] = landcell ? 0.0f : (float)BIG;
		}
	}
	// Two-pass chamfer, arithmetic in double, store float (matches _chamfer).
	const double ORTH = 1.0;
	const double DIAG = 1.41421356;
	auto chamfer = [&](std::vector<float> &d) {
		for (int64_t gy = 0; gy < dth; gy++) { // forward
			for (int64_t gx = 0; gx < dtw; gx++) {
				const int64_t i = gy * dtw + gx;
				double m = (double)d[i];
				if (gx > 0) m = gd_minf(m, (double)d[i - 1] + ORTH);
				if (gy > 0) m = gd_minf(m, (double)d[i - dtw] + ORTH);
				if (gx > 0 && gy > 0) m = gd_minf(m, (double)d[i - dtw - 1] + DIAG);
				if (gx < dtw - 1 && gy > 0) m = gd_minf(m, (double)d[i - dtw + 1] + DIAG);
				d[i] = (float)m;
			}
		}
		for (int64_t gy = dth - 1; gy >= 0; gy--) { // backward
			for (int64_t gx = dtw - 1; gx >= 0; gx--) {
				const int64_t i = gy * dtw + gx;
				double m = (double)d[i];
				if (gx < dtw - 1) m = gd_minf(m, (double)d[i + 1] + ORTH);
				if (gy < dth - 1) m = gd_minf(m, (double)d[i + dtw] + ORTH);
				if (gx < dtw - 1 && gy < dth - 1) m = gd_minf(m, (double)d[i + dtw + 1] + DIAG);
				if (gx > 0 && gy < dth - 1) m = gd_minf(m, (double)d[i + dtw - 1] + DIAG);
				d[i] = (float)m;
			}
		}
	};
	chamfer(to_water);
	chamfer(to_land);

	PackedFloat32Array dt_out;
	dt_out.resize(n);
	float *DT = dt_out.ptrw();
	for (int64_t gy = 0; gy < dth; gy++) {
		for (int64_t gx = 0; gx < dtw; gx++) {
			const int64_t i = gy * dtw + gx;
			const int64_t sy = (gy * ds < h - 1) ? gy * ds : h - 1;
			const int64_t sx = (gx * ds < w - 1) ? gx * ds : w - 1;
			const bool landcell = WA[sy * w + sx] == 0;
			const double v = landcell ? (double)to_water[i] : -(double)to_land[i];
			DT[i] = (float)(v * (double)ds);
		}
	}
	return dt_out;
}

// Shared MapField cell tests. Vector2 components are real_t (float) exactly as
// in GDScript; int(x) truncates toward zero (plain C cast on in-range values).
namespace {

struct FieldView {
	const int32_t *labels;
	const uint8_t *blocked;
	int64_t w, h;
	int64_t main_label;
	bool confine_main;

	bool in_bounds(const Vector2 &p) const {
		return (double)p.x >= 0.0 && (double)p.y >= 0.0 && (double)p.x < (double)w && (double)p.y < (double)h;
	}
	int64_t label_at(const Vector2 &p) const {
		if (!in_bounds(p)) return -1;
		return labels[((int64_t)p.y * w) + (int64_t)p.x];
	}
	bool in_domain(const Vector2 &p) const {
		if (!in_bounds(p)) return false;
		const int64_t l = labels[((int64_t)p.y * w) + (int64_t)p.x];
		return confine_main ? l == main_label : l >= 0;
	}
	bool blocked_at(const Vector2 &p) const {
		int64_t x = (int64_t)p.x;
		if (x < 0) x = 0; else if (x > w - 1) x = w - 1;
		int64_t y = (int64_t)p.y;
		if (y < 0) y = 0; else if (y > h - 1) y = h - 1;
		return blocked[(y * w) + x] == 1;
	}
	// Twin of MapField._unblocked_near.
	Vector2 unblocked_near(const Vector2 &p, double max_r) const {
		const int64_t lab = label_at(p);
		const int64_t rings = (int64_t)std::ceil(max_r);
		for (int64_t ring = 1; ring <= rings; ring++) {
			for (int64_t dy = -ring; dy <= ring; dy++) {
				for (int64_t dx = -ring; dx <= ring; dx++) {
					const int64_t adx = dx < 0 ? -dx : dx;
					const int64_t ady = dy < 0 ? -dy : dy;
					if ((adx > ady ? adx : ady) != ring) continue;
					const Vector2 q = p + Vector2((real_t)dx, (real_t)dy);
					if (in_bounds(q) && label_at(q) == lab && !blocked_at(q)) return q;
				}
			}
		}
		return p;
	}
};

} // namespace

// Twin of MapField._poisson_samples (Bridson). Uses the engine's own
// RandomNumberGenerator so the random sequence is identical to GDScript's.
// seed_pts = label_seed.values() in label-id order.
PackedVector2Array WorldgenNative::poisson_land_samples(const PackedInt32Array &labels, const PackedByteArray &blocked,
		int64_t w, int64_t h, int64_t main_label, bool confine_main,
		const PackedVector2Array &seed_pts, double r, int64_t seed_val) const {
	const FieldView F{ labels.ptr(), blocked.ptr(), w, h, main_label, confine_main };
	constexpr double TAU_D = 6.2831853071795864769252867666; // GDScript TAU

	Ref<RandomNumberGenerator> rng;
	rng.instantiate();
	rng->set_seed((uint64_t)(seed_val * 100069));

	const double cell = r / std::sqrt(2.0);
	const int64_t gw = (int64_t)std::ceil((double)w / cell);
	const int64_t gh = (int64_t)std::ceil((double)h / cell);
	std::vector<int32_t> grid(gw * gh, -1);
	std::vector<Vector2> samples;
	std::vector<int32_t> active;

	auto poisson_ok = [&](const Vector2 &p) -> bool {
		const int64_t cx = (int64_t)((double)p.x / cell);
		const int64_t cy = (int64_t)((double)p.y / cell);
		for (int64_t dy = -2; dy <= 2; dy++) {
			for (int64_t dx = -2; dx <= 2; dx++) {
				const int64_t nx = cx + dx;
				const int64_t ny = cy + dy;
				if (nx < 0 || ny < 0 || nx >= gw || ny >= gh) continue;
				const int32_t si = grid[ny * gw + nx];
				if (si >= 0 && (double)samples[si].distance_to(p) < r) return false;
			}
		}
		return true;
	};
	auto add_poisson = [&](const Vector2 &p) {
		const int32_t idx = (int32_t)samples.size();
		samples.push_back(p);
		active.push_back(idx);
		grid[(int64_t)((double)p.y / cell) * gw + (int64_t)((double)p.x / cell)] = idx;
	};

	const int64_t nseeds = seed_pts.size();
	for (int64_t s = 0; s < nseeds; s++) {
		Vector2 seed_pt = seed_pts[s];
		if (F.blocked_at(seed_pt)) seed_pt = F.unblocked_near(seed_pt, r);
		if (F.in_domain(seed_pt) && !F.blocked_at(seed_pt) && poisson_ok(seed_pt)) add_poisson(seed_pt);
	}
	if (!active.empty()) {
		while (!active.empty()) {
			const int32_t ai = rng->randi_range(0, (int32_t)active.size() - 1);
			const Vector2 center = samples[active[ai]];
			bool found = false;
			for (int k = 0; k < 30; k++) {
				const double ang = (double)rng->randf() * TAU_D;
				const double rad = r * (1.0 + (double)rng->randf());
				const Vector2 cand = center + Vector2((real_t)std::cos(ang), (real_t)std::sin(ang)) * (real_t)rad;
				if (!F.in_domain(cand) || F.blocked_at(cand)) continue;
				if (poisson_ok(cand)) {
					add_poisson(cand);
					found = true;
					break;
				}
			}
			if (!found) active.erase(active.begin() + ai);
		}
	}

	PackedVector2Array out;
	out.resize(samples.size());
	Vector2 *O = out.ptrw();
	for (size_t i = 0; i < samples.size(); i++) {
		O[i] = samples[i];
	}
	return out;
}

// Twin of MapField._measure_land's scan loop. Returns [lo, hi, sum, n]; the
// wrapper keeps the n==0 branch and the centroid division. Vector2 accumulation
// stays in float32 exactly as GDScript's `sum += Vector2(x, y)`.
Array WorldgenNative::measure_land(const PackedInt32Array &labels, int64_t w, int64_t h, int64_t main_label, bool confine_main) const {
	const int32_t *L = labels.ptr();
	Vector2 lo((real_t)w, (real_t)h);
	Vector2 hi(0.0f, 0.0f);
	Vector2 sum(0.0f, 0.0f);
	int64_t n = 0;
	for (int64_t y = 0; y < h; y++) {
		for (int64_t x = 0; x < w; x++) {
			const int32_t l = L[(y * w) + x];
			if (!(confine_main ? l == main_label : l >= 0)) continue;
			lo.x = (real_t)gd_minf((double)lo.x, (double)x);
			lo.y = (real_t)gd_minf((double)lo.y, (double)y);
			hi.x = (real_t)gd_maxf((double)hi.x, (double)x);
			hi.y = (real_t)gd_maxf((double)hi.y, (double)y);
			sum += Vector2((real_t)x, (real_t)y);
			n += 1;
		}
	}
	Array out;
	out.append(lo);
	out.append(hi);
	out.append(sum);
	out.append(n);
	return out;
}

// Twin of MapField._jittered_samples.
PackedVector2Array WorldgenNative::jittered_land_samples(const PackedInt32Array &labels, const PackedByteArray &blocked,
		int64_t w, int64_t h, int64_t main_label, bool confine_main, double cs, int64_t seed_val) const {
	const FieldView F{ labels.ptr(), blocked.ptr(), w, h, main_label, confine_main };

	Ref<RandomNumberGenerator> rng;
	rng.instantiate();
	rng->set_seed((uint64_t)(seed_val * 100069));

	const int64_t gx = (int64_t)std::ceil((double)w / cs);
	const int64_t gy = (int64_t)std::ceil((double)h / cs);
	PackedVector2Array out;
	for (int64_t cy = 0; cy < gy; cy++) {
		for (int64_t cx = 0; cx < gx; cx++) {
			const double px = ((double)cx + (double)rng->randf()) * cs;
			const double py = ((double)cy + (double)rng->randf()) * cs;
			const Vector2 p((real_t)px, (real_t)py);
			if (F.in_domain(p) && !F.blocked_at(p)) out.push_back(p);
		}
	}
	return out;
}

// GDScript clampf semantics.
static inline double gd_clampf(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }

// --- Rivers residual: twins of the loops in StepRivers.execute() -------------

// Point-sample downsample of the full-res heightmap to the hydrology grid.
PackedFloat32Array WorldgenNative::river_downsample(const PackedFloat32Array &height, int64_t w, int64_t h,
		int64_t s, int64_t lw, int64_t lh) const {
	const float *H = height.ptr();
	PackedFloat32Array out;
	out.resize(lw * lh);
	float *O = out.ptrw();
	for (int64_t ly = 0; ly < lh; ly++) {
		for (int64_t lx = 0; lx < lw; lx++) {
			O[(ly * lw) + lx] = H[((ly * s) * w) + (lx * s)];
		}
	}
	return out;
}

// Rainfall seed field: wet^bias * elev^bias + 0.001 per land cell. Humidity is
// read via the engine's own Image.get_pixel so the value matches GDScript's.
PackedFloat32Array WorldgenNative::river_seed_field(const PackedFloat32Array &lbase, const Ref<Image> &hum_img,
		int64_t w, int64_t h, int64_t s, int64_t lw, int64_t lh,
		double oth, double hum_bias, double elev_bias) const {
	const float *B = lbase.ptr();
	const double inv_sea = 1.0 / gd_maxf(1e-3, 1.0 - oth);
	PackedFloat32Array out;
	out.resize(lw * lh);
	float *O = out.ptrw();
	Image *img = const_cast<Image *>(hum_img.ptr());
	for (int64_t ly = 0; ly < lh; ly++) {
		for (int64_t lx = 0; lx < lw; lx++) {
			const int64_t i = (ly * lw) + lx;
			if ((double)B[i] < oth) continue; // ocean is a sink (seed stays 0)
			const int64_t px = (lx * s < w - 1) ? lx * s : w - 1;
			const int64_t py = (ly * s < h - 1) ? ly * s : h - 1;
			const double wet = (double)img->get_pixel((int32_t)px, (int32_t)py).r;
			const double elev = gd_clampf(((double)B[i] - oth) * inv_sea, 0.0, 1.0);
			O[i] = (float)(std::pow(wet, hum_bias) * std::pow(elev, elev_bias) + 0.001);
		}
	}
	return out;
}

// River depth map with sqrt(discharge) widening (disc stamping).
PackedFloat32Array WorldgenNative::river_depth_stamp(const PackedFloat32Array &lbase, const PackedFloat32Array &accum,
		int64_t lw, int64_t lh, double oth, double thr, double carve_depth, double width_gain) const {
	const int64_t ln = lw * lh;
	const float *B = lbase.ptr();
	const float *A = accum.ptr();

	double max_accum = 0.0;
	for (int64_t i = 0; i < ln; i++) {
		max_accum = gd_maxf(max_accum, (double)A[i]);
	}
	double lmax = std::log(1.0 + max_accum);
	if (lmax <= 0.0) lmax = 1.0;
	const double accum_span = gd_maxf(1e-6, max_accum - thr);

	PackedFloat32Array out;
	out.resize(ln); // zero-initialized
	float *D = out.ptrw();
	for (int64_t ly = 0; ly < lh; ly++) {
		for (int64_t lx = 0; lx < lw; lx++) {
			const int64_t i = (ly * lw) + lx;
			if ((double)B[i] < oth || (double)A[i] < thr) continue;
			const double an = std::log(1.0 + (double)A[i]) / lmax;
			const double carve = carve_depth * an;
			const double wfrac = std::sqrt(gd_clampf(((double)A[i] - thr) / accum_span, 0.0, 1.0));
			const int64_t rad = (int64_t)(width_gain * wfrac);
			for (int64_t oy = -rad; oy <= rad; oy++) {
				for (int64_t ox = -rad; ox <= rad; ox++) {
					if ((ox * ox) + (oy * oy) > rad * rad) continue;
					const int64_t nx = lx + ox;
					const int64_t ny = ly + oy;
					if (nx < 0 || ny < 0 || nx >= lw || ny >= lh) continue;
					const int64_t ni = (ny * lw) + nx;
					if ((double)B[ni] >= oth) D[ni] = (float)gd_maxf((double)D[ni], carve);
				}
			}
		}
	}
	return out;
}

// Lake mask + flat per-basin surfaces at spill level. Returns [mask, surface].
Array WorldgenNative::river_lake_surfaces(const PackedFloat32Array &lbase, const PackedFloat32Array &lfilled,
		int64_t lw, int64_t lh, double oth, double lake_min_depth, int64_t lake_min_area,
		double lake_carve_depth) const {
	const int64_t ln = lw * lh;
	const float *B = lbase.ptr();
	const float *F = lfilled.ptr();

	PackedByteArray mask;
	mask.resize(ln); // zeroed
	uint8_t *M = mask.ptrw();
	for (int64_t i = 0; i < ln; i++) {
		if ((double)B[i] >= oth && (double)F[i] - (double)B[i] > lake_min_depth) M[i] = 1;
	}

	PackedFloat32Array surf;
	surf.resize(ln); // zeroed
	float *S = surf.ptrw();
	std::vector<int32_t> comp(ln, -1);
	std::vector<int32_t> members, stack;
	for (int64_t start = 0; start < ln; start++) {
		if (M[start] == 0 || comp[start] != -1) continue;
		members.clear();
		stack.clear();
		stack.push_back((int32_t)start);
		comp[start] = (int32_t)start;
		double spill = (double)F[start];
		while (!stack.empty()) {
			const int32_t c = stack.back();
			stack.pop_back();
			members.push_back(c);
			spill = gd_minf(spill, (double)F[c]);
			const int64_t cx = c % lw;
			const int64_t cy = c / lw;
			for (int oy = -1; oy <= 1; oy++) {
				for (int ox = -1; ox <= 1; ox++) {
					if (ox == 0 && oy == 0) continue;
					const int64_t nx = cx + ox;
					const int64_t ny = cy + oy;
					if (nx < 0 || ny < 0 || nx >= lw || ny >= lh) continue;
					const int64_t ni = (ny * lw) + nx;
					if (M[ni] == 1 && comp[ni] == -1) {
						comp[ni] = (int32_t)start;
						stack.push_back((int32_t)ni);
					}
				}
			}
		}
		if ((int64_t)members.size() < lake_min_area) {
			for (const int32_t m : members) {
				M[m] = 0;
			}
			continue;
		}
		const double sv = gd_maxf(spill - lake_carve_depth, oth + 0.004);
		for (const int32_t m : members) {
			S[m] = (float)sv;
		}
	}
	Array out;
	out.append(mask);
	out.append(surf);
	return out;
}

// Full-res apply: carve rivers into the bed, record water tops + node lists +
// presence masks. Returns [height, water_surface, river_nodes, lake_nodes, rmask, lmask].
Array WorldgenNative::river_apply_water(const PackedFloat32Array &base, const PackedFloat32Array &wsurf_in,
		const PackedByteArray &is_lake_l, const PackedFloat32Array &lake_surf_l,
		const PackedFloat32Array &depth_l, int64_t w, int64_t h, int64_t s,
		int64_t lw, int64_t lh, double oth) const {
	const float *BS = base.ptr();
	const uint8_t *LK = is_lake_l.ptr();
	const float *LS = lake_surf_l.ptr();
	const float *DL = depth_l.ptr();

	PackedFloat32Array height = base.duplicate();
	PackedFloat32Array wsurf = wsurf_in.duplicate();
	float *HT = height.ptrw();
	float *WS = wsurf.ptrw();
	PackedByteArray rmask, lmask;
	rmask.resize(w * h);
	lmask.resize(w * h);
	uint8_t *RM = rmask.ptrw();
	uint8_t *LM = lmask.ptrw();
	std::vector<int32_t> river_nodes, lake_nodes;

	for (int64_t y = 0; y < h; y++) {
		const int64_t lyv = (y / s < lh - 1) ? y / s : lh - 1;
		for (int64_t x = 0; x < w; x++) {
			const int64_t fi = (y * w) + x;
			const int64_t lc = (lyv * lw) + ((x / s < lw - 1) ? x / s : lw - 1);
			if (LK[lc] == 1) {
				// Keep the real lake floor as the bed; water sits at the spill surface.
				WS[fi] = LS[lc];
				lake_nodes.push_back((int32_t)fi);
				LM[fi] = 1;
			} else if ((double)DL[lc] > 0.0) {
				// Carve the channel; water fills it back up to (near) original grade.
				HT[fi] = (float)gd_maxf((double)BS[fi] - (double)DL[lc], oth + 0.004);
				WS[fi] = BS[fi];
				river_nodes.push_back((int32_t)fi);
				RM[fi] = 1;
			}
		}
	}

	PackedInt32Array rn, lnodes;
	rn.resize(river_nodes.size());
	memcpy(rn.ptrw(), river_nodes.data(), river_nodes.size() * sizeof(int32_t));
	lnodes.resize(lake_nodes.size());
	memcpy(lnodes.ptrw(), lake_nodes.data(), lake_nodes.size() * sizeof(int32_t));

	Array out;
	out.append(height);
	out.append(wsurf);
	out.append(rn);
	out.append(lnodes);
	out.append(rmask);
	out.append(lmask);
	return out;
}

// --- NoiseBake: twin of NoiseBaker._multi's octave/normalize loops -----------
// The FastNoiseLite arrives fully configured from GDScript (seed, type,
// frequency, FRACTAL_NONE, domain warp), and we call the ENGINE's own
// get_noise_2d, so the noise values are identical by construction — this port
// only removes the per-pixel GDScript overhead.
Ref<Image> WorldgenNative::bake_multifractal(const Ref<FastNoiseLite> &noise, int64_t w, int64_t h,
		int64_t octaves, double gain, double lacunarity, bool ridged, double offset) const {
	FastNoiseLite *n = const_cast<FastNoiseLite *>(noise.ptr());
	const int64_t np = w * h;
	std::vector<float> vals(np);
	double vmin = std::numeric_limits<double>::infinity();
	double vmax = -std::numeric_limits<double>::infinity();
	for (int64_t y = 0; y < h; y++) {
		for (int64_t x = 0; x < w; x++) {
			double freq_mul = 1.0;
			double amp = 1.0;
			double weight = 1.0;
			double sum = 0.0;
			for (int64_t o = 0; o < octaves; o++) {
				const double nv = (double)n->get_noise_2d((double)x * freq_mul, (double)y * freq_mul); // -1..1
				double sig;
				if (ridged) {
					sig = offset - std::fabs(nv);
					sig = sig * sig;
				} else {
					sig = std::fabs(nv);
				}
				sum += sig * amp * weight;
				// Multifractal modulation: next octave is gated by this octave's signal.
				weight = gd_clampf(sig * 2.0, 0.0, 1.0);
				amp *= gain;
				freq_mul *= lacunarity;
			}
			vals[(y * w) + x] = (float)sum;
			vmin = gd_minf(vmin, sum); // GDScript tracks the DOUBLE sum, not the f32 store
			vmax = gd_maxf(vmax, sum);
		}
	}
	const double span = gd_maxf(1e-6, vmax - vmin);
	PackedByteArray bytes;
	bytes.resize(np);
	uint8_t *B = bytes.ptrw();
	for (int64_t i = 0; i < np; i++) {
		// GDScript roundi: round half away from zero.
		B[i] = (uint8_t)(int64_t)std::round(gd_clampf(((double)vals[i] - vmin) / span, 0.0, 1.0) * 255.0);
	}
	return Image::create_from_data(w, h, false, Image::FORMAT_L8, bytes);
}

// --- Phase 3: BiomeRegions.build_cells twin (biome_regions.gd) ---------------
// Warped multi-source Dial flood + orphan-islet labeling + per-cell stats and
// adjacency. Returns the same Dictionary as the GDScript (minus "ms", which the
// wrapper adds). adj Dictionaries are built with the exact same insertion order
// so downstream `for nb in adj[c]` iteration matches.
Dictionary WorldgenNative::biome_build_cells(const PackedFloat32Array &heightb, const PackedByteArray &water,
		const PackedInt32Array &labels, const PackedVector2Array &samples,
		const PackedInt32Array &sample_label, const PackedByteArray &warp_bytes,
		const PackedByteArray &humid_bytes, int64_t w, int64_t h,
		double warp_amp, double height_cost) const {
	constexpr int NB = 8192; // dial bucket count (matches BiomeRegions.NB)
	const int64_t n = w * h;
	const float *HB = heightb.ptr();
	const uint8_t *WM = water.ptr();
	const bool has_warp = warp_bytes.size() >= n;
	const uint8_t *WP = has_warp ? warp_bytes.ptr() : nullptr;

	std::vector<float> best(n, std::numeric_limits<float>::infinity());
	PackedInt32Array owner_out;
	owner_out.resize(n);
	int32_t *owner = owner_out.ptrw();
	for (int64_t i = 0; i < n; i++) {
		owner[i] = -1;
	}
	std::vector<uint8_t> closed(n, 0);
	std::vector<std::vector<int32_t>> buckets(NB);
	const double max_cost = (double)(w + h) * (1.0 + warp_amp + height_cost * 0.05);
	const double inv_bw = (double)NB / max_cost;

	const int64_t n_samples = samples.size();
	for (int64_t si = 0; si < n_samples; si++) {
		const Vector2 p = samples[si];
		const int64_t i = ((int64_t)p.y * w) + (int64_t)p.x;
		if (i < 0 || i >= n || WM[i] == 1 || owner[i] != -1) continue;
		best[i] = 0.0f;
		owner[i] = (int32_t)si;
		buckets[0].push_back((int32_t)i);
	}

	static const int DX[4] = { 1, -1, 0, 0 };
	static const int DY[4] = { 0, 0, 1, -1 };
	int cur = 0;
	size_t cursor = 0;
	while (cur < NB) {
		if (cursor >= buckets[cur].size()) {
			cur += 1;
			cursor = 0;
			continue;
		}
		const int32_t ci = buckets[cur][cursor];
		cursor += 1;
		if (closed[ci] == 1) continue; // stale (relaxed again after this push)
		closed[ci] = 1;
		const int64_t cx = ci % w;
		const int64_t cy = ci / w;
		const double bc = (double)best[ci];
		const double hc = (double)HB[ci];
		for (int k = 0; k < 4; k++) {
			const int64_t nx = cx + DX[k];
			const int64_t ny = cy + DY[k];
			if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
			const int64_t ni = (ny * w) + nx;
			if (closed[ni] == 1 || WM[ni] == 1) continue;
			double step = 1.0 + height_cost * std::fabs((double)HB[ni] - hc);
			if (has_warp) step += warp_amp * ((double)WP[ni] / 255.0);
			const double nc = bc + step;
			if (nc < (double)best[ni]) {
				best[ni] = (float)nc;
				owner[ni] = owner[ci];
				const int64_t lv = (int64_t)(nc * inv_bw);
				buckets[(lv < NB - 1) ? lv : NB - 1].push_back((int32_t)ni);
			}
		}
	}

	// Orphan islets: BFS each unowned land component into a synthetic cell.
	int64_t n_cells = n_samples;
	std::vector<int32_t> orphan_first;
	std::vector<int32_t> bfs;
	for (int64_t i0 = 0; i0 < n; i0++) {
		if (WM[i0] == 1 || owner[i0] != -1) continue;
		const int64_t cid = n_cells;
		n_cells += 1;
		orphan_first.push_back((int32_t)i0);
		owner[i0] = (int32_t)cid;
		bfs.clear();
		bfs.push_back((int32_t)i0);
		size_t sp = 0;
		while (sp < bfs.size()) {
			const int32_t c = bfs[sp];
			sp += 1;
			const int64_t ccx = c % w;
			const int64_t ccy = c / w;
			for (int k = 0; k < 4; k++) {
				const int64_t nx = ccx + DX[k];
				const int64_t ny = ccy + DY[k];
				if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
				const int64_t ni = (ny * w) + nx;
				if (WM[ni] == 0 && owner[ni] == -1) {
					owner[ni] = (int32_t)cid;
					bfs.push_back((int32_t)ni);
				}
			}
		}
	}

	// Per-cell stats + exact cell adjacency (right/down neighbor pairs).
	PackedInt32Array px_count;
	px_count.resize(n_cells);
	PackedFloat32Array sum_h, sum_m;
	sum_h.resize(n_cells);
	sum_m.resize(n_cells);
	int32_t *PC = px_count.ptrw();
	float *SH = sum_h.ptrw();
	float *SM = sum_m.ptrw();
	Array adj;
	adj.resize(n_cells);
	for (int64_t c = 0; c < n_cells; c++) {
		adj[c] = Dictionary();
	}
	const bool has_humid = humid_bytes.size() >= n;
	const uint8_t *HM = has_humid ? humid_bytes.ptr() : nullptr;
	for (int64_t y = 0; y < h; y++) {
		for (int64_t x = 0; x < w; x++) {
			const int64_t i = (y * w) + x;
			const int32_t o = owner[i];
			if (o < 0) continue;
			PC[o] += 1;
			SH[o] = (float)((double)SH[o] + (double)HB[i]);
			SM[o] = (float)((double)SM[o] + (has_humid ? (double)HM[i] / 255.0 : 0.5));
			if (x + 1 < w) {
				const int32_t o2 = owner[i + 1];
				if (o2 >= 0 && o2 != o) {
					Dictionary d = adj[o];
					d[(int64_t)o2] = true;
					Dictionary d2 = adj[o2];
					d2[(int64_t)o] = true;
				}
			}
			if (y + 1 < h) {
				const int32_t o3 = owner[i + w];
				if (o3 >= 0 && o3 != o) {
					Dictionary d = adj[o];
					d[(int64_t)o3] = true;
					Dictionary d3 = adj[o3];
					d3[(int64_t)o] = true;
				}
			}
		}
	}

	PackedInt32Array cell_label;
	cell_label.resize(n_cells);
	int32_t *CL = cell_label.ptrw();
	const int64_t sl_size = sample_label.size();
	const int32_t *SL = sample_label.ptr();
	const int32_t *LB = labels.ptr();
	for (int64_t si = 0; si < n_samples; si++) {
		CL[si] = (si < sl_size) ? SL[si] : -1;
	}
	for (size_t k = 0; k < orphan_first.size(); k++) {
		CL[n_samples + (int64_t)k] = LB[orphan_first[k]];
	}

	Dictionary out;
	out["cell_of"] = owner_out;
	out["n_cells"] = n_cells;
	out["orphan_cells"] = (int64_t)orphan_first.size();
	out["px_count"] = px_count;
	out["sum_h"] = sum_h;
	out["sum_m"] = sum_m;
	out["adj"] = adj;
	out["cell_label"] = cell_label;
	return out;
}

// --- Phase 4A: GraphDetail._route ------------------------------------------
// Twin of graph_detail.gd `_route` (plus its helpers `_cell_cost`, `_heur`,
// the binary heap, `_los_simplify`/`_segment_clear` and `_chaikin`). No RNG,
// so bit-identity is purely a matter of matching widths and tie-breaks:
//  - Vector2 is real_t (float32) in BOTH languages, so every geometric call
//    (distance_to / dot / lerp / length_squared) is done through godot::Vector2
//    and only THEN widened to double, exactly as GDScript does.
//  - `gscore` is a PackedFloat32Array in GDScript: costs accumulate in double
//    but narrow to float on store, and the heap keeps the UN-narrowed double.
//  - heap sift comparisons (`<=` on push, `<` on pop) and the dy/dx neighbour
//    order decide equal-f tie-breaks — do not "clean up" either.
namespace {

// MapField.is_land / height_at: clamped nearest-pixel lookup, int() truncates.
struct RouteField {
	const float *H;
	const uint8_t *WA;
	int64_t w, h;
	inline int64_t idx(const Vector2 &p) const {
		int64_t x = (int64_t)p.x;
		int64_t y = (int64_t)p.y;
		if (x < 0) x = 0; else if (x > w - 1) x = w - 1;
		if (y < 0) y = 0; else if (y > h - 1) y = h - 1;
		return (y * w) + x;
	}
	inline bool is_land(const Vector2 &p) const { return WA[idx(p)] == 0; }
	inline double height_at(const Vector2 &p) const { return (double)H[idx(p)]; }
};

inline void route_heap_push(std::vector<double> &hf, std::vector<int32_t> &hi, double f, int32_t idx) {
	hf.push_back(f);
	hi.push_back(idx);
	int64_t c = (int64_t)hf.size() - 1;
	while (c > 0) {
		const int64_t p = (c - 1) >> 1;
		if (hf[p] <= hf[c]) break;
		const double tf = hf[p]; hf[p] = hf[c]; hf[c] = tf;
		const int32_t ti = hi[p]; hi[p] = hi[c]; hi[c] = ti;
		c = p;
	}
}

inline int32_t route_heap_pop(std::vector<double> &hf, std::vector<int32_t> &hi) {
	const int32_t top = hi[0];
	const int64_t last = (int64_t)hf.size() - 1;
	hf[0] = hf[last]; hi[0] = hi[last];
	hf.pop_back(); hi.pop_back();
	const int64_t n = (int64_t)hf.size();
	int64_t c = 0;
	while (true) {
		const int64_t l = 2 * c + 1;
		const int64_t r = 2 * c + 2;
		int64_t s = c;
		if (l < n && hf[l] < hf[s]) s = l;
		if (r < n && hf[r] < hf[s]) s = r;
		if (s == c) break;
		const double tf = hf[c]; hf[c] = hf[s]; hf[s] = tf;
		const int32_t ti = hi[c]; hi[c] = hi[s]; hi[s] = ti;
		c = s;
	}
	return top;
}

// _dist_to_seg: Vector2 (float32) math, widened on return.
inline double route_dist_to_seg(const Vector2 &p, const Vector2 &a, const Vector2 &b) {
	const Vector2 ab = b - a;
	const double l2 = (double)ab.length_squared();
	if (l2 < 0.0001) return (double)p.distance_to(a);
	double t = (double)(p - a).dot(ab) / l2;
	if (t < 0.0) t = 0.0; else if (t > 1.0) t = 1.0;
	return (double)p.distance_to(a + ab * (real_t)t);
}

// _chaikin: corner cutting, endpoints fixed.
PackedVector2Array route_chaikin(PackedVector2Array pts, int64_t iterations) {
	for (int64_t it = 0; it < iterations; it++) {
		const int64_t n = pts.size();
		if (n < 3) return pts;
		PackedVector2Array out;
		out.push_back(pts[0]);
		for (int64_t j = 0; j < n - 1; j++) {
			out.push_back(pts[j].lerp(pts[j + 1], (real_t)0.25));
			out.push_back(pts[j].lerp(pts[j + 1], (real_t)0.75));
		}
		out.push_back(pts[n - 1]);
		pts = out;
	}
	return pts;
}

} // namespace

PackedVector2Array WorldgenNative::route_edge(const PackedFloat32Array &height, const PackedByteArray &water,
		int64_t w, int64_t h, const Vector2 &a, const Vector2 &b, bool water_mode,
		double target_h, int64_t ds, const Dictionary &opts, const Dictionary &occ,
		const Dictionary &node_occ, const Dictionary &excl) const {
	RouteField field{ height.ptr(), water.ptr(), w, h };

	PackedVector2Array straight;
	straight.push_back(a);
	straight.push_back(b);

	const double land_pen = (double)opts.get("route_land_penalty", 8.0);
	const double water_pen = (double)opts.get("route_water_penalty", 8.0);
	const double slope_w = (double)opts.get("route_slope_weight", 10.0);
	const double occ_pen = (double)opts.get("route_occupancy_penalty", 10.0);
	const double corr_w = (double)opts.get("route_corridor_penalty", 12.0);
	const double corridor = (double)opts.get("route_corridor_ratio", 0.35) * (double)a.distance_to(b) + (double)ds * 2.0;
	const double over_w = (double)opts.get("route_overshoot_penalty", 18.0);
	const double border_pen = (double)opts.get("route_border_penalty", 25.0);
	const double node_pen = (double)opts.get("route_node_penalty", 20.0);
	const double back_pen = (double)opts.get("route_backtrack_penalty", 3.0);
	const double tol = (double)opts.get("route_height_tol", 0.15);
	const int64_t smooth_iters = (int64_t)opts.get("route_smooth_iterations", 1);
	const Vector2 ab = b - a;
	const double ab_len2 = gd_maxf(1.0, (double)ab.length_squared());
	const double ab_len = std::sqrt(ab_len2);
	const double ds_f = gd_maxf(1.0, (double)ds);

	const int64_t cx_max = (w / ds) - 1;
	const int64_t cy_max = (h / ds) - 1;
	const double margin = (double)a.distance_to(b) * (double)opts.get("route_margin", 0.7) + 16.0;
	auto clampi64 = [](int64_t v, int64_t lo, int64_t hi) { return v < lo ? lo : (v > hi ? hi : v); };
	const int64_t x0 = clampi64((int64_t)((gd_minf((double)a.x, (double)b.x) - margin) / (double)ds), 0, cx_max);
	const int64_t y0 = clampi64((int64_t)((gd_minf((double)a.y, (double)b.y) - margin) / (double)ds), 0, cy_max);
	const int64_t x1 = clampi64((int64_t)((gd_maxf((double)a.x, (double)b.x) + margin) / (double)ds), 0, cx_max);
	const int64_t y1 = clampi64((int64_t)((gd_maxf((double)a.y, (double)b.y) + margin) / (double)ds), 0, cy_max);
	const int64_t gw = x1 - x0 + 1;
	const int64_t gh = y1 - y0 + 1;
	if (gw < 2 || gh < 2) return straight;
	const int64_t n = gw * gh;
	const int64_t start_i = ((int64_t)((double)a.y / (double)ds) - y0) * gw + ((int64_t)((double)a.x / (double)ds) - x0);
	const int64_t goal_i = ((int64_t)((double)b.y / (double)ds) - y0) * gw + ((int64_t)((double)b.x / (double)ds) - x0);
	if (start_i < 0 || start_i >= n || goal_i < 0 || goal_i >= n) return straight;

	// The two Dictionaries are queried once per neighbour expansion in GDScript;
	// flatten the parts that fall inside the search box into byte grids so the
	// inner loop is an array read. Cells outside the box (none in practice, but
	// _segment_clear is not box-bounded by construction) fall back to the dict.
	std::vector<uint8_t> occ_g(n, 0);
	{
		const Array keys = occ.keys();
		for (int64_t k = 0; k < keys.size(); k++) {
			const Vector2i c = keys[k];
			if (c.x >= x0 && c.x <= x1 && c.y >= y0 && c.y <= y1) {
				occ_g[(c.y - y0) * gw + (c.x - x0)] = 1;
			}
		}
	}
	std::vector<uint8_t> foreign_g(n, 0);
	{
		const Array keys = node_occ.keys();
		for (int64_t k = 0; k < keys.size(); k++) {
			const Vector2i c = keys[k];
			if (c.x < x0 || c.x > x1 || c.y < y0 || c.y > y1) continue;
			const Array ids = node_occ[keys[k]];
			for (int64_t j = 0; j < ids.size(); j++) {
				if (!excl.has(ids[j])) {
					foreign_g[(c.y - y0) * gw + (c.x - x0)] = 1;
					break;
				}
			}
		}
	}
	auto in_box = [&](int64_t cx, int64_t cy) { return cx >= x0 && cx <= x1 && cy >= y0 && cy <= y1; };
	auto occ_has = [&](int64_t cx, int64_t cy) -> bool {
		if (in_box(cx, cy)) return occ_g[(cy - y0) * gw + (cx - x0)] != 0;
		return occ.has(Vector2i((int32_t)cx, (int32_t)cy));
	};
	auto near_foreign = [&](int64_t cx, int64_t cy) -> bool {
		if (in_box(cx, cy)) return foreign_g[(cy - y0) * gw + (cx - x0)] != 0;
		const Array ids = node_occ.get(Vector2i((int32_t)cx, (int32_t)cy), Array());
		for (int64_t j = 0; j < ids.size(); j++) {
			if (!excl.has(ids[j])) return true;
		}
		return false;
	};

	// _cell_cost
	auto cell_cost = [&](int64_t cx, int64_t cy) -> double {
		const double extra = occ_has(cx, cy) ? occ_pen : 0.0;
		const Vector2 world((real_t)(((double)cx + 0.5) * (double)ds), (real_t)(((double)cy + 0.5) * (double)ds));
		const bool land = field.is_land(world);
		if (water_mode) return (land ? land_pen : 1.0) + extra;
		if (!land) return water_pen + extra;
		return 1.0 + slope_w * std::abs(field.height_at(world) - target_h) + extra;
	};

	std::vector<float> gscore(n, std::numeric_limits<float>::infinity());
	std::vector<int32_t> came(n, -1);
	std::vector<uint8_t> closed(n, 0);
	std::vector<double> hf;
	std::vector<int32_t> hi;
	auto heur = [&](int64_t i) -> double {
		const double hdx = (double)((i % gw) - (goal_i % gw));
		const double hdy = (double)((i / gw) - (goal_i / gw));
		return std::sqrt(hdx * hdx + hdy * hdy);
	};
	gscore[start_i] = 0.0f;
	route_heap_push(hf, hi, heur(start_i), (int32_t)start_i);

	int64_t iter = 0;
	const int64_t iter_cap = n * 4 + 64;
	bool found = false;
	while (!hf.empty()) {
		iter++;
		if (iter > iter_cap) break;
		const int64_t cur = (int64_t)route_heap_pop(hf, hi);
		if (closed[cur] == 1) continue;
		closed[cur] = 1;
		if (cur == goal_i) { found = true; break; }
		const int64_t cx = cur % gw;
		const int64_t cy = cur / gw;
		for (int64_t dy = -1; dy <= 1; dy++) {
			for (int64_t dx = -1; dx <= 1; dx++) {
				if (dx == 0 && dy == 0) continue;
				const int64_t nx = cx + dx;
				const int64_t ny = cy + dy;
				if (nx < 0 || ny < 0 || nx >= gw || ny >= gh) continue;
				const int64_t ni = ny * gw + nx;
				if (closed[ni] == 1) continue;
				double base = cell_cost(x0 + nx, y0 + ny);
				if (x0 + nx <= 0 || y0 + ny <= 0 || x0 + nx >= cx_max || y0 + ny >= cy_max) {
					base += border_pen;
				}
				if (near_foreign(x0 + nx, y0 + ny)) base += node_pen;
				if ((double)Vector2((real_t)dx, (real_t)dy).dot(ab) < 0.0) base += back_pen;
				const Vector2 world((real_t)(((double)(x0 + nx) + 0.5) * (double)ds),
						(real_t)(((double)(y0 + ny) + 0.5) * (double)ds));
				const double dseg = route_dist_to_seg(world, a, b);
				if (dseg > corridor) base += corr_w * (dseg - corridor) / ds_f;
				const double tproj = (double)ab.dot(world - a) / ab_len2;
				if (tproj < 0.0 || tproj > 1.0) {
					const double over = (tproj < 0.0 ? -tproj : tproj - 1.0) * ab_len;
					base += over_w * over / ds_f;
				}
				const double step = ((dx != 0 && dy != 0) ? 1.41421356 : 1.0) * base;
				const double ng = (double)gscore[cur] + step;
				if (ng < (double)gscore[ni]) {
					gscore[ni] = (float)ng;
					came[ni] = (int32_t)cur;
					route_heap_push(hf, hi, ng + heur(ni), (int32_t)ni);
				}
			}
		}
	}

	if (!found) return straight;
	PackedVector2Array rev;
	int64_t c = goal_i;
	while (c != -1) {
		const int64_t rx = c % gw;
		const int64_t ry = c / gw;
		rev.push_back(Vector2((real_t)(((double)(x0 + rx) + 0.5) * (double)ds),
				(real_t)(((double)(y0 + ry) + 0.5) * (double)ds)));
		if (c == start_i) break;
		c = came[c];
	}
	PackedVector2Array pts;
	pts.push_back(a);
	for (int64_t i = rev.size() - 1; i >= 0; i--) pts.push_back(rev[i]);
	pts.push_back(b);

	// _segment_clear
	auto segment_clear = [&](const Vector2 &sa, const Vector2 &sb) -> bool {
		int64_t steps = (int64_t)((double)sa.distance_to(sb) / ds_f);
		if (steps < 1) steps = 1;
		for (int64_t s = 0; s <= steps; s++) {
			const double f = (double)s / (double)steps;
			const Vector2 pt = sa.lerp(sb, (real_t)f);
			const int64_t ccx = (int64_t)((double)pt.x / (double)ds);
			const int64_t ccy = (int64_t)((double)pt.y / (double)ds);
			if (f > 0.15 && f < 0.85 && occ_has(ccx, ccy)) return false;
			if (near_foreign(ccx, ccy)) return false;
			if (water_mode) {
				if (field.is_land(pt)) return false;
			} else {
				if (!field.is_land(pt) || std::abs(field.height_at(pt) - target_h) > tol) return false;
			}
		}
		return true;
	};

	// _los_simplify
	PackedVector2Array simp;
	if (pts.size() <= 2) {
		simp = pts;
	} else {
		simp.push_back(pts[0]);
		int64_t anchor = 0;
		for (int64_t i = 2; i < pts.size(); i++) {
			if (!segment_clear(pts[anchor], pts[i])) {
				simp.push_back(pts[i - 1]);
				anchor = i - 1;
			}
		}
		simp.push_back(pts[pts.size() - 1]);
	}
	return route_chaikin(simp, smooth_iters);
}

// --- Phase 4B: WorldMapPainter._paint --------------------------------------
// Twin of map_painter.gd `_paint`. The band ramps arrive FLATTENED (GDScript
// walks the WorldHeightBand resources once and packs upper/color/smooth), but
// every color op goes through godot::Color so `Color.lerp` is the engine's own
// float32 math. `upper` / `snow_line` are GDScript floats = DOUBLES, hence
// PackedFloat64Array — narrowing them to float32 would shift band edges.
//
// The RGBA8 write reproduces Image::set_pixel exactly: uint8_t(CLAMP(c * 255.0,
// 0, 255)) per channel — a TRUNCATION, not a round. (Do NOT "fix" this to
// rounding; the A/B gate compares Image bytes.)
namespace {

inline uint8_t paint_px8(float v) {
	double d = (double)v * 255.0;
	if (d < 0.0) d = 0.0; else if (d > 255.0) d = 255.0;
	return (uint8_t)d;
}

// WorldHeightColorizer.eval_bands over one flattened slice.
Color paint_eval_bands(const double *upper, const Color *cols, const uint8_t *smooth,
		int64_t start, int64_t count, double hv) {
	const double NEG_INF = -std::numeric_limits<double>::infinity();
	double lower = NEG_INF;
	for (int64_t i = 0; i < count; i++) {
		const double bu = upper[start + i];
		if (hv >= bu && i < count - 1) {
			lower = bu;
			continue;
		}
		if (smooth[start + i] != 0 && i < count - 1) {
			const double span = gd_maxf(1e-6, bu - lower);
			double t = 0.0;
			if (lower > NEG_INF) {
				t = (hv - lower) / span;
				if (t < 0.0) t = 0.0; else if (t > 1.0) t = 1.0;
			}
			return cols[start + i].lerp(cols[start + i + 1], (float)t);
		}
		return cols[start + i];
	}
	return Color(1, 0, 1, 1); // Color.MAGENTA — no bands configured
}

} // namespace

PackedByteArray WorldgenNative::paint_map(const PackedFloat32Array &height, const PackedFloat32Array &wsurf,
		const PackedByteArray &rmask, const PackedByteArray &lmask, const PackedInt32Array &bbuf,
		int64_t w, int64_t h, double oth, bool paint_land, bool paint_water,
		bool include_ocean, const Dictionary &pal) const {
	const int64_t n = w * h;
	PackedByteArray out;
	out.resize(n * 4);
	uint8_t *O = out.ptrw();
	const float *H = height.ptr();
	const float *WS = wsurf.ptr();
	const uint8_t *RM = rmask.ptr();
	const uint8_t *LM = lmask.ptr();
	const int32_t *BB = bbuf.ptr();

	const bool has_masks = rmask.size() >= n && lmask.size() >= n;
	// GDScript reads wsurf[idx] behind an is_empty() check only; require a full
	// grid here so a short (malformed) buffer can't read past the end.
	const bool wsurf_ok = wsurf.size() >= n;

	const Color ocean_color = pal.get("ocean", Color());
	const Color lake_color = pal.get("lake", Color());
	const Color river_low = pal.get("river_low", Color());
	const Color river_high = pal.get("river_high", Color());
	const Color snow_color = pal.get("snow", Color());
	const double snow_line = (double)pal.get("snow_line", 0.0);

	const PackedFloat64Array land_upper = pal.get("land_upper", PackedFloat64Array());
	const PackedColorArray land_cols = pal.get("land_color", PackedColorArray());
	const PackedByteArray land_smooth = pal.get("land_smooth", PackedByteArray());
	const int64_t land_count = land_upper.size();

	// Per-biome band slices: b_start[i]/b_count[i] index into b_upper/b_color/b_smooth.
	const PackedInt32Array b_start = pal.get("b_start", PackedInt32Array());
	const PackedInt32Array b_count = pal.get("b_count", PackedInt32Array());
	const PackedFloat64Array b_upper = pal.get("b_upper", PackedFloat64Array());
	const PackedColorArray b_cols = pal.get("b_color", PackedColorArray());
	const PackedByteArray b_smooth = pal.get("b_smooth", PackedByteArray());
	const int64_t n_biomes = b_count.size();
	const bool has_biomes = (bool)pal.get("has_biomes", false) && bbuf.size() >= n;

	const double river_span = gd_maxf(0.001, 1.0 - oth);

	for (int64_t idx = 0; idx < n; idx++) {
		const bool is_river = has_masks && RM[idx] == 1;
		const bool is_lake = has_masks && LM[idx] == 1;
		Color c(0, 0, 0, 0);
		const double hv = (double)H[idx];
		if (hv < oth) {
			if (paint_water && include_ocean) c = ocean_color;
		} else if (is_lake && !is_river) {
			if (paint_water) c = lake_color;
		} else if (is_river) {
			if (paint_water) {
				const double wv = (wsurf_ok && (double)WS[idx] >= 0.0) ? (double)WS[idx] : hv;
				double t = (wv - oth) / river_span;
				if (t < 0.0) t = 0.0; else if (t > 1.0) t = 1.0;
				c = river_low.lerp(river_high, (float)t);
			}
		} else if (paint_land) {
			bool painted = false;
			if (has_biomes) {
				const int64_t b = (int64_t)BB[idx];
				if (b >= 0 && b < n_biomes && b_count[b] > 0) {
					if (snow_line > 0.0 && hv >= snow_line) {
						c = snow_color;
					} else {
						c = paint_eval_bands(b_upper.ptr(), b_cols.ptr(), b_smooth.ptr(),
								b_start[b], b_count[b], hv);
					}
					painted = true;
				}
			}
			if (!painted) {
				c = paint_eval_bands(land_upper.ptr(), land_cols.ptr(), land_smooth.ptr(),
						0, land_count, hv);
			}
		}
		O[idx * 4 + 0] = paint_px8(c.r);
		O[idx * 4 + 1] = paint_px8(c.g);
		O[idx * 4 + 2] = paint_px8(c.b);
		O[idx * 4 + 3] = paint_px8(c.a);
	}
	return out;
}

// --- Determinism: CPU twin of landmass.gdshader ------------------------------
// The GPU steps are the sole source of cross-machine map divergence (the four
// heightmap shaders are read back at float32 and use ops whose precision is
// implementation-defined). This is the CPU replacement for the first of them.
//
// IMPORTANT, and different from every other function in this file: this is NOT a
// bit-identical port. Matching a GPU's pow/atan across vendors is exactly the
// thing that cannot be done. The contract here is DETERMINISM -- identical output
// on every machine of a given platform -- so the A/B for these is "same result
// twice, and across renderers", not "same as GDScript".
//
// The noise/warp maps are CPU-baked L8 at exactly w x h, and the shader samples
// them at pixel centres, so bilinear sampling degenerates to a direct texel
// fetch -- no filtering behaviour to reproduce.
PackedFloat32Array WorldgenNative::terrain_landmass(const PackedByteArray &noise_l8,
		const PackedByteArray &warpx_l8, const PackedByteArray &warpy_l8,
		int64_t w, int64_t h, double island_radius, double land_contrast,
		double edge_jag, double island_falloff) const {
	const int64_t n = w * h;
	PackedFloat32Array out;
	out.resize(n);
	float *O = out.ptrw();
	const uint8_t *N = noise_l8.ptr();
	const uint8_t *WX = warpx_l8.ptr();
	const uint8_t *WY = warpy_l8.ptr();
	const bool have_warp = warpx_l8.size() >= n && warpy_l8.size() >= n;

	for (int64_t y = 0; y < h; y++) {
		const double v = ((double)y + 0.5) / (double)h;
		for (int64_t x = 0; x < w; x++) {
			const int64_t i = (y * w) + x;
			const double u = ((double)x + 0.5) / (double)w;
			// Contrast around 0.5 (shader: clamp((n - 0.5) * land_contrast + 0.5)).
			double nv = (double)N[i] / 255.0;
			nv = (nv - 0.5) * land_contrast + 0.5;
			if (nv < 0.0) nv = 0.0; else if (nv > 1.0) nv = 1.0;
			// Jagged island cutoff: warp the sample position by the tectonic noise.
			double jx = 0.0, jy = 0.0;
			if (have_warp) {
				jx = ((double)WX[i] / 255.0 - 0.5) * 2.0 * edge_jag;
				jy = ((double)WY[i] / 255.0 - 0.5) * 2.0 * edge_jag;
			}
			const double dx = (u + jx) - 0.5;
			const double dy = (v + jy) - 0.5;
			const double d = std::sqrt(dx * dx + dy * dy);
			double mask = 1.0 - (d / island_radius);
			if (mask < 0.0) mask = 0.0; else if (mask > 1.0) mask = 1.0;
			mask = std::pow(mask, island_falloff);
			double hv = nv * mask;
			if (hv < 0.0) hv = 0.0; else if (hv > 1.0) hv = 1.0;
			O[i] = (float)hv;
		}
	}
	return out;
}

// ===========================================================================
// Determinism: shared GLSL-equivalent helpers for the terrain twins.
// ===========================================================================
namespace {

inline double gl_clamp(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }
inline double gl_mix(double a, double b, double t) { return a + ((b - a) * t); }
inline double gl_sign(double v) { return v > 0.0 ? 1.0 : (v < 0.0 ? -1.0 : 0.0); }
inline double gl_fract(double v) { return v - std::floor(v); }

inline double gl_smoothstep(double e0, double e1, double x) {
	const double t = gl_clamp((x - e0) / (e1 - e0), 0.0, 1.0);
	return t * t * (3.0 - (2.0 * t));
}

// Bilinear sampler over a float32 buffer with clamp-to-edge, matching a Godot
// canvas_item sampler2D at its defaults (filter_linear, repeat_disable).
inline double sample_bilinear(const float *src, int64_t w, int64_t h, double u, double v) {
	const double fx = (u * (double)w) - 0.5;
	const double fy = (v * (double)h) - 0.5;
	const double x0f = std::floor(fx);
	const double y0f = std::floor(fy);
	const double tx = fx - x0f;
	const double ty = fy - y0f;
	int64_t x0 = (int64_t)x0f, y0 = (int64_t)y0f;
	int64_t x1 = x0 + 1, y1 = y0 + 1;
	x0 = x0 < 0 ? 0 : (x0 > w - 1 ? w - 1 : x0);
	x1 = x1 < 0 ? 0 : (x1 > w - 1 ? w - 1 : x1);
	y0 = y0 < 0 ? 0 : (y0 > h - 1 ? h - 1 : y0);
	y1 = y1 < 0 ? 0 : (y1 > h - 1 ? h - 1 : y1);
	const double a = gl_mix((double)src[(y0 * w) + x0], (double)src[(y0 * w) + x1], tx);
	const double b = gl_mix((double)src[(y1 * w) + x0], (double)src[(y1 * w) + x1], tx);
	return gl_mix(a, b, ty);
}

} // namespace

// Twin of tectonic_blueprint.gdshader + tectonic_deformation.gdshader.
// The deform shader samples gen.viewport_texture("landmass"); on this path that
// viewport is never rendered, so we read the height BUFFER instead (bilinearly,
// since the drift offset lands between texels).
Array WorldgenNative::terrain_tectonics(const PackedFloat32Array &height,
		const PackedByteArray &warpx_l8, const PackedByteArray &warpy_l8,
		const PackedVector4Array &plate_data, const PackedFloat32Array &plate_is_land,
		int64_t w, int64_t h, int64_t plate_count, double warp_strength, double map_px,
		double drift_intensity, double plate_move, double tectonic_band,
		double land_rift_damping, double tectonic_height_cap) const {
	const int64_t n = w * h;
	PackedFloat32Array out;
	out.resize(n);
	PackedInt32Array ids;
	ids.resize(n);
	float *O = out.ptrw();
	int32_t *ID = ids.ptrw();
	const float *H = height.ptr();
	const uint8_t *WX = warpx_l8.ptr();
	const uint8_t *WY = warpy_l8.ptr();
	const bool have_warp = warpx_l8.size() >= n && warpy_l8.size() >= n;
	if (plate_count > plate_data.size()) plate_count = plate_data.size();

	for (int64_t y = 0; y < h; y++) {
		const double v = ((double)y + 0.5) / (double)h;
		for (int64_t x = 0; x < w; x++) {
			const int64_t i = (y * w) + x;
			const double u = ((double)x + 0.5) / (double)w;

			// Warped coordinate, shared by both passes (identical formula).
			double wx = 0.0, wy = 0.0;
			if (have_warp) {
				wx = ((double)WX[i] / 255.0 - 0.5) * 2.0 * warp_strength;
				wy = ((double)WY[i] / 255.0 - 0.5) * 2.0 * warp_strength;
				wx = gl_clamp(wx, -warp_strength, warp_strength);
				wy = gl_clamp(wy, -warp_strength, warp_strength);
			}
			const double pxx = (u * map_px) + wx;
			const double pxy = (v * map_px) + wy;

			// Two nearest plate centres.
			int64_t best = 0, second = 0;
			double d1 = 1.0e9, d2 = 1.0e9;
			for (int64_t p = 0; p < plate_count; p++) {
				const Vector4 pd = plate_data[p];
				const double ddx = pxx - (double)pd.x;
				const double ddy = pxy - (double)pd.y;
				const double dd = std::sqrt((ddx * ddx) + (ddy * ddy));
				if (dd < d1) {
					d2 = d1; second = best; d1 = dd; best = p;
				} else if (dd < d2) {
					d2 = dd; second = p;
				}
			}
			// Blueprint packs best/15 into blue; the readback rounds it back out.
			ID[i] = (int32_t)best;

			const Vector4 p1 = plate_data[best];
			const Vector4 p2 = plate_data[second];

			// 1. Slide this plate's terrain along its drift vector.
			double hv = sample_bilinear(H, w, h,
					u - ((double)p1.z * plate_move), v - ((double)p1.w * plate_move));

			// 2. Convergence/divergence relief in a band along the boundary.
			const double boundary = 1.0 - gl_smoothstep(0.0, tectonic_band, d2 - d1);
			double dirx = (double)p2.x - (double)p1.x;
			double diry = (double)p2.y - (double)p1.y;
			const double dlen = std::sqrt((dirx * dirx) + (diry * diry));
			double convergence = 0.0;
			if (dlen > 0.0) {
				dirx /= dlen;
				diry /= dlen;
				convergence = (((double)p1.z * dirx) + ((double)p1.w * diry))
						- (((double)p2.z * dirx) + ((double)p2.w * diry));
			}
			double relief = convergence * drift_intensity * boundary;
			if (relief < 0.0) {
				const double land1 = (best < plate_is_land.size()) ? (double)plate_is_land[best] : 0.0;
				const double land2 = (second < plate_is_land.size()) ? (double)plate_is_land[second] : 0.0;
				const double both_land = (land1 + land2) >= 1.5 ? 1.0 : 0.0; // step(1.5, ...)
				relief *= gl_mix(1.0, land_rift_damping, both_land);
			}
			hv += relief;

			O[i] = (float)gl_clamp(hv, 0.0, tectonic_height_cap);
		}
	}
	Array res;
	res.push_back(out);
	res.push_back(ids);
	return res;
}

// Twin of peaks_and_valleys.gdshader. Every texture here is sampled at a pixel
// centre of a map-sized map, so bilinear degenerates to a direct texel fetch.
PackedFloat32Array WorldgenNative::terrain_peaks(const PackedFloat32Array &height,
		const PackedByteArray &ridge_l8, const PackedByteArray &billow_l8,
		const PackedByteArray &detail_l8, const PackedByteArray &warpx_l8,
		const PackedByteArray &warpy_l8, int64_t w, int64_t h,
		double ocean_threshold, double boundary_radius, double edge_jag,
		double peak_uplift, double highland_range, double peak_detail_strength,
		double peak_billow_strength, double peak_height_cap,
		double detail_min_elevation, double detail_falloff,
		double boundary_falloff, double lowland_flatten) const {
	const int64_t n = w * h;
	PackedFloat32Array out;
	out.resize(n);
	float *O = out.ptrw();
	const float *H = height.ptr();
	const uint8_t *R = ridge_l8.ptr();
	const uint8_t *B = billow_l8.ptr();
	const uint8_t *D = detail_l8.ptr();
	const uint8_t *WX = warpx_l8.ptr();
	const uint8_t *WY = warpy_l8.ptr();
	const bool have_warp = warpx_l8.size() >= n && warpy_l8.size() >= n;
	const bool have_noise = ridge_l8.size() >= n && billow_l8.size() >= n && detail_l8.size() >= n;

	for (int64_t y = 0; y < h; y++) {
		const double v = ((double)y + 0.5) / (double)h;
		for (int64_t x = 0; x < w; x++) {
			const int64_t i = (y * w) + x;
			const double u = ((double)x + 0.5) / (double)w;
			double hv = (double)H[i];

			// Lowland flatten: power-curve the above-sea band before the gates read it.
			if (hv > ocean_threshold && lowland_flatten != 1.0) {
				const double excess = gd_maxf(hv - 1.0, 0.0);
				double a = gl_clamp((hv - ocean_threshold) / gd_maxf(1e-4, 1.0 - ocean_threshold), 0.0, 1.0);
				a = std::pow(a, lowland_flatten);
				hv = ocean_threshold + (a * (1.0 - ocean_threshold)) + excess;
			}

			if (hv > ocean_threshold && have_noise) {
				const double ridge = (double)R[i] / 255.0;
				const double billow = (double)B[i] / 255.0;
				const double detail = ((double)D[i] / 255.0 - 0.5) * 2.0 * peak_detail_strength;
				const double t = gl_smoothstep(ocean_threshold, ocean_threshold + highland_range, hv);
				const double ridge_w = t;
				const double billow_w = t * (1.0 - t) * 4.0;
				const double detail_w = gl_smoothstep(detail_min_elevation,
						detail_min_elevation + gd_maxf(detail_falloff, 1e-4), hv);
				hv = gl_clamp(hv
						+ (ridge * peak_uplift * ridge_w)
						+ (billow * peak_billow_strength * billow_w)
						+ (detail * detail_w), 0.0, peak_height_cap);
			}

			// Jagged outer edge clamp (same warp the landmass mask used).
			double jx = 0.0, jy = 0.0;
			if (have_warp) {
				jx = ((double)WX[i] / 255.0 - 0.5) * 2.0 * edge_jag;
				jy = ((double)WY[i] / 255.0 - 0.5) * 2.0 * edge_jag;
			}
			const double ex = (u + jx) - 0.5;
			const double ey = (v + jy) - 0.5;
			const double edge = std::sqrt((ex * ex) + (ey * ey));
			hv *= 1.0 - gl_smoothstep(boundary_radius, boundary_radius + boundary_falloff, edge);
			O[i] = (float)hv;
		}
	}
	return out;
}

// ===========================================================================
// Erosion: CPU twin of erosion.gdshader (directional gabor).
// Every vec3 below is the shader's "analytic" triple (value, d/dx, d/dy).
// ===========================================================================
namespace {

struct V3 {
	double x = 0.0, y = 0.0, z = 0.0;
	V3() {}
	V3(double a, double b, double c) : x(a), y(b), z(c) {}
};

inline V3 v3_add(const V3 &a, const V3 &b) { return V3(a.x + b.x, a.y + b.y, a.z + b.z); }
inline V3 v3_scale(const V3 &a, double s) { return V3(a.x * s, a.y * s, a.z * s); }

constexpr double ROOT_TWO = 1.4142135624;
constexpr double TAU_C = 6.28318530717959;
constexpr double M_PI_C = 3.14159265358979323846;
constexpr int VORONOI_MAX_FREQUENCY_SHIFT = 28;
constexpr int VORONOI_SALT = 938443;
constexpr int WORLD_DIM_X = 1 << 29;
constexpr int WORLD_DIM_Y = 1 << 28;

inline uint32_t hash_ivec2(int32_t dx, int32_t dy) {
	uint32_t hash = 8u;
	uint32_t tmp;
	const uint32_t ux = (uint32_t)dx;
	const uint32_t uy = (uint32_t)dy;
	hash += ux & 0xFFFFu;
	tmp = ((ux >> 16u) << 11u) ^ hash;
	hash = (hash << 16u) ^ tmp;
	hash += hash >> 11u;
	hash += uy & 0xFFFFu;
	tmp = ((uy >> 16u) << 11u) ^ hash;
	hash = (hash << 16u) ^ tmp;
	hash += hash >> 11u;
	hash ^= hash << 3u;
	hash += hash >> 5u;
	hash ^= hash << 4u;
	hash += hash >> 17u;
	hash ^= hash << 25u;
	hash += hash >> 6u;
	return hash;
}

// Cell centre in world-integer space. Shifts go through uint32 so the negative
// cases stay defined in C++ while matching GLSL's wrapping int shifts.
inline void get_cell_position(int32_t cx, int32_t cy, int shift, int32_t &ox, int32_t &oy) {
	const int32_t wrap_x = WORLD_DIM_X >> shift;
	const int32_t wrap_y = WORLD_DIM_Y >> shift;
	const int32_t wcx = (cx < 0) ? (wrap_x + cx) : (cx & (wrap_x - 1));
	const int32_t wcy = (cy < 0) ? (wrap_y + cy) : (cy & (wrap_y - 1));
	const uint32_t mask = (uint32_t)((1 << shift) - 1);
	const uint32_t a = hash_ivec2(wcx, wcy) & mask;
	const uint32_t b = hash_ivec2(wcx + VORONOI_SALT, wcy + VORONOI_SALT) & mask;
	ox = (int32_t)(((uint32_t)cx << shift) + a);
	oy = (int32_t)(((uint32_t)cy << shift) + b);
}

inline V3 ease_out_quad(const V3 &t) {
	const double v = 1.0 - gl_clamp(t.x, 0.0, 1.0);
	const double mask = (t.x >= 0.0 && t.x <= 1.0) ? 1.0 : 0.0;
	const double g = 2.0 * v * mask;
	return V3(1.0 - (v * v), g * t.y, g * t.z);
}

inline V3 ease_in_quad_linear(const V3 &t, const V3 &smoothing) {
	const double s = gd_maxf(smoothing.x, 0.0001);
	const bool is_quad = t.x < s;
	const double val_out = is_quad ? (0.5 * t.x * t.x / s) : (t.x - (0.5 * s));
	const double df_dt = is_quad ? (t.x / s) : 1.0;
	const double df_ds = is_quad ? (-0.5 * t.x * t.x / (s * s)) : -0.5;
	return V3(val_out, (df_dt * t.y) + (df_ds * smoothing.y), (df_dt * t.z) + (df_ds * smoothing.z));
}

inline V3 ease_out_pow(const V3 &t, double power) {
	const double base = 1.0 - gl_clamp(t.x, 0.0, 1.0);
	const double new_h = 1.0 - std::pow(base, power);
	const double deriv = power * std::pow(gd_maxf(base, 0.0001), power - 1.0);
	return V3(new_h, t.y * deriv, t.z * deriv);
}

inline V3 abs3(const V3 &t) {
	const double s = gl_sign(t.x);
	return V3(std::abs(t.x), t.y * s, t.z * s);
}

inline V3 mix_graded(const V3 &a, const V3 &b, const V3 &t_in) {
	V3 t = t_in;
	if (t.x > 1.0) t = V3(1.0, 0.0, 0.0);
	const double d = b.x - a.x;
	return V3(gl_mix(a.x, b.x, t.x),
			gl_mix(a.y, b.y, t.x) + (d * t.y),
			gl_mix(a.z, b.z, t.x) + (d * t.z));
}

inline V3 multiply_graded(const V3 &a, const V3 &b) {
	return V3(a.x * b.x, (a.x * b.y) + (b.x * a.y), (a.x * b.z) + (b.x * a.z));
}

inline V3 get_rounding(const V3 &fade_target, double rr, double gr) {
	const double u = fade_target.x + 0.5;
	const double c = gl_clamp(u, 0.0, 1.0);
	const double grad_scalar = (u >= 0.0 && u <= 1.0) ? (rr - gr) : 0.0;
	return V3(gl_mix(gr, rr, c), grad_scalar * fade_target.y, grad_scalar * fade_target.z);
}

// Returns out_cos; writes out_sin into `sloping` (the shader aliases this onto
// `steepness`, which later octaves then read — that is deliberate, not a bug).
V3 directional_gabor2(int32_t px, int32_t py, double in_frequency, const V3 &aspect, V3 &sloping) {
	// GLSL leaves an out-of-range shift undefined; C++ makes it UB, so clamp.
	int shift = VORONOI_MAX_FREQUENCY_SHIFT - (int)std::floor(in_frequency);
	if (shift < 0) shift = 0; else if (shift > VORONOI_MAX_FREQUENCY_SHIFT) shift = VORONOI_MAX_FREQUENCY_SHIFT;
	const double freq = (double)(1 << shift) * ROOT_TWO;
	const int32_t base_cx = px >> shift;
	const int32_t base_cy = py >> shift;
	const double inv_frequency = 1.0 / freq;
	const double stripe_freq = TAU_C * ROOT_TWO * (1.0 + gl_fract(in_frequency));
	const double dis_fall_off = 4.0;

	const double dirx = std::cos(aspect.x);
	const double diry = std::sin(aspect.x);
	const double perpx = -diry;
	const double perpy = dirx;

	V3 as, ac, at;
	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			int32_t cposx, cposy;
			get_cell_position(base_cx + i, base_cy + j, shift, cposx, cposy);
			const double cdx = (double)(px - cposx) * inv_frequency;
			const double cdy = (double)(py - cposy) * inv_frequency;
			const double sqr_dis = (cdx * cdx) + (cdy * cdy);
			const double alignment = (cdx * dirx * stripe_freq) + (cdy * diry * stripe_freq);
			const double weight = std::exp(-dis_fall_off * sqr_dis);
			const double csc = std::cos(alignment);
			const double css = std::sin(alignment);
			const double delta_proj = (cdx * perpx) + (cdy * perpy);
			const double gdx = (dirx + (aspect.y * delta_proj * freq)) * stripe_freq;
			const double gdy = (diry + (aspect.z * delta_proj * freq)) * stripe_freq;
			const double k = -2.0 * dis_fall_off;
			as.x += weight * css;
			as.y += weight * ((k * cdx * css) + (csc * gdx));
			as.z += weight * ((k * cdy * css) + (csc * gdy));
			ac.x += weight * csc;
			ac.y += weight * ((k * cdx * csc) - (css * gdx));
			ac.z += weight * ((k * cdy * csc) - (css * gdy));
			at.x += weight;
			at.y += weight * k * cdx;
			at.z += weight * k * cdy;
		}
	}
	const V3 oc0(ac.x / at.x,
			(ac.y - (ac.x * at.y / at.x)) * inv_frequency / at.x,
			(ac.z - (ac.x * at.z / at.x)) * inv_frequency / at.x);
	const V3 os0(as.x / at.x,
			(as.y - (as.x * at.y / at.x)) * inv_frequency / at.x,
			(as.z - (as.x * at.z / at.x)) * inv_frequency / at.x);

	const double mag = (0.5 * ((oc0.x * oc0.x) + (os0.x * os0.x))) + 0.5;
	const double gmy = (oc0.x * oc0.y) + (os0.x * os0.y);
	const double gmz = (oc0.x * oc0.z) + (os0.x * os0.z);
	const double m2 = mag * mag;

	sloping = V3(os0.x / mag, ((mag * os0.y) - (os0.x * gmy)) / m2, ((mag * os0.z) - (os0.x * gmz)) / m2);
	return V3(oc0.x / mag, ((mag * oc0.y) - (oc0.x * gmy)) / m2, ((mag * oc0.z) - (oc0.x * gmz)) / m2);
}

} // namespace

Array WorldgenNative::terrain_erosion(const PackedFloat32Array &height, int64_t w, int64_t h,
		int64_t octaves, double amplitude, double frequency, double gain,
		double lacunarity, double branch_angle, double ridge_rounding,
		double gully_rounding, double detail, double steepness_scale,
		double min_elevation, double elevation_falloff) const {
	const int64_t n = w * h;
	PackedFloat32Array out;
	out.resize(n);
	PackedByteArray field;
	field.resize(n);
	float *O = out.ptrw();
	uint8_t *F = field.ptrw();
	const float *H = height.ptr();

	// texelFetch with the shader's clamp to [0, size-1].
	auto h_at = [&](int64_t cx, int64_t cy) -> double {
		cx = cx < 0 ? 0 : (cx > w - 1 ? w - 1 : cx);
		cy = cy < 0 ? 0 : (cy > h - 1 ? h - 1 : cy);
		return (double)H[(cy * w) + cx];
	};
	// (height, d/dx, d/dy, laplacian) by finite differences.
	auto our_field = [&](int64_t cx, int64_t cy, double f[4]) {
		const double c = h_at(cx, cy);
		const double xp = h_at(cx + 1, cy);
		const double xm = h_at(cx - 1, cy);
		const double yp = h_at(cx, cy + 1);
		const double ym = h_at(cx, cy - 1);
		f[0] = c;
		f[1] = (xp - xm) * 0.5;
		f[2] = (yp - ym) * 0.5;
		f[3] = xp + xm + yp + ym - (4.0 * c);
	};

	// Row-parallel. Every output pixel is a pure function of the (read-only) input
	// buffer with no cross-pixel accumulation, so the result does not depend on the
	// thread count or on scheduling -- determinism is preserved by construction.
	// This is the one heavy step (~1.7 s single-threaded on a 512x512 map).
	auto run_rows = [&](int64_t y_begin, int64_t y_end) {
	for (int64_t y = y_begin; y < y_end; y++) {
		for (int64_t x = 0; x < w; x++) {
			const int64_t idx = (y * w) + x;
			double c[4], dcdx[4], dcdy[4];
			our_field(x, y, c);
			our_field(x + 1, y, dcdx);
			our_field(x, y + 1, dcdy);

			const double cl = std::sqrt((c[1] * c[1]) + (c[2] * c[2]));
			V3 steepness(cl,
					std::sqrt((dcdx[1] * dcdx[1]) + (dcdx[2] * dcdx[2])) - cl,
					std::sqrt((dcdy[1] * dcdy[1]) + (dcdy[2] * dcdy[2])) - cl);
			const double theta = std::atan2(c[2], c[1]);
			V3 aspect(theta, std::atan2(dcdx[2], dcdx[1]) - theta, std::atan2(dcdy[2], dcdy[1]) - theta);
			aspect.y = (gl_fract((aspect.y / TAU_C) + 0.5) - 0.5) * TAU_C;
			aspect.z = (gl_fract((aspect.z / TAU_C) + 0.5) - 0.5) * TAU_C;
			V3 laplacian(c[3], dcdx[3] - c[3], dcdy[3] - c[3]);

			steepness = v3_scale(steepness, steepness_scale);
			laplacian = v3_scale(laplacian, steepness_scale / 25.0);

			V3 fade_target = (std::abs(laplacian.x) >= 1.0) ? V3(gl_sign(laplacian.x), 0.0, 0.0) : laplacian;
			V3 rounding = get_rounding(fade_target, ridge_rounding, gully_rounding);
			V3 slope_mask = ease_out_quad(ease_in_quad_linear(steepness, rounding));
			V3 ridge_gully_slope_mask(1.0, 0.0, 0.0);
			V3 ridge_gully_fade_target(0.0, 0.0, 0.0);

			double freq = frequency;
			double amp = 1.0;
			aspect.x += M_PI_C / 2.0; // first octave runs perpendicular to the aspect

			V3 gabor = directional_gabor2((int32_t)x, (int32_t)y, freq, aspect, steepness);
			V3 octave = mix_graded(fade_target, gabor, slope_mask);
			ridge_gully_fade_target = mix_graded(ridge_gully_fade_target, gabor, ridge_gully_slope_mask);

			V3 erosion = v3_scale(octave, amp);
			double max_erosion = amp;

			for (int64_t o = 1; o < octaves; o++) {
				amp *= gain;
				freq += lacunarity;
				aspect.x += gl_sign(steepness.x) * -branch_angle;

				int oct_shift = (int)(freq - frequency);
				if (oct_shift < 0) oct_shift = 0; else if (oct_shift > 30) oct_shift = 30;
				rounding = v3_scale(get_rounding(gabor, ridge_rounding, gully_rounding),
						(double)(1 << oct_shift));
				const V3 octave_slope_mask = ease_out_quad(ease_in_quad_linear(abs3(steepness), rounding));
				slope_mask = multiply_graded(ease_out_pow(slope_mask, detail), octave_slope_mask);

				const V3 octave_rg = ease_out_quad(ease_in_quad_linear(v3_scale(abs3(steepness), 2.0), rounding));
				ridge_gully_slope_mask = multiply_graded(ridge_gully_slope_mask, octave_rg);

				fade_target = octave;
				ridge_gully_fade_target = mix_graded(ridge_gully_fade_target, gabor, ridge_gully_slope_mask);

				gabor = directional_gabor2((int32_t)x, (int32_t)y, freq, aspect, steepness);
				octave = mix_graded(fade_target, gabor, slope_mask);

				erosion = v3_add(erosion, v3_scale(octave, amp));
				max_erosion += amp;
			}

			double ero = erosion.x / max_erosion;
			ero *= gl_smoothstep(min_elevation, min_elevation + gd_maxf(elevation_falloff, 1e-4), c[0]);
			O[idx] = (float)(c[0] + (ero * amplitude));
			// output_mode 1, quantized into the L8 slot the debug viewer reads.
			F[idx] = (uint8_t)std::lround(gl_clamp(0.5 + (0.5 * ero), 0.0, 1.0) * 255.0);
		}
	}
	};

	unsigned int nthreads = std::thread::hardware_concurrency();
	if (nthreads < 1) nthreads = 1;
	if ((int64_t)nthreads > h) nthreads = (unsigned int)h;
	if (nthreads <= 1) {
		run_rows(0, h);
	} else {
		std::vector<std::thread> pool;
		pool.reserve(nthreads - 1);
		const int64_t chunk = (h + (int64_t)nthreads - 1) / (int64_t)nthreads;
		for (unsigned int t = 1; t < nthreads; t++) {
			const int64_t y0 = (int64_t)t * chunk;
			const int64_t y1 = (y0 + chunk > h) ? h : (y0 + chunk);
			if (y0 >= h) break;
			pool.emplace_back(run_rows, y0, y1);
		}
		run_rows(0, chunk > h ? h : chunk);
		for (std::thread &th : pool) th.join();
	}
	Array res;
	res.push_back(out);
	res.push_back(field);
	return res;
}

void WorldgenNative::_bind_methods() {
	ClassDB::bind_method(D_METHOD("fill_depressions", "height", "w", "h", "oth"), &WorldgenNative::fill_depressions);
	ClassDB::bind_method(D_METHOD("flow_accumulate_mfd", "filled", "seed", "w", "h", "oth", "exponent"), &WorldgenNative::flow_accumulate_mfd);
	ClassDB::bind_method(D_METHOD("dilate_lake", "mask", "surf", "w", "h", "r"), &WorldgenNative::dilate_lake);
	ClassDB::bind_method(D_METHOD("box_blur", "src", "w", "h", "passes"), &WorldgenNative::box_blur);
	ClassDB::bind_method(D_METHOD("label_landmasses", "water", "w", "h"), &WorldgenNative::label_landmasses);
	ClassDB::bind_method(D_METHOD("map_distance_transform", "water", "w", "h", "downscale"), &WorldgenNative::map_distance_transform);
	ClassDB::bind_method(D_METHOD("poisson_land_samples", "labels", "blocked", "w", "h", "main_label", "confine_main", "seed_pts", "r", "seed_val"), &WorldgenNative::poisson_land_samples);
	ClassDB::bind_method(D_METHOD("measure_land", "labels", "w", "h", "main_label", "confine_main"), &WorldgenNative::measure_land);
	ClassDB::bind_method(D_METHOD("river_downsample", "height", "w", "h", "s", "lw", "lh"), &WorldgenNative::river_downsample);
	ClassDB::bind_method(D_METHOD("river_seed_field", "lbase", "hum_img", "w", "h", "s", "lw", "lh", "oth", "hum_bias", "elev_bias"), &WorldgenNative::river_seed_field);
	ClassDB::bind_method(D_METHOD("river_depth_stamp", "lbase", "accum", "lw", "lh", "oth", "thr", "carve_depth", "width_gain"), &WorldgenNative::river_depth_stamp);
	ClassDB::bind_method(D_METHOD("river_lake_surfaces", "lbase", "lfilled", "lw", "lh", "oth", "lake_min_depth", "lake_min_area", "lake_carve_depth"), &WorldgenNative::river_lake_surfaces);
	ClassDB::bind_method(D_METHOD("river_apply_water", "base", "wsurf", "is_lake_l", "lake_surf_l", "depth_l", "w", "h", "s", "lw", "lh", "oth"), &WorldgenNative::river_apply_water);
	ClassDB::bind_method(D_METHOD("bake_multifractal", "noise", "w", "h", "octaves", "gain", "lacunarity", "ridged", "offset"), &WorldgenNative::bake_multifractal);
	ClassDB::bind_method(D_METHOD("biome_build_cells", "heightb", "water", "labels", "samples", "sample_label", "warp_bytes", "humid_bytes", "w", "h", "warp_amp", "height_cost"), &WorldgenNative::biome_build_cells);
	ClassDB::bind_method(D_METHOD("jittered_land_samples", "labels", "blocked", "w", "h", "main_label", "confine_main", "cs", "seed_val"), &WorldgenNative::jittered_land_samples);
	ClassDB::bind_method(D_METHOD("terrain_landmass", "noise_l8", "warpx_l8", "warpy_l8", "w", "h", "island_radius", "land_contrast", "edge_jag", "island_falloff"), &WorldgenNative::terrain_landmass);
	ClassDB::bind_method(D_METHOD("terrain_tectonics", "height", "warpx_l8", "warpy_l8", "plate_data", "plate_is_land", "w", "h", "plate_count", "warp_strength", "map_px", "drift_intensity", "plate_move", "tectonic_band", "land_rift_damping", "tectonic_height_cap"), &WorldgenNative::terrain_tectonics);
	ClassDB::bind_method(D_METHOD("terrain_peaks", "height", "ridge_l8", "billow_l8", "detail_l8", "warpx_l8", "warpy_l8", "w", "h", "ocean_threshold", "boundary_radius", "edge_jag", "peak_uplift", "highland_range", "peak_detail_strength", "peak_billow_strength", "peak_height_cap", "detail_min_elevation", "detail_falloff", "boundary_falloff", "lowland_flatten"), &WorldgenNative::terrain_peaks);
	ClassDB::bind_method(D_METHOD("terrain_erosion", "height", "w", "h", "octaves", "amplitude", "frequency", "gain", "lacunarity", "branch_angle", "ridge_rounding", "gully_rounding", "detail", "steepness_scale", "min_elevation", "elevation_falloff"), &WorldgenNative::terrain_erosion);
	ClassDB::bind_method(D_METHOD("paint_map", "height", "wsurf", "rmask", "lmask", "bbuf", "w", "h", "oth", "paint_land", "paint_water", "include_ocean", "pal"), &WorldgenNative::paint_map);
	ClassDB::bind_method(D_METHOD("route_edge", "height", "water", "w", "h", "a", "b", "water_mode", "target_h", "ds", "opts", "occ", "node_occ", "excl"), &WorldgenNative::route_edge);
}
