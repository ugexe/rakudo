use lib <t/packages/Test-Helpers>;
use Test;
use Test::Helpers;
use MONKEY-SEE-NO-EVAL;

plan 110;

# A block declares its topic itself, so a `my $_` in the body gives the
# block a container of its own under that name, as a `my` in an inner
# block would, and the argument the block was called with is left as it was.
is EVAL(q|my $c = { my $_ = 7; $_ }; $c(42)|), 7,
    'an initializer on a `my $_` in a block stores into a container of its own';

is-deeply EVAL(q|my $c = { my $_; $_ }; $c(42)|), Any,
    'a `my $_` in a block without an initializer reads its default rather than the argument';

is EVAL(q|$_ = 1; my $c = { my $_ = 2 }; $c(); $_|), 1,
    'an initializer on a `my $_` in a block leaves the outer topic alone';

is EVAL(q|$_ = 1; { my $_ = 2 }; $_|), 1,
    'an initializer on a `my $_` in a bare block leaves the outer topic alone';

is EVAL(q|$_ = 1; my class C { my $_ = 5 }; $_|), 1,
    'an initializer on a `my $_` in a class body leaves the outer topic alone';

is EVAL(q|$_ = 1; my @seen; { @seen.push($_); my $_ = 2; @seen.push($_) }; @seen.push($_); @seen.join(",")|), '1,2,1',
    'the topic read above a `my $_` in a block is still the outer topic';

is EVAL(q|my @seen; for 1,2 { my $_ = 9; @seen.push($_) }; @seen.join(",")|), '9,9',
    'an initializer on a `my $_` in a for body stores into a container of its own';

is EVAL(q|my @seen; for 1,2 { my $arg = $_; my $_ = 9; @seen.push("$arg:$_") }; @seen.join(",")|), '1:9,2:9',
    'the topic read above a `my $_` in a for body is still the argument';

is EVAL(q|$_ = 1; my @seen; for 1 { FIRST { my $_ = 3 }; @seen.push($_) }; @seen.push($_); @seen.join(",")|), '1,1',
    'an initializer on a `my $_` in a FIRST block leaves the loop topic and the outer topic alone';

is EVAL(q|my @seen; for 1,2 { FIRST my $_ = 4; @seen.push($_) }; @seen.join(",")|), '4,2',
    'a `my $_` declared by a FIRST statement is stored into on the first iteration, and the loop binds the topic again after it';

is EVAL(q|$_ = 1; my @seen; { ENTER my $_ = 4; @seen.push($_) }; @seen.push($_); @seen.join(",")|), '4,1',
    'a `my $_` declared by an ENTER statement is a container of the block, filled at entry';

is EVAL(q|$_ = 1; EVAL q[FIRST my $_ = 4]; $_|), 1,
    'a `my $_` declared by a FIRST statement in an EVAL leaves the topic of the caller alone';

is EVAL(q|$_ = 1; EVAL q[FIRST my $_ = 4; $_]|), 4,
    'a `my $_` declared by a FIRST statement in an EVAL is a container of the EVAL';

is EVAL(q|$_ = 1; my $seen; EVAL q[FIRST $seen = $_]; $seen|), 1,
    'a FIRST statement in an EVAL reads the topic of the caller';

is EVAL(q|my @seen; for 1,2 { my Int $_ = 9; @seen.push($_) }; @seen.join(",")|), '9,9',
    'a typed `my $_` in a for body stores into a container of its own';

throws-like { EVAL q|for 1 { my Int $_ = "x" }| }, X::TypeCheck::Assignment,
    'a typed `my $_` in a for body checks the type of what is assigned';

is EVAL(q|({ my $_ where * > 3 = 5; $_ })(1)|), 5,
    'a constrained `my $_` in a block stores into a container of its own';

throws-like { EVAL q|({ my $_ where * > 3 = 1 })(9)| }, X::TypeCheck::Assignment,
    'a constrained `my $_` in a block checks what is assigned against the constraint';

