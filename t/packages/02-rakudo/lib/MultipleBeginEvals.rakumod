use MONKEY-SEE-NO-EVAL;
# Each string-form EVAL runs a two-step compile in ForeignCode: a
# `:target('ast')` first pass and a `:from('qast')` second pass. The
# first pass invokes HLL::Backend.start, which on MoarVM pushes a fresh
# frame list onto %COMPILING<moar><frames>. The first pass stops at
# 'ast' so the matching pop in QASTCompilerMAST.to_mast does not run.
# HLL::Compiler.compile pops the dangling level at the end of the first
# pass via the compile_snapshot / compile_cleanup hooks on the MoarVM
# backend, so the second pass's MAST migrates its frames into the outer
# compile's frame list. Running several EVALs in one BEGIN exercises
# that cleanup across a sequence of nested compiles.
our @subs;
BEGIN {
    @subs = (
        EVAL('sub { 1 }'),
        EVAL('sub { 2 }'),
        EVAL('sub { 3 }'),
        EVAL('sub { 4 }'),
        EVAL('sub { 5 }'),
    );
}
