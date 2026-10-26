#!/usr/bin/env bash
# Prueba los laboratorios del curso, uno detrás de otro:
#   containerlab deploy  →  lab/verificar.sh  →  containerlab destroy
# y termina con un resumen. La salida completa de cada laboratorio queda en un
# registro, en resultados-pruebas/<fecha>/ (ignorado por git).
#
# Uso, desde cualquier carpeta del repositorio:
#   herramientas/probar-todos.sh                 todos los laboratorios
#   herramientas/probar-todos.sh 12 13 base E0   solo algunos: número de módulo,
#                                                'base' o el código del escenario
# Opciones:
#   -k        si un laboratorio falla, NO lo destruye (para depurarlo a mano)
#   -l DIR    carpeta para los registros (por defecto resultados-pruebas/<fecha>)
#   -h        esta ayuda
#
# Requiere containerlab y Docker. Usa "sudo containerlab"; para otro comando,
# define CLAB, por ejemplo: CLAB=containerlab herramientas/probar-todos.sh

set -u
cd "$(dirname "$0")/.." || exit 1

KEEP=0
LOGDIR=""
while getopts "kl:h" opt; do
  case $opt in
    k) KEEP=1 ;;
    l) LOGDIR=$OPTARG ;;
    h) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) exit 2 ;;
  esac
done
shift $((OPTIND - 1))

CLAB=${CLAB:-"sudo containerlab"}
LOGDIR=${LOGDIR:-resultados-pruebas/$(date +%Y%m%d-%H%M%S)}
mkdir -p "$LOGDIR"
TIMEOUT=""
command -v timeout >/dev/null 2>&1 && TIMEOUT="timeout 900"

# --- Qué laboratorios probar ---
ALL=()
for d in [0-9][0-9]-*/lab anexo-escenarios/*/lab anexo-escenarios/*/lab-*; do
  [ -f "$d/lab.clab.yml" ] && [ -x "$d/verificar.sh" ] || continue
  case $d in *plantilla*) continue ;; esac
  ALL+=("$d")
done

SEL=()
if [ $# -eq 0 ]; then
  SEL=("${ALL[@]}")
else
  for want in "$@"; do
    found=0
    for d in "${ALL[@]}"; do
      mod=${d%/lab}; mod=${mod%/lab-*}
      case $want in
        base) [ "$mod" = "anexo-escenarios/topologia-base" ] && { SEL+=("$d"); found=1; } ;;
        E[0-9]*|e[0-9]*) case $mod in anexo-escenarios/"$(echo "$want" | tr e E)"-*) SEL+=("$d"); found=1 ;; esac ;;
        *) w=$want
           [[ $want =~ ^[0-9]+$ ]] && w=$(printf '%02d' "$((10#$want))")
           case $mod in "$w"-*) SEL+=("$d"); found=1 ;; esac ;;
      esac
    done
    [ $found -eq 1 ] || echo "⚠️  No encuentro ningún laboratorio para '$want'"
  done
fi
[ ${#SEL[@]} -gt 0 ] || { echo "No hay laboratorios que probar."; exit 1; }

# --- Entorno ---
{
  echo "Fecha:        $(date '+%Y-%m-%d %H:%M:%S')"
  echo "Containerlab: $($CLAB version 2>/dev/null | grep -i 'version' | head -1 | awk '{print $NF}')"
  echo "Docker:       $(docker version --format '{{.Server.Version}}' 2>/dev/null)"
  echo "Kernel:       $(uname -r)"
  echo "Imágenes:     $(for d in "${SEL[@]}"; do grep -ho 'image: [^ ]*' "$d/lab.clab.yml"; done | sort -u | awk '{print $2}' | tr '\n' ' ')"
} | tee "$LOGDIR/entorno.txt"
echo
echo "Se van a probar ${#SEL[@]} laboratorios. Registros en $LOGDIR/"
case $CLAB in sudo*) sudo -v || exit 1 ;; esac
echo

# --- Bucle de pruebas ---
SUMMARY=()
TOTAL_FAIL=0
for d in "${SEL[@]}"; do
  mod=${d%/lab}
  log="$LOGDIR/$(echo "$mod" | tr '/' '_').log"
  start=$(date +%s)
  printf '▶ %-40s ' "$mod"

  status=""
  if ! $CLAB deploy -t "$d/lab.clab.yml" --reconfigure >"$log" 2>&1; then
    status="ERROR AL DESPLEGAR"
  else
    echo "===== verificar.sh =====" >>"$log"
    (cd "$d" && $TIMEOUT ./verificar.sh) >>"$log" 2>&1
    rc=$?
    line=$(grep -a 'Resultado:' "$log" | tail -1)
    if [ -n "$line" ]; then
      ok=$(echo "$line" | sed -E 's/.*Resultado: ([0-9]+) correctas.*/\1/')
      ko=$(echo "$line" | sed -E 's/.*correctas, ([0-9]+) fallidas.*/\1/')
      status="$ok correctas, $ko fallidas"
      [ "$ko" -eq 0 ] || status="❌ $status"
    elif [ $rc -eq 124 ]; then
      status="TIEMPO AGOTADO"
    else
      status="SIN RESULTADO (rc=$rc)"
    fi
  fi

  case $status in
    "❌ "*|ERROR*|TIEMPO*|SIN*) failed=1 ;;
    *) failed=0; status="✅ $status" ;;
  esac
  [ $failed -eq 1 ] && TOTAL_FAIL=$((TOTAL_FAIL + 1))

  if [ $failed -eq 1 ] && [ $KEEP -eq 1 ]; then
    status="$status (laboratorio NO destruido)"
  else
    echo "===== destroy =====" >>"$log"
    $CLAB destroy -t "$d/lab.clab.yml" --cleanup >>"$log" 2>&1
  fi

  secs=$(( $(date +%s) - start ))
  echo "$status  [${secs}s]"
  SUMMARY+=("$(printf '%-40s %s  [%ss]' "$mod" "$status" "$secs")")
done

# --- Resumen ---
{
  echo
  echo "================ RESUMEN ================"
  printf '%s\n' "${SUMMARY[@]}"
  echo "========================================="
  echo "Laboratorios: ${#SEL[@]} · con fallos: $TOTAL_FAIL"
} | tee "$LOGDIR/resumen.txt"

if [ $TOTAL_FAIL -gt 0 ]; then
  echo
  echo "Para ver qué falló en un laboratorio:  less $LOGDIR/<laboratorio>.log"
  echo "Para pasármelo todo de una vez:        tar czf resultados.tgz $LOGDIR"
  exit 1
fi
