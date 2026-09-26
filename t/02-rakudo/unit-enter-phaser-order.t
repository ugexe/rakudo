use lib <t/packages/Test-Helpers>;
use Test;
use Test::Helpers;

plan 2;

# An ENTER at the unit level runs ahead of the unit's statements, before
# the END phasers of the unit are registered.
is-run 'ENTER print "enter"; print "body"',
    :out('enterbody'),
    'a unit-level ENTER runs before the unit body';

is-run 'ENTER die "x"; END print "end"',
    :out(''),
    :err{.contains('x')},
    :exitcode(1),
    'an END phaser is not run when a unit-level ENTER dies';

# vim: expandtab shiftwidth=4
