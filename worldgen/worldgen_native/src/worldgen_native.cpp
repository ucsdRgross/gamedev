#include "worldgen_native.h"

#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>
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
	ClassDB::bind_method(D_METHOD("biome_build_cells", "heightb", "water", "labels", "samples", "sample_label", "warp_bytes", "humid_bytes", "w", "h", "warp_amp", "height_cost"), &WorldgenNative::biome_build_cells);
	ClassDB::bind_method(D_METHOD("jittered_land_samples", "labels", "blocked", "w", "h", "main_label", "confine_main", "cs", "seed_val"), &WorldgenNative::jittered_land_samples);
}
