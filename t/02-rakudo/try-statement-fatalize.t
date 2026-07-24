use Test;

plan 10;

# `try EXPR` fatalizes the calls inside EXPR the way `try { EXPR }` does,
# so a Failure produced mid-expression throws and is caught by the try
# rather than flowing into the rest of the expression as a value.

is-deeply (try ::('NoSuchSymbolForTryTest').^name), Nil,
    'a Failure from an indirect lookup inside a larger expression throws inside the try';
isa-ok $!, X::NoSuchSymbol,
    'the exception the try caught into $! is the lookup failure';
is-deeply (try (sub { ::('NoSuchSymbolForTryTest').^name })()), Nil,
    'a Failure produced inside a nested block of the expression also throws inside the try';
is-deeply (try ::('NoSuchSymbolForTryTest')), Nil,
    'a Failure that is the whole expression result still gives Nil';
is (try 'abc'.uc), 'ABC',
    'a successful method call evaluates to its value';
is (try 42), 42,
    'an expression with no calls at all evaluates to its value';
is-deeply (try (sub { fail 'armed' })()), Nil,
    'a Failure returned by a call in the expression throws inside the try';
is-deeply (try { ::('NoSuchSymbolForTryTest').^name }), Nil,
    'the block form catches the same mid-expression Failure';
is (try do { no fatal; my $r = (sub { fail 'soft' })(); $r.^name }), 'Failure',
    'an explicit no fatal block inside the try keeps its soft Failure as a value';
is EVAL(q[sub gimme { no fatal; my $f = (sub { fail 'z' })(); $f.so; $f }; use fatal; gimme().^name]), 'Failure',
    'a handled Failure passes through a use fatal call boundary as a value';
