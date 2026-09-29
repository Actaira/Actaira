#!/usr/bin/env python3
"""Mutation proofs for E0 step 0.3 (after round 1 of the adversarial pass).

Works on a copy of the committed tree (git archive HEAD) in a temporary
directory: the live repo, its settings.json and the guard-git hook that
reviews every command of the session are never edited (F-0008; step 0.3,
round 1, finding 15). For each fix: remove it in the copy, run its test (it
must be red, for that reason), restore the file byte for byte, and run the
test again (it must be green). Exits 1 if any mutation is not proven.
Usage: python3 evals/sessions/2026-09-28-e0-paso-3-mutate.py [commit]; the commit defaults to HEAD, and the
output records which one was copied, so a later tree can rerun the proofs of
the commit they were made on.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
H = "scripts/harness/"
T = "scripts/harness/tests/"

# (title, file, fragment, replacement, test file, test name)
MUTATIONS = [
    # guard-git.sh
    ("F-0010: sin unir las continuaciones", H + "guard-git.sh",
     "cmd=\"${cmd//\\\\$'\\n'/}\"                          # line continuations, joined as bash does (F-0010)", "# mutation",
     T + "guard-git_test.sh", "test_blocks_line_continuations"),
    ("F-0011: sin excepcion para la etiqueta de cierre", H + "guard-git.sh",
     '[ "$all_closing" -eq 1 ] && exit 0', "true",
     T + "guard-git_test.sh", "test_allows_only_the_closing_tag_from_main"),
    ("F-0007: sin quitar comillas", H + "guard-git.sh",
     """| tr -d "\\"'\\\\\\\\" |""", "|",
     T + "guard-git_test.sh", "test_blocks_quoted_or_chained_main"),
    ("guard: sin grupos cortos con f", H + "guard-git.sh",
     '      -*f*) block "push forzado ($a)" ;;\n', "",
     T + "guard-git_test.sh", "test_blocks_quoted_or_chained_main"),
    ("guard: sin abreviaturas", H + "guard-git.sh",
     "--force* | --no-v* | --al* | --b* | --m*)", "--force* | --no-verify | --all | --branches | --mirror)",
     T + "guard-git_test.sh", "test_blocks_abbreviations_refspec_patterns_and_inline_config"),
    ("guard: sin refspec : ni comodines", H + "guard-git.sh",
     ": | *'*'* | *'?'* | *'['*) block", "__never__) block",
     T + "guard-git_test.sh", "test_blocks_abbreviations_refspec_patterns_and_inline_config"),
    ("guard: sin revisar la configuracion en linea", H + "guard-git.sh",
     'if [[ "$key" =~ ^(alias|push|remote|include|includeif)\\. ]] || [ "$key" = core.hookspath ]; then', "if false; then",
     T + "guard-git_test.sh", "test_blocks_abbreviations_refspec_patterns_and_inline_config"),
    ("guard: sin expandir alias", H + "guard-git.sh",
     'if ! is_builtin "$sub"; then', "if false; then",
     T + "guard-git_test.sh", "test_blocks_configured_push_alias"),
    ("guard: sin bloquear expansiones", H + "guard-git.sh",
     "*'$'* | *'`'* | *'{'* | *'}'*) block \"push con expansi", "__never__) block \"push con expansi",
     T + "guard-git_test.sh", "test_blocks_shell_expansions_in_a_push"),
    ("guard: sin xargs", H + "guard-git.sh",
     'if [ "$word" = xargs ]; then', "if false; then",
     T + "guard-git_test.sh", "test_blocks_shell_expansions_in_a_push"),
    ("guard: orden que empieza por push", H + "guard-git.sh",
     '  if [ "$cmdword" = push ]; then', "  if false; then",
     T + "guard-git_test.sh", "test_blocks_shell_expansions_in_a_push"),
    ("guard: push en cualquier palabra (sin subcomando real)", H + "guard-git.sh",
     '[ "$sub" = push ] || continue', '[[ " ${w[*]} " == *" push "* ]] || continue',
     T + "guard-git_test.sh", "test_allows_commands_that_only_mention_push"),
    ("guard: sin mirar los repos de git -C", H + "guard-git.sh",
     'for d in "$project" "$PWD" "${push_dirs[@]}"; do',
     'for d in "$project" "$PWD"; do',
     T + "guard-git_test.sh", "test_blocks_push_from_another_repo_on_main"),
    ("guard: sin bloquear el push desde main", H + "guard-git.sh",
     'if [ "$(git -C "$d" branch --show-current 2>/dev/null)" = main ]; then', "if false; then",
     T + "guard-git_test.sh", "test_blocks_any_push_from_main"),
    # check-weakeners.sh
    ("weakeners: sin || true", H + "check-weakeners.sh",
     "grep -nE '\\|\\|[[:space:]]*((/[^[:space:];]*/)?true|:|echo|printf|exit 0)([[:space:];]|$)' \"$f\" && {", "false && {",
     T + "check-weakeners_test.sh", "test_or_true_in_makefile_fails"),
    ("weakeners: sin prefijo -", H + "check-weakeners.sh",
     'grep -n "^${tab}-" "$f" && {', "false && {",
     T + "check-weakeners_test.sh", "test_dash_prefixed_recipe_fails"),
    ("weakeners: sin .IGNORE", H + "check-weakeners.sh",
     "grep -nE '^[[:space:]]*\\.IGNORE' \"$f\" && {", "false && {",
     T + "check-weakeners_test.sh", "test_ignore_special_target_fails"),
    ("weakeners: sin make -i/-k", H + "check-weakeners.sh",
     'grep -nE "${make_cmd}(-[a-zA-Z]*[ik][a-zA-Z]*|--ign[a-z-]*|--kee[a-z-]*)([[:space:]]|$)" "$f" && {', "false && {",
     T + "check-weakeners_test.sh", "test_make_ignore_errors_in_workflow_fails"),
    ("weakeners: sin continue-on-error", H + "check-weakeners.sh",
     "grep -nE 'continue-on-error:[[:space:]]*true' \"$f\" && {", "false && {",
     T + "check-weakeners_test.sh", "test_continue_on_error_workflow_fails"),
    ("#13: sin exigir SHELL := bash", H + "check-weakeners.sh",
     "if [ \"$(grep -c . <<< \"$sh_lines\")\" -ne 1 ] || ! grep -qxE '[0-9]+:SHELL := bash' <<< \"$sh_lines\"; then", "if false; then",
     T + "check-weakeners_test.sh", "test_makefile_with_other_shell_fails"),
    ("#13: sin exigir -e en .SHELLFLAGS", H + "check-weakeners.sh",
     "-[a-zA-Z]*e[a-zA-Z]*[[:space:]].*pipefail", "pipefail",
     T + "check-weakeners_test.sh", "test_shellflags_without_errexit_fails"),
    ("#11: .SHELLFLAGS sin exigir una sola asignacion", H + "check-weakeners.sh",
     'if [ "$(grep -c . <<< "$fl_lines")" -ne 1 ] ||\n', "if false ||\n",
     T + "check-weakeners_test.sh", "test_second_shellflags_assignment_fails"),
    ("#11: SHELL sin exigir una sola asignacion", H + "check-weakeners.sh",
     'if [ "$(grep -c . <<< "$sh_lines")" -ne 1 ] || ! grep', "if ! grep",
     T + "check-weakeners_test.sh", "test_target_specific_shell_fails"),
    ("#8: sin ::=", H + "check-weakeners.sh",
     "\\.SHELLFLAGS[[:space:]]*[:?+!]*=' \"$f\")\" || fl_lines=\"\"", "\\.SHELLFLAGS[[:space:]]*[:?+!]?=' \"$f\")\" || fl_lines=\"\"",
     T + "check-weakeners_test.sh", "test_posix_assignment_of_shellflags_fails"),
    ("#8: sin +e", H + "check-weakeners.sh",
     "grep -qE '(^|[[:space:]])\\+([a-zA-Z]*e|o[[:space:]])' <<< \"$fl_lines\"; then", "false; then",
     T + "check-weakeners_test.sh", "test_errexit_turned_off_in_shellflags_fails"),
    ("#8: sin define", H + "check-weakeners.sh",
     "grep -nE '^[[:space:]]*((override|export)[[:space:]]+)*define[[:space:]]+(SHELL|\\.SHELLFLAGS|MAKEFLAGS)([[:space:]]|$)' \"$f\" &&", "false &&",
     T + "check-weakeners_test.sh", "test_define_block_for_shell_settings_fails"),
    ("#8: sin include", H + "check-weakeners.sh",
     "grep -nE '^[[:space:]]*-?s?include[[:space:]]' \"$f\" && {", "false && {",
     T + "check-weakeners_test.sh", "test_include_directive_fails"),
    ("#8: sin GNUmakefile ni makefile", H + "check-weakeners.sh",
     'if [ -e "$other" ]; then echo', "if false; then echo",
     T + "check-weakeners_test.sh", "test_makefiles_that_take_precedence_fail"),
    ("#9: sin MAKEFLAGS en cualquier fichero", H + "check-weakeners.sh",
     'grep -nE "$makeflags_re" "$f" && {', "false && {",
     T + "check-weakeners_test.sh", "test_makeflags_in_workflow_env_fails"),
    ("#9: sin variables de make en la linea de ordenes", H + "check-weakeners.sh",
     'grep -nE "${make_cmd}(SHELL|\\.SHELLFLAGS|MAKEFLAGS)[:+]?=" "$f" && {', "false && {",
     T + "check-weakeners_test.sh", "test_make_variable_override_fails"),
    ("#9: sin filtros de go test", H + "check-weakeners.sh",
     "grep -nE 'go[[:space:]]+test[^#]*[[:space:]]--?(test\\.)?(run|skip|short)([=[:space:]]|$)' \"$f\" && {", "false && {",
     T + "check-weakeners_test.sh", "test_go_test_filters_fail"),
    # stop-gate.sh
    ("stop-gate: sin mirar si hay check:", H + "stop-gate.sh",
     "[ -f Makefile ] && grep -q '^check:' Makefile || exit 0", "true",
     T + "stop-gate_test.sh", "test_without_check_target_exits_zero"),
    ("stop-gate: escala al cuarto bloqueo", H + "stop-gate.sh",
     'if [ "$blocks" -ge 3 ]; then', 'if [ "$blocks" -ge 4 ]; then',
     T + "stop-gate_test.sh", "test_red_check_blocks_three_times_then_allows"),
    ("stop-gate: sin pausa para Marcos", H + "stop-gate.sh",
     'if [ -s "$pause_file" ]; then', "if false; then",
     T + "stop-gate_test.sh", "test_pause_file_allows_stop_and_shows_reason"),
    ("stop-gate: sin cache", H + "stop-gate.sh",
     'if [ -n "$tree" ]; then touch "$state_dir/ok-$key"; fi', ":",
     T + "stop-gate_test.sh", "test_green_is_cached_and_resets_counter"),
    ("stop-gate: sin salida rapida con todo subido", H + "stop-gate.sh",
     'if [ -z "$(git status --porcelain)" ] && [ "$unpushed" = "0" ]; then', "if false; then",
     T + "stop-gate_test.sh", "test_clean_tree_without_unpushed_commits_exits_zero"),
    ("stop-gate: git add -A sobre el indice real", H + "stop-gate.sh",
     'if GIT_INDEX_FILE="$idx_dir/index" git add -A', "if git add -A",
     T + "stop-gate_test.sh", "test_hook_leaves_the_real_index_untouched"),
    ("F-0004: clave de cache constante", H + "stop-gate.sh",
     'tree="$(tree_key)"', 'tree="constante"',
     T + "stop-gate_test.sh", "test_untracked_file_change_invalidates_cache"),
    # post-edit.sh
    ("post-edit: sin informar del error de gofmt", H + "post-edit.sh",
     '      report "gofmt failed on $file: $out"\n', "      exit 0\n",
     T + "post-edit_test.sh", "test_syntax_error_is_reported_as_additional_context"),
    # check-skips.sh
    ("#14: check-skips sin exigir la cita", H + "check-skips.sh",
     'if ! cites_known_fallo "$(cut -d: -f3- <<< "$hit")" "$known"; then', "if false; then",
     T + "check-skips_test.sh", "test_unjustified_skip_fails"),
    ("#10: la cita vale tambien en la ruta", H + "check-skips.sh",
     'cites_known_fallo "$(cut -d: -f3- <<< "$hit")" "$known"', 'cites_known_fallo "$hit" "$known"',
     T + "check-skips_test.sh", "test_fallo_in_the_path_does_not_justify_a_skip"),
    ("#10: solo Skip con parentesis", H + "check-skips.sh",
     "'\\.Skip(Now|f)?([^[:alnum:]_]|$)'", "'\\.Skip(Now|f)?\\('",
     T + "check-skips_test.sh", "test_skip_used_as_a_value_is_checked"),
    ("#14: check-skips entra en testdata", H + "check-skips.sh",
     " ':(exclude,glob)**/testdata/**'", "",
     T + "check-skips_test.sh", "test_testdata_fixtures_are_ignored"),
    ("R2 #5: sin mirar los tests que make check no compila", H + "check-skips.sh",
     "if [ -f go.mod ]; then", "if false; then",
     T + "check-skips_test.sh", "test_test_files_the_default_build_never_compiles_fail"),
    ("R2 #5: la cabecera no justifica", H + "check-skips.sh",
     'if ! cites_known_fallo "$header" "$known"; then', "if true; then",
     T + "check-skips_test.sh", "test_justified_ignored_test_file_passes"),
    ("R2 #5: sin mirar los helpers", H + "check-skips.sh",
     """    *) grep -qE '^[[:space:]]*(import[[:space:]]+)?"testing"' "$file" || continue ;;""", "    *) continue ;;",
     T + "check-skips_test.sh", "test_skip_in_a_test_helper_fails"),
    ("R2 #5: Skip de produccion tratado como test", H + "check-skips.sh",
     """    *) grep -qE '^[[:space:]]*(import[[:space:]]+)?"testing"' "$file" || continue ;;""", "    *) ;;",
     T + "check-skips_test.sh", "test_skip_method_in_production_code_passes"),
    # check-attribution.sh, commit-msg, merge-pr.sh
    ("F-0009: sin la regla noreply", H + "check-attribution.sh",
     "|^[[:space:]#>*-]*[a-z-]+:.*noreply@anthropic\\.com", "",
     T + "attribution_test.sh", "test_anthropic_noreply_address_fails"),
    ("F-0009: sin la linea Generated with", H + "check-attribution.sh",
     "|generated with \\[claude code\\]'", "'",
     T + "attribution_test.sh", "test_generated_with_claude_footer_fails"),
    ("F-0009: coautoria ancha otra vez", H + "check-attribution.sh",
     "co-authored-by:[[:space:]]*(claude([[:space:]]+(code|opus|sonnet|haiku|fable|[0-9.]+)[^<]*)?[[:space:]]*<|.*anthropic)",
     "co-authored-by:.*(claude|anthropic)",
     T + "attribution_test.sh", "test_product_text_mentioning_claude_passes"),
    ("F-0009: toda la historia en vez de la rama", H + "check-attribution.sh",
     "if git rev-parse --verify -q refs/remotes/origin/main >/dev/null; then range=refs/remotes/origin/main..HEAD; fi", "",
     T + "attribution_test.sh", "test_attribution_already_in_main_does_not_block_branches"),
    ("F-0009: sin fallar en clon superficial", H + "check-attribution.sh",
     'if [ "$(git rev-parse --is-shallow-repository)" = true ]; then', "if false; then",
     T + "attribution_test.sh", "test_shallow_clone_fails"),
    ("F-0009: sin mirar autor ni committer", H + "check-attribution.sh",
     'if [ -n "$ids" ]; then', "if false; then",
     T + "attribution_test.sh", "test_claude_as_commit_author_fails"),
    ("#12: --message sin -i", H + "check-attribution.sh",
     'if grep -qiE -- "$pattern" "$2"; then', 'if grep -qE -- "$pattern" "$2"; then',
     T + "attribution_test.sh", "test_message_mode_ignores_letter_case"),
    ("#12: el # no se admite delante", H + "check-attribution.sh",
     "pattern='^[[:space:]#>*-]*co-authored-by:", "pattern='^[[:space:]>*-]*co-authored-by:",
     T + "attribution_test.sh", "test_message_mode_checks_comment_lines"),
    ("atribucion: solo el ultimo commit de la rama", H + "check-attribution.sh",
     "--format='%h %s' \"$range\")\"", "--format='%h %s' HEAD^!)\"",
     T + "attribution_test.sh", "test_attribution_in_an_old_commit_of_the_branch_fails"),
    ("commit-msg: no rechaza", H + "commit-msg",
     'if grep -qiE -- "$pattern" "$1"; then', "if false; then",
     T + "attribution_test.sh", "test_commit_msg_hook_rejects_attribution"),
    ("commit-msg: depende de scripts/harness", H + "commit-msg",
     'if grep -qiE -- "$pattern" "$1"; then',
     'if "$(git rev-parse --show-toplevel)/scripts/harness/check-attribution.sh" --message "$1"; [ $? -ne 0 ]; then',
     T + "attribution_test.sh", "test_commit_msg_hook_works_without_the_harness_scripts"),
    ("commit-msg: patron distinto del script", H + "commit-msg",
     "|generated with \\[claude code\\]'", "|generated with \\[claude\\]'",
     T + "attribution_test.sh", "test_hook_and_script_use_the_same_pattern"),
    ("F-0009: merge-pr sin revisar el mensaje del squash", H + "merge-pr.sh",
     '"$here/check-attribution.sh" --message "$work/squash-msg"', ":",
     T + "merge-pr_test.sh", "test_refuses_a_squash_message_with_attribution"),
    ("merge-pr: sin revisar el PR", H + "merge-pr.sh",
     '"$here/check-attribution.sh" --message "$work/pr-msg"', ":",
     T + "merge-pr_test.sh", "test_refuses_a_pr_description_with_attribution"),
    ("merge-pr: sin esperar los checks", H + "merge-pr.sh",
     '  gh pr checks "$pr" --watch --fail-fast\n', "  :\n",
     T + "merge-pr_test.sh", "test_does_not_merge_when_checks_fail"),
    ("merge-pr: sin fijar el commit comprobado", H + "merge-pr.sh",
     '--match-head-commit "$head" ', "",
     T + "merge-pr_test.sh", "test_merges_a_clean_pr_after_green_checks"),
    # secrets-scan.sh, install.sh
    ("#10: la cita del allow vale en la ruta", H + "secrets-scan.sh",
     'cites_known_fallo "$(cut -d: -f3- <<< "$hit")" "$known_ids"', 'cites_known_fallo "$hit" "$known_ids"',
     T + "secrets-scan_test.sh", "test_fallo_in_the_path_does_not_justify_an_allow_comment"),
    ("install.sh sin instalar commit-msg", H + "install.sh",
     "for name in pre-push commit-msg; do", "for name in pre-push; do",
     T + "install_test.sh", "test_installs_settings_scripts_and_pre_push"),
    # settings.json and its test (in the copy, never the live file)
    ("settings: sin denegar el push forzado", ".claude/settings.json",
     '      "Bash(git push --force*)",\n', "",
     T + "settings_test.sh", "test_settings_denies_dangerous_commands"),
    ("settings: sin quitar la atribucion", ".claude/settings.json",
     '"attribution": {\n    "commit": "",\n    "pr": "",\n    "sessionUrl": false\n  },', '"attribution": {},',
     T + "settings_test.sh", "test_settings_disable_claude_attribution"),
    ("settings: el hook Stop apunta a otro script", ".claude/settings.json",
     '/scripts/harness/stop-gate.sh",', '/scripts/harness/check-fallos.sh",',
     T + "settings_test.sh", "test_settings_is_valid_json_with_the_three_hooks"),
    ("settings: un hook que no carga env.sh", ".claude/settings.json",
     '/scripts/harness/stop-gate.sh",', '/scripts/harness/check-fallos.sh",',
     T + "settings_test.sh", "test_every_hook_script_sources_env_first"),
    # Round 2 of the adversarial pass
    ("F-0013: sin la lectura tokenizada", H + "guard-git.sh",
     'if [ "$pushy" -eq 1 ]; then\n  command -v python3', 'if false; then\n  command -v python3',
     T + "guard-git_test.sh", "test_blocks_quoted_values_in_global_options"),
    ("R2: los heredocs no se quitan de la lectura tokenizada", H + "guard-git.sh",
     "    for _, delimiter in delimiters:", "    for _, delimiter in []:",
     T + "guard-git_test.sh", "test_heredocs"),
    ("R2 #2: orden que se decide al ejecutarse", H + "guard-git.sh",
     """if [[ "$cmdword" == *'$'* || "$cmdword" == *'`'* ]] && has_push_word; then""", "if false; then",
     T + "guard-git_test.sh", "test_blocks_git_behind_variables_functions_or_aliases"),
    ("R2 #2: funciones, alias y eval", H + "guard-git.sh",
     'if [ "$defines_code" -eq 1 ] && [ "$pushy" -eq 1 ]; then', "if false; then",
     T + "guard-git_test.sh", "test_blocks_git_behind_variables_functions_or_aliases"),
    ("R2 #2: sin detectar nombre() {", H + "guard-git.sh",
     "if [[ \"$cmd\" =~ [A-Za-z_][A-Za-z0-9_]*[[:space:]]*\\(\\)[[:space:]]*\\{ ]]; then defines_code=1; fi", "",
     T + "guard-git_test.sh", "test_blocks_git_behind_variables_functions_or_aliases"),
    ("R2 #2: sin detectar function, alias y eval como orden", H + "guard-git.sh",
     "    function | alias | eval) defines_code=1 ;;\n", "",
     T + "guard-git_test.sh", "test_blocks_git_behind_variables_functions_or_aliases"),
    ("R2: function suelto en un mensaje bloquea", H + "guard-git.sh",
     "if [[ \"$cmd\" =~ [A-Za-z_][A-Za-z0-9_]*[[:space:]]*\\(\\)[[:space:]]*\\{ ]]; then defines_code=1; fi",
     "if [[ \"$cmd\" =~ (^|[^[:alnum:]_])(function|alias|eval)[[:space:]] ]]; then defines_code=1; fi",
     T + "guard-git_test.sh", "test_allows_commands_that_only_mention_push"),
    ("R2 #3: send-pack", H + "guard-git.sh",
     '      send-pack) block "git send-pack no pasa por el hook pre-push" ;;\n', "      send-pack) ;;\n",
     T + "guard-git_test.sh", "test_blocks_other_push_paths_and_config_from_the_environment"),
    ("R2 #3: configuracion por entorno", H + "guard-git.sh",
     'if [ "$env_config" -eq 1 ] && [ "$has_git" -eq 1 ]; then', "if false; then",
     T + "guard-git_test.sh", "test_blocks_other_push_paths_and_config_from_the_environment"),
    ("R2 #3: alias escrito en el mismo comando", H + "guard-git.sh",
     '      if [ "$touches_config" -eq 1 ]; then', "      if false; then",
     T + "guard-git_test.sh", "test_blocks_other_push_paths_and_config_from_the_environment"),
    ("R2 #3: --get en cualquier sitio cuenta como lectura", H + "guard-git.sh",
     "      --get | --get-all | --get-regexp | --get-urlmatch | --list | -l | get | list) return 0 ;;\n      -*) ;;\n      *) break ;;\n",
     "      --get | --get-all | --get-regexp | --get-urlmatch | --list | -l | get | list) return 0 ;;\n      -*) ;;\n      *) ;;\n",
     T + "guard-git_test.sh", "test_blocks_other_push_paths_and_config_from_the_environment"),
    ("R2 #3: git-push con guion en posicion de orden", H + "guard-git.sh",
     'if [ "$pass" = tokens ] || [ "$i" -eq "$cmd_index" ]; then', "if false; then",
     T + "guard-git_test.sh", "test_blocks_other_push_paths_and_config_from_the_environment"),
    ("R2: git-push suelto en un mensaje bloquea", H + "guard-git.sh",
     'if [ "$pass" = tokens ] || [ "$i" -eq "$cmd_index" ]; then', "if true; then",
     T + "guard-git_test.sh", "test_allows_commands_that_only_mention_push"),
    ("R2 #4: sin seguir cd y pushd", H + "guard-git.sh",
     '    cd | pushd) cur_dir="$(resolve_dir "$cur_dir" "${w[$((i + 1))]:-~}")" ;;\n', "",
     T + "guard-git_test.sh", "test_follows_cd_and_git_c_to_the_repo_that_pushes"),
    ("R2 #9: el numero de 2>&1 cuenta como argumento", H + "guard-git.sh",
     "cmd=\"$(sed -E 's/[0-9]+([<>])/\\1/g' <<< \"$cmd\")\"", "# mutation",
     T + "guard-git_test.sh", "test_closing_tag_with_redirections"),
    ("R2 #7: fusion directa de un PR", H + "guard-git.sh",
     '        merge) if [ "$saw_pr" -eq 1 ]; then block', "        merge) if false; then block",
     T + "guard-git_test.sh", "test_blocks_direct_pull_request_merges"),
    ("R2 #6: MAKEFLAGS solo con la primera opcion", H + "check-weakeners.sh",
     "[:=](.*[[:space:]\"\\'=])?(-?[a-zA-Z]*[ik]", "[:=][[:space:]]*(-?[a-zA-Z]*[ik]",
     T + "check-weakeners_test.sh", "test_makeflags_with_several_options_fails"),
    ("R2 #6: sin abreviaturas de --ignore y --keep", H + "check-weakeners.sh",
     '--ign[a-z-]*|--kee[a-z-]*)([[:space:]]|$)" "$f" && { echo "$f: make con -i o -k"',
     '--ignore-errors|--keep-going)([[:space:]]|$)" "$f" && { echo "$f: make con -i o -k"',
     T + "check-weakeners_test.sh", "test_long_option_abbreviations_fail"),
    ("R2 #6: .IGNORE con sangria", H + "check-weakeners.sh",
     "grep -nE '^[[:space:]]*\\.IGNORE'", "grep -nE '^\\.IGNORE'",
     T + "check-weakeners_test.sh", "test_indented_ignore_fails"),
    ("R2 #6: sin set +o errexit", H + "check-weakeners.sh",
     "(\\+[a-zA-Z]*e|\\+o[[:space:]]+(errexit|pipefail))", "(\\+[a-zA-Z]*e)",
     T + "check-weakeners_test.sh", "test_set_plus_o_fails"),
    ("R2 #6: sin true por ruta", H + "check-weakeners.sh",
     "\\|\\|[[:space:]]*((/[^[:space:];]*/)?true|", "\\|\\|[[:space:]]*(true|",
     T + "check-weakeners_test.sh", "test_true_by_path_fails"),
    ("R2 #7: merge-pr sin mirar el commit que entro en main", H + "merge-pr.sh",
     'if ! "$here/check-attribution.sh" --message "$work/merged-msg"; then', "if false; then",
     T + "merge-pr_test.sh", "test_checks_the_commit_that_entered_main"),
    # Documentation checks (verificador-apis) and F-0012
    ("docs: la pausa por stderr con exit 0", H + "stop-gate.sh",
     'tell_marcos "Pausa para Marcos: $(cat "$pause_file")"', 'echo "Pausa para Marcos: $(cat "$pause_file")" >&2',
     T + "stop-gate_test.sh", "test_pause_file_allows_stop_and_shows_reason"),
    ("docs: parar en rojo sin avisar a Marcos", H + "stop-gate.sh",
     '  tell_marcos "make check sigue en rojo: Claude para tras 3 intentos; el diagn', '  : "',
     T + "stop-gate_test.sh", "test_red_check_blocks_three_times_then_allows"),
    ("docs: sin mirar el cwd de la sesion", H + "guard-git.sh",
     '  cur_dir="${session_cwd:-$PWD}"', '  cur_dir="$PWD"',
     T + "guard-git_test.sh", "test_uses_the_cwd_of_the_session"),
    ("guard: sin jq deja pasar", H + "guard-git.sh",
     "if ! command -v jq >/dev/null 2>&1; then", "if false; then",
     T + "guard-git_test.sh", "test_blocks_everything_without_jq"),
    ("docs: matcher solo Bash", ".claude/settings.json",
     '"matcher": "Bash|Monitor|PowerShell",', '"matcher": "Bash",',
     T + "settings_test.sh", "test_settings_is_valid_json_with_the_three_hooks"),
    ("F-0012: check-pipes no encuentra nada", H + "check-pipes.sh",
     "early_exit='(^|[^|])", "early_exit='^NUNCA$(^|[^|])",
     T + "check-pipes_test.sh", "test_pipe_into_head_fails"),
    ("F-0012: check-pipes confunde || con |", H + "check-pipes.sh",
     "early_exit='(^|[^|])\\|", "early_exit='\\|",
     T + "check-pipes_test.sh", "test_or_list_and_here_strings_pass"),
    ("F-0012: el test de settings vuelve a usar | head", T + "settings_test.sh",
     "code=\"$(grep -vE '^[[:space:]]*(#|$)' \"$REPO_DIR/$s\")\"",
     "code=\"$(grep -vE '^[[:space:]]*(#|$)' \"$REPO_DIR/$s\" | head -n 2)\"",
     T + "settings_test.sh", "test_every_hook_script_sources_env_first"),
    ("F-0008: SETTINGS_FILE relativo", T + "settings_test.sh",
     'SETTINGS="$(cd "$(dirname "$SETTINGS")" && pwd)/$(basename "$SETTINGS")"\n', "",
     T + "settings_test.sh", "test_settings_file_can_be_relative"),
    # Round 3, low finding: without python3 a push is blocked.
    ("guard: sin python3 se salta la lectura tokenizada", H + "guard-git.sh",
     'if [ "$pushy" -eq 1 ]; then', 'if [ "$pushy" -eq 1 ] && command -v python3 >/dev/null 2>&1; then',
     T + "guard-git_test.sh", "test_blocks_a_push_without_python3"),
    ("guard: sin bloquear cuando falta python3", H + "guard-git.sh",
     '  command -v python3 >/dev/null 2>&1 || block "falta python3; guard-git no puede leer las comillas de un push"\n', "",
     T + "guard-git_test.sh", "test_blocks_a_push_without_python3"),
]