is EVAL(q|$_ = 1; { my $_ is default(42); $_ = Nil; $_ }|), 42,
    'a `my $_` in a block keeps the default its trait gives it';

is EVAL(q|my @c; for 1,2 { my $_ = 5; @c.push({ $_++ }) }; @c>>.(); @c>>.().join(",")|), '6,6',
    'a closure over a `my $_` in a for body keeps the container of its own iteration';

is EVAL(q|$_ = 1; sub f { my $_; 1 }; f(); $_|), 1,
    'a `my $_` in a sub that reads nothing by that name leaves the outer topic alone';

is EVAL(q|"a" ~~ /a/; sub f { my $/; 1 }; f(); ~$/|), 'a',
    'a `my $/` in a sub that reads nothing by that name leaves the outer match variable alone';

is EVAL(q|$_ = 1; EVAL q[my $_]; $_|), 1,
    'a `my $_` in an EVAL that reads nothing by that name leaves the topic of the caller alone';

is EVAL(q|$_ = 1; EVAL q[my $_ = 4]; $_|), 1,
    'an initializer on a `my $_` in an EVAL leaves the topic of the caller alone';

# A declaration that asks for nothing of its own gets a container shaped
# as a routine shapes the lexical.
is EVAL(q|sub g { CALLER::<$/> }; sub f { my $/; "abc" ~~ /b/; ~g() }; f()|), 'b',
    'a `my $/` in a sub is dynamic as the match variable is';

is EVAL(q|sub f { my $/; $/.raku }; f()|), 'Nil',
    'a `my $/` in a sub defaults to Nil as the match variable does';

is EVAL(q|sub f { my $!; $!.raku }; f()|), 'Nil',
    'a `my $!` in a sub defaults to Nil as the error variable does';

is EVAL(q|use v6.c; sub g { CALLER::<$_> }; sub f { my $_ = 3; g() }; f()|), 3,
    'a `my $_` in a sub is dynamic under 6.c as the topic is there';

throws-like { EVAL q|sub g { CALLER::<$_> }; sub f { my $_ = 3; g() }; f()| }, X::Caller::NotDynamic,
    'a `my $_` in a sub is not dynamic under 6.d as the topic is not there';

is-deeply EVAL(q|(CORE::<$/>.VAR.dynamic, CORE::<$!>.VAR.dynamic)|), (True, True),
    'the match and error variables of the setting stay dynamic';

# A routine declares its topic, match and error variables as a block
# declares its topic, so a `my` of their names is a container of its own
# there too.
is EVAL(q|$_ = 1; sub f { my $_ = 3; $_ }; f() ~ $_|), '31',
    'a `my $_` in a sub is a container of its own';

is EVAL(q|sub f { my $r := $_; my $_ = 3; $r.raku }; f()|), 'Any',
    'a `my $_` in a sub leaves the topic the sub declared as it was';

is EVAL(q|"abc" ~~ /b/; sub f { my $/ = 3; $/ }; f() ~ $/|), '3b',
    'a `my $/` in a sub is a container of its own';

is EVAL(q|try die "x"; sub f { my $! = 3; $! }; f() ~ $!.message|), '3x',
    'a `my $!` in a sub is a container of its own';

is EVAL(q|$_ = 1; my class C { method m { my $_ = 4; $_ } }; C.m ~ $_|), '41',
    'a `my $_` in a method is a container of its own';

is EVAL(q|multi m(Int) { my $_ = 3; $_ }; m(1)|), 3,
    'a `my $_` in a multi candidate is a container of its own';

is EVAL(q|sub f { my $_; $_++; $_ }; f(); f()|), 1,
    'a `my $_` in a sub is a fresh container on each call';

is EVAL(q|{ my $_ = "abc"; .uc }|), 'ABC',
    'a method call on the topic after a `my $_` reads the new container';

# The initializer runs before the name comes to mean the new container.
is EVAL(q|$_ = "a"; { my $_ = .uc; $_ }|), 'A',
    'an initializer on a `my $_` in a block still reads the topic the block was given';

