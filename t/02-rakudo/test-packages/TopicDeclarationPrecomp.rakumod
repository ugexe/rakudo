unit module TopicDeclarationPrecomp;

my $_ = 9;
sub unit-topic is export { OUTER::<$_> }
sub topic-for is export { my $_ = 5 for 1,2; $_ }
sub topic-closure is export { my $_ = 5; my $p = -> { $_ }; $p }
our constant CLOSURE = topic-closure();
sub match-var is export { my $/ = 8; $/ }
role R is export {
    my $/ = 6;
    method m { my Int $_ = 7 given 3; $_ }
}
