# The base of all contextualizers.
class RakuAST::Contextualizer
  is RakuAST::Term
{
    # The thing to be contextualized.
    has RakuAST::Contextualizable $.target;

    method new(RakuAST::Contextualizable $target) {
        my $obj := nqp::create(self);
        nqp::bindattr($obj, RakuAST::Contextualizer, '$!target', $target);
        $obj
    }

    # A contextualizer around a lone Whatever ($(*), @(*), %(*)) is the
    # whatever-feed reader: it contextualizes the values most recently fed
    # to `*`, or the values fed to the enclosing feed stage.
    method IMPL-WHATEVER-FEED-READER() {
        nqp::istype($!target, RakuAST::StatementSequence)
          && $!target.IMPL-IS-SINGLE-EXPRESSION
          && nqp::istype(
               self.IMPL-UNWRAP-LIST($!target.statements)[0].expression,
               RakuAST::Term::Whatever
             )
    }

    method IMPL-EXPR-QAST(RakuAST::IMPL::QASTContext $context) {
        my $target-qast;
        if self.IMPL-WHATEVER-FEED-READER {
            # Rakudo::Internals is bound as an HLL symbol when the setting
            # loads, so the reader needs no compile-time setting lookup.
            $target-qast := QAST::Op.new(
                :op('callmethod'), :name('WHATEVER-FEED'),
                QAST::Op.new(
                    :op('gethllsym'),
                    QAST::SVal.new( :value('Raku') ),
                    QAST::SVal.new( :value('Rakudo::Internals') )
                )
            );
        }
        else {
            $target-qast := $!target.IMPL-TO-QAST($context);
        }
        QAST::Op.new(
            :op('callmethod'), :name(self.IMPL-METHOD),
            $target-qast
        )
    }

    method IMPL-CAN-INTERPRET() {
        !self.IMPL-WHATEVER-FEED-READER && $!target.IMPL-CAN-INTERPRET
    }

    method IMPL-INTERPRET(RakuAST::IMPL::InterpContext $ctx) {
        my str $method := self.IMPL-METHOD;
        $!target.IMPL-INTERPRET($ctx)."$method"()
    }

    method visit-children(Code $visitor) {
        $visitor($!target);
    }
}

# The item contextualizer.
class RakuAST::Contextualizer::Item
  is RakuAST::Contextualizer
{
    method IMPL-METHOD() { 'item' }
    method sigil { '$' }
}

# The list contextualizer.
class RakuAST::Contextualizer::List
  is RakuAST::Contextualizer
{
    method IMPL-METHOD() { 'cache' }
    method sigil { '@' }
}

# The hash contextualizer.
class RakuAST::Contextualizer::Hash
  is RakuAST::Contextualizer
{
    method IMPL-METHOD() { 'hash' }
    method sigil { '%' }
}