def run_test(copy, test_file, name):
    env = dict(os.environ)
    env["PATH"] = os.path.expanduser("~/.local/go/bin") + ":" + os.path.expanduser("~/go/bin") + ":" + env["PATH"]
    env["GITLEAKS"] = os.path.join(copy, ".tools", "gitleaks-8.30.1")
    env.pop("SETTINGS_FILE", None)
    p = subprocess.run(["bash", test_file, name], cwd=copy, env=env,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=300)
    return p.returncode, re.sub(r"\x1b\[[0-9;]*m", "", p.stdout)


def main():
    work = tempfile.mkdtemp(prefix="mutate-")
    copy = os.path.join(work, "repo")
    os.makedirs(copy)
    rev = sys.argv[1] if len(sys.argv) > 1 else "HEAD"
    tree = subprocess.run(["git", "-C", REPO, "archive", rev], stdout=subprocess.PIPE, check=True).stdout
    subprocess.run(["tar", "-x", "-C", copy], input=tree, check=True)
    os.makedirs(os.path.join(copy, ".tools"))
    shutil.copy2(os.path.join(REPO, ".tools", "gitleaks-8.30.1"), os.path.join(copy, ".tools"))
    head = subprocess.run(["git", "-C", REPO, "rev-parse", rev], stdout=subprocess.PIPE, text=True, check=True).stdout.strip()
    print(f"copia de {head} en un directorio temporal; el repo no se toca\n")
    ok = True
    for title, path, old, new, test_file, name in MUTATIONS:
        full = os.path.join(copy, path)
        original = open(full, encoding="utf-8").read()
        if original.count(old) != 1:
            print(f"### {title}\nNO APLICABLE: el fragmento aparece {original.count(old)} veces en {path}\nresultado: MAL\n")
            ok = False
            continue
        with open(full, "w", encoding="utf-8") as fh:
            fh.write(original.replace(old, new))
        rc_mut, out_mut = run_test(copy, test_file, name)
        with open(full, "w", encoding="utf-8") as fh:
            fh.write(original)
        restored = open(full, encoding="utf-8").read() == original
        rc_ok, out_ok = run_test(copy, test_file, name)
        red = rc_mut != 0 and f"--- FAIL: {name}" in out_mut
        green = rc_ok == 0 and f"--- PASS: {name}" in out_ok
        ok = ok and red and green and restored
        print(f"### {title}")
        print(f"fichero: {path}; test: {test_file}::{name}")
        print(f"con la mutacion (debe ser rojo): exit {rc_mut}")
        print("\n".join(l for l in out_mut.splitlines() if l.strip())[-1200:])
        print(f"restaurado byte a byte: {restored}")
        print(f"con la correccion (debe ser verde): exit {rc_ok}: {out_ok.strip().splitlines()[-1]}")
        print(f"resultado: {'OK' if red and green and restored else 'MAL'}\n")
    shutil.rmtree(work)
    live = subprocess.run(["git", "-C", REPO, "status", "--porcelain", "--", "scripts", ".claude"],
                          stdout=subprocess.PIPE, text=True, check=True).stdout
    print("repo en uso sin cambios" if not live.strip() else "repo en uso CAMBIADO:\n" + live)
    ok = ok and not live.strip()
    print("TODAS OK" if ok else "HAY MUTACIONES MAL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
