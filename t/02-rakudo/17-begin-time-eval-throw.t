use lib <t/packages/02-rakudo/lib>;
use Test;

use EvalThrowThenGood;
is ([+] @subs.map({ $_() })), 6,
    'a caught parse failure in BEGIN does not corrupt later EVALs in the same precomp';

done-testing;

# vim: expandtab shiftwidth=4
