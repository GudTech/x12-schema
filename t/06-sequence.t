use strict;
use warnings;
use Test::More tests => 25;
use Test::Exception;

use X12::Schema::Element;
use X12::Schema::Segment;
use X12::Schema::SegmentUse;
use X12::Schema::TokenSink;
use X12::Schema::TokenSource;
BEGIN { use_ok('X12::Schema::Sequence') or die }

my $sink = X12::Schema::TokenSink->new( component_sep => '/', element_sep => '*', segment_term => '~' );

my $source;

sub mksource {
    $source = X12::Schema::TokenSource->new(buffer => $_[0]);
    $source->set_delims('/',undef,'*','~','');
}

sub mksegment {
    my $name = shift;
    return X12::Schema::SegmentUse->new(
        name => $name, @_,
        def => X12::Schema::Segment->new( tag => $name, friendly => $name, elements => [
            X12::Schema::Element->new( name => 'X', type => 'AN 1/1' )
        ] )
    );
}

sub outtest {
    my ($sg, $data, $expect, $name) = @_;

    $sink->output('');
    if (ref($expect)) {
        throws_ok { $sg->encode($sink, $data) } $expect, $name;
    } else {
        lives_ok { $sg->encode($sink, $data) } "$name (1)";
        is $sink->output, $expect, "$name (2)";
    }
}

sub intest {
    my ($sg, $data, $expect, $name) = @_;

    mksource($data);
    if (ref($expect) eq 'Regexp') {
        throws_ok { $sg->decode($source, {END=>1}) } $expect, $name;
    } else {
        my $out;
        lives_ok { $out=$sg->decode($source, {END=>1}) } "$name (1)";
        is_deeply $out, $expect, "$name (2)";
    }
}


my $seq1 = X12::Schema::Sequence->new(
    name => 'ROOT',
    children => [
        mksegment('AAA'),
        mksegment('BBB', required => 1),
        mksegment('CCC', max_use => 5),
        mksegment('DDD', max_use => undef, required => 1),
    ]
);

outtest $seq1, undef, qr/encode a HASH/, 'HASH required (1)';
outtest $seq1, 22, qr/encode a HASH/, 'HASH required (2)';
outtest $seq1, [], qr/encode a HASH/, 'HASH required (3)';

outtest $seq1, {}, qr/Segment or loop BBB is required/, 'Requirement check, nonrep';
outtest $seq1, { BBB => {X=>1} }, qr/Segment or loop DDD is required/, 'Requirement check, rep';
outtest $seq1, { BBB => {X=>1}, DDD => [{X=>2},{X=>3}] }, 'BBB*1~DDD*2~DDD*3~', 'Requirement check, satisfied';
outtest $seq1, { BBB => {X=>1}, DDD => [{X=>2},{X=>3}], AAA => {X=>0} }, 'AAA*0~BBB*1~DDD*2~DDD*3~', 'With optional';

outtest $seq1, { BBB => {X=>1}, DDD => [{X=>2},{X=>3}], CCC => [({X=>4}) x 9] }, qr/Segment or loop CCC is limited to 5 uses/, 'max_use checking';
outtest $seq1, { BBB => {X=>1}, DDD => [{X=>2},{X=>3}], CCC => [({X=>4}) x 4] }, 'BBB*1~CCC*4~CCC*4~CCC*4~CCC*4~DDD*2~DDD*3~', 'max_use met';
outtest $seq1, { BBB => {X=>1}, DDD => [{X=>2},{X=>3}], CCC => {X=>4} }, qr/Replicated.*must encode/, 'repeat requires ARRAY';


intest $seq1, '', qr/BBB is required at 1/, 'input requirement checking, nonrep';
intest $seq1, 'BBB*1~', qr/DDD is required at 2/, 'input requirement checking, rep';
intest $seq1, 'BBB*9~DDD*8~', { BBB => {X=>9}, DDD => [{X=>8}], CCC => [] }, 'minimal input';
intest $seq1, 'DDD*8~BBB*9~', qr/Unexpected segment at 1/, 'order sensitivity';
intest $seq1, 'XXX*8~BBB*9~', qr/Unexpected segment at 1/, 'unexpected segment';
intest $seq1, 'AAA*1~BBB*9~DDD*8~', { AAA => {X=>1}, BBB => {X=>9}, DDD => [{X=>8}], CCC => [] }, 'input with optional';
intest $seq1, 'BBB*9~CCC*1~CCC*2~DDD*8~', { BBB => {X=>9}, DDD => [{X=>8}], CCC => [{X=>1},{X=>2}] }, 'input with Cs';
intest $seq1, 'BBB*9~CCC*1~CCC*2~CCC*1~CCC*2~CCC*1~CCC*2~DDD*8~', qr/CCC exceeds 5 occurrences at 7/, 'input with too many Cs';
