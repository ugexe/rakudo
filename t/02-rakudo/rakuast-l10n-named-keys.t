use lib <t/packages/Test-Helpers>;
use Test;
use Test::Helpers;

# Rakuast-only: the fix lives in src/Raku/Grammar.nqp.  The legacy
# frontend (src/Perl6/Grammar.nqp) has not been updated.
unless %*ENV<RAKUDO_RAKUAST> {
    plan :skip-all<rakuast-only fix; set RAKUDO_RAKUAST=1>;
    exit 0;
}

plan 8;

# Regression coverage for: under L10N slang scope, `named2str` must be
# applied to colonpair-as-term and fatarrow-as-term, not only to
# argument-list colonpairs.  Specifically, `:!elementen` as the right
# operand of `...^` was reaching SEQUENCE as Pair("elementen", False)
# instead of the translated Pair("elems", False), causing
# `Pair.ACCEPTS` to look up a method `elementen` and fail.  See the
# original report at https://github.com/rakudo/rakudo/issues/6046

# Minimal local slang shim that defines just enough of L10N::NL to
# exercise the translation paths without depending on the ecosystem
# module.
my $slang-source = q:to/SLANG/;
    role L10N::Mini {
        use experimental :rakuast;
        method named2str (str $key) {
            my %mapping = "elementen", "elems",
                          "sleutel",   "key",
                          "paar",      "pair";
            %mapping{$key} // $key
        }
    }
    my sub EXPORT() {
        my $LANG := $*LANG;
        $LANG.define_slang('MAIN',
          $LANG.slang_grammar('MAIN').^mixin(L10N::Mini),
          $LANG.slang_actions('MAIN')
        );
        BEGIN Map.new
    }
    SLANG

# Stage the shim into a writable temp dir for is-run's compunit lookup.
my $tmp = $*TMPDIR.add("rakuast-l10n-test-{$*PID}");
$tmp.add("L10N").mkdir;
$tmp.add("L10N/Mini.rakumod").spurt($slang-source);
END {
    # Use shell rm -rf to clean the temp dir; is-run invocations leave
    # a `.precomp` cache underneath which our plain `rmdir` can't walk.
    run(<rm -rf>, $tmp.Str) if $tmp.defined && $tmp.e;
}

sub run-with(Str $code, $desc, *%args) {
    is-run $code, $desc, :compiler-args[«-I "$tmp"»], |%args
}

# 1) Issue 6046 minimal: :!elementen as adverb to ...^ inside L10N scope
run-with q:to/CODE/,
    use L10N::Mini;
    say (1, 2, 3 ...^ :!elementen)[^5]
    CODE
    ':!elementen translates to :!elems as ...^ adverb',
    :out("(1 2 3 4 5)\n");

# 2) Same shape with FatArrow style: elementen => False
run-with q:to/CODE/,
    use L10N::Mini;
    say (1, 2, 3 ...^ (elementen => False))[^5]
    CODE
    'elementen => False FatArrow term translates',
    :out("(1 2 3 4 5)\n");

# 3) Outside L10N scope, untouched (dies at runtime with method-not-found)
run-with q:to/CODE/,
    say (1, 2, 3 ...^ :!elementen)[^5]
    CODE
    'outside L10N scope, :!elementen is left literal (fails at runtime)',
    :err(/'No such method'/),
    :exitcode(*);

# 4) Random keys (not in the L10N map) pass through unchanged
run-with q:to/CODE/,
    use L10N::Mini;
    my $p = :totally-random-key<v>;
    say $p.key
    CODE
    'random keys not in L10N map remain untranslated',
    :out("totally-random-key\n");

# 5) Mapped keys in standalone Pair literal DO translate (consistent
#    treatment of named identifier in L10N scope, matching the
#    `named2str` contract)
run-with q:to/CODE/,
    use L10N::Mini;
    my $p = :elementen<v>;
    say $p.key
    CODE
    'mapped key in standalone Pair literal translates inside L10N scope',
    :out("elems\n");

# 6) FatArrow with mapped key translates
run-with q:to/CODE/,
    use L10N::Mini;
    my $p = elementen => 5;
    say $p.key
    CODE
    'mapped key in FatArrow translates inside L10N scope',
    :out("elems\n");

# 7) Lexical scope: outside the use-block, no translation
run-with q:to/CODE/,
    {
        use L10N::Mini;
        my $p = :elementen<v>;
        say $p.key;
    }
    my $q = :elementen<v>;
    say $q.key
    CODE
    'L10N translation is lexically scoped to the use-block',
    :out("elems\nelementen\n");

# 8) Without any L10N slang loaded, Pair literal keys pass through
is-run q:to/CODE/,
    my $p = :elementen<v>;
    say $p.key
    CODE
    'no L10N: Pair literal keys pass through',
    :out("elementen\n");

# vim: expandtab shiftwidth=4
