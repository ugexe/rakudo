use lib <t/packages/Test-Helpers>;
use Test;
use Test::Helpers;

plan 3;

# `Code.assuming` synthesises a RakuAST::Sub at runtime that wraps
# the original Code.  When the original Code's signature has
# parameters typed by names that live outside the setting scope (a
# user class, a class loaded via `use`, etc.) the synthesised AST
# previously failed to resolve those names because `.EVAL` ran in
# the setting scope rather than the caller's.  Reported via
# JSON::RPC::Client failing to install (its BUILD does
# `&transport.assuming(uri => $uri)` where transport has
# `URI :$uri`).

my $tmp = $*TMPDIR.add("rakuast-assuming-test-{$*PID}");
$tmp.add("MyMod").mkdir;
$tmp.add("MyMod/Thing.rakumod").spurt(q:to/MOD/);
    unit class MyMod::Thing;
    has Int $.value;
    method new(Int $value) { self.bless(:$value) }
    MOD
END { run(<rm -rf>, $tmp.Str) if $tmp.defined && $tmp.e }

sub run-with(Str $code, $desc, *%args) {
    is-run $code, $desc, :compiler-args[«-I "$tmp"»], |%args
}

# Bare reproducer: external type in the curried Code's signature.
run-with q:to/CODE/,
    use MyMod::Thing;
    sub transport(MyMod::Thing :$thing!, Str :$payload) {
        "thing.value=" ~ $thing.value ~ " payload=" ~ $payload
    }
    say &transport.assuming(thing => MyMod::Thing.new(42))(payload => "hi")
    CODE
    'assuming over a sub with an externally-defined typed parameter',
    :out("thing.value=42 payload=hi\n");

# JSON::RPC-style: assuming called inside a class's BUILD.
run-with q:to/CODE/,
    use MyMod::Thing;
    class C {
        has Code $!transport;
        submethod BUILD(MyMod::Thing :$thing!) {
            $!transport = &transport.assuming(thing => $thing);
        }
        sub transport(MyMod::Thing :$thing!, Str :$msg!) {
            "$thing.value()/$msg"
        }
        method call(Str $msg) { $!transport(:$msg) }
    }
    say C.new(thing => MyMod::Thing.new(99)).call("hello")
    CODE
    'assuming from a BUILD submethod (JSON::RPC::Client pattern)',
    :out("99/hello\n");

# Plain assuming still works (no external types).
run-with q:to/CODE/,
    sub f($x, $y, $z) { $x + $y + $z }
    say &f.assuming(1, 2)(10)
    CODE
    'plain positional assuming still works',
    :out("13\n");

# vim: expandtab shiftwidth=4
