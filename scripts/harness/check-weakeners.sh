#!/usr/bin/env bash
# Fails if the Makefile, CI workflows or project scripts contain anything that can
# turn a red check green. Portable (GNU and BSD grep, no -P).
set -uo pipefail
status=0
# make reads GNUmakefile or makefile before Makefile, and only Makefile is checked.
for other in GNUmakefile makefile; do
  if [ -e "$other" ]; then echo "$other: make lo leería antes que Makefile, que es el único que se revisa"; status=1; fi
done
files="$(
  { ls Makefile 2>/dev/null
    ls .github/workflows/*.yml .github/workflows/*.yaml 2>/dev/null
    find scripts -name '*.sh' -not -path 'scripts/harness/*' 2>/dev/null
  } | sort -u
)"
tab="$(printf '\t')"
# A make invocation, as a command or as $(MAKE), up to one of its arguments.
make_cmd='(\$\(MAKE\)|(^|[^[:alnum:]_])make)[^#]*[[:space:]]'
# Any word of the value: single-letter flags with i or k, or --ignore/--keep abbreviations.
makeflags_re=$'MAKEFLAGS[^:=]*[:=](.*[[:space:]"\'=])?(-?[a-zA-Z]*[ik][a-zA-Z]*|--ign[a-z-]*|--kee[a-z-]*)([[:space:]"\']|$)'
for f in $files; do
  if [ "$(basename "$f")" = "Makefile" ]; then
    grep -n "^${tab}-" "$f" && { echo "$f: receta con prefijo '-'"; status=1; }
    grep -nE '^[[:space:]]*\.IGNORE' "$f" && { echo "$f: .IGNORE"; status=1; }
    # Everything make runs must be in this file: included files are not checked.
    grep -nE '^[[:space:]]*-?s?include[[:space:]]' "$f" && { echo "$f: include de otro fichero, que no se revisa"; status=1; }
    grep -nE '^[[:space:]]*((override|export)[[:space:]]+)*define[[:space:]]+(SHELL|\.SHELLFLAGS|MAKEFLAGS)([[:space:]]|$)' "$f" &&
      { echo "$f: define de SHELL, .SHELLFLAGS o MAKEFLAGS"; status=1; }
    # Recipes must run under bash -e -o pipefail: without -e, a failing command
    # in a multi-command line (a loop, `a; b`) no longer fails the recipe. Any
    # other assignment (later, conditional, target-specific, ::=) could undo it.
    sh_lines="$(grep -nE '(^|[[:space:]:])SHELL[[:space:]]*[:?+!]*=' "$f")" || sh_lines=""
    if [ "$(grep -c . <<< "$sh_lines")" -ne 1 ] || ! grep -qxE '[0-9]+:SHELL := bash' <<< "$sh_lines"; then
      printf '%s\n' "$sh_lines"; echo "$f: SHELL := bash tiene que ser la única asignación de SHELL"; status=1
    fi
    fl_lines="$(grep -nE '(^|[[:space:]:])\.SHELLFLAGS[[:space:]]*[:?+!]*=' "$f")" || fl_lines=""
    if [ "$(grep -c . <<< "$fl_lines")" -ne 1 ] ||
      ! grep -qE '^[0-9]+:\.SHELLFLAGS := (.*[[:space:]])?-[a-zA-Z]*e[a-zA-Z]*[[:space:]].*pipefail' <<< "$fl_lines" ||
      grep -qE '(^|[[:space:]])\+([a-zA-Z]*e|o[[:space:]])' <<< "$fl_lines"; then
      printf '%s\n' "$fl_lines"; echo "$f: .SHELLFLAGS tiene que llevar -e y pipefail (sin +e ni +o), en una sola asignación"; status=1
    fi
  fi
  grep -nE "$makeflags_re" "$f" && { echo "$f: MAKEFLAGS que ignora errores"; status=1; }
  grep -nE "${make_cmd}(-[a-zA-Z]*[ik][a-zA-Z]*|--ign[a-z-]*|--kee[a-z-]*)([[:space:]]|$)" "$f" && { echo "$f: make con -i o -k"; status=1; }
  grep -nE "${make_cmd}(SHELL|\.SHELLFLAGS|MAKEFLAGS)[:+]?=" "$f" && { echo "$f: variable de make cambiada en la línea de órdenes"; status=1; }
  grep -nE 'go[[:space:]]+test[^#]*[[:space:]]--?(test\.)?(run|skip|short)([=[:space:]]|$)' "$f" && { echo "$f: filtro de tests en go test"; status=1; }
  grep -nE '\|\|[[:space:]]*((/[^[:space:];]*/)?true|:|echo|printf|exit 0)([[:space:];]|$)' "$f" && { echo "$f: || que traga errores"; status=1; }
  grep -nE ';[[:space:]]*((/[^[:space:];]*/)?true|exit 0)([[:space:];]|$)' "$f" && { echo "$f: ; true o ; exit 0"; status=1; }
  grep -nE 'set[[:space:]]+([-+][a-zA-Z]*[[:space:]]+)*(\+[a-zA-Z]*e|\+o[[:space:]]+(errexit|pipefail))' "$f" && { echo "$f: set +e o set +o errexit/pipefail"; status=1; }
  # Any value: an expression such as ${{ true }} lets the step fail as well (F-0014).
  grep -nE 'continue-on-error[[:space:]]*:' "$f" && { echo "$f: continue-on-error"; status=1; }
  grep -nE 'if:[[:space:]]*always\(\)' "$f" && { echo "$f: if: always()"; status=1; }
done
exit $status
