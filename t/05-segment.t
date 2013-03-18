use strict;
use warnings;
use Test::More tests => 15;
use Test::Exception;

use X12::Schema::Element;
BEGIN { use_ok('X12::Schema::Segment') or die }
use X12::Schema::TokenSink;

# TODO: constraints will be redesigned for the parser, so don't test those

my $sink = X12::Schema::TokenSink->new( element_sep => '*', segment_term => '~', component_sep => ':' );

my $seg;


$seg = new_ok 'X12::Schema::Segment', [ tag => 'FOO', friendly => 'Foo', elements => [
    X12::Schema::Element->new( name => 'A', type => 'AN 5/5'),
    X12::Schema::Element->new( name => 'B', type => 'AN 5/5'),
] ], 'create, optional fields';

throws_ok { $seg->encode($sink, undef) } qr/using a HASH/;
throws_ok { $seg->encode($sink, 5) } qr/using a HASH/;
throws_ok { $seg->encode($sink, []) } qr/using a HASH/;
throws_ok { $seg->encode($sink, { C => 2 }) } qr/Excess fields/;
throws_ok { $seg->encode($sink, {  }) } qr/must contain data/;

$sink->output('');
lives_ok { $seg->encode($sink, { A => 'cow' }) } 'partial encode with suppressed sep lives';
is $sink->output, 'FOO*cow  ~', 'partial encode with suppressed sep right result';

$sink->output('');
lives_ok { $seg->encode($sink, { B => 'dog' }) } 'partial encode without suppressed sep lives';
is $sink->output, 'FOO**dog  ~', 'partial encode without suppressed sep right result';


$seg = new_ok 'X12::Schema::Segment', [ tag => 'FOO', friendly => 'Foo', elements => [
    X12::Schema::Element->new( name => 'A', type => 'AN 5/5', required => 1 ),
    X12::Schema::Element->new( name => 'B', type => 'AN 5/5', required => 1 ),
] ], 'create, required fields';

throws_ok { $seg->encode($sink, { A => 'cow' }) } qr/B is required/;

$sink->output('');
lives_ok { $seg->encode($sink, { A => 'cow', B => 'dog' }) } 'encode with required fields';
is $sink->output, 'FOO*cow  *dog  ~', '... right result';

