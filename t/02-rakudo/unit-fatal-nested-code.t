use Test;

plan 3;

# A `use fatal` at the unit level applies to the code the unit declares, not
# only to the statements of the unit itself.
use fatal;

sub f { my $x = "abc".Int; "survived" }
my $b = { my $x = "abc".Int; "survived" };
my $c = -> { my $x = "abc".Int; "survived" };

throws-like { f() }, X::Str::Numeric,
    'a unit-level `use fatal` throws a Failure inside a sub the unit declares';

throws-like { $b() }, X::Str::Numeric,
    'a unit-level `use fatal` throws a Failure inside a block the unit declares';

throws-like { $c() }, X::Str::Numeric,
    'a unit-level `use fatal` throws a Failure inside a pointy block the unit declares';

# vim: expandtab shiftwidth=4
