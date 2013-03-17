use strict;
use warnings;

use File::Slurp qw( read_file );
use Test::More tests => 45;
use Try::Tiny;

BEGIN { use_ok('X12::Schema::Parser') or die; }

my (undef, @examples) = split /\n--- /, read_file(\*DATA);

for my $ex (@examples) {
    my ($name, $postname) = split /\n/, $ex, 2;
    my ($input, $output) = split /\n==>\n/, $postname, 2;

    $output =~ s/#.*//g;
    $output =~ s/\n*$//;

    my $result;

    local $@;
    my $expect = ($output =~ /^(_F.*)/) ? [ FAIL => $1 ] : [ OK => eval $output ];
    die $@ if $@;

    try {
        $result = [ 'OK', X12::Schema::Parser->parse( '_F', $input ) ];
    } catch {
        chomp; $result = [ 'FAIL', $_ ];
    };

    use Data::Dumper;
    is_deeply( $result, $expect, $name );
}

__DATA__

#### Errors
#### Gross syntax

--- indentation consistency
schema:
   foo
  bar
==>
_F:3:Inconsistent indentation; previous sibling indented 3, this indented 2

--- hard tabs
schema:
	foo
==>
_F:2:Illegal hard tab

#### Root level

--- Duplicate schema
schema:
schema:
==>
_F:2:Duplicate schema definition

--- Invalid root-level element
foo: bar
==>
_F:1:Root-level element in schema must be segment: or schema:

--- No schema

==>
_F:0:Missing schema: element

--- Duplicate segment
segment: FOO FooThing
    A AN 1/1
segment: BAR BarThing
    A AN 1/1
segment: FOO BazThing
    A AN 1/1
==>
_F:5:Duplicate definition of segment FOO

#### Segments

--- segment: duplicate flag
segment: FOO FooThing +incomplete +incomplete
    A AN 1/1
==>
_F:1:Duplicate flag +incomplete

--- segment: invalid flag
segment: FOO FooThing +unknown
    A AN 1/1
==>
_F:1:Invalid flag +unknown for segment, valid flags are: +incomplete

--- segment: syntax check
segment: FOO +incomplete
    A AN 1/1
==>
_F:1:Segment syntax is segment: SHRT FriendlyName

--- segment: syntax (long)
segment: FOO BAR BAZ
    A AN 1/1
==>
_F:1:Segment syntax is segment: SHRT FriendlyName

--- segment: invalid children
segment: FOO FooThing
    child: bar
    A AN 1/1
==>
_F:2:Child of a segment must be an element (unmarked) or a constraint:

--- segment: duplicate children
segment: FOO FooThing
    Aleph   N0 1/5
    Bet     N0 1/5
    Aleph   N0 1/5
==>
_F:4:Duplicate hash key for segment element: Aleph

--- segment: no children
segment: FOO FooThing
==>
_F:1:Non-incomplete segment without defined elements

#### Constraints

--- constraint: no flags
segment: FOO FooThing
    constraint: +bob
    A AN 1/1
==>
_F:2:Constraint does not accept flags

--- constraint: parens
segment: FOO FooThing
    constraint: foo[bar]
    A AN 1/1
==>
_F:2:Constraint syntax is constraint: kind( A, B, C )

--- constraint: commas
segment: FOO FooThing
    constraint: foo(A B)
    A AN 1/1
==>
_F:2:Constraint syntax is constraint: kind( A, B, C )

--- constraint: >1
segment: FOO FooThing
    constraint: foo( A )
    A   R 1/3
==>
_F:2:Constraint requires at least two elements

--- constraint: existance check
segment: FOO FooThing
    constraint: foo(A, B)

    A   R 1/3
==>
_F:2:No such element B

--- constraint: uniqueness check
segment: FOO FooThing
    constraint: foo(A, A)

    A   R 1/3
==>
_F:2:Duplicate element A

--- constraint: legality check
segment: FOO FooThing
    constraint: foo(A, B)

    A   R 1/3
    B   R 1/3
==>
_F:2:Invalid constraint type foo, must be one of (all_or_none, at_most_one, at_least_one, if_then_all, if_then_one)

#### Elements

--- element: flags
segment: FOO Foo
    A   R 1/3  +bob
==>
_F:2:Invalid flag +bob for element, valid flags are: +required +raw

--- element: short token list
segment: FOO foo
    A   R
