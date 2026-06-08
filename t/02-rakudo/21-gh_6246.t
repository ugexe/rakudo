use Test;

# GH#6246: `my %h is Set/Bag/Mix = ...` must not dirty the empty
# set()/bag()/mix() sentinel. The initializer compiled to STORE running on
# the value bound to the variable, which for these immutable types is the
# shared empty sentinel returned by .new.

plan 18;

{
    my %h is Set = "a";
    is %h.keys.sort.join(","), "a", 'Set initializer populates the variable';
    is set().elems, 0, 'set() sentinel stays empty after Set initializer';
    ok %h !=:= set(), 'initialized Set is not the shared sentinel';
}

{
    my %h is Bag = "x", "x", "y";
    is %h.total, 3, 'Bag initializer populates the variable';
    is bag().total, 0, 'bag() sentinel stays empty after Bag initializer';
    ok %h !=:= bag(), 'initialized Bag is not the shared sentinel';
}

{
    my %h is Mix = "p" => 2.5, "q" => 1;
    is %h.total, 3.5, 'Mix initializer populates the variable';
    is mix().total, 0, 'mix() sentinel stays empty after Mix initializer';
    ok %h !=:= mix(), 'initialized Mix is not the shared sentinel';
}

# Two independent declarations must not share state through the sentinel.
{
    my %a is Set = "a";
    my %b is Set = "b";
    is %a.keys.sort.join(","), "a", 'first Set keeps its own keys';
    is %b.keys.sort.join(","), "b", 'second Set keeps its own keys';
    is set().elems, 0, 'sentinel still empty after two Set declarations';
}

# An empty initializer yields a valid empty Set without dirtying the sentinel.
{
    my %h is Set = ();
    is %h.elems, 0, 'empty Set initializer yields an empty Set';
    ok %h eqv set(), 'empty Set initializer is value-equal to set()';
}

# A non-QuantHash explicit container base type must be left alone: shaped
# arrays with an explicit base type keep their shape through the initializer.
# (state %h is Set / state @a is Array are a separate, pre-existing defect and
# are intentionally not covered here.)
{
    my @a[3] is Array = 1, 2, 3;
    is @a.shape.join(","), "3", 'shaped @a[3] is Array keeps its shape';
    is @a.join(","), "1,2,3", 'shaped @a[3] is Array keeps its contents';
}

{
    my @a[2;2] is Array[Int] = (1, 2), (3, 4);
    is @a.shape.join(","), "2,2", 'shaped @a[2;2] is Array[Int] keeps its shape';
    is @a[1;1], 4, 'shaped @a[2;2] is Array[Int] keeps its contents';
}

# vim: expandtab shiftwidth=4