is EVAL(q|sub f { "abc" ~~ /(b)/; my $/ = $0.Str; $/ }; f()|), 'b',
    'an initializer on a `my $/` in a sub still reads the match the sub holds';

# A statement modifier runs the declaration under a thunk or a topic of
# its own, and the name declared is still the scope's.
is EVAL(q|my $_ = 5 given 3; $_|), 5,
    'a `my $_` under a given modifier is a container of the declaring scope';

is EVAL(q|sub f { my $_ = .Str for 7; $_ }; f()|), '7',
    'a `my $_` under a for modifier is initialized from the topic of each iteration';

is EVAL(q|sub f { my $_ = 5 with 3; $_ }; f()|), 5,
    'a `my $_` under a with modifier is a container of the declaring scope';

is EVAL(q|my $_ = 5 without Nil; $_|), 5,
    'a `my $_` under a without modifier is a container of the declaring scope';

is EVAL(q|my $_ = .uc given "a"; $_|), 'A',
    'an initializer on a `my $_` under a given modifier reads the topic given';

# A construct that sets the topic for part of a statement evaluates that
# part before it sets the topic aside, so a declaration in it is what
# gets put back.
is EVAL(q|sub f { $_ = 1; (my $_ = "abc") ~~ s/b/X/; $_ }; f()|), 'aXc',
    'a `my $_` on the left of a smartmatch with a substitution keeps its container';

is EVAL(q|sub f { $_ = 1; (my $_ = "abc") ~~ /b/; $_ }; f()|), 'abc',
    'a `my $_` on the left of a smartmatch with a regex keeps its container';

is EVAL(q|sub f { $_ = 1; my $s; $s = .Str given my $_ = 5; "$s $_" }; f()|), '5 5',
    'a `my $_` as the source of a given modifier is the topic of the statement and stays after it';

# A topic declaration anywhere in the statement, not only as its whole
# expression, reaches the declaring scope from under any modifier.
is EVAL(q|sub f { $_ = 1; (my $_ = 5) given 3; $_ }; f()|), 5,
    'a `my $_` in parentheses under a given modifier is a container of the declaring scope';

is EVAL(q|sub f { $_ = 1; (my $_ = 5) for 3; $_ }; f()|), 5,
    'a `my $_` in parentheses under a for modifier is a container of the declaring scope';

is EVAL(q|sub f { my @a; @a.push(my $_ = 5) for 1,2; "@a[] $_" }; f()|), '5 5 5',
    'a `my $_` as an argument under a for modifier stores into the declaring scope on each iteration';

is EVAL(q|sub f { $_ = 1; my $x = (my $_ = 5) given 3; "$x $_" }; f()|), '5 5',
    'a `my $_` in an initializer under a given modifier is a container of the declaring scope';

is EVAL(q|(my $_ = 5, my $y = 7) given 3; "$_ $y"|), '5 7',
    'a `my $_` in a list under a given modifier is a container of the declaring scope';

is EVAL(q|sub f { $_ = 1; (my $_ = 5 given 7) for 3,4; $_ }; f()|), 5,
    'a `my $_` under a given modifier nested under a for modifier is a container of the declaring scope';

is EVAL(q|sub f { $_ = 1; (my $_ = 5 for 1,2) given 3; $_ }; f()|), 5,
    'a `my $_` under a for modifier nested under a given modifier is a container of the declaring scope';

is EVAL(q|sub f { $_ = 1; my $x; ($x = 1) if (my $_ = 5) for 1,2; $_ }; f()|), 5,
    'a `my $_` in the condition of a statement under a for modifier is a container of the declaring scope';

is EVAL(q|sub f { my @a; (@a.push($_); my $_ = 5) for 1,2; "@a[] $_" }; f()|), '1 2 5',
    'the topic read above a `my $_` in a statement under a for modifier is the loop value';

