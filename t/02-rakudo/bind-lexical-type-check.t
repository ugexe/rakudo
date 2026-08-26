use nqp;
use Test;

plan 12;

# Binding to an already declared lexical must assert the source against
# the variable's bind constraint, the same check the declaration
# initializer performs.

{
    my Int $b;
    throws-like { $b := "x" }, X::TypeCheck::Binding,
      'binding a Str to a typed Int scalar throws';
    $b := 5;
    is $b, 5, 'binding an Int to a typed Int scalar works';
}

{
    my Int @a;
    throws-like { @a := [1, 2] }, X::TypeCheck::Binding,
      'binding an untyped Array to a typed array throws';
    my Int @b = 1, 2;
    @a := @b;
    is-deeply @a, @b, 'binding a matching typed array works';
}

{
    my Str %h;
    throws-like { %h := {a => 1} }, X::TypeCheck::Binding,
      'binding an untyped Hash to a typed hash throws';
    my Str %m = a => "x";
    %h := %m;
    is-deeply %h, %m, 'binding a matching typed hash works';
}

{
    subset Even of Int where * %% 2;
    my Even $x;
    throws-like { $x := 3 }, X::TypeCheck::Binding,
      'binding a value that fails a subset constraint throws';
    $x := 4;
    is $x, 4, 'binding a value that passes a subset constraint works';
}

{
    sub f() { state Int $x; $x := "s" }
    throws-like { f }, X::TypeCheck::Binding,
      'binding a Str to a typed state scalar throws';
}

{
    my $u;
    $u := "x";
    is $u, "x", 'binding a Str to an untyped scalar works';
}

my $rakuast := nqp::gethllsym('Raku', 'COMPILER-FRONTEND') eq 'rakuast';

{
    my $r = try EVAL q«role R1[::T] { method m { my T $x; $x := 42; $x } }; R1[Int].new.m»;
    todo 'the legacy frontend asserts against the uninstantiated generic' unless $rakuast;
    is $r, 42, 'binding to a generic-typed lexical inside a role body accepts a valid value';
}

{
    my $r = try EVAL q«my Int &f; &f := sub (--> Int) { 1 }; f()»;
    todo 'the legacy frontend rejects rebinding a & variable' unless $rakuast;
    is $r, 1, 'binding a matching sub to a typed & variable works';
}
