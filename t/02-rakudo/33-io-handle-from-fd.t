use lib $*PROGRAM.parent(2).add('packages/Test-Helpers');
use Test;
use Test::Helpers;

plan 6;

subtest 'basic writable fd (stdout fd=1)' => {
    my $fh = IO::Handle.from-native-descriptor(1);
    ok $fh.opened, 'reports as opened';
    # fd-based handles do not auto-close, so stdout is safe here
}

subtest 'fd-based writable handle writes data' => {
    my $tmp = make-temp-file;
    my $fh = $tmp.open(:w);
    my $writer = IO::Handle.from-native-descriptor($fh.native-descriptor);
    $writer.print("hello via fd");
    $writer.flush;
    is $tmp.slurp, "hello via fd", 'data written and read back';
    $fh.close;
}

subtest 'fd-based readable handle: slurp' => {
    my $tmp = make-temp-file(:content("hello via fd"));
    my $fh = $tmp.open(:r);
    my $reader = IO::Handle.from-native-descriptor($fh.native-descriptor);
    my $got = $reader.slurp;
    is $got, "hello via fd", 'slurp reads content';
    $fh.close;
}

subtest 'fd-based readable handle: .get' => {
    my $tmp = make-temp-file(:content("first\nsecond\n"));
    my $fh = $tmp.open(:r);
    my $reader = IO::Handle.from-native-descriptor($fh.native-descriptor, :enc<utf8>);
    is $reader.get, "first",  'first line';
    is $reader.get, "second", 'second line';
    $fh.close;
}

subtest 'native-descriptor returns the original fd' => {
    my $tmp = make-temp-file(:content(""));
    my $fh = $tmp.open(:r);
    my $fd = $fh.native-descriptor;
    my $fh2 = IO::Handle.from-native-descriptor($fd);
    is $fh2.native-descriptor, $fd, 'native-descriptor matches fd used to open';
    $fh.close;
}

subtest 'OS-inferred open mode prevents exclusive lock on read-only fd' => {
    my $tmp = make-temp-file(:content(""));
    my $fh = $tmp.open(:r);
    my $reader = IO::Handle.from-native-descriptor($fh.native-descriptor);
    throws-like { $reader.lock(:!shared) }, X::IO::Lock, :message(/read\-only/), 'failure mentions read-only';
    $fh.close;
}
