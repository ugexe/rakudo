use lib <t/02-rakudo/test-packages>;
use Test;
use TopicDeclarationPrecomp;

plan 5;

# A topic declaration gives its slot a container that lives in a lexical
# of the scope, and a frame a BEGIN runs is kept by the closures the
# module serializes, so the module lives under test-packages to be
# precompiled.

is unit-topic(), 9,
    'a `my $_` at the top of a precompiled module is read by its subs';
is topic-for(), 5,
    'a `my $_` under a for modifier in a precompiled sub is a container of the sub';
is TopicDeclarationPrecomp::CLOSURE(), 5,
    'a closure over a `my $_` made at BEGIN time in a precompiled module reads it';
is match-var(), 8,
    'a `my $/` in a precompiled sub is a container of the sub';
class C does R { }
is C.m, 7,
    'a `my $_` under a given modifier in a precompiled role method is a container of the method';
