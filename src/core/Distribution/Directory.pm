class Distribution::Directory does Distribution::Interface {
    has IO::Path $.path;
    has $!meta;

    method meta {
        $!meta := ?$!meta ?? $!meta !! self!read-meta;
        $!meta<ver>  //= $!meta<version>:delete   if ?$!meta<version>;
        $!meta<auth> //= $!meta<authority>:delete if ?$!meta<authority>;
        $!meta<auth> //= $!meta<author>:delete    if ?$!meta<author>;
        $!meta;
    }

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

    method ls-files($subdir?) {
        my @stack = $subdir ?? $!path.child($subdir) !! $!path;
        my $files := gather while ( @stack ) {
            my $current = @stack.pop;
            my $relpath = IO::Path.new($current, :CWD($!path)).relative;
            take $relpath if $current.f;
            @stack.append( |dir($current) ) if $current.d;
        }
    }

    method !read-meta {
        my $meta-basename = <META6.json META.info>.first({ $!path.child($_).e });
        my $meta-path     = $!path.child($meta-basename);
        %(from-json($meta-path.IO.slurp))
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
