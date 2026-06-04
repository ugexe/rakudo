use Test;

plan 3;

# `cmp` on two Maps/Hashes must be content-stable. The `Iterable cmp
# Iterable` multi added in `ee30c34ff` for Seq comparison caught Map as
# well (since Map does Iterable), comparing via raw iterator order which
# is not deterministic. Narrowing that multi to Seq-involving cases lets
# Map cmp Map fall back to `(\a, \b)` -> `Stringy cmp Stringy`. Map.Str
# sorts its entries before joining, so the comparison is content-stable.

my $h1 = {:path(['a']), :value('alpha')};
my $h2 = {:path(['b']), :value('bravo')};
my $h3 = {:path(['c']), :value('charlie')};

is ($h1 cmp $h2), Less, 'multi-key Map cmp by content is Less';
is ($h2 cmp $h1), More, 'multi-key Map cmp by content is More';

is-deeply
    ($h3, $h1, $h2).sort.map(*.<path>[0]).list,
    ('a', 'b', 'c').list,
    'sort of multi-key Maps orders them by content';

# vim: expandtab shiftwidth=4
