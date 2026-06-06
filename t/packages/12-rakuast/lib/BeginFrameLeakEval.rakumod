use MONKEY-SEE-NO-EVAL;
# Precompiling this module used to fail under RAKUDO_RAKUAST=1 with
# `Missing serialize REPR function for REPR ConditionVariable`. The EVAL'd
# Sub's outer-frame chain walked from the Sub through the EVAL mainline
# to the BEGIN block frame, whose lexpad held the Proc::Async tap closure
# (and via that, a Lock and its ConditionVariable). The wrapper interposed
# in IMPL-TO-QAST-COMP-UNIT for nested EVAL terminates that walk at a
# QAST::Block with no SC-resident static_code, matching what legacy
# compile_in_context does.
our &x;
BEGIN {
    my $p = Proc::Async.new($*EXECUTABLE, :w);
    $p.stderr.tap: {;};
    my $start-promise = $p.start;
    await $p.print: 'my $sub = sub () { 42 }';
    $p.close-stdin;
    await $start-promise;
    &x = EVAL 'sub () { 42 }';
}
