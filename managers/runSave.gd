extends RefCounted

# El fichero de la run en curso (Plan «Serialización de Run»). Separado de saveManager a
# propósito: `user://save.json` es la meta-progresión, que se acumula para siempre, y este es un
# snapshot efímero que se borra al cargarlo, al ganar, al perder y al reiniciar. Un guardado a
# medias de la run no puede llevarse por delante lo único que el jugador no recupera jugando.
#
# Main tiene UNA instancia (`Main.runSave`) y es la única que lee y escribe el fichero; las
# celdas (cell_key / parse_cell) son estáticas porque las usan los snapshot() sin instancia.

const RUN_PATH = "user://run.json";
# Sube cuando cambie la FORMA del snapshot. Un save de otra versión no se migra: se tira.
const VERSION = 1;

# 🔴 La suite y el juego comparten `user://` (el del snap): una prueba que escribiera en RUN_PATH
# borraría la run guardada de David. La suite pone aquí "user://test_run.json" lo PRIMERO, antes
# de crear ningún Main, y como cada instancia toma su `path` de esta estática al nacer, ningún
# Main de prueba —por _ready(), por set_script() o suelto— llega a ver el fichero real, ni los
# que pasan por reset(), ganar o perder sin saber nada de este hito. Redirigir instancia a
# instancia dejaría fuera a la primera prueba vieja que se olvidara.
static var default_path: String = RUN_PATH;
var path: String = default_path;

# Escribe a `path + ".tmp"` y renombra encima: rename() es atómico en el mismo sistema de
# ficheros, así que un cierre a mitad de escritura deja el save anterior o el nuevo, nunca un
# JSON roto. Sin `sort_keys` (reordenaría la bolsa, y su orden es el del HUD) y con
# `full_precision` (sin ella los floats pierden cifras).
func write(snapshot: Dictionary) -> bool:
	var tmp = path + ".tmp";
	var f = FileAccess.open(tmp, FileAccess.WRITE);
	if f == null:
		push_warning("runSave: no se pudo abrir '%s' (%s)" % [tmp, error_string(FileAccess.get_open_error())]);
		return false;
	f.store_string(JSON.stringify(snapshot, "", false, true));
	f.close();
	var err = DirAccess.rename_absolute(tmp, path);
	if err != OK:
		push_warning("runSave: no se pudo renombrar '%s' (%s)" % [tmp, error_string(err)]);
		DirAccess.remove_absolute(tmp);
		return false;
	return true;

# El snapshot si es de ESTE formato y de ESTE balance; {} si no. Un fichero que existe pero no
# vale —no parsea, no es un objeto, otra `version`, otro `params_hash`— se BORRA: no va a valer
# nunca, y dejarlo haría que el menú lo consultara en cada arranque. Avisa con push_warning y no
# con push_error: un save roto es un caso del juego, no un fallo del programa.
func read_valid(params_hash: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {};
	var snap = _parse_valid(params_hash);
	if snap.is_empty():
		push_warning("runSave: '%s' no vale para esta versión o este balance; se descarta" % path);
		clear();
	return snap;

func clear() -> void:
	for ruta in [path, path + ".tmp"]:
		if FileAccess.file_exists(ruta):
			DirAccess.remove_absolute(ruta);

# Lo que pregunta el menú para enseñar «CONTINUAR». Solo mira: borrar es cosa de read_valid().
func exists_valid(params_hash: String) -> bool:
	return FileAccess.file_exists(path) and not _parse_valid(params_hash).is_empty();

# El fichero parseado si cumple las tres condiciones, {} si no. JSON.new().parse() y no
# JSON.parse_string(): esta última imprime un error por un save truncado, que aquí es esperable.
# `version` vuelve como float (todo número del JSON lo hace): se compara con int().
func _parse_valid(params_hash: String) -> Dictionary:
	var json = JSON.new();
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {};
	var d = json.data;
	if not d is Dictionary:
		return {};
	var version = d.get("version", null);
	if not (version is int or version is float) or int(version) != VERSION:
		return {};
	if str(d.get("params_hash", "")) != params_hash:
		return {};
	return d;

# 🔴 JSON no conserva `Vector2i`: `JSON.stringify()` lo convierte EN SILENCIO al texto
# "(3, 4)" —ni avisa ni falla— y `parse_string()` devuelve ese String, que ya no es una celda.
# Por eso toda celda del snapshot, como clave o como valor, sale por aquí como "x,y" y vuelve
# por parse_cell(). Sirve igual para direcciones (`dir_in`/`dir_out` de las cintas), que son
# Vector2i con componentes negativas: "-1,0".
static func cell_key(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y];

static func parse_cell(s: String) -> Vector2i:
	var partes = s.split(",");
	if partes.size() != 2:
		push_warning("runSave: celda mal formada '%s'" % s);
		return Vector2i.ZERO;
	return Vector2i(int(partes[0]), int(partes[1]));
