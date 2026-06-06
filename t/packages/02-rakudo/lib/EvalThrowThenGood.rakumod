use MONKEY-SEE-NO-EVAL;
# Each string EVAL runs a compile via HLL::Compiler.compile. On
# MoarVM, HLL::Backend.start pushes a frame list at the 'start'
# stage and the matching pop runs at the 'mast' stage in
# QASTCompilerMAST.to_mast. When a stage before 'mast' throws,
# HLL::Compiler.compile runs the compile_cleanup hook on the
# MoarVM backend before rethrowing, so the dangling frame entry
# from the failed EVAL does not corrupt subsequent compiles in
# the same outer compile.
our @subs;
BEGIN {
    @subs.push: EVAL('sub { 1 }');
    {
        EVAL 'sub bad {{{';
        CATCH { default { } }
    }
    @subs.push: EVAL('sub { 2 }');
    @subs.push: EVAL('sub { 3 }');
}