==>
_F:2:Element definition must be of the form FriendlyName TYPE MIN/MAX [+flags]

--- element: long token list
segment: FOO foo
    A   R R R
==>
_F:2:Element definition must be of the form FriendlyName TYPE MIN/MAX [+flags]

--- element: +raw for ID only
segment: FOO foo
    A  N 1/3  +raw
==>
_F:2:+raw only permitted for ID

#### Values

--- value: out of place 1
segment: FOO foo
    A  ID 1/3  +raw
        FO: SomeVal
==>
_F:3:Value definitions only permitted for ID-type elements without +raw

--- value: out of place 2
segment: FOO foo
    A  R 1/3
        FO: SomeVal
==>
_F:3:Value definitions only permitted for ID-type elements without +raw

--- value: flags
segment: FOO foo
    A  ID 1/3
        FO: SomeVal +flag
==>
_F:3:Value does not accept flags

--- value: base syntax 1
segment: FOO foo
    A  ID 1/3
        Foo ->
==>
_F:3:Value definition must be of the form SHORT -> LONG

--- value: base syntax 2
segment: FOO foo
    A  ID 1/3
        Foo -> Bar Baz
==>
_F:3:Value definition must be of the form SHORT -> LONG

--- value: base syntax 3
segment: FOO foo
    A  ID 1/3
        Foo -- Bar
==>
_F:3:Value definition must be of the form SHORT -> LONG

--- value: base syntax 4
segment: FOO foo
    A  ID 1/3
        value: Foo -> Bar
==>
_F:3:Value definition must be of the form SHORT -> LONG

--- value: short character set
segment: FOO foo
    A  ID 1/3
        A+ -> Excellent
==>
_F:3:Short value can contain only [0-9A-Z] chars

--- value: duplicate short
segment: FOO foo
    A  ID 1/3
        A -> One
        B -> Two
        A -> Three
==>
_F:5:Duplicate short value A

--- value: duplicate long
segment: FOO foo
    A  ID 1/3
        A -> One
        B -> Two
        C -> One
==>
_F:5:Duplicate long value One

#### Schema

--- schema: flags
schema: +bob
==>
_F:1:Schema does not accept flags

--- schema: odd element
schema: foo
    bob:
==>
_F:2:Child of a loop: or schema: element must be a loop or segment reference

--- schema: malformed segment ref
schema: foo
    FOO
segment: FOO FooThing
    A AN 1/1
==>
_F:2:Segment ref must be of the form CODE HashKey MIN/MAX

--- schema: unresolved segment ref
schema: foo
    FOO FooThing 0/N
==>
_F:2:Code FOO does not correspond to a defined segment

--- schema: malformed loop
schema: foo
    loop: BOB
==>
_F:2:Loop header must be of the form loop: HashKey [01]/ddd or HashKey [01]/N

#### Now let's test some VALID syntax

--- minimal valid
schema: foo
    FOO Foo1 1/1
segment: FOO Foo2
    A AN 1/1
==>
my $FOO = X12::Schema::Segment->new( tag => 'FOO', friendly => 'Foo2', elements => [
    X12::Schema::Element->new( name => 'A', type => 'AN 1/1' )
] );
X12::Schema->new(root => X12::Schema::Sequence->new( required => 1, max_use => 1, name => 'ROOT', children => [
    X12::Schema::SegmentUse->new( def => $FOO, name => 'Foo1', required => 1, max_use => 1 )
] ) );

# this may break if we start verifying that constraints are logically compatible...
--- constraints: all features
schema: foo
    FOO Foo1 1/1
segment: FOO Foo2
    A AN 1/1
    B AN 1/1
    C AN 1/1

    constraint: all_or_none(B, A)
    constraint:   at_most_one  (  A ,B)
    constraint: at_least_one  ( A,B  )  
    constraint: if_then_one(A,B)
    constraint: if_then_all(A,B,C)
