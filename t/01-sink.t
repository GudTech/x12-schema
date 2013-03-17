use strict;
use warnings;
use Test::More tests => 28;
use Test::Exception;

BEGIN { use_ok "X12::Schema::TokenSink"; }

my %args = qw( segment_term s element_sep e repeat_sep r component_sep c );

for my $t (qw( segment_term element_sep component_sep )) {
    local $args{$t}; delete $args{$t};  # delete local is a 5.12ism
    throws_ok { X12::Schema::TokenSink->new( %args ) } qr/$t.*required/, "$t is required";
}

for my $t (sort keys %args) {
    local $args{$t};
    $args{$t} = 'aa';
    throws_ok { X12::Schema::TokenSink->new( %args ) } qr/$t must be a single character/;
    $args{$t} = "a\n";
    throws_ok { X12::Schema::TokenSink->new( %args ) } qr/$t must be a single character/, "$t cannot include a suffix"
        unless $t eq 'segment_term';
}

{
    local $args{segment_term} = "a\n\r";
    throws_ok { X12::Schema::TokenSink->new( %args ) } qr/segment_term must be a single character, optionally followed by CR and\/or LF/, "weird suffix forbidden";
}

{
    local $args{segment_term} = "e";
    throws_ok { X12::Schema::TokenSink->new( %args ) } qr/all delimiters must be unique/;
}

$args{segment_term} = "a\r\n";

my $baseline = new_ok 'X12::Schema::TokenSink', [%args], 'new without output_func';

my $re = $baseline->delim_re;
for my $d (sort keys %args) {
    ok $args{$d} =~ /$re/, "delimiter regex matches ($d)";
}

ok "\r" !~ /$re/, "delimiter regex ignores suffix";

is $baseline->output, '', 'output initially empty';

$baseline->segment('foo');
is $baseline->output, 'foo', 'first output recorded';

$baseline->segment('bar');
is $baseline->output, 'foobar', 'subseq output recorded';

my $ext = '';

$baseline = new_ok 'X12::Schema::TokenSink', [%args, output_func => sub { $ext .= $_[0] }], 'new with output_func';

is $ext, '', 'external output initially empty';
is $baseline->segment_counter, 0, 'ctr initially 0';

$baseline->segment('foo');
is $ext, 'foo', 'first external output recorded';

$baseline->segment('bar');
is $ext, 'foobar', 'subseq external output recorded';
is $baseline->segment_counter, 2, 'ctr records segments';
