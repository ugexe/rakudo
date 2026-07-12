use nqp;
use Test;
use MONKEY-SEE-NO-EVAL;

plan 8;

# The whatever-feed: `==> *` replaces the store's contents, `==>> *`
# appends to them, and $(*), @(*) and %(*) read them back. A feed stage
# mentioning a reader receives the values fed to it through the reader
# instead of as a trailing argument. Only the RakuAST grammar compiles
# these; the snippets are EVALed so the file still parses under the
# legacy frontend.
if nqp::gethllsym('Raku', 'COMPILER-FRONTEND') eq 'rakuast' {
    is-deeply EVAL(Q|my @d = "a".."e"; @d ==> *; @(*)|),
        ["a".."e"],
        'feeding to * stores the values for @(*)';

    is-deeply EVAL(Q|<a b c d> ==> *; 0..3 ==>> *; @(*)|),
        ["a", "b", "c", "d", 0, 1, 2, 3],
        '==> * replaces the store and ==>> * appends to it';

    is-deeply EVAL(Q|1..4 ==> *; $(*)|),
        $[1, 2, 3, 4],
        '$(*) reads the store as an item';

    is-deeply EVAL(Q|1..4 ==> *; %(*)|),
        {"1" => 2, "3" => 4},
        '%(*) reads the store as a hash';

    is EVAL(Q{(1..5) ==> grep(* %% 2) ==> join("|", @(*))}),
        "2|4",
        'a stage mentioning @(*) receives its values through the reader';

    is-deeply EVAL(Q{<x y> ==> *; (1..5) ==> grep(* %% 2) ==> join("|", @(*)); @(*)}),
        ["x", "y"],
        'a stage reader does not disturb the store';

    is-deeply EVAL(Q|* <== <p q>; @(*)|),
        ["p", "q"],
        'the leftward feed can also target *';

    is-deeply EVAL(Q|* <== <p q>; * <<== <r s>; @(*)|),
        ["p", "q", "r", "s"],
        'the leftward appending feed appends to the store';
}
else {
    skip 'the whatever-feed requires the RakuAST frontend', 8;
}

# vim: expandtab shiftwidth=4
