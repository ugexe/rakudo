use Test;

plan 7;

# An unhandled Failure discarded in sink context must surface (throw),
# even as an element of a list literal or parenthesised group.

dies-ok { Failure.new("boom"); 0 },
    'a bare Failure discarded in sink throws';

dies-ok { Failure.new("boom"), Failure.new("other"); 0 },
    'a Failure element of a comma list discarded in sink throws';

dies-ok { (Failure.new("boom"), Failure.new("other")); 0 },
    'a Failure element of a parenthesised list discarded in sink throws';

dies-ok { (Failure.new("boom"); Failure.new("other")); 0 },
    'a Failure statement of a semicolon list discarded in sink throws';

dies-ok { (Failure.new("boom"),); 0 },
    'a Failure in a single-element list literal discarded in sink throws';

dies-ok { ((Failure.new("boom"),),); 0 },
    'a Failure nested in list literals discarded in sink throws';

# Assigning a Failure handles it, so sinking the handled value is fine.
lives-ok { my $f = Failure.new("boom"); $f; 0 },
    'a handled Failure discarded in sink does not throw';

# vim: expandtab shiftwidth=4