is EVAL(q|sub f { my @a; (my $_ = 5; @a.push($_)) for 1,2; "@a[] $_" }; f()|), '5 5 5',
    'the topic read below a `my $_` in a statement under a for modifier is the container it declared';

is EVAL(q|sub f { $_ = 1; (my $_ = 5) andthen $_ + 1 }; f()|), 6,
    'a `my $_` on the left of andthen is the topic of the right side';

is EVAL(q|$_ = 0; -> { my $_ = 5 for 1,2; $_ }()|), 5,
    'a `my $_` under a for modifier in a pointy block, which declares no topic of its own, is a container of the block';

# A binding declaration binds the slot of the declaring scope the same way.
is EVAL(q|sub f { my $_ := 5 given 3; $_ }; f()|), 5,
    'a binding `my $_ :=` under a given modifier binds the name for the declaring scope';

is EVAL(q|sub f { my $_ := 5 for 1; $_ }; f()|), 5,
    'a binding `my $_ :=` under a for modifier binds the name for the declaring scope';

is EVAL(q|sub f { my $_ := 5 with 3; $_ }; f()|), 5,
    'a binding `my $_ :=` under a with modifier binds the name for the declaring scope';

is EVAL(q|sub f { my $x = 3; my $_ := $x given $x; $_ }; f()|), 3,
    'a binding `my $_ :=` to the very topic a given modifier sets binds the name for the declaring scope';

throws-like { EVAL q|{ my Int $_ := "x" }| }, X::TypeCheck::Binding,
    'a typed binding `my $_ :=` in a block checks the type of what is bound';

is EVAL(q|({ my Int $_ := 4; $_ })(1)|), 4,
    'a typed binding `my $_ :=` in a block binds the name to the value';

is EVAL(q|sub f($x = (my $_ = 5)) { "$x $_" }; f()|), '5 5',
    'a `my $_` in a parameter default is a container of the routine';

lives-ok { EVAL q|sub f { my $_ = 5; MY::.gist }; f()| },
    'the pseudo package of a scope with a `my $_` can be listed';

# A modifier that never runs the statement leaves the slot as it was.
is EVAL(q|sub f { $_ = 1; my $_ = 5 with Nil; $_ }; f()|), 1,
    'a `my $_` under a with modifier that does not run leaves the topic as it was';

is EVAL(q|sub f { $_ = 1; my $_ = 5 for (); $_ }; f()|), 1,
    'a `my $_` under a for modifier over nothing leaves the topic as it was';

# A for modifier over a regex sets the topic aside for the loop.
is EVAL(q|sub f { $_ = "x"; my $_ = 5 for /x/; $_ }; f()|), 5,
    'a `my $_` under a for modifier over a regex is a container of the declaring scope';

# A phaser run before any frame of the scope exists runs a declaration as
# an assignment through the name, as any assignment run then is.
is EVAL(q|sub h { INIT my $_ = 9; $_ }; h() ~ h()|), '99',
    'a `my $_` declared by an INIT statement in a sub is read by every call';

is EVAL(q|sub h { INIT my $/ = 9; $/ }; h()|), 9,
    'a `my $/` declared by an INIT statement in a sub is read by a call';

is EVAL(q|my class C { method m { INIT my $_ = 6; $_ } }; C.m ~ C.m|), '66',
    'a `my $_` declared by an INIT statement in a method is read by every call';

is-run 'sub f { BEGIN my $_ = 9; CHECK my $/ = 8; INIT my $! = 7; 1 }; print f()',
    :out('1'),
    :err(''),
    'topic, match and error declarations run by BEGIN, CHECK and INIT compile and warn nothing';

is EVAL(q|$_ = 1; EVAL q[INIT { my $_ = 7 }]; $_|), 1,
    'a `my $_` in an INIT block is a container of the block';

is EVAL(q|$_ = 1; EVAL q[BEGIN { my $_ = 7 }; INIT { my $_ = 8 }]; $_|), 1,
    'a `my $_` in a BEGIN or INIT block leaves the topic of the caller alone';

