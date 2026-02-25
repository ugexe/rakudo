## Order enumeration, for cmp and <=>
my enum Order (:Less(-1), :Same(0), :More(1));
role Rational { ... }

sub ORDER(int $i --> Order) is implementation-detail {
    $i
      ?? nqp::islt_i($i,0)
        ?? Less
        !! More
      !! Same
}

proto sub infix:<cmp>($, $, *% --> Order:D) is pure {*}
multi sub infix:<cmp>(\a, \b) {
    nqp::eqaddr(nqp::decont(a), nqp::decont(b))
      ?? Same
      !! a.Stringy cmp b.Stringy
}
multi sub infix:<cmp>(Real:D $a, \b) {
     $a === -Inf
       ?? Less
       !! $a === Inf
         ?? More
         !! $a.Stringy cmp b.Stringy
}
multi sub infix:<cmp>(\a, Real:D $b) {
     $b === Inf
       ?? Less
       !! $b === -Inf
         ?? More
         !! a.Stringy cmp $b.Stringy
}

multi sub infix:<cmp>(Real:D $a, Real:D $b) {
    nqp::istype($a,Rational) && nqp::istype($b,Rational)
      ?? $a.isNaN || $b.isNaN
        ?? $a.Num cmp $b.Num
        !! $a <=> $b
      !! (nqp::istype($a, Rational) && nqp::isfalse($a.denominator))
           || (nqp::istype($b, Rational) && nqp::isfalse($b.denominator))
        ?? $a.Bridge cmp $b.Bridge
        !! $a === -Inf || $b === Inf
          ?? Less
          !! $a === Inf || $b === -Inf
            ?? More
            !! $a.Bridge cmp $b.Bridge
}
multi sub infix:<cmp>(Int:D $a, Rational:D $b) {
    $a.isNaN || $b.isNaN ?? $a.Num cmp $b.Num !! $a <=> $b
}
multi sub infix:<cmp>(Rational:D $a, Int:D $b) {
    $a.isNaN || $b.isNaN ?? $a.Num cmp $b.Num !! $a <=> $b
}
multi sub infix:<cmp>(Int:D $a, Int:D $b) {
    ORDER(nqp::cmp_I($a,$b))
}
multi sub infix:<cmp>(int $a, int $b) {
    ORDER(nqp::cmp_i($a, $b))
}

multi sub infix:<cmp>(Code:D $a, Code:D $b) {
     $a.name cmp $b.name
}
multi sub infix:<cmp>(Code:D $a, \b) {
     $a.name cmp b.Stringy
}
multi sub infix:<cmp>(\a, Code:D $b) {
     a.Stringy cmp $b.name
}

multi sub infix:<cmp>(List:D \a, List:D \b) {
    nqp::if(
      a.is-lazy || b.is-lazy,
      infix:<cmp>(a.iterator, b.iterator),
      nqp::stmts(
        (my int $elems-a = a.elems),  # reifies
        (my int $elems-b = b.elems),  # reifies
        (my $list-a := nqp::getattr(nqp::decont(a),List,'$!reified')),
        (my $list-b := nqp::getattr(nqp::decont(b),List,'$!reified')),
        nqp::if(
          (my int $elems = nqp::if(
            nqp::islt_i($elems-a,$elems-b),
            $elems-a,
            $elems-b
          )),
          nqp::stmts(                                # elements to compare
            (my $i = -1),
            nqp::while(
              nqp::islt_i(++$i,$elems)
                && nqp::eqaddr(
                     (my $order := infix:<cmp>(
                       nqp::atpos($list-a,$i),
                       nqp::atpos($list-b,$i)
                     )),
                     Same
                   ),
              nqp::null
            ),
            nqp::if(
              nqp::eqaddr($order,Same),
              ORDER(nqp::cmp_i($elems-a,$elems-b)),  # same, length significant
              $order                                 # element different
            )
          ),
          ORDER(nqp::cmp_i($elems-a,$elems-b)),      # only length significant
        )
      )
    )
}

