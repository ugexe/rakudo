use Test;
use nqp;

# resolve_repossession_conflicts copies a repossessed Stash's entries into the
# current one, keeping '&'-subs and any key not already present. Feed it a Stash
# directly rather than staging a real precompilation repossession.

plan 3;

my $ml := nqp::gethllsym('Raku', 'ModuleLoader');

# A package's .WHO is a Stash; `our $sym` gives it a non-'&' key.
module Repo::Conflict { our $sym = 42; }
my $stash := Repo::Conflict.WHO;

is $stash.HOW.name($stash), 'Stash',
  'fixture is a Stash, so the resolver takes its Stash-merge branch';
ok (nqp::existskey($stash.FLATTENABLE_HASH, '$sym')),
  'fixture Stash holds a non-"&" key, the case the merge must handle';

# @conflicts is a flat (original, current) list; give it a fresh empty target.
my $current := nqp::hash();
my $conflicts := nqp::list($stash, $current);

lives-ok {
    nqp::findmethod($ml, 'resolve_repossession_conflicts')($ml, $conflicts);
    die 'entry was not merged into the current Stash'
      unless nqp::existskey($current, '$sym');
}, 'merges a Stash with a non-"&" key into the current one';
