{
    my $i;
    role CompUnit::PrecompilationRepository {
        has $!i = $i++;

        method load(CompUnit::PrecompilationId $id) returns CompUnit {
            CompUnit
        }

        method may-precomp() {
            $i < 3 # number of next repo after None and the first Default
        }
    }
}

BEGIN CompUnit::PrecompilationRepository::<None> := CompUnit::PrecompilationRepository.new;

class CompUnit { ... }
class CompUnit::PrecompilationRepository::Default does CompUnit::PrecompilationRepository {
    has CompUnit::PrecompilationStore $.store;
    has %!loaded;

    my $lle;
    my $profile;

    method try-load(
        CompUnit::PrecompilationDependency::File $dependency,
        IO::Path :$source = $dependency.src.IO,
        CompUnit::PrecompilationStore :@precomp-stores = Array[CompUnit::PrecompilationStore].new($.store),
    ) returns CompUnit::Handle {
        my $RMD = $*RAKUDO_MODULE_DEBUG;
        my $id = $dependency.id;
        $RMD("try-load $id: $source") if $RMD;

        # Even if we may no longer precompile, we should use already loaded files
        return %!loaded{$id} if %!loaded{$id}:exists;

        my $handle = (
            self.may-precomp and (
                my $loaded = self.load($id, :since($source.modified), :@precomp-stores) # already precompiled?
                or self.precompile($source, $id, :source-name($dependency.source-name), :force($loaded ~~ Failure))
                    and self.load($id, :@precomp-stores) # if not do it now
            )
        );
        my $precompiled = ?$handle;

        if $*W and $*W.is_precompilation_mode {
            if $precompiled {
                say $dependency.serialize;
            }
            else {
                nqp::exit(0);
            }
        }

        $handle ?? $handle !! Nil
    }

    method !load-handle-for-path(CompUnit::PrecompilationUnit $unit) {
        my $preserve_global := nqp::ifnull(nqp::gethllsym('perl6', 'GLOBAL'), Mu);
        if $*RAKUDO_MODULE_DEBUG -> $RMD { $RMD("Loading precompiled\n$unit") }
#?if moar
        my $handle := CompUnit::Loader.load-precompilation-file($unit.bytecode-handle);
#?endif
#?if !moar
        my $handle := CompUnit::Loader.load-precompilation($unit.bytecode);
#?endif
        nqp::bindhllsym('perl6', 'GLOBAL', $preserve_global);
        CATCH {
            default {
                nqp::bindhllsym('perl6', 'GLOBAL', $preserve_global);
                .throw;
            }
        }
        $handle
    }

    method !load-file(
        CompUnit::PrecompilationStore @precomp-stores,
        CompUnit::PrecompilationId $id,
        :$repo-id,
    ) {
        my $compiler-id = $*PERL.compiler.id;
        my $RMD = $*RAKUDO_MODULE_DEBUG;
        for @precomp-stores -> $store {
            $RMD("Trying to load {$id ~ ($repo-id ?? '.repo-id' !! '')} from $store.prefix()") if $RMD;
            my $file = $repo-id
                ?? $store.load-repo-id($compiler-id, $id)
                !! $store.load-unit($compiler-id, $id);
            return $file if $file;
        }
        Nil
    }

    method !load-dependencies(CompUnit::PrecompilationUnit:D $precomp-unit, Instant $since, @precomp-stores) {
        my $compiler-id = $*PERL.compiler.id;
        my $RMD = $*RAKUDO_MODULE_DEBUG;
        my $resolve = False;
        my $repo = $*REPO;
        my $repo-id = self!load-file(@precomp-stores, $precomp-unit.id, :repo-id);
        if $repo-id ne $repo.id {
            $RMD("Repo changed: $repo-id ne {$repo.id}. Need to re-check dependencies.") if $RMD;
            $resolve = True;
        }
        for $precomp-unit.dependencies -> $dependency {
            $RMD("dependency: $dependency") if $RMD;
            unless %!loaded{$dependency.id}:exists {
                if $resolve {
                    my $comp-unit = $repo.resolve($dependency.spec);
                    $RMD("Old id: $dependency.id(), new id: {$comp-unit.repo-id}") if $RMD;
                    return False unless $comp-unit and $comp-unit.repo-id eq $dependency.id;
                }
                my $file;
                my $store = @precomp-stores.first({ $file = $_.path($compiler-id, $dependency.id); $file.e });
                $RMD("Could not find $dependency.spec()") if $RMD and not $store;
                return False unless $store;
                my $modified = $file.modified;
                $RMD("$file\nspec: $dependency.spec()\nmtime: $modified\nsince: $since}")
                  if $RMD;

                return False if $modified > $since;
                my $srcIO = CompUnit::RepositoryRegistry.file-for-spec($dependency.src) // $dependency.src.IO;
                $RMD("source: $srcIO mtime: " ~ $srcIO.modified) if $RMD;
                return False if not $srcIO.e or $modified <= $srcIO.modified;

                my $dependency-precomp = $store.load-unit($compiler-id, $dependency.id);
                %!loaded{$dependency.id} = self!load-handle-for-path($dependency-precomp);
            }

            # report back id and source location of dependency to dependant
            say $dependency.serialize if $*W and $*W.is_precompilation_mode;
        }

        if $resolve {
            self.store.store-repo-id($compiler-id, $precomp-unit.id, :repo-id($repo.id));
        }
        True
    }

