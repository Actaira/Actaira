#!/usr/bin/env bash
# Tests for scripts/harness/check-personal.sh (CLAUDE.md, rule 4: nothing
# personal in the repo, the repos are public; F-0015). The fixtures use a
# made-up private list passed with --terms; the default list is only exercised
# from a fake HOME.
source "$(dirname "$0")/lib.sh"

# term_list <file>: a private list with made-up terms.
term_list() {
  printf '%s\n' "# lista de prueba" "nombre de prueba | Persona Ficticia" "cuenta de prueba | cuentaficticia" \
    "frase de prueba | una frase ficticia de cinco palabras" > "$1"
}

personal() { # <repo>: runs the check with the test list; prints the exit code; output in $T/out
  local rc=0
  term_list "$T/terms.txt"
  (cd "$1" && env -u GITHUB_ACTIONS "$HARNESS_DIR/check-personal.sh" --terms "$T/terms.txt") >"$T/out" 2>&1 || rc=$?
  echo "$rc"
}

test_clean_repo_passes() {
  init_repo "$T/repo"
  assert_eq "$(personal "$T/repo")" "0" "repo limpio ($(cat "$T/out"))"
}

test_term_in_a_tracked_file_fails_without_printing_it() {
  init_repo "$T/repo"
  printf 'Hola.\nEscribe a PERSONA   Fictícia si hace falta.\n' > "$T/repo/notes.md"
  git -C "$T/repo" add notes.md
  assert_eq "$(personal "$T/repo")" "1" "término en un fichero seguido"
  assert_contains "$(cat "$T/out")" "dato personal (nombre de prueba) en notes.md:2"
  assert_not_contains "$(cat "$T/out")" "ctici" "la salida nunca enseña el texto: los logs de la CI son públicos"
}

test_term_split_by_punctuation_or_lines_fails() {
  init_repo "$T/repo"
  printf 'ver `persona/ficticia`\n' > "$T/repo/a.md"
  printf 'firma: persona\nficticia\n' > "$T/repo/b.md"
  printf 'una frase ficticia\nde cinco palabras\n' > "$T/repo/c.md"
  assert_eq "$(personal "$T/repo")" "1" "término partido"
  assert_contains "$(cat "$T/out")" "a.md:1"
  assert_contains "$(cat "$T/out")" "b.md:1"
  assert_contains "$(cat "$T/out")" "dato personal (frase de prueba) en c.md:1"
}

test_term_inside_other_words_passes() {
  init_repo "$T/repo"
  printf 'impersona ficticiamente, personas ficticias, micuentaficticia\n' > "$T/repo/a.md"
  assert_eq "$(personal "$T/repo")" "0" "solo palabras enteras ($(cat "$T/out"))"
}

# Review of the clean import, findings 7: names, other encodings and invisible characters.
test_term_in_a_path_other_encodings_or_with_invisible_characters_fails() {
  init_repo "$T/repo"
  mkdir -p "$T/repo/docs"
  printf 'nada\n' > "$T/repo/docs/cuentaficticia.md"
  printf '\xff\xfe' > "$T/repo/u16.txt"
  printf 'hola cuentaficticia\n' | iconv -f utf-8 -t utf-16le >> "$T/repo/u16.txt"
  printf 'hola persona fict\xedcia\n' > "$T/repo/latin1.txt"
  printf 'hola cuenta\xe2\x80\x8bficticia\n' > "$T/repo/zw.txt"
  assert_eq "$(personal "$T/repo")" "1" "nombre, UTF-16, Latin-1 y carácter invisible"
  assert_contains "$(cat "$T/out")" "dato personal (cuenta de prueba) en el nombre de docs/cuentaficticia.md"
  assert_contains "$(cat "$T/out")" "dato personal (cuenta de prueba) en u16.txt:1"
  assert_contains "$(cat "$T/out")" "dato personal (nombre de prueba) en latin1.txt:1"
  assert_contains "$(cat "$T/out")" "dato personal (cuenta de prueba) en zw.txt:1"
}

test_untracked_file_fails_and_ignored_file_passes() {
  init_repo "$T/repo"
  printf 'cuentaficticia\n' > "$T/repo/nuevo.md"
  assert_eq "$(personal "$T/repo")" "1" "fichero sin seguir"
  assert_contains "$(cat "$T/out")" "dato personal (cuenta de prueba) en nuevo.md:1"
  printf 'privado/\n' > "$T/repo/.gitignore"
  mkdir -p "$T/repo/privado"
  mv "$T/repo/nuevo.md" "$T/repo/privado/"
  assert_eq "$(personal "$T/repo")" "0" "fichero ignorado ($(cat "$T/out"))"
}

