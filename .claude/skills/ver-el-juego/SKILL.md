---
name: ver-el-juego
description: Arrancar Balactorio CON VENTANA y conducirlo para mirarlo — jugarlo a mano, o conducirlo desde un script y capturar PNG. Úsala cuando haya que comprobar algo que se ve (UI, HUD, el mapa, el color de una casilla, si un texto cabe), o cuando pidan «arranca el juego», «hazme una captura», «compruébalo jugando».
---

# Ver el juego — Balactorio con ventana

Esto **mira**, no mide. Hoy el repo **no tiene ningún instrumento de medida**: los bancos se borraron
el 2026-09-22 y `sim/`, la telemetría y `tools/analisis/` el 2026-09-23. Junto a
`tests/run_tests.gd`, esta skill es lo único que queda para verificar algo.

## Arrancar

El entorno de David sirve tal cual: hay display X real (`DISPLAY=:0`) y **no hace falta xvfb**.

```bash
cd /home/david/Documents/workspace/Balactorio
godot-4 --path . res://Main.tscn                        # jugarlo con el ratón
godot-4 --path . --script res://tools/ver_dilema.gd     # conducirlo y capturar
```

**Ruido esperado, no es un fallo:** Godot intenta Vulkan, no lo consigue con los drivers de la AMD
780M y cae a OpenGL 3 solo. El bloque `ERROR: Condition "err != VK_SUCCESS"` seguido de
`switching to OpenGL 3` es normal. Los `ObjectDB instances were leaked at exit` al salir, también.

**No abras el editor gráfico** (`godot-4 --path .` a secas) desde una sesión de agente.

## Conducir y capturar

Un conductor con ventana es un script de `SceneTree` que monta `Main.tscn`, lo lleva al estado que
quieres ver y captura. Hay uno completo y comentado en **`tools/ver_dilema.gd`**: cópialo como punto
de partida en vez de empezar de cero. El montaje mínimo:

```gdscript
extends SceneTree

func _process(_delta):        # los nodos se montan AQUÍ, no en _initialize(): allí no hay root
    if _hecho: return false;
    _hecho = true; _todo();
    return false;

func _todo():
    var main = load("res://Main.tscn").instantiate();
    root.add_child(main);
    var menu = main.get_node_or_null("MainMenu");
    if menu: main.remove_child(menu); menu.free();    # saltarse los menús
    main._start_game("standard");
    # pick_map() es ALEATORIO: si necesitas un mapa concreto, reaplícalo entero
    # (demoliendo antes el almacén del mapa descartado). Receta literal en tools/ver_dilema.gd.
    await _capturar("res://capturas/foo.png");
    quit();

func _capturar(ruta):
    await RenderingServer.frame_post_draw;             # sin esto guardas el frame ANTERIOR
    root.get_texture().get_image().save_png(ruta);
```

`Engine.time_scale` **también vale con render**: a 40× la espiral de contaminación entera cabe en
~10 s reales.

## Las cinco trampas

1. 🔴 **Las pantallas no se buscan por nombre.** `ui/upgradeScreen.gd` extiende `CanvasLayer`, y en
   cuanto se apila más de una —`queue_free()` es diferido, y el juego alcanza sus **propios**
   checkpoints mientras tú inyectas los tuyos— Godot las renombra a `@CanvasLayer@N`. Entonces
   `get_node("UpgradeScreen")` encuentra solo la primera y la foto sale con un panel tapando lo que
   querías ver. Identifícalas por su señal:

   ```gdscript
   for hijo in main.get_children():
       if hijo.has_signal("upgrade_chosen"):
           main.remove_child(hijo); hijo.queue_free();
   ```

   Es la misma familia que la trampa del tooltip que documenta el `CLAUDE.md` de la raíz.
2. **Para fotografiar el mapa, pausa el árbol** (`paused = true`). Si lo dejas correr, alcanza el
   checkpoint siguiente en unos frames y vuelve a abrir la pantalla encima.
3. **`await RenderingServer.frame_post_draw` antes de `save_png()`.** Sin él capturas el frame
   anterior, y en un juego que cambia de color despacio eso no canta hasta que te has creído una
   captura falsa.
4. **El PNG va bajo `res://`, nunca `/tmp`.** El snap de Godot no lee `/tmp`, y `user://` vive en
   `~/snap/godot-4/current/.local/share/godot/app_userdata/…`. `capturas/` ya está en el
   `.gitignore`; si escribes en otra carpeta, sácala del repo al terminar.
5. **`--script` con ventana no lleva `--headless`.** Parece obvio y es el error más rápido de cometer
   copiando una línea de la sección de tests.

## Mirar la captura

**Léela de verdad con la herramienta de imagen.** Una captura en negro es un fallo de arranque, no
una foto. Y un PNG que nadie abre no ha verificado nada: el valor de esta skill está en el paso de
mirar, no en el de generar el fichero.

Para sacarlas del repo y poder abrirlas:

```bash
cp capturas/*.png "$SCRATCH"/     # $SCRATCH = el scratchpad de la sesión
```

## Cuándo usar esto

| Pregunta | Herramienta |
|---|---|
| ¿Se entiende? ¿Se ve? ¿Cabe en pantalla? ¿Los dos mapas quedan distintos? | **Esta skill** |
| ¿Se cumple una relación entre constantes o reglas? | `tests/run_tests.gd` |
| ¿Cuánto vale esta constante? ¿Cuánto tarda la run? ¿Divergen dos estrategias? | **Sin herramienta hoy** — la medición está por rehacer desde cero (Roadmap del Brain) |

🔴 **El precedente que sigue valiendo.** El 2026-09-20 el Plan «Catálogo de Mejoras» midió durante un
día que «coger la carta potente es perder». Era falso: el bot del banco no elegía carta por política,
no replanificaba cuando le degradaban una casilla de su plan y no se gastaba la madera que tenía.
Veinte minutos con esta skill contestaron lo que seis barridos no supieron.

**La regla:** antes de gastar una medición en una pregunta de diseño, pregúntate si un humano la
contestaría mirando la pantalla cinco minutos. Si sí, mira primero y mide después.

**El síntoma que delata a un instrumento mintiendo:** termina la run **con recursos sin gastar**.
Es la lección que acabó con los bots, los bancos y `sim/`, y la que tendrá que respetar la medición
que se rehaga.

## No dejes procesos vivos

Todo `godot-4` largo lleva `timeout N` delante, y **nunca** se espera con un bucle
`until [ "$(pgrep -c -f 'godot-4 …')" = "0" ]`: `pgrep -f` se encuentra a sí mismo y el bucle no
termina jamás. Detalle y receta buena en el `CLAUDE.md` de la raíz, sección «Lanzar un `godot-4`
largo desde Claude Code sin dejar procesos vivos». Antes de terminar:

```bash
pgrep -a -x godot-4     # ¿queda algo vivo?
```
