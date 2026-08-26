use nqp;
use Test;

plan 32;

# The unicode fat arrow is an infix alias for the Pair constructor and
# does not participate in identifier autoquoting, so its left side is
# evaluated and a user declared infix:<⇒> shadows it like any other
# lexical operator. The unicode bind spelling means binding only while
# no infix:<≔> is declared, so a user declared infix:<≔> dispatches as
# an ordinary operator.

{
    my \k = "x";
    my $pair = (k ⇒ 2);
    isa-ok $pair, Pair, 'the unicode fat arrow constructs a Pair';
    is $pair.key, "x", 'the unicode fat arrow evaluates an identifier on its left rather than autoquoting it';
}

{
    is (foo => 1).key, "foo", 'the ascii fat arrow autoquotes an identifier on its left';
}

{
    sub infix:<⇒>(\a, \b) { "user" }
    my \k = True;
    is (k ⇒ False), "user", 'a user declared infix:<⇒> is dispatched after an identifier term';
}

{
    sub infix:<≔>(\a, \b) { "user" }
    is (1 ≔ 2), "user", 'a user declared infix:<≔> is dispatched rather than treated as a bind operator';
}

{
    my module Ops {
        sub infix:<≔>(\a, \b) is export { "imported" }
        sub infix:<⇒>(\a, \b) is export { "imported" }
    }
    import Ops;
    is (1 ≔ 2), "imported", 'an imported infix:<≔> is dispatched rather than treated as a bind operator';
    my \k = 1;
    is (k ⇒ 2), "imported", 'an imported infix:<⇒> is dispatched after an identifier term';
    is (my $y ≔ 6), "imported", 'a declaration followed by the unicode bind spelling dispatches to an imported infix:<≔>';
}

{
    my $seen;
    sub infix:<≔>(\a, \b) { $seen = b; "user" }
    my $x ≔ 5;
    is $seen, 5, 'a declaration followed by the unicode bind spelling dispatches to a declared infix:<≔>';
    ok $x === Any, 'the declined initializer leaves the declared variable unbound';
}

{
    my $seen;
    sub infix:<≔>(\a, \b) { $seen = b }
    my class C { has $.x ≔ 1 }
    is $seen, 1, 'an attribute declaration followed by the unicode bind spelling dispatches to a declared infix:<≔> rather than panicking';
}

{
    is (4 ⇒ 2 + 3).value, 5, 'the unicode fat arrow binds looser than additive operators';
    is (1, 2 ⇒ 3)[1].key, 2, 'the unicode fat arrow binds tighter than the comma';
}

{
    isa-ok (∅ ⇒ 1).key, Set, 'the unicode fat arrow after the empty set term takes the Set as its key';
}

{
    throws-like q[${a ⇒ 1}], X::Obsolete, 'the unicode fat arrow inside ${ } is reported as obsolete syntax';
    is EVAL(q[${a => 1}])<a>, 1, 'the ascii fat arrow inside ${ } composes a Hash';
}

# The unicode bind spelling only exists in the RakuAST grammar.
{
    my $rakuast := nqp::gethllsym('Raku', 'COMPILER-FRONTEND') eq 'rakuast';

    my $bound = try EVAL 'my $a = 1; my $b; $b ≔ $a; $b++; $a';
    todo 'the legacy grammar has no unicode bind spelling' unless $rakuast;
    is $bound, 2, 'the unicode bind spelling binds when no infix:<≔> is declared';

    my $resumed = try EVAL 'my $inner = do { sub infix:<≔>(\a, \b) { "user" }; 1 ≔ 2 }; my $a = 1; my $b; $b ≔ $a; $b++; ($inner, $a)';
    todo 'the legacy grammar has no unicode bind spelling' unless $rakuast;
    is-deeply $resumed, $("user", 2), 'the unicode bind spelling binds after a shadowing infix:<≔> goes out of scope';

    todo 'the legacy grammar has no unicode bind spelling' unless $rakuast;
    throws-like q«[≔] 1, 2», X::Syntax::CannotMeta, operator => '≔',
      'a reduce of the unicode bind spelling names the operator as typed';

    todo 'the legacy grammar has no unicode bind spelling' unless $rakuast;
    throws-like q«my ($a, $b); $a ≔= $b», X::Syntax::CannotMeta, meta => 'assign', operator => '≔',
      'an assignment metaop of the unicode bind spelling names the operator as typed';

    todo 'the legacy grammar has no unicode bind spelling' unless $rakuast;
    throws-like q«my ($a, $b); $a !≔ $b», X::Syntax::CannotMeta, meta => 'negate', operator => '≔',
      'a negation of the unicode bind spelling names the operator as typed';

    todo 'the legacy grammar has no unicode bind spelling' unless $rakuast;
    throws-like q«my ($a, $b); $a R≔ $b», X::Syntax::CannotMeta, meta => 'reverse the args of', operator => '≔',
      'a reversal of the unicode bind spelling names the operator as typed';

    todo 'the legacy grammar has no unicode bind spelling' unless $rakuast;
    throws-like q«my Int $b ≔ "x"», X::TypeCheck::Binding,
      'the unicode bind spelling in a declaration asserts the declared type';

    todo 'the legacy grammar has no unicode bind spelling' unless $rakuast;
    is (try EVAL q«my ($x, $y) ≔ (1, 2); "$x $y"»), "1 2",
      'the unicode bind spelling binds a signature declaration';

    todo 'the legacy grammar has no unicode bind spelling' unless $rakuast;
    is (try EVAL q«constant c ≔ 5; c»), 5,
      'the unicode bind spelling initializes a constant declaration';

    todo 'the legacy grammar has no unicode bind spelling' unless $rakuast;
    is (try EVAL q«my \k ≔ 5; k»), 5,
      'the unicode bind spelling initializes a term declaration';

    todo 'the legacy grammar has no unicode bind spelling' unless $rakuast;
    throws-like q«my class AttrBindUnicode { has $.x ≔ 1 }», Exception,
      message => /'Cannot use ≔ to initialize an attribute'/,
      'the unicode bind spelling is rejected as an attribute initializer naming the operator as typed';
}

{
    throws-like q«my class AttrBindAscii { has $.x := 1 }», Exception,
      message => /'Cannot use := to initialize an attribute'/,
      'the ascii bind spelling is rejected as an attribute initializer';
}

{
    throws-like q«[:=] 1, 2», X::Syntax::CannotMeta, operator => ':=',
      'a reduce of the ascii bind spelling names the operator as typed';
}

{
    use experimental :rakuast;
    is RakuAST::Infix.new(':=').spelling, ':=',
      'an infix node constructed without a spelling reports its operator as the spelling';
    is RakuAST::Infix.new(':=', :spelling('≔')).spelling, '≔',
      'an infix node constructed with a spelling reports that spelling';
    is RakuAST::Infix.new(':=', :spelling('≔')).raku,
      'RakuAST::Infix.new(":=", :spelling("≔"))',
      'an infix node with a spelling includes it in its .raku form';
}