# Review of the clean import, finding 4: what the branch already published.
test_term_only_in_the_index_or_in_an_earlier_commit_fails() {
  init_repo "$T/repo"
  printf 'cuentaficticia\n' > "$T/repo/a.md"
  git -C "$T/repo" add a.md
  rm "$T/repo/a.md"
  assert_eq "$(personal "$T/repo")" "1" "término solo en el índice"
  assert_contains "$(cat "$T/out")" "dato personal (cuenta de prueba) en el índice"
  git -C "$T/repo" commit -q -m "Add a"
  git -C "$T/repo" rm -q a.md
  git -C "$T/repo" commit -q -m "Remove a"
  assert_eq "$(personal "$T/repo")" "1" "término en un commit anterior de la rama"
  assert_contains "$(cat "$T/out")" "dato personal (cuenta de prueba) en el commit $(git -C "$T/repo" rev-parse --short HEAD~1)"
}

test_commit_message_and_identity_fail() {
  init_repo "$T/repo"
  git -C "$T/repo" commit -q --allow-empty -m "Add notes" -m "gracias a cuentaficticia"
  assert_eq "$(personal "$T/repo")" "1" "término en un mensaje de commit"
  assert_contains "$(cat "$T/out")" "dato personal (cuenta de prueba) en el commit $(git -C "$T/repo" rev-parse --short HEAD)"
  init_repo "$T/repo2"
  git -C "$T/repo2" -c user.name="Persona Ficticia" commit -q --allow-empty -m "Add notes"
  assert_eq "$(personal "$T/repo2")" "1" "término en el autor de un commit"
  assert_contains "$(cat "$T/out")" "dato personal (nombre de prueba) en el commit"
}

# Review of the clean import, finding 2 (F-0009 again): main is not scanned
# again, so a finding there can never keep every branch red.
test_only_the_commits_of_the_branch_are_scanned() {
  init_repo "$T/repo"
  git -C "$T/repo" -c user.name="Persona Ficticia" commit -q --allow-empty -m "Old commit in main"
  git -C "$T/repo" update-ref refs/remotes/origin/main HEAD
  git -C "$T/repo" switch -q -c e1/paso-1-x
  git -C "$T/repo" commit -q --allow-empty -m "Clean step"
  assert_eq "$(personal "$T/repo")" "0" "commit de main fuera del rango ($(cat "$T/out"))"
}

test_personal_email_fails_outside_testdata_and_identities() {
  init_repo "$T/repo"
  local addr="alguien.ejemplo@""gmail.com"
  printf 'contacto: %s\n' "$addr" > "$T/repo/a.md"
  assert_eq "$(personal "$T/repo")" "1" "correo de un proveedor personal"
  assert_contains "$(cat "$T/out")" "correo de un proveedor personal en a.md:1"
  printf 'autor: 123+Actaira@users.noreply.github.com, no-reply@mail.actaira.com\n' > "$T/repo/a.md"
  mkdir -p "$T/repo/testdata/repo"
  printf '{"author": "%s"}\n' "$addr" > "$T/repo/testdata/repo/package.json"
  git -C "$T/repo" -c user.email="$addr" commit -q --allow-empty -m "From a contributor"
  assert_eq "$(personal "$T/repo")" "0" "noreply, fixtures de testdata y correo de un colaborador ($(cat "$T/out"))"
}

# The project contact address is not personal (Marcos, 2026-09-29): it may go
# on the website and in user docs, and code reads it from ACTAIRA_CONTACT_EMAIL.
# The check allows the one set in config/contact.env, outside code files.
contact_config() { # <repo> <address>
  mkdir -p "$1/config"
  printf '# contacto del proyecto\nACTAIRA_CONTACT_EMAIL=%s\n' "$2" > "$1/config/contact.env"
}

test_project_contact_email_passes_outside_code() {
  init_repo "$T/repo"
  local contact="proyecto.ficticio@""gmail.com"
  contact_config "$T/repo" "$contact"
  mkdir -p "$T/repo/web/.well-known" "$T/repo/docs"
  printf 'Contact: mailto:%s\n' "$contact" > "$T/repo/web/.well-known/security.txt"
  printf 'Escribe a %s.\n' "$(tr 'a-z' 'A-Z' <<< "$contact")" > "$T/repo/docs/contacto.md"
  assert_eq "$(personal "$T/repo")" "0" "correo de contacto en la web y en la documentación ($(cat "$T/out"))"
  printf 'Contact: %s\n' "$contact" > "$T/pr-msg"
  local rc=0
  (cd "$T/repo" && env -u GITHUB_ACTIONS "$HARNESS_DIR/check-personal.sh" --terms "$T/terms.txt" --files "$T/pr-msg") >"$T/out" 2>&1 || rc=$?
  assert_eq "$rc" "0" "correo de contacto en el texto de un PR ($(cat "$T/out"))"
}

