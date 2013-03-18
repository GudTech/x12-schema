use strict;
use warnings;
use Test::More tests => 28;
use Test::Exception;

use X12::Schema::Element;
BEGIN { use_ok('X12::Schema::Segment') or die }
use X12::Schema::TokenSink;
use X12::Schema::TokenSource;

# TODO: constraints will be redesigned for the parser, so don't test those

my $sink = X12::Schema::TokenSink->new( element_sep => '*', segment_term => '~', component_sep => ':' );

my $seg;
my $src;

sub decode {
    $src = X12::Schema::TokenSource->new( buffer => $_[0] );
    $src->set_delims('/', '^', '*', '~', '');

    return $seg->decode($src);
}

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


throws_ok { decode('FOO^X~') } qr/Malformed segment tag/;
throws_ok { decode('FOO/X~') } qr/Malformed segment tag/;
throws_ok { decode('FOO~') } qr/Segment with nothing but a terminator/;
throws_ok { decode('FOO*X^X~') } qr/unsupported/;
throws_ok { decode('FOO*X/X~') } qr/unsupported/;
throws_ok { decode('FOO*ABCD~') } qr/too_short/;
throws_ok { decode('FOO*ABCDE*~') } qr/trailing empty/;
throws_ok { decode('FOO*ABCDE*FGHIJ*KLMNO~') } qr/Too many/;

is_deeply decode('FOO**ABCDE~'), { A => undef, B => 'ABCDE' }, 'correct optional parse 1';
is_deeply decode('FOO*ABCDE~'), { B => undef, A => 'ABCDE' }, 'correct optional parse 2';

$seg = new_ok 'X12::Schema::Segment', [ tag => 'FOO', friendly => 'Foo', elements => [
    X12::Schema::Element->new( name => 'A', type => 'AN 5/5', required => 1 ),
    X12::Schema::Element->new( name => 'B', type => 'AN 5/5', required => 1 ),
] ], 'create, required fields';

throws_ok { $seg->encode($sink, { A => 'cow' }) } qr/B is required/;

$sink->output('');
lives_ok { $seg->encode($sink, { A => 'cow', B => 'dog' }) } 'encode with required fields';
is $sink->output, 'FOO*cow  *dog  ~', '... right result';

throws_ok { decode('FOO*ABCDE~') } qr/Required/;
throws_ok { decode('FOO**ABCDE~') } qr/Required/;
is_deeply decode('FOO*ABCDE*FGHIJ~'), { B => 'FGHIJ', A => 'ABCDE' }, 'correct mandatory parse';

