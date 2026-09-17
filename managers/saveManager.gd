extends Node

const SAVE_PATH = "user://save.json";

var _data = {
	"unlocked_packages": ["standard"],
	"unlocked_maps": ["forest_01"],
	"runs_completed": 0,
	"best_time": 0.0
};

func _ready():
	load_save();

func load_save():
	if not FileAccess.file_exists(SAVE_PATH):
		return;
	var text = FileAccess.get_file_as_string(SAVE_PATH);
	var parsed = JSON.parse_string(text);
	if parsed is Dictionary:
		for key in parsed:
			_data[key] = parsed[key];

func save():
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE);
	if file:
		file.store_string(JSON.stringify(_data));
		file.close();

func is_package_unlocked(package_id) -> bool:
	return _data["unlocked_packages"].has(package_id);

func is_map_unlocked(map_id) -> bool:
	return _data["unlocked_maps"].has(map_id);

func unlock_package(package_id):
	if not _data["unlocked_packages"].has(package_id):
		_data["unlocked_packages"].append(package_id);
		save();

func unlock_map(map_id):
	if not _data["unlocked_maps"].has(map_id):
		_data["unlocked_maps"].append(map_id);
		save();

func record_run_completion(run_time: float):
	_data["runs_completed"] += 1;
	if _data["best_time"] == 0.0 or run_time < _data["best_time"]:
		_data["best_time"] = run_time;
	save();

func get_runs_completed() -> int:
	return int(_data["runs_completed"]);

func get_best_time() -> float:
	return float(_data["best_time"]);