multi sub infix:<cmp>(
  Iterator:D \iter-a, Iterator:D \iter-b
) is implementation-detail {
    nqp::until(
      nqp::eqaddr((my $a := iter-a.pull-one),IterationEnd)
        || nqp::eqaddr((my $b := iter-b.pull-one),IterationEnd)
        || nqp::not_i(nqp::eqaddr(
             (my $order := infix:<cmp>($a,$b)),
             Same
           )),
      nqp::null
    );

    nqp::if(
      nqp::eqaddr($order,Same),                       # ended because different?
      nqp::if(
        nqp::eqaddr($a,IterationEnd),                 # left exhausted?
        nqp::if(
          nqp::eqaddr(iter-b.pull-one,IterationEnd),  # right exhausted?
          Same,
          Less
        ),
        More
      ),
      $order
    )
}

proto sub infix:«<=>»($, $, *% --> Order:D) is pure {*}
multi sub infix:«<=>»(\a, \b)  { a.Real <=> b.Real }
multi sub infix:«<=>»(Real $a, Real $b) { $a.Bridge <=> $b.Bridge }

multi sub infix:«<=>»(Int:D $a, Int:D $b) {
    ORDER(nqp::cmp_I($a,$b))
}
multi sub infix:«<=>»(int $a, int $b) {
    ORDER(nqp::cmp_i($a, $b))
}

proto sub infix:<before>($?, $?, *% --> Bool:D) is pure {*}
multi sub infix:<before>($? --> True) { }
multi sub infix:<before>($a, $b) {
    nqp::hllbool(nqp::eqaddr(($a cmp $b),Order::Less))
}

proto sub infix:<after>($?, $?, *% --> Bool:D) is pure {*}
multi sub infix:<after>($x? --> True) { }
multi sub infix:<after>($a, $b) {
    nqp::hllbool(nqp::eqaddr(($a cmp $b),Order::More))
}

proto sub infix:<leg>($, $, *% --> Order:D) is pure {*}
multi sub infix:<leg>(\a, \b) { a.Stringy cmp b.Stringy }

proto sub infix:<unicmp>($, $, *% --> Order:D) is pure {*}

# NOT is pure because of $*COLLATION
proto sub infix:<coll>(  $, $, *% --> Order:D) {*}


