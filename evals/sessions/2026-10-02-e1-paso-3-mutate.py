#!/usr/bin/env python3
"""Mutation proofs of E1 step 1.3 (e1/paso-3-modelo).

The canonical JSON, the model, the coverage block, the lockfile, the contract
and the two JSON Schemas. Same method as the other proofs: on a copy of a
committed tree (git archive) in a temporary directory, never in the live repo
(F-0008). For each guard: break it in the copy, run its Go test (it must be
red, for that reason), restore the file byte for byte and run the test again
(it must be green). Exits 1 if any mutation is not proven.
Usage: python3 evals/sessions/2026-10-02-e1-paso-3-mutate.py [commit]; the
commit defaults to HEAD, and the output records which one was copied.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CAN = "pkg/lock/canonical.go"
LOCK = "pkg/lock/lockfile.go"
MODEL = "pkg/model/model.go"
COV = "pkg/coverage/coverage.go"
INT = "pkg/intent/intent.go"
ACM = "schemas/acm.v0.json"
LSCH = "schemas/actaira.lock.v1.json"

# (title, file, fragment, replacement, package, test name)
MUTATIONS = [
    ("canonical: claves por bytes y no por UTF-16", CAN,
     "return lessUTF16(keys[i], keys[j])", "return keys[i] < keys[j]",
     "./pkg/lock", "TestCanonicalVectors"),
    ("canonical: no comprueba NFC", CAN,
     "\tif !norm.NFC.IsNormalString(s) {\n", "\tif false && !norm.NFC.IsNormalString(s) {\n",
     "./pkg/lock", "TestCanonicalRejectsWhatIsOutsideTheSubset"),
    ("canonical: no comprueba UTF-8", CAN,
     "\tif !utf8.ValidString(s) {\n", "\tif false && !utf8.ValidString(s) {\n",
     "./pkg/lock", "TestCanonicalRejectsWhatIsOutsideTheSubset"),
    ("canonical: enteros sin rango", CAN,
     "\tif n > maxInt || n < -maxInt {\n", "\tif false {\n",
     "./pkg/lock", "TestCanonicalRejectsWhatIsOutsideTheSubset"),
    ("canonical: escapa < como en HTML", CAN,
     "\t\t\t\tb.WriteRune(r)\n", "\t\t\t\tif r == '<' {\n\t\t\t\t\tb.WriteString(`\\u003c`)\n\t\t\t\t} else {\n\t\t\t\t\tb.WriteRune(r)\n\t\t\t\t}\n",
     "./pkg/lock", "TestCanonicalVectors"),
    ("canonical: escapes en mayúsculas", CAN,
     'const hex = "0123456789abcdef"', 'const hex = "0123456789ABCDEF"',
     "./pkg/lock", "TestCanonicalVectors"),
    ("model: id sin separar sus partes", MODEL,
     "\t\tbinary.BigEndian.PutUint64(n[:], uint64(len(part)))\n\t\th.Write(n[:])\n", "\t\t_ = binary.BigEndian\n\t\t_ = n\n",
     "./pkg/model", "TestIDSeparatesItsParts"),
    ("model: resuelta con un solo hash", MODEL,
     'return t.SchemaHash != "" && t.DescriptionHash != ""', 'return t.SchemaHash != ""',
     "./pkg/model", "TestToolResolvedNeedsBothHashes"),
    ("coverage: detectadas cuenta referencias, no tools", COV,
     "axes(len(callTools), resolved, len(entries))", "axes(len(out[a.ID]), resolved, len(entries))",
     "./pkg/coverage", "TestCoverageDetectedCountsEachToolOnce"),
    ("coverage: una tool sin resolver no deja entrada", COV,
     '\t\t\t\tentries = append(entries, Entry{Location: t.Source, Kind: "tool", Reason: "definition_not_resolved"})\n', "",
     "./pkg/coverage", "TestCoverageResolvedNeedsTheWholeDefinition"),
    ("coverage: un eje sin fuente vale 0", COV,
     "\t\t{Name: Effective, NoSource: NotFromRepo},\n", "\t\t{Name: Effective, Value: v(0)},\n",
     "./pkg/coverage", "TestCoverageAxisWithoutSourceIsNotZero"),
    ("coverage: saltado y unresolved a la vez", COV,
     "\t\tif skipped[f.Entry.Location.File] {\n", "\t\tif false {\n",
     "./pkg/coverage", "TestCoverageUnseenAndUnresolvedNeverMix"),
    ("coverage: el resumen olvida el bloque del repo", COV,
     "return summarize(append(append([]Source{}, a.Sources...), c.Repo.Sources...), c.Repo.Skipped,", "return summarize(append([]Source{}, a.Sources...), c.Repo.Skipped,",
     "./pkg/coverage", "TestCoverageSourcesCountObservedOfKnown"),
    ("coverage: las declaraciones sin resolver no salen", COV,
     "\t\t\ts.UnresolvedSourceDeclarations = append(s.UnresolvedSourceDeclarations, e.Location)\n", "",
     "./pkg/coverage", "TestCoverageUnresolvedSourceDeclarationsAppearInTheSummary"),
    ("coverage: lo saltado no es no visto", COV,
     '\t\ts.Unseen = append(s.Unseen, Unseen{Kind: "skipped", Name: k.Path, Reason: k.Reason})\n', "\t\t_ = k\n",
     "./pkg/coverage", "TestCoverageSkippedPartsAreUnseen"),
    ("coverage: sin agentes no hay bloque del repo", COV,
     '\tc.Repo.Sources = append(c.Repo.Sources, Source{Kind: SourceRepo, Name: ".", State: Observed, Extractors: in.Extractors})\n', "",
     "./pkg/coverage", "TestCoverageRepoBlockIsShownWithoutAgents"),
    ("coverage: una variable no configurada sin motivo", COV,
     "\t\t\tsources = append(sources, Source{Kind: SourceEnvRef, Name: s.Name, Locations: s.Locations, State: NotConfigured, Reason: ReasonNoRunnerConfig})\n",
     "\t\t\tsources = append(sources, Source{Kind: SourceEnvRef, Name: s.Name, Locations: s.Locations, State: NotConfigured})\n",
     "./pkg/coverage", "TestCoverageSourceNotObservedCarriesReason"),
    ("lock: listas sin ordenar", LOCK,
     '\t\t"agents":         sorted(agents),\n', '\t\t"agents":         agents,\n',
     "./pkg/lock", "TestLockIsTheSameWhateverTheOrderOfItsInputs"),
    ("lock: lee otra versión del esquema", LOCK,
     "\tif raw.SchemaVersion == nil || *raw.SchemaVersion != SchemaVersion {\n", "\tif raw.SchemaVersion == nil {\n",
     "./pkg/lock", "TestLockRejectsAnotherSchemaVersion"),
    ("lock: acepta campos desconocidos", LOCK,
     "\tdec.DisallowUnknownFields()\n\tvar raw rawLock\n", "\tvar raw rawLock\n",
     "./pkg/lock", "TestLockRejectsUnknownFields"),
    ("lock: no escribe el contrato", LOCK,
     '\t\tout["intent"] = l.Intent.Value()\n', "",
     "./pkg/lock", "TestLockKeepsTheIntentBlock"),
    ("lock: guarda un efecto", LOCK,
     "\tif t.Effect != model.EffectUnknown {\n", "\tif false {\n",
     "./pkg/lock", "TestLockRejectsWhatTheModelDoesNotAllow"),
    ("intent: no caduca", INT,
     "\t\tcase c.Expires < today:\n", "\t\tcase false:\n",
     "./pkg/intent", "TestDraftOrExpiredIntentDoesNotCount"),
    ("intent: la misma capacidad en allow y deny", INT,
     "\t\t\t} else if allowed[cap] {\n", "\t\t\t} else if false {\n",
     "./pkg/intent", "TestIntentValidationRejectsACapabilityBothAllowedAndDenied"),
    ("intent: importes con decimales", INT,
     "\tv, err := strconv.ParseInt(n.String(), 10, 64)\n", "\tf, err := strconv.ParseFloat(n.String(), 64)\n\tv := int64(f)\n",
     "./pkg/intent", "TestIntentAmountsAreIntegersInMinorUnits"),
    ("intent: un contrato huérfano pasa", INT,
     "\tif len(orphans) > 0 {\n", "\tif false {\n",
     "./pkg/intent", "TestIntentOrphanContractIsAnInputError"),
    ("intent: sin contrato es un contrato en vigor", INT,
     "\treturn NoContract\n}", "\treturn InForce\n}",
     "./pkg/intent", "TestAgentWithoutIntentIsNoContractNotAnError"),
    ("intent: no normaliza a NFC", INT,
     "func nfc(s string) string { return norm.NFC.String(s) }", "func nfc(s string) string { _ = norm.NFC; return s }",
     "./pkg/intent", "TestIntentStringsAreReadAsNFC"),
    ("intent: comodines en las capacidades", INT,
     "capabilityRE = regexp.MustCompile(`^[a-z][a-z0-9_]*\\.[a-z][a-z0-9_]*$`)", "capabilityRE = regexp.MustCompile(`^[a-z][a-z0-9_]*\\.([a-z][a-z0-9_]*|\\*)$`)",
     "./pkg/intent", "TestIntentCapabilityFormHasNoWildcards"),
    ("esquema ACM: un contrato aceptado con confianza", ACM,
     '"then": { "required": ["accepted_by", "accepted_at"], "not": { "required": ["confidence"] } }', '"then": { "required": ["accepted_by", "accepted_at"] }',
     "./pkg/lock", "TestACMSchemaAndGoAgree"),
    ("esquema del lockfile: guarda un efecto", LSCH,
     '"effect": { "const": "unknown" },', '"effect": { "enum": ["unknown", "write"] },',
     "./pkg/lock", "TestLockSchemaAndGoAgree"),
]


def run_test(copy, pkg, name):
    env = dict(os.environ)
    env["PATH"] = os.path.expanduser("~/.local/go/bin") + ":" + os.path.expanduser("~/go/bin") + ":" + env["PATH"]
    env.pop("GOFLAGS", None)
    env["GOTOOLCHAIN"] = "local"
    p = subprocess.run(["go", "test", "-count=1", "-v", "-run", f"^{name}$", pkg], cwd=copy, env=env,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=300)
    return p.returncode, p.stdout


def main():
    work = tempfile.mkdtemp(prefix="mutate-")
    copy = os.path.join(work, "repo")
    os.makedirs(copy)
    rev = sys.argv[1] if len(sys.argv) > 1 else "HEAD"
    tree = subprocess.run(["git", "-C", REPO, "archive", rev], stdout=subprocess.PIPE, check=True).stdout
    subprocess.run(["tar", "-x", "-C", copy], input=tree, check=True)
    head = subprocess.run(["git", "-C", REPO, "rev-parse", rev], stdout=subprocess.PIPE, text=True, check=True).stdout.strip()
    print(f"copia de {head} en un directorio temporal; el repo no se toca\n")
    ok = True
    for title, path, old, new, pkg, name in MUTATIONS:
        full = os.path.join(copy, path)
        original = open(full, encoding="utf-8").read()
        if original.count(old) != 1:
            print(f"### {title}\nNO APLICABLE: el fragmento aparece {original.count(old)} veces en {path}\nresultado: MAL\n")
            ok = False
            continue
        with open(full, "w", encoding="utf-8") as fh:
            fh.write(original.replace(old, new))
        rc_mut, out_mut = run_test(copy, pkg, name)
        with open(full, "w", encoding="utf-8") as fh:
            fh.write(original)
        restored = open(full, encoding="utf-8").read() == original
        rc_ok, out_ok = run_test(copy, pkg, name)
        red = rc_mut != 0 and f"--- FAIL: {name}" in out_mut
        green = rc_ok == 0 and f"--- PASS: {name}" in out_ok
        ok = ok and red and green and restored
        print(f"### {title}")
        print(f"fichero: {path}; test: {pkg}::{name}")
        print(f"con la mutacion (debe ser rojo): exit {rc_mut}")
        print("\n".join(l for l in out_mut.splitlines() if l.strip() and not l.startswith("=== "))[-700:])
        print(f"restaurado byte a byte: {restored}")
        print(f"con la correccion (debe ser verde): exit {rc_ok}: {out_ok.strip().splitlines()[-1]}")
        print(f"resultado: {'OK' if red and green and restored else 'MAL'}\n")
    shutil.rmtree(work)
    live = subprocess.run(["git", "-C", REPO, "status", "--porcelain", "--", "pkg", "schemas"],
                          stdout=subprocess.PIPE, text=True, check=True).stdout
    print("repo en uso sin cambios" if not live.strip() else "repo en uso CAMBIADO:\n" + live)
    ok = ok and not live.strip()
    print("TODAS OK" if ok else "HAY MUTACIONES MAL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
