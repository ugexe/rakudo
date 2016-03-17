role Distribution {
    # Distribution::Meta::*
    method meta    { ... }

    # Distribution::Storage::*
    method content { ... }
    method files   { ... }

    method Str() {
        return "{$.meta<name>}"
        ~ ":ver<{$.meta<ver>   //''}>"
        ~ ":auth<{$.meta<auth> // ''}>"
        ~ ":api<{$.meta<api>   // ''}>";

    }
    method id() {
        return nqp::sha1(self.Str);
    }
}

# Pre-install distribution style META6 parsing
# Differs from post-install META6 parsing in the following ways:
# 1. `provides` value changes
#   a. { "Module::Name" => "lib/Module/Name.pm6" }
#   b. { "Module::Name" => { "pm6" => { file => "xxx", time => "xxx", cver => "xxx" } } }
role Distribution::Storage::Directory {
    has IO::Path $.path;

    proto method content(|) {*}
    multi method content('provides', $name, $relpath) {
        self!make-handle($relpath);
    }
    multi method content('resources', 'libraries', *@keys) {
        my $relpath = self!make-path: 'resources', 'libraries', |@keys.reduce: { $^a.IO.child($^b) };
        my $lib     = $*VM.platform-library-name($relpath);
        self!make-handle($lib);
    }
    multi method content('resources', *@keys) {
        my $relpath = self!make-path: 'resources', |@keys.reduce: { $^a.IO.child($^b) };
        self!make-handle($relpath);
    }
    multi method content(*@keys) {
        self!make-handle(~@keys.tail);
    }

    method files($subdir?) {
        my @stack = $subdir ?? $!path.child($subdir) !! $!path;
        my $files := gather while ( @stack ) {
            my $current = @stack.pop;
            my $relpath = IO::Path.new($current, :CWD($!path)).relative;
            take $relpath if $current.f;
            @stack.append( |dir($current) ) if $current.d;
        }
    }

    method !make-handle($relpath) {
        my $file   = IO::Path.new($relpath, :CWD($!path));
        my $handle = IO::Handle.new(path => $file);
        $handle // $handle.throw;
    }

    method !make-path(*@parts) {
        +@parts == 1 ?? @parts[0].IO !! @parts.reduce({ $^a.IO.child($^b) })
    }
}

role Distribution::Hash[::Storage = Distribution::Storage::Directory] {
    has %.hash;

    method BUILDALL(|) {
        self does Storage;
        self does Distribution;
        nextsame;
    }

    method new($hash, *%_) {
        self.bless(:$hash, |%_)
    }

    method meta { %!hash }
}

role Distribution::Path[::Storage = Distribution::Storage::Directory] {
    has $!meta;

    submethod BUILD(:$!meta) { }

    method BUILDALL(|) {
        self does Storage;
        self does Distribution;
        nextsame;
    }

    proto method new(|) {*}
    multi method new($path where *.IO.d) {
        my $meta-basename = <META6.json META.info>.first({ $path.child($_).e });
        my $meta-path     = $path.child($meta-basename);
        my $meta          = %(from-json($meta-path.IO.slurp));
        $meta<ver> = $meta<version>:delete // $meta<ver>;

        self.bless(:$path, :meta($meta))
    }
    multi method new($path where *.IO.f) {
        say "P2: {$path.perl}";
        my $meta = %(from-json($path.IO.slurp));
        $meta<ver> = $meta<version>:delete // $meta<ver>;

        self.bless(:path($path.IO.parent), :meta($meta))
    }

    method meta { $!meta }
}

role CompUnit::Repository { ... }
class CompUnit::RepositoryRegistry is repr('Uninstantiable') { ... }
class Distribution::Resources does Associative {
    has Str $.dist-id;
    has Str $.repo;

    proto method BUILD(|) { * }

    multi method BUILD(:$!dist-id, CompUnit::Repository :$repo --> Nil) {
        $!repo = $repo.path-spec;
    }

    multi method BUILD(:$!dist-id, Str :$!repo --> Nil) { }

    method from-precomp() {
        if %*ENV<RAKUDO_PRECOMP_DIST> -> \dist {
            my %data := from-json dist;
            self.new(:repo(%data<repo>), :dist-id(%data<dist-id>))
        }
        else {
            Nil
        }
    }

    method AT-KEY($key) {
        CompUnit::RepositoryRegistry.repository-for-spec($.repo).resource($.dist-id, $key)
    }

    method Str() {
        to-json {repo => $.repo.Str, dist-id => $.dist-id};
    }
}

# vim: ft=perl6 expandtab sw=4
