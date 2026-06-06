use MONKEY-SEE-NO-EVAL;
# Precompiling this module used to fail under RAKUDO_RAKUAST=1 with
# `missing static code ref for closure` because the string-EVAL path in
# ForeignCode.rakumod skipped the IMPL-FIXUP-COMPILED-CODEREFS step that
# the AST-EVAL path runs.
our &foo;
BEGIN { &foo = EVAL 'sub () { "from-precomped-string-eval" }' }
