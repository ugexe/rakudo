use lib <t/packages/Test-Helpers>;
use Test;
use Test::Helpers;

plan 7;

# Repository modules pulled in during $*REPO setup are loaded with
# dependency recording suspended, so they normally stay out of the
# compiled module's recorded dependencies. But the compilation can
# still end up referencing an object owned by such a module's
# serialization context, most commonly a type parameterization the
# repository module's own compilation interned first (e.g. the
# Callable[T] mixin applied to a routine with a return type). The
# bytecode then carries a hard reference to that context, and a
# process that loads the precompiled module without the repository
# module preloaded dies with "Missing or wrong version of dependency".
# Such a dependency must be promoted into the recorded set so the
# loader knows to preload the repository module.

# Part 1: mechanism. A custom CUR anchors Callable[Semaphore] in its
# own serialization context (Semaphore because CORE.setting must not
# own the parameterization itself, and no setting routine returns it).
# The consumer module requests the same parameterization without ever
# naming the CUR, so the CUR must show up in its recorded
# dependencies. This is the inverse of the case covered by
# rakuast-suspend-precomp-deps.t, where nothing from the suspended
# load is referenced and the dependency must stay unrecorded.

my $tmp       = make-temp-dir;
my $cur-dir   = $tmp.add('cur-classes');
$cur-dir.add('CompUnit/Repository').mkdir(:parent);
my $mod-store = $tmp.add('module-store');
$mod-store.mkdir;

$cur-dir.add('CompUnit/Repository/PromoteTestCUR.rakumod').spurt: q:to/EOF/;
class CompUnit::Repository::PromoteTestCUR is CompUnit::Repository::FileSystem {
    method short-id(--> Str:D) { 'promotetestcur' }
    method path-spec(::?CLASS:D: --> Str:D) {
        self.^name ~ '#' ~ self.prefix.absolute
    }
}
our sub leak-anchor(--> Semaphore) { Semaphore.new(1) }
EOF

$mod-store.add('PromoteTestConsumer.rakumod').spurt: q:to/EOF/;
use Test;
unit module PromoteTestConsumer;
our sub greet(--> Semaphore) { Semaphore.new(1) }
EOF

my $proc = run :out, :err,
    $*EXECUTABLE.absolute,
    '-I', "CompUnit::Repository::PromoteTestCUR#{$mod-store.absolute}",
    '-I', $cur-dir.absolute,
    '-e', 'use PromoteTestConsumer; say PromoteTestConsumer::greet().^name';

my $out      = $proc.out.slurp(:close);
my $proc-err = $proc.err.slurp(:close);
my $exitcode = $proc.exitcode;

# The precomp file starts with a text dependency header followed by
# binary bytecode; decoding the first few KB as latin1 is enough to
# scan the header.
my $promoted = False;
if $mod-store.add('.precomp').d {
    for Rakudo::Internals.DIR-RECURSE($mod-store.add('.precomp').absolute) -> $path {
        my $f = $path.IO;
        next if $f.basename eq 'CACHEDIR.TAG';
        next if $f.basename.ends-with('.lock');
        next if $f.basename.ends-with('.repo-id');
        my $bytes     = $f.slurp(:bin);
        my $head-size = $bytes.bytes min 4096;
        my $head      = $bytes.subbuf(0, $head-size).decode('latin1', :replacement('?'));
        $promoted = True if $head.contains('PromoteTestCUR');
    }
}

is $exitcode, 0,          'consumer subprocess exited cleanly';
is $out.chomp, 'Semaphore', 'consumer module ran through the custom CUR chain';
ok $promoted,             'referenced CUR was promoted into consumer precomp dependencies';

# Part 2: end to end, the shape of a zef self-install. Install a dist
# through CompUnit::Repository::Staging, then load it from the bare
# installation in a fresh process where nothing has loaded Staging.
# The Staging source is copied out of lib/ so the test does not depend
# on an installed core dist (the build-tree rakudo has none) and gains
# an anchor sub whose Callable[Semaphore] mixin both frontends
# serialize into the copy's context. The staged module's own routines
# then pick that parameterization up. The `use` of the dist's second
# module is what makes the precompile worker initialize $*REPO, which
# is where Staging gets loaded with recording suspended.

my $curs-lib = $tmp.add('curs-lib');
$curs-lib.add('CompUnit/Repository').mkdir(:parent);
$curs-lib.add('CompUnit/Repository/Staging.rakumod').spurt:
    'lib/CompUnit/Repository/Staging.rakumod'.IO.slurp
    ~ "\nour sub promote-test-anchor(--> Semaphore) \{ Semaphore.new(1) }\n";

my $dist = $tmp.add('dist');
$dist.add('lib').mkdir(:parent);
$dist.add('META6.json').spurt: q:to/EOF/;
{
  "perl": "6.d",
  "name": "PromoteTestStaged",
  "version": "0.0.1",
  "auth": "test",
  "provides": {
    "PromoteTestStaged": "lib/PromoteTestStaged.rakumod",
    "PromoteTestStaged::Extra": "lib/PromoteTestStaged/Extra.rakumod"
  }
}
EOF
$dist.add('lib/PromoteTestStaged').mkdir;
$dist.add('lib/PromoteTestStaged/Extra.rakumod').spurt: q:to/EOF/;
unit module PromoteTestStaged::Extra;
EOF
$dist.add('lib/PromoteTestStaged.rakumod').spurt: q:to/EOF/;
use PromoteTestStaged::Extra;
unit class PromoteTestStaged;
method c(--> Semaphore) { Semaphore.new(1) }
our sub d(--> Semaphore) { Semaphore.new(1) }
EOF

my $inst = $tmp.add('inst');
$inst.mkdir;

my $install = run :out, :err, :cwd($tmp),
    $*EXECUTABLE.absolute,
    '-I', $curs-lib.absolute,
    '-e', q:to/EOF/;
        use CompUnit::Repository::Staging;
        CompUnit::Repository::Staging.new(
            :prefix("inst".IO.absolute),
            :next-repo($*REPO),
            :name("site"),
        ).install(Distribution::Path.new("dist".IO));
        EOF
my $install-err = $install.err.slurp(:close);
my $install-out = $install.out.slurp(:close);
is $install.exitcode, 0, 'staging install exited cleanly'
    or diag $install-err;

my $staged-promoted = False;
if $inst.add('precomp').d {
    for Rakudo::Internals.DIR-RECURSE($inst.add('precomp').absolute) -> $path {
        my $f = $path.IO;
        next if $f.basename.ends-with('.lock');
        next if $f.basename.ends-with('.repo-id');
        my $bytes     = $f.slurp(:bin);
        my $head-size = $bytes.bytes min 4096;
        my $head      = $bytes.subbuf(0, $head-size).decode('latin1', :replacement('?'));
        $staged-promoted = True if $head.contains('Staging');
    }
}
ok $staged-promoted, 'Staging was promoted into the staged precomp dependencies';

my $consume = run :out, :err,
    $*EXECUTABLE.absolute,
    '-I', "inst#{$inst.absolute}",
    '-e', 'use PromoteTestStaged; say PromoteTestStaged.c.^name';
my $consume-out = $consume.out.slurp(:close);
my $consume-err = $consume.err.slurp(:close);
is $consume.exitcode, 0, 'staged module loads in a process without Staging'
    or diag $consume-err;
is $consume-out.chomp, 'Semaphore', 'staged module works';

# vim: expandtab shiftwidth=4
