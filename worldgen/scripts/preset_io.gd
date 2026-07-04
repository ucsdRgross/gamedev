class_name PresetIO
extends RefCounted

## Static helpers for the map_viewer recording workflow. Density-model edition:
##   - save_preset(step, "good"/"bad") : append one compact JSON line to pending.jsonl
##   - process_step_ranges(step)       : read pending.jsonl, build per-param density
##                                       (good = this epoch, bad = accumulated forever)
##                                       into ranges.json, then fold the batch into the
##                                       single archive.jsonl and clear pending
##   - load_ranges(step) / sample_entry(): continuous piecewise-linear draw of
##                                       (base + good - bad); bad pockets stay carved out
##   - clear_step_data(step)           : reset valve (drop ranges.json + pending.jsonl)
##
## Storage is three files per step (pending.jsonl, archive.jsonl, ranges.json) -- no
## file-per-save and no .tres. Per-step isolation: a step's data holds only that
## step's params, so tuning a later step never disturbs an earlier one. Plain JSON via
## FileAccess gets no .import sidecar, so no .gdignore is needed.

const PRESET_ROOT := "res://presets"

## Param tables + sampler live in WorldRandomizer (addon; single source of truth). The
## recording workflow below delegates to it so the dev side and the shipped bundle never
## drift. These thin wrappers keep the map_viewer call sites (PresetIO.step_params/
## param_ranges/sample_entry) stable.

## The tunable params assigned to a step (empty Array if the step is unknown).
static func step_params(step: String) -> Array:
	return WorldRandomizer.step_params(step)

## name -> [lo, hi, is_int] for every randomizable WorldSettings parameter.
static func param_ranges() -> Dictionary:
	return WorldRandomizer.param_ranges()

## name -> is_int for EVERY tunable WorldSettings param (the canonical "save everything"
## set, so no finetuned value is silently dropped from a preset).
static func tunable_params() -> Dictionary:
	return WorldRandomizer.tunable_params()

## Draw a value from one density entry (inverse-CDF over the good/bad histograms).
static func sample_entry(entry: Dictionary, rng: RandomNumberGenerator, base: float) -> float:
	return WorldRandomizer.sample_entry(entry, rng, base)

## Snapshot ONLY this step's params (+ main_seed for provenance) into a flat dict.
## Per-step isolation: a Landmass preset holds only Landmass params, so processing
## the Landmass folder yields Landmass ranges and never disturbs other steps.
static func settings_to_dict(settings: WorldSettings, step: String) -> Dictionary:
	var d := {"_step": step, "main_seed": settings.main_seed}
	for pname in step_params(step):
		d[pname] = settings.get(pname)
	return d

# Histogram resolution for the density model.
const BINS := 12
# One growing line-delimited file per step instead of a file (+ .tres) per save:
#   pending.jsonl = the current epoch's samples (one compact JSON per line)
#   archive.jsonl = every consumed sample, combined into one file at process time
const PENDING_FILE := "pending.jsonl"
const ARCHIVE_FILE := "archive.jsonl"

## Append a GOOD or BAD sample (this step's params + seed + verdict) as one compact
## JSON line to the step's pending.jsonl. No per-save files, no .tres. Returns the
## pending path or "".
static func save_preset(settings: WorldSettings, step: String, verdict: String = "good") -> String:
	var dir := "%s/%s" % [PRESET_ROOT, step]
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir)) != OK \
			and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		push_error("[PresetIO] could not create %s" % dir)
		return ""
	var d := settings_to_dict(settings, step)
	d["_verdict"] = verdict
	var path := "%s/%s" % [dir, PENDING_FILE]
	_append_line(path, JSON.stringify(d))
	return path

# Append one line to a file (creating it if absent). FileAccess has no append mode,
# so open READ_WRITE + seek_end when the file already exists.
static func _append_line(path: String, line: String) -> void:
	var f: FileAccess
	if FileAccess.file_exists(path):
		f = FileAccess.open(path, FileAccess.READ_WRITE)
		if f:
			f.seek_end()
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_line(line)
		f.close()