    method load(
        CompUnit::PrecompilationId $id,
        Instant :$since,
        CompUnit::PrecompilationStore :@precomp-stores = Array[CompUnit::PrecompilationStore].new($.store),
    ) returns CompUnit::Handle {
        return %!loaded{$id} if %!loaded{$id}:exists;
        my $RMD = $*RAKUDO_MODULE_DEBUG;
        my $compiler-id = $*PERL.compiler.id;
        my $unit = self!load-file(@precomp-stores, $id);
        if $unit {
            my $modified = $unit.modified;
            if (not $since or $modified > $since)
                and self!load-dependencies($unit, $modified, @precomp-stores)
            {
                return %!loaded{$id} = self!load-handle-for-path($unit)
            }
            else {
                if $*RAKUDO_MODULE_DEBUG -> $RMD {
                    $RMD("Outdated precompiled $unit\nmtime: $modified\nsince: $since")
                }
                fail "Outdated precompiled $unit";
            }
        }
        Nil
    }

    method precompile(
        IO::Path:D $path,
        CompUnit::PrecompilationId $id,
        Bool :$force = False,
        Instant :$since,
        :$source-name = $path.Str
    ) {
        my $compiler-id = $*PERL.compiler.id;
        my $io = self.store.destination($compiler-id, $id);
        my $RMD = $*RAKUDO_MODULE_DEBUG;
        if not $force and $io.e and $io.s and (not $since or $io.modified > $since) {
            $RMD("$source-name\nalready precompiled into\n$io") if $RMD;
            self.store.unlock;
            return True;
        }
        my $bc = "$io.bc".IO;

        my $rev-deps = ($io ~ '.rev-deps').IO;
        if $rev-deps.e {
            for $rev-deps.lines {
                $RMD("removing outdated rev-dep $_") if $RMD;
                self.store.delete($compiler-id, $_);
            }
        }

        $lle     //= Rakudo::Internals.LL-EXCEPTION;
        $profile //= Rakudo::Internals.PROFILE;
        my %ENV := %*ENV;
        %ENV<RAKUDO_PRECOMP_WITH> = $*REPO.repo-chain.map(*.path-spec).join(',');
        %ENV<RAKUDO_PRECOMP_LOADING> = Rakudo::Internals::JSON.to-json: @*MODULES // [];
        my $current_dist = %ENV<RAKUDO_PRECOMP_DIST>;
        %ENV<RAKUDO_PRECOMP_DIST> = $*RESOURCES ?? $*RESOURCES.Str !! '{}';

        $RMD("Precompiling $path into $bc") if $RMD;
        my $perl6 = $*EXECUTABLE
            .subst('perl6-debug', 'perl6') # debugger would try to precompile it's UI
            .subst('perl6-gdb', 'perl6')
            .subst('perl6-jdb-server', 'perl6-j') ;
        my $proc = run(
          $perl6,
          $lle,
          $profile,
          "--target=" ~ Rakudo::Internals.PRECOMP-TARGET,
          "--output=$bc",
          "--source-name=$source-name",
          $path,
          :out,
          :err,
        );
        %ENV.DELETE-KEY(<RAKUDO_PRECOMP_WITH>);
        %ENV.DELETE-KEY(<RAKUDO_PRECOMP_LOADING>);
        %ENV<RAKUDO_PRECOMP_DIST> = $current_dist;

        my $error  = $proc.err.lines.join("\n");
        my @result = $proc.out.lines.unique;
        if not $proc.out.close or $proc.status {  # something wrong
            self.store.unlock;
            $RMD("Precomping $path failed: $proc.status()") if $RMD;
            Rakudo::Internals.VERBATIM-EXCEPTION(1);
            die $error;
        }

        $*ERR.print($error) if $error;
        unless $bc.e {
            $RMD("$path aborted precompilation without failure") if $RMD;
            self.store.unlock;
            return True;
        }
        $RMD("Precompiled $path into $bc") if $RMD;
        my str $dependencies = '';
        my CompUnit::PrecompilationDependency::File @dependencies;
        for @result -> $dependency-str {
            unless $dependency-str ~~ /^<[A..Z0..9]> ** 40 \0 .+/ {
                say $dependency-str;
                next
            }
            my $dependency = CompUnit::PrecompilationDependency::File.deserialize($dependency-str);
            $RMD("id: $dependency.id(), src: $dependency.src(), spec: $dependency.spec()") if $RMD;
            my $path = self.store.path($compiler-id, $dependency.id);
            if $path.e {
                spurt($path ~ '.rev-deps', "$dependency.id()\n", :append);
            }
            @dependencies.push: $dependency;
        }
        $RMD("Writing dependencies and byte code to $io.tmp") if $RMD;
        self.store.store-unit(
            $compiler-id,
            $id,
            self.store.new-unit(:$id, :@dependencies, :bytecode($bc.slurp(:bin))),
        );
        $bc.unlink;
        self.store.store-repo-id($compiler-id, $id, :repo-id($*REPO.id));
        self.store.unlock;
        True
    }
}

# vim: ft=perl6 expandtab sw=4
