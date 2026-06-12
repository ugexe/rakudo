use Test;

plan 2;

# A `my %`/`my @`/`my $` declaration must produce a fresh container on
# every invocation, including when the declaring frame is spesh-inlined
# into a caller that invokes it several times per frame entry. Relying
# on lazy static-lexpad vivification broke this: the inliner merges an
# inlinee's lexicals into the inliner's environment, so the container
# vivified for the first logical call was shared by the rest. Any.hash
# is `my % = self`, making `@pairs.map(*.Hash)` return the same Hash
# object for every element once the chain got hot.
#
# The loops below need enough iterations for spesh to specialize and
# inline the call chain; the corruption historically appeared within
# the first few hundred.

{
    my $bad = -1;
    for ^10_000 -> $i {
        my @t = (ident => "lang"), (op => "="), (ident => "fr");
        my @h = @t.map: *.Hash;
        my $got = @h.map({ .keys.sort.join('+') ~ ':' ~ .values.sort.join }).join(',');
        if $got ne 'ident:lang,op:=,ident:fr' {
            $bad = $i;
            last;
        }
    }
    is $bad, -1, 'map(*.Hash) builds each Hash from its own element when hot';
}

{
    my sub collect() {
        my @r;
        @r.push($_) for 1 .. 3;
        @r
    }
    my $bad = -1;
    for ^10_000 -> $i {
        my @a := collect();
        my @b := collect();
        if @a === @b || @a != 3 || @b != 3 {
            $bad = $i;
            last;
        }
    }
    is $bad, -1, 'a returned my-array is a fresh container per call when hot';
}

# vim: expandtab shiftwidth=4