is EVAL(q|sub f { BEGIN my $_ = 9; $_.raku }; f()|), 'Any',
    'a `my $_` declared by a BEGIN statement in a sub assigns at compile time, and a call reads the topic the sub declares';

# The topic above a `my $_` in an EVAL is still the topic of the caller.
is EVAL(q|$_ = 1; EVAL(q[$_ = 2; my $_ = 7; $_]) ~ $_|), '72',
    'a write to the topic above a `my $_` in an EVAL reaches the caller, and the declaration is a container of the EVAL';

# Code compiled ahead of the unit, when a role is composed or a BEGIN runs,
# gets the same treatment.
is EVAL(q|my role R { method m { my $_ = 5 for 1,2; $_ } }; my class C does R {}; C.m|), 5,
    'a `my $_` under a for modifier in a role method is a container of the method';

is EVAL(q|my role R { method m { my @s; for 1,2 { my $_ = 9; @s.push($_) }; @s.join(",") } }; my class C does R {}; C.m|), '9,9',
    'a `my $_` in a for body in a role method is a container of its own';

is EVAL(q|BEGIN ({ my $_ = 7; $_ })(42)|), 7,
    'a `my $_` in a block called at BEGIN time is a container of its own';

is EVAL(q|constant X = sub { my $_ = 5 for 1,2; $_ }(); X|), 5,
    'a `my $_` under a for modifier in a sub called at BEGIN time is a container of the sub';

# A native scalar takes the slot over rather than filling it.
is-run 'sub f { my int $_ = 5; $_ }; print f()',
    :out('5'),
    :err{.contains: q{Redeclaration of symbol '$_'}},
    'a native `my int $_` in a sub takes the slot and warns';

is-run '{ my int $_ = 5 }; print "ok"',
    :out(''),
    :err{.contains: q{Redeclaration of symbol '$_'}},
    :exitcode(1),
    'a native `my int $_` in a block is a compile error';

is-run 'sub f { state $_ = 5; $_ }; print f()',
    :out('5'),
    :err{.contains: q{Redeclaration of symbol '$_'}},
    'a `state $_` in a sub takes the slot and warns';

# A declaration of a name the scope already declared explicitly, as a
# parameter or an earlier `my`, is a redeclaration of that one.
is-run '-> $_ { my $_ = 5 }(1); print "ok"',
    :out(''),
    :err{.contains(q{Redeclaration of symbol '$_'}) && .contains('readonly')},
    :exitcode(1),
    'a `my $_` below an explicit topic parameter assigns into that parameter';

is-run '{ my $_; my $y := $_; my $_ = 5; print $y }',
    :out('5'),
    :err{.contains: q{Redeclaration of symbol '$_'}},
    'a second `my $_` in a block assigns into the container of the first';

is-run 'my $_ = "x"; print $_',
    :compiler-args['-n'],
    :in("a\n"),
    :out('x'),
    :err(''),
    'a `my $_` in a -n program is a container of the line loop body and warns nothing';

is EVAL(q|"abc" ~~ /b/; sub f { my $/ = 5 if True for 1,2; $/ }; f() ~ $/|), '5b',
    'a `my $/` under a condition and a for modifier stores into the sub, not the caller';

is EVAL(q|$_ = 1; sub f { my $_ = 5 with 3 for 1,2; $_ }; f() ~ $_|), '51',
    'a `my $_` under a with and a for modifier stores into the sub, not the caller';

is EVAL(q|sub f { my @r = (my $_ = .Str for 1,2); "@r[] $_" }; f()|), '1 2 2',
    'a `my $_` under a for modifier in value context yields each value and leaves the last in the sub';

is-run 'use v6.e.PREVIEW; sub f { FIRST my $/ = 4; $/ }; print f()',
    :out('4'),
    'a `my $/` declared by a FIRST statement in a 6.e sub fills the slot of the sub';

is-run 'use v6.e.PREVIEW; sub f { FIRST "abc" ~~ /b/; ~$/ }; print f()',
    :out('b'),
    'a regex in a FIRST statement in a 6.e sub writes the match variable of the sub';

