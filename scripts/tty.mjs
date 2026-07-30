import { openSync, readSync, closeSync } from "node:fs";

/** ¿La persona dijo que sí? Solo un sí explícito cuenta; cualquier otra cosa (enter, silencio,
 *  basura) es que no. Falla cerrado a propósito: esto autoriza escribir credenciales. */
export function esSi(respuesta) {
  const r = (respuesta || "").trim().toLowerCase();
  return r === "s" || r === "si" || r === "sí" || r === "y" || r === "yes";
}

/** Lee una línea de la TERMINAL (no de la entrada estándar).
 *
 *  Por qué de /dev/tty: el modelo puede ejecutar el comando —una inyección de prompt en un
 *  README puede pedirlo— pero no puede apretar una tecla en la terminal de la persona. Si no
 *  hay terminal (pipe, CI, otro proceso), devuelve null y quien llama debe abortar.
 *
 *  El bucle con EAGAIN no es adorno: el descriptor de /dev/tty suele estar en modo no
 *  bloqueante, así que la primera lectura vuelve vacía y una implementación ingenua interpreta
 *  ese vacío como "no contestó" — cancelando SIEMPRE, incluso cuando la persona escribió que sí. */
export function preguntar(pregunta) {
  let fd;
  try {
    fd = openSync("/dev/tty", "r");
  } catch {
    return null;
  }
  process.stdout.write(`${pregunta} [s/N] `);
  const buf = Buffer.alloc(64);
  let texto = "";
  const limite = Date.now() + 120000; // dos minutos y se cancela solo
  try {
    while (Date.now() < limite) {
      let n = 0;
      try {
        n = readSync(fd, buf, 0, buf.length, null);
      } catch (e) {
        if (e && (e.code === "EAGAIN" || e.code === "EWOULDBLOCK")) {
          dormir(40);
          continue;
        }
        break;
      }
      if (n === 0) { dormir(40); continue; }
      texto += buf.toString("utf8", 0, n);
      if (texto.includes("\n") || texto.includes("\r")) break;
    }
  } finally {
    closeSync(fd);
  }
  process.stdout.write("\n");
  return texto;
}

/** Pausa sin quemar CPU ni depender de async: Atomics.wait bloquea el hilo de verdad. */
function dormir(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}