test_other_personal_email_fails_next_to_the_contact_email() {
  init_repo "$T/repo"
  local contact="proyecto.ficticio@""gmail.com" other="alguien.ejemplo@""gmail.com"
  contact_config "$T/repo" "$contact"
  printf 'Contacto: %s, o %s.\nx%s\n' "$contact" "$other" "$contact" > "$T/repo/docs.md"
  assert_eq "$(personal "$T/repo")" "1" "otro gmail junto al de contacto"
  assert_contains "$(cat "$T/out")" "correo de un proveedor personal en docs.md:1"
  assert_contains "$(cat "$T/out")" "correo de un proveedor personal en docs.md:2"
}

test_contact_email_fixed_in_code_fails() {
  init_repo "$T/repo"
  local contact="proyecto.ficticio@""gmail.com"
  contact_config "$T/repo" "$contact"
  mkdir -p "$T/repo/cmd" "$T/repo/web"
  printf 'package main\n\nconst contact = "%s"\n' "$contact" > "$T/repo/cmd/main.go"
  printf 'export const contact = "%s";\n' "$contact" > "$T/repo/web/contact.ts"
  assert_eq "$(personal "$T/repo")" "1" "correo de contacto fijo en el código"
  assert_contains "$(cat "$T/out")" "correo de contacto fijo en el código (va por ACTAIRA_CONTACT_EMAIL) en cmd/main.go:3"
  assert_contains "$(cat "$T/out")" "correo de contacto fijo en el código (va por ACTAIRA_CONTACT_EMAIL) en web/contact.ts:1"
}

test_contact_email_without_its_config_fails() {
  init_repo "$T/repo"
  printf 'Contacto: %s\n' "proyecto.ficticio@""gmail.com" > "$T/repo/docs.md"
  assert_eq "$(personal "$T/repo")" "1" "sin config/contact.env no hay correo permitido"
  assert_contains "$(cat "$T/out")" "correo de un proveedor personal en docs.md:1"
}

# merge-pr.sh scans the squash message and the PR text with --files, outside
# any repo: those texts enter main or GitHub without passing through the CI.
test_files_mode_scans_only_the_given_files() {
  term_list "$T/terms.txt"
  printf 'Adds the demo.\n\nThanks, cuentaficticia.\n' > "$T/squash-msg"
  printf 'clean\n' > "$T/pr-msg"
  local rc=0
  (cd "$T" && env -u GITHUB_ACTIONS "$HARNESS_DIR/check-personal.sh" --terms "$T/terms.txt" --files "$T/squash-msg" "$T/pr-msg") >"$T/out" 2>&1 || rc=$?
  assert_eq "$rc" "1" "término en el mensaje del squash"
  assert_contains "$(cat "$T/out")" "dato personal (cuenta de prueba) en squash-msg:3"
  assert_not_contains "$(cat "$T/out")" "pr-msg"
}

# The default private list is read from ~/actaira-ws/privado, outside git.
test_default_private_list_is_used() {
  init_repo "$T/repo"
  mkdir -p "$T/home/actaira-ws/privado"
  term_list "$T/home/actaira-ws/privado/datos-personales.txt"
  printf 'cuentaficticia\n' > "$T/repo/a.md"
  local rc=0
  (cd "$T/repo" && env -u GITHUB_ACTIONS HOME="$T/home" "$HARNESS_DIR/check-personal.sh") >"$T/out" 2>&1 || rc=$?
  assert_eq "$rc" "1" "lista privada por defecto"
  assert_contains "$(cat "$T/out")" "dato personal (cuenta de prueba) en a.md:1"
}

# Outside the CI a missing private list fails; the CI never has it, and says so.
test_missing_list_fails_locally_and_is_announced_in_ci() {
  init_repo "$T/repo"
  local rc=0
  (cd "$T/repo" && env -u GITHUB_ACTIONS HOME="$T/nohome" "$HARNESS_DIR/check-personal.sh") >"$T/out" 2>&1 || rc=$?
  assert_eq "$rc" "1" "sin lista privada en local"
  assert_contains "$(cat "$T/out")" "falta la lista privada de términos"
  rc=0
  (cd "$T/repo" && GITHUB_ACTIONS=true HOME="$T/nohome" "$HARNESS_DIR/check-personal.sh") >"$T/out" 2>&1 || rc=$?
  assert_eq "$rc" "0" "sin lista privada en la CI"
  assert_contains "$(cat "$T/out")" "la CI no tiene la lista privada de términos; solo busca correos"
  local addr="alguien.ejemplo@""gmail.com"
  printf 'contacto: %s\n' "$addr" > "$T/repo/a.md"
  rc=0
  (cd "$T/repo" && GITHUB_ACTIONS=true HOME="$T/nohome" "$HARNESS_DIR/check-personal.sh") >"$T/out" 2>&1 || rc=$?
  assert_eq "$rc" "1" "correos en la CI"
}

run_tests "$@"
