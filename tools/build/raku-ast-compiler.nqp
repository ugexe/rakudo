# We want to compile Raku code by building up an AST, and thanks to macros,
# and other compile-time functionality, that AST needs to be something that
# is visible to Raku code. Thus, it should be made up of objects that are
# Raku-like - that is, we can introspect them just like any other Raku object.
# This means we need to build them up using the Raku MOP. The most convenient
# way to use *that* would be to write Raku code - but we can't, because we
# can't compile Raku code without the Raku AST!
#
# Thus, we need to piece together the Raku AST objects using the MOP. That is
# very tedious to do by hand. Thus this boring little compiler, which lets us
# write things that look like classes with attributes and methods, but with
# NQP bodies. These are then turned into code that uses the MOP to piece the
# AST nodes together - giving us rather easier to write/maintain code.

# Parser

grammar RakuASTParser {
    rule TOP {
        <?> <package>* [$ || <.panic("Confused")>]
    }

    proto rule package {*}
    rule package:sym<class> { <sym> <package-def('class')> }
    rule package:sym<role> { <sym> <package-def('role')> }

    rule package-def($*PKGDECL) {
        <name> {}
        :my $*PACKAGE-NAME := ~$<name>;
        :my %*ATTRS;
        [ 'is' <parent=.name> | 'does' <role=.name> ]*
        [ '{' || <.panic("Missing block in $*PKGDECL $*PACKAGE-NAME declaration")> ]
        [ <attribute-decl> | <method-decl> ]*
        [ '}' || <.panic("Missing '}' in $*PKGDECL $*PACKAGE-NAME declaration")> ]
    }

    rule attribute-decl {
        'has' <type=.name> [<attribute> || $<public-attribute>=['$.' <.identifier>]]
        [ ';' || <.panic('Missing ; after attribute declaration')> ]
    }

    token attribute {
        '$!' <.identifier>
    }

    rule method-decl {
        'method' <name=.identifier> {}
        :my $*METHOD-NAME := ~$<name>;
         <signature>? {}
        :my $*RETURNS := $<signature> && $<signature><returns> ?? ~$<signature><returns> !! '';
         <method-body>
    }

    token method-body {
        [ '{' || <.panic("Missing block in method '$*METHOD-NAME' declaration")> ]
        <nqp-code>
        [ '}' || <.panic("Missing '}' in method '$*METHOD-NAME' declaration")> ]
    }

    rule signature {
        '(' <parameter>* % [',' ] [ '-->' <returns=.name> ]? ')'
    }

    rule parameter {
        <type=.name>?
        [$<named>=':'|$<slurpy>='*']?$<name>=[<[$@%]><.identifier>][$<optional>=<[?!]>]?
        [$<raw>=[is raw]]?
    }

    token sigil {
        '$' | '@' | '%'
    }

    token nqp-code {
        # We want to do some minor transforms on the NQP code, so just sorta
        # tokenize it. If it's good enough for the C preproc... :-)
        (
        | <name>
        | <attribute>
        | $<variable>=[<.sigil> '*'? <.identifier>]
        | <string>
        | ['/' <-[/]>+ '/' || '//' || '/' <?before \s* [\d | '$']>] # regex or // operator
        | $<numeric>=[ \d+ ['.' \d*]? [<[eE]> \d+]? ]
        | $<paren>='(' {} <nqp-code> [ ')' || {} <.panic('Missing ) for opening ( at line ' ~ self.line-of($<paren>))> ]
        | $<brace>='{' {} <nqp-code> [ '}' || {} <.panic('Missing } for opening { at line ' ~ self.line-of($<brace>))> ]
        | $<brckt>='[' {} <nqp-code> [ ']' || {} <.panic('Missing ] for opening [ at line ' ~ self.line-of($<brckt>))> ]
        | <?[\s#]> <ws>
        || $<other>=[<-[{}()\[\]'"\s\w$/#]>+] # don't include in LTM as it'd win too much
        )*
    }

    token string {
        | "'" [<-[\\']>+ | "\\'" | "\\\\"]* ["'" || <.panic('Unterminated string')> ]
        | '"' [<-[\\"]>+ | '\\"' | "\\".]* ['"' || <.panic('Unterminated string')> ]
    }

    token name {
        <identifier>+ % '::'
    }

    token identifier {
        <.ident> [<[-']><.ident>]*
    }

    token ws {
        <!ww>
        [
        | \s+
        | '#' \N*
        ]*
    }

    method panic($message) {
        nqp::die( "$message near '" ~ nqp::substr(self.orig, self.pos, 20) ~ "' at "
            ~ $*CURRENT-FILE ~ ":" ~ HLL::Compiler.lineof(self.target, self.pos, :cache))
    }

    method line-of($whatever) {
        -1
    }
}

# AST

role Node {
    has $!line;
    method line() { $!line }
    method set-line($line) { $!line := $line; }
}

class CompUnit does Node {
    has @!packages;
    has $!filename;
    method packages() { @!packages }
    method filename() { $!filename }
}

class Package does Node {
    has $!type; # 'class' or 'role'
    has $!name;
    has @!parents;
    has @!roles;
    has @!attributes;
    has @!methods;
    method type() { $!type }
    method is-role() { $!type eq 'role' }
    method name() { $!name }
    method parents() { @!parents }
    method roles() { @!roles }
    method attributes() { @!attributes }
    method methods() { @!methods }
}

class Attribute does Node {
    has $!type;
    has $!name;
    has $!has-accessor;
    method type() { $!type }
    method name() { $!name }
    method has-accessor() { $!has-accessor }
    method getattr-op() {
        $!type eq 'int' ?? 'getattr_i' !!
        $!type eq 'num' ?? 'getattr_n' !!
        $!type eq 'str' ?? 'getattr_s' !!
                           'getattr'
    }
}

class Method does Node {
    has $!name;
    has @!parameters;
    has $!returns;
    has $!body;
    method name() { $!name }
    method parameters() { @!parameters }
    method returns() { $!returns }
    method body() { $!body }
}

class Parameter does Node {
    has $!type;
    has $!slurpy;
    has $!named;
    has $!name;
    has $!optional;
    has $!raw;
    method type() { $!type }
    method named() { $!named }
    method slurpy() { $!slurpy }
    method name() { $!name }
    method optional() { $!optional }
    method raw() { $!raw }
}

# The keywords NQP may split off the front of a longer name, as in if-return.
my constant SPLIT-WORDS := nqp::hash(
  'eq', 1, 'ne', 1, 'lt', 1, 'le', 1, 'gt', 1, 'ge', 1, 'if', 1, 'unless', 1, 'elsif', 1,
  'else', 1, 'while', 1, 'until', 1, 'for', 1, 'repeat', 1
);

# The words in the text, with where each starts, including those in strings
# and comments and the parts of a name led by a keyword. A $ or @ variable
# with no twigil and a method after . are left out.
sub bare-words(str $text) {
    my %words;
    for match($text, / <!after \w> [<alpha> | _] \w* [<[-']> [<alpha> | _] \w*]* /, :global) {
        my int $at := $_.from;
        unless $at && nqp::index('$@.', nqp::substr($text, $at - 1, 1)) >= 0 {
            %words{~$_} := [] unless nqp::existskey(%words, ~$_);
            nqp::push(%words{~$_}, $at);
            my @parts := nqp::split('-', subst(~$_, /\'/, '-', :global));
            if nqp::elems(@parts) > 1 && nqp::existskey(SPLIT-WORDS, @parts[0]) {
                my int $part := $at;
                for @parts {
                    %words{$_} := [] unless nqp::existskey(%words, $_);
                    nqp::push(%words{$_}, $part);
                    $part := $part + nqp::chars($_) + 1;
                }
            }
        }
    }
    %words
}

class NQPCode does Node {
    has $!body;
    has $!raw;
    has $!source;
    has $!from;
    has $!is-stub;
    has $!statements;
    has $!declared;
    has $!misread;
    has $!hidden-return;
    has $!routine;
    has $!control-returns;
    has $!returns;
    method body() { $!body }

    # The code without the return checks, for a body that runs as a block in a
    # handler for returns.
    method raw() { $!raw }

    # The code as written and where it starts in its file.
    method source() { $!source }
    method from() { $!from }

    # Whether the tokenizer may have misread the code or the code may give its
    # own meaning to True, False, TRUE, FALSE or ReturnCheck, and whether it
    # has a return whose check the generator cannot be sure of.
    method misread() { $!misread }
    method hidden-return() { $!hidden-return }

    # Where in its file each return the tokenizer reads as the keyword starts,
    # in a method that declares --> Bool.
    method returns() { $!returns }

    # Whether the code may declare a routine, whose returns leave it rather
    # than the method.
    method declares-routine() { $!routine }

    # Whether the block of a control statement at the level of the code has a
    # return the generator checks.
    method control-returns() { $!control-returns }
    method is-stub() { $!is-stub }
    method Str() { $!body }

    # The variables the code declares outside of any block.
    method declared() { $!declared }

    # The code before the last statement and that statement, when the last is
    # not a return and can be wrapped in parens with no CATCH or CONTROL to
    # cover the check, or NQPMu when the code has to run as a block.
    method split() {
        # Misread text may hide the end of a statement, and a CATCH or CONTROL
        # anywhere in the code may cover the check.
        my %words := bare-words($!source);
        return NQPMu if $!misread || nqp::existskey(%words, 'CATCH') || nqp::existskey(%words, 'CONTROL');
        my int $last := nqp::elems($!statements) - 1;
        $last := $last - 1 while $last >= 0 && $!statements[$last]<first> eq '';
        return NQPMu if $last < 0 || $!statements[$last]<blocked>
          || $!statements[$last]<first> eq 'return';
        my $statement := $!statements[$last];
        my $prefix := nqp::substr($!body, 0, $statement<start>);
        my $final := nqp::substr($!body, $statement<start>, $statement<end> - $statement<start>);
        [$prefix, $final]
    }
}

# AST-building actions

# The words of the statement modifiers. A statement control always takes a
# block, whose braces already mark it.
my constant STATEMENT-WORDS := nqp::hash(
  'if', 1, 'unless', 1, 'while', 1, 'until', 1, 'for', 1
);

# The words NQP reads as an infix.
my constant INFIX-WORDS := nqp::hash('eq', 1, 'ne', 1, 'lt', 1, 'le', 1, 'gt', 1, 'ge', 1);

# The words that declare a package, whose body may run when it is composed.
my constant PACKAGE-WORDS := nqp::hash(
  'module', 1, 'knowhow', 1, 'class', 1, 'grammar', 1, 'role', 1, 'native', 1, 'stub', 1
);

# The words that start a quote.
my constant QUOTE-WORDS := nqp::hash('q', 1, 'qq', 1, 'Q', 1);

# The words that declare a routine.
my constant ROUTINE-WORDS := nqp::hash(
  'sub', 1, 'method', 1, 'regex', 1, 'token', 1, 'rule', 1, 'multi', 1, 'proto', 1
);

# The words that start a statement or clause whose block ends it when the
# block ends its line, as in NQP. Unlike in NQP, a block ending the line of
# any other statement does not end it.
my constant CONTROL-WORDS := nqp::hash(
  'if', 1, 'unless', 1, 'elsif', 1, 'else', 1, 'while', 1, 'until', 1,
  'for', 1, 'repeat', 1
);

# The tokens after which a word is a method, named argument, sub or hash
# key rather than a keyword. A return after any of them but . is left to
# the handler for returns, since a lone ! or < before it would look the same.
my constant NOT-KEYWORD-AFTER := nqp::hash(
  '.', 1, '!', 1, ':', 1, '&', 1, '<', 1, '.^', 1, '.?', 1, '.&', 1, '.!', 1, '.=', 1
);

class RakuASTActions {
    method attach($/, $node) {
        $node.set-line(HLL::Compiler.lineof($/.target, $/.from, :cache));
        make $node;
    }

    method TOP($/) {
        my @packages;
        for $<package> {
            @packages.push($_.ast);
        }
        self.attach($/, CompUnit.new(:@packages, :filename($*CURRENT-FILE)));
    }

    method package:sym<class>($/) { make $<package-def>.ast }
    method package:sym<role>($/) { make $<package-def>.ast }

    method package-def($/) {
        my $name := ~$<name>;
        my @parents;
        for $<parent> {
            nqp::push(@parents, ~$_);
        }
        if @parents && $*PKGDECL eq 'role' {
            $/.panic("A role cannot inherit; $*PACKAGE-NAME can only do other roles");
        }
        my @roles;
        for $<role> {
            nqp::push(@roles, ~$_);
        }
        my @attributes;
        for $<attribute-decl> {
            @attributes.push($_.ast);
        }
        my @methods;
        for $<method-decl> {
            @methods.push($_.ast);
        }
        self.attach($/, Package.new(:type($*PKGDECL), :$name, :@parents, :@roles, :@attributes, :@methods));
    }

    method attribute-decl($/) {
        my $type := ~$<type>;
        my $attr;
        if $<attribute> {
            my $name := ~$<attribute>;
            $attr := Attribute.new(:$type, :$name, :!has-accessor);
        }
        else {
            my $name := nqp::replace(~$<public-attribute>, 1, 1, '!');
            $attr := Attribute.new(:$type, :$name, :has-accessor);
        }
        %*ATTRS{$attr.name} := $attr;
        self.attach($/, $attr);
    }

    method method-decl($/) {
        my $name := ~$<name>;
        my @parameters := $<signature> ?? $<signature>.ast !! [];
        my $returns := $<signature> && $<signature><returns> ?? ~$<signature><returns> !! NQPMu;
        my $body := $<method-body>.ast;
        self.attach($/, Method.new(:$name, :@parameters, :$returns, :$body));
    }

    method method-body($/) {
        make $<nqp-code>.ast
    }

    method signature($/) {
        my @parameters;
        for $<parameter> {
            @parameters.push($_.ast);
        }
        make @parameters;
    }

    method parameter($/) {
        my $type := $<type> ?? ~$<type> !! NQPMu;
        my $named := ?$<named>;
        my $slurpy := ?$<slurpy>;
        my $name := ~$<name>;
        my $optional := $named
            ?? ($<optional> eq '!' ?? 0 !! 1)
            !! ($<optional> eq '?' ?? 1 !! 0);
        my $raw := ?$<raw>;
        self.attach($/, Parameter.new(:$type, :$named, :$slurpy, :$name, :$optional, :$raw));
    }

    method nqp-code($/) {
        my @chunks;
        my @code;
        # Each statement at this level records its first token, its span,
        # whether a block or modifier keeps it out of parens, and what decides
        # which brace is its block when it is a control statement.
        my $statement := nqp::hash('first', '', 'blocked', 0);
        my @statements := [$statement];
        my @declared;
        my int $declaring := 0;
        # A return in a method that declares --> Bool has its value checked too.
        my int $check := $*RETURNS eq 'Bool';
        my str $close := "), '$*METHOD-NAME')";
        my int $returning := 0;
        my int $returned := 0;
        my int $return-at := 0;
        my str $return-literal := '';
        my %returns;
        my @raw;
        my int $closed-block := 0;
        my int $misread := 0;
        my int $hidden-return := 0;
        my int $routine := 0;
        my int $control-returns := 0;
        my int $return-ternary := 0;
        my int $ternary := 0;
        my int $return-in-ternary := 0;
        my int $return-next := 0;
        my int $pointy := 0;
        my str $previous := '';
        my int $previous-name := 0;
        my int $after-ws := 0;
        my int $previous-term := 0;
        my int $length := 0;
        my @tokens := $/[0];
        # A return of a literal True or False needs no check. For any other
        # value the check opens after the return and closes where the value
        # ends.
        my sub end-return() {
            $returning := 0;
            return '' if $return-literal eq 'TRUE' || $return-literal eq 'FALSE';
            my str $open := ' ReturnCheck.bool((';
            nqp::splice(@chunks, nqp::list($open), $return-at, 0);
            $length := $length + nqp::chars($open);
            ($returned ?? '' !! 'NQPMu') ~ $close
        }
        my int $n := nqp::elems(@tokens);
        my int $i := -1;
        # The index of the first token after the one at $from that is not
        # space or a comment, or $n when there is none.
        my sub next-token(int $from) {
            my int $at := $from + 1;
            ++$at while $at < $n && @tokens[$at]<ws>;
            $at
        }
        # Whether the token at $at is the key of a pair, and whether it is a
        # label.
        my sub pair-key(int $at) {
            my int $next := next-token($at);
            $next < $n && @tokens[$next]<other> && nqp::eqat(~@tokens[$next], '=>', 0)
        }
        my sub label(int $at) {
            $at + 1 < $n && @tokens[$at + 1]<other> && nqp::eqat(~@tokens[$at + 1], ':', 0)
        }
        while ++$i < $n {
            my $/ := @tokens[$i];
            my str $chunk;
            my str $raw;
            my int $is-return := 0;
            my int $is-declared := 0;
            my int $clause-block := 0;
            if $<name> {
                # Rewrite `self` into `$SELF` and True/False into TRUE/FALSE.
                my $name := ~$<name>;
                if $name eq 'self' {
                    $chunk := '$SELF';
                }
                elsif $name eq 'True' || $name eq 'False' {
                    # The key of a pair is a string, so it keeps its case. A
                    # True or False after a word other than return, or as a
                    # label, may name something the code declares.
                    $chunk := pair-key($i) ?? $name !! nqp::uc($name);
                    $misread := 1 if $previous-name && $previous ne 'return' || label($i);
                }
                else {
                    my int $method := nqp::chars($previous) && nqp::eqat($previous, '.', nqp::chars($previous) - 1);
                    my int $word := !$method && !nqp::existskey(NOT-KEYWORD-AFTER, $previous)
                      && !pair-key($i) && !label($i);
                    $chunk := $name;
                    # The tokenizer reads q, qq or Q quotes and the bodies of
                    # regexes as code. A BEGIN, use or package may redefine
                    # TRUE, FALSE or ReturnCheck.
                    $misread := 1 if nqp::existskey(QUOTE-WORDS, $name)
                      || !$method && ($name eq 'regex' || $name eq 'token' || $name eq 'rule')
                      || !$method && ($name eq 'BEGIN' || $name eq 'use' || nqp::existskey(PACKAGE-WORDS, $name));
                    $routine := 1 if !$method && nqp::existskey(ROUTINE-WORDS, $name);
                    # The tokenizer reads a name such as if-return as one word.
                    my $keyword := $name ~~ /^ (\w+) <[-']>/;
                    $misread := 1 if !$method && !nqp::existskey(NOT-KEYWORD-AFTER, $previous)
                      && $keyword && nqp::existskey(SPLIT-WORDS, ~$keyword[0]);
                    $hidden-return := 1 if $check && $name eq 'return' && !$word && !$method;
                    # What follows a while or until after the block of a repeat
                    # is its condition, which has no block.
                    if $word && $statement<first> eq 'repeat' && ($name eq 'while' || $name eq 'until') {
                        $statement<condition> := 1 if $statement<blocked>;
                        $statement<loop-word> := 1;
                    }
                    if $word && nqp::existskey(STATEMENT-WORDS, $name) {
                        $statement<blocked> := 1;
                        if $returning {
                            # NQP has no return without a value before a
                            # modifier.
                            $hidden-return := 1 unless $returned;
                            $raw := $name;
                            my str $end := end-return();
                            $chunk := nqp::chars($end) ?? $end ~ ' ' ~ $name !! $name;
                        }
                    }
                    elsif $word && $check && $name eq 'return' {
                        # A return in the value of another would leave the other
                        # unchecked. One after a -> may be in a pointy default,
                        # which runs when the block is called.
                        $hidden-return := 1 if $returning || $pointy;
                        $returning := 1;
                        $return-in-ternary := $ternary;
                        $return-next := 1;
                        $returned := 0;
                        $return-at := nqp::elems(@chunks) + 1;
                        $return-literal := '';
                        $return-ternary := 0;
                        $is-return := 1;
                        %returns{$/.from} := 1;
                    }
                }
                $declaring := 1 if $name eq 'my' || $name eq 'our' || $name eq 'state';
            }
            elsif $<attribute> {
                my $name := ~$<attribute>;
                if %*ATTRS{$name} -> $attr {
                    $chunk := "nqp::" ~ $attr.getattr-op ~ "(\$SELF, $*PACKAGE-NAME, '$name')";
                }
                else {
                    $/.panic("No such attribute $name in $*PACKAGE-NAME");
                }
            }
            elsif $<variable> {
                $chunk := ~$/;
                @declared.push($chunk) if $declaring;
                $is-declared := $declaring;
                # A % before a quote or routine word may be a modulo.
                $misread := 1 if nqp::eqat($chunk, '%', 0)
                  && (nqp::existskey(QUOTE-WORDS, nqp::substr($chunk, 1))
                       || nqp::existskey(ROUTINE-WORDS, nqp::substr($chunk, 1)));
            }
            elsif $<string> {
                $chunk := $<string>.ast;
                # A double quote in the code of a string, or in a comment in
                # the brackets of a \c, \x or \o escape, may end the tokenizer's
                # string.
                $misread := 1 if nqp::eqat($chunk, '"', 0) && (nqp::index($chunk, '{') >= 0
                  || nqp::index($chunk, '$(') >= 0 || nqp::index($chunk, '$<') >= 0
                  || $chunk ~~ / \\ <[cxo]> '[' <-[\]]>* ['#' | \v | $] /);
            }
            elsif $<paren> || $<brckt> {
                my $inner := $<nqp-code>.ast;
                @declared.push($_) for $inner.declared;
                $misread := 1 if $inner.misread;
                # No control statement starts in parens or brackets, so a block
                # in them is a closure. After a -> they may be in a pointy
                # signature, which runs when the block is called.
                $hidden-return := 1 if $inner.hidden-return || $inner.control-returns
                  || $pointy && nqp::elems($inner.returns);
                $routine := 1 if $inner.declares-routine;
                %returns{$_.key} := 1 for $inner.returns;
                $chunk := $<paren>
                  ?? '(' ~ $inner ~ ')'
                  !! '[' ~ $inner ~ ']';
                $raw := $<paren>
                  ?? '(' ~ $inner.raw ~ ')'
                  !! '[' ~ $inner.raw ~ ']';
            }
            elsif $<brace> {
                my $inner := $<nqp-code>.ast;
                $misread := 1 if $inner.misread;
                $hidden-return := 1 if $inner.hidden-return;
                $routine := 1 if $inner.declares-routine;
                %returns{$_.key} := 1 for $inner.returns;
                # NQP reads a brace straight after a term as a subscript when it
                # holds one expression. One straight after a word is taken for a
                # block, as else{ is, even when the word is a call like foo{.
                $statement<glued> := 1 if $statement<control> && !$after-ws && !$previous-name;
                # A block that ends the clause of a control statement is its
                # block, which runs here.
                if $statement<control> && !$statement<condition> && !$statement<glued> && !$statement<unclear> {
                    my int $at := next-token($i);
                    my int $newline := 0;
                    my int $j := $i;
                    $newline := 1 if ~@tokens[$j] ~~ /\v/ while ++$j < $at;
                    my $next := $at < $n ?? @tokens[$at] !! NQPMu;
                    my str $word := $at < $n && $next<name> ?? ~$next<name> !! '';
                    # An infix word or a % may carry the statement on.
                    my int $term := $at < $n && ($next<name> && !nqp::existskey(INFIX-WORDS, ~$next<name>)
                      || $next<variable> && !nqp::eqat(~$next, '%', 0)
                      || $next<attribute> || $next<string> || $next<numeric>) ?? 1 !! 0;
                    $clause-block := $at >= $n || $next<other> && nqp::eqat(~$next, ';', 0)
                      || $newline && $term
                      || $word eq 'else' || $word eq 'elsif'
                      || $statement<first> eq 'repeat' && ($word eq 'while' || $word eq 'until');
                    # The line after this brace may carry the statement on,
                    # which leaves unclear which brace is the block.
                    $statement<unclear> := 1 if $newline && !$clause-block;
                }
                # A closure may be called under a CATCH that would catch the
                # failed check of a return in it.
                if nqp::elems($inner.returns) {
                    $hidden-return := 1 unless $clause-block;
                    $control-returns := 1 if $clause-block;
                }
                $statement<blocked> := 1;
                $raw := '{' ~ $inner.raw ~ '}';
                $chunk := '{' ~ $inner ~ '}';
            }
            else {
                $chunk := ~$/;
                # A division can be taken for a regex running on to the next
                # division, over a modifier or past the end of the statement.
                $misread := 1 if !$<ws> && !$<other> && !$<numeric> && nqp::chars($chunk) > 2;
                $pointy := 1 if $<other> && nqp::index($chunk, '->') >= 0;
                if $<other> && nqp::index($chunk, '??') >= 0 {
                    $ternary := $ternary + 1;
                    $return-ternary := $return-ternary + 1 if $returning;
                }
                elsif $<other> && nqp::index($chunk, '!!') >= 0 {
                    # A !! glued to another operator may be a prefix.
                    $misread := 1 if $chunk ne '!!';
                    if $returning && $return-ternary {
                        $return-ternary := $return-ternary - 1;
                    }
                    elsif $returning && $return-in-ternary {
                        # The !! of a ternary the return is in ends the value.
                        $raw := $chunk;
                        my str $end := end-return();
                        $chunk := nqp::chars($end) ?? $end ~ ' ' ~ $chunk !! $chunk;
                    }
                    $ternary := $ternary - 1 if $ternary;
                }
                if $returning && $<other> && nqp::index($chunk, ';') >= 0 {
                    # The ; that ends the statement also ends the value.
                    $raw := $chunk;
                    my int $at := nqp::index($chunk, ';');
                    $returned := 1 if $at;
                    $return-literal := 'x' if $at;
                    $chunk := nqp::substr($chunk, 0, $at) ~ end-return() ~ nqp::substr($chunk, $at);
                }
            }
            $raw := $chunk unless nqp::chars($raw);
            if $return-next && !$is-return {
                # NQP reads a return with no space before its value, such as
                # return( or return-1, as something else.
                $hidden-return := 1 unless $<ws> || $<other> && nqp::eqat($raw, ';', 0);
                $return-next := 0;
            }
            if $<ws> && $closed-block && $chunk ~~ /\v/ {
                # NQP may carry an expression on past such a block, so a return
                # still open here may not end at it.
                $hidden-return := 1 if $returning;
                $chunk := end-return() ~ $chunk if $returning;
                $statement<end> := $length;
                $statement := nqp::hash('first', '', 'blocked', 0);
                @statements.push($statement);
                $closed-block := 0;
                $ternary := 0;
                $pointy := 0;
            }
            # The tokenizer takes a # straight after a token, as in <#>, for a
            # comment, where NQP may not.
            $misread := 1 if $<ws> && nqp::eqat($chunk, '#', 0) && !$after-ws && $i;
            my int $after-was-ws := $after-ws;
            $after-ws := $<ws> ?? 1 !! 0;
            unless $<ws> {
                $declaring := 0 unless $<name>;
                # The tokenizer reads the words of an angle quote as code. An
                # angle quote starts where a term goes. A < with space before it
                # and none after may start one, as after return, or be an infix.
                $misread := 1
                  if $<other> && ($chunk ~~ /^ ['<' | '«'] /)
                  && (!nqp::chars($previous) || !$previous-name && $previous ~~ / <-[\w)\]}'"]> $ /
                       || $after-was-ws && $i + 1 < $n && !@tokens[$i + 1]<ws>);
                my int $angle := $<other> && nqp::index($chunk, '<') >= 0;
                my int $french := $<other> && nqp::index($chunk, '«') >= 0;
                # A < with space on each side after a term is infix, but after
                # a block or a variable being declared it may not be.
                if ($angle || $french) && !(nqp::eqat($chunk, '<', 0)
                  && $previous-term && $after-was-ws && $i + 1 < $n && @tokens[$i + 1]<ws>) {
                    my str $text := nqp::substr($/.target, $/.from);
                    # The tokenizer may read a quote, #, bracket, semicolon,
                    # line break, nested angle, backslash or return in an
                    # angle quote not as NQP does.
                    $misread := 1
                      if $angle && $text ~~ /^ <-[<«]>* '<' <-[>]>* [<['"#{}()\[\];\v<«»\\]> | <!after \w> return <!before \w>] /
                      || $french && $text ~~ /^ <-[<«]>* '«' <-[»]>* [<['"#{}()\[\];\v<>«\\]> | <!after \w> return <!before \w>] /;
                }
                if $returning && !$is-return {
                    $return-literal := !$returned && ($chunk eq 'TRUE' || $chunk eq 'FALSE') ?? $chunk !! 'x';
                    $returned := 1;
                }
                nqp::push(@code, ~$/);
                # Each ; ends a statement, and what follows it starts one.
                my int $at := $length;
                for $<other> ?? nqp::split(';', $chunk) !! [$chunk] -> $piece {
                    if $at > $length {
                        $statement<end> := $at - 1;
                        $statement := nqp::hash('first', '', 'blocked', 0);
                        @statements.push($statement);
                        $ternary := 0;
                        $pointy := 0;
                    }
                    if $statement<first> eq '' && $piece ne '' {
                        $statement<first> := $<name> ?? ~$<name> !! $piece;
                        $statement<start> := $at;
                        $statement<control> := $<name> && nqp::existskey(CONTROL-WORDS, ~$<name>)
                          && !pair-key($i) && !label($i);
                    }
                    $at := $at + nqp::chars($piece) + 1;
                }
                # Only the block of a clause may end the statement, and the
                # block of a repeat only when it follows the while or until.
                $closed-block := $clause-block
                  && ($statement<first> ne 'repeat' || $statement<loop-word>) ?? 1 !! 0;
                $previous := $chunk;
                $previous-name := $<name> ?? 1 !! 0;
                $previous-term := $<numeric> || $<paren> || $<brckt> || $<attribute>
                  || $<variable> && !$is-declared ?? 1 !! 0;
            }
            @chunks.push($chunk);
            @raw.push($raw);
            $length := $length + nqp::chars($chunk);
        }
        # A constant runs code at compile time, which could redefine TRUE,
        # FALSE or the check through the dynamic variables or frames of the
        # compiler.
        $misread := 1 if ~$/ ~~ / <!after \w> 'constant' <!before \w> /
          && ~$/ ~~ / <[$@%&]> '*' \w | getlexdyn | 'nqp::ctx' | getlexcaller | getlexrel /;
        # The code may give TRUE, FALSE or ReturnCheck its own meaning, even
        # where the tokenizer cannot see the name, as in the code of a string.
        $misread := 1 if ~$/ ~~ / <!after \w> [TRUE | FALSE | ReturnCheck] <!before \w> /;
        # A #line directive may run on over the lines after it, which NQP
        # then reads as part of the comment, and NQP reads a line that starts
        # with = after any horizontal space as pod.
        $misread := 1 if ~$/ ~~ / ^^ ['#' \s* 'line' | \h* '='] /;
        if $returning {
            # The value of a return runs to the end of the code.
            my str $chunk := end-return();
            @chunks.push($chunk);
            $length := $length + nqp::chars($chunk);
        }
        $statement<end> := $length;

        # A body of just ... is a stub, which a role requires the class
        # doing it to provide.
        my $is-stub := nqp::elems(@code) == 1 && @code[0] eq '...';
        self.attach($/, NQPCode.new(:body(nqp::join("", @chunks)), :raw(nqp::join("", @raw)),
          :source(~$/), :from($/.from), :$is-stub, :statements(@statements),
          :declared(@declared), :$misread, :$hidden-return, :$routine, :$control-returns,
          :%returns));
    }

    method string($/) {
        make ~$/;
    }
}

# Code-gen


# Frontend

sub MAIN(*@files) {
    # Parse everything.
    my @compunits;
    nqp::shift(@files); # first arg is this script
    for @files {
        my $*CURRENT-FILE := $_;
        my $*LINEPOSCACHE;
        my $source := slurp($_);
        @compunits.push(RakuASTParser.parse($source, actions => RakuASTActions).ast);
    }

    # Every type name a declaration may use: the classes and roles declared
    # here plus the natives, bootstrap types and QAST types their
    # signatures name.
    my %*KNOWN-TYPES;
    my %*PACKAGES;
    my %files;
    for @compunits -> $cu {
        for $cu.packages -> $package {
            if %*PACKAGES{$package.name} {
                nqp::die($package.name ~ " is declared twice (" ~ %files{$package.name}
                    ~ " and " ~ $cu.filename ~ ")");
            }
            %*KNOWN-TYPES{$package.name} := 1;
            %*PACKAGES{$package.name} := $package;
            %files{$package.name} := $cu.filename;
        }
    }
    for <Mu Any str int num Str Int Bool Code List Array Hash Scalar Signature ContainerDescriptor QAST::Node QAST::Block QAST::Op QAST::Stmts> {
        %*KNOWN-TYPES{$_} := 1;
    }

    # An unknown type name would otherwise compile to a lookup that yields
    # NQPMu. All names are checked before anything is emitted, so one run
    # reports every unknown name.
    my @*UNKNOWN-TYPES;
    for @compunits {
        my $*CU := $_;
        for $_.packages {
            check-package-types($_);
        }
    }
    if @*UNKNOWN-TYPES {
        nqp::die("Unknown types in RakuAST declarations:\n  " ~ nqp::join("\n  ", @*UNKNOWN-TYPES));
    }

    # Geneate code
    say('# Generated by tools/build/raku-ast-compiler.nqp');
    say('');
    emit-stubs(@compunits);
    say('BEGIN {');
    emit-nqp('src/Raku/ast/rakuast-prologue.nqp');
    for order-packages(@compunits) {
        my $*CU := $_[0];
        emit-package($_[1]);
    }
    emit-nqp('src/Raku/ast/rakuast-epilogue.nqp');
    say('}');
}

# The packages, each paired with its compilation unit, in the order they
# are composed. A role's methods are instantiated for a class when that
# class is composed, so every role comes before every class, a role after
# the roles it does, and a class after its parents.
sub order-packages(@compunits) {
    my @packages;
    my %by-name;
    for @compunits -> $cu {
        for $cu.packages -> $package {
            my @pair := [$cu, $package];
            nqp::push(@packages, @pair);
            %by-name{$package.name} := @pair;
        }
    }
    my @ordered;
    my %done;
    my %visiting;
    sub visit(@pair) {
        my $package := @pair[1];
        my $name := $package.name;
        unless %done{$name} {
            if %visiting{$name} {
                nqp::die("$name is declared in terms of itself (" ~ @pair[0].filename ~ ")");
            }
            %visiting{$name} := 1;
            for $package.is-role ?? $package.roles !! $package.parents {
                visit(%by-name{$_}) if nqp::existskey(%by-name, $_);
            }
            nqp::deletekey(%visiting, $name);
            %done{$name} := 1;
            nqp::push(@ordered, @pair);
        }
    }
    for @packages {
        visit($_) if $_[1].is-role;
    }
    for @packages {
        visit($_);
    }
    @ordered
}

# Code-gen.

sub emit-stubs(@compunits) {
    say('stub RakuAST metaclass Perl6::Metamodel::PackageHOW { ... };');
    say('BEGIN { Perl6::Metamodel::PackageHOW.add_stash(RakuAST); }');
    for @compunits -> $cu {
        for $cu.packages -> $package {
            say('stub ' ~ $package.name ~ ' metaclass Perl6::Metamodel::'
                ~ ($package.is-role ?? 'ParametricRoleHOW' !! 'ClassHOW') ~ ' { ... };');
        }
    }
    say('');
}

sub emit-nqp($nqp-file) {
    say('#line 1 ' ~ $nqp-file);
    say(slurp($nqp-file));
}

sub check-type-name($type, $where) {
    unless %*KNOWN-TYPES{$type} {
        nqp::push(@*UNKNOWN-TYPES, "$type in $where (" ~ $*CU.filename ~ ")");
    }
}

sub check-package-types($package) {
    my $name := $package.name;
    for $package.parents {
        check-type-name($_, "parent of $name");
        if %*PACKAGES{$_} && %*PACKAGES{$_}.is-role {
            nqp::die("$name inherits from $_, which is a role, so it must do it (" ~ $*CU.filename ~ ")");
        }
    }
    my %named;
    for $package.roles {
        check-type-name($_, "role of $name");
        unless %*PACKAGES{$_} && %*PACKAGES{$_}.is-role {
            nqp::die("$name does $_, which is not a role (" ~ $*CU.filename ~ ")");
        }
        if %named{$_} {
            nqp::die("$name does $_ twice (" ~ $*CU.filename ~ ")");
        }
        %named{$_} := 1;
    }
    # A class doing a role an ancestor already does is only noise, and
    # so is a role with attributes that reaches a class a second way. A
    # role without attributes may be reached through more than one
    # parent, as a marker can be.
    for $package.roles -> $role {
        for $package.roles -> $other {
            if $other ne $role && %*PACKAGES{$other} && role-does(%*PACKAGES{$other}, $role) {
                nqp::die("$name does $role, which it already does through $other (" ~ $*CU.filename ~ ")");
            }
        }
    }
    unless $package.is-role {
        my %composers;
        collect-roles($package, %composers);
        my %direct;
        for $package.roles {
            %direct{$_} := 1;
        }
        for sorted_keys(%composers) -> $role {
            my @composers := %composers{$role};
            if nqp::elems(@composers) > 1 {
                if %direct{$role} {
                    nqp::die("$name does $role, which it already does through " ~ @composers[1] ~ " (" ~ $*CU.filename ~ ")");
                }
                if has-attributes(%*PACKAGES{$role}) {
                    nqp::die("$name gets $role from both " ~ @composers[0] ~ " and " ~ @composers[1] ~ " (" ~ $*CU.filename ~ ")");
                }
            }
        }
    }
    for $package.attributes -> $attr {
        check-type-name($attr.type, "attribute " ~ $attr.name ~ " of $name");
    }
    for $package.methods -> $method {
        for $method.parameters {
            check-type-name($_.type || 'Any', "parameter " ~ $_.name ~ " of $name." ~ $method.name);
        }
        if $method.returns {
            check-type-name($method.returns, "return type of $name." ~ $method.name);
        }
        # An attribute is keyed on the package that declares it, for a
        # role's attribute the role, whether the access is in the role
        # or in a class that does it.
        for match(~$method.body, / (<[\w:]>+) \s* ',' \s* <['"]> ('$!' <[\w-]>+) <['"]> /, :global) -> $access {
            my $handle := ~$access[0];
            my $attr := ~$access[1];
            if %*PACKAGES{$handle} && !declares-attribute(%*PACKAGES{$handle}, $attr) {
                nqp::die("$name." ~ $method.name ~ " keys $attr on $handle, which does not declare it (" ~ $*CU.filename ~ ")");
            }
        }
    }
}

# Every role a class composes, directly or through the roles those do,
# keyed to the classes that compose it, for the class and its ancestors.
sub collect-roles($class, %composers) {
    sub composed-by($role) {
        %composers{$role} := [] unless %composers{$role};
        my @composers := %composers{$role};
        my $seen := 0;
        for @composers { $seen := 1 if $_ eq $class.name }
        nqp::push(@composers, $class.name) unless $seen;
        for %*PACKAGES{$role}.roles {
            composed-by($_) if %*PACKAGES{$_};
        }
    }
    for $class.roles {
        composed-by($_) if %*PACKAGES{$_};
    }
    for $class.parents {
        collect-roles(%*PACKAGES{$_}, %composers) if %*PACKAGES{$_};
    }
}

# Whether $role does $name, directly or through the roles it does.
sub role-does($role, $name) {
    for $role.roles {
        return 1 if $_ eq $name
            || %*PACKAGES{$_} && role-does(%*PACKAGES{$_}, $name);
    }
    0
}

sub declares-attribute($package, $name) {
    for $package.attributes {
        return 1 if $_.name eq $name;
    }
    0
}

sub has-attributes($role) {
    return 1 if nqp::elems($role.attributes);
    for $role.roles {
        return 1 if %*PACKAGES{$_} && has-attributes(%*PACKAGES{$_});
    }
    0
}

sub emit-package($package) {
    my $name := $package.name;

    unless $package.is-role {
        for $package.parents || ['Any'] {
            say("    parent($name, $_);");
        }
    }
    for $package.roles {
        say("    does($name, $_);");
    }

    my %need-accessor;
    for $package.attributes -> $attr {
        my $type := $attr.type;
        my $attr-name := $attr.name;
        say("    add-attribute($name, $type, '$attr-name');");
        if $attr.has-accessor {
            %need-accessor{nqp::substr($attr-name, 2)} := $attr;
        }
    }

    for $package.methods -> $method {
        nqp::deletekey(%need-accessor, $method.name);
        emit-method($package, $method);
    }

    for sorted_keys(%need-accessor) -> $method-name {
        my $attr-node := %need-accessor{$method-name};
        my $attr-name := $attr-node.name;
        my $decl-line := $attr-node.line;
        my $op := $attr-node.getattr-op;
        say("#line ", $decl-line, " ", $*CU.filename);
        my $attr-type := $attr-node.type;
        say("    add-method($name, '$method-name', [], anon sub $method-name (\$self) \{",
            " nqp::" ~ $op ~ "(nqp::decont(\$self), $name, '$attr-name')",
            " }" ~ (type-is-native($attr-type) ?? '' !! ", $attr-type") ~ ");");
    }

    say("    compose($name);");
}

sub type-is-native($type) {
    $type eq 'str' || $type eq 'int' || $type eq 'num'
}

# Whether a declared type needs an object type check. Mu and Any accept
# anything, including NQP values, and a native parameter is enforced by the
# unbox when the argument is bound.
sub type-is-checked($type) {
    !($type eq 'Any' || $type eq 'Mu' || type-is-native($type))
}

# The compiler passes VM strings, integers, arrays, hashes and closures
# where user code passes Str, Int, List, Hash and Code objects, and a bare
# adverb, which is a VM integer, where user code passes a Bool. NQP cannot
# know those satisfy the type, so these checks are emitted here. A VM integer
# for a Bool becomes a Bool on entry, and NQPMu for an optional flag becomes
# the Bool type object. An omitted optional of the other five stays
# undefined, which the bodies treat as absent. Every other type goes on the
# NQP parameter itself, and NQP checks it, deconts the argument and gives an
# omitted optional the type object. NQP does not check a slurpy, so the
# elements of a typed slurpy are checked here too.
sub type-is-vm-shaped($type) {
    $type eq 'Str' || $type eq 'Int' || $type eq 'Bool' || $type eq 'Code' || $type eq 'List' || $type eq 'Hash'
}

# The NQP expression that decides whether a value satisfies a declared type,
# for the checks emitted here. For the types type-is-vm-shaped names, an
# undefined value passes only as the type object itself, or as the NQPMu
# that NQP code passes for an absent value. A required flag refuses NQPMu,
# which is also what a name NQP cannot resolve evaluates to.
sub type-check-expr($type, $value, $absent-ok = 1) {
    return "nqp::istype($value, $type)" unless type-is-vm-shaped($type);
    my $concrete :=
      $type eq 'Str'  ?? "nqp::isstr($value) || nqp::istype($value, Str)" !!
      $type eq 'Int'  ?? "nqp::isint($value) || nqp::istype($value, Int)" !!
      $type eq 'Bool' ?? "nqp::isint($value) || nqp::istype($value, Bool)" !!
      $type eq 'Code' ?? "nqp::isinvokable($value)" !!
      $type eq 'List' ?? "nqp::islist($value) || nqp::istype($value, List)" !!
                         "nqp::ishash($value) || nqp::istype($value, Hash)";
    my $absent := $absent-ok ?? "nqp::eqaddr($value, NQPMu) || " !! '';
    "(nqp::isconcrete($value) ?? ($concrete) !! ({$absent}nqp::istype($value, $type)))"
}

# The call that reports a failed check, through the hook NQP uses for the
# parameters it checks itself.
sub type-check-fail($name, $type, $value) {
    "nqp::gethllsym('nqp', 'parameter-type-check-failure')($value, $type, '$name', nqp::curcode())"
}

# Whether a return in the code may leave the method without the check the
# generator puts on it, so the code needs a handler for its returns.
sub may-return-unchecked($code) {
    my $source := $code.source;
    my %words := bare-words($source);
    # A return can be made by hand, or thrown as an exception made elsewhere,
    # as fail, Mu.return, Mu.return-rw and Exception.fail do into their caller.
    return 1 if $source ~~ / throwpayloadlex | throwextype | setextype | CONTROL_RETURN | 'nqp::throw' | 'nqp::rethrow'
      | '.' <[^?&!]>? [return | fail] <!before \w> <!before <[-']> <alpha>> | '.return-rw' /;
    return 1 if nqp::existskey(%words, 'fail');
    return 0 unless nqp::existskey(%words, 'return');
    # The tokenizer may not see or check a return.
    for %words<return> {
        return 1 unless nqp::existskey($code.returns, $code.from + $_);
    }
    # The value of a return in misread code may end elsewhere, and a return of
    # a routine the code declares looks like one of the method. A CATCH, try or
    # nqp::handle may catch a failed check, and a CONTROL may catch a return.
    $code.hidden-return || $code.misread || $code.declares-routine
      || nqp::existskey(%words, 'CATCH') || nqp::existskey(%words, 'CONTROL')
      || nqp::existskey(%words, 'try') || nqp::index($source, 'nqp::handle') >= 0
}

# A checked body that runs as a block cannot be inlined, and code in it that
# looks at its frame or its caller would be off by the frame of the block,
# so the build refuses such code.
sub note-block($package-name, $name, $code) {
    if $code.source ~~ / 'nqp::' [ctx | curcode | callercode | curlexpad | getlexcaller | getlexouter
                                  | usecapture | savecapture | backtrace | throwpayloadlexcaller] / {
        nqp::die("The checked body of $package-name.$name runs as a block, so it cannot look at its frame or its caller (" ~ $*CU.filename ~ ")");
    }
    note("The checked body of $package-name.$name runs as a block, so it cannot be inlined");
}

sub emit-method($package, $method) {
    my $package-name := $package.name;
    my @parameters := $method.parameters;
    my @params-in;
    my @params-desc := ["$package-name, '', 0, 0"];
    my @params-decont;
    my $name := $method.name;
    for @parameters {
        my $param-name := $_.name;
        my $type := $_.type || 'Any';
        my $named := $_.named ?? ':' !! '';
        my $slurpy := $_.slurpy ?? '*' !! '';
        my $opt := $slurpy ?? '' !! ($_.optional ?? '?' !! '!');
        my $checked := type-is-checked($type);
        my $here := $checked && (type-is-vm-shaped($type) || $slurpy);
        # The type goes on the NQP parameter unless it is checked here. A
        # native one makes binding unbox the argument and refuse one that
        # cannot be unboxed.
        my $typed := type-is-native($type) || ($checked && !$here) ?? "$type " !! '';
        if $type eq 'Bool' && ($slurpy || $_.raw) {
            nqp::die("A Bool parameter cannot be slurpy or raw: $param-name of $package-name.$name (" ~ $*CU.filename ~ ")");
        }
        my $raw := $_.raw && $typed ?? ' is raw' !! '';
        my $default := $type eq 'Bool' && !$slurpy && $_.optional ?? ' = Bool' !! '';
        @params-in.push(", $typed$named$slurpy$param-name$opt$raw$default");
        @params-desc.push("$type, '$param-name', " ~ ($_.named ?? '1, ' !! '0, ') ~
            ($_.optional ?? '1' !! '0'));
        unless $_.raw || $typed {
            @params-decont.push("$param-name := nqp::decont($param-name);");
        }
        if $here && $slurpy {
            my $value := $_.named ?? 'nqp::decont(nqp::iterval($_))' !! 'nqp::decont($_)';
            @params-decont.push("for $param-name \{ " ~ type-check-expr($type, $value)
                ~ " || " ~ type-check-fail($param-name, $type, $value) ~ " }");
        }
        elsif $here {
            my $value := $_.raw ?? "nqp::decont($param-name)" !! $param-name;
            @params-decont.push(type-check-expr($type, $value, $type ne 'Bool' || $_.optional)
                ~ " || " ~ type-check-fail($param-name, $type, $value) ~ ";");
        }
        if $type eq 'Bool' {
            @params-decont.push("$param-name := nqp::isint($param-name) ?? (nqp::unbox_i($param-name) ?? TRUE !! FALSE) !! nqp::eqaddr($param-name, NQPMu) ?? Bool !! $param-name;");
        }
    }
    my $params-in := nqp::join("", @params-in);
    my $params-desc := nqp::join(", ", @params-desc);
    my $yada := $method.body.is-stub ?? ', :yada' !! '';

    say("    add-method($package-name, '$name', [$params-desc], anon sub $name (\$SELF_CONT$params-in) \{");
    say("        my \$SELF := nqp::decont(\$SELF_CONT);");
    for @params-decont {
        say("        $_");
    }
    my $returns := $method.returns;
    my $is-stub := $method.body.is-stub;
    if $returns && type-is-checked($returns) && !$is-stub {
        # The build rewrites a #? or # vim: line and #RAKUDO_FLAVOR# in the
        # generated code before NQP compiles it, which could lose the check.
        if $method.body.source ~~ / ^^ ['#?' | '# vim:'] | '#RAKUDO_FLAVOR#' / {
            nqp::die("Method $package-name.$name has a line the build rewrites, so its return type cannot be checked (" ~ $*CU.filename ~ ")");
        }
        # A return would bypass any check but the Bool one, which the
        # generator puts on each return in the body.
        if $returns ne 'Bool' && nqp::existskey(bare-words($method.body.source), 'return') {
            nqp::die("Method $package-name.$name declares a return type, so it cannot use return (" ~ $*CU.filename ~ ")");
        }
        if $returns eq 'Bool' && may-return-unchecked($method.body) {
            # The body runs as a block in a handler for returns, which gives
            # the check the value of any return.
            note-block($package-name, $name, $method.body);
            say("#line " ~ $method.body.line ~ " " ~ $*CU.filename);
            say("        ReturnCheck.bool(nqp::handlepayload(\{" ~ $method.body.raw);
            say("        }(), 'RETURN', nqp::lastexpayload()), '$name')");
            say("    }, $returns);");
            return;
        }
        # A body that cannot be split runs as a block to give it a value, and
        # taking that closure keeps the method from being inlined. The closing
        # paren goes on its own line so a trailing comment cannot swallow it.
        my $code := $method.body;
        # The declarations share the scope of the generated code, so one that
        # reuses a name the generated code declares needs the block.
        my %taken := nqp::hash('$SELF', 1, '$SELF_CONT', 1, '$RESULT', 1);
        %taken{$_.name} := 1 for @parameters;
        my $split := $code.split;
        for $code.declared {
            $split := NQPMu if nqp::existskey(%taken, $_);
        }
        my $before := '';
        my $value;
        my $open;
        my $close;
        if nqp::isconcrete($split) {
            $before := $split[0];
            $value  := $split[1];
            $open   := '(';
            $close  := ')';
        }
        else {
            note-block($package-name, $name, $method.body);
            $value := ~$code;
            $open  := '{';
            $close := '}()';
        }
        say("#line " ~ $code.line ~ " " ~ $*CU.filename);
        if $returns eq 'Bool' && nqp::isconcrete($split) && $value ~~ /^ \s* [TRUE | FALSE] \s* $/ {
            # A literal True or False needs no check.
            say("        $before$value");
        }
        elsif $returns eq 'Bool' {
            say("        {$before}ReturnCheck.bool($open$value");
            say("        $close, '$name')");
        }
        else {
            say("        {$before}my \$RESULT := $open$value");
            say("        $close;");
            say("        " ~ type-check-expr($returns, '$RESULT')
                ~ " || ReturnCheck.failure(\$RESULT, $returns, '$name');");
            say("        \$RESULT");
        }
        say("    }, $returns);");
    }
    else {
        if $returns && !type-is-checked($returns) {
            nqp::die("Method $package-name.$name declares a return type the generator does not check (" ~ $*CU.filename ~ ")");
        }
        say("#line " ~ $method.body.line ~ " " ~ $*CU.filename);
        say("        " ~ ($is-stub ?? "nqp::die('Stub code executed: $name of $package-name')" !! $method.body));
        say("    }" ~ ($returns ?? ", $returns" !! '') ~ "$yada);");
    }
}