# Now that we have the Order enum, we can use it to speed up
# checks, rather than having the enum first be converted to an
# integer value for comparison.
augment class Any {

    # Make sure given comparator has an arity of 2
    my sub aritize22(&by) {
        nqp::iseq_i(&by.arity,2) ?? &by !! { by($^a) cmp by($^b) }
    }

    # Common logic for minpairs / maxpairs
    method !minmaxpairs(\order, &by) {
        my $iter   := self.pairs.iterator;
        my $result := nqp::create(IterationBuffer);

        nqp::until(
          nqp::eqaddr((my $pair := $iter.pull-one),IterationEnd)
            || nqp::isconcrete(my $target := $pair.value),
          nqp::null
        );

        nqp::unless(
          nqp::eqaddr($pair,IterationEnd),
          nqp::if(
            # 2-arg &by is already a comparator; use directly
            nqp::iseq_i(&by.arity, 2),
            nqp::stmts(                             # found at least one value
              nqp::push($result,$pair),
              nqp::until(
                nqp::eqaddr(nqp::bind($pair,$iter.pull-one),IterationEnd),
                nqp::if(
                  nqp::isconcrete(my $value := $pair.value),
                  nqp::if(
                    nqp::eqaddr(
                      (my $cmp-result := by($value,$target)),
                      order
                    ),
                    nqp::stmts(                     # new best
                      nqp::push(nqp::setelems($result,0),$pair),
                      nqp::bind($target,$value)
                    ),
                    nqp::if(                        # additional best (tie)
                      nqp::eqaddr($cmp-result,Order::Same),
                      nqp::push($result,$pair)
                    )
                  )
                )
              )
            ),
            # 1-arg &by is a key function: Schwartzian transform.
            # Cache the current best's key so it's computed once per element.
            nqp::stmts(
              nqp::push($result,$pair),
              (my $target-key = by($target)),
              nqp::until(
                nqp::eqaddr(nqp::bind($pair,$iter.pull-one),IterationEnd),
                nqp::if(
                  nqp::isconcrete(my $val := $pair.value),
                  nqp::stmts(
                    (my $val-key = by($val)),
                    nqp::if(
                      nqp::eqaddr($val-key cmp $target-key, order),
                      nqp::stmts(                   # new best
                        nqp::push(nqp::setelems($result,0),$pair),
                        nqp::bind($target,$val),
                        ($target-key = $val-key)
                      ),
                      nqp::if(                      # additional best (tie)
                        nqp::eqaddr($val-key cmp $target-key, Order::Same),
                        nqp::push($result,$pair)
                      )
                    )
                  )
                )
              )
            )
          )
        );

        $result
    }

    proto method minpairs(|) {*}
    multi method minpairs(Any:D: &by = &infix:<cmp>) {
        self!minmaxpairs(Order::Less, &by).List
    }

    proto method maxpairs(|) {*}
    multi method maxpairs(Any:D: &by = &infix:<cmp>) {
        self!minmaxpairs(Order::More, &by).List
    }

    proto method min (|) is nodal {*}
    multi method min(Any:D:) {
        nqp::if(
          (my $iter := self.iterator-and-first(".min", my $min)),
          nqp::until(
            nqp::eqaddr((my $pulled := $iter.pull-one),IterationEnd),
            nqp::if(
              (nqp::isconcrete($pulled)
                && nqp::eqaddr($pulled cmp $min,Order::Less)),
              $min = $pulled
            )
          )
        );

        nqp::defined($min) ?? $min !! Inf
    }
    multi method min(Any:D: :&by!) { self.min(&by, |%_) }
    multi method min(Any:D: &by) {
        nqp::if(
          (my $iter := self.iterator-and-first(".min", my $min)),
          nqp::if(
            # 2-arg &by is already a comparator; use directly
            nqp::iseq_i(&by.arity, 2),
            nqp::until(
              nqp::eqaddr((my $pulled := $iter.pull-one),IterationEnd),
              nqp::if(
                (nqp::isconcrete($pulled)
                  && nqp::eqaddr(by($pulled,$min),Order::Less)),
                $min = $pulled
              )
            ),
            # 1-arg &by is a key function: Schwartzian transform.
            # Cache the current best's key so it's computed once per element.
            nqp::stmts(
              (my $min-key = by($min)),
              nqp::until(
                nqp::eqaddr((my $pulled2 := $iter.pull-one),IterationEnd),
                nqp::if(
                  nqp::isconcrete($pulled2),
                  nqp::stmts(
                    (my $pulled-key = by($pulled2)),
                    nqp::if(
                      nqp::eqaddr($pulled-key cmp $min-key,Order::Less),
                      nqp::stmts(
                        ($min = $pulled2),
                        ($min-key = $pulled-key)
                      )
                    )
                  )
                )
              )
            )
          )
        );

        nqp::defined($min) ?? $min !! Inf
    }

    method !order-map(\order, &by, &mapper) {
        (nqp::elems(my $result := self!minmaxpairs(order, &by))
          ?? $result.map(&mapper)
          !! $result
        ).List
    }

    multi method min(Any:D: &by = &infix:<cmp>, :$k!) {
        $k ?? self!order-map(Order::Less, &by, *.key) !! self.min
    }
    multi method min(Any:D: &by = &infix:<cmp>, :$v!) {
        $v ?? self!order-map(Order::Less, &by, *.value) !! self.min
    }
    multi method min(Any:D: &by = &infix:<cmp>, :$kv!) {
        $kv
          ?? self!order-map(Order::Less, &by, { |(.key, .value) })
          !! self.min
    }
    multi method min(Any:D: &by = &infix:<cmp>, :$p!) {
        $p ?? self.minpairs(&by) !! self.min(&by)
    }

    proto method max (|) is nodal {*}
    multi method max(Any:D:) {
        nqp::if(
          (my $iter := self.iterator-and-first(".max", my $max)),
          nqp::until(
            nqp::eqaddr((my $pulled := $iter.pull-one),IterationEnd),
            nqp::if(
              (nqp::isconcrete($pulled)
                && nqp::eqaddr($pulled cmp $max,Order::More)),
              $max = $pulled
            )
          )
        );

        nqp::defined($max) ??  $max !! -Inf
    }
    multi method max(Any:D: :&by!) { self.max(&by, |%_) }
    multi method max(Any:D: &by) {
        nqp::if(
          (my $iter := self.iterator-and-first(".max", my $max)),
          nqp::if(
            # 2-arg &by is already a comparator; use directly
            nqp::iseq_i(&by.arity, 2),
            nqp::until(
              nqp::eqaddr((my $pulled := $iter.pull-one),IterationEnd),
              nqp::if(
                (nqp::isconcrete($pulled)
                  && nqp::eqaddr(by($pulled,$max),Order::More)),
                $max = $pulled
              )
            ),
            # 1-arg &by is a key function: Schwartzian transform.
            # Cache the current best's key so it's computed once per element.
            nqp::stmts(
              (my $max-key = by($max)),
              nqp::until(
                nqp::eqaddr((my $pulled2 := $iter.pull-one),IterationEnd),
                nqp::if(
                  nqp::isconcrete($pulled2),
                  nqp::stmts(
                    (my $pulled-key = by($pulled2)),
                    nqp::if(
                      nqp::eqaddr($pulled-key cmp $max-key,Order::More),
                      nqp::stmts(
                        ($max = $pulled2),
                        ($max-key = $pulled-key)
                      )
                    )
                  )
                )
              )
            )
          )
        );

        nqp::defined($max) ?? $max !! -Inf
    }
    multi method max(Any:D: &by = &infix:<cmp>, :$k!) {
        $k ?? self!order-map(Order::More, &by, *.key) !! self.max
    }
    multi method max(Any:D: &by = &infix:<cmp>, :$v!) {
        $v ?? self!order-map(Order::More, &by, *.value) !! self.max
    }
    multi method max(Any:D: &by = &infix:<cmp>, :$kv!) {
        $kv ?? self!order-map(Order::More, &by, { |(.key, .value) }) !! self.max
    }
    multi method max(Any:D: &by = &infix:<cmp>, :$p!) {
        $p ?? self.maxpairs(&by) !! self.max(&by)
    }

    method !minmax-range-init(
      $value, $mi is rw, $exmi is rw, $ma is rw, $exma is rw
    --> Nil) {
        $mi   = $value.min;
        $exmi = $value.excludes-min;
        $ma   = $value.max;
        $exma = $value.excludes-max;
    }
    method !minmax-range-check(
      $value, $mi is rw, $exmi is rw, $ma is rw, $exma is rw
    --> Nil) {
        nqp::if(
          nqp::eqaddr($value.min cmp $mi,Order::Less),
          nqp::stmts(
            ($mi   = $value.min),
            ($exmi = $value.excludes-min)
          )
        );

        nqp::if(
          nqp::eqaddr($value.max cmp $ma,Order::More),
          nqp::stmts(
            ($ma   = $value.max),
            ($exma = $value.excludes-max)
          )
        );
    }
    method !cmp-minmax-range-check(
      $value, &comparator, $mi is rw, $exmi is rw, $ma is rw, $exma is rw
    --> Nil) {
        nqp::if(                        # $cmp sigillless confuses the optimizer
          nqp::eqaddr(comparator($value.min,$mi),Order::Less),
          nqp::stmts(
            ($mi   = $value.min),
            ($exmi = $value.excludes-min)
          )
        );

        nqp::if(
          nqp::eqaddr(comparator($value.max,$ma),Order::More),
          nqp::stmts(
            ($ma   = $value.max),
            ($exma = $value.excludes-max)
          )
        );
    }

    proto method minmax (|) is nodal {*}
    multi method minmax(Any:D: ) {
        nqp::if(
          (my $iter := self.iterator-and-first(".minmax",my $pulled)),
          nqp::stmts(
            nqp::if(
              nqp::istype($pulled,Range),
              self!minmax-range-init($pulled,
                my $min,my int $excludes-min,my $max,my int $excludes-max),
              nqp::if(
                nqp::istype($pulled,Positional),
                self!minmax-range-init($pulled.minmax, # recurse for min/max
                  $min,$excludes-min,$max,$excludes-max),
                ($min = $max = $pulled)
              )
            ),
            nqp::until(
              nqp::eqaddr(($pulled := $iter.pull-one),IterationEnd),
              nqp::if(
                nqp::isconcrete($pulled),
                nqp::if(
                  nqp::istype($pulled,Range),
                  self!minmax-range-check($pulled,
                     $min,$excludes-min,$max,$excludes-max),
                  nqp::if(
                    nqp::istype($pulled,Positional),
                    self!minmax-range-check($pulled.minmax,
                       $min,$excludes-min,$max,$excludes-max),
                    nqp::if(
                      nqp::eqaddr($pulled cmp $min,Order::Less),
                      ($min = $pulled),
                      nqp::if(
                        nqp::eqaddr($pulled cmp $max,Order::More),
                        ($max = $pulled)
                      )
                    )
                  )
                )
              )
            )
          )
        );

        nqp::defined($min)
          ?? Range.new($min,$max,:$excludes-min,:$excludes-max)
          !! Range.Inf-Inf
    }
    multi method minmax(Any:D: :&by!) { self.minmax(&by, |%_) }
    multi method minmax(Any:D: &by) {
        # Cache arity once; 2-arg &by is a comparator, 1-arg is a key function.
        # For Range/Positional elements we always need a 2-arg comparator.
        my int $is-cmp = nqp::iseq_i(&by.arity, 2);
        my &comparator = $is-cmp ?? &by !! { by($^a) cmp by($^b) };

        nqp::if(
          (my $iter := self.iterator-and-first(".minmax",my $pulled)),
          nqp::stmts(
            nqp::if(
              nqp::istype($pulled,Range),
              self!minmax-range-init($pulled,
                my $min,my int $excludes-min,my $max,my int $excludes-max),
              nqp::if(
                nqp::istype($pulled,Positional),
                self!minmax-range-init($pulled.minmax(&by), # recurse min/max
                  $min,$excludes-min,$max,$excludes-max),
                ($min = $max = $pulled)
              )
            ),
            # For 1-arg key functions: cache initial min/max keys.
            # Scalar init sets $min === $max from the same element, so reuse the key.
            nqp::unless(
              $is-cmp,
              nqp::stmts(
                (my $min-key = by($min)),
                (my $max-key = (nqp::istype($pulled,Range) || nqp::istype($pulled,Positional))
                  ?? by($max) !! $min-key)
              )
            ),
            nqp::until(
              nqp::eqaddr(($pulled := $iter.pull-one),IterationEnd),
              nqp::if(
                nqp::isconcrete($pulled),
                nqp::if(
                  nqp::istype($pulled,Range),
                  nqp::stmts(
                    self!cmp-minmax-range-check($pulled,
                       &comparator,$min,$excludes-min,$max,$excludes-max),
                    # Range may have updated $min/$max; resync cached keys
                    nqp::unless(
                      $is-cmp,
                      nqp::stmts(
                        ($min-key = by($min)),
                        ($max-key = by($max))
                      )
                    )
                  ),
                  nqp::if(
                    nqp::istype($pulled,Positional),
                    nqp::stmts(
                      self!cmp-minmax-range-check($pulled.minmax(&by),
                         &comparator,$min,$excludes-min,$max,$excludes-max),
                      nqp::unless(
                        $is-cmp,
                        nqp::stmts(
                          ($min-key = by($min)),
                          ($max-key = by($max))
                        )
                      )
                    ),
                    nqp::if(
                      $is-cmp,
                      # 2-arg comparator: original logic
                      nqp::if(
                        nqp::eqaddr(comparator($pulled,$min),Order::Less),
                        ($min = $pulled),
                        nqp::if(
                          nqp::eqaddr(comparator($pulled,$max),Order::More),
                          ($max = $pulled)
                        )
                      ),
                      # 1-arg key function: Schwartzian transform.
                      # $pulled-key computed once, compared against both cached keys.
                      nqp::stmts(
                        (my $pulled-key = by($pulled)),
                        nqp::if(
                          nqp::eqaddr($pulled-key cmp $min-key,Order::Less),
                          nqp::stmts(
                            ($min = $pulled),
                            ($min-key = $pulled-key)
                          ),
                          nqp::if(
                            nqp::eqaddr($pulled-key cmp $max-key,Order::More),
                            nqp::stmts(
                              ($max = $pulled),
                              ($max-key = $pulled-key)
                            )
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        );

        nqp::defined($min)
          ?? Range.new($min,$max,:$excludes-min,:$excludes-max)
          !! Range.Inf-Inf
    }
}

# vim: expandtab shiftwidth=4
