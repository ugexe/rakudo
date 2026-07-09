use Test;

plan 15;

# A Range passed as a version-matcher was coerced to a (mangled) Version by
# CompUnit::DependencySpecification, so `:ver(v1.0.0..*)` never matched an
# installed version, and stringifying the spec iterated the Range (which has
# no .succ for Version endpoints) and threw.

my $ds := CompUnit::DependencySpecification;

{
    my $spec = $ds.new(:short-name<Foo>, :version-matcher(v1.0.0..*));
    ok $spec.version-matcher ~~ Range, 'an open Range version-matcher is kept as a Range';
    ok v1.5.0 ~~ $spec.version-matcher, 'a version inside an open range matches';
    nok v0.9.0 ~~ $spec.version-matcher, 'a version below an open range does not match';
    lives-ok { ~$spec }, 'stringifying an open-range spec does not iterate the Range';
}

{
    my $spec = $ds.new(:short-name<Foo>, :version-matcher(v1.0.0..v2.0.0));
    ok $spec.version-matcher ~~ Range, 'a closed Range version-matcher is kept as a Range';
    ok v1.5.0 ~~ $spec.version-matcher, 'a version inside a closed range matches';
    nok v2.5.0 ~~ $spec.version-matcher, 'a version above a closed range does not match';
    lives-ok { ~$spec }, 'stringifying a closed-range spec does not iterate the Range';
}

# Regression: the existing matcher kinds are unchanged.
{
    my $spec = $ds.new(:short-name<Foo>, :version-matcher(v1.2.3));
    ok $spec.version-matcher ~~ Version, 'a Version version-matcher stays a Version';
    is ~$spec, 'Foo:ver<1.2.3>', 'a Version spec stringifies without a v-prefix, as before';
}

{
    # A string matcher is still coerced to a Version (so `+` still works).
    my $spec = $ds.new(:short-name<Foo>, :version-matcher('1.0.0+'));
    ok $spec.version-matcher ~~ Version, 'a string version-matcher is coerced to a Version';
    ok v2.0.0 ~~ $spec.version-matcher, 'the coerced 1.0.0+ matcher accepts a later version';
}

# A precompilation dependency record round-trips the spec through .raku and
# EVAL, so a Range matcher must come back as a Range, not as a string that
# the accessor then mangles into a Version.
{
    use MONKEY-SEE-NO-EVAL;
    my $spec = EVAL $ds.new(:short-name<Foo>, :version-matcher(v1.0.0..v2.0.0)).raku;
    ok $spec.version-matcher ~~ Range, 'a closed Range survives a .raku round-trip as a Range';
    ok v1.5.0 ~~ $spec.version-matcher, 'the round-tripped closed range still matches an in-range version';
    my $open = EVAL $ds.new(:short-name<Foo>, :version-matcher(v1.0.0..*)).raku;
    ok $open.version-matcher ~~ Range, 'an open Range survives a .raku round-trip as a Range';
}

# vim: expandtab shiftwidth=4
