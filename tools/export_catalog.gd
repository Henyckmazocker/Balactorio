extends SceneTree

# Imprime el catálogo de analítica EXPANDIDO (Plan «Analítica de Runs», M1) en el formato de
# `catalog.upsert` de Augur: un array JSON de `{"name", "description", "properties": {"p":
# {"type": "string|number"}}}`, con enum/id → string e int/float/bool01 → number. Las familias
# (`built_*@per_factory`) salen ya abiertas a una prop por factoría o material, y los enums leídos
# de `resources/factoryParams.json`: la expansión vive en UN sitio, `managers/analytics.gd`.
#
#   godot-4 --headless --path . --script res://tools/export_catalog.gd | sed -n '/^\[/,$p' | jq .
#
# 🔴 Godot imprime SIEMPRE su cabecera («Godot Engine v4.7…») por stdout antes de correr el script,
# y `--quiet` la quita pero se lleva también el `print()`: el JSON empieza en la primera línea que
# empieza por `[`, y de ahí se corta con el `sed` de arriba.
#
# Lo consume `tools/augur-setup.sh` (M5). No escribe nada ni abre red.

func _initialize():
	var text = FileAccess.get_file_as_string("res://resources/factoryParams.json");
	var file_data = JSON.parse_string(text);
	if not (file_data is Dictionary):
		printerr("export_catalog: no se pudo leer resources/factoryParams.json");
		quit(2);
		return;
	var analytics = load("res://managers/analytics.gd").new();
	var ok = analytics.initialize(file_data, text);
	var out = analytics.export_upsert();
	analytics.free();
	if not ok:
		printerr("export_catalog: el catálogo no se pudo expandir (ver el error de arriba)");
		quit(1);
		return;
	print(JSON.stringify(out, "  "));
	quit(0);
