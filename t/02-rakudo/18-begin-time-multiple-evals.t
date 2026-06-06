use lib <t/packages/02-rakudo/lib>;
use Test;

use MultipleBeginEvals;
is ([+] @subs.map({ $_() })), 15,
    'precompiling a module whose BEGIN runs multiple string EVALs works';

done-testing;

# vim: expandtab shiftwidth=4
