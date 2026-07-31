// Lógica pura de los comandos de proyecto (dejar / retomar). Vive aparte de los ejecutables
// para poder testearla: mezclar un archivo de entorno ajeno y decidir si una credencial está
// vencida son justo las cosas que no se pueden "probar a mano" sin arriesgar el .env de alguien.

/** Mezcla variables nuevas dentro del contenido de un .env EXISTENTE.
 *
 *  Nunca pisa el archivo entero: reemplaza la línea de cada variable que ya estaba y agrega al
 *  final las que faltan. El archivo de la otra persona puede tener cosas suyas (puertos, flags,
 *  credenciales de otro servicio) que no están en el cerebro y que se perderían con un
 *  sobrescribir. Conserva comentarios, orden y líneas en blanco.
 *
 *  Devuelve { contenido, agregadas, reemplazadas, sinCambio }. */
export function mergeEnv(actual, vars) {
  const lineas = actual === "" ? [] : actual.replace(/\n$/, "").split("\n");
  const agregadas = [];
  const reemplazadas = [];
  const sinCambio = [];
  const pendientes = new Map(Object.entries(vars));

  const salida = lineas.map((linea) => {
    // Solo tocamos asignaciones reales: un comentario que MENCIONA la variable no es la variable.
    const m = /^(\s*)([A-Za-z_][A-Za-z0-9_]*)(\s*=)(.*)$/.exec(linea);
    if (!m) return linea;
    const clave = m[2];
    if (!pendientes.has(clave)) return linea;
    const valorNuevo = pendientes.get(clave);
    pendientes.delete(clave);
    const valorViejo = m[4].trim().replace(/^["']|["']$/g, "");
    if (valorViejo === valorNuevo) {
      sinCambio.push(clave);
      return linea;
    }
    reemplazadas.push(clave);
    return `${m[1]}${clave}=${valorNuevo}`;
  });

  for (const [clave, valor] of pendientes) {
    salida.push(`${clave}=${valor}`);
    agregadas.push(clave);
  }

  const contenido = salida.length ? salida.join("\n") + "\n" : "";
  return { contenido, agregadas, reemplazadas, sinCambio };
}

/** Extrae los NOMBRES de las variables de un .env. Se usa para mostrar qué se va a subir sin
 *  imprimir un solo valor: la confirmación es por nombre, nunca por contenido. */
export function nombresDeEnv(contenido) {
  return (contenido || "").split("\n")
    .map((l) => /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=/.exec(l))
    .filter(Boolean)
    .map((m) => m[1]);
}

/** Lee las variables de un .env como objeto (para subirlas). */
export function leerEnv(contenido) {
  const out = {};
  for (const linea of (contenido || "").split("\n")) {
    const m = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$/.exec(linea);
    if (!m) continue;
    out[m[1]] = m[2].trim().replace(/^["']|["']$/g, "");
  }
  return out;
}

/** ¿Esta credencial está vieja? Devuelve los días, o null si no hay fecha.
 *
 *  Sirve para avisar ANTES de que la persona pierda media hora peleando contra un token que
 *  venció hace dos meses. No bloquea nada: avisa. */
export function diasDesde(iso, ahora = new Date()) {
  if (!iso) return null;
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return null;
  return Math.floor((ahora.getTime() - t) / 86400000);
}

/** ¿El destino queda tapado por .gitignore? Chequeo textual a propósito: no queremos depender
 *  de que `git` esté disponible ni de correr un comando por archivo. Cubre el patrón exacto,
 *  el archivo suelto y el directorio con barra. */
export function estaIgnorado(gitignore, destino) {
  if (!destino.startsWith(".") && !destino.includes("/")) return false;
  const base = destino.replace(/^\.\//, "");
  const patrones = (gitignore || "").split("\n").map((l) => l.trim()).filter((l) => l && !l.startsWith("#"));
  return patrones.some((p) => {
    const limpio = p.replace(/^\//, "").replace(/\/$/, "");
    if (limpio === base) return true;
    if (base.startsWith(limpio + "/")) return true;
    // .env* cubre .env.local
    if (limpio.endsWith("*") && base.startsWith(limpio.slice(0, -1))) return true;
    return false;
  });
}

/** El nombre del repo tal como lo guarda el perfil, para comparar con dónde estoy parado.
 *  Normaliza las formas de la misma URL (ssh, https, con y sin .git). */
export function normalizarRepo(url) {
  if (!url) return null;
  return url.trim()
    .replace(/^git@([^:]+):/, "https://$1/")
    .replace(/\.git$/, "")
    .replace(/\/$/, "")
    .toLowerCase();
}

/** ¿El repo donde estoy parado es el del proyecto que estoy pidiendo?
 *  Es la defensa contra una inyección en el repo del cliente A que pida las credenciales de B:
 *  si no coinciden, el comando exige una confirmación aparte. */
export function mismoRepo(repoPerfil, repoLocal) {
  const a = normalizarRepo(repoPerfil);
  const b = normalizarRepo(repoLocal);
  if (!a || !b) return null; // no se puede saber
  return a === b;
}

/** Lee las opciones de onebrain-project-push.
 *
 *  Existe como función pura, y con tests, porque la versión anterior parseaba a mano con un
 *  `args.find` que se confundía con el valor de la opción anterior — y ahora hay tres opciones
 *  más donde equivocarse. Que el nombre del proyecto salga mal no es cosmético: sube el perfil
 *  y las credenciales al proyecto equivocado. */
export function parsearArgsPush(argv) {
  const conValor = { "--dir": "dir", "--descripcion": "descripcion", "--prod": "prod", "--roadmap-file": "roadmapFile" };
  const opciones = { dir: null, descripcion: null, prod: null, roadmapFile: null, env: [], excluir: [] };
  const sueltos = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (conValor[a]) { opciones[conValor[a]] = argv[++i] ?? null; continue; }
    if (a === "--env") { const v = argv[++i]; if (v) opciones.env.push(v); continue; }
    if (a === "--excluir") {
      const v = argv[++i] ?? "";
      opciones.excluir.push(...v.split(",").map((s) => s.trim()).filter(Boolean));
      continue;
    }
    // Una opción que no conocemos se ignora en vez de tomarse como el nombre del proyecto.
    if (a.startsWith("--")) continue;
    sueltos.push(a);
  }
  return { proyecto: sueltos[0] ?? null, ...opciones };
}

/** El primer párrafo de prosa del README, para PROPONER la descripción del proyecto.
 *
 *  Es una propuesta, no un dato: la persona la ve en el resumen antes de confirmar la subida y
 *  la corrige con --descripcion. Se saltean el título, las insignias, el HTML y las citas —
 *  lo que queda es la frase que alguien ya escribió explicando qué es esto, que casi siempre
 *  es mejor que la que se escribiría a las apuradas al final del día. */
export function descripcionDeReadme(contenido, tope = 300) {
  const parrafo = [];
  for (const cruda of (contenido || "").split("\n")) {
    const l = cruda.trim();
    if (!l) { if (parrafo.length) break; continue; }
    if (/^[#<>[!]/.test(l)) { if (parrafo.length) break; continue; }
    parrafo.push(l);
  }
  const texto = parrafo.join(" ").replace(/\s+/g, " ").trim();
  if (!texto) return null;
  return texto.length > tope ? texto.slice(0, tope).trimEnd() + "…" : texto;
}

/** Los dos campos de descripción que viajan al server, separando el DATO de la PROPUESTA.
 *
 *  Antes viajaba uno solo: `descripcion: opts.descripcion || descripcionPropuesta(dir)`. Como la
 *  propuesta del README siempre sale con valor, la corrida rutinaria del push —la de "actualizá
 *  el repo", sin --descripcion— le pisaba a la descripción escrita a mano la primera línea del
 *  README. La descripción es el campo titular de la tab Proyectos: es lo único que le permite a
 *  alguien que no programa saber qué es cada proyecto.
 *
 *  Separados, el server sabe cuál es cuál: `descripcion` se guarda siempre, `descripcion_propuesta`
 *  sólo si el proyecto todavía no tiene ninguna (ver upsertProjectProfile). Para CORREGIR una
 *  descripción cargada hay que pasar --descripcion, que es exactamente el acto deliberado que
 *  antes ocurría solo. */
export function camposDeDescripcion(explicita, propuesta) {
  const escrita = (explicita || "").trim();
  if (escrita) return { descripcion: escrita, descripcion_propuesta: null };
  return { descripcion: null, descripcion_propuesta: propuesta || null };
}