==>
my $FOO = X12::Schema::Segment->new( tag => 'FOO', friendly => 'Foo2', elements => [
    X12::Schema::Element->new( name => 'A', type => 'AN 1/1' ),
    X12::Schema::Element->new( name => 'B', type => 'AN 1/1' ),
    X12::Schema::Element->new( name => 'C', type => 'AN 1/1' ),
], constraints => [
    X12::Schema::Constraint->new( all_or_none => [ 'B', 'A' ] ),
    X12::Schema::Constraint->new( at_most_one => [ 'A', 'B' ] ),
    X12::Schema::Constraint->new( at_least_one => [ 'A', 'B' ] ),
    X12::Schema::Constraint->new( if_present => 'A', require_one => [ 'B' ] ),
    X12::Schema::Constraint->new( if_present => 'A', require_all => [ 'B', 'C' ] ),
]);
X12::Schema->new(root => X12::Schema::Sequence->new( required => 1, max_use => 1, name => 'ROOT', children => [
    X12::Schema::SegmentUse->new( def => $FOO, name => 'Foo1', required => 1, max_use => 1 )
] ) );

--- elements: all features
schema: foo
    FOO Foo1 1/1
segment: FOO Foo2
    A AN 1/1
    B AN 1/10 +required
    C ID 2/2
        US -> UnitedStates
        CA -> Canada
    D ID 2/2 +raw
==>
my $FOO = X12::Schema::Segment->new( tag => 'FOO', friendly => 'Foo2', elements => [
    X12::Schema::Element->new( name => 'A', type => 'AN 1/1' ),
    X12::Schema::Element->new( name => 'B', type => 'AN 1/10', required => 1 ),
    X12::Schema::Element->new( name => 'C', type => 'ID 2/2', expand => { US => 'UnitedStates', CA => 'Canada' } ),
    X12::Schema::Element->new( name => 'D', type => 'ID 2/2' ),
] );
X12::Schema->new(root => X12::Schema::Sequence->new( required => 1, max_use => 1, name => 'ROOT', children => [
    X12::Schema::SegmentUse->new( def => $FOO, name => 'Foo1', required => 1, max_use => 1 )
] ) );

--- segments: all features
schema: foo
    FO1 Foo1 1/1
    FO2 Foo2 1/N
    FO3 Foo3 0/1
segment: FO1 Foo
    A AN 1/1
segment: FO2 Foo
    A AN 1/1
segment: FO3 Foo +incomplete
    A AN 1/1
==>
my %S; $S{$_} = X12::Schema::Segment->new( tag => $_, friendly => 'Foo', incomplete => ($_ eq 'FO3' ? 1 : 0), elements => [
    X12::Schema::Element->new( name => 'A', type => 'AN 1/1' )
] ) for qw( FO1 FO2 FO3 );
X12::Schema->new(root => X12::Schema::Sequence->new( required => 1, max_use => 1, name => 'ROOT', children => [
    X12::Schema::SegmentUse->new( def => $S{FO1}, name => 'Foo1', required => 1, max_use => 1 ),
    X12::Schema::SegmentUse->new( def => $S{FO2}, name => 'Foo2', required => 1, max_use => undef ),
    X12::Schema::SegmentUse->new( def => $S{FO3}, name => 'Foo3', required => 0, max_use => 1 )
] ) );

--- again, with loops
segment: FO1 Foo
    A AN 1/1
schema: foo
    loop: L1 1/1
        FO1 Foo1 1/1
    loop: L2 1/N
        FO2 Foo2 1/1
    loop: L3 0/1
        FO3 Foo3 1/1
segment: FO2 Foo
    A AN 1/1
segment: FO3 Foo
    A AN 1/1
==>
my %S; $S{$_} = X12::Schema::Segment->new( tag => $_, friendly => 'Foo', elements => [
    X12::Schema::Element->new( name => 'A', type => 'AN 1/1' )
] ) for qw( FO1 FO2 FO3 );
X12::Schema->new(root => X12::Schema::Sequence->new( required => 1, max_use => 1, name => 'ROOT', children => [
    X12::Schema::Sequence->new( required => 1, max_use => 1, name => 'L1', children => [
        X12::Schema::SegmentUse->new( def => $S{FO1}, name => 'Foo1', required => 1, max_use => 1 ) ]),
    X12::Schema::Sequence->new( required => 1, max_use => undef, name => 'L2', children => [
        X12::Schema::SegmentUse->new( def => $S{FO2}, name => 'Foo2', required => 1, max_use => 1 ) ]),
    X12::Schema::Sequence->new( required => '', max_use => 1, name => 'L3', children => [
        X12::Schema::SegmentUse->new( def => $S{FO3}, name => 'Foo3', required => 1, max_use => 1 ) ]),
] ) );
