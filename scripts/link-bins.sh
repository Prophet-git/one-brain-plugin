#!/bin/sh
# Deja los comandos de One Brain a mano en ~/.local/bin.
#
# POR QUÉ EXISTE. Los binarios del plugin viven en la caché de Claude Code, en una ruta que
# lleva el número de versión adentro:
#
#   ~/.claude/plugins/cache/prophet/one-brain/0.1.741/bin/onebrain-secret
#
# Nadie se la acuerda, y cambia con cada actualización. El resultado es que `onebrain-secret`
# contesta "command not found" y la persona tiene que pedirle la ruta a su Claude — que es
# justo lo que no queremos para el comando que saca una clave, porque el modelo termina
# metido en el medio de una operación pensada para que la haga una persona sola.
#
# QUÉ HACE. Un symlink por comando en ~/.local/bin, apuntando al PUENTE de bin/ (no al bin del
# core: el puente es la ruta estable que ya circula en las skills y en el contexto). Corre en
# cada arranque, así que después de un update los links quedan apuntando a la versión nueva.
#
# TRES CUIDADOS, porque escribe en una carpeta de binarios de otra persona:
#
#   1. NO PISA LO AJENO. Si ya hay un archivo con ese nombre y no es un symlink nuestro, no se
#      toca. Alguien puede tener su propio `onebrain-save`, y su script gana.
#   2. NO ENSUCIA. Sólo escribe si el destino no existe o si es un symlink que ya apunta a una
#      versión de one-brain (ahí sí se re-apunta a la actual).
#   3. NO HABLA. Es un hook de arranque: si algo falla, se sale en silencio. Tener los comandos
#      a mano es una comodidad, no puede ser el motivo de que una sesión no arranque.
#
# Si ~/.local/bin no está en el PATH de esa persona, el symlink no molesta a nadie y el día que
# lo agregue empieza a funcionar solo.

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ORIGEN="$DIR/../bin"
DESTINO="$HOME/.local/bin"

[ -d "$ORIGEN" ] || exit 0
mkdir -p "$DESTINO" 2>/dev/null || exit 0

for bin in "$ORIGEN"/onebrain-*; do
  [ -f "$bin" ] || continue
  nombre=$(basename "$bin")
  link="$DESTINO/$nombre"

  if [ -e "$link" ] || [ -L "$link" ]; then
    # Sólo se re-apunta lo que ya es nuestro: un symlink que mira a la caché del plugin.
    [ -L "$link" ] || continue
    actual=$(readlink "$link" 2>/dev/null) || continue
    case "$actual" in
      *"/one-brain/"*) ;;   # nuestro, de otra versión: se actualiza
      *) continue ;;        # de otro, no se toca
    esac
  fi

  ln -sfn "$bin" "$link" 2>/dev/null || true
done

exit 0