## Build a density model from this batch of good/bad presets, write it to
## ranges.json, then ARCHIVE the consumed presets so the next batch starts fresh.
## Per param the model is two histograms over a FIXED domain:
##   good[] -- replaced each epoch (this batch only) so narrowing isn't dragged by
##             old generations.
##   bad[]  -- ACCUMULATED across all epochs (read back from the previous ranges.json
##             and added to). Bad is forever -- a value that looked bad always counts.
## Randomize samples a continuous piecewise-linear curve of (base + good - bad), so
## picks land anywhere under the line (between bins) and bad pockets stay carved out.
static func process_step_ranges(step: String) -> Dictionary:
	var dir := "%s/%s" % [PRESET_ROOT, step]
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		return {}
	var prev := load_ranges(step)  # persisted bad histograms + domains
	var good := {}   # param -> Array[float] (this batch)
	var bad := {}
	var pending_path := "%s/%s" % [dir, PENDING_FILE]
	var lines: PackedStringArray = []
	if FileAccess.file_exists(pending_path):
		lines = FileAccess.get_file_as_string(pending_path).split("\n", false)
	var kept := []  # valid raw lines, consolidated into the archive afterwards
	for line in lines:
		var parsed = JSON.parse_string(line)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		kept.append(line)
		var bucket: Dictionary = bad if String(parsed.get("_verdict", "good")) == "bad" else good
		for k in parsed:
			if String(k).begins_with("_") or WorldRandomizer.EXCLUDE.has(k):
				continue
			var tv := typeof(parsed[k])
			if tv != TYPE_FLOAT and tv != TYPE_INT:
				continue
			if not bucket.has(k):
				bucket[k] = []
			bucket[k].append(float(parsed[k]))

	var tp := tunable_params()
	var defaults := param_ranges()
	var params := {}
	for k in good: params[k] = true
	for k in bad: params[k] = true
	for k in prev: params[k] = true  # carry forward params we only have bad history for
	var out := {}
	for p in params:
		# Fixed domain: reuse the persisted one, else the predefined range, else span.
		var lo: float
		var hi: float
		var n := BINS
		if prev.has(p) and prev[p] is Dictionary and prev[p].has("lo"):
			lo = float(prev[p]["lo"]); hi = float(prev[p]["hi"]); n = int(prev[p].get("bins", BINS))
		elif defaults.has(p):
			lo = defaults[p][0]; hi = defaults[p][1]
		else:
			var span: Array = good.get(p, []) + bad.get(p, [])
			if span.is_empty():
				continue
			lo = span.min(); hi = span.max()
		if hi <= lo:
			hi = lo + maxf(absf(lo) * 0.01, 1e-4)
		var bstep := (hi - lo) / float(n)
		# bad = persisted bad + this batch's bad (accumulate forever).
		var bad_bins := []
		bad_bins.resize(n); bad_bins.fill(0.0)
		if prev.has(p) and prev[p] is Dictionary and prev[p].has("bad"):
			var pb: Array = prev[p]["bad"]
			for i in mini(n, pb.size()):
				bad_bins[i] = float(pb[i])
		for v in bad.get(p, []):
			bad_bins[clampi(int((v - lo) / bstep), 0, n - 1)] += 1.0
		# good = THIS batch only (replace).
		var good_bins := []
		good_bins.resize(n); good_bins.fill(0.0)
		for v in good.get(p, []):
			good_bins[clampi(int((v - lo) / bstep), 0, n - 1)] += 1.0
		out[p] = {"lo": lo, "hi": hi, "bins": n, "is_int": tp.get(p, false),
			"good": good_bins, "bad": bad_bins,
			"good_n": good.get(p, []).size(), "bad_n": bad.get(p, []).size()}

	var f := FileAccess.open("%s/ranges.json" % dir, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "  "))
		f.close()
	# Consolidate the consumed batch into the single archive file, then clear pending.
	if not kept.is_empty():
		_append_line("%s/%s" % [dir, ARCHIVE_FILE], "\n".join(kept))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(pending_path))
	print("[PresetIO] '%s': %d samples -> %d param models (bad accumulates), batch consolidated." % [step, kept.size(), out.size()])
	return out

## Read the density model (rich entries) written by process_step_ranges.
static func load_ranges(step: String) -> Dictionary:
	var path := "%s/%s/ranges.json" % [PRESET_ROOT, step]
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

## Reset valve: drop the model (ranges.json, incl. accumulated bad) and the current
## pending batch so the step starts from defaults again. archive.jsonl (raw history)
## is left intact.
static func clear_step_data(step: String) -> void:
	var dir := "%s/%s" % [PRESET_ROOT, step]
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		return
	for fn in [PENDING_FILE, "ranges.json"]:
		if FileAccess.file_exists("%s/%s" % [dir, fn]):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s" % [dir, fn]))
	print("[PresetIO] cleared model + pending for '%s' (archive.jsonl kept)." % step)