is-run 'use v6.e.PREVIEW; "abc" ~~ /b/; { my $/ = 5 for 1; print $/ }; print $/',
    :out('5b'),
    'a `my $/` under a for modifier in a 6.e block is a container of the block';

is-run 'use v6.e.PREVIEW; for 1,2 { FIRST "abc" ~~ /b/; print $/.defined ?? ~$/ !! "-" }',
    :out('b-'),
    'a regex in a FIRST statement in a 6.e loop body writes the match variable of the first iteration';

is EVAL(q|$_ = "outer"; -> { POST my $_ = 5; $_ = 1 }(); $_|), 'outer',
    'a `my $_` declared by a POST statement in a pointy block is a container of the block';

is-run '$_ = 1; my $_ = 7; print $_',
    :out('7'),
    'a `my $_` in the mainline is a container of its own';

# An `our $_` binds the block's topic to the package symbol it installs.
is EVAL(q|my $c = { our $_ = 9; "$_/$GLOBAL::_" }; $c(3)|), '9/9',
    'an `our $_` in a block names the package symbol it installs';

is EVAL(q|my class C { method m { our $_ = 9; "$_/$C::_" } }; C.m|), '9/9',
    'an `our $_` in a method names the package symbol it installs';

is EVAL(q|my $c = { my $_ := 4; $_ }; $c(1)|), 4,
    'a binding `my $_ :=` in a block binds the name to the value';

is EVAL(q|$_ = 1; given 2 { my $_ = 5 }; $_|), 1,
    'an initializer on a `my $_` in a given body leaves the outer topic alone';

is EVAL(q|my $m; { CATCH { default { my $_ = 5; $m = $_ } }; die "boom" }; $m|), 5,
    'a `my $_` in an exception handler is a container of its own';

is EVAL(q|my $m; { { CATCH { my $_ = 5; $m = $_ }; die "boom" }; CATCH { default { } } }; $m|), 5,
    'a `my $_` in a CATCH block is a container of its own';

# The lexical a scope declares for itself is not one the user wrote, so a
# declaration of its name is a shadowing rather than a redeclaration.
is-run 'my $c = { my $_ }; for 1 { my $_ }; class C { my $_ }; class D { method m { my $_ } }; sub f { my $_ }; my $d = { our $_ }; my $_; print "ok"',
    :out('ok'),
    :err(''),
    'a `my $_` warns nothing wherever a scope declares the topic itself';

is-run 'use fatal; { my $_ }; print "ok"',
    :out('ok'),
    :err(''),
    'a `my $_` is no error under `use fatal` either';

# The parser has the first declaration in scope by the time it reads the
# second, so that one is a redeclaration.
is-run '{ my $_; my $_ }; print "ok"',
    :out('ok'),
    :err{ 1 == .comb(q{Redeclaration of symbol '$_'}).elems },
    'a second `my $_` in a block is reported once';

# A parameter list declares the lexicals of a signature it binds, which
# cannot be ones the block already has.
is-run 'my $c = { my ($_, $x) = 1,2 }; print "ok"',
    :out(''),
    :err{.contains: q{Redeclaration of symbol '$_'}},
    :exitcode(1),
    'a `my ($_, ...)` in a block is a compile error';

# Only a variable declaration can name the topic's slot, so a constant of
# its name is a redeclaration.
is-run 'my $c = { constant $_ = 3; $_ }; print $c(1)',
    :out(''),
    :err{.contains: q{Redeclaration of symbol '$_'}},
    :exitcode(1),
    'a `constant $_` in a block is a compile error';

# A placeholder asks for a parameter of a name the declaration has taken.
is-run 'my $c = { my $_; $^_ }; print "ok"',
    :out(''),
    :err{.contains: q{Redeclaration of symbol '$^_' as a placeholder parameter}},
    :exitcode(1),
    'a `$^_` after a `my $_` in a block is a compile error';

# vim: expandtab shiftwidth=4
