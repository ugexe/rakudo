#-------------------------------------------------------------------------------
# Base class for all package related objects, and for the -package- statement
# itself

class RakuAST::Package
  is RakuAST::PackageInstaller
  is RakuAST::StubbyMeta
  is RakuAST::Term
  is RakuAST::IMPL::ImmediateBlockUser
  is RakuAST::Declaration
  is RakuAST::AttachTarget
  is RakuAST::ParseTime
  is RakuAST::BeginTime
  is RakuAST::TraitTarget
  is RakuAST::ImplicitBlockSemanticsProvider
  is RakuAST::LexicalScope
  is RakuAST::Lookup
  is RakuAST::Doc::DeclaratorTarget
{
    has RakuAST::Name $.name;
    has RakuAST::Code $.body;
    has Mu            $.attribute-type;
    has Mu            $.how;
    has Str           $.repr;
    has Bool          $.augmented;

    has Mu   $!block-semantics-applied;
    has Bool $.is-stub;
    has Bool $!stub-defused;
    has Bool $.is-require-stub;
    has Bool $!installed;

    has Mu $!compose-exception;

    # Accessors and POPULATE built synthetically at compose time by
    # PRODUCE-ACCESSORS-POPULATE. Their code objects are attached as methods,
    # but the blocks must also be emitted into the package body so they become
    # real bytecode (and survive setting precompilation) rather than
    # lazily-compiled stubs. We keep the method nodes here and form their QAST
    # in IMPL-EXPR-QAST: by then the meta-object is produced and cached, so
    # forming the block cannot re-enter meta-object production.
    has Mu $!synthetic-methods;

    # Enclosing parametric role captured at BEGIN-time so the package can
    # register itself as an instantiation lexical on that role if it ends up
    # archetypally generic after composition.
    has Mu $!generics-pad;

    method new(          str :$scope,
               RakuAST::Name :$name,
          RakuAST::Signature :$parameterization,
                        List :$traits,
               RakuAST::Code :$body,
                          Mu :$attribute-type,
                          Mu :$how,
                         Str :$repr,
                        Bool :$augmented,
                        Bool :$is-require-stub,
    RakuAST::Doc::Declarator :$WHY
    ) {
        my $obj := nqp::create(self);
        nqp::bindattr_s($obj, RakuAST::Declaration, '$!scope', $scope);
        nqp::bindattr($obj, RakuAST::Package, '$!name', $name // RakuAST::Name);
        nqp::bindattr($obj, RakuAST::Package, '$!attribute-type',
          nqp::eqaddr($attribute-type, NQPMu) ?? Attribute !! $attribute-type);
        nqp::bindattr($obj, RakuAST::Package, '$!how',
          nqp::eqaddr($how,NQPMu) ?? $obj.default-how !! $how);
        nqp::bindattr($obj, RakuAST::Package, '$!repr', $repr // Str);
        nqp::bindattr($obj, RakuAST::Package, '$!augmented',$augmented // False);
        nqp::bindattr($obj, RakuAST::Package, '$!is-require-stub',$is-require-stub // False);

        $obj.set-traits($traits) if $traits;
        $obj.replace-body($body, $parameterization);
        $obj.set-WHY($WHY);

        nqp::bindattr($obj, RakuAST::Package, '$!is-stub', False);
        nqp::bindattr($obj, RakuAST::Package, '$!stub-defused', False);

        $obj
    }

    # Informational methods
    method declarator()  { "package"             }
    method dba()         { "package"             }
    method default-how() { Metamodel::PackageHOW }

    method allowed-scopes() { self.IMPL-WRAP-LIST(['anon', 'augment', 'my', 'our', 'unit']) }
    method default-scope()       { 'our' }
    method can-have-methods()    { False }
    method can-have-attributes() { False }
    method IMPL-CAN-INTERPRET()  { True }

    method parameterization() { Mu }

    method creates-block() { False }

    # While a package may be declared `my`, its installation semantics are
    # more complex, and thus handled as a BEGIN-time effect. (For example,
    # `my Foo::Bar { }` should not create a lexical symbol Foo::Bar.)
    method is-simple-lexical-declaration() { False }

    # Setter methods
    method replace-body(RakuAST::Code $body, RakuAST::Signature $signature) {
        nqp::bindattr(self, RakuAST::Package, '$!body',
          $body // RakuAST::Block.new);
        Nil
    }

    method set-repr(Str $repr) {
        nqp::bindattr(self, RakuAST::Package, '$!repr', $repr);
    }

    method set-is-stub(Bool $is-stub) {
        nqp::bindattr(self, RakuAST::Package, '$!is-stub', $is-stub ?? True !! False);
    }

    method defuse-stub() {
        nqp::bindattr(self, RakuAST::Package, '$!stub-defused', True);
    }

    method PERFORM-PARSE(RakuAST::Resolver $resolver, RakuAST::IMPL::QASTContext $context) {
        if $!augmented {
            if self.name {
                my $resolved := $resolver.resolve-name(self.name);
                if $resolved {
                    unless $resolved.compile-time-value.HOW.archetypes.augmentable {
                        self.add-sorry:
                            $resolver.build-exception: 'X::Syntax::Augment::Illegal',
                                :package(self.name.canonicalize);
                        $resolver.add-node-with-check-time-problems(self);
                    }
                    self.set-resolution($resolved);
                }
                else {
                    self.add-sorry:
                        $resolver.build-exception: 'X::Augment::NoSuchType',
                            :package(self.name.canonicalize), :package-kind(self.declarator);
                    $resolver.add-node-with-check-time-problems(self);
                }
            }
            else {
                self.add-sorry:
                    $resolver.build-exception: 'X::Anon::Augment',
                        :package-kind(self.declarator);
                $resolver.add-node-with-check-time-problems(self);
            }
        }
        elsif $!name {
            my $full-name := self.IMPL-FULL-NAME($resolver);
            # First try to find it using the fully qualified name
            my $resolved := $resolver.resolve-name-constant($full-name, :current-scope-only(self.scope eq 'my'));
            # If not found try locally using just the declared name
            $resolved := $resolver.resolve-name-constant($!name, :current-scope-only)
                unless nqp::isconcrete($resolved);
            if $resolved {
                my $meta := $resolved.compile-time-value;
                my $how  := $meta.HOW;
                if $how.HOW.name($how) ne 'Perl6::Metamodel::PackageHOW' {
                    self.defuse-stub;
                    $resolved.package.defuse-stub if nqp::istype($resolved, RakuAST::Declaration::LexicalPackage);
                    # Note: this won't find role groups as they are not Composing. That's ok as
                    # we do not need to re-use the stub's meta object for roles.
                    if nqp::can($how, 'is_composed') && !$how.is_composed($meta) {
                        self.set-resolution($resolved);
                    }
                }
            }
        }

    }

    method attach-target-names() { ['package', 'also'] }

    method IMPL-GENERATE-LEXICAL-DECLARATION(RakuAST::Name $name, Mu $type-object) {
        $type-object := self.stubbed-meta-object if nqp::eqaddr($type-object, Mu);
        my $package := RakuAST::Declaration::LexicalPackage.new:
            :lexical-name($name),
            :compile-time-value($type-object),
            :package(self);
        $package
    }

    method IMPL-FULL-NAME($resolver) {
        my $name := $!name;
        my $current := $resolver.current-package;
        my $full-name := nqp::eqaddr($current,$resolver.get-global)
            ?? $name.is-global-lookup ?? $name.without-first-part !! $name
            !! $name.qualified-with(
                RakuAST::Name.from-identifier-parts(
                    |nqp::split('::', $current.HOW.name($current))
                )
            );
    }

    method ensure-installed(RakuAST::Resolver $resolver, RakuAST::IMPL::QASTContext $context) {
        unless $!installed {
            nqp::bindattr(self, RakuAST::Package, '$!installed', True);

            # Install the symbol.
            my str $scope := self.scope;
            $scope := 'our' if $scope eq 'unit';
            my $name := $!name;
            if $name && $name.is-installable {
                my $type-object := self.stubbed-meta-object(:$resolver, :$context);
                my $full-name := self.IMPL-FULL-NAME($resolver);
                $type-object.HOW.set_name(
                    $type-object,
                    $full-name.canonicalize(:colonpairs(0))
                );

                # Update the Stash's name, too.
                nqp::bindattr_s($type-object.WHO, Stash, '$!longname',
                  $type-object.HOW.name($type-object));

                self.install-in-scope($resolver, $scope, $name, $full-name);
            }

            self.install-extra-declarations($resolver);
        }
    }

    method PERFORM-BEGIN(RakuAST::Resolver $resolver, RakuAST::IMPL::QASTContext $context) {
        $!body.to-begin-time($resolver, $context); # In case it's the default generated by replace-body

        self.ensure-installed($resolver, $context);

        # Apply any traits
        self.apply-traits($resolver, $context, self);

        # Remember the enclosing parametric role, if any, so that we can
        # register an instantiation lexical with it once the type is composed.
        # We cannot add to the role's body directly here: for the outer role,
        # $ast.replace-body(...) in Raku/Actions.nqp has not yet run, so
        # self.body still refers to the stub body that will be discarded. The
        # Role collects the request and applies it during additional-body-lexicals
        # (which runs after the body replacement).
        unless nqp::istype(self, RakuAST::Role) {
            my $pad := $resolver.find-attach-target('generics-pad');
            nqp::bindattr(self, RakuAST::Package, '$!generics-pad', $pad) if $pad;
        }
    }

    # Shared archetype filter used by both the declaration side
    # (IMPL-MAYBE-REGISTER-INSTANTIATION-LEXICAL below) and the reference
    # side (RakuAST::Type::Simple.IMPL-EXPR-QAST). A type is eligible for
    # `!INS_OF_<fullname>` registration exactly when its archetypes are
    # generic, nominal, and non-parametric. Mirrors the filter traditional
    # grammar uses in src/Perl6/Actions.nqp package_def.
    method IMPL-IS-INSTANTIATION-REGISTRABLE(Mu $type) {
        my $how := $type.HOW;
        return 0 unless nqp::can($how, 'archetypes');
        my $archetypes := $how.archetypes($type);
        $archetypes.generic && $archetypes.nominal
          && !(nqp::can($archetypes, 'parametric') && $archetypes.parametric)
            ?? 1
            !! 0
    }

    # After the package has been composed, if the type ended up archetypally
    # generic/nominal/non-parametric, declare a `!INS_OF_<fullname>` lexical
    # on the enclosing role and register it on the role's
    # instantiation-lexicals list so resolve_instantiations rebinds it per
    # specialization. Called from the base IMPL-COMPOSE, so any
    # RakuAST::Package subclass gets the behavior without its
    # IMPL-COMPOSE override needing to remember.
    method IMPL-MAYBE-REGISTER-INSTANTIATION-LEXICAL() {
        return Nil unless $!generics-pad;
        my $type := self.stubbed-meta-object;
        return Nil unless RakuAST::Package.IMPL-IS-INSTANTIATION-REGISTRABLE($type);
        my str $ins-name := '!INS_OF_' ~ $type.HOW.name($type);
        my $decl := RakuAST::VarDeclaration::Implicit::Constant.new(
            :name($ins-name), :value($type), :scope('my')
        );
        $!generics-pad.IMPL-QUEUE-INSTANTIATION-LEXICAL($decl);
        Nil
    }

    method PERFORM-CHECK(RakuAST::Resolver $resolver, RakuAST::IMPL::QASTContext $context) {
        my $name := $!name;
        if $name && !$name.is-empty && $!name.has-colonpairs {
            my $colonpairs := $!name.IMPL-UNWRAP-LIST($!name.colonpairs);
            for $colonpairs {
                my $key := $_.key;
                if $key ne 'ver' && $key ne 'api' && $key ne 'auth' {
                    self.add-sorry:
                        $resolver.build-exception: 'X::Syntax::' ~ ($!augmented ?? 'Augment' !! 'Type') ~ '::Adverb',
                            adverb => $key
                }
                elsif $!augmented && $key eq 'auth' {
                    self.add-sorry:
                        $resolver.build-exception: 'X::Syntax::Augment::Adverb',
                            adverb => $key
                }
            }
        }

        if $!compose-exception {
            self.add-sorry: $resolver.convert-exception($!compose-exception)
        }

        self.check-scope($resolver, self.declarator);

        self.add-trait-sorries;

        if $!is-stub && !$!stub-defused && !$!is-require-stub
            && !self.stubbed-meta-object.HOW.is_composed(self.stubbed-meta-object)
            && !nqp::istype(self, RakuAST::Role) # No idea why roles are excempt
        { # Should be replaced by now
            self.add-sorry:
                $resolver.build-exception: 'X::Package::Stubbed',
                    packages => [$!name.canonicalize];
        }

        if self.is-resolved && $!repr {
            self.add-sorry: $resolver.build-exception: 'X::TooLateForREPR', type => self.stubbed-meta-object;
        }

        nqp::findmethod(RakuAST::LexicalScope, 'PERFORM-CHECK')(self, $resolver, $context);
    }

    method install-extra-declarations(RakuAST::Resolver $resolver) {
        Nil
    }

    # Need to install the package somewhere
    method install-in-scope(RakuAST::Resolver $resolver, str $scope, RakuAST::Name $name, RakuAST::Name $full-name) {
        self.IMPL-INSTALL-PACKAGE(
          $resolver, $scope, $name, $resolver.current-package, :meta-object(Mu)
        ) if $scope eq 'my' || $scope eq 'our';
    }

    # Declare the lexicals for this type of package
    method declare-lexicals(RakuAST::Resolver $resolver, RakuAST::IMPL::QASTContext $context) {
        self.meta-object-as-lexicals($resolver, 'PACKAGE', :$context);
        self.meta-object-as-lexicals($resolver, 'CLASS', :$context)
          unless self.declarator eq 'package';
    }

    # Helper method to create $?CLASS ::?CLASS and similar
    method meta-object-as-lexicals(RakuAST::Resolver $resolver, str $root, :$context) {
        for '$?', '::?' {
            $resolver.declare-lexical(self.implicit-constant($_ ~ $root, :$resolver, :$context));
        }
    }

    # Helper method to create $?CLASS ::?CLASS and similar
    method meta-object-as-body-lexicals(str $root, :$resolver, :$context) {
        my $body := self.body;
        for '$?', '::?' {
            $body.add-generated-lexical-declaration(
              self.implicit-constant($_ ~ $root, :$resolver, :$context)
            )
        }
    }

    # Helper method to define an implicit constant for the meta object
    method implicit-constant(str $name, :$resolver, :$context) {
        RakuAST::VarDeclaration::Implicit::Constant.new(
          :$name, :value(self.stubbed-meta-object(:$resolver, :$context))
        )
    }

    method PRODUCE-STUBBED-META-OBJECT(:$resolver, :$context) {
        if self.is-resolved {
            self.resolution.compile-time-value;
        }
        elsif $!augmented && nqp::istype(self, RakuAST::Role) {
            Nil # Will report the error a little later
        }
        else {
            # Create the type object and return it; this stubs the type.
            # Colonpair values evaluate against $resolver/$context when
            # present, so callers in the compile pipeline must pass both.
            # Packages without colonpairs work fine without context.
            my %options;
            %options<name> := $!name.canonicalize if $!name && $!name.is-installable;
            %options<repr> := $!repr if $!repr;
            if $!name {
                my @colonpairs := $!name.IMPL-UNWRAP-LIST($!name.colonpairs);
                if nqp::elems(@colonpairs) {
                    nqp::die("RakuAST::Package.stubbed-meta-object: package with colonpairs `"
                      ~ $!name.canonicalize
                      ~ "' requires resolver and context, but caller did not pass them")
                        unless nqp::isconcrete($resolver) && nqp::isconcrete($context);
                    my $Failure := $resolver.type-from-setting('Failure');
                    for @colonpairs {
                        my $key := $_.key;
                        my $value := $_.IMPL-EVAL-COLONPAIR-VALUE-OR-RETHROW(
                            $resolver, $context, $Failure);
                        next if $key eq 'auth' && nqp::eqaddr($value, Nil);
                        $value := Version.new($value) if $key eq 'ver' || $key eq 'api';
                        %options{$key} := $value;
                    }
                }
            }
            my $meta-object := $!how.new_type(|%options);
            if $!is-require-stub {
                my $cont := nqp::create(Scalar);
                nqp::bindattr($cont, Scalar, '$!value', $meta-object);
                my $cont-desc := ContainerDescriptor::Untyped.new(:of(Mu), :default(Mu), :!dynamic);
                nqp::bindattr($cont, Scalar, '$!descriptor', $cont-desc);
                $meta-object := $cont;
            }
            $meta-object
        }
    }

    method PRODUCE-META-OBJECT(:$resolver, :$context) {
        my $type := self.stubbed-meta-object(:$resolver, :$context);
        self.IMPL-COMPOSE-TYPE($type);
        CATCH {
            nqp::bindattr(self, RakuAST::Package, '$!compose-exception', $_)
        }
        $type
    }

    # Compose $type via its HOW
    method IMPL-COMPOSE-TYPE(Mu $type) {
        $type.HOW.compose($type);
    }

    method apply-implicit-block-semantics(:$resolver, :$context) {
        unless $!block-semantics-applied {
            self.meta-object-as-body-lexicals('PACKAGE', :$resolver, :$context);
            self.additional-body-lexicals(:$resolver, :$context);

            nqp::bindattr(self,RakuAST::Package,'$!block-semantics-applied',1);
        }
    }

    # Add any additional lexicals to the body
    method additional-body-lexicals(:$resolver, :$context) {
        self.meta-object-as-body-lexicals('CLASS', :$resolver, :$context)
          unless self.declarator eq 'package';
    }

    method IMPL-EXPR-QAST(RakuAST::IMPL::QASTContext $context) {
        my $type-object := self.meta-object;
        $context.ensure-sc($type-object);
        my $body := $!body.IMPL-QAST-BLOCK($context, :blocktype<immediate>);
        # Emit the QAST for any synthetic accessor / POPULATE methods into the
        # body, so they become real bytecode rather than lazily-compiled stubs.
        # Formed here (not at compose time) so the meta-object is already cached
        # and forming the block cannot re-enter meta-object production.
        if nqp::isconcrete($!synthetic-methods) {
            for $!synthetic-methods {
                $body[0].push($_.IMPL-QAST-BLOCK($context));
            }
        }
        my $result := QAST::Stmts.new(
            $body,
            QAST::WVal.new( :value($type-object) )
        );
        $result
    }

    method IMPL-INTERPRET(RakuAST::IMPL::InterpContext $ctx) {
        self.compile-time-value
    }

    method IMPL-COMPOSE(RakuAST::Resolver $resolver, RakuAST::IMPL::QASTContext $context) {
        # $resolver/$context are mandatory here: this is the first
        # meta-object access for the package and fills the cache. A bare
        # call would cache the degraded compose and starve later callers
        # of accessor QAST.
        self.meta-object(:$resolver, :$context);
        self.IMPL-MAYBE-REGISTER-INSTANTIATION-LEXICAL;
    }

    method visit-children(Code $visitor) {
        $visitor($!name) if $!name;
        self.visit-traits($visitor);
        $visitor($!body);
        $visitor(self.WHY) if self.WHY;
    }

    method needs-sink-call() { False }
}

#-------------------------------------------------------------------------------
# Role for handling package types that can have methods and attributes
# attached to it

class RakuAST::Package::Attachable
  is RakuAST::Package
{
    # Methods and attributes are not directly added, but rather thorugh the
    # attach target mechanism. Attribute usages are also attached for checking
    # after compose time.
    has Mu $.attached-methods;
    has Mu $.attached-attributes;
    has Mu $!attached-attribute-usages;
    has Mu $!role-group;

    method new(          str :$scope,
               RakuAST::Name :$name,
          RakuAST::Signature :$parameterization,
                        List :$traits,
               RakuAST::Code :$body,
                          Mu :$attribute-type,
                          Mu :$how,
                         Str :$repr,
                        Bool :$augmented,
    RakuAST::Doc::Declarator :$WHY
    ) {
        my $obj := nqp::create(self);
        nqp::bindattr_s($obj, RakuAST::Declaration, '$!scope', $scope);
        nqp::bindattr($obj, RakuAST::Package, '$!name', $name // RakuAST::Name);
        nqp::bindattr($obj, RakuAST::Package, '$!attribute-type',
          nqp::eqaddr($attribute-type, NQPMu) ?? Attribute !! $attribute-type);
        nqp::bindattr($obj, RakuAST::Package, '$!how',
          nqp::eqaddr($how,NQPMu) ?? $obj.default-how !! $how);
        nqp::bindattr($obj, RakuAST::Package, '$!repr', $repr // Str);
        nqp::bindattr($obj, RakuAST::Package, '$!augmented',$augmented // False);

        $obj.set-traits($traits) if $traits;
        $obj.replace-body($body, $parameterization);
        $obj.set-WHY($WHY);

        nqp::bindattr($obj, RakuAST::Package, '$!is-stub', False);

        # Set up internal defaults
        nqp::bindattr($obj, RakuAST::Package::Attachable,
          '$!attached-methods', []);
        nqp::bindattr($obj, RakuAST::Package::Attachable,
          '$!attached-attributes', []);
        nqp::bindattr($obj, RakuAST::Package::Attachable,
          '$!attached-attribute-usages', {});
        nqp::bindattr($obj, RakuAST::Package::Attachable,
          '$!role-group', Mu);

        $obj
    }

    method can-have-methods()    { True }
    method can-have-attributes() { True }

    method ATTACH-METHOD(RakuAST::Method $method) {
        nqp::push($!attached-methods, $method);
        Nil
    }

    # TODO also list-y declarations
    method ATTACH-ATTRIBUTE(RakuAST::VarDeclaration::Simple $attribute) {
        nqp::push($!attached-attributes, $attribute);
        my $type := self.stubbed-meta-object;
        $type.HOW.add_attribute($type, $attribute.meta-object);
        Nil
    }

    method ATTACH-ATTRIBUTE-USAGE(RakuAST::Var::Attribute $attribute) {
        nqp::bindkey($!attached-attribute-usages, $attribute.name, $attribute);
        Nil
    }

    # Add methods and attributes to meta object
    method PRODUCE-META-ATTACHABLES($type, $how) {
        for $!attached-methods {
            my str $name    := $_.name.canonicalize;
            my $meta-object := $_.meta-object;

            if nqp::istype($_, RakuAST::Method) && $_.private {
                $how.add_private_method($type, $name, $meta-object);
            }
            elsif nqp::istype($_, RakuAST::Method) && $_.meta {
                $how.add_meta_method($type, $name, $meta-object);
            }
            elsif $_.multiness eq 'multi' {
                $how.add_multi_method($type, $name, $meta-object);
            }
            else {
                $how.add_method($type, $name, $meta-object);
            }
        }

        for $!attached-attributes {

            # attribute defined means we don't need to check it anymore
            nqp::deletekey($!attached-attribute-usages, $_.name);
        }
    }
}

#-------------------------------------------------------------------------------
# Specific logic to handle roles

class RakuAST::Role
  is RakuAST::Package::Attachable
{
    has Array $.instantiation-lexicals;
    has Array $!pending-ins-lexicals;
    has RakuAST::LexicalFixup $!fixup;

    method declarator()  { "role"                       }
    method default-how() { Metamodel::ParametricRoleHOW }
    method attach-target-names() { self.IMPL-WRAP-LIST(['package', 'also', 'generics-pad']) }

    # Called twice: once from Package.new with no real body, then again
    # from package-def with the parsed body. Only wrap the body when we
    # have one, since the wrapping calls stubbed-meta-object and that
    # memoizes; running it before parser state is bound caches a wrong
    # meta-object.
    method replace-body(RakuAST::Code $role-body, RakuAST::Signature $signature) {
        # The body of a role is internally a Sub that has the parameterization
        # of the role as the signature.  This allows a role to be selected
        # using ordinary dispatch semantics.  The statement list gets a return
        # value added, so that the role's meta-object and lexpad are returned.
        nqp::bindattr(self, RakuAST::Role, '$!fixup', RakuAST::LexicalFixup.new) unless $!fixup;
        unless nqp::defined($!instantiation-lexicals) {
            nqp::bindattr(self, RakuAST::Role, '$!instantiation-lexicals', []);
        }

        unless $signature {
            $signature := $role-body ?? $role-body.signature !! RakuAST::Signature.new;
        }
        my $body-node := $role-body // RakuAST::RoleBody.new(:$signature);
        $body-node.set-fixup($!fixup);
        $body-node.replace-name(self.name);
        $body-node.replace-signature($signature);

        if $role-body {
            for $signature.IMPL-UNWRAP-LIST($signature.parameters) {
                $_.set-owner($role-body);
            }

            my $body := $role-body.body;
            my $resolve-instantiations;
            $body.statement-list.unshift-statement(
                $resolve-instantiations := RakuAST::Role::ResolveInstantiations.new(
                    $!instantiation-lexicals)
            );

            $body.statement-list.add-statement(
              RakuAST::Statement::Expression.new(
                expression => RakuAST::Nqp.new('list',
                  RakuAST::Declaration::ResolvedConstant.new(
                    compile-time-value => self.stubbed-meta-object
                  ),
                  nqp::elems($!instantiation-lexicals)
                      ?? RakuAST::Role::TypeEnvVar.new($resolve-instantiations.type-env-var)
                      !! RakuAST::Nqp.new('curlexpad')
                )
              )
            );
        }

        nqp::bindattr(self, RakuAST::Package, '$!body', $body-node);
        Nil
    }

    method parameterization() { self.body.signature }

    method declare-lexicals(RakuAST::Resolver $resolver, RakuAST::IMPL::QASTContext $context) {
        self.meta-object-as-lexicals($resolver, 'PACKAGE', :$context);
        self.meta-object-as-lexicals($resolver, 'ROLE', :$context);

        for '$?CLASS', '::?CLASS' {
            $resolver.declare-lexical(
              RakuAST::Type::Capture.new(RakuAST::Name.from-identifier($_)).to-begin-time($resolver, $context)
            );
        }
    }

    method install-in-scope(RakuAST::Resolver $resolver, str $scope, RakuAST::Name $name, RakuAST::Name $full-name) {
        # Find an appropriate existing role group
        my $group := $resolver.resolve-name-constant($full-name, :current-scope-only(self.scope eq 'my'));
        if $group && !nqp::istype($group.compile-time-value.HOW, Perl6::Metamodel::PackageHOW) {
            $group := $group.compile-time-value;
            $resolver.panic(
                $resolver.build-exception('X::Redeclaration', :symbol(self.name.canonicalize))
            ) unless nqp::can($group.HOW, 'add_possibility');
        }

        # No existing one found - create a role group
        else {
            my $group-name := $full-name.canonicalize(:colonpairs(0));
            $group := Perl6::Metamodel::ParametricRoleGroupHOW.new_type(
              :name($group-name), :repr(self.repr)
            );
            self.IMPL-INSTALL-PACKAGE(
              $resolver, $scope, $name, $resolver.current-package,
              :meta-object($group),
            );
        }
        # Add ourselves to the role group
        my $type-object := self.stubbed-meta-object;
        $type-object.HOW.set_group($type-object, $group);
        nqp::bindattr(self,RakuAST::Package::Attachable,'$!role-group',$group);
    }

    method install-extra-declarations(RakuAST::Resolver $resolver) {
        # We might have declarations from our signature. Need to push them on
        # to the outer scope as the role itself won't generate code for its
        # declarations.
        for self.IMPL-UNWRAP-LIST(self.generated-lexical-declarations) {
            $resolver.current-scope.add-generated-lexical-declaration($_);
        }
        $resolver.current-scope.add-generated-lexical-declaration(self.body.fixup) if self.body.fixup;
    }

    method additional-body-lexicals(:$resolver, :$context) {
        self.meta-object-as-body-lexicals('ROLE', :$resolver, :$context);

        self.body.add-generated-lexical-declaration(
            # $?CONCRETIZATION is actually a run-time symbol because it's being initialized when role is
            # getting specialized. But we make it ?-twigilled to stay in line with $?ROLE, $?CLASS, etc.,
            # and to reduce pollution of lexcial namespace.
            RakuAST::VarDeclaration::Implicit::RoleConcretization.new(:name('$?CONCRETIZATION'), :scope('my'))
        );

        # Flush any instantiation-lexicals that nested generic packages
        # queued during their own compose. The role's body has been
        # replaced by now (in Raku/Actions.nqp), so adding the lexical
        # declarations here puts them on the body that will actually be
        # emitted, and registering them on $!instantiation-lexicals gets
        # them rebound by resolve_instantiations per specialization.
        if $!pending-ins-lexicals {
            for $!pending-ins-lexicals {
                self.body.add-generated-lexical-declaration($_);
                self.IMPL-ADD-GENERIC-LEXICAL($_);
            }
            nqp::bindattr(self, RakuAST::Role, '$!pending-ins-lexicals', Array);
        }
    }

    # Queue an instantiation-lexical declaration requested by a nested
    # generic-typed package that is being composed before our body has
    # been replaced. additional-body-lexicals (called during the role's
    # apply-implicit-block-semantics) drains the queue. Guards against
    # double-registration by name in case the same package enters
    # IMPL-COMPOSE more than once, which should not happen in practice
    # but would otherwise leak duplicate entries into
    # $!instantiation-lexicals and duplicate lexical decls into the
    # role body.
    method IMPL-QUEUE-INSTANTIATION-LEXICAL(Mu $decl) {
        unless nqp::defined($!pending-ins-lexicals) {
            nqp::bindattr(self, RakuAST::Role, '$!pending-ins-lexicals', []);
        }
        my str $name := $decl.name;
        for $!pending-ins-lexicals {
            return Nil if $_.name eq $name;
        }
        if $!instantiation-lexicals {
            for $!instantiation-lexicals {
                return Nil if $_.name eq $name;
            }
        }
        nqp::push($!pending-ins-lexicals, $decl);
        Nil
    }

    method PRODUCE-META-OBJECT(:$resolver, :$context) {
        my $type := self.stubbed-meta-object(:$resolver, :$context);

        unless self.is-stub {
            my $how := $type.HOW;
            self.PRODUCE-META-ATTACHABLES($type, $how);
            $how.set_body_block($type, self.body.meta-object(:$resolver, :$context));
            self.IMPL-COMPOSE-TYPE($type);
            CATCH {
                nqp::bindattr(self, RakuAST::Package, '$!compose-exception', $_)
            }
            my $group :=
              nqp::getattr(self, RakuAST::Package::Attachable, '$!role-group');
            $group.HOW.add_possibility($group, $type) unless $group =:= Mu;
        }

        $type
    }

    method IMPL-ADD-GENERIC-LEXICAL(Mu $lexical) {
        unless nqp::defined($!instantiation-lexicals) {
            nqp::bindattr(self, RakuAST::Role, '$!instantiation-lexicals', []);
        }
        nqp::push($!instantiation-lexicals, $lexical);
    }

    method IMPL-COMPOSE(RakuAST::Resolver $resolver, RakuAST::IMPL::QASTContext $context) {
        # See Package.IMPL-COMPOSE; $resolver/$context are mandatory and
        # the first meta-object access fills the cache.
        self.meta-object(:$resolver, :$context);
        self.body.IMPL-FINISH-ROLE-BODY($context);
    }
}

class RakuAST::Role::ResolveInstantiations
  is RakuAST::Statement
{
    has List $.instantiation-lexicals;
    has str $.type-env-var;

    method new(@instantiation-lexicals) {
        my $obj := nqp::create(self);
        nqp::bindattr($obj, RakuAST::Role::ResolveInstantiations, '$!instantiation-lexicals', @instantiation-lexicals);
        nqp::bindattr_s($obj, RakuAST::Role::ResolveInstantiations, '$!type-env-var', QAST::Node.unique('__typeenv_'));
        $obj
    }

    method IMPL-TO-QAST(RakuAST::IMPL::QASTContext $context) {
        if nqp::elems($!instantiation-lexicals) {
            my @names;
            for $!instantiation-lexicals {
                nqp::push(@names, $_.lexical-name);
            }
            $context.ensure-sc(@names);
            QAST::Op.new( :op<bind>,
                QAST::Var.new( :name($!type-env-var), :scope<local>, :decl<var> ),
                QAST::Op.new( :op<callmethod>, :name<resolve_instantiations>,
                    QAST::Op.new( :op<how>,
                        QAST::Var.new( :name<::?ROLE>, :scope<lexical> ) ),
                    QAST::Var.new( :name<::?ROLE>, :scope<lexical> ),
                    QAST::Op.new( :op<curlexpad> ),
                    QAST::WVal.new( :value(@names) )
                ))
        }
        else {
            QAST::Op.new(:op<null>)
        }
    }
}

class RakuAST::Role::TypeEnvVar
    is RakuAST::Expression
{
    has str $.type-env-var;

    method new(str $type-env-var) {
        my $obj := nqp::create(self);
        nqp::bindattr_s($obj, RakuAST::Role::TypeEnvVar, '$!type-env-var', $type-env-var);
        $obj
    }

    method IMPL-EXPR-QAST(RakuAST::IMPL::QASTContext $context) {
      QAST::Var.new( :name($!type-env-var), :scope<local> )
    }
}

#-------------------------------------------------------------------------------
# Specific logic to handle classes and grammars

class RakuAST::Class
  is RakuAST::Package::Attachable
{
    method declarator()  { "class"             }
    method default-how() { Metamodel::ClassHOW }

    method PRODUCE-META-OBJECT(:$resolver, :$context) {
        my $type := self.stubbed-meta-object(:$resolver, :$context);

        # Seed the cache with the stub before building the synthetic methods:
        # bringing them to begin time resolves references back to this type,
        # which would otherwise re-enter meta-object production and compose
        # the attached methods twice.
        self.IMPL-SEED-META-OBJECT($type);

        # Build the accessors and attach them before the attached methods are
        # added to the meta object, so they are composed in exactly once. Needs
        # the resolver/context to drive the synthetic AST to begin time;
        # without them we fall back to the MOP's runtime closure accessors.
        self.PRODUCE-ACCESSORS($resolver, $context)
          if nqp::isconcrete($resolver) && nqp::isconcrete($context);

        self.PRODUCE-META-ATTACHABLES($type, $type.HOW);

        {
            self.IMPL-COMPOSE-TYPE($type);
            CATCH {
                nqp::bindattr(self, RakuAST::Package, '$!compose-exception', $_)
            }
        }

        # Build the POPULATE submethod once the type is composed, so its MRO
        # (and any applied roles) are available.
        self.PRODUCE-POPULATE($resolver, $context)
          if nqp::isconcrete($resolver) && nqp::isconcrete($context);

        $type
    }

    # Produce any accessor methods as well as the POPULATE method from
    # the attributes that are known at this time, and add them as methods
    # for later processing
    method PRODUCE-ACCESSORS(RakuAST::Resolver $resolver, RakuAST::IMPL::QASTContext $context) {

        # Nothing to generate for a HOW that cannot take methods (e.g. a
        # native reference type).
        my $type := self.stubbed-meta-object;
        my $how  := $type.HOW;
        return Nil unless nqp::can($how,'add_method');

        # Make the resolver aware of the invocant class.
        $resolver.push-scope(self.body);
        $resolver.push-package(self);

        # Methods this class already has: its attached methods plus, when
        # augmenting, the methods produced by the original composition. An
        # accessor is not generated when one of these already provides it.
        my $methods := nqp::hash();
        for self.attached-methods {
            nqp::bindkey($methods, $_.name.canonicalize, 1);
        }
        if nqp::can($how,'method_table') {
            for $how.method_table($type) {
                nqp::bindkey($methods, nqp::iterkey_s($_), 1);
            }
        }

        # Collect the accessors we build, so IMPL-EXPR-QAST can emit their QAST
        # into the body as real bytecode instead of leaving them as
        # lazily-compiled stubs.
        my $synthetic := nqp::list();

        my sub makeName(str $name) {
            nqp::index($name,"::") == -1
              ?? RakuAST::Name.from-identifier($name)
              !! RakuAST::Name.from-identifier-parts(|nqp::split("::",$name))
        }

        for self.attached-attributes -> $attribute {
            my str $sigil := $attribute.sigil;
            my str $key   := $attribute.desigilname.canonicalize;

            # Only public attributes ($.foo) get an accessor, and only when the
            # class does not already provide a method of that name.
            next unless $attribute.twigil eq '.';
            next if nqp::existskey($methods,$key);

            my int $is-rw;
            for self.IMPL-UNWRAP-LIST($attribute.traits) -> $trait {
                $is-rw := 1
                  if $trait.IMPL-TRAIT-NAME eq 'is'
                  && $trait.name.canonicalize eq 'rw';
            }

            # method $key () [is raw] { $!attribute }
            my $method := RakuAST::Method.new(
              name   => makeName($key),
              traits => $is-rw
                ?? (RakuAST::Trait::Is.new(
                      name => RakuAST::Name.from-identifier("raw")),)
                !! (),
              body   => RakuAST::Blockoid.new(
                RakuAST::StatementList.new(
                  RakuAST::Statement::Expression.new(
                    expression => RakuAST::Var::Attribute.new($sigil ~ '!' ~ $key)
                  )
                )
              )
            );
            $method.IMPL-BEGIN($resolver, $context);
            nqp::push($synthetic, $method);
        }

        # Keep the accessors for QAST emission into the body.
        nqp::bindattr(self, RakuAST::Package, '$!synthetic-methods', $synthetic);

        # Remove knowledge of invocant class from the resolver
        $resolver.pop-package();
        $resolver.pop-scope();
    }

    # Build the complete POPULATE submethod for this class, reading attribute
    # and BUILD/TWEAK information straight from the (composed) meta objects of
    # the whole MRO. This replaces both the Metamodel BUILDPLAN and the runtime
    # Mu.POPULATE for classes built through RakuAST. Runs after composition, so
    # the MRO and any applied roles are in place.
    method PRODUCE-POPULATE(
      RakuAST::Resolver $resolver, RakuAST::IMPL::QASTContext $context
    ) {
        my $type := self.stubbed-meta-object;
        my $how  := $type.HOW;
        return Nil unless nqp::can($how,'add_method') && nqp::can($how,'mro');

        # A POPULATE already in place (user-defined, or from the original
        # composition when augmenting) wins.
        return Nil if $how.declares_method($type,'POPULATE');

        # Only synthesize a POPULATE when this class introduces construction
        # work of its own. If it adds nothing, the parent's POPULATE (which
        # already walks the full MRO) is correct by inheritance, and skipping
        # avoids generating a method (and republishing the cache) per class.
        my int $own-work;
        for $how.attributes($type, :local) -> $a {
            if $a.is_built
              || (nqp::can($a,'required') && $a.required)
              || (nqp::can($a,'build') && nqp::isconcrete($a.build)) {
                $own-work := 1;
                last;
            }
        }
        unless $own-work {
            my $st := nqp::can($how,'submethod_table') ?? $how.submethod_table($type) !! nqp::hash();
            my $mt := nqp::can($how,'method_table')    ?? $how.method_table($type)    !! nqp::hash();
            $own-work := 1
              if nqp::not_i(nqp::isnull(nqp::atkey($st,'BUILD')))
              || nqp::not_i(nqp::isnull(nqp::atkey($st,'TWEAK')))
              || nqp::not_i(nqp::isnull(nqp::atkey($mt,'BUILD')))
              || nqp::not_i(nqp::isnull(nqp::atkey($mt,'TWEAK')));
        }
        return Nil unless $own-work;

        $resolver.push-scope(self.body);
        $resolver.push-package(self);

        my $Code := $resolver.type-from-setting('Code');

        my $statements := RakuAST::StatementList.new;
        my sub add($expression) {
            $statements.add-statement(
              RakuAST::Statement::Expression.new(:$expression)
            )
        }
        my sub makeName(str $name) {
            nqp::index($name,"::") == -1
              ?? RakuAST::Name.from-identifier($name)
              !! RakuAST::Name.from-identifier-parts(|nqp::split("::",$name))
        }
        my sub primsuffix(int $ps) {
            $ps == 1 ?? '_i' !! $ps == 2 ?? '_n' !! $ps == 10 ?? '_u' !! '_s'
        }
        my sub self-ast()    { RakuAST::Term::Self.new }
        my sub class-ast($c) { RakuAST::Literal.from-value($c) }
        my sub init-ast()    { RakuAST::Var::Lexical.new('$init') }
        my sub getattr(str $sfx, $c, str $name) {
            RakuAST::Nqp.new('getattr' ~ $sfx,
              self-ast(), class-ast($c), RakuAST::StrLiteral.new($name))
        }
        my sub atkey(str $key) {
            RakuAST::Nqp.new('atkey', init-ast(), RakuAST::StrLiteral.new($key))
        }
        my sub invoke($code, *@args) {
            RakuAST::ApplyPostfix.new(
              operand => RakuAST::Literal.from-value($code),
              postfix => RakuAST::Call::Term.new(
                args => RakuAST::ArgList.new(|@args)
              )
            )
        }
        my sub flat-nameds() {
            RakuAST::ApplyPrefix.new(
              prefix  => RakuAST::Prefix.new('|'),
              operand => RakuAST::Var::Lexical.new('%nameds')
            )
        }
        # Store into an attribute the class declares *itself*, the way ordinary
        # code would: $!a = v, or $!a := v for an is-bound object attribute. The
        # standard assignment / bind compilation handles native unboxing, the
        # .STORE for @ and % sigils, container vivification (including typed
        # containers) and binding. A native attribute is a raw slot, so binding
        # and assignment are the same and `=` is used (only an object attribute
        # supports `:=`).
        my sub store-own($attr, $value) {
            my int $bind := $attr.is_bound && nqp::not_i(nqp::objprimspec($attr.type));
            RakuAST::ApplyInfix.new(
              left  => RakuAST::Var::Attribute.new($attr.name),
              infix => $bind ?? RakuAST::Infix.new(':=') !! RakuAST::Assignment.new,
              right => $value)
        }

        # Store into an attribute that comes from an ancestor class $c. A direct
        # $!a cannot reach an inherited attribute, so name the declaring class
        # explicitly and do the low-level store the normal assignment would have
        # produced (.STORE for @/%, unbox + bindattr for natives).
        my sub store-inherited($c, $attr, $value) {
            my str $name  := $attr.name;
            my str $sigil := nqp::substr($name,0,1);
            my int $ps    := nqp::objprimspec($attr.type);
            $ps
              ?? RakuAST::Nqp.new('bindattr' ~ primsuffix($ps),
                   self-ast(), class-ast($c), RakuAST::StrLiteral.new($name),
                   RakuAST::Nqp.new('decont', $value))
              !! $attr.is_bound
                ?? RakuAST::Nqp.new('bindattr',
                     self-ast(), class-ast($c), RakuAST::StrLiteral.new($name), $value)
                !! ($sigil eq '@' || $sigil eq '%')
                  ?? RakuAST::ApplyPostfix.new(
                       operand => getattr('', $c, $name),
                       postfix => RakuAST::Call::Method.new(
                         name => makeName('STORE'),
                         args => RakuAST::ArgList.new(
                           $value, RakuAST::ColonPair::True.new('INITIALIZE'))))
                  !! RakuAST::Nqp.new('p6assign', getattr('', $c, $name), $value)
        }

        # Pick the right store for an attribute owned by MRO class $c.
        my sub store-into($c, $attr, $value) {
            nqp::eqaddr($c, $type)
              ?? store-own($attr, $value)
              !! store-inherited($c, $attr, $value)
        }

        my int $any-init;

        # Least-derived first, so a more derived class's BUILD/TWEAK and
        # defaults run after its parents'.
        my @mro := $how.mro($type);
        my int $m := nqp::elems(@mro);
        while --$m >= 0 {
            my $c    := nqp::atpos(@mro, $m);
            my $chow := $c.HOW;
            next unless nqp::can($chow,'attributes');

            my @attrs     := $chow.attributes($c, :local);
            my $sub-table := nqp::can($chow,'submethod_table')
              ?? $chow.submethod_table($c)
              !! nqp::hash();
            my $meth-table := nqp::can($chow,'method_table')
              ?? $chow.method_table($c)
              !! nqp::hash();

            # BUILD/TWEAK may be declared as a submethod (the norm) or as a
            # plain method (e.g. CompUnit::Repository::Installation.TWEAK).
            my $build := nqp::atkey($sub-table,'BUILD');
            $build := nqp::atkey($meth-table,'BUILD') if nqp::isnull($build);
            my $tweak := nqp::atkey($sub-table,'TWEAK');
            $tweak := nqp::atkey($meth-table,'TWEAK') if nqp::isnull($tweak);

            # 0. Install the containers for @ and % (and other) attributes.
            #    Normal `@!a = ...` assignment generated for a parsed attribute
            #    vivifies the container, but the synthetic attribute access here
            #    does not, so the container has to exist before the store.
            for @attrs -> $attr {
                next unless nqp::can($attr,'container_initializer');
                my $ci := $attr.container_initializer;
                next unless nqp::isconcrete($ci);
                add(RakuAST::Nqp.new('bindattr',
                  self-ast(), class-ast($c), RakuAST::StrLiteral.new($attr.name),
                  invoke($ci)));
            }

            # 1. Initialize attributes from the named arguments, unless a
            #    custom BUILD takes that over.
            if nqp::isconcrete($build) {
                add(invoke($build, self-ast(), flat-nameds()));
            }
            else {
                for @attrs -> $attr {
                    next unless $attr.is_built;
                    $any-init := 1;
                    my str $key := nqp::substr($attr.name,2);
                    # $!a = nqp::atkey($init,'a') if it was passed
                    add(RakuAST::Nqp.new('unless',
                      RakuAST::Nqp.new('isnull', atkey($key)),
                      store-into($c, $attr, atkey($key))));
                }
            }

            # 2. Required attributes must have ended up initialized.
            for @attrs -> $attr {
                next unless nqp::can($attr,'required') && $attr.required;
                $any-init := 1;
                my str $name := $attr.name;
                my int $ps   := nqp::objprimspec($attr.type);
                my $check :=
                  $ps == 3
                    ?? RakuAST::Nqp.new('not_i',
                         RakuAST::Nqp.new('isnull_s', getattr('_s', $c, $name)))
                    !! $ps
                      ?? getattr(primsuffix($ps), $c, $name)
                      !! RakuAST::Nqp.new('p6attrinited', getattr('', $c, $name));
                add(RakuAST::Nqp.new('unless',
                  $check,
                  RakuAST::ApplyPostfix.new(
                    operand => RakuAST::ApplyPostfix.new(
                      operand => RakuAST::Type::Simple.new(
                        makeName('X::Attribute::Required')),
                      postfix => RakuAST::Call::Method.new(
                        name => makeName('new'),
                        args => RakuAST::ArgList.new(
                          RakuAST::ColonPair::Value.new(
                            key => 'name', value => RakuAST::StrLiteral.new($name)),
                          RakuAST::ColonPair::Value.new(
                            key => 'why',
                            value => RakuAST::Literal.from-value($attr.required))))),
                    postfix => RakuAST::Call::Method.new(name => makeName('throw')))));
            }

            # 3. Apply default values to attributes still uninitialized.
            for @attrs -> $attr {
                next unless nqp::can($attr,'build');
                my $default := $attr.build;
                next unless nqp::isconcrete($default);
                $any-init := 1;
                my str $name := $attr.name;
                my int $ps   := nqp::objprimspec($attr.type);

                # The value, computed lazily by calling a will/default closure,
                # or used directly.
                my $value := nqp::istype($default,$Code)
                  ?? invoke($default, self-ast(),
                       getattr($ps ?? primsuffix($ps) !! '', $c, $name))
                  !! RakuAST::Literal.from-value($default);

                # Apply it only if the attribute is still at its zero/null/
                # uninitialized state.
                my $uninit :=
                  $ps == 3
                    ?? RakuAST::Nqp.new('isnull_s', getattr('_s', $c, $name))
                    !! $ps == 2
                      ?? RakuAST::Nqp.new('iseq_n',
                           getattr('_n', $c, $name), RakuAST::NumLiteral.new(0e0))
                      !! $ps
                        ?? RakuAST::Nqp.new('not_i', getattr(primsuffix($ps), $c, $name))
                        !! RakuAST::Nqp.new('not_i',
                             RakuAST::Nqp.new('p6attrinited', getattr('', $c, $name)));
                add(RakuAST::Nqp.new('if', $uninit, store-into($c, $attr, $value)));
            }

            # 4. Run this class's TWEAK, if any.
            if nqp::isconcrete($tweak) {
                add(invoke($tweak, self-ast(), flat-nameds()));
            }
        }

        # my $init := nqp::getattr(%nameds,Map,'$!storage')
        if $any-init {
            $statements.unshift-statement(
              RakuAST::Statement::Expression.new(
                expression => RakuAST::VarDeclaration::Simple.new(
                  sigil => '$', desigilname => makeName('init'),
                  initializer => RakuAST::Initializer::Bind.new(
                    RakuAST::Nqp.new('getattr',
                      RakuAST::Var::Lexical.new('%nameds'),
                      RakuAST::Type::Simple.new(makeName('Map')),
                      RakuAST::StrLiteral.new('$!storage'))))));
        }

        add(self-ast());  # POPULATE returns the invocant

        my $method := RakuAST::Method.new(
          name      => makeName('POPULATE'),
          signature => RakuAST::Signature.new(
            parameters => (RakuAST::Parameter.new(
              target   => RakuAST::ParameterTarget::Var.new(name => "\%nameds"),
              optional => False),)),
          body      => RakuAST::Blockoid.new($statements));
        $method.IMPL-BEGIN($resolver, $context);

        # Install on the type and refresh the cache so .new finds it, then keep
        # it for QAST emission into the body.
        $how.add_method($type, 'POPULATE', $method.meta-object);
        $how.publish_method_cache($type)
          if nqp::can($how,'publish_method_cache');

        my $synthetic := nqp::getattr(self, RakuAST::Package, '$!synthetic-methods');
        $synthetic := nqp::list() unless nqp::islist($synthetic);
        nqp::push($synthetic, $method);
        nqp::bindattr(self, RakuAST::Package, '$!synthetic-methods', $synthetic);

        # Remove knowledge of invocant class from the resolver
        $resolver.pop-package();
        $resolver.pop-scope();
    }
}

#-------------------------------------------------------------------------------
# Specific logic to handle grammars

class RakuAST::Grammar
  is RakuAST::Class
  is RakuAST::CheckTime
{
    method declarator()  { "grammar"             }
    method default-how() { Metamodel::GrammarHOW }

    method PERFORM-CHECK(
      RakuAST::Resolver          $resolver,
      RakuAST::IMPL::QASTContext $context
    ) {
        nqp::findmethod(RakuAST::Class, 'PERFORM-CHECK')(
          self, $resolver, $context
        );
        my $sanity-check := self.HOW.find_method(self,"check-sanity");
        $sanity-check(self) if $sanity-check;
        True;
    }
}

#-------------------------------------------------------------------------------
# Specific logic to handle modules

class RakuAST::Module
  is RakuAST::Package
{
    method declarator()  { "module"              }
    method default-how() { Metamodel::ModuleHOW  }

    method declare-lexicals(RakuAST::Resolver $resolver, RakuAST::IMPL::QASTContext $context) {
        self.meta-object-as-lexicals($resolver, 'PACKAGE', :$context);
        self.meta-object-as-lexicals($resolver, 'MODULE', :$context);
    }

    method additional-body-lexicals(:$resolver, :$context) {
        self.meta-object-as-body-lexicals('MODULE', :$resolver, :$context);
    }
}

#-------------------------------------------------------------------------------
# Specific logic to handle -knowhow- blocks

class RakuAST::Knowhow
  is RakuAST::Package
{
    method declarator()  { "knowhow"          }
    method default-how() { Metamodel::KnowHOW }
}

#-------------------------------------------------------------------------------
# Specific logic to handle -native- blocks

class RakuAST::Native
  is RakuAST::Package
{
    method declarator()  { "native"             }
    method default-how() { Metamodel::NativeHOW }
}
